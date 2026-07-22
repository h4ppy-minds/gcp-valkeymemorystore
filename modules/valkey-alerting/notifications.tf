############################################
# Requester channels — this is the "alert to the emails the requester
# gave us" path. Created in var.project_id because notification channels
# are project-scoped and the alert policies below live in var.project_id
# too — a channel in a different project simply cannot be attached to
# these policies, regardless of who "owns" the email address.
############################################

resource "google_monitoring_notification_channel" "requester_critical" {
  for_each     = toset(var.requester_critical_emails)
  project      = var.project_id
  display_name = "Requester - Critical - ${each.value}"
  type         = "email"
  labels = {
    email_address = each.value
  }
}

resource "google_monitoring_notification_channel" "requester_warning" {
  for_each     = toset(local.effective_requester_warning_emails)
  project      = var.project_id
  display_name = "Requester - Warning - ${each.value}"
  type         = "email"
  labels = {
    email_address = each.value
  }
}

############################################
# Platform (host project) channels — optional standing on-call list,
# cc'd on every instance this module is used for.
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

locals {
  # Flattened channel ID lists reused across every alert policy below.
  critical_channel_ids = concat(
    [for c in google_monitoring_notification_channel.requester_critical : c.id],
    [for c in google_monitoring_notification_channel.platform_critical : c.id],
  )

  warning_channel_ids = concat(
    [for c in google_monitoring_notification_channel.requester_warning : c.id],
    [for c in google_monitoring_notification_channel.platform_warning : c.id],
  )
}
