############################################
# Alternative to the YAML-manifest root (../main.tf): one JSON file per
# onboarding request under config/onboarding-files-valkey/, merged with
# global + per-environment defaults in locals.tf. See this folder's
# README.md for how the two patterns compare.
############################################

locals {
  # var.env uses "prd" (matching the manifest-driven root and typical TFC
  # workspace naming), but the valkey module's environment variable
  # validates against "PROD", not "PRD" — upper(var.env) alone would fail
  # for prd specifically. Explicit map avoids that mismatch.
  _env_label = {
    dev = "DEV"
    qa  = "QA"
    uat = "UAT"
    prd = "PROD"
  }
}

module "valkey" {
  source = "./modules/terraform-google-valkey"
  #source   = "app.terraform.io/<YOUR_ORG>/valkey/google" # replace <YOUR_ORG>; see ../../REGISTRY_PUBLISHING.md
  #version  = "~> 1.0"
  for_each = local.valkey

  deployment_topology = each.value.deployment_topology
  secondary_location  = each.value.secondary_location

  project_id  = each.value.project_id
  environment = local._env_label[var.env]
  instance_id = each.value.instance_id

  location               = each.value.location
  zone_distribution_mode = each.value.zone_distribution_mode
  zone                   = try(each.value.zone, null)
  secondary_zone         = try(each.value.secondary_zone, null)

  cluster_mode  = each.value.cluster_mode
  node_type     = each.value.node_type
  shard_count   = each.value.shard_count
  replica_count = each.value.replica_count

  psc_connectivity_mode   = each.value.psc_connectivity_mode
  shared_vpc_host_project = each.value.shared_vpc_host_project
  shared_vpc_network_name = each.value.shared_vpc_network_name

  authorization_mode      = each.value.authorization_mode
  transit_encryption_mode = each.value.transit_encryption_mode

  server_ca_mode = each.value.server_ca_mode
  server_ca_pool = try(each.value.server_ca_pool, null)

  encryption_type = each.value.encryption_type
  kms_key         = try(each.value.kms_key, null)

  persistence_mode        = each.value.persistence_mode
  rdb_snapshot_period     = try(each.value.rdb_snapshot_period, null)
  rdb_snapshot_start_time = try(each.value.rdb_snapshot_start_time, null)
  aof_config              = try(each.value.aof_config, null)

  automated_backup_enabled         = each.value.automated_backup_enabled
  automated_backup_start_time_hour = each.value.automated_backup_start_time_hour
  automated_backup_retention_days  = each.value.automated_backup_retention_days

  maintenance_day        = each.value.maintenance_day
  maintenance_start_hour = each.value.maintenance_start_hour

  engine_version   = each.value.engine_version
  maxmemory_policy = each.value.maxmemory_policy

  deletion_protection_enabled = each.value.deletion_protection_enabled
  labels                      = try(each.value.labels, {})
}

module "valkey_alerts" {
  source = "./modules/terraform-google-valkey-alerting"
  #source   = "app.terraform.io/<YOUR_ORG>/valkey-alerting/google" # replace <YOUR_ORG>
  #version  = "~> 1.0"
  for_each = local.valkey

  project_id    = each.value.project_id
  instance_id   = module.valkey[each.key].instance_id
  region        = each.value.location
  replica_count = each.value.replica_count

  appteam_emails      = try(each.value.appteam_emails, [])
  platformteam_emails = try(each.value.platformteam_emails, [])
}
