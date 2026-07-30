locals {

  # --- Layer 1: global technical defaults + per-environment infra ---
  # One default.json with plain defaults at the top level, plus a
  # reserved "environments" key holding per-env infra (project, region,
  # shared VPC, DR target region) that instance requests are never
  # allowed to set themselves.
  _defaults_raw = jsondecode(file("${path.module}/config/onboarding-files-valkey/default.json"))

  # Strip the two reserved/structural keys, leaving just the flat
  # technical defaults every instance inherits unless it overrides them.
  _valkey_defaults = {
    for k, v in local._defaults_raw : k => v
    if !contains(["type", "environments"], k)
  }

  # Current environment's centrally-governed infra (project_id, location,
  # shared_vpc_*, cross_region_replica.location for DR). var.env selects
  # which block — typically set per TFC/TFE workspace.
  _env_infra = local._defaults_raw.environments[var.env]

  # --- Layer 2: one onboarding request per file ---
  # Every *.json file in the folder except default.json is a self-service
  # request: { request_type, environment, instance: {...} }. Team PRs add
  # or edit exactly one file — no shared file to merge-conflict over.
  _all_instances = {
    for f in fileset("${path.module}/config/onboarding-files-valkey", "*.json") :
    f => jsondecode(file("${path.module}/config/onboarding-files-valkey/${f}"))
    if f != "default.json"
  }

  # --- Layer 3: merge defaults -> env infra -> instance overrides ---
  # Keyed by the instance's own declared instance_id (not the filename),
  # so renaming a file doesn't change the resource's identity.
  # Excludes anything not targeting the current environment, and anything
  # marked request_type = "delete" — a delete request stops appearing in
  # this map (and therefore in the module's for_each) on the next apply,
  # rather than requiring a separate destroy step.
  _valkey_raw = {
    for f, payload in local._all_instances :
    payload.instance.instance_id => merge(
      local._valkey_defaults,
      local._env_infra,
      payload.instance,
    )
    if payload.environment == var.env && payload.request_type != "delete"
  }

  # RDB snapshot period as an ISO-8601-ish duration string, for timeadd().
  # Matches the module's own rdb_snapshot_period enum exactly.
  _rdb_period_to_duration = {
    ONE_HOUR          = "1h"
    SIX_HOURS         = "6h"
    TWELVE_HOURS      = "12h"
    TWENTY_FOUR_HOURS = "24h"
  }

  # --- Layer 4: normalize cross_region_replica + derive deployment_topology ---
  # Adapted to the merged module's actual DR inputs (deployment_topology +
  # secondary_location, not a resource_group). Accepts either input style
  # from a request file:
  #   "cross_region_replica": { "enabled": true }   (nested)
  #   "cross_region_replica": true                  (bare boolean)
  # The *location* for DR is never taken from the request — it always
  # comes from the environment's central infra config
  # (_env_infra.cross_region_replica.location), so a team can ask for DR
  # but cannot pick which region their secondary lands in.
  #
  # rdb_snapshot_start_time: if the request file supplies its own value,
  # that wins (an explicit override always beats a computed default).
  # Otherwise, when persistence_mode == "RDB", default to
  # time_static.rdb_anchor[name] (frozen at first apply) + the
  # instance's rdb_snapshot_period as a duration. This single value is
  # what the module forwards to BOTH its primary and (if DR) secondary
  # instance internally, so the secondary is guaranteed to reference the
  # exact same recorded value as the primary rather than computing its
  # own "now" independently — which is what the module's
  # persistence_config_consistency check exists to protect against.
  valkey = {
    for name, cfg in local._valkey_raw :
    name => merge(cfg, {
      deployment_topology = (
        try(cfg.cross_region_replica.enabled, cfg.cross_region_replica == true) ? "DR" :
        (try(cfg.replica_count, 0) > 0 ? "HA" : "STANDALONE")
      )
      secondary_location = (
        try(cfg.cross_region_replica.enabled, cfg.cross_region_replica == true)
        ? local._env_infra.cross_region_replica.location
        : null
      )
      rdb_snapshot_start_time = (
        cfg.persistence_mode != "RDB" ? null :
        try(cfg.rdb_snapshot_start_time, null) != null ? cfg.rdb_snapshot_start_time :
        timeadd(
          time_static.rdb_anchor[name].rfc3339,
          local._rdb_period_to_duration[cfg.rdb_snapshot_period]
        )
      )
      # cross_region_replica itself was only a request-time signal — the
      # module doesn't take this key, so it's dropped from the final map
      # rather than passed through and rejected as an unsupported argument.
      cross_region_replica = null
    })
  }
}
