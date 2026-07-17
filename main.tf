
# Root main.tf — this is the file customers/callers actually edit values
# for (via a tfvars file). All logic lives in modules/valkey/; this just
# wires inputs through.

module "valkey" {
  source = "./modules/valkey" # Replace with actual module source
  #version  = "1.0.0"            # Pin to the module version you're using
  for_each = local.enabled_configs

  # --- Deployment Topology & DR ---
  deployment_topology             = each.value.deployment_topology
  enable_cross_region_replication = each.value.enable_cross_region_replication
  secondary_location              = each.value.secondary_location

  # --- Core Identity ---
  project_id          = local.provider_project_id
  consumer_project_id = each.value.consumer_project_id
  environment         = each.value.environment
  instance_id         = each.value.instance_id

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
  existing_scp_name       = each.value.existing_scp_name

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

  # --- Deletion Protection ---
  deletion_protection_enabled = each.value.deletion_protection_enabled
}


# module "valkey" {
#   source = "./modules/valkey"

#   project_id          = var.project_id
#   consumer_project_id = var.consumer_project_id
#   environment         = var.environment
#   instance_id         = var.instance_id

#   location               = var.location
#   zone_distribution_mode = var.zone_distribution_mode
#   zone                   = var.zone

#   deployment_topology             = var.deployment_topology
#   enable_cross_region_replication = var.enable_cross_region_replication
#   secondary_location              = var.secondary_location
#   secondary_zone                  = var.secondary_zone

#   cluster_mode  = var.cluster_mode
#   node_type     = var.node_type
#   shard_count   = var.shard_count
#   replica_count = var.replica_count

#   psc_connectivity_mode   = var.psc_connectivity_mode
#   shared_vpc_host_project = var.shared_vpc_host_project
#   shared_vpc_network_name = var.shared_vpc_network_name
#   existing_scp_name       = var.existing_scp_name

#   authorization_mode      = var.authorization_mode
#   transit_encryption_mode = var.transit_encryption_mode

#   server_ca_mode = var.server_ca_mode
#   server_ca_pool = var.server_ca_pool

#   encryption_type = var.encryption_type
#   kms_key         = var.kms_key

#   persistence_mode        = var.persistence_mode
#   rdb_snapshot_period     = var.rdb_snapshot_period
#   rdb_snapshot_start_time = var.rdb_snapshot_start_time
#   aof_config              = var.aof_config

#   automated_backup_enabled         = var.automated_backup_enabled
#   automated_backup_start_time_hour = var.automated_backup_start_time_hour
#   automated_backup_retention_days  = var.automated_backup_retention_days

#   maintenance_day        = var.maintenance_day
#   maintenance_start_hour = var.maintenance_start_hour

#   engine_version          = var.engine_version
#   maxmemory_policy        = var.maxmemory_policy
#   notify_keyspace_events  = var.notify_keyspace_events
#   maxmemory_clients       = var.maxmemory_clients
#   slowlog_log_slower_than = var.slowlog_log_slower_than
#   maxclients              = var.maxclients

#   deletion_protection_enabled = var.deletion_protection_enabled
# }
# module "valkey_alerts" {
#   source = "./modules/valkey-alerts-module"

#   project_id  = var.project_id
#   instance_id = module.valkey.instance_id
#   region      = var.location

#   # Service team is in a different project — omit this if they share yours
#   service_project_id = var.service_project_id

#   platform_critical_emails     = var.platform_critical_emails
#   platform_warning_emails      = var.platform_warning_emails
#   service_team_critical_emails = var.service_team_critical_emails
#   service_team_warning_emails  = var.service_team_warning_emails

#   # Optional — override defaults if your workload's baseline differs
#   cpu_warning_threshold               = var.cpu_warning_threshold
#   cpu_critical_threshold              = var.cpu_critical_threshold
#   memory_warning_threshold            = var.memory_warning_threshold
#   memory_critical_threshold           = var.memory_critical_threshold
#   rejected_connections_threshold      = var.rejected_connections_threshold
#   connected_clients_warning_threshold = var.connected_clients_warning_threshold
#   replication_lag_warning_bytes       = var.replication_lag_warning_bytes
#   critical_alignment_period           = var.critical_alignment_period
#   warning_duration                    = var.warning_duration
#   critical_auto_close                 = var.critical_auto_close
# }
