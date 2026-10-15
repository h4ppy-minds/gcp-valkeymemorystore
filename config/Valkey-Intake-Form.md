# Memorystore for Valkey – Intake Form

Please fill in every blank. Pick one value where options are listed. Leave a row blank if you don't know; the platform team will follow up.

> **Note:** Every instance uses **IAM authentication** and **TLS**. Your app must support both.

---

## 1. Purpose

| Question | Answer |
| --- | --- |
| What will Valkey be used for? (cache, session store, rate limiting, queue, other) | |
| Is this a new onboarding or a migration from Memorystore for Redis? | |

---

## 2. Migration from Memorystore for Redis

*Skip this section if this is a new onboarding.*

**Existing Redis instance**

| Field | Dev | QA | UAT | Prod |
| --- | --- | --- | --- | --- |
| Instance name | | | | |
| GCP project ID | | | | |
| Region | | | | |
| SKU / tier (Basic / Standard / Redis Cluster) | | | | |
| Size (GB) | | | | |
| Shards | | | | |
| Replicas | | | | |
| Topology (Standalone / HA / DR) | | | | |
| Redis version | | | | |

**Target Valkey instance**

| Field | Dev | QA | UAT | Prod |
| --- | --- | --- | --- | --- |
| Instance name (lowercase, hyphens, no env suffix) | | | | |
| Region | | | | |
| SKU / node type (platform can recommend) | | | | |
| Shards | | | | |
| Replicas | | | | |
| Topology (Standalone / HA / DR) | | | | |

**Migration plan**

| Question | Answer |
| --- | --- |
| Migration method (rebuild from source / dual-write / backup & restore) | |
| Can data be rebuilt if lost? (Y/N) | |
| Acceptable cutover downtime | |
| Target cutover date | |
| Redis decommission date | |

---

## 3. Application Ownership

| Field | Answer |
| --- | --- |
| Application name | |
| Application ID | |
| Line of business / cost center | |
| Business owner (name, email) | |
| Tech support lead (name, email) | |
| Support team | |
| ADO project / support group | |
| Alert email(s) (distribution list preferred) | |

---

## 4. Required Environments

| Environment | Needed? (Y/N) | Go-live date |
| --- | --- | --- |
| Dev | | |
| QA | | |
| UAT | | |
| Prod | | |

---

## 5. App Criticality

| Field | Answer |
| --- | --- |
| App tier (Tier 0 / 1 / 2 / 3) | |
| RTO (max downtime) | |
| RPO (max data loss) | |
| Is Valkey the only copy of the data? (Y/N) | |

---

## 6. Availability Requirements

| Field | Dev | QA | UAT | Prod |
| --- | --- | --- | --- | --- |
| Topology (Standalone / HA / DR) | | | | |
| Primary region | | | | |
| Secondary region (DR only) | | | | |
| Preferred maintenance window (day + hour UTC) | | | | |

*Standalone = no failover (dev/test). HA = automatic failover in one region. DR = HA plus a copy in a second region.*

---

## 7. Sizing & Capacity

| Field | Dev | QA | UAT | Prod |
| --- | --- | --- | --- | --- |
| Current dataset size (GB) | | | | |
| Projected size in 1 year (GB) | | | | |
| Projected size in 2 years (GB) | | | | |
| Peak recorded client connections | | | | |
| Peak operations/sec | | | | |
| Do keys have TTLs? (Y/N) | | | | |

---

## 8. Network Connectivity

Where will the clients connect from?

| Location | Needed? (Y/N) | Subnet / VNet / CIDR | Environments |
| --- | --- | --- | --- |
| GCP 3.0 | | | |
| Azure 3.0 | | | |
| On-prem LDC | | | |
| On-prem SDC | | | |

---

## 9. Security & Authentication

**IAM**

| Field | Dev | QA | UAT | Prod |
| --- | --- | --- | --- | --- |
| Service account(s) that will connect | | | | |
| Group needing read-only access | | | | |

**Certificate (TLS)**

| Field | Answer |
| --- | --- |
| CA mode (Per-instance CA *(default)* / Shared regional CA / Customer-managed CA) | |
| CA pool resource ID (Customer-managed CA only) | |
| Where the app stores the CA cert (Vault, Secret Manager, other) | |

**Encryption at rest**

| Field | Answer |
| --- | --- |
| Encryption (Google-managed *(default)* / Customer-managed key) | |
| KMS key resource ID (customer-managed only) | |
| Data classification (Internal / Confidential / PHI / PCI) | |

---

## 10. Client Integration

| Field | Answer |
| --- | --- |
| Language & version | |
| Redis/Valkey client library & version | |
| Supports Redis Cluster mode? (Y/N) | |
| Supports TLS + IAM token auth? (Y/N) | |
| Uses Lua, pub/sub, transactions, or multi-key commands? | |

---

## 11. Connection Model

Mark one with **X**.

| Model | Select |
| --- | --- |
| Single app / team | |
| Multiple apps, one team | |
| Multiple teams | |
| Shared enterprise service | |

If you didn't pick "Single app / team", list each consuming app:

| App | Owner team | Service account |
| --- | --- | --- |
| | | |

---

## 12. Data & Operations

| Field | Answer |
| --- | --- |
| Persistence (None / Snapshots every 1, 6, 12 or 24 hrs / Every-second log) | |
| Daily backups needed? (Y/N) | |
| Eviction when full (evict keys with TTL *(default)* / evict any key / reject writes) | |
| Deletion protection for Prod? (Y/N, recommended Y) | |

---

## 13. Sign-off

| Role | Name | Date |
| --- | --- | --- |
| Business owner | | |
| Tech lead | | |
