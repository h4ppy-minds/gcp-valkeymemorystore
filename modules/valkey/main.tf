############################################
# Memorystore for Valkey — primary + optional DR secondary
#
# Both instances are the SAME underlying resource (./modules/_instance),
# called twice. Primary and secondary aren't symmetric — different
# location, and the secondary's replication config points at the
# primary's id — so this stays two explicit call sites rather than one
# for_each over both (which would mean one instance of a for_each
# referencing a sibling key of the same for_each — legal in Terraform,
# but a needless source of confusing dependency-graph behavior for a
# relationship that's inherently asymmetric anyway). What WAS wrong
# before this refactor was two ~150-line hand-duplicated resource
# blocks; that duplication now lives in exactly one place
# (modules/_instance/main.tf).
#
# Network connectivity is controlled by var.psc_connectivity_mode:
#   NONE        — no endpoint block; nothing can reach the instance over
#                 PSC until wired up some other way, outside this module.
#   SHARED_VPC  — points the instance at an already-existing Shared VPC
#                 network + Service Connection Policy (both created
#                 outside this module — see data.tf and the
#                 shared_vpc_* / existing_scp_name variables). Memorystore
#                 auto-creates the PSC endpoint itself; no second apply.
#
# Topology: var.deployment_topology (STANDALONE / HA / DR) is the single
# source of truth — local.enable_cross_region_replication (locals.tf) is
# derived from it (true iff deployment_topology == "DR"), not a separate
# variable. replica_count is still validated for consistency against
# deployment_topology (see the check block in variables.tf), since that's
# a real independent magnitude, not something the topology label implies
# a single value for.
############################################

module "primary" {
  source = "./module/_instance"

  project_id             = var.project_id
  instance_id            = var.instance_id
  location               = var.location
  zone_distribution_mode = var.zone_distribution_mode
  effective_zone         = local.effective_zone
  cluster_mode           = var.cluster_mode
  node_type              = var.node_type
  shard_count            = var.shard_count
  replica_count          = var.replica_count

  # Confirmed via a real apply error: "Invalid cross instance replication
  # role PRIMARY. Allowed value is: SECONDARY" — the primary never
  # declares a role itself; it becomes PRIMARY implicitly once a
  # secondary's cross_instance_replication_config.primary_instance points
  # at it (below). This resolves the "unverified" DR-pairing caveat that
  # used to be in the README: the answer is "the primary needs no block
  # at all," not "the primary needs instance_role = PRIMARY."
  instance_role       = "NONE"
  primary_instance_id = null

  psc_connectivity_mode    = var.psc_connectivity_mode
  effective_psc_network_id = local.effective_psc_network_id

  authorization_mode      = var.authorization_mode
  transit_encryption_mode = var.transit_encryption_mode
  server_ca_mode          = var.server_ca_mode
  server_ca_pool          = var.server_ca_mode == "CUSTOMER_MANAGED_CAS_CA" ? var.server_ca_pool : null
  kms_key                 = var.encryption_type == "CUSTOMER_MANAGED" ? var.kms_key : null

  persistence_mode                 = var.persistence_mode
  rdb_snapshot_period              = var.rdb_snapshot_period
  rdb_snapshot_start_time          = var.rdb_snapshot_start_time
  aof_config                       = var.aof_config
  automated_backup_enabled         = var.automated_backup_enabled
  automated_backup_start_time_hour = var.automated_backup_start_time_hour
  automated_backup_retention_days  = var.automated_backup_retention_days
  maintenance_day                  = var.maintenance_day
  maintenance_start_hour           = var.maintenance_start_hour

  engine_version          = var.engine_version
  maxmemory_policy        = var.maxmemory_policy
  notify_keyspace_events  = var.notify_keyspace_events
  maxmemory_clients       = var.maxmemory_clients
  slowlog_log_slower_than = var.slowlog_log_slower_than
  maxclients              = var.maxclients

  deletion_protection_enabled = var.deletion_protection_enabled
  labels                      = var.labels

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
  instance_id            = "${var.instance_id}-dr"
  location               = var.secondary_location
  zone_distribution_mode = var.zone_distribution_mode
  effective_zone         = local.effective_secondary_zone
  cluster_mode           = var.cluster_mode
  node_type              = var.node_type
  shard_count            = var.shard_count
  replica_count          = var.replica_count

  instance_role       = "SECONDARY"
  primary_instance_id = module.primary.id

  psc_connectivity_mode    = var.psc_connectivity_mode
  effective_psc_network_id = local.effective_psc_network_id

  # Must match the primary — cross-instance replication requires
  # consistent auth/TLS/CA/engine settings between the two.
  authorization_mode      = var.authorization_mode
  transit_encryption_mode = var.transit_encryption_mode
  server_ca_mode          = var.server_ca_mode
  server_ca_pool          = var.server_ca_mode == "CUSTOMER_MANAGED_CAS_CA" ? var.server_ca_pool : null
  kms_key                 = var.encryption_type == "CUSTOMER_MANAGED" ? var.kms_key : null

  persistence_mode        = var.persistence_mode
  rdb_snapshot_period     = var.rdb_snapshot_period
  rdb_snapshot_start_time = var.rdb_snapshot_start_time
  aof_config              = var.aof_config
  # Preserved as-is from the original hand-written resource: the
  # secondary never got automated_backup_config, regardless of
  # var.automated_backup_enabled. That may well have been an oversight
  # rather than a deliberate choice — worth deciding explicitly rather
  # than carrying it forward silently forever. Flagged in the README.
  automated_backup_enabled = false
  maintenance_day          = var.maintenance_day
  maintenance_start_hour   = var.maintenance_start_hour

  engine_version          = var.engine_version
  maxmemory_policy        = var.maxmemory_policy
  notify_keyspace_events  = var.notify_keyspace_events
  maxmemory_clients       = var.maxmemory_clients
  slowlog_log_slower_than = var.slowlog_log_slower_than
  maxclients              = var.maxclients

  deletion_protection_enabled = var.deletion_protection_enabled
  labels                      = var.labels

  # Only the secondary's own location gets (re-)checked — shard_count/
  # node_type/cluster_mode/authorization_mode are the exact same
  # variables the primary already validated, so re-asserting them here
  # would just duplicate the same check against identical inputs.
  valid_location = local.valid_secondary_location
}
