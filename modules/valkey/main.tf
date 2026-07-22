############################################
# Memorystore for Valkey — primary instance
#
# Lives in var.project_id. Network connectivity is controlled by
# var.psc_connectivity_mode:
#   NONE        — no endpoint block; nothing can reach the instance over
#                 PSC until wired up some other way, outside this module.
#   SHARED_VPC  — points the instance at an already-existing Shared VPC
#                 network + Service Connection Policy (both created
#                 outside this module — see data.tf and the
#                 shared_vpc_* / existing_scp_name variables). Memorystore
#                 auto-creates the PSC endpoint itself; no second apply.
#
# Topology: var.deployment_topology (STANDALONE / HA / DR) is a
# self-documenting label validated for consistency against
# replica_count / enable_cross_region_replication (see the check block in
# variables.tf) — it does not silently override those variables. This
# keeps the module's actual behavior fully explained by its explicit
# variables, while still giving callers/customers a single clear knob to
# talk about ("we want DR") that maps to a validated combination.
############################################

resource "google_memorystore_instance" "primary-instance" {

  # --- Identity ---
  project     = var.project_id
  instance_id = var.instance_id

  # --- Region and zonal availability ---
  location = var.location

  zone_distribution_config {
    mode = var.zone_distribution_mode
    zone = local.effective_zone
  }

  # --- Cluster mode (Enabled/Disabled) ---
  mode = var.cluster_mode

  # --- Size / topology ---
  node_type     = var.node_type
  shard_count   = var.shard_count
  replica_count = var.replica_count

  # --- Cross-region replication role ---
  # NONE for STANDALONE/HA.
  # --- Network endpoint (AUTO mode only) ---
  # In USER mode, the instance is created with NO endpoint block at all.
  # The connection is created and registered afterward via the separate
  # google_memorystore_instance_desired_user_created_endpoints resource
  # in psc_network.tf, once the instance (and its service attachments)
  # exist. See README.md for the two-phase apply this requires.
  dynamic "desired_auto_created_endpoints" {
    for_each = var.psc_connectivity_mode == "SHARED_VPC" ? [1] : []
    content {
      network    = local.effective_psc_network_id
      project_id = var.project_id
    }
  }

  # --- Authorization (AUTH) & TLS ---
  authorization_mode      = var.authorization_mode
  transit_encryption_mode = var.transit_encryption_mode

  # --- Certificate Authority management ---
  server_ca_mode = var.server_ca_mode
  server_ca_pool = var.server_ca_mode == "CUSTOMER_MANAGED_CAS_CA" ? var.server_ca_pool : null

  # --- Encryption at rest (CMEK) ---
  kms_key = var.encryption_type == "CUSTOMER_MANAGED" ? var.kms_key : null

  # --- Persistence (RDB / AOF / disabled) ---
  persistence_config {
    mode = var.persistence_mode

    dynamic "rdb_config" {
      for_each = var.persistence_mode == "RDB" ? [1] : []
      content {
        rdb_snapshot_period     = var.rdb_snapshot_period
        rdb_snapshot_start_time = var.rdb_snapshot_start_time
      }
    }

    dynamic "aof_config" {
      for_each = var.persistence_mode == "AOF" ? [1] : []
      content {
        append_fsync = var.aof_config.append_fsync
      }
    }
  }

  # --- Automated backups (separate from persistence — GCS-backed collection) ---
  dynamic "automated_backup_config" {
    for_each = var.automated_backup_enabled ? [1] : []
    content {
      fixed_frequency_schedule {
        start_time {
          hours = var.automated_backup_start_time_hour
        }
      }
      retention = "${var.automated_backup_retention_days * 86400}s"
    }
  }

  # --- Maintenance window ---
  maintenance_policy {
    weekly_maintenance_window {
      day = var.maintenance_day
      start_time {
        hours   = var.maintenance_start_hour
        minutes = 0
        seconds = 0
        nanos   = 0
      }
    }
  }

  # --- Engine version & configuration parameters ---
  engine_version = var.engine_version

  engine_configs = merge(
    {
      "maxmemory-policy"       = var.maxmemory_policy
      "notify-keyspace-events" = var.notify_keyspace_events
    },
    var.maxmemory_clients != null ? { "maxmemory-clients" = var.maxmemory_clients } : {},
    var.slowlog_log_slower_than != null ? { "slowlog-log-slower-than" = tostring(var.slowlog_log_slower_than) } : {},
    var.maxclients != null ? { "maxclients" = tostring(var.maxclients) } : {}
  )

  # --- Deletion protection ---
  # This is the real, API-enforced guard (blocks delete via console/gcloud/
  # API too, not just `terraform destroy`). lifecycle.prevent_destroy is
  # intentionally NOT used here — it cannot reference variables (must be a
  # literal bool), which would defeat the point of a reusable module.
  deletion_protection_enabled = var.deletion_protection_enabled

  lifecycle {
    precondition {
      condition     = local.valid_location
      error_message = "location '${var.location}' is not available for project '${var.project_id}'."
    }

    precondition {
      condition     = local.valid_zone_for_single_zone_mode
      error_message = "Could not resolve a valid zone for SINGLE_ZONE mode in region '${var.location}' for project '${var.project_id}'. Either no zones are available, or the supplied zone '${var.zone_distribution_mode}' is invalid."
    }

    precondition {
      condition     = local.valid_shard_count_for_cluster_mode
      error_message = "shard_count must be 1 when cluster_mode is 'CLUSTER_DISABLED'; Cluster Mode Disabled instances only support a single shard."
    }

    precondition {
      condition     = local.valid_node_type_for_prod
      error_message = "SHARED_CORE_NANO has no SLA and is not recommended for production. Use STANDARD_SMALL, HIGHMEM_MEDIUM, or HIGHMEM_XLARGE for environment = 'PROD'."
    }

    precondition {
      condition     = local.valid_custom_node_type_requires_cluster_disabled
      error_message = "node_type '${var.node_type}' (CUSTOM_PICO/CUSTOM_MICRO/CUSTOM_MINI) is only available for Cluster Mode Disabled instances. Set cluster_mode = 'CLUSTER_DISABLED', or choose a different node_type for cluster_mode = 'CLUSTER'."
    }

    precondition {
      condition     = local.valid_iam_auth_requires_tls
      error_message = "IAM_AUTH sends the AUTH token unencrypted unless in-transit encryption is enabled. Set transit_encryption_mode = 'SERVER_AUTHENTICATION' when using authorization_mode = 'IAM_AUTH'."
    }
  }
}

############################################
# Memorystore for Valkey — secondary instance (DR only)
#
# Created only when var.enable_cross_region_replication = true. Mirrors
# the primary's engine/persistence/auth/TLS settings — cross-instance
# replication does not support mismatched configuration between the two.
# This resource has its own full PSC networking stack in
# psc_network.tf (everything suffixed _secondary), since PSC connections
# are strictly regional and the secondary lives in a different region.
############################################

resource "google_memorystore_instance" "secondary" {
  count = var.enable_cross_region_replication ? 1 : 0

  project     = var.project_id
  instance_id = "${var.instance_id}-dr"
  location    = var.secondary_location

  zone_distribution_config {
    mode = var.zone_distribution_mode
    zone = local.effective_secondary_zone
  }

  mode          = var.cluster_mode
  node_type     = var.node_type
  shard_count   = var.shard_count
  replica_count = var.replica_count

  cross_instance_replication_config {
    instance_role = "SECONDARY"
    primary_instance {
      instance = google_memorystore_instance.primary-instance.id
    }
  }
  dynamic "desired_auto_created_endpoints" {
    for_each = var.psc_connectivity_mode == "SHARED_VPC" ? [1] : []
    content {
      network    = local.effective_psc_network_id
      project_id = var.project_id
    }
  }
  # Must match the primary — cross-instance replication requires
  # consistent auth/TLS/CA/engine settings between the two.
  authorization_mode      = var.authorization_mode
  transit_encryption_mode = var.transit_encryption_mode
  server_ca_mode          = var.server_ca_mode
  server_ca_pool          = var.server_ca_mode == "CUSTOMER_MANAGED_CAS_CA" ? var.server_ca_pool : null
  kms_key                 = var.encryption_type == "CUSTOMER_MANAGED" ? var.kms_key : null
  engine_version          = var.engine_version
  engine_configs = merge(
    {
      "maxmemory-policy"       = var.maxmemory_policy
      "notify-keyspace-events" = var.notify_keyspace_events
    },
    var.maxmemory_clients != null ? { "maxmemory-clients" = var.maxmemory_clients } : {},
    var.slowlog_log_slower_than != null ? { "slowlog-log-slower-than" = tostring(var.slowlog_log_slower_than) } : {},
    var.maxclients != null ? { "maxclients" = tostring(var.maxclients) } : {}
  )

  persistence_config {
    mode = var.persistence_mode

    dynamic "rdb_config" {
      for_each = var.persistence_mode == "RDB" ? [1] : []
      content {
        rdb_snapshot_period     = var.rdb_snapshot_period
        rdb_snapshot_start_time = var.rdb_snapshot_start_time
      }
    }

    dynamic "aof_config" {
      for_each = var.persistence_mode == "AOF" ? [1] : []
      content {
        append_fsync = var.aof_config.append_fsync
      }
    }
  }

  maintenance_policy {
    weekly_maintenance_window {
      day = var.maintenance_day
      start_time {
        hours   = var.maintenance_start_hour
        minutes = 0
        seconds = 0
        nanos   = 0
      }
    }
  }

  deletion_protection_enabled = var.deletion_protection_enabled

  lifecycle {
    precondition {
      condition     = local.valid_secondary_location
      error_message = "secondary_location '${var.secondary_location}' is not available for project '${var.project_id}'."
    }
  }
}
