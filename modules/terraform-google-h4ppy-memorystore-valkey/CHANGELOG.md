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

## [2.0.1-pre] - 2026-08-04

> Tagged as a pre-release (`v2.0.1-pre`), not yet promoted to a stable
> tag — apply it in a non-prod environment first and confirm nothing in
> your callers still depends on the values being removed below.
>
> **Semver note:** strictly speaking this removes previously-accepted
> input values (`AUTH_DISABLED`, `TRANSIT_ENCRYPTION_DISABLED`), which
> is breaking behavior — a `2.0.x` patch tag doesn't fully capture that.
> Flagging this so it isn't missed by anyone skimming version numbers
> instead of reading changelogs; treat this the way you'd treat a major
> bump when deciding whether to auto-upgrade.

### Security
- **`authorization_mode` and `transit_encryption_mode` no longer accept
  insecure values.** `authorization_mode` must now be `IAM_AUTH` (or
  unset); `AUTH_DISABLED` is rejected by variable validation.
  `transit_encryption_mode` must now be `SERVER_AUTHENTICATION` (or
  unset); `TRANSIT_ENCRYPTION_DISABLED` is rejected. Both were already
  this module's *defaults* — this change removes the ability to
  override away from them. Any caller currently passing
  `authorization_mode = "AUTH_DISABLED"` or `transit_encryption_mode =
  "TRANSIT_ENCRYPTION_DISABLED"` explicitly will get a plan-time
  validation error and must remove that override (or the instance
  itself needs to be recreated with authentication/TLS enabled, which is
  a real change to the running instance — coordinate with whoever owns
  it before applying).
- Rationale: every instance this module creates now requires client
  authentication and in-transit encryption, full stop. There is no
  supported way to opt out.

## [2.0.0] - 2026-08-03

### Changed — BREAKING
- **Alerting removed from this module entirely.** `enable_alerting`,
  `appteam_emails`, `platformteam_emails`, the
  `alerting_requires_appteam_emails` check, and every alerting output
  (`alerting_enabled`, `notification_channel_ids`,
  `replication_lag_alert_enabled`, `alert_policy_ids`) are gone. Cloud
  Monitoring alert policies + email notification channels are now a
  separate module — `terraform-google-valkey-alerts` — that you call
  independently against this module's `instance_id` /
  `resolved_location` outputs.

  This reverses the 1.0.0 consolidation. The reason: with alerting
  folded into this module, adding or removing a single notification
  email required a plan/apply against the instance itself — which meant
  an email-list change went through the same change-ticket process as
  an infrastructure change. Splitting them apart means the email list
  can change on its own, independently of the instance.

- **No more nested submodules.** `module/_instance` and
  `module/_alert_policy` are gone; `google_memorystore_instance.primary`
  and `google_memorystore_instance.secondary` are now resources declared
  directly in this module's root `main.tf`. Registry modules should be
  flat/self-contained — everything a consumer needs to read is now in
  one directory instead of spread across `module/`.

- **Resource addresses changed** as a direct result of flattening:
  - `module.primary` → `google_memorystore_instance.primary`
  - `module.secondary[0]` → `google_memorystore_instance.secondary[0]`

  Existing state referencing the old `module.primary...` /
  `module.secondary...` addresses needs `terraform state mv` (or an
  equivalent `moved` block in your root config) before applying this
  version, or Terraform will plan to destroy and recreate the instance.
  Suggested commands, run from the calling root module:
  ```
  terraform state mv 'module.valkey.module.primary.google_memorystore_instance.this' \
    'module.valkey.google_memorystore_instance.primary'
  terraform state mv 'module.valkey.module.secondary[0].google_memorystore_instance.this' \
    'module.valkey.google_memorystore_instance.secondary[0]'
  ```
  (adjust the `module.valkey.` prefix to whatever you named the module
  call). If you had `enable_alerting = true`, also import the
  now-separate alert resources into a new
  `terraform-google-valkey-alerts` module call, or accept that Terraform
  will destroy them here and the new module will recreate them under
  new addresses — the underlying `google_monitoring_alert_policy` /
  `google_monitoring_notification_channel` resources are identical, so
  this is a Terraform-state-only move if you'd rather not recreate them
  (see that module's CHANGELOG for the target addresses).

### Added
- `resolved_location` output — the effective region the primary
  instance was created in, meant to be passed straight into
  `terraform-google-valkey-alerts`' `location` input.

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