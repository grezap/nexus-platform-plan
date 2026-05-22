# DEMO-15 · Analytics warehouse: sharded + replicated, survive a node loss

## 1. What this shows

The `04-analytics` tier as the protagonist (an infra demo in the spirit of DEMO-08 / DEMO-13, not an application demo). A data architect connects to one stable endpoint and runs analytical queries against a **genuinely sharded AND replicated** warehouse — then we kill nodes and the queries keep returning correct results:

- **ClickHouse** (Phase 0.G.5): a `Distributed` query fans out across **3 shards**, each shard's data lives on **2 replicas** kept in sync by a 3-node **ClickHouse Keeper** RAFT quorum (not ZooKeeper). Kill a Keeper → quorum re-elects, inserts still commit. Kill a shard replica → the query reroutes to the surviving replica, no rows lost.
- **StarRocks** (Phase 0.G.6): the same data modeled for high-concurrency BI — tablets `DISTRIBUTED BY HASH ... BUCKETS n` with `replication_num=3` across **3 BE**, fronted by a **3-FE quorum**. Kill the FE leader → a follower is elected, DDL still works. Kill a BE → tablets re-replicate, queries reroute.

Both are reached via **round-robin DNS, no VIP** (`clickhouse.nexus.lab` / `starrocks-fe.nexus.lab`) — the documented client-side-multi-endpoint HA pattern (ADR-0031). Target persona: data architect / CTO who wants to see that "analytical store" means *clustered, sharded, replicated, and fault-tolerant* — not a single big box.

## 2. Runtime + prerequisites

- **Environment target** — `analytics`
- **VMs required (ClickHouse half, 0.G.5)** — nexus-gateway, vault-1/2/3, vault-transit, ch-keeper-1/2/3, ch-shard1-rep1/rep2, ch-shard2-rep1/rep2, ch-shard3-rep1/rep2
- **VMs required (StarRocks half, 0.G.6)** — sr-fe-leader, sr-fe-follower-1/2, sr-be-1/2/3
- **External services** — ClickHouse `nexus.events` (Distributed) over `nexus.events_local` (ReplicatedMergeTree); StarRocks `nexus.events` (hash-distributed, replication_num=3)
- **Seed data** — the smoke-gate's 600-row demo set (`numbers(600)`), or `nexus-cli seed analytics --profile=small`
- **Expected duration** — 7 min
- **Reset command** — `nexus-cli demo run DEMO-15 --reset`

## 3. Architecture snapshot

```
            round-robin DNS (no VIP, ADR-0031)
   clickhouse.nexus.lab ─┬─ ch-shard1-rep1  ch-shard2-rep1  ch-shard3-rep1
                         └─ ch-shard1-rep2  ch-shard2-rep2  ch-shard3-rep2
                                   │ ReplicatedMergeTree (2 replicas / shard)
                          ClickHouse Keeper quorum: ch-keeper-1/2/3 (RAFT)

   starrocks-fe.nexus.lab ─ sr-fe-leader + sr-fe-follower-1/2 (BDB-JE quorum)
                                   │ tablet scheduler
                          sr-be-1/2/3  (tablets x replication_num=3)
```

## 4. Step-by-step script

1. **Connect to one stable name.** `clickhouse-client --secure --host clickhouse.nexus.lab` (resolves round-robin to one of 6 data nodes). Run `SELECT count() FROM nexus.events` → 600.
2. **Prove sharding.** `SELECT count() FROM nexus.events_local` on each shard's rep1 → ~200 each (data split across 3 shards).
3. **Prove replication.** Compare `nexus.events_local` count on shard1-rep1 vs shard1-rep2 → equal (Keeper-coordinated).
4. **Kill a Keeper** (the RAFT leader). Re-run an INSERT → still commits (2-of-3 quorate). Restart it → rejoins as follower.
5. **Kill a shard replica.** Re-run the `Distributed` `SELECT count()` → still 600 (rerouted to the surviving replica). Restart → re-syncs.
6. **Switch to StarRocks** (0.G.6): `mysql -h starrocks-fe.nexus.lab -P 9030` → `SHOW TABLET` (tablets across all 3 BE) → kill the FE leader → `SHOW FRONTENDS` shows a new leader → kill a BE → queries still return.

## 5. Observability trail

- ClickHouse: `system.clusters`, `system.replicas` (absolute_delay, queue_size), `system.parts`; Keeper `mntr` (`zk_server_state`, `zk_followers`).
- StarRocks: `SHOW FRONTENDS` / `SHOW BACKENDS` / `SHOW TABLET`; FE leader election in `fe.log`.
- (Phase 0.I) Prometheus node_exporter on every analytics node; ClickHouse + StarRocks exporters feed Grafana dashboards.

## 6. Code pointers

- ClickHouse: [`nexus-infra-analytics`](https://github.com/grezap/nexus-infra-analytics) — `terraform/envs/analytics-clickhouse/` (overlays) + `packer/analytics-clickhouse-{keeper,server}-node/` + `scripts/smoke-0.G.5.ps1`.
- StarRocks: same repo — `terraform/envs/analytics-starrocks/` + `packer/analytics-starrocks-{fe,be}-node/` + `scripts/smoke-0.G.6.ps1`.
- ADRs: [0028](../adr/ADR-0028-clickhouse-keeper-not-zookeeper.md) · [0029](../adr/ADR-0029-clickhouse-shard-replica-topology.md) · [0030](../adr/ADR-0030-starrocks-fe-quorum-be-tablet-sharding.md) · [0031](../adr/ADR-0031-analytics-client-front-door-round-robin-dns.md) · [0032](../adr/ADR-0032-analytics-backup-repository-nfs-gateway.md).
- System B verb demos: [`nexus-cli/docs/demos/demo-0.G.5-clickhouse-*.json`](https://github.com/grezap/nexus-cli/tree/main/docs/demos) (11) + `demo-0.G.6-starrocks-*.json` (when 0.G.6 lands).

## 7. Variations

- Backup/restore tour: take a `BACKUP` on one node, `RESTORE` from another (shared NFS repo, ADR-0032) — shows DR within the tier.
- Scale-out: drain + re-add a replica (`scale-out` verb) and watch it re-sync via Keeper.
- cert-rotate: force a fresh Vault-PKI leaf + `SYSTEM RELOAD CONFIG` with zero downtime.

## 8. Troubleshooting

- A single-host `clickhouse-client` that resolves the round-robin name once + pins can land on a just-killed node — use the engine's multi-host client form (the no-VIP tradeoff documented in ADR-0031 §Consequences).
- If a Keeper kill makes inserts hang, check the quorum still has 2/3 (`mntr`); killing 2 of 3 loses quorum (expected).

## 9. What this proves

The analytics tier is not a toy: both stores are clustered, **sharded** (horizontal scale) AND **replicated** (fault tolerance), with engine-native coordination (ClickHouse Keeper RAFT; StarRocks FE BDB-JE quorum). The cluster survives a coordinator loss and a data-node loss while returning correct results, reached through a single stable round-robin endpoint with no SPOF — the MASTER-PLAN "no toy databases" mandate, proven by killing things on stage.

---

**Status:** planned. ClickHouse half (0.G.5) is implementable now (the System B `demo-0.G.5-clickhouse-*` specs back every step); StarRocks half fills in at 0.G.6.
