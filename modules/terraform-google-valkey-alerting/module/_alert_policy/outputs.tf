output "id" {
  description = "Resource ID of the alert policy."
  value       = google_monitoring_alert_policy.this.id
}

output "name" {
  description = "Fully qualified resource name of the alert policy (e.g. projects/.../alertPolicies/...)."
  value       = google_monitoring_alert_policy.this.name
}
