# Root main.tf — this is the file customers/callers actually edit values
# for (via the YAML manifest in config/). All logic lives in
# modules/memorystore-valkey/; this just wires inputs through.

module "valkey" {
  source = "./modules/valkey" # Replace with actual module source
  #version  = "1.0.0"            # Pin to the module version you're using
  for_each = local.enabled_configs

  # --- Deployment Topology & DR ---  
  deployment_topology = each.value.deployment_topology
  secondary_location  = each.value.secondary_location


  project_id  = each.value.project_id
  environment = each.value.environment
  instance_id = each.value.instance_id

  # --- Region / Zone ---
  location               = each.value.location
  zone_distribution_mode = each.value.zone_distribution_mode
  zone                   = each.value.zone
  secondary_zone         = each.value.secondary_zone

  # --- Cluster Topology & Sizing ---
  cluster_mode  = each.value.cluster_mode
  node_type     = each.value.node_type
  shard_count   = each.value.shard_count
  replica_count = each.value.replica_count

  # --- PSC Connectivity ---
  psc_connectivity_mode   = each.value.psc_connectivity_mode
  shared_vpc_host_project = each.value.shared_vpc_host_project
  shared_vpc_network_name = each.value.shared_vpc_network_name

  # --- Authorization & TLS ---
  authorization_mode      = each.value.authorization_mode
  transit_encryption_mode = each.value.transit_encryption_mode

  # --- Certificate Authority ---
  server_ca_mode = each.value.server_ca_mode
  server_ca_pool = each.value.server_ca_pool

  # --- Encryption at Rest ---
  encryption_type = each.value.encryption_type
  kms_key         = each.value.kms_key

  # --- Persistence ---
  persistence_mode        = each.value.persistence_mode
  rdb_snapshot_period     = each.value.rdb_snapshot_period
  rdb_snapshot_start_time = each.value.rdb_snapshot_start_time
  aof_config              = each.value.aof_config

  # --- Automated Backups ---
  automated_backup_enabled         = each.value.automated_backup_enabled
  automated_backup_start_time_hour = each.value.automated_backup_start_time_hour
  automated_backup_retention_days  = each.value.automated_backup_retention_days

  # --- Maintenance Window ---
  maintenance_day        = each.value.maintenance_day
  maintenance_start_hour = each.value.maintenance_start_hour

  # --- Engine ---
  engine_version = each.value.engine_version

  # --- Engine Configuration Parameters ---
  maxmemory_policy        = each.value.maxmemory_policy
  notify_keyspace_events  = each.value.notify_keyspace_events
  maxmemory_clients       = each.value.maxmemory_clients
  slowlog_log_slower_than = each.value.slowlog_log_slower_than
  maxclients              = each.value.maxclients

  # --- Deletion Protection & Labels --- 
  deletion_protection_enabled = each.value.deletion_protection_enabled
  labels                      = each.value.labels
}

# --- Alerts, per instance (optional) ---
# Uncomment to wire up modules/valkey-alerts for every enabled instance.
# Fixed vs. the earlier draft: service_project_id/service_team_* renamed
# to requester_* (the alerts module's data-plane-connect design changed —
# see its README), memory_warning/critical_threshold added,
# rejected_connections split into warning/critical, replica_count and the
# two log-based-alert toggles added. Uses variables that don't exist yet
# in variables.tf — add them (or hardcode per-manifest values under
# each.value, same pattern as module.valkey above) before uncommenting.
#
# module "valkey_alerts" {
#   source   = "./modules/valkey-alerts"
#   for_each = local.enabled_configs
#
#   project_id    = each.value.project_id
#   instance_id   = module.valkey[each.key].instance_id
#   region        = each.value.location
#   replica_count = each.value.replica_count
#
#   requester_critical_emails = var.requester_critical_emails
#   requester_warning_emails  = var.requester_warning_emails
#   platform_critical_emails  = var.platform_critical_emails
#   platform_warning_emails   = var.platform_warning_emails
#
#   cpu_warning_threshold                   = var.cpu_warning_threshold
#   cpu_critical_threshold                  = var.cpu_critical_threshold
#   memory_warning_threshold                = var.memory_warning_threshold
#   memory_critical_threshold               = var.memory_critical_threshold
#   rejected_connections_warning_threshold  = var.rejected_connections_warning_threshold
#   rejected_connections_critical_threshold = var.rejected_connections_critical_threshold
#   connected_clients_warning_threshold     = var.connected_clients_warning_threshold
#   replication_lag_warning_bytes           = var.replication_lag_warning_bytes
#
#   enable_admin_activity_alerts = true
#   enable_system_event_alerts   = true
# }
