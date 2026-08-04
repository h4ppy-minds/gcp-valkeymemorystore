# Terraform Module: Memorystore for Valkey — Alerting

Cloud Monitoring alert policies + email notification channels for one
Memorystore for Valkey instance. This module creates no compute/storage
resources of its own — it points Cloud Monitoring at an instance that
already exists (e.g. one created by
[`terraform-google-valkey`](../terraform-google-valkey)) via that
instance's `project_id`, `instance_id`, and `location`.

## Why this is its own module

This used to be folded into the instance module itself, so one `module`
call produced both the instance and its alerting. That meant changing
who gets notified — adding, removing, or swapping a single address in
`appteam_emails` — required a plan/apply against the instance's own
infrastructure, and so went through whatever change-ticket process
governs infrastructure changes. An email-list update isn't an
infrastructure change and shouldn't need to be treated like one.

As a separate module:
- Editing `appteam_emails` / `platformteam_emails` only ever plans
  **this** module. It never touches, or requires re-planning, the
  instance.
- Anyone who owns the notification list doesn't need write access to (or
  review authority over) the instance's Terraform.
- This module can be versioned and released independently of the
  instance module.

## No submodules

Everything lives in this one directory. The notification channels and
alert policies are declared directly as `google_monitoring_notification_channel`
and `google_monitoring_alert_policy` resources in `main.tf`, each driven
by a `for_each` over a locals-built table (`alerts.tf`) — there is no
nested per-alert submodule.

## Alerting is intentionally not tunable per caller

This module exposes exactly these alerting-routing variables:
- `enable_alerting` — on/off switch
- `appteam_emails` — required when enabled
- `platformteam_emails` — optional, in addition to `appteam_emails`
- `enable_replication_lag_alert` — see below

Every threshold, duration, and metric/resource-type string — CPU/memory
utilization thresholds, rejected-connections thresholds, alignment
periods, `auto_close` durations, the exact Cloud Monitoring metric type
strings — is a fixed constant in `local.alert_defaults`
(`alerts.tf`), **not** a variable. This module's alerting is meant to
ship as "on with good defaults, or off," not individually retuned per
caller, so that alerting behavior stays consistent across every instance
this module is pointed at. If a threshold genuinely needs to change,
edit `local.alert_defaults` directly; there is no variable path for it.

## Why `enable_replication_lag_alert` is a variable, not inferred

The previous, folded-in version of this alerting derived
"does this instance need a replication-lag alert" from the instance's
own `replica_count` local. Now that alerting is a separate module with
no access to the instance's internals, that inference isn't possible —
the caller passes `enable_replication_lag_alert` explicitly (typically
`replica_count > 0`, using whatever value your instance module exposes).

## Structure

| File | Contents |
|---|---|
| `versions.tf` | `required_providers` only |
| `variables.tf` | `project_id` / `instance_id` / `location` (identify the target instance), alerting-routing variables, and the `alerting_requires_appteam_emails` check |
| `alerts.tf` | **The** file to edit for alerting behavior. `local.alert_defaults` — every threshold/duration/metric constant, none of them variables — plus notification-channel dedup logic and `local.alert_definitions`, the table that IS the alert set |
| `main.tf` | `google_monitoring_notification_channel.email` (one per unique address) and `google_monitoring_alert_policy.this` (`for_each` over `local.alert_definitions`) |
| `outputs.tf` | `alerting_enabled`, `notification_channel_ids`, `replication_lag_alert_enabled`, `alert_policy_ids` |

## Usage

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
  platformteam_emails           = ["oncall@example.com"]
  enable_replication_lag_alert  = false # true if module.valkey has replicas
}
```

### Changing who gets notified

Once the above is applied, adding or removing an email address is a
change to `appteam_emails` / `platformteam_emails` only:

```hcl
module "valkey_alerts" {
  source = "path/to/terraform-google-valkey-alerts"

  project_id  = "my-project"
  instance_id = module.valkey.instance_id
  location    = module.valkey.resolved_location

  appteam_emails = ["app-team@example.com", "new-teammate@example.com"]
  # ...
}
```

`terraform plan` against this module call only ever touches
`google_monitoring_notification_channel` / `google_monitoring_alert_policy`
resources — never the instance.

## Migrating from the old built-in alerting

See `CHANGELOG.md` for `terraform state mv` commands to move existing
alert policies/notification channels into this module instead of having
Terraform destroy and recreate them.
