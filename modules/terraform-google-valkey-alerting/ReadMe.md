# Terraform Module: Memorystore for Valkey — Alerting

Reusable module that wires up Cloud Monitoring alert policies + email
notification channels for a Memorystore for Valkey instance. Call it once
per instance from your Valkey host project.

## Structure

This module follows the same wrapper/inner-module split as the
`memorystore-valkey` module: a generic, reusable resource lives in a small
inner module and gets instantiated multiple times, instead of being
hand-duplicated per alert.

| File | Contents |
|---|---|
| `variables.tf` | Inputs, split into three tiers — required, commonly-set optional, and advanced (durations/metric-type overrides you should basically never touch) |
| `locals.tf` | `alert_definitions` — the table that *is* the alert set — plus notification-channel spec flattening and derived values |
| `notifications.tf` | One `google_monitoring_notification_channel` resource, `for_each` over every unique address across `appteam_emails` + `platformteam_emails` |
| `alert_policies.tf` | One `module` block, `for_each` over `local.alert_definitions`, calling `module/_alert_policy` once per alert |
| `module/_alert_policy/` | The inner module — a single generic threshold alert policy (optionally with an absent-metric check). This is the `_instance` of this module: one definition, called N times. |
| `output.tf` | Channel ID lists, replication-lag-enabled flag, alert policy name map |

**Adding a new alert doesn't mean writing a new resource block.** Add one
entry to `local.alert_definitions` in `locals.tf`; `alert_policies.tf`
picks it up automatically via `for_each`.

## Design choices carried over from the first draft

- **No `service_project_id`.** Notification channels are project-scoped,
  and an alert policy can only reference channels in its own project — so
  creating "service team" channels in a separate project could never
  actually be attached to alert policies living in the host project.
  Everything lives in `var.project_id`.
- **`appteam_emails` / `platformteam_emails`** — split by team, not by
  severity. Every alert this module creates (WARNING or CRITICAL) notifies
  both sets combined. Cloud Monitoring's `email` channel type only takes
  one address per channel, so this creates one channel per unique address
  across both sets and attaches the whole combined list to every alert —
  there's no way to get a literal comma-joined `To:` line into a single
  channel, since the API validates `labels.email_address` as one address.
- **`replication_lag` is conditional** (`replica_count > 0`, or an
  explicit `enable_replication_lag_alert` override) — it simply isn't a
  key in `local.alert_definitions` when disabled, so `module.alert_policies`
  never creates it and `alert_policy_ids` never has a null to filter.
- **Two-tier WARNING/CRITICAL pattern** for CPU, memory, and rejected
  connections — sustained, high rejected connections is client-visible
  failure, not just a trend to watch, so it gets the same treatment as
  CPU/memory rather than staying warning-only.

## Variable tiers — the "default, don't ask" philosophy

Only four inputs are required: `project_id`, `instance_id`, `region`, and
`appteam_emails`. Everything else defaults to a production-sane value:

1. **Required** — target instance + primary notification path.
2. **Commonly set** — `replica_count`, the optional `platformteam_emails`
   set, threshold overrides. These exist
   because different workloads genuinely have different baselines, but a
   typical caller sets few or none of them.
3. **Advanced** — condition durations and metric-type strings. These are
   still real Terraform variables (not hardcoded into `module/_alert_policy`),
   so if a specific alert flaps and needs retuning, or Google renames a
   metric, it's a variable override — not a module edit. You should not
   expect to touch this tier in normal use.

## The alert set (production-oriented, not exhaustive)

| Alert | Severity | Signal |
|---|---|---|
| `instance_down` | CRITICAL | Node health check failing, or the health metric goes absent entirely (covers regional-outage-style silent failure, not just a reported-unhealthy state) |
| `cpu_warning` / `cpu_critical` | WARNING / CRITICAL | `instance/cpu/maximum_utilization` |
| `memory_warning` / `memory_critical` | WARNING / CRITICAL | `instance/memory/maximum_utilization` |
| `rejected_connections_warning` / `_critical` | WARNING / CRITICAL | `instance/node/stats/rejected_connections_count` |
| `connected_clients_high` | WARNING | `instance/node/clients/connected_clients` — backpressure signal, set below `maxclients` |
| `replication_lag` | WARNING | `instance/node/replication/maximum_offset_diff` — only created when `replica_count > 0` |

Not included, and worth adding once you've confirmed the exact metric
names against your instance in Metrics Explorer (I didn't want to wire up
metric type strings I couldn't verify): key eviction rate (memory
pressure causing silent data loss beyond what your `maxmemory-policy`
expects) and command/op latency (p99 spikes). Both are legitimate
production signals for a cache — add them the same way as the existing
alerts, as a new entry in `local.alert_definitions`, once you've confirmed
the metric name.

## Usage

```hcl
module "valkey_alerts" {
  source = "./modules/valkey-alerting"

  project_id  = "valkeyhubhost-500604"    # same project as the instance
  instance_id = google_memorystore_instance.shared_instance.instance_id
  region      = "us-central1"
  replica_count = 2

  appteam_emails      = ["app-team-oncall@example.com", "app-team@example.com"]
  platformteam_emails = ["platform-oncall@example.com"] # optional
}
```

See `example-usage.tf` for a fuller example, including overriding
`replication_lag_warning_bytes` for a `highmem-xlarge` node type (the
64MB default is only correct for smaller node types — see the variable
description).

## Notes

- `project_id` is required and drives both the alert policies and every
  notification channel — see the variable description for why this can't
  be split across projects.
- `appteam_emails` is required and validated non-empty — an alert with
  nowhere to go is a silent outage.
- `platformteam_emails` is optional; every address in both sets gets
  every alert this module creates, since there's no severity split
  anymore.
- If you need to retune a specific alert's duration or point it at a
  renamed metric, override the relevant "advanced" variable — you should
  not need to edit `module/_alert_policy` or `locals.tf` for that.