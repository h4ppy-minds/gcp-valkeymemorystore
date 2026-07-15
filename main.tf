
# Root main.tf — this is the file customers/callers actually edit values
# for (via a tfvars file). All logic lives in modules/valkey/; this just
# wires inputs through.

module "valkey" {
  source = "./modules/valkey"

  project_id          = var.project_id
  consumer_project_id = var.consumer_project_id
  environment         = var.environment
  instance_id         = var.instance_id

  location               = var.location
  zone_distribution_mode = var.zone_distribution_mode
  zone                   = var.zone

  deployment_topology             = var.deployment_topology
  enable_cross_region_replication = var.enable_cross_region_replication
  secondary_location              = var.secondary_location
  secondary_zone                  = var.secondary_zone

  cluster_mode  = var.cluster_mode
  node_type     = var.node_type
  shard_count   = var.shard_count
  replica_count = var.replica_count

  psc_connectivity_mode   = var.psc_connectivity_mode
  shared_vpc_host_project = var.shared_vpc_host_project
  shared_vpc_network_name = var.shared_vpc_network_name
  existing_scp_name       = var.existing_scp_name

  authorization_mode      = var.authorization_mode
  transit_encryption_mode = var.transit_encryption_mode

  server_ca_mode = var.server_ca_mode
  server_ca_pool = var.server_ca_pool

  encryption_type = var.encryption_type
  kms_key         = var.kms_key

  persistence_mode        = var.persistence_mode
  rdb_snapshot_period     = var.rdb_snapshot_period
  rdb_snapshot_start_time = var.rdb_snapshot_start_time
  aof_config              = var.aof_config

  automated_backup_enabled         = var.automated_backup_enabled
  automated_backup_start_time_hour = var.automated_backup_start_time_hour
  automated_backup_retention_days  = var.automated_backup_retention_days

  maintenance_day        = var.maintenance_day
  maintenance_start_hour = var.maintenance_start_hour

  engine_version          = var.engine_version
  maxmemory_policy        = var.maxmemory_policy
  notify_keyspace_events  = var.notify_keyspace_events
  maxmemory_clients       = var.maxmemory_clients
  slowlog_log_slower_than = var.slowlog_log_slower_than
  maxclients              = var.maxclients

  deletion_protection_enabled = var.deletion_protection_enabled
}
