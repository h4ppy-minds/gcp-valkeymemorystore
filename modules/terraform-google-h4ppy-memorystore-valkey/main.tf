############################################
# Memorystore for Valkey instance(s): primary + optional DR secondary.
#
# Primary and secondary are both google_memorystore_instance, but NOT
# expressed as one resource with for_each/count over a shared shape:
# they aren't symmetric — different location, and the secondary's
# cross_instance_replication_config points at the primary's id, which
# only exists once the primary is created. Two explicit resource blocks
# keeps that dependency simple and avoids a same-resource self-reference.
#
# This module intentionally has no submodules — everything a registry
# consumer needs to read is in this root path. The two blocks below
# necessarily repeat most of their arguments; that repetition is the
# tradeoff for a flat, single-directory registry module instead of a
# shared internal module. If that duplication becomes painful, the fix
# is a for_each over a locals-built map, not a nested module directory.
#
# Network connectivity is controlled by local.psc_connectivity_mode:
#   NONE        — no endpoint block; nothing can reach the instance over
#                 PSC until wired up some other way, outside this module.
#   SHARED_VPC  — points the instance at an already-existing Shared VPC
#                 network + Service Connection Policy (both created
#                 outside this module — see data.tf and the
#                 shared_vpc_* / existing_scp_name variables). Memorystore
#                 auto-creates the PSC endpoint itself; no second apply.
#
# Topology: local.deployment_topology (STANDALONE / HA / DR) is the
# single source of truth — local.enable_cross_region_replication
# (all-locals.tf) is derived from it, not a separate variable.
#
# NOTE on alerting: Cloud Monitoring alert policies and email
# notification channels for this instance are NOT created here anymore.
# That's a separate module — see terraform-google-valkey-alerts — so
# that changing who gets notified (an email address) never has to touch,
# or run a plan against, this instance's infrastructure. Wire it up
# against this module's `instance_id` / `resolved_location` outputs.
############################################

resource "google_memorystore_instance" "primary" {
  # --- Identity ---
  project     = var.project_id
  instance_id = local.instance_id

  # --- Region and zonal availability ---
  location = local.location

  zone_distribution_config {
    mode = local.zone_distribution_mode
    zone = local.effective_zone
  }

  # --- Cluster mode (Enabled/Disabled) ---
  mode = local.cluster_mode

  # --- Size / topology ---
  node_type     = local.node_type
  shard_count   = var.shard_count
  replica_count = local.replica_count

  # The primary never declares a replication role itself — confirmed via
  # a real apply error: "Invalid cross instance replication role
  # PRIMARY. Allowed value is: SECONDARY". It becomes PRIMARY implicitly
  # once a secondary's cross_instance_replication_config.primary_instance
  # points at it (below), so no cross_instance_replication_config block
  # is ever set here.

  # --- Network endpoint (SHARED_VPC mode only) ---
  dynamic "desired_auto_created_endpoints" {
    for_each = local.psc_connectivity_mode == "SHARED_VPC" ? [1] : []
    content {
      network    = local.effective_psc_network_id
      project_id = var.project_id
    }
  }

  # --- Authorization (AUTH) & TLS ---
  authorization_mode      = local.authorization_mode
  transit_encryption_mode = local.transit_encryption_mode

  # --- Certificate Authority management ---
  server_ca_mode = local.server_ca_mode
  server_ca_pool = local.server_ca_mode == "CUSTOMER_MANAGED_CAS_CA" ? var.server_ca_pool : null

  # --- Encryption at rest (CMEK) ---
  kms_key = local.encryption_type == "CUSTOMER_MANAGED" ? var.kms_key : null

  # --- Persistence (RDB / AOF / disabled) ---
  persistence_config {
    mode = local.persistence_mode

    dynamic "rdb_config" {
      for_each = local.persistence_mode == "RDB" ? [1] : []
      content {
        rdb_snapshot_period     = var.rdb_snapshot_period
        rdb_snapshot_start_time = var.rdb_snapshot_start_time
      }
    }

    dynamic "aof_config" {
      for_each = local.persistence_mode == "AOF" ? [1] : []
      content {
        append_fsync = var.aof_config.append_fsync
      }
    }
  }

  # --- Automated backups (separate from persistence — GCS-backed collection) ---
  dynamic "automated_backup_config" {
    for_each = local.automated_backup_enabled ? [1] : []
    content {
      fixed_frequency_schedule {
        start_time {
          hours = local.automated_backup_start_time_hour
        }
      }
      retention = "${local.automated_backup_retention_days * 86400}s"
    }
  }

  # --- Maintenance window ---
  maintenance_policy {
    weekly_maintenance_window {
      day = local.maintenance_day
      start_time {
        hours   = local.maintenance_start_hour
        minutes = 0
        seconds = 0
        nanos   = 0
      }
    }
  }

  # --- Engine version & configuration parameters ---
  engine_version = local.engine_version

  engine_configs = merge(
    {
      "maxmemory-policy"       = local.maxmemory_policy
      "notify-keyspace-events" = local.notify_keyspace_events
    },
    var.maxmemory_clients != null ? { "maxmemory-clients" = var.maxmemory_clients } : {},
    local.slowlog_log_slower_than != null ? { "slowlog-log-slower-than" = tostring(local.slowlog_log_slower_than) } : {},
    var.maxclients != null ? { "maxclients" = tostring(var.maxclients) } : {}
  )

  # --- Deletion protection ---
  # This is the real, API-enforced guard (blocks delete via console/gcloud/
  # API too, not just `terraform destroy`).
  deletion_protection_enabled = local.deletion_protection_enabled

  labels = local.labels

  lifecycle {
    precondition {
      condition     = local.valid_location
      error_message = "location '${local.location}' is not available for project '${var.project_id}'."
    }

    precondition {
      condition     = local.valid_zone_for_single_zone_mode
      error_message = "Could not resolve a valid zone for SINGLE_ZONE mode in region '${local.location}' for project '${var.project_id}'."
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
      error_message = "node_type '${local.node_type}' (CUSTOM_PICO/CUSTOM_MICRO/CUSTOM_MINI) is only available for Cluster Mode Disabled instances. Set cluster_mode = 'CLUSTER_DISABLED', or choose a different node_type for cluster_mode = 'CLUSTER'."
    }

    precondition {
      condition     = local.valid_iam_auth_requires_tls
      error_message = "IAM_AUTH sends the AUTH token unencrypted unless in-transit encryption is enabled. Set transit_encryption_mode = 'SERVER_AUTHENTICATION' when using authorization_mode = 'IAM_AUTH'."
    }
  }
}

resource "google_memorystore_instance" "secondary" {
  count = local.enable_cross_region_replication ? 1 : 0

  # --- Identity ---
  project     = var.project_id
  instance_id = "${local.instance_id}-dr"

  # --- Region and zonal availability ---
  location = var.secondary_location

  zone_distribution_config {
    mode = local.zone_distribution_mode
    zone = local.effective_secondary_zone
  }

  # --- Cluster mode (Enabled/Disabled) ---
  mode = local.cluster_mode

  # --- Size / topology ---
  node_type     = local.node_type
  shard_count   = var.shard_count
  replica_count = local.replica_count

  cross_instance_replication_config {
    instance_role = "SECONDARY"
    primary_instance {
      instance = google_memorystore_instance.primary.id
    }
  }

  # --- Network endpoint (SHARED_VPC mode only) ---
  dynamic "desired_auto_created_endpoints" {
    for_each = local.psc_connectivity_mode == "SHARED_VPC" ? [1] : []
    content {
      network    = local.effective_psc_network_id
      project_id = var.project_id
    }
  }

  # --- Authorization (AUTH) & TLS — must match the primary; cross-instance
  # replication requires consistent auth/TLS/CA/engine settings. ---
  authorization_mode      = local.authorization_mode
  transit_encryption_mode = local.transit_encryption_mode

  server_ca_mode = local.server_ca_mode
  server_ca_pool = local.server_ca_mode == "CUSTOMER_MANAGED_CAS_CA" ? var.server_ca_pool : null

  kms_key = local.encryption_type == "CUSTOMER_MANAGED" ? var.kms_key : null

  # --- Persistence (RDB / AOF / disabled) ---
  persistence_config {
    mode = local.persistence_mode

    dynamic "rdb_config" {
      for_each = local.persistence_mode == "RDB" ? [1] : []
      content {
        rdb_snapshot_period     = var.rdb_snapshot_period
        rdb_snapshot_start_time = var.rdb_snapshot_start_time
      }
    }

    dynamic "aof_config" {
      for_each = local.persistence_mode == "AOF" ? [1] : []
      content {
        append_fsync = var.aof_config.append_fsync
      }
    }
  }

  # Preserved as-is from the original design: the secondary never gets
  # automated_backup_config, regardless of local.automated_backup_enabled.
  # Flagged in the README as worth deciding explicitly rather than
  # carrying forward silently.

  # --- Maintenance window ---
  maintenance_policy {
    weekly_maintenance_window {
      day = local.maintenance_day
      start_time {
        hours   = local.maintenance_start_hour
        minutes = 0
        seconds = 0
        nanos   = 0
      }
    }
  }

  # --- Engine version & configuration parameters ---
  engine_version = local.engine_version

  engine_configs = merge(
    {
      "maxmemory-policy"       = local.maxmemory_policy
      "notify-keyspace-events" = local.notify_keyspace_events
    },
    var.maxmemory_clients != null ? { "maxmemory-clients" = var.maxmemory_clients } : {},
    local.slowlog_log_slower_than != null ? { "slowlog-log-slower-than" = tostring(local.slowlog_log_slower_than) } : {},
    var.maxclients != null ? { "maxclients" = tostring(var.maxclients) } : {}
  )

  deletion_protection_enabled = local.deletion_protection_enabled

  labels = local.labels

  lifecycle {
    # Only the secondary's own location gets (re-)checked here —
    # shard_count/node_type/cluster_mode/authorization_mode are the exact
    # same effective values the primary already validated above.
    precondition {
      condition     = local.valid_secondary_location
      error_message = "secondary_location '${var.secondary_location}' is not available for project '${var.project_id}'."
    }
  }
}
