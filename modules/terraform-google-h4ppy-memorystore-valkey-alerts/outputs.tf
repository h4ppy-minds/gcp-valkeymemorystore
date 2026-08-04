output "alerting_enabled" {
  description = "Whether this module call created alerting resources at all (see enable_alerting)."
  value       = var.enable_alerting
}

output "notification_channel_ids" {
  description = "IDs of every notification channel created — one per unique address across appteam_emails and platformteam_emails. Attached to every alert this module creates. Empty when enable_alerting = false."
  value       = local.notification_channel_ids
}

output "replication_lag_alert_enabled" {
  description = "Whether the replication-lag alert policy was actually created (see var.enable_replication_lag_alert)."
  value       = var.enable_alerting ? var.enable_replication_lag_alert : false
}

output "alert_policy_ids" {
  description = "Map of alert name to alert policy resource name, for quick reference or linking from a runbook. Keys come straight from local.alert_definitions, so replication_lag simply isn't a key here when it wasn't created — no null to check for. Empty map when enable_alerting = false."
  value = {
    for k, p in google_monitoring_alert_policy.this : k => p.name
  }
}
