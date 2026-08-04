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
├── variables.tf                   # var.env (dev/qa/uat/prd)
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
`persistence.mode`). `project_id`/`location`/Shared VPC host project are
never taken from a request file at all — always
`default.json.environments[var.env]`.

Then `deployment_topology` (`STANDALONE`/`HA`/`DR`) and
`secondary_location` are derived from `replica_count` and
`cross_region_replica`, `rdb_snapshot_start_time` is computed once (via
`time_static`) so it doesn't drift on every plan, and the resource
`labels` are assembled from the request's `tags` plus the
auto-populated `topology`/`environment`/`managed_by` (see below).

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
    "persistence": { "mode": "RDB" },
    "tags": { "application_id": "my-app", "lob": "cc-0042" },
    "enable_alerting": true,
    "appteam_emails": ["app-team-oncall@example.com"]
  }
}
```

- `instance.name` is what the module calls `instance_id` — and is the
  **map key** everything is keyed by (`local.valkey`, both module
  `for_each`es). It must be unique across every request file targeting
  the same environment. Two files sharing a `name` silently collide into
  one map entry and one of the two requests disappears without a plan
  error — this actually happened once (`test-ha-cache.json` briefly
  duplicated `test-dr-cache.json`'s name); double-check this on every new
  onboarding PR.
- `cross_region_replica` accepts either `{"enabled": true}` or a bare
  `true`/`false` — only the *on/off* signal comes from the request; the
  DR region itself always comes from `default.json`'s per-environment
  infra block.
- Nested objects (`persistence`, `backup`, `maintenance_window`,
  `config`) can be **partially** overridden — e.g. `{"persistence":
  {"mode": "AOF"}}` still inherits `persistence.aof_config.append_fsync`
  from `default.json` rather than losing it. `locals.tf` merges these
  field by field for exactly this reason (a plain top-level `merge()`
  would silently drop unspecified nested fields).
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

### `tags` — don't set `topology`, `environment`, or `managed_by`

`instance.tags` only needs requester-supplied metadata (e.g.
`application_id`, `lob`). **`topology`, `environment`, and `managed_by`
are always derived by `locals.tf` and applied automatically** — as GCP
labels on the created resources — and overwrite anything a request file
sends under those same keys:

- `topology` — `standalone` / `ha` / `dr`, derived from `replica_count`
  and `cross_region_replica`.
- `environment` — the human-readable form of `var.env` (`dev` / `qa` /
  `uat` / `prod`).
- `managed_by` — always `"terraform"`.

Older request files that set these by hand (or `application_id` under a
different name like `team`, or `lob` under `cost_center`) should be
updated to the shape above — see the `test-*.json` files in
`config/onboarding-files-valkey/` for current examples of all three
topologies. Also fixed as part of that cleanup: `test-standalone-cache.json`
was still using the older flat `"labels"` key instead of `"tags"`.

## Running it

```bash
terraform init
terraform plan  -var="env=dev"
terraform apply -var="env=dev"
```
