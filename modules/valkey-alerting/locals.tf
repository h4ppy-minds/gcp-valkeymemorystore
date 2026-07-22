locals {
  # Warnings fall back to the requester's critical list so a WARNING
  # alert never has nowhere to go just because warning emails weren't
  # separately specified.
  effective_requester_warning_emails = length(var.requester_warning_emails) > 0 ? var.requester_warning_emails : var.requester_critical_emails

  # Explicit override wins; otherwise default on only when the instance
  # actually has replicas.
  enable_replication_lag_alert = var.enable_replication_lag_alert != null ? var.enable_replication_lag_alert : var.replica_count > 0
}
