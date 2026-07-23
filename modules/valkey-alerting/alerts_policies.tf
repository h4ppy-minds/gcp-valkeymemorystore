############################################
# Every alert policy in this module is one instantiation of the generic
# module/_alert_policy submodule, driven by local.alert_definitions
# (locals.tf). This is the same "single resource definition, called
# multiple times" pattern modules/valkey/main.tf uses for module/_instance
# (primary + secondary) — here via for_each instead of two named calls,
# since the alert set is naturally table-shaped rather than a fixed pair.
#
# To add a new alert: add one entry to local.alert_definitions. Nothing in
# this file changes.
############################################

module "alert_policies" {
  source   = "./module/_alert_policy"
  for_each = local.alert_definitions

  project_id  = var.project_id
  instance_id = var.instance_id

  display_name           = each.value.display_name
  condition_display_name = each.value.condition_display_name
  severity               = each.value.severity
  resource_type          = each.value.resource_type
  metric_type            = each.value.metric_type
  comparison             = each.value.comparison
  threshold_value        = each.value.threshold_value
  duration               = each.value.duration
  alignment_period       = each.value.alignment_period
  per_series_aligner     = each.value.per_series_aligner
  cross_series_reducer   = each.value.cross_series_reducer
  group_by_fields        = each.value.group_by_fields

  enable_absent_check       = each.value.enable_absent_check
  absent_duration           = coalesce(each.value.absent_duration, "300s")
  absent_alignment_period   = coalesce(each.value.absent_alignment_period, "60s")
  absent_per_series_aligner = coalesce(each.value.absent_per_series_aligner, "ALIGN_MIN")

  auto_close = each.value.auto_close

  notification_channels = local.notification_channel_ids
}
