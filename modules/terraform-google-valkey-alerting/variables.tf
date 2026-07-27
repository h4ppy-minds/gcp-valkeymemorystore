############################################
# Required — target instance and notification path
############################################

variable "project_id" {
  type        = string
  description = "Project ID where the Memorystore for Valkey instance lives. Alert policies AND all notification channels are created here — Cloud Monitoring notification channels are project-scoped and an alert policy can only reference channels in its own project, so there is no valid way to split channels across projects for a single instance's alerts."
}

variable "instance_id" {
  type        = string
  description = "The Memorystore for Valkey instance ID to monitor (e.g. module.valkey.instance_id)."
}

variable "region" {
  type        = string
  description = "Region of the instance, used in alert display names."
}

variable "appteam_emails" {
  type        = set(string)
  description = "App team's email addresses — every one of these gets notified on every alert this module creates, regardless of severity. set(string) because order doesn't matter and duplicates are meaningless here. Required."

}

variable "platformteam_emails" {
  type        = set(string)
  description = "Platform/on-call team's email addresses — notified on every alert alongside appteam_emails. Optional; leave empty if you don't have a standing platform list yet."
  default     = []
  validation {
    condition     = length(var.platformteam_emails) > 0
    error_message = "platformteam_emails must have at least one address — alerts with nowhere to go are silent outages."
  }
}

############################################
# Optional — commonly set
############################################

variable "replica_count" {
  type        = number
  description = "Replica count of the monitored instance. Purely informational here (this module doesn't create the instance) — used only to default the replication-lag alert off for STANDALONE instances, where the replication metric never reports anything meaningful. Pass the same value you gave the instance itself."
  default     = 0
}

variable "enable_replication_lag_alert" {
  type        = bool
  description = "Whether to create the replication-lag alert. Null (default) means: on only when replica_count > 0. Override explicitly if you want it on/off regardless of replica_count."
  default     = null
  nullable    = true
}

############################################
# Optional — thresholds. Every default below reflects Google's general
# guidance for a production cache; you should not need to touch these for
# a typical instance. They're variables (not hardcoded) so a workload with
# a genuinely different baseline can override without forking the module.
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
  description = "Memory maximum_utilization (0.0-1.0) that triggers a WARNING alert. Google recommends starting to act around 0.8 if you expect continued data growth."
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
  description = "Count of rejected connections (per alignment period) that triggers a CRITICAL alert — this is client-visible failed connections, sustained and high, not just a soft signal."
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
# Advanced — timing knobs. Defaults match Google's own recommended alerting
# posture for this metric set. You should essentially never need to change
# these; they're exposed only so a false-positive/flapping alert can be
# retuned without editing module code.
############################################

variable "critical_alignment_period" {
  type        = string
  description = "Alignment period for the instance_down conditions (health check + absent check)."
  default     = "60s"
}

variable "warning_duration" {
  type        = string
  description = "How long a WARNING condition must persist before firing (avoids flapping on brief spikes). Shared by cpu_warning, memory_warning, connected_clients_high, and replication_lag."
  default     = "300s"
}

variable "cpu_critical_duration" {
  type        = string
  description = "How long the CPU CRITICAL condition must persist before firing."
  default     = "180s"
}

variable "memory_critical_duration" {
  type        = string
  description = "How long the memory CRITICAL condition must persist before firing."
  default     = "180s"
}

variable "rejected_connections_duration" {
  type        = string
  description = "How long the rejected-connections condition must persist before firing. Shared by both the WARNING and CRITICAL tier — deliberately short, since any sustained rejection is worth surfacing quickly."
  default     = "60s"
}

variable "instance_down_absent_duration" {
  type        = string
  description = "How long the instance_down health metric must be absent before firing (covers regional-outage-style silent failure)."
  default     = "300s"
}

variable "critical_auto_close" {
  type        = string
  description = "How long Cloud Monitoring waits before auto-closing a CRITICAL incident if the condition stops firing without an explicit resolution."
  default     = "1800s"
}

############################################
# Advanced — metric type and resource type overrides. You should never need
# to touch these in normal use. Both were verified against a live project's
# monitoredResourceDescriptors API rather than guessed — see the module
# README for the verification command if you ever need to re-check them
# (e.g. after a Google API change).
############################################

variable "resource_type_instance" {
  type        = string
  description = "Monitored resource type for instance-level metrics (CPU, memory) — confirmed via monitoredResourceDescriptors. Used by cpu_warning, cpu_critical, memory_warning, memory_critical."
  default     = "memorystore.googleapis.com/Instance"
}

variable "resource_type_instance_node" {
  type        = string
  description = "Monitored resource type for node-level metrics (health, connections, replication) — confirmed via monitoredResourceDescriptors. Used by instance_down, rejected_connections_warning, rejected_connections_critical, connected_clients_high, replication_lag."
  default     = "memorystore.googleapis.com/InstanceNode"
}

variable "metric_type_instance_health" {
  type        = string
  description = "Metric type for node health, used by instance_down. Confirmed against the official supported-monitoring-metrics reference."
  default     = "memorystore.googleapis.com/instance/node/server/healthy"
}

variable "metric_type_cpu" {
  type        = string
  description = "Metric type for CPU utilization, used by cpu_warning / cpu_critical."
  default     = "memorystore.googleapis.com/instance/cpu/maximum_utilization"
}

variable "metric_type_memory" {
  type        = string
  description = "Metric type for memory utilization, used by memory_warning / memory_critical."
  default     = "memorystore.googleapis.com/instance/memory/maximum_utilization"
}

variable "metric_type_rejected_connections" {
  type        = string
  description = "Metric type for rejected connections, used by rejected_connections_warning / _critical."
  default     = "memorystore.googleapis.com/instance/node/stats/rejected_connections_count"
}

variable "metric_type_connected_clients" {
  type        = string
  description = "Metric type for connected client count, used by connected_clients_high."
  default     = "memorystore.googleapis.com/instance/node/clients/connected_clients"
}

variable "metric_type_replication_lag" {
  type        = string
  description = "Metric type for replication offset diff, used by replication_lag. Confirmed against the official supported-monitoring-metrics reference — this is an INSTANCE-level metric (see resource_type_instance, not resource_type_instance_node, in alert_definitions)."
  default     = "memorystore.googleapis.com/instance/replication/maximum_offset_diff"
}
