# Root variables.tf — declares every variable the module accepts so
# terraform.tfvars / test.tfvars work exactly as before, just at the root
# level now. Values pass straight through to module "valkey" in main.tf.
#
# Kept as a thin mirror rather than re-typing all descriptions/validations —
# the module's variables.tf (modules/valkey/variables.tf) is the source of
# truth for what each one means and how it's validated.

variable "project_id" { type = string }
variable "consumer_project_id" {
  type    = string
  default = null
}
variable "environment" { type = string }
variable "instance_id" {
  type    = string
  default = "basic-instance"
}

variable "location" {
  type    = string
  default = "us-central1"
}
variable "zone_distribution_mode" {
  type    = string
  default = "MULTI_ZONE"
}
variable "zone" {
  type    = string
  default = null
}

variable "deployment_topology" {
  type    = string
  default = "STANDALONE"
}
variable "enable_cross_region_replication" {
  type    = bool
  default = false
}
variable "secondary_location" {
  type    = string
  default = null
}
variable "secondary_zone" {
  type    = string
  default = null
}

variable "cluster_mode" {
  type    = string
  default = "CLUSTER"
}
variable "node_type" {
  type    = string
  default = "STANDARD_SMALL"
}
variable "shard_count" { type = number }
variable "replica_count" {
  type    = number
  default = 0
}

variable "psc_connectivity_mode" {
  type    = string
  default = "AUTO"
}
variable "user_networks" {
  type    = map(object({ subnet_cidr = string }))
  default = {}
}
variable "psc_attachment_count" {
  type    = number
  default = 2
}

variable "authorization_mode" {
  type    = string
  default = "IAM_AUTH"
}
variable "transit_encryption_mode" {
  type    = string
  default = "SERVER_AUTHENTICATION"
}

variable "server_ca_mode" {
  type    = string
  default = "GOOGLE_MANAGED_PER_INSTANCE_CA"
}
variable "server_ca_pool" {
  type    = string
  default = null
}

variable "encryption_type" {
  type    = string
  default = "GOOGLE_MANAGED"
}
variable "kms_key" {
  type    = string
  default = null
}

variable "persistence_mode" { type = string }
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
  default = true
}
variable "automated_backup_start_time_hour" {
  type    = number
  default = 3
}
variable "automated_backup_retention_days" {
  type    = number
  default = 35
}

variable "maintenance_day" {
  type    = string
  default = "SUNDAY"
}
variable "maintenance_start_hour" {
  type    = number
  default = 4
}

variable "engine_version" {
  type    = string
  default = "VALKEY_7_2"
}
variable "maxmemory_policy" {
  type    = string
  default = "volatile-lru"
}
variable "notify_keyspace_events" {
  type    = string
  default = ""
}
variable "maxmemory_clients" {
  type    = string
  default = null
}
variable "slowlog_log_slower_than" {
  type    = number
  default = 10000
}
variable "maxclients" {
  type    = number
  default = null
}

variable "deletion_protection_enabled" {
  type    = bool
  default = true
}
