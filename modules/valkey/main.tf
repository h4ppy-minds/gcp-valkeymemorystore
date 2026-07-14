############################################
# Memorystore for Valkey — primary instance
#
# Lives in var.project_id (the "host" project). Network connectivity is
# handled entirely in psc_network.tf: see that file for how AUTO vs USER
# mode differ, and which project each network resource lands in.
############################################

resource "google_memorystore_instance" "shared-instance" {

  # --- Identity ---
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

  # --- Network endpoint (AUTO mode only) ---
  # In USER mode, the instance is created with NO endpoint block at all.
  # The connection is created and registered afterward via the separate
  # google_memorystore_instance_desired_user_created_endpoints resource
  # in psc_network.tf, once the instance (and its service attachment)
  # exists. See psc_network.tf and README.md for the two-phase apply
  # this requires in USER mode.
  dynamic "desired_auto_created_endpoints" {
    for_each = var.psc_connectivity_mode == "AUTO" ? [1] : []
    content {
      network    = google_compute_network.auto_producer_net[0].id
      project_id = local.effective_consumer_project_id
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
  deletion_protection_enabled = var.deletion_protection_enabled

  # Service connection policy only exists in AUTO mode (count 0 or 1) —
  # referencing the resource without an index is safe either way.
  depends_on = [
    google_network_connectivity_service_connection_policy.auto_policy,
  ]

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
