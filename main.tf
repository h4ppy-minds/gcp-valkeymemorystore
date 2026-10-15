############################################
# Onboarding root: one JSON file per request under
# config/onboarding-files-valkey/, merged with global + per-environment
# defaults in locals.tf, fed into TWO module calls per instance.
#
# This used to call one merged module (terraform-google-valkey, with
# alerting folded in via enable_alerting / appteam_emails /
# platformteam_emails on the same call). Alerting is a separate module
# again — modules/terraform-google-h4ppy-memorystore-valkey-alerts — so
# that an onboarding PR that only edits appteam_emails/platformteam_emails
# plans and applies just the alerting module, never the instance itself.
# module.valkey_alerts is back; its outputs no longer come off
# module.valkey (see output.tf).
############################################
module "valkey" {
  source = "./modules/terraform-google-h4ppy-memorystore-valkey"
  #source   = "app.terraform.io/<YOUR_ORG>/valkey/google" # replace <YOUR_ORG>; see REGISTRY_PUBLISHING.md
  #version  = "~> 2.0" # Terraform version constraints don't match pre-release tags (e.g. 2.0.1-pre) unless pinned exactly — use "= 2.0.1-pre" while testing a pre-release, switch to "~> 2.0" once it's promoted to a stable tag.
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
  # authorization_mode / transit_encryption_mode are intentionally NOT
  # passed here — the module hard-requires IAM_AUTH / SERVER_AUTHENTICATION
  # and rejects any other value via variable validation (module CHANGELOG
  # 3.0.0), so there's nothing for this template to override. Leaving
  # them unset gets the module's (only) secure default.
  server_ca_mode  = each.value.server_ca_mode
  server_ca_pool  = try(each.value.server_ca_pool, null)
  encryption_type = each.value.encryption_type
  kms_key         = try(each.value.kms_key, null)

  # --- Persistence / backups / maintenance ---
  persistence_mode        = each.value.persistence_mode
  rdb_snapshot_period     = try(each.value.rdb_snapshot_period, null)
  rdb_snapshot_start_time = each.value.rdb_snapshot_start_time # always set (possibly null) by locals.tf's final merge
  aof_config              = try(each.value.aof_config, null)

  # automated_backup_start_time_hour / automated_backup_retention_days
  # are intentionally NOT passed here — left unset, the module supplies
  # its own defaults (hour = 3, retention = 35 days; see that module's
  # all-locals.tf). Only whether backups happen at all is
  # request-settable, same pattern as authorization_mode/
  # transit_encryption_mode above.
  automated_backup_enabled = each.value.automated_backup_enabled

  maintenance_day        = each.value.maintenance_day
  maintenance_start_hour = each.value.maintenance_start_hour

  # --- Engine & config parameters ---
  engine_version          = each.value.engine_version
  maxmemory_policy        = each.value.maxmemory_policy
  notify_keyspace_events  = each.value.notify_keyspace_events
  maxmemory_clients       = each.value.maxmemory_clients
  slowlog_log_slower_than = each.value.slowlog_log_slower_than
  maxclients              = each.value.maxclients

  # --- Deletion protection ---
  deletion_protection_enabled = each.value.deletion_protection_enabled

  # Alerting is no longer an input here at all — see module.valkey_alerts
  # below. Nothing in this block changes if an onboarding PR only touches
  # appteam_emails / platformteam_emails / enable_alerting.
}

# --- Alerting: one call per onboarded instance, wired to module.valkey's
# own outputs rather than back to each.value, so alerting always targets
# the instance actually created (its real instance_id/location) instead
# of whatever the request file happened to say. Same for_each key set as
# module.valkey, so every onboarded instance gets an alerting call —
# enable_alerting = false (or omitted, defaulting true) still produces
# the module call, it just no-ops internally. ---
module "valkey_alerts" {
  source = "./modules/terraform-google-h4ppy-memorystore-valkey-alerts"
  #source   = "app.terraform.io/<YOUR_ORG>/valkey-alerts/google" # replace <YOUR_ORG>; see REGISTRY_PUBLISHING.md
  #version  = "~> 1.0"
  for_each = local.valkey

  project_id  = each.value.project_id
  instance_id = module.valkey[each.key].instance_id
  location    = module.valkey[each.key].resolved_location

  # The module's enable_alerting is non-nullable (default true) — unlike
  # the old merged module, passing an explicit null here is a type error,
  # so the "unset -> module default" fallback has to happen on this side
  # instead: try(..., true), not try(..., null).
  enable_alerting = try(each.value.enable_alerting, true)

  appteam_emails      = try(each.value.appteam_emails, [])
  platformteam_emails = try(each.value.platformteam_emails, [])

  # This module has no visibility into the instance's replica_count (it
  # isn't the module that creates the instance), so the caller — here —
  # decides explicitly.
  enable_replication_lag_alert = try(each.value.replica_count, 0) > 0
}
