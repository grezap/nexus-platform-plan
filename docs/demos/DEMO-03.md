# DEMO-03 · Onboard a new SaaS tenant

## 1. What this shows

A new tenant record in `tenantcore` triggers creation of a tenant-scoped schema on Percona PXC, seeded role/permission rows, a Vault AppRole, Kafka ACLs on the tenant's topic prefix, and an Unleash feature-flag default set — all within 20 seconds. Target persona: CTO evaluating multi-tenancy hygiene.

## 2. Runtime + prerequisites

- **Environment target** — `saas`
- **VMs required** — dc-nexus, vault-1/2/3, pxc-node-1/2/3, proxysql-1/2, kafka-east-1/2/3, unleash-1, swarm-manager-1, obs-*
- **External services** — ProxySQL VIP, Vault path `nexus/tenants/*`, Kafka ACL API, Unleash API
- **Seed data** — none; demo creates a net-new tenant
- **Expected duration** — 4 min
- **Reset command** — `nexus-cli demo run DEMO-03 --reset` drops the tenant schema and Vault role.

## 3. Architecture snapshot

*Filled in when the project ships.*

## 4. Step-by-step script

- POST `/tenants` with name and plan.
- Hangfire job schema-bootstraps the tenant on PXC (12 tables).
- Vault AppRole + KV secret mount `nexus/tenants/{id}/*` created.
- Kafka ACL grants tenant principal READ/WRITE on `tenant.{id}.*`.
- Unleash project + default flags provisioned.
- Tenant admin user receives initial credentials via email transport stub.
- CLI prints timings per sub-step.

## 5. Observability trail

- **Grafana** — dashboard `tenantcore-ops` · panel `tenant creations / hour`
- **Jaeger** — service `tenantcore`; trace shows 6 child spans (schema, vault, kafka-acl, unleash, user, email)
- **Seq** — query `TenantId = '{new-id}'`
- **URLs** — `http://obs-metrics.nexus.local:3000/d/tenantcore-ops`

## 6. Code pointers

*Filled in when the project ships.*

## 7. Variations

*Filled in when the project ships.*

## 8. Troubleshooting

*Filled in when the project ships.*

## 9. What this proves

- **.NET engineering + architecture** — Clean Architecture, saga-style orchestration, idempotent Hangfire jobs.
- **Advanced SQL + analytics** — per-tenant schema fan-out via dynamic SQL, MERGE for role provisioning, recursive CTEs for feature inheritance.
- **Python** — load test generator to provision 100 tenants for benchmarking.
- **DevOps** — Vault dynamic secret lifecycle, Kafka ACL governance, feature-flag-driven rollout.
