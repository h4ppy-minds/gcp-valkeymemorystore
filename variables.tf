# Root variables.tf — declares every variable the module accepts so
# terraform.tfvars / test.tfvars work exactly as before, just at the root
# level now. Values pass straight through to module "valkey" in main.tf.
#
# Kept as a thin mirror rather than re-typing all validation logic — the
# module's variables.tf (modules/valkey/variables.tf) is the source of
# truth for validation rules and check blocks. Descriptions here are
# shown to callers running `terraform plan` at the root without digging
# into the module, so they're worth keeping accurate even though the
# validation itself lives one level down.

############################################
# Core Identity
############################################

variable "project_id" {
  type        = string
  description = "Host project ID where the Memorystore for Valkey instance is created. Required — no default."
}

variable "consumer_project_id" {
  type        = string
  default     = null
  description = "Legacy input from the AUTO/USER PSC modes (module-created consumer VPC lived here). Not used by NONE or SHARED_VPC modes — SHARED_VPC uses shared_vpc_host_project instead. VERIFY: confirm modules/valkey/variables.tf still accepts this input; if it was removed there during the AUTO/USER cleanup, remove this variable and its pass-through in main.tf too, or terraform validate will reject it as an unsupported module argument."
}

variable "environment" {
  type        = string
  description = "Deployment environment: DEV, QA, UAT, or PROD. Drives stricter preconditions inside the module (e.g. blocks SHARED_CORE_NANO in PROD)."
}

variable "instance_id" {
  type        = string
  default     = "basic-instance"
  description = "Permanent, unique identifier for this instance. Becomes the final component of the instance's resource name. Immutable after creation."
}

############################################
# Region / Zone
############################################

variable "location" {
  type        = string
  default     = "us-central1"
  description = "GCP region where the Memorystore instance is created."
}

variable "zone_distribution_mode" {
  type        = string
  default     = "MULTI_ZONE"
  description = "SINGLE_ZONE or MULTI_ZONE. MULTI_ZONE (default) survives a single-zone outage — recommended for anything beyond a throwaway test."
}

variable "zone" {
  type        = string
  default     = null
  description = "Zone to pin the instance to. Only used when zone_distribution_mode = SINGLE_ZONE; must be left null for MULTI_ZONE. Auto-selected by the module if left null in SINGLE_ZONE mode."
}

############################################
# Deployment Topology & Disaster Recovery
############################################

variable "deployment_topology" {
  type        = string
  default     = "STANDALONE"
  description = "Self-documenting label: STANDALONE (no replicas, no DR), HA (replicas and/or MULTI_ZONE, single region), or DR (adds a SECONDARY instance in secondary_location). Validated against replica_count / enable_cross_region_replication inside the module — this variable does not silently override those."
}

variable "enable_cross_region_replication" {
  type        = bool
  default     = false
  description = "Whether to provision a SECONDARY instance in secondary_location for DR. Set true only for deployment_topology = DR."
}

variable "secondary_location" {
  type        = string
  default     = null
  description = "GCP region for the SECONDARY (DR) instance. Required when enable_cross_region_replication = true. Must differ from location — PSC connections are strictly regional, so DR needs its own full networking stack in this region."
}

variable "secondary_zone" {
  type        = string
  default     = null
  description = "Zone to pin the SECONDARY instance to. Only used with SINGLE_ZONE + DR. Auto-selected by the module if left null."
}

############################################
# Cluster Topology & Sizing
############################################

variable "cluster_mode" {
  type        = string
  default     = "CLUSTER"
  description = "CLUSTER (sharded, Cluster Mode Enabled) or CLUSTER_DISABLED (single primary + replicas, classic Redis-style). Immutable after creation."
}

variable "node_type" {
  type        = string
  default     = "STANDARD_SMALL"
  description = "Machine type for individual nodes. SHARED_CORE_NANO has no SLA — DEV/test only, blocked in PROD by a module precondition."
}

variable "shard_count" {
  type        = number
  description = "Number of shards. Must be exactly 1 when cluster_mode = CLUSTER_DISABLED. Required — no default, since the right value is topology-specific."
}

variable "replica_count" {
  type        = number
  default     = 0
  description = "Replica nodes per shard, 0-5. Required >= 1 for deployment_topology = HA."
}

############################################
# PSC Connectivity Mode
#
# Only two modes are supported at this layer of the project: NONE (no
# private connectivity — instance only, useful for a bare-instance
# smoke test) and SHARED_VPC (attach to an existing Shared VPC network
# + a Service Connection Policy your platform team already created).
############################################

variable "psc_connectivity_mode" {
  type        = string
  default     = "NONE"
  description = "NONE (no PSC connectivity — instance only) or SHARED_VPC (attach to an existing Shared VPC network + pre-existing Service Connection Policy). Full validation of allowed values lives in modules/valkey/variables.tf."
}

variable "shared_vpc_host_project" {
  type        = string
  default     = null
  description = "Host project ID that owns the existing Shared VPC network (the network 'hub' project). Required when psc_connectivity_mode = SHARED_VPC."
}

variable "shared_vpc_network_name" {
  type        = string
  default     = null
  description = "Name of the existing Shared VPC network itself (not a project id — the VPC's own name as shown in console under VPC networks). Required when psc_connectivity_mode = SHARED_VPC."
}

variable "existing_scp_name" {
  type        = string
  default     = null
  description = "Name of the existing Service Connection Policy (service_class = gcp-memorystore) already created by the platform team, for var.location specifically — SCPs are regional. Required when psc_connectivity_mode = SHARED_VPC."
}

############################################
# Authorization (AUTH) & TLS
############################################

variable "authorization_mode" {
  type        = string
  default     = "IAM_AUTH"
  description = "AUTH_DISABLED (no auth — never use in production) or IAM_AUTH (short-lived IAM tokens)."
}

variable "transit_encryption_mode" {
  type        = string
  default     = "SERVER_AUTHENTICATION"
  description = "TRANSIT_ENCRYPTION_DISABLED or SERVER_AUTHENTICATION (TLS). Must be SERVER_AUTHENTICATION when authorization_mode = IAM_AUTH, enforced by a check block in the module."
}

############################################
# Certificate Authority (CA) Management
############################################

variable "server_ca_mode" {
  type        = string
  default     = "GOOGLE_MANAGED_PER_INSTANCE_CA"
  description = "CA mode for TLS server certs. Immutable after creation. GOOGLE_MANAGED_PER_INSTANCE_CA (default, unique cert per instance), GOOGLE_MANAGED_SHARED_CA (one regional bundle), or CUSTOMER_MANAGED_CAS_CA (your own CA pool — requires server_ca_pool)."
}

variable "server_ca_pool" {
  type        = string
  default     = null
  description = "Full CA pool resource ID, e.g. projects/PROJECT_ID/locations/REGION/caPools/POOL_ID. Required only when server_ca_mode = CUSTOMER_MANAGED_CAS_CA."
}

############################################
# Encryption at Rest (CMEK)
############################################

variable "encryption_type" {
  type        = string
  default     = "GOOGLE_MANAGED"
  description = "GOOGLE_MANAGED (default) or CUSTOMER_MANAGED (CMEK — requires kms_key)."
}

variable "kms_key" {
  type        = string
  default     = null
  description = "Full CryptoKey resource ID, e.g. projects/PROJECT_ID/locations/REGION/keyRings/RING_ID/cryptoKeys/KEY_ID. Required when encryption_type = CUSTOMER_MANAGED. Must be a symmetric key in the same region as the instance."
}

############################################
# Persistence
############################################

variable "persistence_mode" {
  type        = string
  description = "RDB (periodic snapshots), AOF (append-only log, higher durability), or DISABLED (data lost on restart/failover). Required — no default, since this is a meaningful production decision."
}

variable "rdb_snapshot_period" {
  type        = string
  default     = null
  description = "Snapshot interval when persistence_mode = RDB: ONE_HOUR, SIX_HOURS, TWELVE_HOURS, or TWENTY_FOUR_HOURS. Required in that case, ignored otherwise."
}

variable "rdb_snapshot_start_time" {
  type        = string
  default     = null
  description = "RFC3339 UTC timestamp for the first RDB snapshot window, e.g. \"2026-07-14T03:00:00Z\". Optional even when mode = RDB — if omitted, Google schedules the first snapshot immediately."
}

variable "aof_config" {
  type        = object({ append_fsync = string })
  default     = null
  description = "AOF fsync policy when persistence_mode = AOF: ALWAYS (safest, highest latency), EVERY_SEC (recommended default), or NO (least durable)."
}

############################################
# Automated Backups
############################################

variable "automated_backup_enabled" {
  type        = bool
  default     = true
  description = "Whether to enable Memorystore's automated backup feature — a GCS-backed backup collection, separate from RDB/AOF persistence, that survives instance deletion."
}

variable "automated_backup_start_time_hour" {
  type        = number
  default     = 3
  description = "UTC hour (0-23) the daily automated backup window begins. Only used when automated_backup_enabled = true."
}

variable "automated_backup_retention_days" {
  type        = number
  default     = 35
  description = "Days to retain each automated backup (1-365)."
}

############################################
# Maintenance Window
############################################

variable "maintenance_day" {
  type        = string
  default     = "SUNDAY"
  description = "Day of week for the weekly maintenance window (UTC)."
}

variable "maintenance_start_hour" {
  type        = number
  default     = 4
  description = "UTC hour (0-23) the weekly maintenance window begins. Pick your lowest-traffic period."
}

############################################
# Engine Version & Configuration Parameters
############################################

variable "engine_version" {
  type        = string
  default     = "VALKEY_7_2"
  description = "Valkey engine version. Immutable after creation — verify current GA versions before deploying, since Google adds new ones over time."
}

variable "maxmemory_policy" {
  type        = string
  default     = "volatile-lru"
  description = "Eviction policy at maxmemory. volatile-lru (default) only evicts keys with a TTL set."
}

variable "notify_keyspace_events" {
  type        = string
  default     = ""
  description = "Keyspace notification classes, e.g. \"KEA\" for all events. Empty string disables (default) — only enable if something actually consumes these, since they add CPU/pubsub overhead."
}

variable "maxmemory_clients" {
  type        = string
  default     = null
  description = "Cap on client output buffer memory, e.g. \"10%\" or \"100mb\". Null uses Valkey's own default."
}

variable "slowlog_log_slower_than" {
  type        = number
  default     = 10000
  description = "Microseconds a command must take to be slow-logged. -1 disables, 0 logs everything. Default 10000 = 10ms."
}

variable "maxclients" {
  type        = number
  default     = null
  description = "Max simultaneous client connections. Null sizes to node_type's default."
}

############################################
# Deletion Protection
############################################

variable "deletion_protection_enabled" {
  type        = bool
  default     = true
  description = "API-enforced deletion guard (blocks delete via console/gcloud/API, not just terraform destroy). Defaults to true — set false explicitly for disposable test instances."
}
