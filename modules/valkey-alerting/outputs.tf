output "critical_notification_channel_ids" {
  description = "All critical-severity notification channel IDs (requester + platform)."
  value       = local.critical_channel_ids
}

output "warning_notification_channel_ids" {
  description = "All warning-severity notification channel IDs (requester + platform)."
  value       = local.warning_channel_ids
}

output "replication_lag_alert_enabled" {
  description = "Whether the replication-lag alert policy was actually created (see enable_replication_lag_alert / replica_count)."
  value       = local.enable_replication_lag_alert
}

output "alert_policy_ids" {
  description = "Map of alert policy name to resource ID, for quick reference or linking from a runbook. replication_lag is null when the instance has no replicas and the alert wasn't created."
  value = {
    instance_down                 = google_monitoring_alert_policy.instance_down.name
    cpu_warning                   = google_monitoring_alert_policy.cpu_warning.name
    cpu_critical                  = google_monitoring_alert_policy.cpu_critical.name
    memory_warning                = google_monitoring_alert_policy.memory_warning.name
    memory_critical               = google_monitoring_alert_policy.memory_critical.name
    rejected_connections_warning  = google_monitoring_alert_policy.rejected_connections_warning.name
    rejected_connections_critical = google_monitoring_alert_policy.rejected_connections_critical.name
    connected_clients_high        = google_monitoring_alert_policy.connected_clients_high.name
    replication_lag               = try(google_monitoring_alert_policy.replication_lag[0].name, null)
  }
}
