############################################
# Deployment Topology & Disaster Recovery
############################################

# --- OPTIONAL ---
variable "deployment_topology" {
  type        = string
  description = <<-EOT
    The single knob for topology — this is the only input; there is no
    separate enable_cross_region_replication variable. STANDALONE / HA
    map 1:1 to no DR; DR maps 1:1 to a SECONDARY instance being created.
    Default (when left null): see local.defaults.deployment_topology in
    all-locals.tf.
      STANDALONE: single instance, no replicas, no cross-region DR.
      HA: single instance with replica(s) and/or MULTI_ZONE distribution,
        still one region, no cross-region DR.
      DR: adds a SECONDARY instance in a second region, replicating from
        this instance (which becomes PRIMARY). Requires secondary_location.
  EOT
  default     = null
  nullable    = true

  validation {
    condition     = var.deployment_topology == null ? true : contains(["STANDALONE", "HA", "DR"], var.deployment_topology)
    error_message = "deployment_topology must be one of: STANDALONE, HA, DR."
  }
}

# --- OPTIONAL ---
variable "secondary_location" {
  type        = string
  description = "GCP region for the SECONDARY instance. Required when deployment_topology = DR. Must differ from location. No centralized default — null is the meaningful 'no DR region chosen' state, not a value to retune."
  default     = null
  nullable    = true

  validation {
    condition     = var.secondary_location == null ? true : var.secondary_location != var.location
    error_message = "secondary_location must differ from location (primary and secondary must be in different regions)."
  }
}

############################################
# Core Identity
############################################

# --- REQUIRED ---
variable "project_id" {
  description = "GCP project ID where the Memorystore for Valkey instance is created. Required — no default, to prevent accidentally deploying into a placeholder project."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID: 6-30 chars, lowercase letters/numbers/hyphens, starting with a letter."
  }
}

# --- REQUIRED ---
variable "environment" {
  type        = string
  description = "Deployment environment: DEV, QA, UAT, or PROD. Drives stricter preconditions (e.g. blocks SHARED_CORE_NANO in PROD). Required — no sensible module-wide default exists for this."

  validation {
    condition     = contains(["DEV", "QA", "UAT", "PROD"], upper(var.environment))
    error_message = "environment must be one of: DEV, QA, UAT, PROD."
  }
}

# --- OPTIONAL ---
variable "instance_id" {
  type        = string
  description = "Permanent, unique identifier for this instance. Becomes the final component of the instance's resource name. Immutable after creation."
  default     = null
  nullable    = true

  validation {
    condition     = var.instance_id == null ? true : can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.instance_id))
    error_message = "instance_id must start with a lowercase letter, use only lowercase letters/numbers/hyphens, and be 2-63 characters."
  }
}

# --- OPTIONAL ---
variable "labels" {
  type        = map(string)
  description = "Resource labels for cost allocation/ownership tracking (e.g. { env = \"dev\", managed_by = \"terraform\" }). Non-authoritative — Memorystore only manages the labels present in this map. Applied identically to both the primary and secondary (DR) instance."
  default     = null
  nullable    = true
}

############################################
# Region / Zone
############################################

# --- OPTIONAL ---
variable "location" {
  description = "GCP region where the Memorystore instance is created (e.g. us-central1). Must be one of local.defaults.allowed_locations in all-locals.tf — edit that list there to support a new region."
  type        = string
  default     = null
  nullable    = true
}

# --- OPTIONAL ---
variable "zone_distribution_mode" {
  description = "Zone distribution mode for the instance's nodes: SINGLE_ZONE or MULTI_ZONE (recommended for production — survives a single-zone outage)."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.zone_distribution_mode == null ? true : contains(["SINGLE_ZONE", "MULTI_ZONE"], var.zone_distribution_mode)
    error_message = "zone_distribution_mode must be either SINGLE_ZONE or MULTI_ZONE."
  }
}

# --- OPTIONAL ---
variable "zone" {
  description = "Zone to pin the instance to. Only used when zone_distribution_mode = SINGLE_ZONE; if left null in that mode, the module auto-selects the first available zone in the region. Must be left null for MULTI_ZONE. No centralized default — null is a meaningful 'auto-select' state, not a value to retune."
  type        = string
  default     = null
  nullable    = true
}

# --- OPTIONAL ---
variable "secondary_zone" {
  description = "Zone to pin the SECONDARY (DR) instance to. Only used when deployment_topology = DR and zone_distribution_mode = SINGLE_ZONE. Auto-selected if left null."
  type        = string
  default     = null
  nullable    = true
}

############################################
# Cluster Topology & Sizing
############################################

# --- OPTIONAL ---
variable "cluster_mode" {
  description = "Cluster Mode Enabled (CLUSTER) or Disabled (CLUSTER_DISABLED). Cannot be changed after creation."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.cluster_mode == null ? true : contains(["CLUSTER", "CLUSTER_DISABLED"], var.cluster_mode)
    error_message = "cluster_mode must be either 'CLUSTER' or 'CLUSTER_DISABLED'."
  }
}

# --- OPTIONAL ---
variable "node_type" {
  description = "Machine type for individual nodes. Determines vCPU count, memory capacity, and max client connections per node. SHARED_CORE_NANO has no SLA — DEV/test only (blocked in PROD by precondition)."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.node_type == null ? true : contains([
      "SHARED_CORE_NANO", "CUSTOM_PICO", "CUSTOM_MICRO", "CUSTOM_MINI",
      "HIGHMEM_MEDIUM", "HIGHCPU_MEDIUM", "HIGHMEM_XLARGE",
      "STANDARD_SMALL", "STANDARD_LARGE", "HIGHMEM_2XLARGE"
    ], var.node_type)
    error_message = "node_type must be one of: SHARED_CORE_NANO, CUSTOM_PICO, CUSTOM_MICRO, CUSTOM_MINI, HIGHMEM_MEDIUM, HIGHCPU_MEDIUM, HIGHMEM_XLARGE, STANDARD_SMALL, STANDARD_LARGE, HIGHMEM_2XLARGE."
  }
}

# --- REQUIRED ---
variable "shard_count" {
  description = "Number of shards. Determines total memory capacity. Must be exactly 1 when cluster_mode = CLUSTER_DISABLED. Required — no module-wide default value makes sense for capacity sizing."
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

# --- OPTIONAL ---
variable "replica_count" {
  description = "Number of replica nodes per shard. 0-5. If you're also using terraform-google-valkey-alerts, pass replica_count > 0 as that module's enable_replication_lag_alert input to turn on the replication-lag alert."
  type        = number
  default     = null
  nullable    = true

  validation {
    condition     = var.replica_count == null ? true : (var.replica_count >= 0 && var.replica_count <= 5)
    error_message = "replica_count must be between 0 and 5 (inclusive)."
  }
  validation {
    condition     = var.replica_count == null ? true : var.replica_count == floor(var.replica_count)
    error_message = "replica_count must be a whole number."
  }
}

############################################
# PSC Connectivity Mode
############################################

# --- OPTIONAL ---
variable "psc_connectivity_mode" {
  type        = string
  description = <<-EOT
    How PSC connections to the instance are established.

    NONE: No PSC connectivity is configured by this module. The instance is
      created with no desired_auto_created_endpoints block — nothing can
      reach it over PSC until connectivity is set up some other way.

    SHARED_VPC: The instance attaches to an existing Shared VPC network that
      is already set up for it — the network (shared_vpc_network_name) and
      its Service Connection Policy (existing_scp_name, service_class =
      gcp-memorystore) both already exist, created outside this module.
      This module does not create the VPC or the SCP, and does not create
      a forwarding rule or reserved IP either — it only points the instance
      at the network via desired_auto_created_endpoints. Because the SCP
      is already there and pre-authorizes gcp-memorystore into that
      network/region, Memorystore auto-creates the PSC endpoint itself the
      moment the instance is created. No second apply, no manual endpoint
      registration.
  EOT
  default     = null
  nullable    = true

  validation {
    condition     = var.psc_connectivity_mode == null ? true : contains(["NONE", "SHARED_VPC"], var.psc_connectivity_mode)
    error_message = "psc_connectivity_mode must be one of: NONE, SHARED_VPC."
  }
}

# --- OPTIONAL ---
variable "shared_vpc_host_project" {
  type        = string
  description = "Host project of the existing Shared VPC network. Required when psc_connectivity_mode = SHARED_VPC."
  default     = null
  nullable    = true
}

# --- OPTIONAL ---
variable "shared_vpc_network_name" {
  type        = string
  description = "Name of the existing Shared VPC network. Required when psc_connectivity_mode = SHARED_VPC."
  default     = null
  nullable    = true
}

# --- OPTIONAL ---
variable "existing_scp_name" {
  type        = string
  description = "Name of the already-existing Service Connection Policy (service_class = gcp-memorystore) that authorizes this connection. Guardrail-only: the google provider has no read-only data source for Service Connection Policies, so this cannot be verified by Terraform. Confirm out-of-band before relying on it (see README)."
  default     = null
  nullable    = true
}

############################################
# Authorization (AUTH) & TLS
############################################

# --- OPTIONAL ---
variable "authorization_mode" {
  type        = string
  description = "Client authentication mode. IAM_AUTH is the only value this module accepts — clients authenticate using short-lived IAM access tokens, integrated with Cloud IAM roles/audit logs. There is no supported way to disable authentication through this module: leave this unset to get IAM_AUTH by default, or set it explicitly to IAM_AUTH for clarity in state/plan output. AUTH_DISABLED is not offered, even though it's a valid value on the underlying google_memorystore_instance resource — every instance this module creates requires authentication."
  default     = null
  nullable    = true

  validation {
    condition     = var.authorization_mode == null ? true : var.authorization_mode == "IAM_AUTH"
    error_message = "authorization_mode must be IAM_AUTH (or unset, which defaults to IAM_AUTH) — this module does not support AUTH_DISABLED. Every instance created by this module requires client authentication; there is no override for this."
  }
}

# --- OPTIONAL ---
variable "transit_encryption_mode" {
  type        = string
  description = "In-transit (TLS) encryption mode. SERVER_AUTHENTICATION is the only value this module accepts — TLS enabled, client verifies server identity via CA cert. There is no supported way to disable TLS through this module: leave this unset to get SERVER_AUTHENTICATION by default, or set it explicitly for clarity in state/plan output. TRANSIT_ENCRYPTION_DISABLED is not offered, even though it's a valid value on the underlying google_memorystore_instance resource — combined with authorization_mode always being IAM_AUTH, disabling TLS would send IAM access tokens over the wire in plaintext."
  default     = null
  nullable    = true

  validation {
    condition     = var.transit_encryption_mode == null ? true : var.transit_encryption_mode == "SERVER_AUTHENTICATION"
    error_message = "transit_encryption_mode must be SERVER_AUTHENTICATION (or unset, which defaults to SERVER_AUTHENTICATION) — this module does not support TRANSIT_ENCRYPTION_DISABLED. authorization_mode is always IAM_AUTH in this module, and IAM access tokens sent without TLS are exposed in plaintext; there is no override for this."
  }
}

############################################
# Certificate Authority (CA) Management
############################################

# --- OPTIONAL ---
variable "server_ca_mode" {
  type        = string
  description = <<-EOT
    CA mode for TLS server certificates. Immutable after creation — cannot be
    changed or deactivated once the instance is created.

    GOOGLE_MANAGED_PER_INSTANCE_CA (default): Google generates a unique CA per
      instance. Every client must download and install that instance's specific
      CA cert. Highest isolation, highest client-side cert management overhead.

    GOOGLE_MANAGED_SHARED_CA: Google manages a single regional CA bundle shared
      across all instances in that region. Clients install one bundle per
      region instead of one per instance — simplest to operate at scale.

    CUSTOMER_MANAGED_CAS_CA: Uses your own CA pool in Certificate Authority
      Service (CAS). Requires server_ca_pool to be set. Best for compliance
      requirements around key custody/rotation.
  EOT
  default     = null
  nullable    = true

  validation {
    condition = var.server_ca_mode == null ? true : contains(
      ["GOOGLE_MANAGED_PER_INSTANCE_CA", "GOOGLE_MANAGED_SHARED_CA", "CUSTOMER_MANAGED_CAS_CA"],
      var.server_ca_mode
    )
    error_message = "server_ca_mode must be one of: GOOGLE_MANAGED_PER_INSTANCE_CA, GOOGLE_MANAGED_SHARED_CA, CUSTOMER_MANAGED_CAS_CA."
  }
}

# --- OPTIONAL ---
variable "server_ca_pool" {
  type        = string
  description = "Full resource ID of the CA pool in Certificate Authority Service, e.g. \"projects/PROJECT_ID/locations/REGION/caPools/POOL_ID\". Required only when server_ca_mode = CUSTOMER_MANAGED_CAS_CA; must be in the same region as the instance."
  default     = null
  nullable    = true
}

############################################
# Encryption at Rest (CMEK)
############################################

# --- OPTIONAL ---
variable "encryption_type" {
  type        = string
  description = "Encryption at rest. GOOGLE_MANAGED = Google's default encryption, no key management overhead. CUSTOMER_MANAGED (CMEK) = you control the key in Cloud KMS, giving you key rotation, revocation, and audit-log control over data access."
  default     = null
  nullable    = true

  validation {
    condition     = var.encryption_type == null ? true : contains(["GOOGLE_MANAGED", "CUSTOMER_MANAGED"], var.encryption_type)
    error_message = "encryption_type must be one of: GOOGLE_MANAGED, CUSTOMER_MANAGED."
  }
}

# --- OPTIONAL ---
variable "kms_key" {
  type        = string
  description = "Full resource ID of the Cloud KMS CryptoKey, e.g. \"projects/PROJECT_ID/locations/REGION/keyRings/RING_ID/cryptoKeys/KEY_ID\". Required when encryption_type = CUSTOMER_MANAGED. Must be a symmetric key in the same region as the instance."
  default     = null
  nullable    = true

  validation {
    condition = (
      var.kms_key == null ? true :
      can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key))
    )
    error_message = "kms_key must be a full CryptoKey resource ID: projects/PROJECT_ID/locations/REGION/keyRings/RING_ID/cryptoKeys/KEY_ID."
  }
}

############################################
# Persistence
############################################

# --- OPTIONAL ---
variable "persistence_mode" {
  type        = string
  description = "Data persistence strategy. RDB = periodic point-in-time snapshots. AOF = append-only log of every write, higher durability. DISABLED = no persistence (data lost on restart/failover, no recovery source)."
  default     = null
  nullable    = true

  validation {
    condition     = var.persistence_mode == null ? true : contains(["RDB", "AOF", "DISABLED"], var.persistence_mode)
    error_message = "persistence_mode must be one of: RDB, AOF, DISABLED."
  }
}

# --- OPTIONAL ---
variable "rdb_snapshot_period" {
  type        = string
  description = "Snapshot interval when persistence_mode = RDB. Required in that case, ignored otherwise."
  default     = null
  nullable    = true

  validation {
    condition = (
      var.rdb_snapshot_period == null ? true :
      contains(["ONE_HOUR", "SIX_HOURS", "TWELVE_HOURS", "TWENTY_FOUR_HOURS"], var.rdb_snapshot_period)
    )
    error_message = "rdb_snapshot_period must be one of: ONE_HOUR, SIX_HOURS, TWELVE_HOURS, TWENTY_FOUR_HOURS."
  }
}

# --- OPTIONAL ---
variable "rdb_snapshot_start_time" {
  type        = string
  description = "RFC3339 UTC timestamp for the first RDB snapshot window (e.g. \"2024-10-02T15:01:23Z\"). Optional even when mode = RDB; if omitted, Google schedules the first snapshot immediately. Required (must be explicit) when deployment_topology = DR and persistence_mode = RDB — see the persistence_config_consistency check."
  default     = null
  nullable    = true
}

# --- OPTIONAL ---
variable "aof_config" {
  type = object({
    append_fsync = string
  })
  description = "AOF fsync policy when persistence_mode = AOF. ALWAYS = fsync every write (safest, highest latency). EVERY_SEC = fsync every second (recommended default). NO = OS decides (least durable)."
  default     = null
  nullable    = true

  validation {
    condition     = var.aof_config == null ? true : contains(["ALWAYS", "EVERY_SEC", "NO"], var.aof_config.append_fsync)
    error_message = "aof_config.append_fsync must be one of: ALWAYS, EVERY_SEC, NO."
  }
}

############################################
# Automated Backups
############################################

# --- OPTIONAL ---
variable "automated_backup_enabled" {
  type        = bool
  description = "Whether to enable Memorystore's automated backup feature on the primary instance (separate from RDB/AOF persistence — a GCS-backed backup collection that survives instance deletion). The secondary (DR) instance never gets this, regardless of this value — see the note in all-locals.tf."
  default     = null
  nullable    = true
}

# --- OPTIONAL ---
variable "automated_backup_start_time_hour" {
  type        = number
  description = "Hour of day (UTC, 0-23) when the daily automated backup window begins. Only used when automated_backup_enabled = true."
  default     = null
  nullable    = true

  validation {
    condition     = var.automated_backup_start_time_hour == null ? true : (var.automated_backup_start_time_hour >= 0 && var.automated_backup_start_time_hour <= 23)
    error_message = "automated_backup_start_time_hour must be between 0 and 23."
  }
}

# --- OPTIONAL ---
variable "automated_backup_retention_days" {
  type        = number
  description = "Number of days to retain each automated backup (1-365). GCP default is 35 if unset; this module always sets it explicitly for clarity."
  default     = null
  nullable    = true

  validation {
    condition     = var.automated_backup_retention_days == null ? true : (var.automated_backup_retention_days >= 1 && var.automated_backup_retention_days <= 365)
    error_message = "automated_backup_retention_days must be between 1 and 365."
  }
}

############################################
# Maintenance Window
############################################

# --- OPTIONAL ---
variable "maintenance_day" {
  type        = string
  description = "Day of week for the weekly maintenance window (UTC)."
  default     = null
  nullable    = true

  validation {
    condition = var.maintenance_day == null ? true : contains(
      ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"],
      var.maintenance_day
    )
    error_message = "maintenance_day must be a valid day of week (MONDAY-SUNDAY)."
  }
}

# --- OPTIONAL ---
variable "maintenance_start_hour" {
  type        = number
  description = "Hour (UTC, 0-23) the weekly maintenance window begins. Pick your lowest-traffic period."
  default     = null
  nullable    = true

  validation {
    condition     = var.maintenance_start_hour == null ? true : (var.maintenance_start_hour >= 0 && var.maintenance_start_hour <= 23)
    error_message = "maintenance_start_hour must be between 0 and 23."
  }
}

############################################
# Engine Version & Configuration Parameters
############################################

# --- OPTIONAL ---
variable "engine_version" {
  type        = string
  description = "Valkey engine version. Immutable after creation — changing this forces a new instance (or requires a documented major-version upgrade path outside Terraform)."
  default     = null
  nullable    = true

  validation {
    condition     = var.engine_version == null ? true : contains(["VALKEY_7_2", "VALKEY_8_0", "VALKEY_9_0"], var.engine_version)
    error_message = "engine_version must be one of: VALKEY_7_2, VALKEY_8_0, VALKEY_9_0 (check current GA versions in provider docs before deploying — Google adds new versions over time)."
  }
}

# --- OPTIONAL ---
variable "maxmemory_policy" {
  type        = string
  description = "Eviction policy when the instance reaches maxmemory. volatile-lru (default) only evicts keys with a TTL set; allkeys-lru evicts any key; noeviction rejects writes at capacity instead of evicting."
  default     = null
  nullable    = true

  validation {
    condition = var.maxmemory_policy == null ? true : contains(
      ["noeviction", "allkeys-lfu", "allkeys-lru", "volatile-lfu", "volatile-lru", "allkeys-random", "volatile-random", "volatile-ttl"],
      var.maxmemory_policy
    )
    error_message = "maxmemory_policy must be a valid Valkey maxmemory-policy value."
  }
}

# --- OPTIONAL ---
variable "notify_keyspace_events" {
  type        = string
  description = "Keyspace notification classes to enable (pub/sub events on key changes/expiry). Empty string disables notifications (default, lowest overhead). E.g. \"Ex\" = expired-key events only, \"KEA\" = all events. Leave unset unless something actually consumes these events — it adds CPU/pubsub overhead."
  default     = null
  nullable    = true
}

# --- OPTIONAL ---
variable "maxmemory_clients" {
  type        = string
  description = "Cap on total memory used by client-side output buffers, e.g. \"10%\" or an absolute byte value like \"100mb\". Protects the instance from being OOM-killed by a slow/misbehaving client draining a large response slowly. Leave null to use Valkey's default."
  default     = null
  nullable    = true
}

# --- OPTIONAL ---
variable "slowlog_log_slower_than" {
  type        = number
  description = "Microseconds a command must take to be logged to the slow log. -1 disables, 0 logs everything (expensive). Useful for catching expensive commands (e.g. unbounded KEYS/SCAN) before they degrade the instance."
  default     = null
  nullable    = true
}

# --- OPTIONAL ---
variable "maxclients" {
  type        = number
  description = "Maximum simultaneous client connections. Leave null for Valkey's default (sized to node type). Lower this for an early rejection signal instead of the instance being overwhelmed by a connection storm."
  default     = null
  nullable    = true
}

############################################
# Deletion Protection
############################################

# --- OPTIONAL ---
variable "deletion_protection_enabled" {
  type        = bool
  description = "If true, deletion of the instance is blocked at the API level. Defaults (see all-locals.tf) to true — this module is meant for production; set to false explicitly for short-lived test instances."
  default     = null
  nullable    = true
}

############################################
# Alerting
#
# This module only provisions the Valkey instance. Cloud Monitoring
# alert policies and email notification channels live in a separate
# module — terraform-google-valkey-alerts — wired up against this
# module's `instance_id` / `resolved_location` outputs. That split is
# deliberate: updating who gets emailed about an alert (adding/removing
# an address) should never require a plan/apply against this instance's
# infrastructure, and shouldn't need to go through whatever change
# process governs the instance itself. See that module's README.
############################################

############################################
# Cross-field checks — these validate combinations of EFFECTIVE
# (post-default) values in all-locals.tf, not raw var.* inputs, since a
# variable left null here no longer means "unset" — it means "use the
# centralized default."
############################################

check "deployment_topology_replica_count" {
  assert {
    condition     = local.deployment_topology != "STANDALONE" || local.replica_count == 0
    error_message = "deployment_topology = STANDALONE requires replica_count = 0."
  }
  assert {
    condition     = local.deployment_topology == "STANDALONE" || local.replica_count >= 1
    error_message = "deployment_topology = HA or DR requires replica_count >= 1. (MULTI_ZONE zone_distribution_mode is also recommended for HA/DR, but not enforced here.)"
  }
}

check "dr_requires_secondary_location" {
  assert {
    condition     = local.deployment_topology != "DR" || var.secondary_location != null
    error_message = "deployment_topology = DR requires secondary_location to be set."
  }
}

check "shared_vpc_inputs_present" {
  assert {
    condition = local.psc_connectivity_mode != "SHARED_VPC" || (
      var.shared_vpc_host_project != null &&
      var.shared_vpc_network_name != null
    )
    error_message = "psc_connectivity_mode = SHARED_VPC requires shared_vpc_host_project and shared_vpc_network_name."
  }
}

check "iam_auth_requires_tls" {
  # Belt-and-suspenders: authorization_mode and transit_encryption_mode
  # variable validations above already make this combination
  # unreachable (only IAM_AUTH / SERVER_AUTHENTICATION are accepted at
  # all), but this stays as a second, independent guard against a
  # regression in those validations.
  assert {
    condition = !(
      local.authorization_mode == "IAM_AUTH" &&
      local.transit_encryption_mode == "TRANSIT_ENCRYPTION_DISABLED"
    )
    error_message = "authorization_mode = IAM_AUTH requires transit_encryption_mode = SERVER_AUTHENTICATION. IAM access tokens are sent via the AUTH command in plaintext otherwise, exposing them on the wire."
  }
}

check "customer_managed_ca_requires_pool" {
  assert {
    condition     = !(local.server_ca_mode == "CUSTOMER_MANAGED_CAS_CA" && var.server_ca_pool == null)
    error_message = "server_ca_mode = CUSTOMER_MANAGED_CAS_CA requires server_ca_pool to be set to a valid CA pool resource ID."
  }
}

check "server_ca_pool_requires_tls" {
  assert {
    condition = !(
      local.server_ca_mode == "CUSTOMER_MANAGED_CAS_CA" &&
      local.transit_encryption_mode == "TRANSIT_ENCRYPTION_DISABLED"
    )
    error_message = "A configured server_ca_mode requires transit_encryption_mode = SERVER_AUTHENTICATION. TLS cannot be disabled once a CA mode is configured."
  }
}

check "cmek_requires_kms_key" {
  assert {
    condition     = !(local.encryption_type == "CUSTOMER_MANAGED" && var.kms_key == null)
    error_message = "encryption_type = CUSTOMER_MANAGED requires kms_key to be set."
  }
}

check "persistence_config_consistency" {
  assert {
    condition     = !(local.persistence_mode == "RDB" && var.rdb_snapshot_period == null)
    error_message = "persistence_mode = RDB requires rdb_snapshot_period to be set."
  }
  assert {
    condition     = !(local.persistence_mode == "AOF" && var.aof_config == null)
    error_message = "persistence_mode = AOF requires aof_config to be set."
  }
  assert {
    condition     = !(local.deployment_topology == "DR" && local.persistence_mode == "RDB" && var.rdb_snapshot_start_time == null)
    error_message = "deployment_topology = DR with persistence_mode = RDB requires rdb_snapshot_start_time to be an explicit value, not null. Left null, GCP auto-assigns its own timestamp independently to the primary and secondary at creation time, and the two never match — the API then rejects the secondary with \"persistence_config cannot be different from the primary instance\". Set any fixed RFC3339 timestamp; primary and secondary receive the identical value from this same variable, so any explicit value fixes it."
  }
}


