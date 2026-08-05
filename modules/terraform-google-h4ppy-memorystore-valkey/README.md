# Terraform Module: Memorystore for Valkey (instance)

Single, reusable Terraform module for a Google Cloud Memorystore for
Valkey instance — persistence, backups, maintenance windows,
authentication/TLS, CA management, encryption at rest, optional Shared
VPC connectivity, optional cross-region DR.

**This module provisions the instance only.** Cloud Monitoring alert
policies and email notification channels for that instance are a
separate module — see
[`terraform-google-valkey-alerts`](../terraform-google-valkey-alerts) —
which you call independently, wired up against this module's
`instance_id` and `resolved_location` outputs.

## Why alerting is a separate module

An earlier version of this module folded alerting in directly, so one
`module` block produced both the instance and its alert policies. In
practice that meant changing who gets notified — adding, removing, or
swapping a single email address in `appteam_emails` — required a
plan/apply against the instance's own infrastructure, and therefore went
through whatever change-ticket process governs infrastructure changes.
That's disproportionate to what the change actually is: updating an
email list shouldn't require the same review as changing shard count or
persistence mode.

Splitting alerting into `terraform-google-valkey-alerts` means:
- Editing the notification email list only ever plans that module — never
  this one.
- This module's blast radius stays scoped to the instance itself.
- The two modules can be versioned and changed independently.

See that module's `CHANGELOG.md` for how to migrate existing alert
policies out of this module's state if you were previously using its
built-in alerting (pre-`2.0.0`).

## No submodules

Everything in this module lives in this one directory — there is no
`module/` subdirectory. The primary and (optional) secondary DR instance
are two explicit `google_memorystore_instance` resource blocks in
`main.tf` rather than two calls into a shared internal module. They
necessarily repeat most of their arguments; that repetition is the
tradeoff for a flat, single-directory registry module. Registry modules
generally shouldn't nest submodules a consumer never calls directly —
everything relevant to using or auditing this module should be readable
from its root path.

## Auth and TLS are mandatory, not defaults

`authorization_mode` and `transit_encryption_mode` accept exactly one
value each — `IAM_AUTH` and `SERVER_AUTHENTICATION` respectively (or
leave them unset, which resolves to the same thing). Variable validation
rejects `AUTH_DISABLED` and `TRANSIT_ENCRYPTION_DISABLED` outright; there
is no supported way to create an unauthenticated or unencrypted instance
with this module. See `CHANGELOG.md`'s `3.0.0` entry if you're migrating
a caller that previously overrode either of these.

## The "one file for defaults" design

Every tunable default value in this module lives in exactly one file,
`all-locals.tf` (`local.defaults` map: topology, sizing, persistence,
auth/TLS/CA, backups, maintenance, engine config). These remain
overridable per caller via the matching variable.

Mechanically:
- Variables that have a default don't carry a literal value in
  `variables.tf` — they default to `null`.
- `all-locals.tf` computes the effective value of each as
  `coalesce(var.x, local.defaults.x)`.
- `main.tf` and `data.tf` all read the `local.x` effective value —
  never `var.x` directly — for anything that has a default.

**To change a default** (e.g. bump the default `node_type`, turn off
automated backups by default, add a new region to the allow-list), edit
the value in `local.defaults` inside `all-locals.tf`. Nothing in
`variables.tf` or `main.tf` needs to change.

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
| `variables.tf` | Every instance variable, plus every cross-field `check` block, checked against effective values |
| `all-locals.tf` | **The** file to edit for defaults (topology, sizing, persistence, auth/TLS/CA, backups, maintenance, engine config). `local.defaults` map, the effective-value locals derived from it, and derived logic (zone resolution, precondition booleans) |
| `data.tf` | Region/zone lookups, project data source, Shared VPC network lookup |
| `main.tf` | The primary `google_memorystore_instance`, plus an optional `secondary` for DR — both declared directly here, no submodule |
| `outputs.tf` | Instance identity, PSC/discovery endpoint info, DR outputs |

## Alerting for an instance from this module

```hcl
module "valkey" {
  source = "path/to/terraform-google-valkey"

  project_id  = "my-project"
  environment = "PROD"
  shard_count = 3
  # ...
}

module "valkey_alerts" {
  source = "path/to/terraform-google-valkey-alerts"

  project_id  = "my-project"
  instance_id = module.valkey.instance_id
  location    = module.valkey.resolved_location

  appteam_emails                = ["app-team@example.com"]
  enable_replication_lag_alert  = false # or true if replica_count > 0
}
```

## Known caveats
`google_memorystore_instance`'s Update API rejects a request that changes
more than one field at once (`Error 400: exactly 1 update_mask field must
be specified per update request`). If you're changing multiple fields
(e.g. both `shard_count` and `replica_count`), apply sequentially instead
of in one `terraform apply`. Recommended order: shrink replicas before
shrinking shards; grow shards before growing replicas.
