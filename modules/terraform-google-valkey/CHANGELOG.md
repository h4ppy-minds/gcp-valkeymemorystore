# Changelog

All notable changes to this module are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/) — this matters directly for a
Terraform private registry, since the registry publishes one version per
VCS tag matching `vMAJOR.MINOR.PATCH`.

## [Unreleased]

### Documented
- Noted a GCP API constraint (not a module bug): `google_memorystore_instance`'s
  Update API rejects a request that changes more than one field at once
  (`Error 400: exactly 1 update_mask field must be specified per update
  request`). Confirmed via a real apply changing `shard_count` and
  `replica_count` together on an existing instance. Documented in
  README.md under "Known caveats" with the sequential-apply workaround
  and the recommended order (shrink replicas before shards; grow shards
  before replicas).

## [1.0.0] - 2026-07-23
### Added
- Initial release: `google_memorystore_instance` provisioning via a
  reusable `modules/_instance` submodule, called once for the primary and
  optionally once more for a DR secondary.
- `deployment_topology` (STANDALONE / HA / DR) as the single source of
  truth for replica/DR shape.
- Dynamic region/zone validation against `data.google_compute_regions` and
  `data.google_compute_zones` — no hardcoded region allow-list, so the
  module works in any region Memorystore for Valkey supports.
- PSC connectivity via Shared VPC (`psc_connectivity_mode = SHARED_VPC`)
  or none.
- Examples for all three topologies under `examples/`.

### Fixed
- Removed a hardcoded US-only region enum from `variable "location"`
  validation that would have blocked non-US deployments — dynamic
  validation already covered this correctly.