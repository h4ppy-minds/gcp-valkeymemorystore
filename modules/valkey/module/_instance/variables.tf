############################################
# Internal submodule — one google_memorystore_instance.
#
# Not meant to be called directly by end users of the parent module —
# no versions.tf/provider requirements of its own; it inherits the
# parent's. Called twice from ../../main.tf: once unconditionally for
# the primary, once with count for the DR secondary. Exists purely to
# eliminate the ~150 lines of persistence/maintenance/auth/CA/CMEK/
# engine-config duplication that existed when primary and secondary were
# two hand-written resource blocks.
############################################

variable "project_id" {
  type = string
}

variable "instance_id" {
  type = string
}

variable "location" {
  type = string
}

variable "zone_distribution_mode" {
  type = string
}

variable "effective_zone" {
  type        = string
  description = "Already-resolved zone for SINGLE_ZONE mode (or null) — computed once in the parent's locals.tf against the region this instance lives in, so this submodule doesn't need its own data-source lookups."
  default     = null
}

variable "cluster_mode" {
  type = string
}

variable "node_type" {
  type = string
}

variable "shard_count" {
  type = number
}

variable "replica_count" {
  type = number
}

############################################
# Cross-instance replication role
############################################

variable "instance_role" {
  type        = string
  description = "NONE (standalone/HA),SECONDARY."
  default     = "NONE"

  validation {
    condition     = contains(["NONE", "SECONDARY"], var.instance_role)
    error_message = "instance_role must be NONE or SECONDARY."
  }
}

variable "primary_instance_id" {
  type        = string
  description = "The primary instance's resource ID. Required when instance_role = SECONDARY, ignored otherwise."
  default     = null
}

############################################
# Networking (PSC)
############################################

variable "psc_connectivity_mode" {
  type = string
}

variable "effective_psc_network_id" {
  type    = string
  default = null
}

############################################
# Auth / TLS / CA / CMEK
############################################

variable "authorization_mode" {
  type = string
}

variable "transit_encryption_mode" {
  type = string
}

variable "server_ca_mode" {
  type = string
}

variable "server_ca_pool" {
  type    = string
  default = null
}

variable "kms_key" {
  type        = string
  description = "Already resolved to null unless encryption_type = CUSTOMER_MANAGED — computed once in the parent."
  default     = null
}

############################################
# Persistence / backups / maintenance
############################################

variable "persistence_mode" {
  type = string
}

variable "rdb_snapshot_period" {
  type    = string
  default = null
}

variable "rdb_snapshot_start_time" {
  type    = string
  default = null
}

variable "aof_config" {
  type    = object({ append_fsync = string })
  default = null
}

variable "automated_backup_enabled" {
  type    = bool
  default = false
}

variable "automated_backup_start_time_hour" {
  type    = number
  default = null
}

variable "automated_backup_retention_days" {
  type    = number
  default = null
}

variable "maintenance_day" {
  type = string
}

variable "maintenance_start_hour" {
  type = number
}

############################################
# Engine version & config parameters
############################################

variable "engine_version" {
  type = string
}

variable "maxmemory_policy" {
  type = string
}

variable "notify_keyspace_events" {
  type = string
}

variable "maxmemory_clients" {
  type    = string
  default = null
}

variable "slowlog_log_slower_than" {
  type    = number
  default = null
}

variable "maxclients" {
  type    = number
  default = null
}

############################################
# Deletion protection
############################################

variable "deletion_protection_enabled" {
  type = bool
}

variable "labels" {
  type    = map(string)
  default = {}
}

############################################
# Precondition inputs — computed once in the parent's locals.tf (which
# owns the region/zone data sources) and passed in here as plain
# booleans, so this submodule stays free of its own data-source lookups.
# Everything except valid_location defaults to true so a minimal call
# (e.g. the secondary, which only needs its own location re-checked)
# doesn't have to restate checks that are identical to the primary's.
############################################

variable "valid_location" {
  type = bool
}

variable "valid_zone_for_single_zone_mode" {
  type    = bool
  default = true
}

variable "valid_shard_count_for_cluster_mode" {
  type    = bool
  default = true
}

variable "valid_node_type_for_prod" {
  type    = bool
  default = true
}

variable "valid_custom_node_type_requires_cluster_disabled" {
  type    = bool
  default = true
}

variable "valid_iam_auth_requires_tls" {
  type    = bool
  default = true
}
