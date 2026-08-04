# Changelog

All notable changes to this module are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/) — this matters directly for a
Terraform registry, since the registry publishes one version per VCS tag
matching `vMAJOR.MINOR.PATCH`.

> This module is a re-extraction of the alerting logic that briefly lived
> inside `terraform-google-valkey` (that module's `1.0.0`, published
> 2026-07-30). It replaces that consolidation — see
> `terraform-google-valkey`'s `2.0.0` changelog entry for why — and is
> itself the direct successor of the original, separate `valkey-alerting`
> internal module that predated both.

## [1.0.0] - 2026-08-03

### Added
- `google_monitoring_alert_policy` (via `for_each` over
  `local.alert_definitions`) and `google_monitoring_notification_channel`
  (one per unique email address across `appteam_emails` and
  `platformteam_emails`), declared directly in this module's root
  `main.tf` — no nested submodule.
- Fixed alert set, unchanged from the instance module's short-lived
  built-in alerting: instance health (with an absent-metric check), CPU
  warning/critical, memory warning/critical, rejected-connections
  warning/critical, connected-clients elevated, and an optional
  replication-lag alert.
- `enable_replication_lag_alert` variable. This module has no visibility
  into the target instance's `replica_count` (it isn't the module that
  creates the instance), so the caller now decides explicitly — pass
  `replica_count > 0` (or your instance module's equivalent) rather than
  this module inferring it.
- `project_id`, `instance_id`, `location` variables identify the target
  instance to alert on by value, not by module reference — this module
  creates no compute/storage resources and has no dependency on any
  particular instance-creating module. Works against
  `terraform-google-valkey`'s outputs, or any other source of those
  three values.
- `enable_alerting`, `appteam_emails`, `platformteam_emails` — same
  variables and same "on with good defaults, or off; not individually
  retuned per caller" design as before. Every threshold, duration, and
  metric/resource-type string is a fixed constant in `alerts.tf`, not a
  variable.
- `alerting_requires_appteam_emails` check — `enable_alerting = true`
  requires at least one address in `appteam_emails`.
- Outputs: `alerting_enabled`, `notification_channel_ids`,
  `replication_lag_alert_enabled`, `alert_policy_ids`.

### Why this is a separate module from the instance
Folding alerting into the instance module meant that changing who gets
notified — adding, removing, or swapping a single email address — required
a plan/apply against the instance's own infrastructure, which in turn
meant an email-only change went through whatever change-ticket process
governs infrastructure changes. That's disproportionate to what the
change actually is. Splitting alerting into its own module means editing
`appteam_emails`/`platformteam_emails` here only ever plans this module —
never the instance.

## Migrating from `terraform-google-valkey`'s built-in alerting (pre-2.0.0)

If you previously had `enable_alerting = true` on a `terraform-google-valkey`
module call, its alert policies and notification channels were created at:

```
module.<your_instance_call>.google_monitoring_notification_channel.email["<address>"]
module.<your_instance_call>.module.alert_policies["<key>"].google_monitoring_alert_policy.this
```

To keep the existing Cloud Monitoring resources instead of destroying and
recreating them, add a new call to this module and `terraform state mv`
each resource into it, e.g.:

```
terraform state mv \
  'module.<your_instance_call>.google_monitoring_notification_channel.email["ops@example.com"]' \
  'module.<your_alerts_call>.google_monitoring_notification_channel.email["ops@example.com"]'

terraform state mv \
  'module.<your_instance_call>.module.alert_policies["cpu_warning"].google_monitoring_alert_policy.this' \
  'module.<your_alerts_call>.google_monitoring_alert_policy.this["cpu_warning"]'
```

Repeat the second command for each key in the old `local.alert_definitions`
map (`instance_down`, `cpu_warning`, `cpu_critical`, `memory_warning`,
`memory_critical`, `rejected_connections_warning`,
`rejected_connections_critical`, `connected_clients_high`, and
`replication_lag` if it existed). Run `terraform state list | grep
alert_policies` against your old state to get the exact set before you
start.
