output "instance_id" {
  description = "The instance ID."
  value       = google_memorystore_instance.shared-instance.instance_id
}

output "instance_name" {
  description = "Fully qualified resource name of the instance."
  value       = google_memorystore_instance.shared-instance.name
}

output "resolved_zone" {
  description = "The zone actually used for the instance (relevant when zone_distribution_mode = SINGLE_ZONE and zone was auto-selected)."
  value       = local.effective_zone
}

output "psc_connectivity_mode" {
  description = "Which PSC connectivity mode this deployment used (AUTO or USER)."
  value       = var.psc_connectivity_mode
}

output "psc_attachment_details" {
  description = "..."
  value = [
    for a in google_memorystore_instance.shared-instance.psc_attachment_details : {
      connection_type    = a.connection_type
      service_attachment = a.service_attachment
    }
  ]
}

output "consumer_project_id" {
  description = "The project the consumer VPC network(s) were created in."
  value       = local.effective_consumer_project_id
}

# --- AUTO mode connection info ---
output "auto_mode_network_self_link" {
  description = "Self link of the consumer VPC network created for AUTO mode. Null in USER mode."
  value       = var.psc_connectivity_mode == "AUTO" ? google_compute_network.auto_producer_net[0].self_link : null
}

output "auto_mode_service_connection_policy" {
  description = "Name of the Service Connection Policy authorizing the AUTO-mode PSC connection. Null in USER mode."
  value       = var.psc_connectivity_mode == "AUTO" ? google_network_connectivity_service_connection_policy.auto_policy[0].name : null
}

# --- USER mode connection info ---
# Keyed by "networkKey-attachmentIndex" — one entry per (consumer network x
# service attachment) pair, since an instance can expose multiple
# attachments (discovery + per-shard) that each need their own endpoint.
output "user_mode_endpoint_ips" {
  description = "Map of 'networkKey-attachmentIndex' -> reserved internal IP address that apps in each consumer VPC should connect to. Empty in AUTO mode."
  value = var.psc_connectivity_mode == "USER" ? {
    for k, addr in google_compute_address.user_endpoint_ip : k => addr.address
  } : {}
}

output "user_mode_forwarding_rules" {
  description = "Map of 'networkKey-attachmentIndex' -> forwarding rule self link created for USER mode. Empty in AUTO mode."
  value = var.psc_connectivity_mode == "USER" ? {
    for k, fr in google_compute_forwarding_rule.user_fr : k => fr.self_link
  } : {}
}
