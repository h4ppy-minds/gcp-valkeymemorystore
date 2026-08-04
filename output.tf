output "valkey_instances" {
  description = "One entry per onboarding request that's enabled for this environment (request_type != delete, environment == var.env). Alerting fields are nested under .alerting — they come from module.valkey_alerts now (a separate module call, keyed the same way as module.valkey), not from module.valkey itself."
  value = {
    for key, inst in module.valkey : key => {
      instance_id                      = inst.instance_id
      instance_name                    = inst.instance_name
      discovery_endpoints              = inst.discovery_endpoints
      psc_attachment_details           = inst.psc_attachment_details
      psc_connectivity_mode            = inst.psc_connectivity_mode
      resolved_zone                    = inst.resolved_zone
      resolved_location                = inst.resolved_location
      secondary_discovery_endpoints    = inst.secondary_discovery_endpoints
      secondary_instance_id            = inst.secondary_instance_id
      secondary_psc_attachment_details = inst.secondary_psc_attachment_details
      shared_vpc_network_self_link     = inst.shared_vpc_network_self_link

      alerting = {
        enabled                       = module.valkey_alerts[key].alerting_enabled
        alert_policy_ids              = module.valkey_alerts[key].alert_policy_ids
        notification_channel_ids      = module.valkey_alerts[key].notification_channel_ids
        replication_lag_alert_enabled = module.valkey_alerts[key].replication_lag_alert_enabled
      }
    }
  }
}

output "derived_topology_by_instance" {
  description = "Debug helper: shows the deployment_topology, secondary_location, and resolved rdb_snapshot_start_time that locals.tf derived for each onboarded instance, before it was even sent to the module — useful for reviewing an onboarding PR's actual effect without running plan."
  value = {
    for name, cfg in local.valkey : name => {
      deployment_topology     = cfg.deployment_topology
      secondary_location      = cfg.secondary_location
      rdb_snapshot_start_time = cfg.rdb_snapshot_start_time
    }
  }
}
