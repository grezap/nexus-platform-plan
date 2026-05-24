# DEMO-16 · Lakehouse: object store + table format + compute, survive a node loss

## 1. What this shows

The `08-spark` lakehouse tier as the protagonist (an infra demo in the spirit of
DEMO-15, consolidating Phases 0.L.1 / 0.L.2 / 0.L.3). A data engineer runs a
Spark job that creates an Iceberg table through a REST catalog and writes Parquet
to an S3 object store — then we kill nodes across all three layers and the
lakehouse keeps working:

- **Object storage** (0.L.1): **MinIO** 4-node **distributed erasure-coded**
  cluster (ADR-0033). Reached via round-robin DNS `minio.nexus.lab` (no VIP). Kill
  one node → the erasure set stays read-write (EC tolerates a node loss).
- **Table format + catalog** (0.L.2): **Apache Iceberg** via **Project Nessie** —
  two stateless REST instances (round-robin `iceberg.nexus.lab`) backed by a
  **dedicated PostgreSQL master-replica HA pair** with a **keepalived VRRP VIP**
  `iceberg-db.nexus.lab` (ADR-0034). Kill the catalog-DB primary → the VIP floats,
  the standby promotes, the catalog keeps serving.
- **Compute** (0.L.3): **Apache Spark** standalone **HA** — 2 masters
  (ZooKeeper-elected) + 3 workers + a 3-node Apache ZooKeeper ensemble
  (recoveryMode=ZOOKEEPER; the one deliberate ZK exception, ADR-0035). Kill the
  active master → ZooKeeper re-elects the standby; running jobs survive.

The end-to-end deliverable: **Spark → Nessie (Iceberg REST) → MinIO (S3A)** — a
real medallion write path. Target persona: data architect who wants to see that
"lakehouse" means *object store + open table format + distributed compute, each
clustered and fault-tolerant* — not a notebook against a laptop.

## 2. Runtime + prerequisites

- **Environment target** — `data-engineering`
- **VMs required (MinIO, 0.L.1)** — minio-1/2/3/4
- **VMs required (Iceberg, 0.L.2)** — iceberg-rest-1/2, iceberg-pg-1/2 (+ VIP
  `iceberg-db.nexus.lab .151`)
- **VMs required (Spark, 0.L.3)** — spark-master-1/2, spark-worker-1/2/3,
  zookeeper-1/2/3
- **Foundation** — nexus-gateway, dc-nexus, vault-1/2/3, vault-transit
- **External services** — MinIO buckets `warehouse` + `spark-events`; Nessie
  Iceberg REST `iceberg.nexus.lab:19120`; Spark multi-master
  `spark://192.168.70.140:7077,192.168.70.153:7077`
- **Seed data** — none; the smoke/bootstrap creates `nexus.lakehouse_demo.smoke`
- **Expected duration** — 8 min
- **Reset command** — `nexus-cli demo run DEMO-16 --reset`

## 3. Architecture snapshot

```
   round-robin DNS (no VIP, ADR-0031/0033)
   minio.nexus.lab ──── minio-1/2/3/4  (distributed erasure-coded; s3://warehouse)

   iceberg.nexus.lab ── iceberg-rest-1/2  (Project Nessie, stateless REST)
                              │ JDBC
                  iceberg-db.nexus.lab (keepalived VRRP VIP .151, ADR-0034)
                  ├─ iceberg-pg-1  PostgreSQL primary
                  └─ iceberg-pg-2  PostgreSQL standby

   spark://m1:7077,m2:7077 (ZK-elected, no VIP, ADR-0035)
   ├─ spark-master-1 / spark-master-2  (active/standby)
   ├─ spark-worker-1 / -2 / -3
   └─ zookeeper-1/2/3  (recoveryMode=ZOOKEEPER)
```

## 4. Step-by-step script

1. **Object store is sharded for fault tolerance.** `mc admin info nexuslocal` on
   minio-1 → 4 online drives across 4 nodes (erasure set).
2. **Catalog is HA.** `dig +short iceberg.nexus.lab` → 2 REST IPs;
   `dig +short iceberg-db.nexus.lab` → the VIP `.151` (on the PG primary).
3. **Spark is HA.** `curl http://192.168.70.140:8080/json/` → one master `ALIVE`
   with 3 workers; the other master `STANDBY`; `/spark` election state in ZooKeeper.
4. **The write path.** On the active master:
   `spark-sql --master spark://192.168.70.140:7077,192.168.70.153:7077 -e
   "CREATE TABLE nexus.lakehouse_demo.smoke (id bigint, msg string) USING iceberg;
   INSERT INTO … VALUES (1,'hello'),(2,'lakehouse'); SELECT count(*) FROM …"` → 2.
   The table's metadata is in Nessie/PG; the Parquet is in MinIO `s3://warehouse`.
5. **Kill a MinIO node.** Re-run a `SELECT` → still returns (EC tolerates 1 loss).
6. **Kill the catalog-DB primary** (`iceberg-pg-1`). The VIP floats to
   `iceberg-pg-2`, which promotes; the Nessie REST catalog keeps answering.
7. **Kill the active Spark master.** ZooKeeper re-elects the standby; submit
   another `spark-sql` job → it schedules on the new leader.

## 5. Observability trail

- MinIO: `mc admin info nexuslocal`; per-node `:9000/minio/health/cluster`.
- Iceberg/Nessie: `curl https://iceberg.nexus.lab:19120/iceberg/v1/config`;
  `http://<rest>:9000/q/health`; on iceberg-pg-1 `pg_stat_replication` + `ip addr` (VIP).
- Spark: `http://<master-ip>:8080/json/` (status, aliveworkers); ZooKeeper
  `zkCli.sh ls /spark`; `zkServer.sh status` (1 leader + 2 followers).
- (Phase 0.I) Prometheus node_exporter on every lakehouse node feeds Grafana.

## 6. Code pointers

- [`nexus-infra-lakehouse`](https://github.com/grezap/nexus-infra-lakehouse) —
  `terraform/envs/lakehouse-{minio,iceberg,spark}/` +
  `packer/lakehouse-{minio,iceberg-pg,iceberg-rest,spark,zookeeper}-node/` +
  `scripts/smoke-0.L.{1,2,3}.ps1`.
- Cross-tier: `nexus-infra-vmware` foundation
  `role-overlay-gateway-lakehouse-{reservations,dns}.tf` + security
  `role-overlay-vault-{pki,agent}-{minio,iceberg,spark}-*.tf`.
- ADRs: [0033](../adr/ADR-0033-minio-distributed-erasure-coded-object-storage.md) ·
  [0034](../adr/ADR-0034-iceberg-catalog-nessie-pg-master-replica.md) ·
  [0035](../adr/ADR-0035-spark-standalone-ha-zookeeper.md) ·
  [0031](../adr/ADR-0031-analytics-client-front-door-round-robin-dns.md).
- System B verb demos: deferred until the nexus-cli lakehouse adapters land.

## 7. Variations

- **Time travel**: take a second INSERT, then `SELECT … VERSION AS OF <snapshot>`
  to read the earlier Iceberg snapshot.
- **Erasure tolerance**: kill a 2nd MinIO node → the set goes read-only (EC:2 is
  the documented boundary).
- **Catalog failover recovery**: re-seed the old iceberg-pg primary as a standby
  (lakehouse handbook).

## 8. Troubleshooting

- "Initial job has not accepted any resources" with free cores ≠ a resources
  problem — it means executors launch and die (the Spark executor-RPC firewall
  gap; lakehouse handbook §3.6 #8).
- A round-robin client that pins to a just-killed MinIO/REST node should retry
  (the no-VIP tradeoff, ADR-0031).

## 9. What this proves

The lakehouse is not a toy: object storage is **distributed + erasure-coded**, the
catalog is **HA** (stateless REST over a streaming-replicated PG with a VRRP VIP),
and compute is **HA** (ZooKeeper-elected master failover). A single Spark job
exercises all three through open standards (S3 + Iceberg REST), and the stack
survives a loss in each layer while returning correct results — the MASTER-PLAN
"no toy infrastructure" mandate, proven by killing things on stage.

---

**Status:** planned. The infra (0.L.1/0.L.2/0.L.3) is implementable now — every
step maps to `smoke-0.L.{1,2,3}.ps1`. The `nexus-cli demo run DEMO-16` wrapper
fills in when the lakehouse CLI adapters land.
