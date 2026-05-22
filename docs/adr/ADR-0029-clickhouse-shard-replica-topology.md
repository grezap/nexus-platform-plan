# ADR-0029 — Phase 0.G.5: ClickHouse topology — 3 shards × 2 replicas, Distributed over ReplicatedMergeTree

- **Status**: Accepted
- **Date**: 2026-05-22
- **Deciders**: Greg Zapantis
- **Related**: ADR-0028 (ClickHouse Keeper), ADR-0031 (analytics client front door), ADR-0032 (analytics backup repository), `feedback_prefer_less_memory.md`, MASTER-PLAN "no toy databases"

## Context

The MASTER-PLAN's data-tier mandate is explicit: **no toy databases** — every store must be a genuine multi-node cluster that is *both* sharded *and* replicated, and the property must be proven in the smoke gate, not assumed. For ClickHouse the two axes are orthogonal and both must be present:

- **Sharding** = horizontal partitioning of a table's data across nodes (more nodes = more storage + more parallel scan). In ClickHouse this is the `Distributed` table engine fanning a query/insert across a set of shards defined in `remote_servers`.
- **Replication** = each shard's data is copied to ≥2 nodes for availability (lose a replica, the shard stays readable/writable). In ClickHouse this is the `ReplicatedMergeTree` family, coordinating through Keeper (ADR-0028).

`vms.yaml` (tier `04-analytics`) budgets 6 data VMs + 3 keeper VMs for ClickHouse. The 6 data VMs can be arranged as 6×1 (6 shards, no replication — fails the "replicated" mandate), 1×6 (1 shard, 6 replicas — fails the "sharded" mandate), 2 shards × 3 replicas, or **3 shards × 2 replicas**.

## Decision

**3 shards × 2 replicas (6 data nodes) + a 3-node Keeper quorum (ADR-0028). `Distributed` tables over `ReplicatedMergeTree` local tables.**

- **Node layout** (canon `vms.yaml`): `ch-shard1-rep1`/`ch-shard1-rep2` (`.44`/`.45`), `ch-shard2-rep1`/`ch-shard2-rep2` (`.46`/`.47`), `ch-shard3-rep1`/`ch-shard3-rep2` (`.48`/`.49`).
- **`remote_servers` cluster** `nexus_analytics` defines 3 shards, each with 2 replica hosts, addressed over the VMnet10 backplane. `internal_replication=true` per shard so the `Distributed` table writes to one replica and lets `ReplicatedMergeTree` propagate to the other (the correct setting — without it the `Distributed` table double-writes and breaks dedup).
- **Per-node `macros`**: each node's `<macros>` carries its `{shard}` and `{replica}` so the `ReplicatedMergeTree` ZooKeeper path `/clickhouse/tables/{shard}/<db>.<table>` and replica name resolve per-host from one templated DDL. This is what makes `CREATE TABLE ... ON CLUSTER nexus_analytics` produce the correct per-node identity from a single statement.
- **Table pattern**: a local `ReplicatedMergeTree` table on every data node + a `Distributed` table over `nexus_analytics` that fans out by a sharding key (`rand()` for even spread in the demo schema, or a business key hash in the app schemas). Clients read/write the `Distributed` table from any node.
- **3 shards × 2 replicas, not 2 × 3**, because 3 shards demonstrates a more interesting fan-out (a 3-way scatter/gather is visibly distributed in `EXPLAIN`/query logs), and 2 replicas per shard is the minimum that proves replication + survives a single replica loss per shard. This matches the canon node names (`shard1/2/3`) verbatim.

## Consequences

### Positive

- **Genuinely sharded AND replicated**, provable: a `Distributed` query touches all 3 shards (visible in `system.query_log` `ProfileEvents` / `EXPLAIN`), and each shard's 2 replicas converge (insert on rep1 → readable on rep2 via Keeper-coordinated replication). Satisfies the "no toy databases" mandate at the gate.
- **Survives a single replica loss per shard** without data unavailability (the surviving replica serves the shard) and a single Keeper loss (quorum re-elects).
- **One templated DDL** via `ON CLUSTER` + `macros` — the same `CREATE TABLE` runs everywhere and each node self-identifies; no per-node SQL.

### Negative

- **No quorum-write durability across replicas by default.** `ReplicatedMergeTree` replication is asynchronous; a replica can briefly lag. For the lab this is acceptable (the smoke gate waits for convergence); production workloads needing synchronous replicas would set `insert_quorum`. Noted as a lab posture, not a defect.
- **3 shards × 2 replicas tolerates only ONE loss per shard.** Losing both replicas of one shard makes that shard's data unavailable (the other two shards still serve). Acceptable at 6-node lab scale; production scale would use 3 replicas per shard.

### Neutral

- **Sharding key is a schema decision, not a topology decision.** The demo schema shards by `rand()` for even distribution; the application schemas (dataflow-studio, chronosight, streamcore, etc.) choose business-appropriate keys. The topology (3×2) is fixed regardless.
- **`internal_replication=true` is mandatory** for this layout; it is the single most common ClickHouse misconfiguration (double-writes) and is baked into the `remote_servers` overlay, not left to operators.

## Verification

`smoke-0.G.5.ps1` asserts: `system.clusters` shows cluster `nexus_analytics` with 3 shards × 2 replicas all reachable; `system.replicas` shows every `ReplicatedMergeTree` table `is_readonly=0` + `is_session_expired=0` + queue not stuck; a `Distributed` INSERT fans across all 3 shards (row counts per shard non-zero); a single-shard replica-convergence round-trip (INSERT into shard1-rep1's local table → SELECT returns it from shard1-rep2); and a replica-loss check (stop shard2-rep1 → `Distributed` SELECT still returns shard2's rows from shard2-rep2). Recorded in `nexus-infra-analytics/docs/verification/0.G.5-clickhouse.md`.
