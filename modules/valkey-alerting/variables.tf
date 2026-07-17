############################################
# Target instance
############################################

variable "project_id" {
  type        = string
  description = "Project ID where the Memorystore for Valkey instance and alert policies live."
}

variable "instance_id" {
  type        = string
  description = "The Memorystore for Valkey instance ID to monitor (e.g. google_memorystore_instance.this.instance_id)."
}

variable "region" {
  type        = string
  description = "Region of the instance, used in alert display names."
}

############################################
# Platform team notification config
############################################

variable "platform_critical_emails" {
  type        = list(string)
  description = "Email addresses for the platform team to receive CRITICAL alerts (instance down, CPU/memory critical)."
}

variable "platform_warning_emails" {
  type        = list(string)
  description = "Email addresses for the platform team to receive WARNING alerts."
}

############################################
# Service project team notification config
############################################

variable "service_team_critical_emails" {
  type        = list(string)
  description = "Email addresses for the service project team to receive CRITICAL alerts."
}

variable "service_team_warning_emails" {
  type        = list(string)
  description = "Email addresses for the service project team to receive WARNING alerts."
}

variable "service_project_id" {
  type        = string
  description = "Project ID to create the service team's notification channels in. Defaults to project_id if the service team doesn't have a separate project."
  default     = null
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
  description = "Memory maximum_utilization (0.0-1.0) that triggers a WARNING alert."
  default     = 0.8
}

variable "memory_critical_threshold" {
  type        = number
  description = "Memory maximum_utilization (0.0-1.0) that triggers a CRITICAL alert."
  default     = 0.95
}

variable "rejected_connections_threshold" {
  type        = number
  description = "Count of rejected connections (per alignment period) that triggers a WARNING alert. Any sustained non-zero value usually warrants investigation."
  default     = 1
}

variable "connected_clients_warning_threshold" {
  type        = number
  description = "Absolute connected client count that triggers a WARNING alert (backpressure signal). Set below your maxclients value."
  default     = 8000
}

variable "replication_lag_warning_bytes" {
  type        = number
  description = "Replication offset diff (bytes) that triggers a WARNING alert. Google recommends <64MB for shared-core-nano/standard-small/highmem-medium, <1GB for highmem-xlarge."
  default     = 67108864 # 64MB
}

############################################
# Alerting behavior
############################################

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
