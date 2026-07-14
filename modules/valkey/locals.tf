locals {
  # --- Cross-project resolution ---
  # Falls back to the host project when consumer_project_id isn't set
  # (same-project deployments). Used throughout psc_network.tf.
  effective_consumer_project_id = coalesce(var.consumer_project_id, var.project_id)

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

  # --- USER mode: one forwarding rule per (consumer network × service attachment) ---
  # The instance exposes N service attachments via psc_attachment_details
  # (e.g. discovery + per-shard endpoints). Each consumer network needs its
  # own forwarding rule + reserved IP per attachment, not just one per network.

  # psc_attachment_indices = var.psc_connectivity_mode == "USER" ? range(
  #   length(google_memorystore_instance.shared-instance.psc_attachment_details)
  # ) : []

  # locals.tf
  psc_attachment_indices = var.psc_connectivity_mode == "USER" ? range(var.psc_attachment_count) : []

  user_network_attachments = var.psc_connectivity_mode == "USER" ? merge([
    for net_key, net_val in var.user_networks : {
      for idx in local.psc_attachment_indices :
      "${net_key}-${idx}" => {
        network_key      = net_key
        attachment_index = idx
      }
    }
  ]...) : {}
}
