############################################
# Cloud Monitoring alert policies + email notification channels for one
# Memorystore for Valkey instance (identified by var.instance_id — this
# module creates no compute/storage resources of its own).
#
# This is deliberately its own module, separate from the one that
# creates the instance (terraform-google-valkey). Reasoning: a change to
# who gets notified — adding, removing, or swapping an email address —
# should never require a plan/apply against the instance's
# infrastructure, and shouldn't have to go through whatever change
# process governs the instance itself. Wiring alerting to the instance
# happens by passing instance_id/location as inputs, not by nesting one
# module inside the other.
#
# This module also has no submodules — everything is in this root path.
# Every alert policy is one instantiation of the generic
# google_monitoring_alert_policy resource below, driven by
# local.alert_definitions (alerts.tf) via for_each, rather than a
# separate per-alert module call.
#
# To add a new alert: add one entry to local.alert_definitions in
# alerts.tf. Nothing in this file changes.
############################################

# One notification channel per unique address across appteam_emails and
# platformteam_emails combined (see local.notification_channel_specs) —
# every address gets exactly one channel regardless of which team's list
# it came from. Created in var.project_id because notification channels
# are project-scoped and the alert policies below live in var.project_id
# too — a channel in a different project cannot be attached to these
# policies.
resource "google_monitoring_notification_channel" "email" {
  for_each     = local.notification_channel_specs
  project      = var.project_id
  display_name = each.value.display_name
  type         = "email"
  labels = {
    email_address = each.value.email
  }
}

resource "google_monitoring_alert_policy" "this" {
  for_each = local.alert_definitions

  project      = var.project_id
  display_name = each.value.display_name
  combiner     = "OR"
  severity     = each.value.severity

  conditions {
    display_name = each.value.condition_display_name
    condition_threshold {
      filter          = "resource.type=\"${each.value.resource_type}\" AND resource.labels.instance_id=\"${var.instance_id}\" AND metric.type=\"${each.value.metric_type}\""
      comparison      = each.value.comparison
      threshold_value = each.value.threshold_value
      duration        = each.value.duration
      aggregations {
        alignment_period     = each.value.alignment_period
        per_series_aligner   = each.value.per_series_aligner
        cross_series_reducer = each.value.cross_series_reducer
        group_by_fields      = length(each.value.group_by_fields) > 0 ? each.value.group_by_fields : null
      }
    }
  }

  # Only added for alerts that opt in (instance_down) — fires if the
  # metric stops reporting entirely instead of just reporting a bad
  # value, which covers silent failure modes a pure threshold condition
  # would miss.
  dynamic "conditions" {
    for_each = each.value.enable_absent_check ? [1] : []
    content {
      display_name = "${each.value.condition_display_name} — metric absent"
      condition_absent {
        filter   = "resource.type=\"${each.value.resource_type}\" AND resource.labels.instance_id=\"${var.instance_id}\" AND metric.type=\"${each.value.metric_type}\""
        duration = coalesce(each.value.absent_duration, "300s")
        aggregations {
          alignment_period   = coalesce(each.value.absent_alignment_period, "60s")
          per_series_aligner = coalesce(each.value.absent_per_series_aligner, "ALIGN_MIN")
        }
      }
    }
  }

  notification_channels = local.notification_channel_ids

  dynamic "alert_strategy" {
    for_each = each.value.auto_close != null ? [1] : []
    content {
      auto_close = each.value.auto_close
    }
  }
}
