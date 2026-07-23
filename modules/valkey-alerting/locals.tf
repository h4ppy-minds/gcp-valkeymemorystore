locals {
  # Explicit override wins; otherwise default on only when the instance
  # actually has replicas.
  enable_replication_lag_alert = var.enable_replication_lag_alert != null ? var.enable_replication_lag_alert : var.replica_count > 0

  ############################################
  # Notification channels — no severity split anymore. Every alert this
  # module creates (WARNING or CRITICAL) notifies the same combined set of
  # app-team + platform-team addresses.
  #
  # Cloud Monitoring's "email" channel type only accepts ONE address per
  # channel (labels.email_address) — there's no way to put a comma-joined
  # "appteam@x.com,platform@x.com" into a single channel and have the API
  # accept it. So this creates one channel per unique address across both
  # sets, and attaches the whole set to every alert policy — functionally
  # the same "both teams get every alert" outcome, just via N channels
  # instead of one multi-recipient one.
  ############################################

  all_notification_emails = setunion(var.appteam_emails, var.platformteam_emails)

  notification_channel_specs = { for email in local.all_notification_emails : email => {
    email        = email
    display_name = "Valkey Alerts - ${email}"
  } }

  # Flattened channel ID list, attached to every alert definition below.
  notification_channel_ids = [
    for email in local.all_notification_emails : google_monitoring_notification_channel.email[email].id
  ]

  ############################################
  # Alert definitions — this table IS the alert set. Each entry is fed into
  # one instantiation of module/_alert_policy (see alert_policies.tf), the
  # same way modules/valkey/main.tf calls module/_instance once per instance
  # instead of hand-duplicating the resource. Adding a new alert means
  # adding one map entry here, not a new ~30-line resource block.
  ############################################

  alert_definitions = merge(
    {
      instance_down = {
        display_name              = "[CRITICAL][${var.region}] Valkey instance node unhealthy"
        condition_display_name    = "Node health check failing"
        severity                  = "CRITICAL"
        resource_type             = var.resource_type_instance_node
        metric_type               = var.metric_type_instance_health
        comparison                = "COMPARISON_LT"
        threshold_value           = 1
        duration                  = var.critical_alignment_period
        alignment_period          = var.critical_alignment_period
        per_series_aligner        = "ALIGN_FRACTION_TRUE"
        cross_series_reducer      = null
        group_by_fields           = []
        enable_absent_check       = true
        absent_duration           = var.instance_down_absent_duration
        absent_alignment_period   = "60s"
        absent_per_series_aligner = "ALIGN_FRACTION_TRUE"
        auto_close                = var.critical_auto_close
      }

      cpu_warning = {
        display_name              = "[WARNING][${var.region}] Valkey CPU utilization high"
        condition_display_name    = "CPU maximum_utilization > ${var.cpu_warning_threshold}"
        severity                  = "WARNING"
        resource_type             = var.resource_type_instance
        metric_type               = var.metric_type_cpu
        comparison                = "COMPARISON_GT"
        threshold_value           = var.cpu_warning_threshold
        duration                  = var.warning_duration
        alignment_period          = "60s"
        per_series_aligner        = "ALIGN_MEAN"
        cross_series_reducer      = null
        group_by_fields           = []
        enable_absent_check       = false
        absent_duration           = null
        absent_alignment_period   = null
        absent_per_series_aligner = null
        auto_close                = null
      }

      cpu_critical = {
        display_name              = "[CRITICAL][${var.region}] Valkey CPU utilization critical"
        condition_display_name    = "CPU maximum_utilization > ${var.cpu_critical_threshold}"
        severity                  = "CRITICAL"
        resource_type             = var.resource_type_instance
        metric_type               = var.metric_type_cpu
        comparison                = "COMPARISON_GT"
        threshold_value           = var.cpu_critical_threshold
        duration                  = var.cpu_critical_duration
        alignment_period          = "60s"
        per_series_aligner        = "ALIGN_MEAN"
        cross_series_reducer      = null
        group_by_fields           = []
        enable_absent_check       = false
        absent_duration           = null
        absent_alignment_period   = null
        absent_per_series_aligner = null
        auto_close                = var.critical_auto_close
      }

      memory_warning = {
        display_name              = "[WARNING][${var.region}] Valkey memory utilization high"
        condition_display_name    = "Memory maximum_utilization > ${var.memory_warning_threshold}"
        severity                  = "WARNING"
        resource_type             = var.resource_type_instance
        metric_type               = var.metric_type_memory
        comparison                = "COMPARISON_GT"
        threshold_value           = var.memory_warning_threshold
        duration                  = var.warning_duration
        alignment_period          = "60s"
        per_series_aligner        = "ALIGN_MEAN"
        cross_series_reducer      = null
        group_by_fields           = []
        enable_absent_check       = false
        absent_duration           = null
        absent_alignment_period   = null
        absent_per_series_aligner = null
        auto_close                = null
      }

      memory_critical = {
        display_name              = "[CRITICAL][${var.region}] Valkey memory utilization critical"
        condition_display_name    = "Memory maximum_utilization > ${var.memory_critical_threshold}"
        severity                  = "CRITICAL"
        resource_type             = var.resource_type_instance
        metric_type               = var.metric_type_memory
        comparison                = "COMPARISON_GT"
        threshold_value           = var.memory_critical_threshold
        duration                  = var.memory_critical_duration
        alignment_period          = "60s"
        per_series_aligner        = "ALIGN_MEAN"
        cross_series_reducer      = null
        group_by_fields           = []
        enable_absent_check       = false
        absent_duration           = null
        absent_alignment_period   = null
        absent_per_series_aligner = null
        auto_close                = var.critical_auto_close
      }

      rejected_connections_warning = {
        display_name              = "[WARNING][${var.region}] Valkey rejected connections detected"
        condition_display_name    = "rejected_connections_count > ${var.rejected_connections_warning_threshold}"
        severity                  = "WARNING"
        resource_type             = var.resource_type_instance_node
        metric_type               = var.metric_type_rejected_connections
        comparison                = "COMPARISON_GT"
        threshold_value           = var.rejected_connections_warning_threshold
        duration                  = var.rejected_connections_duration
        alignment_period          = var.rejected_connections_duration
        per_series_aligner        = "ALIGN_SUM"
        cross_series_reducer      = "REDUCE_SUM"
        group_by_fields           = ["resource.label.instance_id"]
        enable_absent_check       = false
        absent_duration           = null
        absent_alignment_period   = null
        absent_per_series_aligner = null
        auto_close                = null
      }

      rejected_connections_critical = {
        display_name              = "[CRITICAL][${var.region}] Valkey rejected connections critical"
        condition_display_name    = "rejected_connections_count > ${var.rejected_connections_critical_threshold}"
        severity                  = "CRITICAL"
        resource_type             = var.resource_type_instance_node
        metric_type               = var.metric_type_rejected_connections
        comparison                = "COMPARISON_GT"
        threshold_value           = var.rejected_connections_critical_threshold
        duration                  = var.rejected_connections_duration
        alignment_period          = var.rejected_connections_duration
        per_series_aligner        = "ALIGN_SUM"
        cross_series_reducer      = "REDUCE_SUM"
        group_by_fields           = ["resource.label.instance_id"]
        enable_absent_check       = false
        absent_duration           = null
        absent_alignment_period   = null
        absent_per_series_aligner = null
        auto_close                = var.critical_auto_close
      }

      connected_clients_high = {
        display_name              = "[WARNING][${var.region}] Valkey connected clients elevated"
        condition_display_name    = "connected_clients > ${var.connected_clients_warning_threshold}"
        severity                  = "WARNING"
        resource_type             = var.resource_type_instance_node
        metric_type               = var.metric_type_connected_clients
        comparison                = "COMPARISON_GT"
        threshold_value           = var.connected_clients_warning_threshold
        duration                  = var.warning_duration
        alignment_period          = "60s"
        per_series_aligner        = "ALIGN_MAX"
        cross_series_reducer      = null
        group_by_fields           = []
        enable_absent_check       = false
        absent_duration           = null
        absent_alignment_period   = null
        absent_per_series_aligner = null
        auto_close                = null
      }
    },
    # Only added to the map when applicable — module.alert_policies (a
    # for_each over this map) simply won't create it otherwise, replacing
    # the old count = local.enable_replication_lag_alert ? 1 : 0 pattern.
    local.enable_replication_lag_alert ? {
      replication_lag = {
        display_name              = "[WARNING][${var.region}] Valkey replication lag high"
        condition_display_name    = "maximum_offset_diff > ${var.replication_lag_warning_bytes} bytes"
        severity                  = "WARNING"
        resource_type             = var.resource_type_instance
        metric_type               = var.metric_type_replication_lag
        comparison                = "COMPARISON_GT"
        threshold_value           = var.replication_lag_warning_bytes
        duration                  = var.warning_duration
        alignment_period          = "60s"
        per_series_aligner        = "ALIGN_MAX"
        cross_series_reducer      = null
        group_by_fields           = []
        enable_absent_check       = false
        absent_duration           = null
        absent_alignment_period   = null
        absent_per_series_aligner = null
        auto_close                = null
      }
    } : {}
  )
}
