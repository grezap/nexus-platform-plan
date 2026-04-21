# tenantcore — Schemas

## Ownership

| Store | Database / schema | Role |
|---|---|---|
| Percona MySQL PXC | `tc_system` | Global control plane — tenants, plans, features |
| Percona MySQL PXC | `tc_{tenantId}` (per tenant) | Per-tenant isolated schema, created dynamically |
| Redis Cluster | — | Per-tenant rate limiting, feature flag cache |

**Migration tool:** FluentMigrator with **multi-schema profile** — control-plane migrations target `tc_system`; tenant migrations replay against every `tc_*` schema via `ITenantSchemaProvisioner`.
**Status:** DDL planned, authoring begins in Phase 2.

## `tc_system` — global control plane

| Table | Description |
|---|---|
| `Tenants` | Root tenant record: Id, Name, Subdomain, Status, PlanId, created_utc, suspended_at. |
| `Plans` | Subscription plans (Free, Team, Business, Enterprise) with limits. |
| `Features` | Feature catalog — stable keys for OpenFeature (E17). |
| `PlanFeatures` | M:N — which features are included in each plan. |
| `TenantFeatureOverrides` | Per-tenant feature toggles (temporary grants, trials). |
| `Subscriptions` | Active subscription record per tenant; billing cycle, renewal date. |
| `BillingInvoices` | Issued invoices; external payment gateway ref. |
| `Users` | Global user directory; can be member of multiple tenants. |
| `TenantMemberships` | User ↔ tenant with roles. |
| `Roles` | System + tenant-scoped roles. |
| `Permissions` | Normalized permission keys. |
| `RolePermissions` | M:N role → permission. |
| `ApiKeys` | Tenant-scoped API keys with rotation metadata. |
| `AuditLog` | Cross-tenant administrative events (tenant created, plan changed, etc.). |
| `BackgroundJobs` | Hangfire state — `JobQueue`, `HashSet`, `Set`, `State`, `Schema` tables per Hangfire.MySqlStorage. |

## `tc_{tenantId}` — per-tenant schema (provisioned on tenant creation)

| Table | Description |
|---|---|
| `Projects` | Business domain entity. |
| `ProjectMembers` | Access within the tenant. |
| `Tasks` | Unit-of-work records with status machine. |
| `Comments` | Threaded comments on tasks. |
| `Attachments` | File metadata (blobs in object store). |
| `Activities` | Per-tenant activity feed — source for SignalR. |
| `Webhooks` | Tenant-registered outbound webhook endpoints. |
| `WebhookDeliveries` | Delivery attempts + retry state. |
| `UsageMetrics` | Daily counters — API calls, storage bytes, users. Used for plan enforcement. |
| `AuditLog` | Tenant-scoped audit trail. |
| `OutboxMessages` | MassTransit Outbox — per-tenant schema isolation. |

## Advanced SQL artifacts required (E28)

- Recursive CTE for role hierarchy resolution.
- Window function computing per-tenant daily-active-user trend.
- Dynamic SQL in `ITenantSchemaProvisioner` to create `tc_{tenantId}` schemas atomically.
- MERGE for idempotent tenant upsert during onboarding saga.
