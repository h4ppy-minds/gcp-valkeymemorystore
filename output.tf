output "instance_id" {
  value = module.valkey.instance_id
}

output "instance_name" {
  value = module.valkey.instance_name
}

output "resolved_zone" {
  value = module.valkey.resolved_zone
}

output "psc_connectivity_mode" {
  value = module.valkey.psc_connectivity_mode
}

output "shared_vpc_network_self_link" {
  description = "Self link of the existing Shared VPC network used. Null unless psc_connectivity_mode = SHARED_VPC."
  value       = module.valkey.shared_vpc_network_self_link
}

output "psc_attachment_details" {
  value = module.valkey.psc_attachment_details
}
output "secondary_instance_id" {
  value = module.valkey.secondary_instance_id
}

output "secondary_psc_attachment_details" {
  value = module.valkey.secondary_psc_attachment_details
}
