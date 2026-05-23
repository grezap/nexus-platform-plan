# ADR-0033 — Lakehouse object storage: MinIO distributed erasure-coded cluster

- **Status:** accepted
- **Date:** 2026-05-23
- **Phase:** 0.L.1 (`nexus-infra-lakehouse`, tier `08-spark`)
- **Supersedes:** the "MinIO/S3 migration deferred to 0.L" note in [ADR-0032](./ADR-0032-analytics-backup-repository-nfs-gateway.md)

## Context

Phase 0.L stands up the lakehouse tier. Apache Iceberg (0.L.2), Apache Spark
(0.L.3), and the StarRocks shared-data/CN tier (0.L.5) all require an
S3-compatible object store for warehouse data + storage volumes; ADR-0032
explicitly deferred that object store to 0.L. The platform is an HA showcase, so
the storage foundation that every lakehouse component sits on must itself be
node-fault-tolerant — a single-node object store would be a tier-wide SPOF.

## Decision

Deploy **MinIO in distributed erasure-coded mode across 4 dedicated nodes**
(`minio-1..4`, `.141`–`.144`).

- **Erasure set:** each node has a dedicated xfs data drive (a 2nd VMDK,
  label `minio-data`, `/mnt/minio/data`); the set spans all 4 drives
  (`MINIO_VOLUMES=https://192.168.10.{141...144}:9000/mnt/minio/data`). Default
  parity EC:2 → tolerates 1 node down read-write, 2 nodes down read-only (write
  quorum 3/4). A dedicated drive (not a directory on root) is required —
  distributed MinIO refuses a root-filesystem path.
- **Backplane/service split:** inter-node erasure/heal/lock traffic uses the
  VMnet10 backplane (the raw `192.168.10.x` IPs in `MINIO_VOLUMES`); the client
  S3 API (`:9000`) and Console (`:9001`) are served on VMnet11.
- **No VIP — round-robin DNS** (`minio.nexus.lab` → the 4 nodes), the same
  client-side-multi-endpoint pattern as the analytics tier ([ADR-0031](./ADR-0031-analytics-client-front-door-round-robin-dns.md)).
  Every node is an equal S3 entry point, so there is no fixed endpoint SPOF.
- **mTLS** via per-host Vault PKI (`minio-server` role); each leaf carries
  `minio.nexus.lab` + the node names + both the VMnet11 and VMnet10 IPs in its
  SANs (peers validate over the backplane IP, clients over the round-robin name).
  Files in MinIO's layout: `certs/public.crt`, `certs/private.key` (PKCS#8),
  `certs/CAs/nexus-ca.crt` (so each node trusts its 3 peers).
- **Credentials** sticky-seeded in Vault KV (`nexus/lakehouse/minio/*`, field
  `value`): root user/password + the least-priv `nexus-lakehouse-app` service
  account consumed by 0.L.2 (Iceberg) and 0.L.3 (Spark).
- **Buckets** created at bootstrap: `warehouse` (Iceberg), `spark-events`
  (Spark history), `lakehouse` (medallion bronze/silver/gold root).

RAM right-sized to 2 GB/node ([feedback_prefer_less_memory]); production reverts
to 8–16 GB.

## Consequences

- The lakehouse is **self-contained** — combined with the dedicated catalog PG
  (ADR-0034), it has no dependency on the OLTP tier.
- MinIO must be running for 0.L.2/0.L.3/0.L.5; per minimal-running-VMs the four
  MinIO VMs stay up across the lakehouse sub-phases and are stopped only when the
  tier is idle (cold-rebuild-proven, power back on + smoke when needed).
- **Cold-rebuild proven 2026-05-23** (destroy → from-zero apply → `smoke-0.L.1.ps1`
  ALL GREEN). Two apply-time transients fixed in source (handbook §3):
  the dedicated 2nd VMDK required a multi-disk preseed fix; the VMnet10
  `ethernet1` NO-CARRIER flake is auto-recovered zero-touch in the config overlay
  (`vmrun connectNamedDevice`).

## Alternatives considered

- **Single-node MinIO (SNSD/SNMD):** simplest, but a tier-wide SPOF — rejected
  for an HA showcase.
- **Directory on the root filesystem instead of a dedicated drive:** distributed
  MinIO refuses a root-filesystem path; rejected.
- **VRRP VIP front door:** unnecessary — every node is an equal S3 endpoint, so
  round-robin DNS suffices (consistent with ADR-0031).
