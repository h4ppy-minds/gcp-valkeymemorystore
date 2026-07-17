output "instance_id" {
  description = "The instance ID."
  value       = google_memorystore_instance.primary-instance.instance_id
}

output "instance_name" {
  description = "Fully qualified resource name of the instance."
  value       = google_memorystore_instance.primary-instance.name
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
  value = [
    for a in google_memorystore_instance.primary-instance.psc_attachment_details : {
      connection_type    = a.connection_type
      service_attachment = a.service_attachment
    }
  ]
}

output "discovery_endpoints" {
  description = "PSC discovery endpoints (ip_address, port, network, service_attachment) for the primary instance — the real connection points clients use."
  value = flatten([
    for e in google_memorystore_instance.primary-instance.endpoints : [
      for c in e.connections : {
        ip_address         = c.psc_auto_connection[0].ip_address
        port               = c.psc_auto_connection[0].port
        network            = c.psc_auto_connection[0].network
        service_attachment = c.psc_auto_connection[0].service_attachment
        forwarding_rule    = c.psc_auto_connection[0].forwarding_rule
      }
      if c.psc_auto_connection[0].connection_type == "CONNECTION_TYPE_DISCOVERY"
    ]
  ])
}

# --- DR (secondary instance) outputs ---
output "secondary_instance_id" {
  description = "Instance ID of the SECONDARY (DR) instance. Null unless enable_cross_region_replication = true."
  value       = var.enable_cross_region_replication ? google_memorystore_instance.secondary[0].instance_id : null
}

output "secondary_psc_attachment_details" {
  description = "Service attachments exposed by the secondary instance. Empty unless enable_cross_region_replication = true."
  value = var.enable_cross_region_replication ? [
    for a in google_memorystore_instance.secondary[0].psc_attachment_details : {
      connection_type    = a.connection_type
      service_attachment = a.service_attachment
    }
  ] : []
}

output "secondary_discovery_endpoints" {
  description = "PSC discovery endpoints for the SECONDARY (DR) instance. Empty unless enable_cross_region_replication = true."
  value = var.enable_cross_region_replication ? flatten([
    for e in google_memorystore_instance.secondary[0].endpoints : [
      for c in e.connections : {
        ip_address         = c.psc_auto_connection[0].ip_address
        port               = c.psc_auto_connection[0].port
        network            = c.psc_auto_connection[0].network
        service_attachment = c.psc_auto_connection[0].service_attachment
        forwarding_rule    = c.psc_auto_connection[0].forwarding_rule
      }
      if c.psc_auto_connection[0].connection_type == "CONNECTION_TYPE_DISCOVERY"
    ]
  ]) : []
}
