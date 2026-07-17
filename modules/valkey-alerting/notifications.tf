locals {
  service_project_id = coalesce(var.service_project_id, var.project_id)
}

############################################
# Platform team channels
############################################

resource "google_monitoring_notification_channel" "platform_critical" {
  for_each     = toset(var.platform_critical_emails)
  project      = var.project_id
  display_name = "Platform Team - Critical - ${each.value}"
  type         = "email"
  labels = {
    email_address = each.value
  }
}

resource "google_monitoring_notification_channel" "platform_warning" {
  for_each     = toset(var.platform_warning_emails)
  project      = var.project_id
  display_name = "Platform Team - Warning - ${each.value}"
  type         = "email"
  labels = {
    email_address = each.value
  }
}

############################################
# Service project team channels
############################################

resource "google_monitoring_notification_channel" "service_team_critical" {
  for_each     = toset(var.service_team_critical_emails)
  project      = local.service_project_id
  display_name = "Service Team - Critical - ${each.value}"
  type         = "email"
  labels = {
    email_address = each.value
  }
}

resource "google_monitoring_notification_channel" "service_team_warning" {
  for_each     = toset(var.service_team_warning_emails)
  project      = local.service_project_id
  display_name = "Service Team - Warning - ${each.value}"
  type         = "email"
  labels = {
    email_address = each.value
  }
}

locals {
  # Flattened channel ID lists reused across every alert policy below.
  critical_channel_ids = concat(
    [for c in google_monitoring_notification_channel.platform_critical : c.id],
    [for c in google_monitoring_notification_channel.service_team_critical : c.id],
  )

  warning_channel_ids = concat(
    [for c in google_monitoring_notification_channel.platform_warning : c.id],
    [for c in google_monitoring_notification_channel.service_team_warning : c.id],
  )
}
