############################################
# rdb_snapshot_start_time defaulting
#
# Why not just use timeadd(timestamp(), ...) directly in locals.tf: the
# built-in timestamp() function re-evaluates to the current moment on
# EVERY plan/apply, so a default built directly from it would produce a
# new "requested" rdb_snapshot_start_time every single apply — a
# perpetual diff, even though nothing about the instance actually
# changed. time_static resources solve this: the value is captured once,
# when the resource is first created, and then stays fixed in state
# across every future plan/apply (it does not track wall-clock time) —
# a static timestamp, not a clock.
#
# One time_static per onboarded instance (for_each over the raw merged
# map — before topology derivation, so this exists even for instances
# that don't end up needing it; unused ones cost nothing extra).
############################################

resource "time_static" "rdb_anchor" {
  for_each = local._valkey_raw
}
