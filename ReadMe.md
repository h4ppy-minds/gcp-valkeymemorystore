# alt-onboarding-config

Alternative to `../main.tf`'s YAML-manifest pattern: **one JSON file per
onboarding request**, merged with global + per-environment defaults, the
same shape as the PostgreSQL onboarding pattern this was adapted from.

## How it works

```
config/onboarding-files-valkey/
├── default.json              # global technical defaults + per-env infra (project, region, shared VPC, DR target)
├── checkout-cache.json        # one team's request: create, DR-enabled
├── search-cache.json          # another team's request: create, HA only
└── legacy-session-cache.json  # a decommission request
```

`locals.tf` does the merge in 4 layers, in priority order (later wins):

1. **`_valkey_defaults`** — `default.json` minus its `type` and
   `environments` keys: plain technical defaults (cluster mode, node
   type, backup schedule, maintenance window, etc.) every instance
   inherits unless it overrides them.
2. **`_env_infra`** — `default.json`'s `environments.<var.env>` block:
   project ID, region, Shared VPC host/network, and the DR secondary
   region. **Instance requests cannot override any of this** — it's
   centrally governed, same rule as the PostgreSQL version's
   `resource_group`/`location`.
3. **`payload.instance`** — the request file's own fields: `instance_id`,
   sizing (`replica_count`, `node_type`, ...), labels, alert email lists,
   and the `cross_region_replica` request signal.
4. **Derived `deployment_topology` / `secondary_location`** — computed
   from the merged result, not requested directly:
   - `cross_region_replica: { "enabled": true }` or bare `true` →
     `deployment_topology = "DR"`, `secondary_location` pulled from
     `_env_infra` (never from the request).
   - Otherwise, `replica_count > 0` → `"HA"`; else `"STANDALONE"`.

A request with `"request_type": "delete"`, or targeting a different
`environment` than `var.env`, is filtered out entirely at layer 3 — it
simply stops appearing in `local.valkey`, and therefore in the module's
`for_each`, on the next apply.

## Running it

```bash
terraform init
terraform apply -var="env=dev"
```

Review what a request actually resolves to *before* applying, using
`terraform console`:

```bash
terraform console -var="env=dev"
> local.valkey
```

or just check the `derived_topology_by_instance` output after a plan/apply
— it shows exactly what topology and DR region each onboarded instance
resolved to, which is the thing worth double-checking in a PR review
before merging a new `.json` request file.

## Onboarding vs. manifest: when to use which

| | YAML manifest (`../main.tf`) | JSON onboarding (this folder) |
|---|---|---|
| Where instances are declared | All in one file, per environment | One file per instance/request |
| Best for | Small, centrally-managed instance count; wanting the whole fleet visible in one diff | Many teams self-service requesting their own instance; each PR touches exactly one file |
| Merge behavior | None — every field is explicit per instance in the manifest | 3-layer merge (defaults → env infra → request), so requests only need to specify what differs from the norm |
| Adding an instance | Add a block under the right `env:` key in the manifest | Add a new `.json` file |
| Removing an instance | Flip `enabled: false` | Set `"request_type": "delete"` |
| Review surface | Whole manifest file in the diff | Just the one new/changed file |

Both patterns produce the same shape of map (keyed by instance name,
consumed by `for_each`) and call the exact same registry modules — you
can run either root, or even both against different `manifest_file`
subsets, without touching `terraform-google-valkey` or
`terraform-google-valkey-alerting` at all. That's the actual point of
having published these as separate modules: the composition pattern on
top is free to vary per team/root without forking the module itself.

## Gaps intentionally left for you to fill in

- `default.json`'s `environments.*.project_id` / `shared_vpc_*` values
  are placeholders — replace with your real project IDs and Shared VPC
  details before applying anywhere but a scratch sandbox.
- No file-naming ↔ `instance_id` consistency check exists yet (e.g.
  nothing stops `weird-filename.json` from declaring
  `"instance_id": "totally-different-name"`). If that matters to you, add
  a `check` block in `locals.tf` comparing the map key derived from
  `payload.instance.instance_id` against the filename.
- No JSON-schema validation of request files beyond what Terraform's own
  type checking catches at merge time — a request with a typo'd field
  name is silently dropped rather than rejected, since `merge()` doesn't
  validate keys. A pre-commit JSON-schema check in CI would close that
  gap.
