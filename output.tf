output "valkey_instances" {
  description = "Per-instance details, keyed the same way as module.valkey (i.e. by manifest entry name, e.g. \"example1\"). Access a single field as valkey_instances[\"example1\"].instance_id, etc. secondary_* fields are null/empty for STANDALONE and HA instances."
  value = {
    for k, m in module.valkey : k => {
      instance_id                      = m.instance_id
      instance_name                    = m.instance_name
      resolved_zone                    = m.resolved_zone
      psc_connectivity_mode            = m.psc_connectivity_mode
      shared_vpc_network_self_link     = m.shared_vpc_network_self_link
      psc_attachment_details           = m.psc_attachment_details
      discovery_endpoints              = m.discovery_endpoints
      secondary_instance_id            = m.secondary_instance_id
      secondary_psc_attachment_details = m.secondary_psc_attachment_details
      secondary_discovery_endpoints    = m.secondary_discovery_endpoints
    }
  }
}
