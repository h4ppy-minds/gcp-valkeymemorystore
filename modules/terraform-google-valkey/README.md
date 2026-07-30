# Terraform Module: Memorystore for Valkey (instance + alerting)

Single, reusable Terraform module for a Google Cloud Memorystore for
Valkey instance — persistence, backups, maintenance windows,
authentication/TLS, CA management, encryption at rest, optional Shared
VPC connectivity, optional cross-region DR — **plus** the Cloud
Monitoring alert policies and email notification channels for that
instance, in the same module call.

**This replaces two previously-separate modules** (`memorystore-valkey`
and `valkey-alerting`). One `module` block now produces the instance(s)
and its alerting; `enable_alerting` is the only thing you flip if you
want the instance without alerting from this module.

## Why one module instead of two

The old alerting module needed `instance_id` and `region` passed back in
from the instance module's outputs by hand in every root module that used
both. Folding it in means:

- One `source`, one set of variables, one place to look for a given
  instance's full configuration.
- Alerting always targets the actual created `instance_id` and its real
  `location` — pulled straight from `module.primary`, not re-typed by the
  caller.
- Still fully optional: `enable_alerting = false` gives you the instance
  only, same as before.

## The "one file for defaults" design

Every tunable default value in this module lives in exactly one of two
files, split by concern:

- **`all-locals.tf`** — Valkey **instance** defaults (`local.defaults`
  map: topology, sizing, persistence, auth/TLS/CA, backups, maintenance,
  engine config). These remain overridable per caller via the matching
  variable.
- **`alerts.tf`** — **alerting** defaults (`local.alert_defaults` map:
  every threshold, duration, and metric/resource-type string). These are
  **not** exposed as variables at all — see "Alerting is intentionally
  not tunable per caller" below.

Mechanically, for the instance side:
- Variables that have a default don't carry a literal value in
  `variables.tf` — they default to `null`.
- `all-locals.tf` computes the effective value of each as
  `coalesce(var.x, local.defaults.x)`.
- `main.tf` and `data.tf` all read the `local.x` effective value —
  never `var.x` directly — for anything that has a default.

**To change an instance default** (e.g. bump the default `node_type`,
turn off automated backups by default, add a new region to the
allow-list), edit the value in `local.defaults` inside `all-locals.tf`.
Nothing in `variables.tf` or `main.tf` needs to change.

**To change an alerting default** (e.g. retune the CPU warning
threshold), edit the value in `local.alert_defaults` inside `alerts.tf`
directly — there's no variable to override, by design.

Variables that stay required or keep a real `null` default are the ones
where that wouldn't make sense: true required identity inputs
(`project_id`, `environment`, `shard_count`), and inputs where `null` is
a distinct, meaningful state rather than "a value someone might want to
retune" (`zone`, `kms_key`, `server_ca_pool`, `secondary_location`,
`rdb_snapshot_start_time`, `aof_config`).

## Structure

| File | Contents |
|---|---|
| `versions.tf` | `required_providers` only — no `provider "google" {}` block, so the module never dictates project/credentials to its caller |
| `variables.tf` | Nearly all variables are about the Valkey **instance**. Alerting exposes only three: `enable_alerting`, `appteam_emails`, `platformteam_emails` — every alert threshold, duration, and metric name is fixed in `alerts.tf`, not a variable. Also holds every cross-field `check` block, checked against effective values |
| `all-locals.tf` | **The** file to edit for instance defaults (topology, sizing, persistence, auth/TLS/CA, backups, maintenance, engine config). `local.defaults` map, the effective-value locals derived from it, and instance-only derived logic (zone resolution, precondition booleans) |
| `alerts.tf` | **The** file to edit for alerting behavior. `local.alert_defaults` — every threshold/duration/metric constant, none of them variables — plus the on/off logic, notification channel specs, and `local.alert_definitions`, the table that IS the alert set |
| `data.tf` | Region/zone lookups, project data source, Shared VPC network lookup |
| `main.tf` | Part 1: the primary `google_memorystore_instance` (via `module/_instance`), plus an optional `secondary` for DR. Part 2: notification channels + one `module "alert_policies"` call per entry in `local.alert_definitions`, with an explicit `depends_on = [module.primary]` guaranteeing alerting is created after the instance |
| `outputs.tf` | Instance identity, PSC/discovery endpoint info, DR outputs, and alerting outputs (channel IDs, alert policy name map, whether alerting/replication-lag-alert were actually created) |
| `module/_instance/` | Inner module: one generic `google_memorystore_instance`. Called twice (primary + optional secondary) instead of hand-duplicating the resource. No defaults of its own — every input is required from the caller; that judgment lives in `all-locals.tf`, in exactly one place. |
| `module/_alert_policy/` | Inner module: one generic single-metric Cloud Monitoring alert policy. Called once per entry in `local.alert_definitions` via `for_each`. Same "no opinions, no defaults" design as `_instance`. |
| `examples/` | Self-contained usage examples |

**Adding a new alert doesn't mean writing a new resource block.** Add one
entry to `local.alert_definitions` in `alerts.tf`; `main.tf`'s `for_each`
over that map picks it up automatically.

## Alerting is intentionally not tunable per caller

This module exposes exactly three alerting variables:

| Variable | Purpose |
|---|---|
| `enable_alerting` | On/off switch (default `true`) |
| `appteam_emails` | Required whenever `enable_alerting = true` |
| `platformteam_emails` | Optional, notified in addition to `appteam_emails` |

Every threshold (`cpu_warning_threshold`, `replication_lag_warning_bytes`,
...), every duration (`warning_duration`, `critical_auto_close`, ...), and
every metric/resource-type string lives as a fixed constant in
`local.alert_defaults` inside `alerts.tf` — **not** as a variable. A
caller of this module cannot pass a different CPU threshold or retune an
alert's duration; the alert set ships as "on with good defaults, or off."
If a value genuinely needs to change, edit `alerts.tf` directly — that's
a deliberate design choice to keep alerting consistent across every
instance this module manages, rather than a gap.

## Installing from the private registry

```hcl
module "valkey" {
  source  = "app.terraform.io/<YOUR_ORG>/valkey/google"
  version = "~> 2.0"

  project_id  = "my-project"
  environment = "PROD"
  instance_id = "my-valkey"
  location    = "us-central1"

  appteam_emails = ["app-team-oncall@example.com"]
  # ...remaining variables all have sane defaults — see all-locals.tf
}
```

Replace `<YOUR_ORG>` with your Terraform Cloud/Enterprise organization
name.

## The 3 deployment topologies — one variable driving them

`var.deployment_topology` is a self-documenting label with three values:
`STANDALONE`, `HA`, `DR`. A `check` block validates it's consistent with
`replica_count` and `secondary_location`, so the module's real behavior
always stays fully explained by its explicit inputs.

| Topology | What it means | Drives |
|---|---|---|
| `STANDALONE` | Single instance, no replicas, no cross-region DR | `replica_count = 0` |
| `HA` | Single instance + replica(s), typically `MULTI_ZONE`, still one region | `replica_count >= 1` |
| `DR` | Adds a `SECONDARY` instance in a second region, replicating from this instance (which becomes `PRIMARY`) | `secondary_location` set |

DR still only creates two `google_memorystore_instance` resources under
one `module` call: `module.primary` and `module.secondary[0]`. Alerting
(when enabled) targets `module.primary` only — the secondary isn't
separately alerted, matching the original alerting module's design.

## PSC Connectivity (`var.psc_connectivity_mode`)

| Mode | Behavior |
|---|---|
| `NONE` (default) | No endpoint block. Nothing can reach the instance over PSC until wired up outside this module. |
| `SHARED_VPC` | Points the instance at an **already-existing** Shared VPC network + Service Connection Policy (`service_class = gcp-memorystore`), both created outside this module. This module does not create the VPC, subnet, or policy — it only sets `desired_auto_created_endpoints`. Memorystore auto-creates the PSC endpoint itself the moment the instance is created; no second `apply`. |

Required inputs for `SHARED_VPC`: `shared_vpc_host_project`,
`shared_vpc_network_name`, `existing_scp_name` (enforced by the
`shared_vpc_inputs_present` check block). `existing_scp_name` is
**guardrail-only** — the `google` provider has no read-only data source
for Service Connection Policies, so Terraform cannot verify it. Confirm
out-of-band first:

```bash
gcloud network-connectivity service-connection-policies describe POLICY_NAME \
  --project=HOST_PROJECT_ID --region=REGION
```

## Alerting (`var.enable_alerting`, default `true`)

When enabled, this module also creates:

| Alert | Severity | Signal |
|---|---|---|
| `instance_down` | CRITICAL | Node health check failing, or the health metric goes absent entirely |
| `cpu_warning` / `cpu_critical` | WARNING / CRITICAL | `instance/cpu/maximum_utilization` |
| `memory_warning` / `memory_critical` | WARNING / CRITICAL | `instance/memory/maximum_utilization` |
| `rejected_connections_warning` / `_critical` | WARNING / CRITICAL | `instance/node/stats/rejected_connections_count` |
| `connected_clients_high` | WARNING | `instance/node/clients/connected_clients` |
| `replication_lag` | WARNING | `instance/node/replication/maximum_offset_diff` — only created when `replica_count > 0` (fixed rule in `alerts.tf`, not overridable) |

Every alert (WARNING or CRITICAL) notifies the combined, deduplicated set
of `appteam_emails` + `platformteam_emails` — there's no severity split.
`appteam_emails` is required (checked by `alerting_requires_appteam_emails`)
whenever `enable_alerting = true`; `platformteam_emails` is genuinely
optional.

Not included, and worth adding once you've confirmed the exact metric
names against your instance in Metrics Explorer: key eviction rate and
command/op latency (p99). Add them as a new entry in
`local.alert_definitions` in `alerts.tf` once verified.

## Prerequisites (outside Terraform)

**APIs enabled:**
- Host project (`project_id`): `memorystore.googleapis.com`, `monitoring.googleapis.com`
- Shared VPC host project (`SHARED_VPC` mode only): `compute.googleapis.com`, `networkconnectivity.googleapis.com`

**IAM**, for whoever runs `terraform apply`:
- Host project: `roles/memorystore.admin`, `roles/monitoring.editor` (or equivalent)
- Shared VPC host project (`SHARED_VPC` mode): `roles/compute.networkViewer` at minimum

If using `CUSTOMER_MANAGED_CAS_CA` or `CUSTOMER_MANAGED` (CMEK)
encryption, Memorystore's service agent also needs
`roles/privateca.certificateRequester` on your CA pool, or
`roles/cloudkms.cryptoKeyEncrypterDecrypter` on your KMS key,
respectively. **Not included** in this module — add them alongside if you
use those features.

## Usage

```hcl
module "valkey" {
  source = "./modules/valkey"

  project_id  = "my-project"
  instance_id = "cache-prod"
  environment = "PROD"
  location    = "us-central1"

  deployment_topology = "HA"
  replica_count       = 2
  node_type           = "STANDARD_LARGE"
  shard_count         = 3

  appteam_emails      = ["app-team-oncall@example.com", "app-team@example.com"]
  platformteam_emails = ["platform-oncall@example.com"] # optional
}
```

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

See `examples/` for full topology + alerting examples.

## Reference: requirements, inputs, outputs

Generated by `terraform-docs` (config: `.terraform-docs.yml`) — run
`terraform-docs markdown table --output-file README.md --output-mode inject .`
from this directory to refresh after changing `variables.tf` or
`outputs.tf`. The `Required` column reflects Terraform's own rule (no
`default` argument = required); `appteam_emails` shows as not-required
here even though it's conditionally required whenever `enable_alerting =
true` — see the `alerting_requires_appteam_emails` check block in
`variables.tf`, since Terraform has no native way to express a
conditional requirement in the variable definition itself.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 7.39.0, < 8.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | >= 7.39.0, < 8.0.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_alert_policies"></a> [alert\_policies](#module\_alert\_policies) | ./module/_alert_policy | n/a |
| <a name="module_primary"></a> [primary](#module\_primary) | ./module/_instance | n/a |
| <a name="module_secondary"></a> [secondary](#module\_secondary) | ./module/_instance | n/a |

## Resources

| Name | Type |
|------|------|
| [google_monitoring_notification_channel.email](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_notification_channel) | resource |
| [google_compute_network.shared_vpc_net](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/compute_network) | data source |
| [google_compute_regions.available_regions](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/compute_regions) | data source |
| [google_compute_zones.available_secondary_zones](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/compute_zones) | data source |
| [google_compute_zones.available_zones](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/compute_zones) | data source |
| [google_project.host_project](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/project) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment: DEV, QA, UAT, or PROD. Drives stricter preconditions (e.g. blocks SHARED\_CORE\_NANO in PROD). Required — no sensible module-wide default exists for this. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | GCP project ID where the Memorystore for Valkey instance (and, when enable\_alerting = true, its alert policies + notification channels) are created. Required — no default, to prevent accidentally deploying into a placeholder project. | `string` | n/a | yes |
| <a name="input_shard_count"></a> [shard\_count](#input\_shard\_count) | Number of shards. Determines total memory capacity. Must be exactly 1 when cluster\_mode = CLUSTER\_DISABLED. Required — no module-wide default value makes sense for capacity sizing. | `number` | n/a | yes |
| <a name="input_aof_config"></a> [aof\_config](#input\_aof\_config) | AOF fsync policy when persistence\_mode = AOF. ALWAYS = fsync every write (safest, highest latency). EVERY\_SEC = fsync every second (recommended default). NO = OS decides (least durable). | <pre>object({<br/>    append_fsync = string<br/>  })</pre> | `null` | no |
| <a name="input_appteam_emails"></a> [appteam\_emails](#input\_appteam\_emails) | App team's email addresses — every one of these gets notified on every alert this module creates, regardless of severity. set(string) because order doesn't matter and duplicates are meaningless here. Required when enable\_alerting = true (see the alerting\_requires\_appteam\_emails check) — an alert with nowhere to go is a silent outage. | `set(string)` | `[]` | no |
| <a name="input_authorization_mode"></a> [authorization\_mode](#input\_authorization\_mode) | Client authentication mode. AUTH\_DISABLED = no authentication (anyone on the authorized network can connect — never use in production). IAM\_AUTH = clients authenticate using short-lived IAM access tokens, integrated with Cloud IAM roles/audit logs. | `string` | `null` | no |
| <a name="input_automated_backup_enabled"></a> [automated\_backup\_enabled](#input\_automated\_backup\_enabled) | Whether to enable Memorystore's automated backup feature on the primary instance (separate from RDB/AOF persistence — a GCS-backed backup collection that survives instance deletion). The secondary (DR) instance never gets this, regardless of this value — see the note in all-locals.tf. | `bool` | `null` | no |
| <a name="input_automated_backup_retention_days"></a> [automated\_backup\_retention\_days](#input\_automated\_backup\_retention\_days) | Number of days to retain each automated backup (1-365). GCP default is 35 if unset; this module always sets it explicitly for clarity. | `number` | `null` | no |
| <a name="input_automated_backup_start_time_hour"></a> [automated\_backup\_start\_time\_hour](#input\_automated\_backup\_start\_time\_hour) | Hour of day (UTC, 0-23) when the daily automated backup window begins. Only used when automated\_backup\_enabled = true. | `number` | `null` | no |
| <a name="input_cluster_mode"></a> [cluster\_mode](#input\_cluster\_mode) | Cluster Mode Enabled (CLUSTER) or Disabled (CLUSTER\_DISABLED). Cannot be changed after creation. | `string` | `null` | no |
| <a name="input_deletion_protection_enabled"></a> [deletion\_protection\_enabled](#input\_deletion\_protection\_enabled) | If true, deletion of the instance is blocked at the API level. Defaults (see all-locals.tf) to true — this module is meant for production; set to false explicitly for short-lived test instances. | `bool` | `null` | no |
| <a name="input_deployment_topology"></a> [deployment\_topology](#input\_deployment\_topology) | The single knob for topology — this is the only input; there is no<br/>separate enable\_cross\_region\_replication variable. STANDALONE / HA<br/>map 1:1 to no DR; DR maps 1:1 to a SECONDARY instance being created.<br/>Default (when left null): see local.defaults.deployment\_topology in<br/>all-locals.tf.<br/>  STANDALONE: single instance, no replicas, no cross-region DR.<br/>  HA: single instance with replica(s) and/or MULTI\_ZONE distribution,<br/>    still one region, no cross-region DR.<br/>  DR: adds a SECONDARY instance in a second region, replicating from<br/>    this instance (which becomes PRIMARY). Requires secondary\_location. | `string` | `null` | no |
| <a name="input_enable_alerting"></a> [enable\_alerting](#input\_enable\_alerting) | Whether this module also creates Cloud Monitoring alert policies + email notification channels for the instance. Defaults to true (see alerts.tf). Set to false if you want the instance only, e.g. alerting is managed elsewhere for this environment. | `bool` | `null` | no |
| <a name="input_encryption_type"></a> [encryption\_type](#input\_encryption\_type) | Encryption at rest. GOOGLE\_MANAGED = Google's default encryption, no key management overhead. CUSTOMER\_MANAGED (CMEK) = you control the key in Cloud KMS, giving you key rotation, revocation, and audit-log control over data access. | `string` | `null` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | Valkey engine version. Immutable after creation — changing this forces a new instance (or requires a documented major-version upgrade path outside Terraform). | `string` | `null` | no |
| <a name="input_existing_scp_name"></a> [existing\_scp\_name](#input\_existing\_scp\_name) | Name of the already-existing Service Connection Policy (service\_class = gcp-memorystore) that authorizes this connection. Guardrail-only: the google provider has no read-only data source for Service Connection Policies, so this cannot be verified by Terraform. Confirm out-of-band before relying on it (see README). | `string` | `null` | no |
| <a name="input_instance_id"></a> [instance\_id](#input\_instance\_id) | Permanent, unique identifier for this instance. Becomes the final component of the instance's resource name, and (when enable\_alerting = true) the instance the alert policies filter on. Immutable after creation. | `string` | `null` | no |
| <a name="input_kms_key"></a> [kms\_key](#input\_kms\_key) | Full resource ID of the Cloud KMS CryptoKey, e.g. "projects/PROJECT\_ID/locations/REGION/keyRings/RING\_ID/cryptoKeys/KEY\_ID". Required when encryption\_type = CUSTOMER\_MANAGED. Must be a symmetric key in the same region as the instance. | `string` | `null` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Resource labels for cost allocation/ownership tracking (e.g. { env = "dev", managed\_by = "terraform" }). Non-authoritative — Memorystore only manages the labels present in this map. Applied identically to both the primary and secondary (DR) instance. | `map(string)` | `null` | no |
| <a name="input_location"></a> [location](#input\_location) | GCP region where the Memorystore instance is created (e.g. us-central1). Must be one of local.defaults.allowed\_locations in all-locals.tf — edit that list there to support a new region. | `string` | `null` | no |
| <a name="input_maintenance_day"></a> [maintenance\_day](#input\_maintenance\_day) | Day of week for the weekly maintenance window (UTC). | `string` | `null` | no |
| <a name="input_maintenance_start_hour"></a> [maintenance\_start\_hour](#input\_maintenance\_start\_hour) | Hour (UTC, 0-23) the weekly maintenance window begins. Pick your lowest-traffic period. | `number` | `null` | no |
| <a name="input_maxclients"></a> [maxclients](#input\_maxclients) | Maximum simultaneous client connections. Leave null for Valkey's default (sized to node type). Lower this for an early rejection signal instead of the instance being overwhelmed by a connection storm. | `number` | `null` | no |
| <a name="input_maxmemory_clients"></a> [maxmemory\_clients](#input\_maxmemory\_clients) | Cap on total memory used by client-side output buffers, e.g. "10%" or an absolute byte value like "100mb". Protects the instance from being OOM-killed by a slow/misbehaving client draining a large response slowly. Leave null to use Valkey's default. | `string` | `null` | no |
| <a name="input_maxmemory_policy"></a> [maxmemory\_policy](#input\_maxmemory\_policy) | Eviction policy when the instance reaches maxmemory. volatile-lru (default) only evicts keys with a TTL set; allkeys-lru evicts any key; noeviction rejects writes at capacity instead of evicting. | `string` | `null` | no |
| <a name="input_node_type"></a> [node\_type](#input\_node\_type) | Machine type for individual nodes. Determines vCPU count, memory capacity, and max client connections per node. SHARED\_CORE\_NANO has no SLA — DEV/test only (blocked in PROD by precondition). | `string` | `null` | no |
| <a name="input_notify_keyspace_events"></a> [notify\_keyspace\_events](#input\_notify\_keyspace\_events) | Keyspace notification classes to enable (pub/sub events on key changes/expiry). Empty string disables notifications (default, lowest overhead). E.g. "Ex" = expired-key events only, "KEA" = all events. Leave unset unless something actually consumes these events — it adds CPU/pubsub overhead. | `string` | `null` | no |
| <a name="input_persistence_mode"></a> [persistence\_mode](#input\_persistence\_mode) | Data persistence strategy. RDB = periodic point-in-time snapshots. AOF = append-only log of every write, higher durability. DISABLED = no persistence (data lost on restart/failover, no recovery source). | `string` | `null` | no |
| <a name="input_platformteam_emails"></a> [platformteam\_emails](#input\_platformteam\_emails) | Platform/on-call team's email addresses — notified on every alert alongside appteam\_emails. Optional; leave empty if you don't have a standing platform list yet. | `set(string)` | `[]` | no |
| <a name="input_psc_connectivity_mode"></a> [psc\_connectivity\_mode](#input\_psc\_connectivity\_mode) | How PSC connections to the instance are established.<br/><br/>NONE: No PSC connectivity is configured by this module. The instance is<br/>  created with no desired\_auto\_created\_endpoints block — nothing can<br/>  reach it over PSC until connectivity is set up some other way.<br/><br/>SHARED\_VPC: The instance attaches to an existing Shared VPC network that<br/>  is already set up for it — the network (shared\_vpc\_network\_name) and<br/>  its Service Connection Policy (existing\_scp\_name, service\_class =<br/>  gcp-memorystore) both already exist, created outside this module.<br/>  This module does not create the VPC or the SCP, and does not create<br/>  a forwarding rule or reserved IP either — it only points the instance<br/>  at the network via desired\_auto\_created\_endpoints. Because the SCP<br/>  is already there and pre-authorizes gcp-memorystore into that<br/>  network/region, Memorystore auto-creates the PSC endpoint itself the<br/>  moment the instance is created. No second apply, no manual endpoint<br/>  registration. | `string` | `null` | no |
| <a name="input_rdb_snapshot_period"></a> [rdb\_snapshot\_period](#input\_rdb\_snapshot\_period) | Snapshot interval when persistence\_mode = RDB. Required in that case, ignored otherwise. | `string` | `null` | no |
| <a name="input_rdb_snapshot_start_time"></a> [rdb\_snapshot\_start\_time](#input\_rdb\_snapshot\_start\_time) | RFC3339 UTC timestamp for the first RDB snapshot window (e.g. "2024-10-02T15:01:23Z"). Optional even when mode = RDB; if omitted, Google schedules the first snapshot immediately. Required (must be explicit) when deployment\_topology = DR and persistence\_mode = RDB — see the persistence\_config\_consistency check. | `string` | `null` | no |
| <a name="input_replica_count"></a> [replica\_count](#input\_replica\_count) | Number of replica nodes per shard. 0-5. Also drives whether the replication-lag alert is created by default when enable\_alerting = true (see enable\_replication\_lag\_alert). | `number` | `null` | no |
| <a name="input_secondary_location"></a> [secondary\_location](#input\_secondary\_location) | GCP region for the SECONDARY instance. Required when deployment\_topology = DR. Must differ from location. No centralized default — null is the meaningful 'no DR region chosen' state, not a value to retune. | `string` | `null` | no |
| <a name="input_secondary_zone"></a> [secondary\_zone](#input\_secondary\_zone) | Zone to pin the SECONDARY (DR) instance to. Only used when deployment\_topology = DR and zone\_distribution\_mode = SINGLE\_ZONE. Auto-selected if left null. | `string` | `null` | no |
| <a name="input_server_ca_mode"></a> [server\_ca\_mode](#input\_server\_ca\_mode) | CA mode for TLS server certificates. Immutable after creation — cannot be<br/>changed or deactivated once the instance is created.<br/><br/>GOOGLE\_MANAGED\_PER\_INSTANCE\_CA (default): Google generates a unique CA per<br/>  instance. Every client must download and install that instance's specific<br/>  CA cert. Highest isolation, highest client-side cert management overhead.<br/><br/>GOOGLE\_MANAGED\_SHARED\_CA: Google manages a single regional CA bundle shared<br/>  across all instances in that region. Clients install one bundle per<br/>  region instead of one per instance — simplest to operate at scale.<br/><br/>CUSTOMER\_MANAGED\_CAS\_CA: Uses your own CA pool in Certificate Authority<br/>  Service (CAS). Requires server\_ca\_pool to be set. Best for compliance<br/>  requirements around key custody/rotation. | `string` | `null` | no |
| <a name="input_server_ca_pool"></a> [server\_ca\_pool](#input\_server\_ca\_pool) | Full resource ID of the CA pool in Certificate Authority Service, e.g. "projects/PROJECT\_ID/locations/REGION/caPools/POOL\_ID". Required only when server\_ca\_mode = CUSTOMER\_MANAGED\_CAS\_CA; must be in the same region as the instance. | `string` | `null` | no |
| <a name="input_shared_vpc_host_project"></a> [shared\_vpc\_host\_project](#input\_shared\_vpc\_host\_project) | Host project of the existing Shared VPC network. Required when psc\_connectivity\_mode = SHARED\_VPC. | `string` | `null` | no |
| <a name="input_shared_vpc_network_name"></a> [shared\_vpc\_network\_name](#input\_shared\_vpc\_network\_name) | Name of the existing Shared VPC network. Required when psc\_connectivity\_mode = SHARED\_VPC. | `string` | `null` | no |
| <a name="input_slowlog_log_slower_than"></a> [slowlog\_log\_slower\_than](#input\_slowlog\_log\_slower\_than) | Microseconds a command must take to be logged to the slow log. -1 disables, 0 logs everything (expensive). Useful for catching expensive commands (e.g. unbounded KEYS/SCAN) before they degrade the instance. | `number` | `null` | no |
| <a name="input_transit_encryption_mode"></a> [transit\_encryption\_mode](#input\_transit\_encryption\_mode) | In-transit (TLS) encryption mode. TRANSIT\_ENCRYPTION\_DISABLED = plaintext. SERVER\_AUTHENTICATION = TLS enabled, client verifies server identity via CA cert. Required when authorization\_mode = IAM\_AUTH, since IAM tokens are otherwise sent unencrypted. | `string` | `null` | no |
| <a name="input_zone"></a> [zone](#input\_zone) | Zone to pin the instance to. Only used when zone\_distribution\_mode = SINGLE\_ZONE; if left null in that mode, the module auto-selects the first available zone in the region. Must be left null for MULTI\_ZONE. No centralized default — null is a meaningful 'auto-select' state, not a value to retune. | `string` | `null` | no |
| <a name="input_zone_distribution_mode"></a> [zone\_distribution\_mode](#input\_zone\_distribution\_mode) | Zone distribution mode for the instance's nodes: SINGLE\_ZONE or MULTI\_ZONE (recommended for production — survives a single-zone outage). | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alert_policy_ids"></a> [alert\_policy\_ids](#output\_alert\_policy\_ids) | Map of alert name to alert policy resource name, for quick reference or linking from a runbook. Keys come straight from local.alert\_definitions, so replication\_lag simply isn't a key here when it wasn't created — no null to check for. Empty map when enable\_alerting = false. |
| <a name="output_alerting_enabled"></a> [alerting\_enabled](#output\_alerting\_enabled) | Whether this module call created alerting resources at all (see enable\_alerting). |
| <a name="output_discovery_endpoints"></a> [discovery\_endpoints](#output\_discovery\_endpoints) | PSC discovery endpoints (ip\_address, port, network, service\_attachment) for the primary instance — the real connection points clients use. |
| <a name="output_instance_id"></a> [instance\_id](#output\_instance\_id) | The instance ID. |
| <a name="output_instance_name"></a> [instance\_name](#output\_instance\_name) | Fully qualified resource name of the instance. |
| <a name="output_notification_channel_ids"></a> [notification\_channel\_ids](#output\_notification\_channel\_ids) | IDs of every notification channel created — one per unique address across appteam\_emails and platformteam\_emails. Attached to every alert this module creates. Empty when enable\_alerting = false. |
| <a name="output_psc_attachment_details"></a> [psc\_attachment\_details](#output\_psc\_attachment\_details) | Service attachments exposed by the primary instance (connection\_type + service\_attachment). Useful for confirming psc\_attachment\_count matches reality. |
| <a name="output_psc_connectivity_mode"></a> [psc\_connectivity\_mode](#output\_psc\_connectivity\_mode) | Which PSC connectivity mode this deployment used (NONE or SHARED\_VPC). |
| <a name="output_replication_lag_alert_enabled"></a> [replication\_lag\_alert\_enabled](#output\_replication\_lag\_alert\_enabled) | Whether the replication-lag alert policy was actually created (see enable\_replication\_lag\_alert / replica\_count). |
| <a name="output_resolved_zone"></a> [resolved\_zone](#output\_resolved\_zone) | The zone actually used for the instance (relevant when zone\_distribution\_mode = SINGLE\_ZONE and zone was auto-selected). |
| <a name="output_secondary_discovery_endpoints"></a> [secondary\_discovery\_endpoints](#output\_secondary\_discovery\_endpoints) | PSC discovery endpoints for the SECONDARY (DR) instance. Empty unless deployment\_topology = DR. |
| <a name="output_secondary_instance_id"></a> [secondary\_instance\_id](#output\_secondary\_instance\_id) | Instance ID of the SECONDARY (DR) instance. Null unless deployment\_topology = DR. |
| <a name="output_secondary_psc_attachment_details"></a> [secondary\_psc\_attachment\_details](#output\_secondary\_psc\_attachment\_details) | Service attachments exposed by the secondary instance. Empty unless deployment\_topology = DR. |
| <a name="output_shared_vpc_network_self_link"></a> [shared\_vpc\_network\_self\_link](#output\_shared\_vpc\_network\_self\_link) | Self link of the existing Shared VPC network used. Null unless psc\_connectivity\_mode = SHARED\_VPC. |
<!-- END_TF_DOCS -->

## Migrating from the two-module setup

If a root module previously called `memorystore-valkey` and
`valkey-alerting` separately:

1. Point `source` at this module instead of the old `memorystore-valkey`
   source, keep all the instance-shaped variables as they were.
2. Delete the separate `valkey_alerts` module block; move
   `appteam_emails` / `platformteam_emails` into the same module call as
   the instance variables. If the old alerting call overrode any
   threshold/duration/metric-type variable, that override is dropped —
   this module no longer accepts them (see "Alerting is intentionally
   not tunable per caller"). If you genuinely need a different value,
   edit `local.alert_defaults` in `alerts.tf` and publish a new module
   version, rather than passing it as a variable.
3. Remove `instance_id`/`region` from the old alerting call — they're now
   derived internally from `module.primary`.
4. Run `terraform state mv` for the alert policy and notification channel
   resources from the old module's addresses to this module's
   `module.alert_policies["<name>"]` / `google_monitoring_notification_channel.email["<address>"]`
   addresses, so they're adopted rather than recreated. Confirm the exact
   old/new addresses with `terraform state list` on both sides before
   applying.

## Known caveats — verify before production use

- **DR pairing on the primary side is unverified beyond the resolved
  error message documented in `main.tf`.**
- **`server_ca_mode` enum casing**: confirm exact values via
  `terraform providers schema -json` before relying on it.
- **Multi-VPC / user-registered PSC connections are not implemented.**
  If you need several separate consumer VPCs (or a different project
  than the instance's host project) reaching the same instance, that
  requires a separate `USER`-mode connectivity path this module doesn't
  currently build.
- **CA/KMS service-agent IAM bindings are not included.**
- **`existing_scp_name` has no Terraform-level effect.**
- **Changing `shard_count` and `replica_count` together fails on an
  existing instance.** The `google_memorystore_instance` Update API only
  accepts one changed field per update request. This only affects
  **updates** to an existing instance. **Fix:** change one field, apply,
  then change the other, apply again. When *shrinking* both, reduce
  `replica_count` first, then `shard_count`. When *growing* both, do the
  reverse.
- **The secondary (DR) instance never gets automated backups**,
  regardless of `automated_backup_enabled` — carried forward unchanged
  from the original module; worth deciding explicitly rather than
  silently forever (see `main.tf`).
- **Alerting only targets the primary instance.** The secondary (DR)
  instance isn't separately monitored by this module.
