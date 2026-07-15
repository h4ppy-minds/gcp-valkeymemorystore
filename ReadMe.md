# Valkey Terraform Project — Root Module

Root-level Terraform configuration for provisioning a Google Cloud
Memorystore for Valkey instance. This is a thin wrapper: all actual
resources (the instance, and any PSC networking) live in
`modules/valkey/`; the root just declares variables, forwards them into
that module, and re-exposes its outputs.

## Layout

```
.
├── main.tf          # module "valkey" block — forwards all inputs to modules/valkey
├── variables.tf      # every input variable, typed + described (validation lives in the module)
├── output.tf         # re-exports modules/valkey's outputs
├── test.tfvars        # NONE-mode smoke test — bare instance, no PSC connectivity
├── dr-test.tfvars      # SHARED_VPC-mode example with cross-region DR
├── tempalte-tfvars.md   # full annotated reference for every variable, with quick presets
└── modules/
    └── valkey/        # actual resources — google_memorystore_instance, PSC data lookups, locals, outputs
```

Root and module stay in sync manually. If a variable or output is
added, removed, or renamed in `modules/valkey/variables.tf` or
`modules/valkey/output.tf`, mirror the change here — `terraform
validate` will fail with an "Unsupported attribute" or "Unsupported
argument" error otherwise, since Terraform doesn't infer the module's
interface for you.

## Why root validation is thin

`variables.tf` at root declares `type` and `description` for every
variable, but intentionally carries **no `validation` or `check`
blocks**. All business-rule validation (enum values, cross-field
consistency, PROD-only restrictions) lives once, in
`modules/valkey/variables.tf`. This isn't a gap — Terraform evaluates
module input validation at `plan`/`validate` time regardless of
whether the root also validates, so duplicating the rules here would
only risk the two copies drifting apart (as already happened once in
this project — see Known Issues below). Root's job is to be a
predictable pass-through, not a second source of truth.

## Architecture: PSC Connectivity Modes

Memorystore instances are not directly inside your VPC — they connect
via **Private Service Connect (PSC)**. This project supports exactly
two connectivity modes, set by `var.psc_connectivity_mode`:

### `NONE`

No PSC networking is created at all. The instance is created with no
endpoint configuration and has no private connectivity path. Useful
for validating that the instance itself provisions correctly —
persistence, backups, engine config, auth settings — independent of
networking. This is also the variable's default.

```
project_id (host)
  └── google_memorystore_instance   (no endpoint, no network resources)
```

### `SHARED_VPC`

The instance's PSC endpoint is auto-created inside an **existing**
Shared VPC network, authorized by a **Service Connection Policy (SCP)**
your platform/network team already provisioned — nothing about the
network or the SCP is created by this project.

```
shared_vpc_host_project (network hub — e.g. your org's "core-net" project)
  └── existing Shared VPC network        (looked up via data source)
        └── existing SCP: service_class = gcp-memorystore, region = var.location
              └── PSC endpoint             (auto-created by Memorystore against the SCP)
                          │
                          ▼
project_id (host — e.g. "hum-it-memorystore-...")
  └── google_memorystore_instance
```

Any workload that is genuinely inside that same Shared VPC network
(i.e. deployed as a service project attached to the host, using one of
its shared subnets) can reach the endpoint's private IP, subject to the
Shared VPC's firewall rules and the instance's own `authorization_mode`.
**VPC Peering to the Shared VPC does not give reachability to the PSC
endpoint** — Google's PSC endpoints are explicitly not accessible from
peered networks, only from clients in the same VPC (or Shared VPC)
network. If a team's workloads live in a genuinely separate VPC, they
need to become a service project of the Shared VPC and deploy into its
subnets, not peer their existing VPC to it.

> **Note:** an SCP is regional. If you also enable
> `enable_cross_region_replication` for DR, the SECONDARY instance in
> `secondary_location` needs its own existing SCP in that region — the
> primary's SCP does not cover it. Confirm `modules/valkey` has an
> input for a secondary-region SCP name before relying on DR +
> SHARED_VPC together (see Known Issues).

### Removed: `AUTO` and `USER` modes

Earlier drafts of this module supported `AUTO` (Memorystore creates its
own isolated consumer VPC + SCP for you) and `USER` (you manually wire
forwarding rules per consumer network). Both were removed because
neither matches this org's actual topology — a centrally-managed
Shared VPC hub with an SCP the platform team already created. `AUTO`
would have provisioned a shadow, ungoverned VPC per instance; `USER`
would have required manually replicating networking wiring the
platform team already owns.

## Prerequisites (outside Terraform)

**APIs enabled**, on `project_id` (host project):
- `memorystore.googleapis.com`

**APIs enabled**, on `shared_vpc_host_project` (only for `SHARED_VPC` mode):
- `compute.googleapis.com`
- `networkconnectivity.googleapis.com`

**IAM**, for whoever runs `terraform apply`:
- Host project (`project_id`): `roles/memorystore.admin` (or equivalent)
- `shared_vpc_host_project` (SHARED_VPC mode only): read access to the
  network and the SCP — `roles/compute.networkViewer` at minimum, since
  this project only looks these up via `data` sources and never creates
  or modifies them

If using `CUSTOMER_MANAGED_CAS_CA` or `CUSTOMER_MANAGED` (CMEK)
encryption, Memorystore's service agent
(`service-PROJECT_NUMBER@cloud-memorystore.iam.gserviceaccount.com`)
also needs `roles/privateca.certificateRequester` on your CA pool, or
`roles/cloudkms.cryptoKeyEncrypterDecrypter` on your KMS key,
respectively. These IAM bindings are **not included** in this project —
add them alongside if you use those features.

## Usage

```bash
terraform init
terraform validate
terraform plan  -var-file=test.tfvars
terraform apply -var-file=test.tfvars
```

Unlike the old `USER`-mode PSC setup, neither `NONE` nor `SHARED_VPC`
requires a two-phase `-target` apply — `SHARED_VPC` relies on
Memorystore auto-creating the endpoint against an already-existing SCP,
so a single `apply` is sufficient.

## Key variables

See `variables.tf` for the full list with types and descriptions, and
`tempalte-tfvars.md` for a fully annotated example with quick presets.
Notable ones:

| Variable | Purpose |
|---|---|
| `project_id` | Host project (required, no default) |
| `psc_connectivity_mode` | `NONE` or `SHARED_VPC` |
| `shared_vpc_host_project` / `shared_vpc_network_name` / `existing_scp_name` | Required together when `psc_connectivity_mode = SHARED_VPC` |
| `deployment_topology` | `STANDALONE`, `HA`, or `DR` — self-documenting label validated against `replica_count`/`enable_cross_region_replication` in the module |
| `persistence_mode` | `RDB`, `AOF`, or `DISABLED` |
| `automated_backup_enabled` | GCS-backed backup collection, separate from persistence |
| `authorization_mode` / `transit_encryption_mode` | AUTH + TLS — `IAM_AUTH` requires `SERVER_AUTHENTICATION`, enforced in the module |
| `server_ca_mode` / `server_ca_pool` | CA management — per-instance, shared, or customer-managed |
| `encryption_type` / `kms_key` | Encryption at rest (CMEK) |
| `deletion_protection_enabled` | Defaults to `true` — set `false` explicitly for disposable test instances |

## Known issues — verify before production use

- **`consumer_project_id`** is still declared at root and forwarded to
  the module, but it was only meaningful for the removed `AUTO`/`USER`
  modes. Confirm whether `modules/valkey/variables.tf` still accepts
  this input — if it was dropped there, `terraform validate` will
  reject it as an unsupported module argument, and both the root
  variable and its pass-through line in `main.tf` need to be deleted.
- **CA enum mismatch**: `server_ca_mode`'s valid values include
  `CUSTOMER_MANAGED_CAS_CA`, but the module's `check` blocks
  (`customer_managed_ca_requires_pool`, `server_ca_pool_requires_tls`)
  compare against `CUSTOMER_MANAGED_CA` — missing `_CAS_`. As written,
  those checks can never fire. Fix the comparison strings in
  `modules/valkey/variables.tf`.
- **DR + SHARED_VPC**: the secondary (DR) instance needs its own
  existing SCP in `secondary_location`, since SCPs are regional. Verify
  `modules/valkey` exposes an equivalent of `existing_scp_name` scoped
  to the secondary region before relying on this combination — it may
  not be wired up yet.
- **This project does not create or modify IAM bindings** for CMEK or
  customer-managed CA service-agent access — see Prerequisites above.

## Testing this project

- `test.tfvars` — `NONE` mode, smallest valid configuration. Validates
  that the instance itself (persistence, backups, engine config, auth)
  provisions correctly, independent of any networking.
- `dr-test.tfvars` — `SHARED_VPC` mode with `enable_cross_region_replication
  = true`. Validates the Shared VPC + SCP lookup path and cross-region
  DR wiring together.

Once both succeed independently, combine settings incrementally
(persistence + backups + auth + CA + CMEK) rather than enabling
everything in one pass.