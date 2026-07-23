resource "google_monitoring_alert_policy" "this" {
  project      = var.project_id
  display_name = var.display_name
  combiner     = "OR"
  severity     = var.severity

  conditions {
    display_name = var.condition_display_name
    condition_threshold {
      filter          = "resource.type=\"${var.resource_type}\" AND resource.labels.instance_id=\"${var.instance_id}\" AND metric.type=\"${var.metric_type}\""
      comparison      = var.comparison
      threshold_value = var.threshold_value
      duration        = var.duration
      aggregations {
        alignment_period     = var.alignment_period
        per_series_aligner   = var.per_series_aligner
        cross_series_reducer = var.cross_series_reducer
        group_by_fields      = length(var.group_by_fields) > 0 ? var.group_by_fields : null
      }
    }
  }

  # Only added for alerts that opt in (instance_down) — fires if the metric
  # stops reporting entirely instead of just reporting a bad value, which
  # covers silent failure modes a pure threshold condition would miss.
  dynamic "conditions" {
    for_each = var.enable_absent_check ? [1] : []
    content {
      display_name = "${var.condition_display_name} — metric absent"
      condition_absent {
        filter   = "resource.type=\"${var.resource_type}\" AND resource.labels.instance_id=\"${var.instance_id}\" AND metric.type=\"${var.metric_type}\""
        duration = var.absent_duration
        aggregations {
          alignment_period   = var.absent_alignment_period
          per_series_aligner = var.absent_per_series_aligner
        }
      }
    }
  }

  notification_channels = var.notification_channels

  dynamic "alert_strategy" {
    for_each = var.auto_close != null ? [1] : []
    content {
      auto_close = var.auto_close
    }
  }
}
