############################################
# Onboarding root: one JSON file per request under
# config/onboarding-files-valkey/, merged with global + per-environment
# defaults in locals.tf, fed into ONE module call per instance.
#
# This used to call two modules (terraform-google-valkey +
# terraform-google-valkey-alerting) separately. They're now merged into
# a single module at ./modules/terraform-google-valkey — alerting is# built in, controlled by enable_alerting / appteam_emails /
# platformteam_emails on the SAME module call. There is no second
# module block anymore; module.valkey_alerts is gone, and its outputs
# now come straight off module.valkey (see output.tf).
############################################

locals {
  # var.env uses "prd" (matching typical TFC workspace naming), but the
  # valkey module's environment variable validates against "PROD", not
  # "PRD" — upper(var.env) alone would fail for prd specifically.
  # Explicit map avoids that mismatch.
  _env_label = {
    dev = "DEV"
    qa  = "QA"
    uat = "UAT"
    prd = "PROD"
  }
}

module "valkey" {
  source = "./modules/terraform-google-valkey"
  #source   = "app.terraform.io/<YOUR_ORG>/valkey/google" # replace <YOUR_ORG>; see REGISTRY_PUBLISHING.md
  #version  = "~> 2.1"
  for_each = local.valkey

  # --- Topology (derived in locals.tf from cross_region_replica + replica_count) ---
  deployment_topology = each.value.deployment_topology
  secondary_location  = each.value.secondary_location

  # --- Identity ---
  project_id  = each.value.project_id
  environment = local._env_label[var.env]
  instance_id = each.value.instance_id
  labels      = try(each.value.labels, {})

  # --- Region / zone ---
  location               = each.value.location
  zone_distribution_mode = each.value.zone_distribution_mode
  zone                   = try(each.value.zone, null)
  secondary_zone         = try(each.value.secondary_zone, null)

  # --- Cluster topology & sizing ---
  cluster_mode  = each.value.cluster_mode
  node_type     = each.value.node_type
  shard_count   = each.value.shard_count
  replica_count = each.value.replica_count

  # --- PSC connectivity ---
  psc_connectivity_mode   = each.value.psc_connectivity_mode
  shared_vpc_host_project = try(each.value.shared_vpc_host_project, null)
  shared_vpc_network_name = try(each.value.shared_vpc_network_name, null)
  existing_scp_name       = try(each.value.existing_scp_name, null)

  # --- Auth / TLS / CA / CMEK ---
  authorization_mode      = each.value.authorization_mode
  transit_encryption_mode = each.value.transit_encryption_mode
  server_ca_mode          = each.value.server_ca_mode
  server_ca_pool          = try(each.value.server_ca_pool, null)
  encryption_type         = each.value.encryption_type
  kms_key                 = try(each.value.kms_key, null)

  # --- Persistence / backups / maintenance ---
  persistence_mode        = each.value.persistence_mode
  rdb_snapshot_period     = try(each.value.rdb_snapshot_period, null)
  rdb_snapshot_start_time = each.value.rdb_snapshot_start_time # always set (possibly null) by locals.tf's final merge
  aof_config              = try(each.value.aof_config, null)

  automated_backup_enabled         = each.value.automated_backup_enabled
  automated_backup_start_time_hour = each.value.automated_backup_start_time_hour
  automated_backup_retention_days  = each.value.automated_backup_retention_days

  maintenance_day        = each.value.maintenance_day
  maintenance_start_hour = each.value.maintenance_start_hour

  # --- Engine & config parameters ---
  # These four were previously dropped on the floor here — present in
  # default.json but never forwarded to the module, so every instance
  # silently got the module's own internal defaults instead of the
  # onboarding-layer default.json values. Fixed.
  engine_version          = each.value.engine_version
  maxmemory_policy        = each.value.maxmemory_policy
  notify_keyspace_events  = each.value.notify_keyspace_events
  maxmemory_clients       = each.value.maxmemory_clients
  slowlog_log_slower_than = each.value.slowlog_log_slower_than
  maxclients              = each.value.maxclients

  # --- Deletion protection ---
  deletion_protection_enabled = each.value.deletion_protection_enabled

  # --- Alerting — now part of this same module call (module
  # "valkey_alerts" no longer exists). Only 3 alerting inputs exist on
  # the module at all; everything else (thresholds/durations/metric
  # names) is fixed inside the module's alerts.tf and cannot be
  # overridden from here. ---
  enable_alerting     = try(each.value.enable_alerting, null) # null -> module default (true)
  appteam_emails      = try(each.value.appteam_emails, [])
  platformteam_emails = try(each.value.platformteam_emails, [])
}
