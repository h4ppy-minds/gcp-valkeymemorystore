# Terraform Module: Memorystore for Valkey — Alerting

Reusable module that wires up Cloud Monitoring alert policies + email
notification channels for a Memorystore for Valkey instance. Call it once
per instance from your Valkey host project.

## What changed from the first draft

- **Removed `service_project_id`.** Notification channels are
  project-scoped, and an alert policy can only reference channels in its
  *own* project — so creating "service team" channels in a separate
  project could never actually be attached to alert policies living in
  the host project. Everything now lives in `var.project_id`.
- **Renamed `service_team_*` → `requester_*`** to match the actual goal:
  alerts go to the emails the requester of the instance gave you.
  `platform_*` remains as an optional standing ops list, cc'd in
  addition.
- **`replication_lag` is now conditional** (`replica_count > 0`, or an
  explicit `enable_replication_lag_alert` override). Previously it was
  unconditional and would sit permanently un-firing on a STANDALONE
  instance with no replicas — harmless, but noise.
- **Added a CRITICAL tier for rejected connections**, matching the
  two-tier pattern already used for CPU/memory. Sustained, high rejected
  connections is client-visible failure, not just a trend to watch.
- Fixed a threshold-variable rename
  (`rejected_connections_threshold` → `rejected_connections_warning_threshold`)
  to make room for the new critical threshold.

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
names against your instance in Metrics Explorer (I didn't want to wire
up metric type strings I couldn't verify): key eviction rate (memory
pressure causing silent data loss beyond what your `maxmemory-policy`
expects) and command/op latency (p99 spikes). Both are legitimate
production signals for a cache — just add them the same way as the
existing alerts once you've confirmed the metric name.

## Usage

```hcl
module "valkey_alerts" {
  source = "./modules/valkey-alerts"

  project_id  = "valkeyhubhost-500604"    # same project as the instance
  instance_id = google_memorystore_instance.shared_instance.instance_id
  region      = "us-central1"
  replica_count = 2

  requester_critical_emails = ["app-team-oncall@example.com"]
  requester_warning_emails  = ["app-team@example.com"]

  platform_critical_emails = ["platform-oncall@example.com"] # optional
  platform_warning_emails  = ["platform-team@example.com"]   # optional
}
```

See `examples/basic/main.tf` for a fuller example, including overriding
`replication_lag_warning_bytes` for a `highmem-xlarge` node type (the
64MB default is only correct for smaller node types — see the variable
description).

## Notes

- `project_id` is required and drives both the alert policies and every
  notification channel — see the variable description for why this
  can't be split across projects.
- `requester_critical_emails` is required and validated non-empty — a
  CRITICAL alert with nowhere to go is a silent outage.
- `requester_warning_emails` falls back to `requester_critical_emails`
  if left empty, so a WARNING alert is never silently dropped.



##Module Usage
  
module "valkey_alerts" {
  source = "../../modules/valkey-alerts"

  # Same project as the instance — see the note on project_id in
  # variables.tf for why this can't be split across projects.
  project_id  = "valkeyhubhost-500604"
  instance_id = google_memorystore_instance.shared_instance.instance_id
  region      = "us-central1"

  # replica_count just needs to match what you gave the instance —
  # it only controls whether the replication-lag alert gets created.
  replica_count = 2

  # The emails the requester (the app team asking for this instance) gave
  # you — this is the actual notification path for their alerts.
  requester_critical_emails = ["app-team-oncall@example.com"]
  requester_warning_emails  = ["app-team@example.com"] # optional — falls back to critical list if omitted

  # Optional — your own standing ops distribution list, cc'd in addition
  # to the requester's addresses. Leave both empty if you don't have one.
  platform_critical_emails = ["platform-oncall@example.com"]
  platform_warning_emails  = ["platform-team@example.com"]

  # Optional — override defaults if this workload's baseline differs.
  cpu_warning_threshold                = 0.8
  cpu_critical_threshold               = 0.95
  connected_clients_warning_threshold  = 6000
  rejected_connections_warning_threshold  = 1
  rejected_connections_critical_threshold = 50

  # Node type is highmem-xlarge here, so the 64MB default replication-lag
  # threshold is too tight — bump to Google's recommended <1GB.
  replication_lag_warning_bytes = 1073741824 # 1GB
}
