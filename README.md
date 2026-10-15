# Valkey onboarding root

Self-service onboarding pattern: one JSON file per Valkey instance
request, merged with centrally-governed defaults, and fed into two
module calls per instance — one for the instance
(`./modules/terraform-google-h4ppy-memorystore-valkey`), one for its
alerting (`./modules/terraform-google-h4ppy-memorystore-valkey-alerts`).

## Layout

```
.
├── main.tf                        # module "valkey" (instance) + module "valkey_alerts" (alerting) — one call each per instance (for_each over local.valkey)
├── locals.tf                      # loads + merges default.json + request JSONs + derives topology
├── output.tf
├── variables.tf                   # var.env (dev/qa/uat/prod)
├── provider.tf
├── rdb_snapshot_timing.tf         # time_static anchor for rdb_snapshot_start_time
├── config/
│   └── onboarding-files-valkey/
│       ├── default.json           # global technical defaults + per-environment infra (project/region/shared VPC/DR region)
│       ├── test-standalone-cache.json
│       ├── test-ha-cache.json
│       └── test-dr-cache.json
└── modules/
    ├── terraform-google-h4ppy-memorystore-valkey/         # instance only
    └── terraform-google-h4ppy-memorystore-valkey-alerts/  # alerting only — targets the instance by instance_id/location, no other coupling
```

## Two module calls, not one

The instance and its alerting are separate module calls in `main.tf`,
wired together only through `module.valkey[key].instance_id` /
`module.valkey[key].resolved_location` being passed into
`module.valkey_alerts[key]`. That means an onboarding PR that only edits
`appteam_emails`/`platformteam_emails`/`enable_alerting` in a request
file produces a plan that only touches `module.valkey_alerts` — the
instance itself is untouched, so an email-list change doesn't need to go
through whatever review process governs actual infrastructure changes.

## How a request file is resolved (locals.tf)

For each `*.json` file except `default.json`, targeting the current
`var.env`: every module variable is resolved field by field as
`try(<request file's nested path>, <default.json's matching nested
path>)` — an explicit per-field fallback, not one generic `merge()` of
the whole objects (see `locals.tf`'s Layer 3 comment for why: a shallow
merge would silently drop nested defaults a partial request override
didn't restate, e.g. `persistence.aof_config` when a request only sets
`persistence.mode`). `project_id`/Shared VPC host project are never
taken from a request file at all — always
`default.json.environments[var.env]`. `location` **is** instance-settable
(falls back to the environment's default when omitted) — see "Request
file shape" below.

Then the physical GCP instance ID is built as `<name>-<var.env>`,
`deployment_topology` (`STANDALONE`/`HA`/`DR`) and `secondary_location`
are derived from `replica_count`, `cross_region_replica`, and (for DR)
the chosen primary `location` looked up against `dr_region_pairs`,
`rdb_snapshot_start_time` is computed once (via `time_static`) so it
doesn't drift on every plan, and the resource `labels` are assembled
from `application_id`/`lob` plus any extra `tags` plus the auto-populated
`topology`/`environment`/`managed_by` (see below).

## Request file shape

Request files use the onboarding wrapper API's nested shape (not flat
keys matching the module's variables 1:1) — `locals.tf` translates this
into the flat variable names the instance/alerts modules expect, field
by field:

```json
{
  "request_type": "create",
  "environment": "dev",
  "requested_by": "platform-team",
  "instance": {
    "name": "my-cache",
    "shard_count": 1,
    "replica_count": 0,
    "server_type": "STANDARD_SMALL",
    "version": "VALKEY_9_0",
    "location": "us-east1",
    "cross_region_replica": true,
    "persistence": { "mode": "RDB" },
    "application_id": "my-app",
    "lob": "cc-0042",
    "enable_alerting": true,
    "appteam_emails": ["app-team-oncall@example.com"]
  }
}
```

- `instance.name` is the **map key** everything is keyed by
  (`local.valkey`, both module `for_each`es) — NOT the physical GCP
  instance ID. It must be unique across every request file targeting the
  same environment. Two files sharing a `name` silently collide into one
  map entry and one of the two requests disappears without a plan error
  — this actually happened once (`test-ha-cache.json` briefly duplicated
  `test-dr-cache.json`'s name); double-check this on every new
  onboarding PR.
- **The actual GCP instance ID is `<name>-<env>`** — `"name": "my-cache"`
  in a `dev` request becomes instance ID `my-cache-dev`. This happens
  automatically in `locals.tf`; request files never set it directly. The
  suffix makes the same request-file `name` usable independently across
  every environment, and makes the environment legible from the instance
  ID alone (console, `gcloud`, an incident channel) without having to
  check labels.
- `application_id` and `lob` are **instance-level fields**, not nested
  under a `tags` object. Both always end up in the created instance's
  GCP labels — `application_id` falls back to `default.json`'s
  `aplication_name` if a request omits it; `lob` has no default and is
  simply left off the labels if omitted. `instance.tags` (if present) is
  still supported as a passthrough for any other ad-hoc label, but
  `application_id`/`lob` should be set at the top level, not inside
  `tags`.
- `location` is instance-settable — a request can pick any GCP region
  available to the project, not just the environment's default. Omit it
  to fall back to `default.json.environments[<env>].location`.
- `cross_region_replica` is a plain boolean (`true`/`false`) — not an
  object. When `true`, the DR secondary region is chosen automatically
  from whichever `location` the request picked as primary, via
  `default.json`'s `dr_region_pairs` table — there is no separate field
  for the secondary region. Cross-region replication is currently only
  supported between region pairs listed in that table (today:
  `us-central1 <-> us-east1`); requesting DR from an unlisted primary
  region fails `terraform plan` with a clear error rather than silently
  picking something.
- `backup` is also a plain boolean (`true`/`false`) — not an object.
  It only controls whether automated backups happen at all; the
  schedule (`start_hour`) and retention (`backup_retention_days`) are
  NOT request-settable or `default.json`-settable — they come from the
  Terraform module's own defaults (currently hour `3` UTC, retention
  `35` days) so there's exactly one place that sets "what a normal
  backup schedule looks like" instead of this template silently
  overriding it to different numbers per environment.
- Nested objects (`persistence`, `maintenance_window`, `config`) can be
  **partially** overridden — e.g. `{"persistence": {"mode": "AOF"}}`
  still inherits `persistence.aof_config.append_fsync` from
  `default.json` rather than losing it. `locals.tf` merges these field
  by field for exactly this reason (a plain top-level `merge()` would
  silently drop unspecified nested fields).
- Setting `"request_type": "delete"` removes the instance from
  `local.valkey` (and therefore from both modules' `for_each`) on the
  next apply — no separate destroy step needed.
- Alerting is controlled by exactly `enable_alerting` +
  `appteam_emails` + `platformteam_emails` — the alerting module fixes
  every threshold/duration/metric name internally (see that module's
  `alerts.tf`), so there is nothing else to set here.
- `appteam_emails` **must** be non-empty whenever `enable_alerting = true`
  (or omitted — the alerting module's default is `true`) — the module
  enforces this with a `check` block and `terraform plan` will fail
  otherwise.
- Whether the replication-lag alert fires is derived automatically from
  `replica_count > 0` in `main.tf` and passed to the alerting module as
  `enable_replication_lag_alert` — there's no separate request-file field
  for it.
- `authorization_mode` / `transit_encryption_mode` are not request-file
  fields at all anymore — the instance module hard-requires `IAM_AUTH` /
  `SERVER_AUTHENTICATION` for every instance it creates and rejects
  anything else, so there's no longer a value for a request to set here.

### `tags` — don't set `topology`, `environment`, or `managed_by`

`topology`, `environment`, and `managed_by` are always derived by
`locals.tf` and applied automatically **as GCP labels** on the created
resources, overwriting anything a request file sends under those same
keys in `instance.tags`:

- `topology` — `standalone` / `ha` / `dr`, derived from `replica_count`
  and `cross_region_replica`.
- `environment` — always `var.env` itself (`dev` / `qa` / `uat` /
  `prod`).
- `managed_by` — always `"terraform"`.

See the `test-*.json` files in `config/onboarding-files-valkey/` for
current examples of all three topologies, including a DR example
(`test-dr-cache.json`) that requests `us-east1` as primary and gets
`us-central1` picked automatically as its secondary.

## ⚠️ Migration note: instance IDs now get an environment suffix

Before this change, an instance's GCP instance ID was exactly
`instance.name` from the request file. It's now `<name>-<env>`. GCP
instance IDs are immutable, so for any instance already deployed under
the old naming, the next `terraform plan` will show a **destroy and
recreate** (`test-ha-cache` → `test-ha-cache-dev`) — not an in-place
rename, because there isn't one at the API level. That's a real outage
for that instance if applied as-is.

Do not run a bulk `terraform apply` across existing environments without
handling this first. Options, per already-deployed instance:
- Accept the recreate during a planned maintenance window (data loss for
  anything not covered by backups/persistence — check
  `automated_backup_enabled`/`persistence_mode` first).
- Or avoid the recreate entirely by snapshotting/backing up, deleting the
  old instance out of band, then applying so Terraform creates the new
  `-<env>`-suffixed one fresh.

There's no `terraform state mv` that fixes this — the underlying GCP
resource's `instance_id` argument is what's changing, not just a
Terraform-side address.

## Running it

```bash
terraform init
terraform plan  -var="env=dev"
terraform apply -var="env=dev"
```
