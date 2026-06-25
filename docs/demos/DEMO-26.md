# DEMO-26 · Drive the lakehouse tier from the CLI — one tool over three engines (MinIO + Iceberg/Nessie + Spark + ZooKeeper)

## 1. What this shows

The Phase-0.L lakehouse plane — a **distributed MinIO** erasure-coded object store, an **Apache Iceberg REST
catalog (Project Nessie)** backed by a dedicated **PostgreSQL 17 streaming-replication** pair, and **Apache
Spark standalone HA** (two ZooKeeper-elected masters + three workers), all coordinated by a **3-node Apache
ZooKeeper** ensemble — is now a single first-class `nexus-cli` cluster (ClusterId `lakehouse`, nexus-cli
v0.8.4). It is the **fourth non-data-tier adapter** (after v0.8.1 Vault/foundation-ad, v0.8.2 Swarm, v0.8.3
Observability) and the last big multi-component one.

The headline is that **one component-aware adapter** spans all three engines + ZooKeeper: the operator runs
`nexus status lakehouse` and gets one rolled-up table over all 16 VMs; `nexus health lakehouse` probes every
engine's real signal path in one report. Internally the adapter classifies each node by name-prefix
(`minio-` / `iceberg-rest-` / `iceberg-pg-` / `spark-master-` / `spark-worker-` / `zookeeper-`) and dispatches
the right probe per component. There is **no managed MinIO / Spark / Iceberg / Nessie driver** (NetArchTest-
enforced) — every probe is an SSH shell-out to the node's own CLIs/HTTP, MinIO admin goes through the on-node
`mc nexuslocal` alias, and runtime creds come from Vault KV (every lakehouse secret field is `value`).

The access posture matches the observability tier (decided by diagnosing the live contract first): service
endpoints are probed **over SSH with each node's own `ca`** — Nessie's management `/q/health` and the Spark
master/worker UIs are plain HTTP, MinIO's `/minio/health/*` is HTTPS validated against the node's own CA bundle.

An operator drives the whole tier from one tool: observe the rolled-up state, prove every engine's signal path
(MinIO erasure-set health, the Nessie object-store + catalog, the Spark ALIVE master + its workers, the
ZooKeeper quorum, the iceberg-pg streaming replication), read the topology, fail the **Spark master** over to
its standby (ZooKeeper auto-promotes it), rotate certs (MinIO big-bang to preserve distributed mTLS), list and
edit MinIO policies, inject chaos on a MinIO node (the EC:2 set tolerates one node loss), and round-trip the
warehouse bucket through `mc mirror`.

Personas: **data platform engineer** (one tool to verify the whole lakehouse signal chain + the Spark HA
failover drill), **SRE** (panic-button verbs — the same surface as every data tier), **security engineer**
(creds never leave Vault KV; the adapter trusts each node's own CA; no managed driver; the catalog-DB failover
is honestly refused as a DR runbook rather than silently doing something unsafe).

## 2. Runtime + prerequisites

- **Environment target** — the 16-VM lakehouse tier (Phase 0.L) on the always-on foundation base.
- **VMs required** — the 16 lakehouse nodes (cluster `lakehouse` in [`docs/infra/vms.yaml`](../infra/vms.yaml))
  + the iceberg-db VRRP VIP `.151`. MinIO + ZooKeeper must be up before Spark (the masters need both).
- **Env vars** — `VAULT_ADDR` · `VAULT_TOKEN` · `VAULT_CACERT` (to read the MinIO root credential from Vault KV
  for `mc`/`acl` — every lakehouse secret field is `value`) · `NEXUS_SSH_KEY` · `NEXUS_VMS_YAML`. (`scratch/nx.ps1`
  in `nexus-cli` sets these.)
- **Seed data** — none; creds are read from Vault KV and each node's `ca` is read on the node over SSH.
- **Expected duration** — 5–8 min wall-clock (the Spark master failover ≈ 30 s + the cert-rotate dominate).
- **Reset command** — none needed; the Spark failover auto-recovers (the old leader restarts as the new
  standby), chaos recovers to green, and `backup` is a read-only round-trip. `failover --direction iceberg-pg`
  is intentionally NOT exercised — the verb refuses it (a VRRP cutover of the catalog-DB pair split-brains it).

## 3. Architecture snapshot

16 VMs carry the lakehouse: **minio-1/2/3/4** form a distributed erasure-coded (EC:2) S3 object store (RR DNS
`minio.nexus.lab`, no VIP) — and that same store is the durability backend for four tiers (the lakehouse
`warehouse` bucket, plus observability `loki`/`tempo`, registry `harbor`, analytics `starrocks`). **iceberg-rest-1/2**
run Project Nessie as the Iceberg REST catalog (RR DNS), backed by **iceberg-pg-1/2** — a PG17 streaming pair
behind a keepalived VRRP VIP `.151` (`iceberg-db.nexus.lab`). **spark-master-1/2** are ZooKeeper-elected
standalone masters (one ALIVE, one STANDBY; master URL `spark://…:7077,…:7077`), with **spark-worker-1/2/3**
and a **zookeeper-1/2/3** ensemble that holds the Spark master-HA election state. Spark's RPC is shared-secret
+ AES (not cert TLS); its only on-node trust material is the JVM truststore CA. ZooKeeper is backplane-only
plaintext (ADR-0035). The write path is **Spark → Nessie (Iceberg REST) → MinIO (`s3a://warehouse`, Parquet)**.

## 4. The greenfield reality this tier was found in (and how the CLI handled it honestly)

The lakehouse was offline during the v0.8.1 Vault greenfield, so it carried the **same casualty class the
observability tier hit**: MinIO had already been re-certed to the new Vault root (in the v0.8.3 session) but
Nessie/iceberg-pg/Spark/ZooKeeper were **still old-root** — a **cross-tier CA split** (old-root Nessie's JVM
truststore couldn't validate the new-root MinIO S3 leaf → `PKIX path validation failed`) plus an **iceberg-pg
replication split**. The adapter diagnosed both first and **reported them honestly RED** in `health` (it never
papered over them), and 11 verbs verified green against the as-is tier.

The repair was a Greg-authorized **cold-rebuild of the Iceberg + Spark envs only** — MinIO was deliberately
kept in place, because reformatting its EC drives would have wiped the four cross-tier buckets it serves. The
fresh new-root Iceberg/Spark certs trust the live new-root MinIO, so the CA split + the pg split resolved; the
rebuild also surfaced + reconciled a **MinIO IAM key drift** (the greenfield had rotated the app secret in KV
while MinIO kept the old one → fresh Nessie got an S3 403 → a data-preserving `mc admin user add` re-sync). The
full verb matrix then re-ran green. (Two adapter bugs were caught live and fixed in the process: cert-rotate
treated Spark/ZooKeeper as having a rotatable leaf — they don't, so they're now a graceful N/A — and the
iceberg-pg VRRP failover split-brained the catalog DB, so it's now a graceful N/A pointing at the spark-master
direction.)

## 5. Walkthrough (operator commands)

> Driven via `nexus-cli/scratch/nx.ps1` (sets the runtime env, calls the freshly built `nexus.exe`).

| # | Command | What you see | What it proves |
|---|---------|--------------|----------------|
| 1 | `nexus status lakehouse` | One 16-row table: the 4 MinIO EC nodes, the 2 Nessie catalog nodes, the iceberg-pg pair (the VIP `.151` holder labelled PRIMARY), the 2 Spark masters (the ALIVE leader labelled), the 3 workers, the 3 ZooKeeper nodes — all `alive`; the `leader:` line names the ALIVE Spark master. | One tool, one rolled-up view over three engines + ZooKeeper; the VIP holder + ALIVE master are resolved live (they drift). |
| 2 | `nexus health lakehouse` | `overall=green`: MinIO 4/4 live + cluster 200 + 4 drives ok; Nessie `/iceberg/v1/config` 2/2 + **object-store 2/2 UP**; Spark ALIVE + 3/3 workers; ZooKeeper 1 leader + 2 followers; **iceberg-pg 1 streaming standby**; VIP bound. | Every engine's real signal path in one report — including the cross-tier S3 trust canary (`nessie-objectstore`) and the iceberg-pg replication, the two probes that were honestly RED before the rebuild. |
| 3 | `nexus topology lakehouse` | 16 role-annotated nodes + the `.151` VIP pseudo-node + the ZooKeeper leader/followers + the Spark master/standby + the `spark://…:7077,…:7077` master URL. | The full shape of the tier; not data-sharded (Shards = null). |
| 4 | `nexus failover-test cluster lakehouse --direction spark-master --yes` | The ALIVE master is stopped; **ZooKeeper promotes the STANDBY to ALIVE** (the workers re-register), RTO ≈ 31 s; the old leader restarts as the new STANDBY; `recovery=recovered`. | The Spark master-HA drill — a real ZooKeeper-driven leader election, measured. |
| 5 | `nexus failover-test cluster lakehouse --direction iceberg-pg --yes` | A graceful, actionable **N/A**: a VRRP cutover of the catalog-DB pair promotes the standby into a split-brain + the promoted standby's `pg_hba` rejects Nessie → a DR runbook, not a one-shot. Points at the spark-master direction. | The CLI refuses an unsafe operation honestly instead of doing it and leaving the catalog broken. |
| 6 | `nexus acl lakehouse list` | The MinIO policies (`readwrite`/`readonly`/`consoleAdmin`/…) + the service users; the root + `nexus-lakehouse-app` identities flagged `protected`. | Day-2 MinIO IAM through the same `acl` surface every tier has. |
| 7 | `nexus cert-rotate lakehouse --yes` | New leaf serials on the **4 MinIO** (re-certed **big-bang** — a rolling 1-node re-cert breaks distributed MinIO's inter-node mTLS) + the **2 Nessie** nodes; **Spark (5) + ZooKeeper (3)** are graceful **N/A** rows (no rotatable leaf), iceberg-pg is DR-deferred. | Cert rotation that respects each component's real trust model — not a blunt restart-everything. |
| 8 | `nexus chaos lakehouse process-kill --yes` | `nexus-minio` is killed on one node; the EC:2 set keeps serving (`/minio/health/cluster` stays 200 while the node is down); the service restarts and the cluster recovers. | The erasure-set's fault tolerance, exercised + recovered through the standard chaos verb. |
| 9 | `nexus backup take lakehouse --yes` then `nexus backup restore lakehouse warehouse --yes` | `mc mirror s3://warehouse` to a node-local copy (N objects) → mirrored back into a fresh `warehouse-restore-verify` bucket → the same N restored (the integrity round-trip). | A portable point-in-time copy of the Iceberg/Spark data + a restore proof (the S3 store itself is already EC-durable). |

## 6. What this proves

One CLI now manages the entire lakehouse tier — three different engines plus a coordination ensemble — through
the same verb surface as every data and non-data tier, with no managed drivers, creds confined to Vault KV, and
honest reporting (the cross-tier CA split and the iceberg-pg replication were surfaced, not hidden; the unsafe
catalog-DB failover is refused with the reason). 4/5 non-data-tier adapters are now live; only the Harbor
registry (v0.8.5) remains. Full verb walkthrough + the cold-rebuild proof:
[`nexus-cli/docs/verification/0.8.4-lakehouse.md`](https://github.com/grezap/nexus-cli/blob/main/docs/verification/0.8.4-lakehouse.md)
+ ADR-0025. The executable System B JSON demos are `nexus-cli/docs/demos/DEMO-134..146`.
