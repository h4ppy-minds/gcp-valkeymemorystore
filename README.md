# Valkey onboarding root

Self-service onboarding pattern: one JSON file per Valkey instance
request, merged with centrally-governed defaults, and fed into a single
call of `./modules/terraform-google-valkey` per instance.

## Layout

```
.
├── main.tf                        # module "valkey" — one call per instance (for_each over local.valkey)
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
    └── terraform-google-valkey/   # the merged instance+alerting module
```

## How a request file is resolved (locals.tf)

For each `*.json` file except `default.json`:

```
final config = merge(
  default.json's flat keys,               # technical defaults (cluster_mode, node_type, thresholds n/a — alerting is fixed in the module, etc.)
  default.json.environments[var.env],      # project_id, location, shared_vpc_*, cross_region_replica.location — never settable by a request
  <request file>.instance,                 # the team's actual ask: instance_id, shard_count, replica_count, labels, alerting emails, ...
)
```

then `deployment_topology` (`STANDALONE`/`HA`/`DR`) and `secondary_location`
are derived from `replica_count` and `cross_region_replica`, and
`rdb_snapshot_start_time` is computed once (via `time_static`) so it
doesn't drift on every plan.

## Request file shape

```json
{
  "request_type": "create",
  "environment": "dev",
  "requested_by": "platform-team",
  "instance": {
    "instance_id": "my-cache",
    "shard_count": 1,
    "replica_count": 0,
    "labels": { "team": "...", "cost_center": "..." },
    "enable_alerting": true,
    "appteam_emails": ["app-team-oncall@example.com"]
  }
}
```

- `cross_region_replica` accepts either `{"enabled": true}` or a bare
  `true`/`false` — only the *on/off* signal comes from the request; the
  DR region itself always comes from `default.json`'s per-environment
  infra block.
- Setting `"request_type": "delete"` removes the instance from
  `local.valkey` (and therefore from the module's `for_each`) on the next
  apply — no separate destroy step needed.
- Alerting is controlled by exactly `enable_alerting` +
  `appteam_emails` + `platformteam_emails` — the module fixes every
  threshold/duration/metric name internally (see the module's
  `alerts.tf`), so there is nothing else to set here.
- `appteam_emails` **must** be non-empty whenever `enable_alerting = true`
  — the module enforces this with a `check` block and `terraform plan`
  will fail otherwise.

## Running it

```bash
terraform init
terraform plan  -var="env=dev"
terraform apply -var="env=dev"
```
