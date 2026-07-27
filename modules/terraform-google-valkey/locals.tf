locals {

  # Single source of truth: DR *is* "has a secondary instance," nothing
  # else distinguishes it. Derived rather than a separate variable so
  # there's no possibility of the two disagreeing.
  enable_cross_region_replication = var.deployment_topology == "DR"

  # --- Zone resolution for SINGLE_ZONE mode ---
  effective_zone = var.zone_distribution_mode == "SINGLE_ZONE" ? coalesce(
    var.zone,
    try(data.google_compute_zones.available_zones.names[0], null)
  ) : null

  # --- Precondition helpers (see main.tf lifecycle block) ---
  valid_location = contains(data.google_compute_regions.available_regions.names, var.location)

  valid_zone_for_single_zone_mode = (
    var.zone_distribution_mode != "SINGLE_ZONE" ||
    (local.effective_zone != null &&
    contains(data.google_compute_zones.available_zones.names, local.effective_zone))
  )

  valid_shard_count_for_cluster_mode = var.cluster_mode != "CLUSTER_DISABLED" || var.shard_count == 1

  valid_node_type_for_prod = var.node_type != "SHARED_CORE_NANO" || upper(var.environment) != "PROD"

  valid_iam_auth_requires_tls = var.authorization_mode != "IAM_AUTH" || var.transit_encryption_mode == "SERVER_AUTHENTICATION"

  valid_custom_node_type_requires_cluster_disabled = (
    !contains(["CUSTOM_PICO", "CUSTOM_MICRO", "CUSTOM_MINI"], var.node_type) ||
    var.cluster_mode == "CLUSTER_DISABLED"
  )

  # --- DR: secondary instance zone/location resolution ---
  effective_secondary_zone = (
    local.enable_cross_region_replication && var.zone_distribution_mode == "SINGLE_ZONE"
    ) ? coalesce(
    var.secondary_zone,
    try(data.google_compute_zones.available_secondary_zones[0].names[0], null)
  ) : null

  valid_secondary_location = (
    !local.enable_cross_region_replication ||
    contains(data.google_compute_regions.available_regions.names, var.secondary_location)
  )

  effective_psc_network_id = (
    var.psc_connectivity_mode == "SHARED_VPC" ? try(data.google_compute_network.shared_vpc_net[0].id, null) : null
  )

}

