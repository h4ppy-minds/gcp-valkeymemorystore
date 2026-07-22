output "instance_id" {
  description = "The instance ID."
  value       = module.primary.instance_id
}

output "instance_name" {
  description = "Fully qualified resource name of the instance."
  value       = module.primary.name
}

output "resolved_zone" {
  description = "The zone actually used for the instance (relevant when zone_distribution_mode = SINGLE_ZONE and zone was auto-selected)."
  value       = local.effective_zone
}

output "shared_vpc_network_self_link" {
  description = "Self link of the existing Shared VPC network used. Null unless psc_connectivity_mode = SHARED_VPC."
  value       = var.psc_connectivity_mode == "SHARED_VPC" ? data.google_compute_network.shared_vpc_net[0].self_link : null
}

output "psc_connectivity_mode" {
  description = "Which PSC connectivity mode this deployment used (NONE or SHARED_VPC)."
  value       = var.psc_connectivity_mode
}

output "psc_attachment_details" {
  description = "Service attachments exposed by the primary instance (connection_type + service_attachment). Useful for confirming psc_attachment_count matches reality."
  value       = module.primary.psc_attachment_details
}

output "discovery_endpoints" {
  description = "PSC discovery endpoints (ip_address, port, network, service_attachment) for the primary instance — the real connection points clients use."
  value       = module.primary.discovery_endpoints
}

# --- DR (secondary instance) outputs ---
output "secondary_instance_id" {
  description = "Instance ID of the SECONDARY (DR) instance. Null unless enable_cross_region_replication = true."
  value       = try(module.secondary[0].instance_id, null)
}

output "secondary_psc_attachment_details" {
  description = "Service attachments exposed by the secondary instance. Empty unless enable_cross_region_replication = true."
  value       = try(module.secondary[0].psc_attachment_details, [])
}

output "secondary_discovery_endpoints" {
  description = "PSC discovery endpoints for the SECONDARY (DR) instance. Empty unless enable_cross_region_replication = true."
  value       = try(module.secondary[0].discovery_endpoints, [])
}
