############################################
# CRITICAL — Instance / node down
############################################

resource "google_monitoring_alert_policy" "instance_down" {
  project      = var.project_id
  display_name = "[CRITICAL][${var.region}] Valkey instance node unhealthy"
  combiner     = "OR"
  severity     = "CRITICAL"

  conditions {
    display_name = "Node health check failing"
    condition_threshold {
      filter          = "resource.type=\"memorystore_instance\" AND resource.labels.instance_id=\"${var.instance_id}\" AND metric.type=\"memorystore.googleapis.com/node/server/healthy\""
      comparison      = "COMPARISON_LT"
      threshold_value = 1
      duration        = var.critical_alignment_period
      aggregations {
        alignment_period   = var.critical_alignment_period
        per_series_aligner = "ALIGN_MIN"
      }
    }
  }

  # Also fires if the metric stops reporting entirely (e.g. regional outage),
  # not just when it reports unhealthy.
  conditions {
    display_name = "Node health metric absent"
    condition_absent {
      filter   = "resource.type=\"memorystore_instance\" AND resource.labels.instance_id=\"${var.instance_id}\" AND metric.type=\"memorystore.googleapis.com/node/server/healthy\""
      duration = "300s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MIN"
      }
    }
  }

  notification_channels = local.critical_channel_ids
  alert_strategy {
    auto_close = var.critical_auto_close
  }
}

############################################
# CPU utilization — WARNING and CRITICAL
############################################

resource "google_monitoring_alert_policy" "cpu_warning" {
  project      = var.project_id
  display_name = "[WARNING][${var.region}] Valkey CPU utilization high"
  combiner     = "OR"
  severity     = "WARNING"

  conditions {
    display_name = "CPU maximum_utilization > ${var.cpu_warning_threshold}"
    condition_threshold {
      filter          = "resource.type=\"memorystore_instance\" AND resource.labels.instance_id=\"${var.instance_id}\" AND metric.type=\"memorystore.googleapis.com/instance/cpu/maximum_utilization\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.cpu_warning_threshold
      duration        = var.warning_duration
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = local.warning_channel_ids
}

resource "google_monitoring_alert_policy" "cpu_critical" {
  project      = var.project_id
  display_name = "[CRITICAL][${var.region}] Valkey CPU utilization critical"
  combiner     = "OR"
  severity     = "CRITICAL"

  conditions {
    display_name = "CPU maximum_utilization > ${var.cpu_critical_threshold}"
    condition_threshold {
      filter          = "resource.type=\"memorystore_instance\" AND resource.labels.instance_id=\"${var.instance_id}\" AND metric.type=\"memorystore.googleapis.com/instance/cpu/maximum_utilization\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.cpu_critical_threshold
      duration        = "180s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = local.critical_channel_ids
  alert_strategy {
    auto_close = var.critical_auto_close
  }
}

############################################
# Memory utilization — WARNING and CRITICAL
############################################

resource "google_monitoring_alert_policy" "memory_warning" {
  project      = var.project_id
  display_name = "[WARNING][${var.region}] Valkey memory utilization high"
  combiner     = "OR"
  severity     = "WARNING"

  conditions {
    display_name = "Memory maximum_utilization > ${var.memory_warning_threshold}"
    condition_threshold {
      filter          = "resource.type=\"memorystore_instance\" AND resource.labels.instance_id=\"${var.instance_id}\" AND metric.type=\"memorystore.googleapis.com/instance/memory/maximum_utilization\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.memory_warning_threshold
      duration        = var.warning_duration
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = local.warning_channel_ids
}

resource "google_monitoring_alert_policy" "memory_critical" {
  project      = var.project_id
  display_name = "[CRITICAL][${var.region}] Valkey memory utilization critical"
  combiner     = "OR"
  severity     = "CRITICAL"

  conditions {
    display_name = "Memory maximum_utilization > ${var.memory_critical_threshold}"
    condition_threshold {
      filter          = "resource.type=\"memorystore_instance\" AND resource.labels.instance_id=\"${var.instance_id}\" AND metric.type=\"memorystore.googleapis.com/instance/memory/maximum_utilization\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.memory_critical_threshold
      duration        = "180s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = local.critical_channel_ids
  alert_strategy {
    auto_close = var.critical_auto_close
  }
}

############################################
# Rejected connections — WARNING and CRITICAL
#
# WARNING: any sustained rejection is worth a look. CRITICAL: this is
# client-visible connection failures, sustained and high — treated with
# the same two-tier pattern as CPU/memory rather than warning-only,
# since it means real requests are failing right now, not just trending
# toward a problem.
############################################

resource "google_monitoring_alert_policy" "rejected_connections_warning" {
  project      = var.project_id
  display_name = "[WARNING][${var.region}] Valkey rejected connections detected"
  combiner     = "OR"
  severity     = "WARNING"

  conditions {
    display_name = "rejected_connections_count > ${var.rejected_connections_warning_threshold}"
    condition_threshold {
      filter          = "resource.type=\"memorystore_instance\" AND resource.labels.instance_id=\"${var.instance_id}\" AND metric.type=\"memorystore.googleapis.com/instance/node/stats/rejected_connections_count\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.rejected_connections_warning_threshold
      duration        = "60s"
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.instance_id"]
      }
    }
  }

  notification_channels = local.warning_channel_ids
}

resource "google_monitoring_alert_policy" "rejected_connections_critical" {
  project      = var.project_id
  display_name = "[CRITICAL][${var.region}] Valkey rejected connections critical"
  combiner     = "OR"
  severity     = "CRITICAL"

  conditions {
    display_name = "rejected_connections_count > ${var.rejected_connections_critical_threshold}"
    condition_threshold {
      filter          = "resource.type=\"memorystore_instance\" AND resource.labels.instance_id=\"${var.instance_id}\" AND metric.type=\"memorystore.googleapis.com/instance/node/stats/rejected_connections_count\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.rejected_connections_critical_threshold
      duration        = "60s"
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.instance_id"]
      }
    }
  }

  notification_channels = local.critical_channel_ids
  alert_strategy {
    auto_close = var.critical_auto_close
  }
}

############################################
# WARNING — Connected clients elevated (backpressure)
############################################

resource "google_monitoring_alert_policy" "connected_clients_high" {
  project      = var.project_id
  display_name = "[WARNING][${var.region}] Valkey connected clients elevated"
  combiner     = "OR"
  severity     = "WARNING"

  conditions {
    display_name = "connected_clients > ${var.connected_clients_warning_threshold}"
    condition_threshold {
      filter          = "resource.type=\"memorystore_instance\" AND resource.labels.instance_id=\"${var.instance_id}\" AND metric.type=\"memorystore.googleapis.com/instance/node/clients/connected_clients\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.connected_clients_warning_threshold
      duration        = var.warning_duration
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  notification_channels = local.warning_channel_ids
}

############################################
# WARNING — Replication lag (HA / DR signal)
############################################

resource "google_monitoring_alert_policy" "replication_lag" {
  count = local.enable_replication_lag_alert ? 1 : 0

  project      = var.project_id
  display_name = "[WARNING][${var.region}] Valkey replication lag high"
  combiner     = "OR"
  severity     = "WARNING"

  conditions {
    display_name = "maximum_offset_diff > ${var.replication_lag_warning_bytes} bytes"
    condition_threshold {
      filter          = "resource.type=\"memorystore_instance\" AND resource.labels.instance_id=\"${var.instance_id}\" AND metric.type=\"memorystore.googleapis.com/instance/node/replication/maximum_offset_diff\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.replication_lag_warning_bytes
      duration        = var.warning_duration
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  notification_channels = local.warning_channel_ids
}
