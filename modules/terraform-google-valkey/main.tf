############################################
# PART 1 — Memorystore for Valkey instance(s): primary + optional DR
# secondary.
#
# Both instances are the SAME underlying resource (./module/_instance),
# called twice. Primary and secondary aren't symmetric — different
# location, and the secondary's replication config points at the
# primary's id — so this stays two explicit call sites rather than one
# for_each over both.
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
############################################

module "primary" {
  source = "./module/_instance"

  project_id             = var.project_id
  instance_id            = local.instance_id
  location               = local.location
  zone_distribution_mode = local.zone_distribution_mode
  effective_zone         = local.effective_zone
  cluster_mode           = local.cluster_mode
  node_type              = local.node_type
  shard_count            = var.shard_count
  replica_count          = local.replica_count

  # Confirmed via a real apply error: "Invalid cross instance replication
  # role PRIMARY. Allowed value is: SECONDARY" — the primary never
  # declares a role itself; it becomes PRIMARY implicitly once a
  # secondary's cross_instance_replication_config.primary_instance points
  # at it (below).
  instance_role       = "NONE"
  primary_instance_id = null

  psc_connectivity_mode    = local.psc_connectivity_mode
  effective_psc_network_id = local.effective_psc_network_id

  authorization_mode      = local.authorization_mode
  transit_encryption_mode = local.transit_encryption_mode
  server_ca_mode          = local.server_ca_mode
  server_ca_pool          = local.server_ca_mode == "CUSTOMER_MANAGED_CAS_CA" ? var.server_ca_pool : null
  kms_key                 = local.encryption_type == "CUSTOMER_MANAGED" ? var.kms_key : null

  persistence_mode                 = local.persistence_mode
  rdb_snapshot_period              = var.rdb_snapshot_period
  rdb_snapshot_start_time          = var.rdb_snapshot_start_time
  aof_config                       = var.aof_config
  automated_backup_enabled         = local.automated_backup_enabled
  automated_backup_start_time_hour = local.automated_backup_start_time_hour
  automated_backup_retention_days  = local.automated_backup_retention_days
  maintenance_day                  = local.maintenance_day
  maintenance_start_hour           = local.maintenance_start_hour

  engine_version          = local.engine_version
  maxmemory_policy        = local.maxmemory_policy
  notify_keyspace_events  = local.notify_keyspace_events
  maxmemory_clients       = var.maxmemory_clients
  slowlog_log_slower_than = local.slowlog_log_slower_than
  maxclients              = var.maxclients

  deletion_protection_enabled = local.deletion_protection_enabled
  labels                      = local.labels

  valid_location                                   = local.valid_location
  valid_zone_for_single_zone_mode                  = local.valid_zone_for_single_zone_mode
  valid_shard_count_for_cluster_mode               = local.valid_shard_count_for_cluster_mode
  valid_node_type_for_prod                         = local.valid_node_type_for_prod
  valid_custom_node_type_requires_cluster_disabled = local.valid_custom_node_type_requires_cluster_disabled
  valid_iam_auth_requires_tls                      = local.valid_iam_auth_requires_tls
}

module "secondary" {
  count  = local.enable_cross_region_replication ? 1 : 0
  source = "./module/_instance"

  project_id             = var.project_id
  instance_id            = "${local.instance_id}-dr"
  location               = var.secondary_location
  zone_distribution_mode = local.zone_distribution_mode
  effective_zone         = local.effective_secondary_zone
  cluster_mode           = local.cluster_mode
  node_type              = local.node_type
  shard_count            = var.shard_count
  replica_count          = local.replica_count

  instance_role       = "SECONDARY"
  primary_instance_id = module.primary.id

  psc_connectivity_mode    = local.psc_connectivity_mode
  effective_psc_network_id = local.effective_psc_network_id

  # Must match the primary — cross-instance replication requires
  # consistent auth/TLS/CA/engine settings between the two.
  authorization_mode      = local.authorization_mode
  transit_encryption_mode = local.transit_encryption_mode
  server_ca_mode          = local.server_ca_mode
  server_ca_pool          = local.server_ca_mode == "CUSTOMER_MANAGED_CAS_CA" ? var.server_ca_pool : null
  kms_key                 = local.encryption_type == "CUSTOMER_MANAGED" ? var.kms_key : null

  persistence_mode        = local.persistence_mode
  rdb_snapshot_period     = var.rdb_snapshot_period
  rdb_snapshot_start_time = var.rdb_snapshot_start_time
  aof_config              = var.aof_config
  # Preserved as-is from the original hand-written resource: the
  # secondary never gets automated_backup_config, regardless of
  # local.automated_backup_enabled. Flagged in the README as worth
  # deciding explicitly rather than carrying forward silently.
  automated_backup_enabled = false
  maintenance_day          = local.maintenance_day
  maintenance_start_hour   = local.maintenance_start_hour

  engine_version          = local.engine_version
  maxmemory_policy        = local.maxmemory_policy
  notify_keyspace_events  = local.notify_keyspace_events
  maxmemory_clients       = var.maxmemory_clients
  slowlog_log_slower_than = local.slowlog_log_slower_than
  maxclients              = var.maxclients

  deletion_protection_enabled = local.deletion_protection_enabled
  labels                      = local.labels

  # Only the secondary's own location gets (re-)checked — shard_count/
  # node_type/cluster_mode/authorization_mode are the exact same
  # effective values the primary already validated.
  valid_location = local.valid_secondary_location
}

############################################
# PART 2 — Alerting: Cloud Monitoring alert policies + email notification
# channels for the instance created above.
#
# This used to be a second module (valkey-alerting) that callers wired up
# themselves against module.valkey's outputs. It's now folded directly
# into this module: instance_id and region come straight from module.primary
# rather than being passed in again, and the whole section is a no-op
# (empty for_each maps) when enable_alerting = false.
#
# Every alert policy is one instantiation of the generic
# module/_alert_policy submodule, driven by local.alert_definitions
# (all-locals.tf) — the same "single resource definition, called multiple
# times" pattern module/_instance uses above, here via for_each since the
# alert set is naturally table-shaped.
#
# To add a new alert: add one entry to local.alert_definitions in
# all-locals.tf. Nothing in this file changes.
############################################

# One notification channel per unique address across appteam_emails and
# platformteam_emails combined (see local.notification_channel_specs) —
# every address gets exactly one channel regardless of which team's list
# it came from. Created in var.project_id because notification channels
# are project-scoped and the alert policies below live in var.project_id
# too — a channel in a different project cannot be attached to these
# policies.
resource "google_monitoring_notification_channel" "email" {
  for_each     = local.notification_channel_specs
  project      = var.project_id
  display_name = each.value.display_name
  type         = "email"
  labels = {
    email_address = each.value.email
  }
}

module "alert_policies" {
  source   = "./module/_alert_policy"
  for_each = local.alert_definitions

  # Belt-and-suspenders: instance_id = module.primary.instance_id below
  # already creates an implicit dependency edge (Terraform can't know that
  # value until module.primary is created), so alert policies are already
  # guaranteed to run after the instance. This explicit depends_on just
  # protects that ordering against a future edit that might otherwise
  # stop referencing module.primary directly.
  depends_on = [module.primary]

  project_id  = var.project_id
  instance_id = module.primary.instance_id

  display_name           = each.value.display_name
  condition_display_name = each.value.condition_display_name
  severity               = each.value.severity
  resource_type          = each.value.resource_type
  metric_type            = each.value.metric_type
  comparison             = each.value.comparison
  threshold_value        = each.value.threshold_value
  duration               = each.value.duration
  alignment_period       = each.value.alignment_period
  per_series_aligner     = each.value.per_series_aligner
  cross_series_reducer   = each.value.cross_series_reducer
  group_by_fields        = each.value.group_by_fields

  enable_absent_check       = each.value.enable_absent_check
  absent_duration           = coalesce(each.value.absent_duration, "300s")
  absent_alignment_period   = coalesce(each.value.absent_alignment_period, "60s")
  absent_per_series_aligner = coalesce(each.value.absent_per_series_aligner, "ALIGN_MIN")

  auto_close = each.value.auto_close

  notification_channels = local.notification_channel_ids
}
