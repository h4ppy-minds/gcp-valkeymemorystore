output "instance_id" {
  value = { for k, m in module.valkey : k => m.instance_id }
}

output "instance_name" {
  value = { for k, m in module.valkey : k => m.instance_name }
}

output "resolved_zone" {
  value = { for k, m in module.valkey : k => m.resolved_zone }
}

output "psc_connectivity_mode" {
  value = { for k, m in module.valkey : k => m.psc_connectivity_mode }
}

output "shared_vpc_network_self_link" {
  description = "Self link of the existing Shared VPC network used, per instance. Null unless psc_connectivity_mode = SHARED_VPC."
  value       = { for k, m in module.valkey : k => m.shared_vpc_network_self_link }
}

output "psc_attachment_details" {
  value = { for k, m in module.valkey : k => m.psc_attachment_details }
}

output "discovery_endpoints" {
  description = "Actual PSC endpoints (address, port, network) created for the primary instance, per instance."
  value       = { for k, m in module.valkey : k => m.discovery_endpoints }
}

output "secondary_instance_id" {
  value = { for k, m in module.valkey : k => m.secondary_instance_id }
}

output "secondary_psc_attachment_details" {
  value = { for k, m in module.valkey : k => m.secondary_psc_attachment_details }
}

output "secondary_discovery_endpoints" {
  description = "Actual PSC endpoints (address, port, network) created for the secondary (DR) instance, per instance."
  value       = { for k, m in module.valkey : k => m.secondary_discovery_endpoints }
}
