# Valkey Terraform Module — Full `.tfvars` Template

Every variable the module accepts, with comments explaining each one, valid
values, and defaults. Copy the block below into your own `.tfvars` file,
delete what you don't need (most have sensible defaults), and fill in the
rest.

```hcl
############################################
# Core Identity
############################################

project_id          = ""  # REQUIRED. Host project — where the Memorystore instance is created. No default.
consumer_project_id = ""    # Project where the consumer VPC lives. Defaults to project_id if omitted (same-project deployments).
environment          = "DEV"                    # REQUIRED. One of: DEV, QA, UAT, PROD. Drives stricter preconditions (e.g. blocks SHARED_CORE_NANO in PROD).
instance_id          = "valkey-basic"           # Permanent, unique instance identifier. Immutable after creation. Default: "basic-instance".

############################################
# Region / Zone
############################################

location                = "us-central1"  # GCP region. Default: "us-central1".
zone_distribution_mode  = "MULTI_ZONE"   # SINGLE_ZONE or MULTI_ZONE. Default: MULTI_ZONE (recommended — survives a zone outage).
zone                    = null            # Only used when zone_distribution_mode = SINGLE_ZONE. Must be null for MULTI_ZONE. Auto-selected if left null in SINGLE_ZONE mode.

############################################
# Deployment Topology & Disaster Recovery
############################################

deployment_topology              = "STANDALONE"  # STANDALONE | HA | DR. Self-documenting label, validated for consistency against replica_count/enable_cross_region_replication below.
enable_cross_region_replication  = false          # true only for DR. Creates a SECONDARY instance in secondary_location.
secondary_location                = null            # Region for the SECONDARY (DR) instance. REQUIRED if enable_cross_region_replication = true. Must differ from `location`.
secondary_zone                    = null            # Zone to pin the secondary to. Only used with SINGLE_ZONE + DR. Auto-selected if left null.

# Consistency rules enforced by the module's check blocks:
#   STANDALONE  -> replica_count must be 0, enable_cross_region_replication must be false
#   HA          -> replica_count must be >= 1, enable_cross_region_replication must be false
#   DR          -> enable_cross_region_replication must be true (secondary_location required)

############################################
# Cluster Topology & Sizing
############################################

cluster_mode  = "CLUSTER"          # CLUSTER (sharded, Cluster Mode Enabled) or CLUSTER_DISABLED (single primary + replicas, classic Redis-style). Immutable after creation. Default: "CLUSTER".
node_type     = "STANDARD_SMALL"   # Machine type. Options: SHARED_CORE_NANO (DEV/test only, no SLA, blocked in PROD), CUSTOM_PICO, CUSTOM_MICRO, CUSTOM_MINI (CLUSTER_DISABLED only), HIGHMEM_MEDIUM, HIGHCPU_MEDIUM, HIGHMEM_XLARGE, STANDARD_SMALL, STANDARD_LARGE, HIGHMEM_2XLARGE. Default: "STANDARD_SMALL".
shard_count   = 1                   # REQUIRED. Number of shards. Must be exactly 1 when cluster_mode = CLUSTER_DISABLED. Max ~125 (regional quota dependent).
replica_count = 0                   # Replica nodes per shard, 0-5. Default: 0. Required >= 1 for deployment_topology = HA.

############################################
# PSC Connectivity Mode
############################################

psc_connectivity_mode = "AUTO"  # AUTO (Memorystore creates the forwarding rule for you, single consumer VPC, same or cross-project) or USER (you create + register forwarding rules yourself; required for multi-VPC or when you want explicit control). Default: "AUTO".

# Only used when psc_connectivity_mode = "USER". Map of consumer VPC networks
# to wire up, keyed by a short name. Each entry gets its own network, subnet,
# reserved IP, and forwarding rule.
user_networks = {
  serviceproj1 = {
    subnet_cidr = "10.10.0.0/28"
  }
  # add more entries here for additional consumer VPCs
}

# Number of service attachments the instance exposes. NOT proportional to
# shard_count/replica_count — CLUSTER mode always exposes exactly 2
# (DISCOVERY + a paired attachment), regardless of cluster size, since
# clients route between shards via the cluster protocol (MOVED/ASK
# redirects) over a single connection, not via one PSC attachment per
# shard. CLUSTER_DISABLED instances expose 2 as well (PRIMARY + READER).
# In practice this value is almost always 2 — verify against
# psc_attachment_details after first apply if in doubt.
psc_attachment_count = 2

############################################
# Authorization (AUTH) & TLS
############################################

authorization_mode      = "IAM_AUTH"              # AUTH_DISABLED (no auth — never use in production) or IAM_AUTH (short-lived IAM tokens). Default: "IAM_AUTH".
transit_encryption_mode = "SERVER_AUTHENTICATION"  # TRANSIT_ENCRYPTION_DISABLED or SERVER_AUTHENTICATION (TLS). Required to be SERVER_AUTHENTICATION when authorization_mode = IAM_AUTH. Default: "SERVER_AUTHENTICATION".

############################################
# Certificate Authority (CA) Management
############################################

# Immutable after creation — cannot be changed or deactivated once the
# instance exists. Options:
#   GOOGLE_MANAGED_PER_INSTANCE_CA (default) — unique CA per instance, clients must install each instance's cert
#   GOOGLE_MANAGED_SHARED_CA        — one regional CA bundle shared across instances, simplest at scale
#   CUSTOMER_MANAGED_CAS_CA          — your own CA pool in Certificate Authority Service (requires server_ca_pool)
server_ca_mode = "GOOGLE_MANAGED_PER_INSTANCE_CA"

server_ca_pool = null  # Full CA pool resource ID, e.g. "projects/PROJECT_ID/locations/REGION/caPools/POOL_ID". REQUIRED if server_ca_mode = CUSTOMER_MANAGED_CAS_CA.

############################################
# Encryption at Rest (CMEK)
############################################

encryption_type = "GOOGLE_MANAGED"  # GOOGLE_MANAGED (default) or CUSTOMER_MANAGED (CMEK — requires kms_key).
kms_key          = null              # Full CryptoKey resource ID, e.g. "projects/PROJECT_ID/locations/REGION/keyRings/RING_ID/cryptoKeys/KEY_ID". REQUIRED if encryption_type = CUSTOMER_MANAGED. Must be symmetric, same region as instance.

############################################
# Persistence
############################################

persistence_mode = "RDB"  # REQUIRED. RDB (periodic snapshots), AOF (append-only log, higher durability), or DISABLED (no persistence — data lost on restart/failover).

# --- Only used when persistence_mode = "RDB" ---
rdb_snapshot_period     = "ONE_HOUR"  # ONE_HOUR | SIX_HOURS | TWELVE_HOURS | TWENTY_FOUR_HOURS. REQUIRED if persistence_mode = RDB.
rdb_snapshot_start_time = null         # RFC3339 UTC timestamp, e.g. "2026-07-14T03:00:00Z". Optional — if null, Google schedules the first snapshot immediately.

# --- Only used when persistence_mode = "AOF" (use instead of the RDB block above, not alongside it) ---
aof_config = {
  append_fsync = "EVERY_SEC"  # ALWAYS (fsync every write, safest/slowest) | EVERY_SEC (recommended default) | NO (OS decides, least durable)
}
# aof_config = null  # set persistence_mode = "RDB" or "DISABLED" instead, and leave this null, if not using AOF

############################################
# Automated Backups
############################################

automated_backup_enabled          = true   # GCS-backed backup collection, separate from persistence — survives instance deletion. Default: true.
automated_backup_start_time_hour  = 3       # UTC hour (0-23) the daily backup window begins. Default: 3.
automated_backup_retention_days   = 35      # Days to retain each backup, 1-365. Default: 35.

############################################
# Maintenance Window
############################################

maintenance_day        = "SUNDAY"  # MONDAY | TUESDAY | WEDNESDAY | THURSDAY | FRIDAY | SATURDAY | SUNDAY. Default: "SUNDAY".
maintenance_start_hour = 4          # UTC hour (0-23) the weekly maintenance window begins. Default: 4. Pick your lowest-traffic period.

############################################
# Engine Version & Configuration Parameters
############################################

engine_version = "VALKEY_9_0"  # VALKEY_7_2 | VALKEY_8_0 | VALKEY_9_0. Immutable after creation. Default: "VALKEY_7_2". Verify current GA versions before deploying — Google adds new ones over time.

maxmemory_policy       = "volatile-lru"  # Eviction policy at maxmemory. volatile-lru (default, only evicts TTL'd keys) | allkeys-lru | allkeys-lfu | volatile-lfu | allkeys-random | volatile-random | volatile-ttl | noeviction.
notify_keyspace_events = ""               # Keyspace notification classes, e.g. "KEA" for all events. Default: "" (disabled). Only enable if something actually consumes these — real CPU/pubsub overhead.
maxmemory_clients       = null             # Cap on client output buffer memory, e.g. "10%" or "100mb". Default: null (Valkey's own default).
slowlog_log_slower_than = 10000            # Microseconds a command must take to be slow-logged. -1 disables, 0 logs everything. Default: 10000 (10ms).
maxclients               = null             # Max simultaneous client connections. Default: null (sized to node_type).

############################################
# Deletion Protection
############################################

deletion_protection_enabled = true  # API-enforced (blocks delete via console/gcloud/API too, not just terraform destroy). Default: true. Set false explicitly for disposable test instances.
```

## Quick presets

**Cheapest possible test instance** (mirrors this module's own `test.tfvars`):
```hcl
environment                  = "DEV"
cluster_mode                 = "CLUSTER_DISABLED"
node_type                    = "SHARED_CORE_NANO"
shard_count                  = 1
replica_count                = 0
authorization_mode           = "AUTH_DISABLED"
transit_encryption_mode      = "TRANSIT_ENCRYPTION_DISABLED"
persistence_mode             = "DISABLED"
automated_backup_enabled     = false
deletion_protection_enabled  = false
```

**Production HA, single region:**
```hcl
environment             = "PROD"
cluster_mode            = "CLUSTER_DISABLED"
node_type               = "STANDARD_SMALL"
replica_count           = 1
zone_distribution_mode  = "MULTI_ZONE"
deployment_topology     = "HA"
authorization_mode      = "IAM_AUTH"
transit_encryption_mode = "SERVER_AUTHENTICATION"
persistence_mode        = "AOF"
aof_config              = { append_fsync = "EVERY_SEC" }
automated_backup_enabled = true
```

**Production DR, cross-region:**
```hcl
deployment_topology              = "DR"
enable_cross_region_replication  = true
secondary_location                 = "us-east1"
replica_count                       = 1  # recommended alongside DR, not automatically enforced — see module notes
```
