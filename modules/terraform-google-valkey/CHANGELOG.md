# Changelog

All notable changes to this module are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/) — this matters directly for a
Terraform private registry, since the registry publishes one version per
VCS tag matching `vMAJOR.MINOR.PATCH`.

## [2.1.0] - Unreleased

### Changed — BREAKING
- **Alerting variable surface cut from 25 down to 3.** Only
  `enable_alerting`, `appteam_emails`, and `platformteam_emails` remain
  as alerting inputs. Every threshold (`cpu_warning_threshold`, ...),
  duration (`warning_duration`, `critical_auto_close`, ...), metric/
  resource-type override, and `enable_replication_lag_alert` has been
  removed as a variable and is now a fixed constant in `local.alert_defaults`
  (`alerts.tf`). A caller relying on any of those overrides will get a
  "no variable named ..." error on `terraform plan` and needs to move
  that override into `alerts.tf` directly (see README migration notes).
- **Alerting defaults + logic extracted into a new file, `alerts.tf`,**
  out of `all-locals.tf`. `all-locals.tf` is now instance-only.
- Explicit `depends_on = [module.primary]` added to the `alert_policies`
  module call, on top of the pre-existing implicit dependency via
  `instance_id = module.primary.instance_id`.
- Every variable in `variables.tf` now has an inline `--- REQUIRED ---`
  or `--- OPTIONAL ---` banner comment. `appteam_emails` is flagged as
  conditionally required instead, since Terraform's required/optional
  distinction (presence of `default`) can't express "required only when
  `enable_alerting = true`."
- `.terraform-docs.yml` added; `README.md` now has a generated
  Requirements/Providers/Modules/Resources/Inputs/Outputs table injected
  between `<!-- BEGIN_TF_DOCS -->` / `<!-- END_TF_DOCS -->` markers.

## [2.0.0] - Unreleased

### Changed — BREAKING
- **Merged `terraform-google-valkey` and `terraform-google-valkey-alerting`
  into this single module.** One `module` block now provisions both the
  instance(s) and its alerting. `enable_alerting` (default `true`) toggles
  the alerting half off if you want the instance only.
- Alerting no longer takes its own `instance_id`/`region` inputs — both
  are now derived internally from the created primary instance
  (`module.primary`), instead of being passed in a second time by the
  caller.
- **All tunable defaults centralized into `all-locals.tf`** (`local.defaults`
  map + effective-value locals). Every variable that previously carried a
  literal default in `variables.tf` now defaults to `null`; the actual
  default lives in exactly one place. See README "The 'one file for
  defaults' design".
- Existing root modules calling the old two modules need a state move —
  see README "Migrating from the two-module setup".

### Fixed
- `platformteam_emails` previously defaulted to `[]` but also carried a
  `validation` block requiring `length > 0` — meaning the default itself
  always failed validation unless explicitly overridden. That validation
  is removed; `platformteam_emails` is now genuinely optional, matching
  its documented intent.

### Documented
- Noted a GCP API constraint (not a module bug): `google_memorystore_instance`'s
  Update API rejects a request that changes more than one field at once
  (`Error 400: exactly 1 update_mask field must be specified per update
  request`). Documented in README.md under "Known caveats" with the
  sequential-apply workaround and the recommended order (shrink replicas
  before shards; grow shards before replicas).

## [1.0.0] - 2026-07-23 (memorystore-valkey, prior to merge)
### Added
- Initial release: `google_memorystore_instance` provisioning via a
  reusable `module/_instance` submodule, called once for the primary and
  optionally once more for a DR secondary.
- `deployment_topology` (STANDALONE / HA / DR) as the single source of
  truth for replica/DR shape.
- Dynamic region/zone validation against `data.google_compute_regions` and
  `data.google_compute_zones`.
- PSC connectivity via Shared VPC (`psc_connectivity_mode = SHARED_VPC`)
  or none.

### Fixed
- Removed a hardcoded US-only region enum from `variable "location"`
  validation that would have blocked non-US deployments — dynamic
  validation already covered this correctly.
