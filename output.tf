output "valkey_instances" {
  description = "..."
  value = {
    for key, inst in module.valkey : key => merge(
      {
        instance_id                      = inst.instance_id
        instance_name                    = inst.instance_name
        discovery_endpoints              = inst.discovery_endpoints
        psc_attachment_details           = inst.psc_attachment_details
        psc_connectivity_mode            = inst.psc_connectivity_mode
        resolved_zone                    = inst.resolved_zone
        secondary_discovery_endpoints    = inst.secondary_discovery_endpoints
        secondary_instance_id            = inst.secondary_instance_id
        secondary_psc_attachment_details = inst.secondary_psc_attachment_details
        shared_vpc_network_self_link     = inst.shared_vpc_network_self_link
      },
      {
        alerting = {
          alert_policy_ids              = module.valkey_alerts[key].alert_policy_ids
          notification_channel_ids      = module.valkey_alerts[key].notification_channel_ids
          replication_lag_alert_enabled = module.valkey_alerts[key].replication_lag_alert_enabled
        }
      }
    )
  }
}
