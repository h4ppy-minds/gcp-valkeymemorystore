# Valkey Terraform Module — Full `.tfvars` Template

Every variable the project accepts, with comments explaining each one, valid
values, and defaults. Copy the block below into your own `.tfvars` file,
delete what you don't need (most have sensible defaults), and fill in the
rest.

> **Note on connectivity modes:** this module supports only `NONE` (no
> private connectivity — instance only) and `SHARED_VPC` (attach to an
> existing Shared VPC network + a Service Connection Policy your platform
> team already created). The `AUTO` and `USER` modes described in earlier
> drafts of this module were removed — they created their own isolated VPC
> (AUTO) or per-team VPCs (USER), which doesn't match this org's actual
> networking (a central Shared VPC hub with a pre-existing SCP already
> provisioned). See README.md for the full explanation.

```hcl
############################################
# Core Identity
############################################

project_id          = ""  # REQUIRED. Host project — where the Memorystore instance is created. No default.
consumer_project_id = ""    # Legacy input from the removed AUTO/USER modes. Not used by NONE or SHARED_VPC — verify modules/valkey/variables.tf still accepts it before setting this; if it was dropped there, remove it here too.
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
#
# Note: if you use DR (enable_cross_region_replication = true) together
# with psc_connectivity_mode = SHARED_VPC, the SECONDARY instance needs
# its own existing SCP in secondary_location — SCPs are strictly
# regional, so the primary's SCP does not cover the secondary. Confirm
# your module has an existing_scp_name-equivalent input for the
# secondary before relying on this combination.

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

psc_connectivity_mode = "NONE"  # NONE (no private connectivity — instance only, useful for a bare-instance smoke test) or SHARED_VPC (attach to an existing Shared VPC network + a pre-existing Service Connection Policy). Default: "NONE".

# --- Only used when psc_connectivity_mode = "SHARED_VPC" ---
shared_vpc_host_project = ""  # Host project ID that owns the existing Shared VPC network (the network "hub" project). REQUIRED if psc_connectivity_mode = SHARED_VPC.
shared_vpc_network_name = ""  # Name of the existing Shared VPC network itself (the VPC's own name, not a project id — check console under VPC networks). REQUIRED if psc_connectivity_mode = SHARED_VPC.
existing_scp_name       = ""  # Name of the existing Service Connection Policy (service_class = gcp-memorystore) your platform team already created for `location`. SCPs are regional — this must match a policy scoped to `location`, not just any policy in the host project. REQUIRED if psc_connectivity_mode = SHARED_VPC.

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

# ⚠️ Known inconsistency to verify in modules/valkey/variables.tf: the
# server_ca_mode validation enum uses "CUSTOMER_MANAGED_CAS_CA", but the
# module's check blocks (customer_managed_ca_requires_pool,
# server_ca_pool_requires_tls) compare against "CUSTOMER_MANAGED_CA" —
# missing "_CAS_". As written, those two checks can never fire, even
# when server_ca_pool is genuinely missing. Fix the check blocks to
# compare against "CUSTOMER_MANAGED_CAS_CA" before relying on that
# validation in production.

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

**Cheapest possible bare-instance test (NONE mode — no PSC connectivity):**
```hcl
psc_connectivity_mode        = "NONE"
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

**Shared VPC, single region (typical enterprise deployment):**
```hcl
psc_connectivity_mode   = "SHARED_VPC"
shared_vpc_host_project = "gcp3-core-net-npe-4b70"   # your network hub project
shared_vpc_network_name = ""                          # fill in the actual VPC network name from console
existing_scp_name       = ""                          # fill in the SCP name for this `location`, shown under Network Connectivity > PSC in console

environment             = "DEV"
cluster_mode            = "CLUSTER_DISABLED"
node_type               = "SHARED_CORE_NANO"
shard_count             = 1
replica_count           = 0
authorization_mode      = "AUTH_DISABLED"
transit_encryption_mode = "TRANSIT_ENCRYPTION_DISABLED"
persistence_mode        = "DISABLED"
automated_backup_enabled    = false
deletion_protection_enabled = false
```

**Production HA, Shared VPC, single region:**
```hcl
psc_connectivity_mode   = "SHARED_VPC"
shared_vpc_host_project = "gcp3-core-net-npe-4b70"
shared_vpc_network_name = ""
existing_scp_name       = ""

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

**Production DR, Shared VPC, cross-region:**
```hcl
psc_connectivity_mode   = "SHARED_VPC"
shared_vpc_host_project = "gcp3-core-net-npe-4b70"
shared_vpc_network_name = ""
existing_scp_name       = ""   # SCP for the PRIMARY region

deployment_topology              = "DR"
enable_cross_region_replication  = true
secondary_location                 = "us-east1"
replica_count                       = 1  # recommended alongside DR, not automatically enforced — see module notes

# ⚠️ Verify: the secondary instance needs its own existing SCP in
# secondary_location. If modules/valkey doesn't yet expose an
# existing_scp_name input for the secondary specifically, this
# combination isn't fully wired up yet — check before relying on it.
```