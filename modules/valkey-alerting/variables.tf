############################################
# Target instance
############################################

variable "project_id" {
  type        = string
  description = "Project ID where the Memorystore for Valkey instance lives. Alert policies AND all notification channels are created here — Cloud Monitoring notification channels are project-scoped resources and an alert policy can only reference channels in its own project, so there is no valid way to split channels across projects for a single instance's alerts."
}

variable "instance_id" {
  type        = string
  description = "The Memorystore for Valkey instance ID to monitor (e.g. google_memorystore_instance.this.instance_id)."
}

variable "region" {
  type        = string
  description = "Region of the instance, used in alert display names."
}

variable "replica_count" {
  type        = number
  description = "Replica count of the monitored instance. Purely informational here (this module doesn't create the instance) — used only to default enable_replication_lag_alert off for STANDALONE instances, where the replication metric never reports anything meaningful. Pass the same value you gave the instance itself."
  default     = 0
}

############################################
# Notification emails
#
# Two audiences, each split by severity:
#   - requester_*: the team that asked for this instance — this is what
#     "alert to the emails the requester gave us" maps to. Required.
#   - platform_*: your own (host project) ops/on-call distribution list,
#     cc'd on every instance this module is used for. Optional — leave
#     empty if you don't want a standing platform-wide channel yet.
############################################

variable "requester_critical_emails" {
  type        = list(string)
  description = "Email addresses the requester gave you to receive CRITICAL alerts (instance down, CPU/memory critical) for their instance. Required — this is the primary notification path."

  validation {
    condition     = length(var.requester_critical_emails) > 0
    error_message = "requester_critical_emails must have at least one address — CRITICAL alerts with nowhere to go are silent outages."
  }
}

variable "requester_warning_emails" {
  type        = list(string)
  description = "Email addresses the requester gave you to receive WARNING alerts for their instance. Defaults to requester_critical_emails if left empty, so warnings are never silently dropped just because this wasn't set."
  default     = []
}

variable "platform_critical_emails" {
  type        = list(string)
  description = "Optional standing platform/on-call distribution list, cc'd on CRITICAL alerts for this instance in addition to the requester's addresses. Leave empty if you don't have one yet."
  default     = []
}

variable "platform_warning_emails" {
  type        = list(string)
  description = "Optional standing platform/on-call distribution list, cc'd on WARNING alerts for this instance in addition to the requester's addresses. Leave empty if you don't have one yet."
  default     = []
}

############################################
# Thresholds — tune per workload
############################################

variable "cpu_warning_threshold" {
  type        = number
  description = "CPU maximum_utilization (0.0-1.0) that triggers a WARNING alert."
  default     = 0.8
}

variable "cpu_critical_threshold" {
  type        = number
  description = "CPU maximum_utilization (0.0-1.0) that triggers a CRITICAL alert."
  default     = 0.95
}

variable "memory_warning_threshold" {
  type        = number
  description = "Memory maximum_utilization (0.0-1.0) that triggers a WARNING alert. Google recommends starting to act around 0.8 if you expect continued data growth (see general-best-practices doc)."
  default     = 0.8
}

variable "memory_critical_threshold" {
  type        = number
  description = "Memory maximum_utilization (0.0-1.0) that triggers a CRITICAL alert."
  default     = 0.95
}

variable "rejected_connections_warning_threshold" {
  type        = number
  description = "Count of rejected connections (per alignment period) that triggers a WARNING alert. Any sustained non-zero value usually warrants investigation."
  default     = 1
}

variable "rejected_connections_critical_threshold" {
  type        = number
  description = "Count of rejected connections (per alignment period) that triggers a CRITICAL alert — this is client-visible failed connections, not just a soft signal, once it's sustained and high."
  default     = 50
}

variable "connected_clients_warning_threshold" {
  type        = number
  description = "Absolute connected client count that triggers a WARNING alert (backpressure signal). Set below your maxclients value."
  default     = 8000
}

variable "replication_lag_warning_bytes" {
  type        = number
  description = "Replication offset diff (bytes) that triggers a WARNING alert. Per Google's guidance: keep below 64MB for shared-core-nano/standard-small/highmem-medium node types, below 1GB for highmem-xlarge. The 64MB default here is wrong for highmem-xlarge — override it if that's your node_type."
  default     = 67108864 # 64MB — see node_type caveat above
}

############################################
# Alerting behavior
############################################

variable "enable_replication_lag_alert" {
  type        = bool
  description = "Whether to create the replication-lag alert. Defaults to true only when replica_count > 0 — for a STANDALONE instance with no replicas, the underlying maximum_offset_diff metric never reports anything meaningful, so the alert would just sit permanently un-firing (harmless, but noise in your policy list). Override explicitly if you want it on/off regardless of replica_count."
  default     = null
  nullable    = true
}

variable "critical_alignment_period" {
  type        = string
  description = "Alignment period for critical conditions (instance down, CPU/memory critical)."
  default     = "60s"
}

variable "warning_duration" {
  type        = string
  description = "How long a warning condition must persist before firing (avoids flapping on brief spikes)."
  default     = "300s"
}

variable "critical_auto_close" {
  type        = string
  description = "How long Cloud Monitoring waits before auto-closing a critical incident if the condition stops firing without an explicit resolution."
  default     = "1800s"
}
