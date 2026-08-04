############################################################################
# alerts.tf — everything about alerting: fixed defaults + the logic that
# builds the alert set and notification channels.
#
# By design, this module exposes only these alerting-routing variables
# (see variables.tf):
#   var.enable_alerting            — on/off switch
#   var.appteam_emails             — required when enabled
#   var.platformteam_emails        — optional, in addition to appteam_emails
#   var.enable_replication_lag_alert — caller-supplied, since this module
#                                     doesn't know the target instance's
#                                     replica_count
#
# Every threshold, duration, and metric/resource-type string below is a
# fixed constant, not a variable — callers cannot pass or override
# individual alert tuning through this module. That's intentional: this
# module's alerting is meant to ship as "on with good defaults, or off,"
# not retuned per caller. If a threshold genuinely needs to change, edit
# local.alert_defaults right here — there is no variable path for it.
#
# Layout of this file, top to bottom:
#   1. local.alert_defaults — every literal alerting constant (thresholds,
#                            durations, metric/resource type strings).
#                            Edit values here to change alerting behavior
#                            for every caller of this module.
#   2. Notification channel locals — dedupes appteam_emails +
#                            platformteam_emails into one channel spec per
#                            unique address.
#   3. local.alert_definitions — the table that IS the alert set, fed
#                            into main.tf's alert-policy resource
#                            for_each. Adding a new alert means adding one
#                            entry here; main.tf does not change.
############################################################################

locals {

  ##########################################################################
  # 1. FIXED ALERTING CONSTANTS — not exposed as variables. Edit here to
  # change alerting behavior module-wide; there is nothing to override
  # from a caller.
  ##########################################################################
  alert_defaults = {
    # --- thresholds (Google's general production-cache guidance) ---
    cpu_warning_threshold                   = 0.8
    cpu_critical_threshold                  = 0.95
    memory_warning_threshold                = 0.8
    memory_critical_threshold               = 0.95
    rejected_connections_warning_threshold  = 1
    rejected_connections_critical_threshold = 50
    connected_clients_warning_threshold     = 8000
    replication_lag_warning_bytes           = 67108864 # 64MB — wrong for highmem-xlarge node_type, edit here if that's a common shape for you

    # --- timing knobs ---
    critical_alignment_period     = "60s"
    warning_duration              = "300s"
    cpu_critical_duration         = "180s"
    memory_critical_duration      = "180s"
    rejected_connections_duration = "60s"
    instance_down_absent_duration = "300s"
    critical_auto_close           = "1800s"

    # --- metric / resource type strings (verified against a live
    # project's monitoredResourceDescriptors + the supported-monitoring-
    # metrics reference; re-verify after a Google API change) ---
    resource_type_instance           = "memorystore.googleapis.com/Instance"
    resource_type_instance_node      = "memorystore.googleapis.com/InstanceNode"
    metric_type_instance_health      = "memorystore.googleapis.com/instance/node/server/healthy"
    metric_type_cpu                  = "memorystore.googleapis.com/instance/cpu/maximum_utilization"
    metric_type_memory               = "memorystore.googleapis.com/instance/memory/maximum_utilization"
    metric_type_rejected_connections = "memorystore.googleapis.com/instance/node/stats/rejected_connections_count"
    metric_type_connected_clients    = "memorystore.googleapis.com/instance/node/clients/connected_clients"
    metric_type_replication_lag      = "memorystore.googleapis.com/instance/replication/maximum_offset_diff"
  }

  ##########################################################################
  # 2. Notification channels — no severity split. Every alert this module
  # creates (WARNING or CRITICAL) notifies the same combined set of
  # app-team + platform-team addresses. Cloud Monitoring's "email" channel
  # type only accepts ONE address per channel, so this creates one channel
  # per unique address across both sets and attaches the whole set to
  # every alert policy. Empty (no-op) when enable_alerting = false.
  ##########################################################################

  all_notification_emails = var.enable_alerting ? setunion(var.appteam_emails, var.platformteam_emails) : []

  notification_channel_specs = var.enable_alerting ? { for email in local.all_notification_emails : email => {
    email        = email
    display_name = "Valkey Alerts - ${email}"
  } } : {}

  notification_channel_ids = [
    for email in local.all_notification_emails : google_monitoring_notification_channel.email[email].id
  ]

  ##########################################################################
  # 3. Alert definitions — this table IS the alert set. Each entry is fed
  # into one instantiation of module/_alert_policy (see main.tf), the same
  # way module/_instance is called once per instance instead of hand-
  # duplicating the resource. Adding a new alert means adding one map
  # entry here, not a new ~30-line resource block. Empty map entirely when
  # enable_alerting = false.
  ##########################################################################

  alert_definitions = var.enable_alerting ? merge(
    {
      instance_down = {
        display_name              = "[CRITICAL][${var.location}] Valkey instance node unhealthy"
        condition_display_name    = "Node health check failing"
        severity                  = "CRITICAL"
        resource_type             = local.alert_defaults.resource_type_instance_node
        metric_type               = local.alert_defaults.metric_type_instance_health
        comparison                = "COMPARISON_LT"
        threshold_value           = 1
        duration                  = local.alert_defaults.critical_alignment_period
        alignment_period          = local.alert_defaults.critical_alignment_period
        per_series_aligner        = "ALIGN_FRACTION_TRUE"
        cross_series_reducer      = null
        group_by_fields           = []
        enable_absent_check       = true
        absent_duration           = local.alert_defaults.instance_down_absent_duration
        absent_alignment_period   = "60s"
        absent_per_series_aligner = "ALIGN_FRACTION_TRUE"
        auto_close                = local.alert_defaults.critical_auto_close
      }

      cpu_warning = {
        display_name              = "[WARNING][${var.location}] Valkey CPU utilization high"
        condition_display_name    = "CPU maximum_utilization > ${local.alert_defaults.cpu_warning_threshold}"
        severity                  = "WARNING"
        resource_type             = local.alert_defaults.resource_type_instance
        metric_type               = local.alert_defaults.metric_type_cpu
        comparison                = "COMPARISON_GT"
        threshold_value           = local.alert_defaults.cpu_warning_threshold
        duration                  = local.alert_defaults.warning_duration
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
        display_name              = "[CRITICAL][${var.location}] Valkey CPU utilization critical"
        condition_display_name    = "CPU maximum_utilization > ${local.alert_defaults.cpu_critical_threshold}"
        severity                  = "CRITICAL"
        resource_type             = local.alert_defaults.resource_type_instance
        metric_type               = local.alert_defaults.metric_type_cpu
        comparison                = "COMPARISON_GT"
        threshold_value           = local.alert_defaults.cpu_critical_threshold
        duration                  = local.alert_defaults.cpu_critical_duration
        alignment_period          = "60s"
        per_series_aligner        = "ALIGN_MEAN"
        cross_series_reducer      = null
        group_by_fields           = []
        enable_absent_check       = false
        absent_duration           = null
        absent_alignment_period   = null
        absent_per_series_aligner = null
        auto_close                = local.alert_defaults.critical_auto_close
      }

      memory_warning = {
        display_name              = "[WARNING][${var.location}] Valkey memory utilization high"
        condition_display_name    = "Memory maximum_utilization > ${local.alert_defaults.memory_warning_threshold}"
        severity                  = "WARNING"
        resource_type             = local.alert_defaults.resource_type_instance
        metric_type               = local.alert_defaults.metric_type_memory
        comparison                = "COMPARISON_GT"
        threshold_value           = local.alert_defaults.memory_warning_threshold
        duration                  = local.alert_defaults.warning_duration
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
        display_name              = "[CRITICAL][${var.location}] Valkey memory utilization critical"
        condition_display_name    = "Memory maximum_utilization > ${local.alert_defaults.memory_critical_threshold}"
        severity                  = "CRITICAL"
        resource_type             = local.alert_defaults.resource_type_instance
        metric_type               = local.alert_defaults.metric_type_memory
        comparison                = "COMPARISON_GT"
        threshold_value           = local.alert_defaults.memory_critical_threshold
        duration                  = local.alert_defaults.memory_critical_duration
        alignment_period          = "60s"
        per_series_aligner        = "ALIGN_MEAN"
        cross_series_reducer      = null
        group_by_fields           = []
        enable_absent_check       = false
        absent_duration           = null
        absent_alignment_period   = null
        absent_per_series_aligner = null
        auto_close                = local.alert_defaults.critical_auto_close
      }

      rejected_connections_warning = {
        display_name              = "[WARNING][${var.location}] Valkey rejected connections detected"
        condition_display_name    = "rejected_connections_count > ${local.alert_defaults.rejected_connections_warning_threshold}"
        severity                  = "WARNING"
        resource_type             = local.alert_defaults.resource_type_instance_node
        metric_type               = local.alert_defaults.metric_type_rejected_connections
        comparison                = "COMPARISON_GT"
        threshold_value           = local.alert_defaults.rejected_connections_warning_threshold
        duration                  = local.alert_defaults.rejected_connections_duration
        alignment_period          = local.alert_defaults.rejected_connections_duration
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
        display_name              = "[CRITICAL][${var.location}] Valkey rejected connections critical"
        condition_display_name    = "rejected_connections_count > ${local.alert_defaults.rejected_connections_critical_threshold}"
        severity                  = "CRITICAL"
        resource_type             = local.alert_defaults.resource_type_instance_node
        metric_type               = local.alert_defaults.metric_type_rejected_connections
        comparison                = "COMPARISON_GT"
        threshold_value           = local.alert_defaults.rejected_connections_critical_threshold
        duration                  = local.alert_defaults.rejected_connections_duration
        alignment_period          = local.alert_defaults.rejected_connections_duration
        per_series_aligner        = "ALIGN_SUM"
        cross_series_reducer      = "REDUCE_SUM"
        group_by_fields           = ["resource.label.instance_id"]
        enable_absent_check       = false
        absent_duration           = null
        absent_alignment_period   = null
        absent_per_series_aligner = null
        auto_close                = local.alert_defaults.critical_auto_close
      }

      connected_clients_high = {
        display_name              = "[WARNING][${var.location}] Valkey connected clients elevated"
        condition_display_name    = "connected_clients > ${local.alert_defaults.connected_clients_warning_threshold}"
        severity                  = "WARNING"
        resource_type             = local.alert_defaults.resource_type_instance_node
        metric_type               = local.alert_defaults.metric_type_connected_clients
        comparison                = "COMPARISON_GT"
        threshold_value           = local.alert_defaults.connected_clients_warning_threshold
        duration                  = local.alert_defaults.warning_duration
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
    # Only added to the map when applicable — the alert-policy resource's
    # for_each over this map simply won't create it otherwise.
    var.enable_replication_lag_alert ? {
      replication_lag = {
        display_name              = "[WARNING][${var.location}] Valkey replication lag high"
        condition_display_name    = "maximum_offset_diff > ${local.alert_defaults.replication_lag_warning_bytes} bytes"
        severity                  = "WARNING"
        resource_type             = local.alert_defaults.resource_type_instance
        metric_type               = local.alert_defaults.metric_type_replication_lag
        comparison                = "COMPARISON_GT"
        threshold_value           = local.alert_defaults.replication_lag_warning_bytes
        duration                  = local.alert_defaults.warning_duration
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
  ) : {}
}
