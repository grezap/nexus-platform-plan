# DEMO-18 · StarRocks shared-data: storage-compute separation, survive a CN loss

## 1. What this shows

The `04-analytics` tier's **second** StarRocks cluster — running side-by-side with the sealed shared-nothing one and demonstrating the OPPOSITE deployment model (Phase 0.L.5, ADR-0037). A data architect connects to one stable endpoint and runs analytical queries against a cluster where the data lives in object storage (MinIO) instead of on the data nodes — then we kill a Compute Node and the query keeps returning correct results from shared storage:

- **3 FE BDB-JE quorum** (`sr-sd-fe-1/2/3` at `.37`/`.38`/`.39`) — same metadata-quorum mechanism as the shared-nothing cluster; fronts the cluster on `starrocks-sd-fe.nexus.lab` (round-robin DNS, no VIP — ADR-0031).
- **2 stateless Compute Nodes** (`sr-sd-cn-1` at `.30`, `sr-sd-cn-2` at `.40` — documented decade-spill) — pure compute + local datacache; no durable storage. Killing a CN is survivable by definition because the data isn't on it.
- **MinIO storage volume** (`nexus_minio_starrocks` → `s3://starrocks/`) — every internal cloud-native table's data lives in MinIO's 4-node erasure-coded cluster. The Storage volume is created via SQL (`CREATE STORAGE VOLUME ... TYPE = S3 ...`); credentials read on-node from Vault KV; `fe.conf` carries no plaintext S3 secret.
- **Tighter least-privilege**: the StarRocks tenant uses a dedicated MinIO identity (`nexus-starrocks-app`) with a scoped policy (`starrocks-tenant`, `s3:*` on bucket `starrocks` only) — not the global readwrite identity Harbor reuses for `s3://harbor`. The cross-bucket deny is proven negatively in the tenant bootstrap.

Target persona: data architect / CTO who wants to see "we know both StarRocks paths — shared-nothing tablet-replication (DEMO-15) and shared-data storage-compute-separation (this one)". Companion to DEMO-15; together they tell the full StarRocks deployment story.

## 2. Runtime + prerequisites

- **Environment target** — `analytics-sd`
- **VMs required** — nexus-gateway, dc-nexus, vault-1/2/3, vault-transit (the 6-VM foundation base) + minio-1/2/3/4 (Phase 0.L.1 EC cluster — the storage backend) + sr-sd-fe-1/2/3 + sr-sd-cn-1/2 (the SR shared-data cluster itself)
- **External services** — MinIO bucket `starrocks` (provisioned by `nexus-infra-lakehouse/terraform/envs/lakehouse-minio/role-overlay-minio-starrocks-tenant.tf`); StarRocks `nexus.events` (cloud-native, default storage volume)
- **Seed data** — the smoke-gate's 60-row demo set (`scripts/smoke-0.L.5.ps1` writes it as part of the exit gate), or `nexus-cli seed analytics-sd --profile=small` once the CLI adapter lands
- **Expected duration** — 5 min
- **Reset command** — `nexus-cli demo run DEMO-18 --reset` (or re-fire `scripts/analytics-starrocks-sd.ps1 apply` — the `DROP+CREATE` schema bootstrap is deterministic)

## 3. Architecture snapshot

```
                                round-robin DNS (no VIP, ADR-0031)
                          starrocks-sd-fe.nexus.lab → .37 / .38 / .39
                                          │
                ┌─────────────────────────┼─────────────────────────┐
                │                         │                         │
        sr-sd-fe-1 (.37)           sr-sd-fe-2 (.38)           sr-sd-fe-3 (.39)
        FE Leader (BDB-JE)         FE Follower               FE Follower
        run_mode=shared_data       run_mode=shared_data       run_mode=shared_data
                │                         │                         │
                └────────────────── compute scheduling ──────────────┘
                                          │
                              ┌───────────┴───────────┐
                              │                       │
                       sr-sd-cn-1 (.30)        sr-sd-cn-2 (.40)
                       Stateless CN            Stateless CN
                       (local datacache only)  (local datacache only)
                              │                       │
                              └────── S3 (path-style) ──────┐
                                          │                 │
                                          ▼                 ▼
                                       MinIO 4-node EC cluster
                                       (minio-1..4 .141-.144)
                                       Storage volume `nexus_minio_starrocks`
                                       → s3://starrocks/  (durability lives here)
                                       Auth: nexus-starrocks-app + starrocks-tenant policy
```

## 4. The script (step → input → expected output → where to observe)

### Step 1 — show the cluster is alive in shared-data mode (the headline distinction)

| | |
|---|---|
| **Input** | On any FE: `mysql --skip-ssl -h 127.0.0.1 -P 9030 -u root -p<root>` then `SHOW FRONTENDS\G SHOW COMPUTE NODES\G SHOW STORAGE VOLUMES\G` |
| **Expected output** | 3 FE rows (1 LEADER + 2 FOLLOWER, all `Alive=true`); 2 CN rows (both `Alive=true`); `nexus_minio_starrocks` row with `Type=S3`, `Locations=s3://starrocks/`, `IsDefault=true` |
| **Where to observe** | `mysql` REPL on `sr-sd-fe-1`; also `sudo grep '^run_mode' /opt/starrocks/fe/conf/fe.conf` shows `shared_data` (distinguishes from the sealed shared-nothing cluster) |
| **What it proves** | Cluster is up; FE quorum holds; the data plane is CN (not BE); the default storage volume points at MinIO. |

### Step 2 — write data; prove it actually lands in MinIO (the headline shared-data property)

| | |
|---|---|
| **Input** | `INSERT INTO nexus.events VALUES …` (60 rows); then on `minio-1`: `sudo mc ls --recursive nexuslocal/starrocks/` |
| **Expected output** | `SELECT count(*) FROM nexus.events` returns `60`; `mc ls` shows non-empty `starrocks/` tree (parquet + metadata files) |
| **Where to observe** | `mysql` (count); `mc` (object listing); the storage volume's `LOCATIONS` already declared this path |
| **What it proves** | The data is in MinIO, not on the CN. The CN holds only a cache; durability is in the object store's EC. |

### Step 3 — the chaos: kill 1 CN, query still returns full results

| | |
|---|---|
| **Input** | `ssh nexusadmin@192.168.70.30 sudo systemctl stop nexus-starrocks-sd-cn.service`; wait ~10 s; re-run `SELECT count(*) FROM nexus.events` |
| **Expected output** | Query still returns `60`. The other CN serves the data — same shared storage, no local replica to "fail over to". |
| **Where to observe** | `mysql` REPL; meanwhile `SHOW COMPUTE NODES` shows the killed CN with `Alive=false` |
| **What it proves** | **Storage-compute separation HA**: any CN can serve any query because the data isn't on any specific node. Compare with DEMO-15's shared-nothing chaos where the surviving replica serves — same outcome, fundamentally different mechanism. |

### Step 4 — restart the CN; cluster heals automatically

| | |
|---|---|
| **Input** | `ssh nexusadmin@192.168.70.30 sudo systemctl start nexus-starrocks-sd-cn.service`; wait ~15 s; re-run `SHOW COMPUTE NODES` |
| **Expected output** | The CN returns to `Alive=true` within 15-30 s — no rebuild, no rebalance, just a heartbeat refresh (it carries no durable state) |
| **Where to observe** | `mysql` REPL |
| **What it proves** | CN elasticity: scale-in / scale-out is trivial because state isn't tied to nodes. Adding a CN-3 is the same shape: `ALTER SYSTEM ADD COMPUTE NODE` and it immediately serves queries. |

### Step 5 — bonus: cross-bucket-deny (least-privilege proof)

| | |
|---|---|
| **Input** | On `minio-1` as the SR tenant identity: `sudo mc alias set test-sr https://localhost:9000 nexus-starrocks-app <KV secret>` then `sudo mc cp /tmp/x test-sr/warehouse/.test` |
| **Expected output** | The `mc cp` to `s3://warehouse` is **denied** (the lakehouse warehouse, used by Spark + Iceberg, isn't reachable from the SR identity). The same `mc cp` to `test-sr/starrocks/.test` succeeds. |
| **Where to observe** | `mc` stderr |
| **What it proves** | The MinIO `starrocks-tenant` policy is correctly scoped — the SR identity cannot touch other tenants' buckets, satisfying ADR-0037's tighter-least-privilege choice. |

## 5. Compare-and-contrast (DEMO-15 ↔ DEMO-18)

| Property | DEMO-15 (shared-nothing 0.G.6) | DEMO-18 (shared-data 0.L.5) |
|---|---|---|
| Cluster | `sr-fe-leader` + 3 BE `.31-.36` | `sr-sd-fe-1..3` + 2 CN `.37/.38/.39/.30/.40` |
| Front door | `starrocks-fe.nexus.lab` | `starrocks-sd-fe.nexus.lab` |
| Data plane | **BE** (`start_be.sh`, `be.conf`, `ADD BACKEND`) | **CN** (`start_cn.sh`, `cn.conf`, `ADD COMPUTE NODE`) |
| Durability | `replication_num=3` across 3 BE (StarRocks layer) | MinIO EC (object-storage layer; `replication_num` is no-op on cloud-native tables) |
| Survives 1 data-node loss | Yes — surviving replica serves | Yes — surviving CN reads same shared storage |
| Add a data node | `ALTER SYSTEM ADD BACKEND` + tablet rebalance (BE catches up over the network) | `ALTER SYSTEM ADD COMPUTE NODE` (no rebalance — data didn't move) |
| Storage lives | On BE local disks | In MinIO storage volume `s3://starrocks/` |

Both modes ship in production StarRocks; the portfolio knows + demonstrates both.

## 6. Why this matters (the persona pitch)

"Storage-compute separation" is the headline cloud-data-warehouse pattern (Snowflake, BigQuery, Databricks SQL all build on it). DEMO-18 proves the lab can build and operate it on the **same StarRocks engine** as DEMO-15's classic tablet-replication cluster — same FE binary, same Vault PKI, same operator surface, different run_mode. The MinIO storage backend (DEMO-16's lakehouse) does double duty: Iceberg tables for Spark batch + a StarRocks storage volume for OLAP. One object store, two analytical engines, both with proper HA.
