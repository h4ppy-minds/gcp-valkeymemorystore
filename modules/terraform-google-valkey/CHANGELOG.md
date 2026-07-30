# Changelog

All notable changes to this module are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/) — this matters directly for a
Terraform registry, since the registry publishes one version per VCS tag
matching `vMAJOR.MINOR.PATCH`.

> This is the first published release of this module. It consolidates
> what were previously two separate internal, unpublished modules
> (`memorystore-valkey` and `valkey-alerting`) into one — that
> consolidation happened before this module was ever tagged or pushed to
> a registry, so it's reflected here as part of `1.0.0`'s initial
> feature set rather than as a breaking change between published
> versions.

## [1.0.0] - 2026-07-30

### Added
- `google_memorystore_instance` provisioning via a reusable
  `module/_instance` submodule, called once for the primary and
  optionally once more for a `SECONDARY` (DR) instance.
- `deployment_topology` (`STANDALONE` / `HA` / `DR`) as the single
  source of truth for replica count + cross-region DR shape, enforced by
  `check` blocks rather than left as independent, inconsistent inputs.
- Dynamic region/zone validation against `data.google_compute_regions`
  and `data.google_compute_zones` — no hardcoded region allow-list to
  fall out of date.
- PSC connectivity via an existing Shared VPC
  (`psc_connectivity_mode = "SHARED_VPC"`) or none.
- Full auth/TLS/CA/CMEK surface: `authorization_mode`,
  `transit_encryption_mode`, `server_ca_mode` (including
  customer-managed CA pools), `encryption_type` (including CMEK via
  `kms_key`), each cross-checked against the others (e.g.
  `IAM_AUTH` requires TLS) by `check` blocks.
- Persistence (`RDB` / `AOF` / `DISABLED`), automated backups, and a
  weekly maintenance window, each with a centrally-editable default.
- **Alerting is built into the same module call as the instance** — no
  separate module to wire up. `enable_alerting` (default `true`) turns
  it off entirely; when on, it creates a fixed set of Cloud Monitoring
  alert policies (instance health, CPU, memory, rejected connections,
  connected clients, and replication lag when `replica_count > 0`) and
  one email notification channel per unique address across
  `appteam_emails` (required whenever alerting is on) and
  `platformteam_emails` (optional). Alert policies are explicitly
  ordered after the instance (`depends_on = [module.primary]`, on top
  of the implicit dependency via `instance_id`).
- **All tunable instance defaults centralized into `all-locals.tf`**
  (`local.defaults` map + effective-value locals) and **all alerting
  defaults centralized into `alerts.tf`** (`local.alert_defaults`).
  Changing a default means editing one value in one file — see the
  README's "The 'one file for defaults' design" and "Alerting is
  intentionally not tunable per caller" sections.
- Alerting deliberately exposes only 3 variables
  (`enable_alerting`, `appteam_emails`, `platformteam_emails`) —
  thresholds, durations, and metric/resource-type strings are fixed
  constants, not overridable per caller, so alerting behavior stays
  consistent across every instance this module manages.
- Every variable in `variables.tf` carries an inline
  `--- REQUIRED ---` / `--- OPTIONAL ---` banner comment;
  `appteam_emails` is flagged as conditionally required, since
  Terraform's own required/optional distinction (presence of a
  `default`) can't express "required only when `enable_alerting =
  true`" — that's enforced by the `alerting_requires_appteam_emails`
  `check` block instead.
- `.terraform-docs.yml` + a generated Requirements/Providers/Modules/
  Resources/Inputs/Outputs table injected into `README.md` between
  `<!-- BEGIN_TF_DOCS -->` / `<!-- END_TF_DOCS -->` markers, kept in
  sync with `variables.tf`/`outputs.tf` by re-running `terraform-docs`
  rather than hand-maintained.
- `examples/basic-with-alerting` and `examples/instance-only-no-alerting`.

### Fixed (pre-release)
- `platformteam_emails` at one point defaulted to `[]` but also carried
  a `validation` block requiring `length > 0` — meaning the default
  itself always failed validation unless explicitly overridden. Fixed
  before this release; `platformteam_emails` is genuinely optional.
- Removed a hardcoded US-only region enum from `variable "location"`
  validation that would have blocked non-US deployments — dynamic
  validation against `data.google_compute_regions` already covers this
  correctly.

### Documented
- Noted a GCP API constraint (not a module bug):
  `google_memorystore_instance`'s Update API rejects a request that
  changes more than one field at once (`Error 400: exactly 1
  update_mask field must be specified per update request`). See
  README "Known caveats" for the sequential-apply workaround and
  recommended order (shrink replicas before shards; grow shards before
  replicas).
