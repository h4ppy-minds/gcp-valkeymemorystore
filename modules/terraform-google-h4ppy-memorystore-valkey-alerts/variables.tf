############################################
# Target instance — this module creates no compute/storage resources of
# its own. It only points Cloud Monitoring at an instance that already
# exists (e.g. created by terraform-google-valkey) via its identity.
############################################

# --- REQUIRED ---
variable "project_id" {
  type        = string
  description = "GCP project ID where the alert policies + notification channels are created. Must be the same project the target Valkey instance lives in — notification channels are project-scoped and cannot be attached to alert policies in a different project."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID: 6-30 chars, lowercase letters/numbers/hyphens, starting with a letter."
  }
}

# --- REQUIRED ---
variable "instance_id" {
  type        = string
  description = "The instance_id of the Memorystore for Valkey instance to alert on (e.g. terraform-google-valkey's `instance_id` output). This module does not create or manage that instance — it only filters alert conditions on it."
}

# --- REQUIRED ---
variable "location" {
  type        = string
  description = "Region the target instance lives in (e.g. terraform-google-valkey's `resolved_location` output). Used only to label alert display names — not used to look up or validate the instance."
}

# --- OPTIONAL ---
variable "enable_replication_lag_alert" {
  type        = bool
  description = "Whether to create the replication-lag alert policy. This module has no visibility into the target instance's replica_count, so the caller decides — pass true whenever the instance actually has replicas (e.g. `replica_count > 0` from terraform-google-valkey)."
  default     = false
}

############################################
# Alerting toggle + notification routing
#
# This module deliberately exposes only these variables. Every
# threshold, duration, and metric/resource-type string is a fixed
# constant in alerts.tf — this module's alerting is meant to ship as "on
# with good defaults, or off," not individually retuned per caller. If a
# threshold genuinely needs to change, edit local.alert_defaults in
# alerts.tf directly; there is no variable path for it.
############################################

# --- OPTIONAL ---
variable "enable_alerting" {
  type        = bool
  description = "Master on/off switch. Set to false to remove all alert policies and notification channels this module manages (e.g. alerting is temporarily handled elsewhere)."
  default     = true
  nullable    = false
}

# --- CONDITIONALLY REQUIRED: must be non-empty whenever enable_alerting =
# true (enforced by the alerting_requires_appteam_emails check block
# below, not by Terraform's built-in required-variable check, since
# Terraform variables can't natively express "required only if some
# other value is true"). ---
variable "appteam_emails" {
  type        = set(string)
  description = "App team's email addresses — every one of these gets notified on every alert this module creates, regardless of severity. set(string) because order doesn't matter and duplicates are meaningless here. Required when enable_alerting = true (see the alerting_requires_appteam_emails check) — an alert with nowhere to go is a silent outage. This is the variable meant to change independently, without touching the instance's Terraform: adding, removing, or swapping an address here only re-plans this module, never the instance."
  default     = []
  nullable    = false
}

# --- OPTIONAL ---
variable "platformteam_emails" {
  type        = set(string)
  description = "Platform/on-call team's email addresses — notified on every alert alongside appteam_emails. Optional; leave empty if you don't have a standing platform list yet."
  default     = []
  nullable    = false
}

############################################
# Cross-field checks
############################################

check "alerting_requires_appteam_emails" {
  assert {
    condition     = !var.enable_alerting || length(var.appteam_emails) > 0
    error_message = "enable_alerting = true requires at least one address in appteam_emails — an alert with nowhere to go is a silent outage. Set enable_alerting = false if you don't want alerting from this module call."
  }
}
