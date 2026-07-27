############################################
# This is the "_instance" of the alerting module: one generic single-metric
# threshold alert policy, instantiated once per alert (see
# ../../locals.tf#alert_definitions and ../../alert_policies.tf) instead of
# hand-writing ~9 near-identical google_monitoring_alert_policy resources.
#
# Every variable here is required from the caller — this module holds no
# opinions about what a "good" threshold is; that judgment (and every
# default) lives one level up, in the outer module's variables.tf, so it
# stays in exactly one place.
############################################

variable "project_id" {
  type        = string
  description = "Project ID the alert policy is created in."
}

variable "instance_id" {
  type        = string
  description = "Memorystore instance ID the alert filters on."
}

variable "resource_type" {
  type        = string
  description = "Monitored resource type for the filter. No default: Memorystore for Valkey exposes two distinct monitored resource types (memorystore.googleapis.com/Instance for instance-level metrics like CPU/memory, memorystore.googleapis.com/InstanceNode for node-level metrics like health/connections/replication) — the correct one depends on which metric this alert targets, so the caller (alert_policies.tf, driven by local.alert_definitions) must always specify it explicitly rather than relying on a guess here."
}

variable "display_name" {
  type        = string
  description = "Alert policy display name shown in Cloud Monitoring, e.g. \"[WARNING][us-central1] Valkey CPU utilization high\"."
}

variable "condition_display_name" {
  type        = string
  description = "Display name of the primary threshold condition."
}

variable "severity" {
  type        = string
  description = "WARNING or CRITICAL."

  validation {
    condition     = contains(["WARNING", "CRITICAL"], var.severity)
    error_message = "severity must be \"WARNING\" or \"CRITICAL\"."
  }
}

variable "metric_type" {
  type        = string
  description = "Fully-qualified Cloud Monitoring metric type, e.g. memorystore.googleapis.com/instance/cpu/maximum_utilization."
}

variable "comparison" {
  type        = string
  description = "COMPARISON_GT or COMPARISON_LT."

  validation {
    condition     = contains(["COMPARISON_GT", "COMPARISON_LT"], var.comparison)
    error_message = "comparison must be \"COMPARISON_GT\" or \"COMPARISON_LT\"."
  }
}

variable "threshold_value" {
  type        = number
  description = "Threshold that triggers the primary condition."
}

variable "duration" {
  type        = string
  description = "How long the primary condition must persist before firing."
}

variable "alignment_period" {
  type        = string
  description = "Alignment period for the primary condition's aggregation."
}

variable "per_series_aligner" {
  type        = string
  description = "Per-series aligner for the primary condition's aggregation (e.g. ALIGN_MEAN, ALIGN_MAX, ALIGN_SUM, ALIGN_MIN)."
}

variable "cross_series_reducer" {
  type        = string
  description = "Optional cross-series reducer (e.g. REDUCE_SUM) for the primary condition. Null when the metric doesn't need combining across series."
  default     = null
  nullable    = true
}

variable "group_by_fields" {
  type        = list(string)
  description = "Optional group_by_fields for the primary condition's aggregation. Only meaningful together with cross_series_reducer."
  default     = []
}

variable "notification_channels" {
  type        = list(string)
  description = "Notification channel IDs to attach to this policy."
}

variable "auto_close" {
  type        = string
  description = "alert_strategy.auto_close duration. Null omits alert_strategy entirely, which leaves Cloud Monitoring's own default (7 days) in effect."
  default     = null
  nullable    = true
}

variable "enable_absent_check" {
  type        = bool
  description = "Also add a condition_absent block, so the policy fires if the metric stops reporting entirely (e.g. a regional outage), not only when it reports a bad value. Used for instance_down; leave false for ordinary threshold alerts."
  default     = false
}

variable "absent_duration" {
  type        = string
  description = "Duration for the condition_absent check. Only used when enable_absent_check = true."
  default     = "300s"
}

variable "absent_alignment_period" {
  type        = string
  description = "Alignment period for the condition_absent check. Only used when enable_absent_check = true."
  default     = "60s"
}

variable "absent_per_series_aligner" {
  type        = string
  description = "Per-series aligner for the condition_absent check. Only used when enable_absent_check = true."
  default     = "ALIGN_MIN"
}
