# ADR-0037 — StarRocks shared-data tier: 3 FE + 2 CN on `run_mode=shared_data`, internal tables in a MinIO storage volume

- **Status:** accepted
- **Date:** 2026-05-26
- **Phase:** 0.L.5 (`nexus-infra-analytics`, tier `04-analytics` — extends the sealed shared-nothing cluster)
- **Amends:** [ADR-0030](./ADR-0030-starrocks-fe-quorum-be-tablet-sharding.md) (the shared-nothing topology)
- **Relates to:** [ADR-0033](./ADR-0033-minio-distributed-erasure-coded-object-storage.md) (the S3 storage backend), [ADR-0031](./ADR-0031-analytics-client-front-door-round-robin-dns.md) (round-robin DNS front door, no VIP), [ADR-0025](./ADR-0025-ha-promise-covers-lb-tier.md) (HA covers the LB tier)

## Context

ADR-0030 sealed a shared-NOTHING StarRocks cluster (3 FE BDB-JE quorum + 3 BE; tablets `DISTRIBUTED BY HASH BUCKETS 6` × `replication_num=3`). At 0.G.6 close-out (2026-05-23) the CN / shared-data tier was deferred to 0.L because it depends on object storage — which only becomes available at 0.L.1 (MinIO 4-node EC, ADR-0033).

The portfolio's value is showcasing **both** StarRocks deployment models — the shared-nothing tablet-replication path (sealed) and the shared-data compute-storage-separation path (this ADR). They are mutually exclusive *within a single cluster* (StarRocks does not support mixing `run_mode` post-deploy), so the shared-data tier is built as a **separate cluster** running in parallel with the sealed one. Both clusters share the analytics tier's network, Vault, and DNS canon; nothing else.

Three either/or decisions were taken with Greg (2026-05-26):

- **MinIO identity = dedicated `nexus-starrocks-app`** service account scoped to a new `starrocks` bucket (not a reuse of `nexus-lakehouse-app`). Tighter least-privilege than the Harbor precedent at the cost of one extra cross-tier seed.
- **Templates = two new dedicated Packer templates** (`analytics-starrocks-sd-fe-node` + `analytics-starrocks-sd-cn-node`), not a reuse of the sealed `analytics-starrocks-fe-node`/`-be-node`. Full isolation per the per-cluster-state + per-engine-template canon — a change to either cluster's templates can never rebake/break the other.
- **Smoke = chaos by default.** The headline shared-data HA property is "any CN serves from shared storage; the data plane is stateless." The default `smoke-0.L.5.ps1` exercises this every run (kill 1 CN, prove the query still returns full results; kill FE leader, prove re-election) — not opt-in via `-IncludeChaos` as in 0.G.6's smoke.

## Decision

Deploy a **second, parallel StarRocks cluster in `run_mode = shared_data`: 3 FE (BDB-JE quorum, 1 leader + 2 followers) + 2 stateless Compute Nodes**, with all internal tables stored in a **MinIO storage volume** (`s3://starrocks/`) created via SQL after FE bootstrap. The cluster shares no on-host state with the sealed shared-nothing one and never touches its data.

### Topology

- **FE quorum (3 nodes; `sr-sd-fe-1/2/3` at `.37/.38/.39`, 3 GB each):** `fe.conf` carries `run_mode = shared_data` + `cloud_native_meta_port = 6090` + per-host `priority_networks = 192.168.10.0/24` + JVM heap. Bootstrap follows the sealed pattern — leader first (empty meta → becomes Leader), then each follower joined via `ALTER SYSTEM ADD FOLLOWER <b10>:9010` on the leader followed by a `--helper` one-shot start that persists BDB-JE meta, then systemd handover. **NB:** `cloud_native_storage_type` + the `aws_s3_*` keys are **deliberately omitted** from `fe.conf` — the storage volume is created via SQL after bootstrap (cleaner separation, supports `aws.s3.enable_path_style_access`, no plaintext S3 secret on disk in the FE conf, change-volume without rebaking the FE).
- **CN data plane (2 nodes; `sr-sd-cn-1/2` at `.30/.40`, 4 GB each):** `cn.conf` carries `priority_networks` + `storage_root_path = /opt/starrocks/be/storage` (local datacache, not durable storage — the durability is the storage volume). Started via `/opt/starrocks/be/bin/start_cn.sh` (the StarRocks tarball includes the CN binary alongside BE under `be/bin/`; CN config goes in `be/conf/cn.conf`). Registered with `ALTER SYSTEM ADD COMPUTE NODE "<b10>:9050"` on the FE leader.
- **Front door = round-robin DNS** (ADR-0031): `starrocks-sd-fe.nexus.lab → .37 / .38 / .39`. No VIP — StarRocks clients (MySQL protocol) and any compatible BI/JDBC tool rotate across the A records; one FE down still leaves quorum + two front-door endpoints.

### Storage volume

After FE quorum is healthy and the 2 CN are registered + alive, the schema-bootstrap overlay creates the storage volume via SQL on the FE leader:

```sql
CREATE STORAGE VOLUME nexus_minio_starrocks
TYPE = S3
LOCATIONS = ('s3://starrocks/')
PROPERTIES (
  "enabled"                              = "true",
  "aws.s3.endpoint"                      = "https://minio.nexus.lab:9000",
  "aws.s3.region"                        = "us-east-1",
  "aws.s3.access_key"                    = "<from Vault KV nexus/analytics/starrocks-sd/s3-access-key>",
  "aws.s3.secret_key"                    = "<from Vault KV nexus/analytics/starrocks-sd/s3-secret-key>",
  "aws.s3.enable_path_style_access"      = "true",
  "aws.s3.use_aws_sdk_default_behavior"  = "false",
  "aws.s3.use_instance_profile"          = "false"
);
SET nexus_minio_starrocks AS DEFAULT STORAGE VOLUME;
```

Then `CREATE TABLE nexus.events (...)` as a cloud-native table (no `replication_num` — durability is the MinIO EC backend, not StarRocks-level replication). The exit gate proves the data actually lives in MinIO (mc-side listing under `s3://starrocks/` shows objects), the table is queryable from both CN (`USE WAREHOUSE` round-robin across CN), and CN loss is survivable.

### MinIO tenant (dedicated identity, lakehouse repo)

A new overlay in `nexus-infra-lakehouse/terraform/envs/lakehouse-minio/role-overlay-minio-starrocks-tenant.tf` runs alongside the existing `role-overlay-minio-bucket-bootstrap.tf` exit gate:

- Bucket `starrocks` (path-style; data layout `s3://starrocks/<storage-volume-internal-tree>`).
- MinIO service account `nexus-starrocks-app` with KV-seeded access/secret (in `nexus/analytics/starrocks-sd/s3-*`, field `value`).
- A scoped policy `starrocks-tenant` granting `s3:*` only on `arn:aws:s3:::starrocks/*` + listing on the bucket; attached to the `nexus-starrocks-app` user. (Not the global `readwrite` policy reused by Harbor for the lakehouse-app key — that is the explicit tightening Greg chose.)

### mTLS, identity, KV

- **PKI role `starrocks-sd-server`** (new, separate from the sealed `starrocks-server`): `allowed_domains` covers the 5 new hosts + `starrocks-sd-fe.nexus.lab` + the sealed `starrocks.nexus.lab` aliases left untouched. Per-host leaf certs at apply time via `nexus-infra-analytics/terraform/envs/analytics-starrocks-sd/role-overlay-starrocks-sd-tls.tf` (PKCS#8 private key, server+client EKU, 90-day TTL).
- **5 per-host AppRoles** + 5 narrow policies (PKI issue on `pki_int/issue/starrocks-sd-server`, KV read on `nexus/data/analytics/starrocks-sd/*`, token self).
- **Sticky-seeded KV creds** at `nexus/analytics/starrocks-sd/{root-password,app-password,s3-access-key,s3-secret-key}` (root/app field `password`; S3 access/secret field `value`).

### MinIO CA trust on the StarRocks nodes

The MinIO endpoint is TLS-only (`https://minio.nexus.lab:9000`) so the StarRocks nodes must trust the Vault CA when reaching it:

- **FE (Java)** — the storage-volume validation runs in the AWS Java SDK; the install task imports the Vault CA bundle into the JDK truststore (`$JAVA_HOME/lib/security/cacerts` via `keytool`, idempotent — re-import is a no-op via alias check).
- **CN (C++)** — the data I/O path uses the AWS C++ SDK which reads the system CA bundle; the install task copies the Vault CA into `/usr/local/share/ca-certificates/nexus-vault-ca.crt` and runs `update-ca-certificates`.

Both paths land in the per-engine Packer templates (the Vault CA bundle is fetched from `/etc/vault-agent/ca-bundle.crt` on the running node, post-firstboot), so a cold rebuild trusts MinIO on first boot.

### What this cluster does NOT do

- **No `replication_num` on cloud-native tables.** Durability is the MinIO EC backend; setting it has no effect in shared-data mode.
- **No NFS backup repo.** Backups are S3 → S3 (StarRocks SNAPSHOT to the storage volume or to a second bucket); the analytics tier's NFS export (ADR-0032) is not extended to the sd cluster.
- **No mixing with the shared-nothing cluster.** They are wholly separate clusters; no client SQL touches both. Tables created in either cluster are visible only there.

## Consequences

- **Showcase covers both StarRocks deployment models** without contaminating the sealed shared-nothing cluster — recruiters/reviewers can see tablet-replication-HA and storage-compute-separation side by side.
- **5 new VMs, 4 new Vault objects** (1 PKI role + 5 AppRoles+policies + 1 KV namespace + 1 MinIO tenant), 1 new MinIO bucket. Fleet grows from 88 to 93 built.
- **The MinIO tier is exercised harder.** The shared-data cluster pushes every internal table write to MinIO synchronously; this is the first 0.L tier to make MinIO a *transactional* hot path (lakehouse Iceberg + Spark writes are batch-y). Failure modes new to this tier: MinIO unreachable → all writes block; MinIO endpoint cert expiry → FE storage-volume validation fails → no new tables. The smoke and the handbook §3 transient chronology will codify both.
- **CN-2 spilled to `.40`** (first free ClickHouse-decade slot) because SR decade `.3x` only had 4 free slots (`.30/.37/.38/.39`) and Greg's full-HA spec needs 5. Documented in `network.md`; future nexusdesk-dev planned for `.150` is unaffected.
- **The handbook §1 walkthrough for analytics now has two clusters.** Operator must know which one to power up for a given task; the handbook playbook spells it out + the smoke gates make `0.G.6` vs `0.L.5` self-evident.
