# Terraform Module: Memorystore for Valkey

Reusable Terraform module for provisioning a Google Cloud Memorystore for
Valkey instance — persistence, backups, maintenance windows,
authentication/TLS, CA management, encryption at rest, optional Shared
VPC connectivity, and optional cross-region DR (PRIMARY/SECONDARY) — all
driven by input variables, with no hardcoded project, region, or network.

## Files

| File | Contents |
|---|---|
| `versions.tf` | `required_providers` only — no `provider "google" {}` block, so the module never dictates project/credentials to its caller |
| `variables.tf` | All input variables, with validation and cross-field `check` blocks |
| `data.tf` | Region/zone lookups, project data source, Shared VPC network lookup |
| `locals.tf` | Derived values (effective zone(s), effective PSC network id, precondition helpers) |
| `main.tf` | The primary `google_memorystore_instance`, plus an optional `secondary` instance for DR |
| `output.tf` | Instance identity, PSC/discovery endpoint info, DR outputs |

This module is self-contained: every resource sets `project = var.project_id`
explicitly, so a single `provider "google" {}` in your root module can
instantiate it any number of times against different projects (see the
example below).

## The 3 deployment topologies — one module, one variable driving them

`var.deployment_topology` is a self-documenting label with three values:
`STANDALONE`, `HA`, `DR`. It doesn't silently change behavior — a `check`
block validates it's consistent with the variables that actually drive
the resources (`replica_count`, `enable_cross_region_replication`,
`secondary_location`), so the module's real behavior always stays fully
explained by its explicit inputs.

| Topology | What it means | Variables that produce it |
|---|---|---|
| `STANDALONE` | Single instance, no replicas, no cross-region DR | `replica_count = 0`, `enable_cross_region_replication = false` |
| `HA` | Single instance + replica(s), typically `MULTI_ZONE`, still one region | `replica_count >= 1`, `enable_cross_region_replication = false` |
| `DR` | Adds a `SECONDARY` instance in a second region, replicating from this instance (which becomes `PRIMARY`) | `enable_cross_region_replication = true`, `secondary_location` set |

A single call of this module produces exactly one of these three shapes
(DR still only being one `module` call — it just creates two
`google_memorystore_instance` resources under the hood: `primary-instance`
and `secondary[0]`).

**To stand up all three topologies at once from one file**, call the
module multiple times with `for_each` over a map of per-environment
configs — see
[`examples/three-topologies-single-file/main.tf`](../../examples/three-topologies-single-file/main.tf).
That's the "single resource file, three modes" pattern: one `module`
block, one `for_each`, three map entries.

## PSC Connectivity (`var.psc_connectivity_mode`)

| Mode | Behavior |
|---|---|
| `NONE` (default) | No endpoint block. Nothing can reach the instance over PSC until wired up outside this module. |
| `SHARED_VPC` | Points the instance at an **already-existing** Shared VPC network + Service Connection Policy (`service_class = gcp-memorystore`), both created outside this module. This module does not create the VPC, subnet, or policy — it only sets `desired_auto_created_endpoints`. Because the policy already authorizes the connection, Memorystore auto-creates the PSC endpoint itself the moment the instance is created; no second `apply`, no manual endpoint registration. |

Required inputs for `SHARED_VPC`: `shared_vpc_host_project`,
`shared_vpc_network_name`, `existing_scp_name` (enforced by the
`shared_vpc_inputs_present` check block). Note `existing_scp_name` is a
**guardrail-only** input — the `google` provider has no read-only data
source for Service Connection Policies, so Terraform cannot verify the
name you give it actually exists or authorizes this instance/region. It
exists so a caller is forced to name the policy they're relying on, not
to be programmatically checked. Confirm it out-of-band first:

```bash
gcloud network-connectivity service-connection-policies describe POLICY_NAME \
  --project=HOST_PROJECT_ID --region=REGION
```

> If you need multiple separate VPCs (or a different project than the
> instance's host project) to reach the same instance via
> user-registered PSC connections instead, that's a larger addition this
> module doesn't currently implement — see Known caveats.

## Prerequisites (outside Terraform)

**APIs enabled:**
- Host project (`project_id`): `memorystore.googleapis.com`
- Shared VPC host project (`shared_vpc_host_project`, `SHARED_VPC` mode only): `compute.googleapis.com`, `networkconnectivity.googleapis.com`

**IAM**, for whoever runs `terraform apply`:
- Host project: `roles/memorystore.admin` (or equivalent)
- Shared VPC host project (`SHARED_VPC` mode): `roles/compute.networkViewer` at minimum (this module only reads the network, it doesn't create it)

If using `CUSTOMER_MANAGED_CAS_CA` or `CUSTOMER_MANAGED` (CMEK)
encryption, Memorystore's service agent
(`service-PROJECT_NUMBER@cloud-memorystore.iam.gserviceaccount.com`) also
needs `roles/privateca.certificateRequester` on your CA pool, or
`roles/cloudkms.cryptoKeyEncrypterDecrypter` on your KMS key,
respectively. These IAM bindings are **not included** in this module —
add them alongside if you use those features.

## Usage

```hcl
module "valkey" {
  source = "./modules/memorystore-valkey"

  project_id  = "my-project"
  instance_id = "cache-prod"
  environment = "PROD"
  location    = "us-central1"

  deployment_topology = "HA"
  replica_count       = 2
  node_type           = "STANDARD_LARGE"
  shard_count         = 3
}
```

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

See `examples/three-topologies-single-file/` for a complete root module
that deploys STANDALONE, HA, and DR instances together via `for_each`.

## Key variables

See `variables.tf` for the full list with descriptions and validation.
Notable ones:

| Variable | Purpose |
|---|---|
| `project_id` | Host project (required, no default) |
| `deployment_topology` | `STANDALONE` / `HA` / `DR` — see above |
| `psc_connectivity_mode` | `NONE` or `SHARED_VPC` |
| `persistence_mode` | `RDB`, `AOF`, or `DISABLED` |
| `automated_backup_enabled` | GCS-backed backup collection, separate from persistence |
| `authorization_mode` / `transit_encryption_mode` | AUTH + TLS — see cross-field `check` blocks enforcing IAM_AUTH requires TLS |
| `server_ca_mode` / `server_ca_pool` | CA management — per-instance, shared, or customer-managed |
| `encryption_type` / `kms_key` | Encryption at rest (CMEK) |
| `deletion_protection_enabled` | Defaults to `true` — set `false` explicitly for disposable test instances |

## Known caveats — verify before production use

- **DR pairing on the primary side is unverified** — see the warning
  under "The 3 deployment topologies" above.
- **`server_ca_mode` enum casing**: this field was added recently to the
  provider; confirm exact values via `terraform providers schema -json`
  before relying on it.
- **Multi-VPC / user-registered PSC connections are not implemented.**
  If you need several separate consumer VPCs (or a different project
  than the instance's host project) reaching the same instance without
  a Shared VPC, that requires a separate `USER`-mode connectivity path
  (self-created forwarding rules +
  `google_memorystore_instance_desired_user_created_endpoints`) that
  this module doesn't currently build. That's a larger, separate
  addition, not a variant of `SHARED_VPC` mode.
- **CA/KMS service-agent IAM bindings are not included** — see
  Prerequisites above.
- **`existing_scp_name` has no Terraform-level effect** — see the PSC
  Connectivity section above.