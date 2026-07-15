############################################
# Deployment Topology & Disaster Recovery
############################################

variable "deployment_topology" {
  type        = string
  description = <<-EOT
    Self-documenting label for what the customer is asking for:
      STANDALONE: single instance, no replicas, no cross-region DR.
      HA: single instance with replica(s) and/or MULTI_ZONE distribution,
        still one region, no cross-region DR.
      DR: adds a SECONDARY instance in a second region, replicating from
        this instance (which becomes PRIMARY).

    This variable does NOT silently override replica_count /
    enable_cross_region_replication — it's validated for consistency
    against them (see the check block below) so the module's actual
    behavior stays fully explained by its explicit variables, while still
    giving you one clear knob to talk through with the customer.
  EOT
  default     = "STANDALONE"
  nullable    = false

  validation {
    condition     = contains(["STANDALONE", "HA", "DR"], var.deployment_topology)
    error_message = "deployment_topology must be one of: STANDALONE, HA, DR."
  }
}

variable "enable_cross_region_replication" {
  type        = bool
  description = "Whether to provision a SECONDARY instance in another region for DR. Set true only for deployment_topology = DR."
  default     = false
  nullable    = false
}

variable "secondary_location" {
  type        = string
  description = "GCP region for the SECONDARY instance. Required when enable_cross_region_replication = true. Must differ from location."
  default     = null
  nullable    = true

  validation {
    condition     = var.secondary_location == null || var.secondary_location != var.location
    error_message = "secondary_location must differ from location (primary and secondary must be in different regions)."
  }
}

check "deployment_topology_consistency" {
  assert {
    condition     = var.deployment_topology != "STANDALONE" || (var.replica_count == 0 && !var.enable_cross_region_replication)
    error_message = "deployment_topology = STANDALONE requires replica_count = 0 and enable_cross_region_replication = false."
  }
  assert {
    condition     = var.deployment_topology != "HA" || (var.replica_count >= 1 && !var.enable_cross_region_replication)
    error_message = "deployment_topology = HA requires replica_count >= 1 and enable_cross_region_replication = false. (MULTI_ZONE zone_distribution_mode is also recommended for HA, but not enforced here.)"
  }
  assert {
    condition     = var.deployment_topology != "DR" || var.enable_cross_region_replication
    error_message = "deployment_topology = DR requires enable_cross_region_replication = true."
  }
}

check "dr_requires_secondary_location" {
  assert {
    condition     = !var.enable_cross_region_replication || var.secondary_location != null
    error_message = "enable_cross_region_replication = true requires secondary_location to be set."
  }
}

############################################
# Core Identity
############################################

variable "project_id" {
  description = "GCP project ID where the Memorystore for Valkey instance is created (the 'host' project). Required — no default, to prevent accidentally deploying into a placeholder project."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID: 6-30 chars, lowercase letters/numbers/hyphens, starting with a letter."
  }
}

variable "consumer_project_id" {
  description = "Project ID where the consumer VPC network lives (the app's project). Defaults to project_id for same-project deployments. Set explicitly for cross-project setups (e.g. a shared 'valkey host' project serving multiple app projects)."
  type        = string
  default     = null
  nullable    = true
}

variable "environment" {
  type        = string
  description = "Deployment environment: DEV, QA, UAT, or PROD. Drives stricter preconditions (e.g. blocks SHARED_CORE_NANO in PROD)."

  validation {
    condition     = contains(["DEV", "QA", "UAT", "PROD"], upper(var.environment))
    error_message = "environment must be one of: DEV, QA, UAT, PROD."
  }
}

variable "instance_id" {
  type        = string
  description = "Permanent, unique identifier for this instance. Becomes the final component of the instance's resource name. Immutable after creation."
  default     = "basic-instance"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.instance_id))
    error_message = "instance_id must start with a lowercase letter, use only lowercase letters/numbers/hyphens, and be 2-63 characters."
  }
}

############################################
# Region / Zone
############################################

variable "location" {
  description = "GCP region where the Memorystore instance is created (e.g. us-central1)."
  type        = string
  default     = "us-central1"

  validation {
    # Inlined literal — variable validation cannot reference locals or data sources.
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-east5",
      "us-south1", "us-west1", "us-west2", "us-west3", "us-west4"
    ], var.location)
    error_message = "location must be a valid US GCP region supported by Memorystore for Valkey."
  }
}

variable "zone_distribution_mode" {
  description = "Zone distribution mode for the instance's nodes: SINGLE_ZONE or MULTI_ZONE (recommended for production — survives a single-zone outage)."
  type        = string
  default     = "MULTI_ZONE"

  validation {
    condition     = contains(["SINGLE_ZONE", "MULTI_ZONE"], var.zone_distribution_mode)
    error_message = "zone_distribution_mode must be either SINGLE_ZONE or MULTI_ZONE."
  }
}

variable "zone" {
  description = "Zone to pin the instance to. Only used when zone_distribution_mode = SINGLE_ZONE; if left null in that mode, the module auto-selects the first available zone in the region. Must be left null for MULTI_ZONE."
  type        = string
  default     = null

  validation {
    condition     = var.zone_distribution_mode != "MULTI_ZONE" || var.zone == null
    error_message = "zone must not be set when zone_distribution_mode is MULTI_ZONE."
  }
}
variable "secondary_zone" {
  description = "Zone to pin the SECONDARY (DR) instance to. Only used when enable_cross_region_replication = true and zone_distribution_mode = SINGLE_ZONE. Auto-selected if left null."
  type        = string
  default     = null
}

############################################
# Cluster Topology & Sizing
############################################

variable "cluster_mode" {
  description = "Cluster Mode Enabled (CLUSTER) or Disabled (CLUSTER_DISABLED). Cannot be changed after creation."
  type        = string
  default     = "CLUSTER"

  validation {
    condition     = contains(["CLUSTER", "CLUSTER_DISABLED"], var.cluster_mode)
    error_message = "cluster_mode must be either 'CLUSTER' or 'CLUSTER_DISABLED'."
  }
}

variable "node_type" {
  description = "Machine type for individual nodes. Determines vCPU count, memory capacity, and max client connections per node. SHARED_CORE_NANO has no SLA — DEV/test only (blocked in PROD by precondition)."
  type        = string
  default     = "STANDARD_SMALL"

  validation {
    condition = contains([
      "SHARED_CORE_NANO", "CUSTOM_PICO", "CUSTOM_MICRO", "CUSTOM_MINI",
      "HIGHMEM_MEDIUM", "HIGHCPU_MEDIUM", "HIGHMEM_XLARGE",
      "STANDARD_SMALL", "STANDARD_LARGE", "HIGHMEM_2XLARGE"
    ], var.node_type)
    error_message = "node_type must be one of: SHARED_CORE_NANO, CUSTOM_PICO, CUSTOM_MICRO, CUSTOM_MINI, HIGHMEM_MEDIUM, HIGHCPU_MEDIUM, HIGHMEM_XLARGE, STANDARD_SMALL, STANDARD_LARGE, HIGHMEM_2XLARGE."
  }
}

variable "shard_count" {
  description = "Number of shards. Determines total memory capacity. Must be exactly 1 when cluster_mode = CLUSTER_DISABLED."
  type        = number

  validation {
    condition     = var.shard_count >= 1
    error_message = "shard_count must be at least 1."
  }
  validation {
    condition     = var.shard_count == floor(var.shard_count)
    error_message = "shard_count must be a whole number."
  }
  validation {
    condition     = var.shard_count <= 125
    error_message = "shard_count exceeds a reasonable ceiling (125) — verify this is intentional given regional quota (usage units = shard_count * (1 + replica_count))."
  }
}

variable "replica_count" {
  description = "Number of replica nodes per shard. 0-5. Defaults to 0 (no replicas)."
  type        = number
  default     = 0

  validation {
    condition     = var.replica_count >= 0 && var.replica_count <= 5
    error_message = "replica_count must be between 0 and 5 (inclusive)."
  }
  validation {
    condition     = var.replica_count == floor(var.replica_count)
    error_message = "replica_count must be a whole number."
  }
}

############################################
# PSC Connectivity Mode
############################################

variable "psc_connectivity_mode" {
  type        = string
  description = <<-EOT
    How PSC connections to the instance are established.

    AUTO: Memorystore creates the forwarding rule/endpoint for you inside one
      consumer VPC that you supply. Simplest option, single-VPC access only.
      Requires a Service Connection Policy authorizing the connection.

    USER: You create the forwarding rule(s) yourself and explicitly register
      them with the instance. Required when connecting from a VPC in a
      different project than the instance (the common "host project owns the
      instance, app projects consume it" pattern), or from multiple VPCs.
      No Service Connection Policy is used in this mode.
  EOT
  default     = "NONE"
  nullable    = false

  validation {
    condition     = contains(["NONE", "SHARED_VPC"], var.psc_connectivity_mode)
    error_message = "psc_connectivity_mode must be one of: NONE, SHARED_VPC."
  }
}

variable "shared_vpc_host_project" {
  type    = string
  default = null
}
variable "shared_vpc_network_name" {
  type    = string
  default = null
}
variable "existing_scp_name" {
  type    = string
  default = null
}

check "shared_vpc_inputs_present" {
  assert {
    condition = var.psc_connectivity_mode != "SHARED_VPC" || (
      var.shared_vpc_host_project != null &&
      var.shared_vpc_network_name != null &&
      var.existing_scp_name != null
    )
    error_message = "psc_connectivity_mode = SHARED_VPC requires shared_vpc_host_project, shared_vpc_network_name, and existing_scp_name."
  }
}

############################################
# Authorization (AUTH) & TLS
############################################

variable "authorization_mode" {
  type        = string
  description = "Client authentication mode. AUTH_DISABLED = no authentication (anyone on the authorized network can connect — never use in production). IAM_AUTH = clients authenticate using short-lived IAM access tokens, integrated with Cloud IAM roles/audit logs."
  default     = "IAM_AUTH"
  nullable    = false

  validation {
    condition     = contains(["AUTH_DISABLED", "IAM_AUTH"], var.authorization_mode)
    error_message = "authorization_mode must be one of: AUTH_DISABLED, IAM_AUTH."
  }
}

variable "transit_encryption_mode" {
  type        = string
  description = "In-transit (TLS) encryption mode. TRANSIT_ENCRYPTION_DISABLED = plaintext. SERVER_AUTHENTICATION = TLS enabled, client verifies server identity via CA cert. Required when authorization_mode = IAM_AUTH, since IAM tokens are otherwise sent unencrypted."
  default     = "SERVER_AUTHENTICATION"
  nullable    = false

  validation {
    condition     = contains(["TRANSIT_ENCRYPTION_DISABLED", "SERVER_AUTHENTICATION"], var.transit_encryption_mode)
    error_message = "transit_encryption_mode must be one of: TRANSIT_ENCRYPTION_DISABLED, SERVER_AUTHENTICATION."
  }
}

check "iam_auth_requires_tls" {
  assert {
    condition = !(
      var.authorization_mode == "IAM_AUTH" &&
      var.transit_encryption_mode == "TRANSIT_ENCRYPTION_DISABLED"
    )
    error_message = "authorization_mode = IAM_AUTH requires transit_encryption_mode = SERVER_AUTHENTICATION. IAM access tokens are sent via the AUTH command in plaintext otherwise, exposing them on the wire."
  }
}

############################################
# Certificate Authority (CA) Management
############################################

variable "server_ca_mode" {
  type        = string
  description = <<-EOT
    CA mode for TLS server certificates. Immutable after creation — cannot be
    changed or deactivated once the instance is created.

    GOOGLE_MANAGED_CA_PER_INSTANCE (default): Google generates a unique CA per
      instance. Every client must download and install that instance's specific
      CA cert. Highest isolation, highest client-side cert management overhead.

    GOOGLE_MANAGED_SHARED_CA: Google manages a single regional CA bundle shared
      across all instances in that region. Clients install one bundle per
      region instead of one per instance — simplest to operate at scale.

    CUSTOMER_MANAGED_CA: Uses your own CA pool in Certificate Authority Service
      (CAS). Requires server_ca_pool to be set. Best for compliance
      requirements around key custody/rotation.
  EOT
  default     = "GOOGLE_MANAGED_PER_INSTANCE_CA"
  nullable    = false

  validation {
    condition = contains(
      ["GOOGLE_MANAGED_PER_INSTANCE_CA", "GOOGLE_MANAGED_SHARED_CA", "CUSTOMER_MANAGED_CAS_CA"],
      var.server_ca_mode
    )
    error_message = "server_ca_mode must be one of: GOOGLE_MANAGED_PER_INSTANCE_CA, GOOGLE_MANAGED_SHARED_CA, CUSTOMER_MANAGED_CAS_CA."
  }
}

variable "server_ca_pool" {
  type        = string
  description = "Full resource ID of the CA pool in Certificate Authority Service, e.g. \"projects/PROJECT_ID/locations/REGION/caPools/POOL_ID\". Required only when server_ca_mode = CUSTOMER_MANAGED_CA; must be in the same region as the instance."
  default     = null
  nullable    = true
}

check "customer_managed_ca_requires_pool" {
  assert {
    condition     = !(var.server_ca_mode == "CUSTOMER_MANAGED_CA" && var.server_ca_pool == null)
    error_message = "server_ca_mode = CUSTOMER_MANAGED_CA requires server_ca_pool to be set to a valid CA pool resource ID."
  }
}

check "server_ca_pool_requires_tls" {
  assert {
    condition = !(
      var.server_ca_mode == "CUSTOMER_MANAGED_CA" &&
      var.transit_encryption_mode == "TRANSIT_ENCRYPTION_DISABLED"
    )
    error_message = "A configured server_ca_mode requires transit_encryption_mode = SERVER_AUTHENTICATION. TLS cannot be disabled once a CA mode is configured."
  }
}

############################################
# Encryption at Rest (CMEK)
############################################

variable "encryption_type" {
  type        = string
  description = "Encryption at rest. GOOGLE_MANAGED = Google's default encryption, no key management overhead. CUSTOMER_MANAGED (CMEK) = you control the key in Cloud KMS, giving you key rotation, revocation, and audit-log control over data access."
  default     = "GOOGLE_MANAGED"
  nullable    = false

  validation {
    condition     = contains(["GOOGLE_MANAGED", "CUSTOMER_MANAGED"], var.encryption_type)
    error_message = "encryption_type must be one of: GOOGLE_MANAGED, CUSTOMER_MANAGED."
  }
}

variable "kms_key" {
  type        = string
  description = "Full resource ID of the Cloud KMS CryptoKey, e.g. \"projects/PROJECT_ID/locations/REGION/keyRings/RING_ID/cryptoKeys/KEY_ID\". Required when encryption_type = CUSTOMER_MANAGED. Must be a symmetric key in the same region as the instance."
  default     = null
  nullable    = true

  validation {
    condition = (
      var.kms_key == null ||
      can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key))
    )
    error_message = "kms_key must be a full CryptoKey resource ID: projects/PROJECT_ID/locations/REGION/keyRings/RING_ID/cryptoKeys/KEY_ID."
  }
}

check "cmek_requires_kms_key" {
  assert {
    condition     = !(var.encryption_type == "CUSTOMER_MANAGED" && var.kms_key == null)
    error_message = "encryption_type = CUSTOMER_MANAGED requires kms_key to be set."
  }
}

############################################
# Persistence
############################################

variable "persistence_mode" {
  type        = string
  description = "Data persistence strategy. RDB = periodic point-in-time snapshots. AOF = append-only log of every write, higher durability. DISABLED = no persistence (data lost on restart/failover, no recovery source)."
  nullable    = false

  validation {
    condition     = contains(["RDB", "AOF", "DISABLED"], var.persistence_mode)
    error_message = "persistence_mode must be one of: RDB, AOF, DISABLED."
  }
}

variable "rdb_snapshot_period" {
  type        = string
  description = "Snapshot interval when persistence_mode = RDB. Required in that case, ignored otherwise."
  default     = null
  nullable    = true

  validation {
    condition = (
      var.rdb_snapshot_period == null ||
      contains(["ONE_HOUR", "SIX_HOURS", "TWELVE_HOURS", "TWENTY_FOUR_HOURS"], var.rdb_snapshot_period)
    )
    error_message = "rdb_snapshot_period must be one of: ONE_HOUR, SIX_HOURS, TWELVE_HOURS, TWENTY_FOUR_HOURS."
  }
}

variable "rdb_snapshot_start_time" {
  type        = string
  description = "RFC3339 UTC timestamp for the first RDB snapshot window (e.g. \"2024-10-02T15:01:23Z\"). Optional even when mode = RDB; if omitted, Google schedules the first snapshot immediately."
  default     = null
  nullable    = true
}

variable "aof_config" {
  type = object({
    append_fsync = string
  })
  description = "AOF fsync policy when persistence_mode = AOF. ALWAYS = fsync every write (safest, highest latency). EVERY_SEC = fsync every second (recommended default). NO = OS decides (least durable)."
  default     = null
  nullable    = true

  validation {
    condition     = var.aof_config == null || contains(["ALWAYS", "EVERY_SEC", "NO"], var.aof_config.append_fsync)
    error_message = "aof_config.append_fsync must be one of: ALWAYS, EVERY_SEC, NO."
  }
}

check "persistence_config_consistency" {
  assert {
    condition     = !(var.persistence_mode == "RDB" && var.rdb_snapshot_period == null)
    error_message = "persistence_mode = RDB requires rdb_snapshot_period to be set."
  }
  assert {
    condition     = !(var.persistence_mode == "AOF" && var.aof_config == null)
    error_message = "persistence_mode = AOF requires aof_config to be set."
  }
}

############################################
# Automated Backups
############################################

variable "automated_backup_enabled" {
  type        = bool
  description = "Whether to enable Memorystore's automated backup feature (separate from RDB/AOF persistence — a GCS-backed backup collection that survives instance deletion)."
  default     = true
  nullable    = false
}

variable "automated_backup_start_time_hour" {
  type        = number
  description = "Hour of day (UTC, 0-23) when the daily automated backup window begins. Only used when automated_backup_enabled = true."
  default     = 3
  nullable    = false

  validation {
    condition     = var.automated_backup_start_time_hour >= 0 && var.automated_backup_start_time_hour <= 23
    error_message = "automated_backup_start_time_hour must be between 0 and 23."
  }
}

variable "automated_backup_retention_days" {
  type        = number
  description = "Number of days to retain each automated backup (1-365). GCP default is 35 if unset; this module always sets it explicitly for clarity."
  default     = 35
  nullable    = false

  validation {
    condition     = var.automated_backup_retention_days >= 1 && var.automated_backup_retention_days <= 365
    error_message = "automated_backup_retention_days must be between 1 and 365."
  }
}

############################################
# Maintenance Window
############################################

variable "maintenance_day" {
  type        = string
  description = "Day of week for the weekly maintenance window (UTC)."
  default     = "SUNDAY"
  nullable    = false

  validation {
    condition = contains(
      ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"],
      var.maintenance_day
    )
    error_message = "maintenance_day must be a valid day of week (MONDAY-SUNDAY)."
  }
}

variable "maintenance_start_hour" {
  type        = number
  description = "Hour (UTC, 0-23) the weekly maintenance window begins. Pick your lowest-traffic period."
  default     = 4
  nullable    = false

  validation {
    condition     = var.maintenance_start_hour >= 0 && var.maintenance_start_hour <= 23
    error_message = "maintenance_start_hour must be between 0 and 23."
  }
}

############################################
# Engine Version
############################################

variable "engine_version" {
  type        = string
  description = "Valkey engine version. Immutable after creation — changing this forces a new instance (or requires a documented major-version upgrade path outside Terraform)."
  default     = "VALKEY_7_2"
  nullable    = false

  validation {
    condition     = contains(["VALKEY_7_2", "VALKEY_8_0", "VALKEY_9_0"], var.engine_version)
    error_message = "engine_version must be one of: VALKEY_7_2, VALKEY_8_0, VALKEY_9_0 (check current GA versions in provider docs before deploying — Google adds new versions over time)."
  }
}

############################################
# Engine Configuration Parameters
############################################

variable "maxmemory_policy" {
  type        = string
  description = "Eviction policy when the instance reaches maxmemory. volatile-lru (default) only evicts keys with a TTL set; allkeys-lru evicts any key; noeviction rejects writes at capacity instead of evicting."
  default     = "volatile-lru"
  nullable    = false

  validation {
    condition = contains(
      ["noeviction", "allkeys-lfu", "allkeys-lru", "volatile-lfu", "volatile-lru", "allkeys-random", "volatile-random", "volatile-ttl"],
      var.maxmemory_policy
    )
    error_message = "maxmemory_policy must be a valid Valkey maxmemory-policy value."
  }
}

variable "notify_keyspace_events" {
  type        = string
  description = "Keyspace notification classes to enable (pub/sub events on key changes/expiry). Empty string disables notifications (default, lowest overhead). E.g. \"Ex\" = expired-key events only, \"KEA\" = all events. Leave empty unless something actually consumes these events — it adds CPU/pubsub overhead."
  default     = ""
  nullable    = false
}

variable "maxmemory_clients" {
  type        = string
  description = "Cap on total memory used by client-side output buffers, e.g. \"10%\" or an absolute byte value like \"100mb\". Protects the instance from being OOM-killed by a slow/misbehaving client draining a large response slowly. Leave null to use Valkey's default."
  default     = null
  nullable    = true
}

variable "slowlog_log_slower_than" {
  type        = number
  description = "Microseconds a command must take to be logged to the slow log. -1 disables, 0 logs everything (expensive). Useful for catching expensive commands (e.g. unbounded KEYS/SCAN) before they degrade the instance."
  default     = 10000 # 10ms
  nullable    = true
}

variable "maxclients" {
  type        = number
  description = "Maximum simultaneous client connections. Leave null for Valkey's default (sized to node type). Lower this for an early rejection signal instead of the instance being overwhelmed by a connection storm."
  default     = null
  nullable    = true
}

############################################
# Deletion Protection
############################################

variable "deletion_protection_enabled" {
  type        = bool
  description = "If true, deletion of the instance is blocked (both by this module's lifecycle.prevent_destroy and by the API-level flag). Defaults to true — this module is meant for production; set to false explicitly for short-lived test instances."
  default     = true
}
