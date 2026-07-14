# Terraform Module: Memorystore for Valkey

Production-oriented Terraform module for provisioning a Google Cloud
Memorystore for Valkey instance, including persistence, backups,
maintenance windows, authentication/TLS, CA management, encryption at
rest, and Private Service Connect (PSC) networking in either a
single-project or cross-project (host/consumer) topology.

## Files

| File | Contents |
|---|---|
| `provider.tf` | Terraform/provider version pinning, single `google` provider |
| `variables.tf` | All input variables, with validation and cross-field `check` blocks |
| `data.tf` | Region/zone lookups, project data sources |
| `locals.tf` | Derived values (effective zone, effective consumer project, precondition helpers) |
| `main.tf` | The `google_memorystore_instance` resource |
| `psc_network.tf` | Networking — AUTO and USER PSC connectivity modes |
| `output.tf` | Instance identity and connection info |
| `test.tfvars` | Example tfvars for a cross-project USER-mode test deployment |

## Architecture: PSC Connectivity Modes

Memorystore instances are not directly inside your VPC. They sit in a
Google-managed producer network and connect to your VPC(s) via **Private
Service Connect (PSC)**. This module supports two ways to establish that
connection, switched by `var.psc_connectivity_mode`:

### AUTO mode

Memorystore creates the forwarding rule/endpoint for you, inside one
consumer VPC that this module creates. Requires a **Service Connection
Policy** authorizing the connection. Best for: single app, single VPC,
same or different project than the instance.

```
consumer_project_id
  └── VPC (created by this module)
        └── Service Connection Policy: "allow gcp-memorystore PSC here"
        └── PSC endpoint (auto-created by Memorystore)
                    │  PSC connection
                    ▼
project_id (host)
  └── google_memorystore_instance
```

### USER mode

You (this module) create the forwarding rule(s) yourself and explicitly
register them with the instance. No Service Connection Policy is
involved — you're wiring the connection directly instead of asking
Memorystore to automate it. Required when:
- The app's VPC lives in a **different project** than the instance
  (the common "host project owns Valkey, app projects consume it"
  pattern), or
- **Multiple separate VPCs** need to reach the same instance.

```
project_id (host)
  └── google_memorystore_instance (created WITHOUT endpoint config)
        → exposes a service attachment once created

consumer_project_id (one entry per key in var.user_networks)
  └── VPC + subnet
  └── Reserved internal IP (purpose = GCE_ENDPOINT)
  └── Forwarding rule (target = instance's service attachment)
        → this IS the PSC endpoint; connection starts PENDING

project_id (host) — registration step
  └── google_memorystore_instance_desired_user_created_endpoints
        → registers the forwarding rule; connection flips to ACTIVE
```

> **Naming note:** resource names like `auto_producer_net` are inherited
> from Google's own example naming and are misleading — the network you
> see in Terraform is **always your consumer-side VPC**, never Google's
> actual producer infrastructure. "Producer"/"consumer" refers to *who
> provides the service* (Google), not which side owns the Terraform
> resource.

### Which mode fits your scenario?

| Scenario | Mode |
|---|---|
| One app, one VPC, same project as instance | AUTO |
| One app, one VPC, **different project** than instance (host/consumer split) | USER |
| Multiple VPCs / multiple app projects consuming one shared instance | USER |

## ⚠️ USER mode requires a two-phase apply on first creation

The forwarding rule needs the instance's service attachment as its
target, but that attachment only exists once the instance itself is
created. On a from-scratch `apply`:

```bash
terraform apply -target=google_memorystore_instance.shared-instance -var-file=test.tfvars
terraform apply -var-file=test.tfvars
```

This mirrors Google's own USER-mode tutorials, which describe the same
create-instance-first, register-connection-second sequence via `gcloud`.
It is inherent to the mechanism, not a gap in this module.

## Prerequisites (outside Terraform)

**APIs enabled:**
- Host project (`project_id`): `memorystore.googleapis.com`
- Consumer project (`consumer_project_id`): `compute.googleapis.com`,
  `networkconnectivity.googleapis.com` (AUTO mode only)

**IAM**, for whoever runs `terraform apply`:
- Host project: `roles/memorystore.admin` (or equivalent)
- Consumer project: `roles/compute.networkAdmin`, and (AUTO mode)
  `roles/networkconnectivity.serviceConnectionPolicyAdmin`

If using `CUSTOMER_MANAGED_CA` or `CUSTOMER_MANAGED` (CMEK) encryption,
Memorystore's service agent
(`service-PROJECT_NUMBER@cloud-memorystore.iam.gserviceaccount.com`)
also needs `roles/privateca.certificateRequester` on your CA pool, or
`roles/cloudkms.cryptoKeyEncrypterDecrypter` on your KMS key,
respectively. These IAM bindings are **not included** in this module —
add them alongside if you use those features.

## Usage

```bash
terraform init
terraform validate
terraform plan  -var-file=test.tfvars
terraform apply -target=google_memorystore_instance.shared-instance -var-file=test.tfvars  # USER mode first pass only
terraform apply -var-file=test.tfvars
```

## Key variables

See `variables.tf` for the full list with descriptions and validation.
Notable ones:

| Variable | Purpose |
|---|---|
| `project_id` | Host project (required, no default) |
| `consumer_project_id` | Consumer project (optional; defaults to `project_id`) |
| `psc_connectivity_mode` | `AUTO` or `USER` |
| `user_networks` | Map of consumer VPCs to wire up in `USER` mode |
| `persistence_mode` | `RDB`, `AOF`, or `DISABLED` |
| `automated_backup_enabled` | GCS-backed backup collection, separate from persistence |
| `authorization_mode` / `transit_encryption_mode` | AUTH + TLS — see cross-field `check` blocks enforcing IAM_AUTH requires TLS |
| `server_ca_mode` / `server_ca_pool` | CA management — per-instance, shared, or customer-managed |
| `encryption_type` / `kms_key` | Encryption at rest (CMEK) |
| `deletion_protection_enabled` | Defaults to `true` — set `false` explicitly for disposable test instances |

## USER mode resource shape (confirmed via provider error output)

`google_memorystore_instance_desired_user_created_endpoints` nests three
levels of blocks, all using standard `dynamic` block syntax — no unusual
object-attribute syntax involved (an earlier draft of this module guessed
otherwise, based on a Pulumi bridge-provider sample that turned out not
to reflect the real `hashicorp/google` schema; the live `terraform plan`
error was the actual source of truth here):

```hcl
resource "google_memorystore_instance_desired_user_created_endpoints" "x" {
  name    = "..."
  region  = "..."
  project = "..."

  desired_user_created_endpoints {   # one per consumer network
    connections {                    # one per service attachment reachable from that network
      psc_connection {                # nested block, not an attribute
        psc_connection_id  = "..."
        ip_address          = "..."
        forwarding_rule     = "..."
        network             = "..."
        service_attachment  = "..."
      }
    }
  }
}
```

The forwarding rule's `target` — and `psc_connection.service_attachment`
above — both come from `google_memorystore_instance.shared-instance.psc_attachment_details[N].service_attachment`,
a flat computed list directly on the instance. An instance can expose
**multiple** service attachments (e.g. discovery + one per shard/replica);
this module creates one reserved IP + forwarding rule per
(consumer network × attachment) pair to cover all of them, keyed as
`"<network-key>-<attachment-index>"` in `psc_network.tf` and in this
module's outputs.

## Known caveats — verify before production use

- **`server_ca_mode` enum casing**: this field was added recently to the
  provider; confirm exact values via `terraform providers schema -json`
  before relying on it.
- **This module does not create a secondary (cross-region DR) instance.**
  See prior design discussion if you need `PRIMARY`/`SECONDARY`
  cross-region replication — that's a separate, larger addition (second
  instance resource + its own network trio + `instance_role` /
  `primary_instance` wiring).
- **CA/KMS service-agent IAM bindings are not included** — see
  Prerequisites above.

## Testing this module

`test.tfvars` deploys the smallest valid configuration for your actual
target topology (USER mode, host project `valkeyhubhost-500604`,
consumer project `serviceproj1-500604`): single shard, no replicas, no
persistence, no backups, auth disabled — enough to validate the
connectivity plumbing works without exercising every feature at once.
Once that succeeds, layer on persistence/backups/auth/CA/CMEK
incrementally rather than enabling everything in one pass.