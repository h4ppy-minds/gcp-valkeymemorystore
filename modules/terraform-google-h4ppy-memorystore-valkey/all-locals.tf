############################################################################
# all-locals.tf — THE file to edit when you want to change a Valkey
# INSTANCE default (topology, sizing, persistence, auth/TLS/CA, backups,
# maintenance, engine config). This module's variables are entirely about
# the instance — no alerting lives here at all.
#
# Alerting (Cloud Monitoring alert policies + email notification
# channels) is a separate module — terraform-google-valkey-alerts — kept
# out of this one on purpose: changing a notification email address
# shouldn't require planning/applying this module's infrastructure.
#
# Layout of this file, top to bottom:
#   1. local.defaults      — every literal instance default value, in one
#                            map. Change a value here to change the
#                            module's default everywhere it's used.
#                            Nothing else in this repo needs to change.
#   2. local.<name>        — the "effective" value of every instance
#                            variable that has a default: var.<name> if
#                            the caller set it, else local.defaults.<name>.
#                            main.tf and data.tf read these, never var.*
#                            directly, for anything listed in
#                            local.defaults.
#   3. Derived locals       — values computed FROM the effective values
#                            above (zone resolution, precondition
#                            booleans for main.tf's lifecycle blocks).
#                            Not "defaults" themselves, just logic, but
#                            they live here too so the instance's
#                            behavior is readable from one file.
############################################################################

locals {

  ##########################################################################
  # 1. DEFAULTS — edit this map to change an instance default. Nothing else.
  ##########################################################################
  defaults = {
    # --- topology / identity ---
    deployment_topology = "STANDALONE"
    instance_id         = "basic-instance"
    labels              = {}

    # --- region / zone ---
    location = "us-central1"
    # Region-agnostic in principle (Memorystore for Valkey isn't limited to
    # these), but this module only allow-lists the regions below by
    # default — add a region here to make it selectable without touching
    # any other file. (Actual availability is still re-checked dynamically
    # against data.google_compute_regions for the target project — see the
    # valid_location derived local below.)
    allowed_locations = [
      "us-central1", "us-east1", "us-east4", "us-east5",
      "us-south1", "us-west1", "us-west2", "us-west3", "us-west4",
    ]
    zone_distribution_mode = "MULTI_ZONE"

    # --- cluster topology & sizing ---
    cluster_mode  = "CLUSTER"
    node_type     = "STANDARD_SMALL"
    replica_count = 0

    # --- PSC connectivity ---
    psc_connectivity_mode = "NONE"

    # --- auth / TLS / CA / CMEK ---
    # authorization_mode / transit_encryption_mode are not just defaults —
    # variables.tf's validation blocks reject any value other than
    # IAM_AUTH / SERVER_AUTHENTICATION (or null, which lands here). There
    # is no supported way for a caller to get an unauthenticated or
    # unencrypted instance out of this module.
    authorization_mode      = "IAM_AUTH"
    transit_encryption_mode = "SERVER_AUTHENTICATION"
    server_ca_mode          = "GOOGLE_MANAGED_PER_INSTANCE_CA"
    encryption_type         = "GOOGLE_MANAGED"

    # --- persistence / backups / maintenance ---
    persistence_mode                 = "RDB"
    automated_backup_enabled         = true
    automated_backup_start_time_hour = 3
    automated_backup_retention_days  = 35
    maintenance_day                  = "SUNDAY"
    maintenance_start_hour           = 4

    # --- engine & config parameters ---
    engine_version          = "VALKEY_9_0"
    maxmemory_policy        = "volatile-lru"
    notify_keyspace_events  = ""
    slowlog_log_slower_than = 10000 # 10ms

    # --- safety ---
    deletion_protection_enabled = true
  }

  ##########################################################################
  # 2. EFFECTIVE VALUES — var override wins, else local.defaults.*.
  # main.tf and data.tf read these, not var.*.
  ##########################################################################

  deployment_topology = coalesce(var.deployment_topology, local.defaults.deployment_topology)
  instance_id         = coalesce(var.instance_id, local.defaults.instance_id)
  labels              = var.labels != null ? var.labels : local.defaults.labels

  location               = coalesce(var.location, local.defaults.location)
  zone_distribution_mode = coalesce(var.zone_distribution_mode, local.defaults.zone_distribution_mode)

  cluster_mode  = coalesce(var.cluster_mode, local.defaults.cluster_mode)
  node_type     = coalesce(var.node_type, local.defaults.node_type)
  replica_count = coalesce(var.replica_count, local.defaults.replica_count)

  psc_connectivity_mode = coalesce(var.psc_connectivity_mode, local.defaults.psc_connectivity_mode)

  authorization_mode      = coalesce(var.authorization_mode, local.defaults.authorization_mode)
  transit_encryption_mode = coalesce(var.transit_encryption_mode, local.defaults.transit_encryption_mode)
  server_ca_mode          = coalesce(var.server_ca_mode, local.defaults.server_ca_mode)
  encryption_type         = coalesce(var.encryption_type, local.defaults.encryption_type)

  persistence_mode                 = coalesce(var.persistence_mode, local.defaults.persistence_mode)
  automated_backup_enabled         = coalesce(var.automated_backup_enabled, local.defaults.automated_backup_enabled)
  automated_backup_start_time_hour = coalesce(var.automated_backup_start_time_hour, local.defaults.automated_backup_start_time_hour)
  automated_backup_retention_days  = coalesce(var.automated_backup_retention_days, local.defaults.automated_backup_retention_days)
  maintenance_day                  = coalesce(var.maintenance_day, local.defaults.maintenance_day)
  maintenance_start_hour           = coalesce(var.maintenance_start_hour, local.defaults.maintenance_start_hour)

  engine_version          = coalesce(var.engine_version, local.defaults.engine_version)
  maxmemory_policy        = coalesce(var.maxmemory_policy, local.defaults.maxmemory_policy)
  notify_keyspace_events  = coalesce(var.notify_keyspace_events, local.defaults.notify_keyspace_events)
  slowlog_log_slower_than = coalesce(var.slowlog_log_slower_than, local.defaults.slowlog_log_slower_than)

  deletion_protection_enabled = coalesce(var.deletion_protection_enabled, local.defaults.deletion_protection_enabled)

  ##########################################################################
  # 3. DERIVED LOCALS — logic built from the effective values above.
  ##########################################################################

  # DR *is* "has a secondary instance," nothing else distinguishes it.
  # Derived rather than a separate variable so there's no possibility of
  # the two disagreeing.
  enable_cross_region_replication = local.deployment_topology == "DR"

  # --- Zone resolution for SINGLE_ZONE mode ---
  effective_zone = local.zone_distribution_mode == "SINGLE_ZONE" ? coalesce(
    var.zone,
    try(data.google_compute_zones.available_zones.names[0], null)
  ) : null

  effective_secondary_zone = (
    local.enable_cross_region_replication && local.zone_distribution_mode == "SINGLE_ZONE"
    ) ? coalesce(
    var.secondary_zone,
    try(data.google_compute_zones.available_secondary_zones[0].names[0], null)
  ) : null

  effective_psc_network_id = (
    local.psc_connectivity_mode == "SHARED_VPC" ? try(data.google_compute_network.shared_vpc_net[0].id, null) : null
  )

  # --- Precondition helpers (see main.tf lifecycle blocks) ---
  valid_location = contains(data.google_compute_regions.available_regions.names, local.location)

  valid_zone_for_single_zone_mode = (
    local.zone_distribution_mode != "SINGLE_ZONE" ||
    (local.effective_zone != null &&
    contains(data.google_compute_zones.available_zones.names, local.effective_zone))
  )

  valid_secondary_location = (
    !local.enable_cross_region_replication ||
    contains(data.google_compute_regions.available_regions.names, var.secondary_location)
  )

  valid_shard_count_for_cluster_mode = local.cluster_mode != "CLUSTER_DISABLED" || var.shard_count == 1

  valid_node_type_for_prod = local.node_type != "SHARED_CORE_NANO" || upper(var.environment) != "PROD"

  valid_iam_auth_requires_tls = local.authorization_mode != "IAM_AUTH" || local.transit_encryption_mode == "SERVER_AUTHENTICATION"

  valid_custom_node_type_requires_cluster_disabled = (
    !contains(["CUSTOM_PICO", "CUSTOM_MICRO", "CUSTOM_MINI"], local.node_type) ||
    local.cluster_mode == "CLUSTER_DISABLED"
  )
}
