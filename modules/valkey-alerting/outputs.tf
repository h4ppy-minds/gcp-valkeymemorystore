output "notification_channel_ids" {
  description = "IDs of every notification channel created — one per unique address across appteam_emails and platformteam_emails. Attached to every alert this module creates."
  value       = local.notification_channel_ids
}

output "replication_lag_alert_enabled" {
  description = "Whether the replication-lag alert policy was actually created (see enable_replication_lag_alert / replica_count)."
  value       = local.enable_replication_lag_alert
}

output "alert_policy_ids" {
  description = "Map of alert name to alert policy resource name, for quick reference or linking from a runbook. Keys come straight from local.alert_definitions, so replication_lag simply isn't a key here when it wasn't created — no null to check for."
  value = {
    for k, m in module.alert_policies : k => m.name
  }
}
