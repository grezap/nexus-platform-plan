# ADR-0030 — Phase 0.G.6: StarRocks topology — FE quorum (BDB-JE) + BE tablet sharding/replication

- **Status**: Accepted
- **Date**: 2026-05-22
- **Deciders**: Greg Zapantis
- **Related**: ADR-0029 (the ClickHouse parallel — "sharded AND replicated, proven"), ADR-0031 (analytics client front door), ADR-0032 (analytics backup repository), `feedback_prefer_less_memory.md`, MASTER-PLAN "no toy databases"

## Context

StarRocks is the second analytics store (Phase 0.G.6). Its architecture splits cleanly into two planes:

- **FE (Frontend)** — the metadata + query-coordination plane. A Java process. FE nodes form a **replicated metadata quorum** using Oracle Berkeley DB Java Edition (BDB-JE) as the embedded consensus log, electing one **Leader** with the rest as **Followers** (and optionally non-voting Observers). The Leader owns metadata writes/DDL; Followers replicate the metadata and can serve reads + forward DDL to the Leader. Majority quorum: with 3 FE (1 Leader + 2 Follower) the cluster tolerates one FE loss and re-elects.
- **BE (Backend)** — the storage + compute plane. Tables are partitioned into **tablets** (`DISTRIBUTED BY HASH(...) BUCKETS n`); each tablet is replicated `replication_num` times across the BE nodes. BE does the actual scan/aggregate/join work; the FE Leader schedules tablet placement and re-replicates tablets when a BE is lost.

`vms.yaml` (tier `04-analytics`) budgets 3 FE + 3 BE for StarRocks. The same "no toy databases" mandate applies: the cluster must be genuinely sharded (tablets spread across all 3 BE) AND replicated (each tablet copied across BE) AND HA at the metadata plane (FE quorum survives Leader loss).

StarRocks FE/BE both require a JDK (FE is Java; BE is C++ but its tooling/agent expects Java present). This is unrelated to ADR-0028's "no JVM coordinator" — that was about ClickHouse's *coordination* tier; StarRocks's coordination IS its Java FE, so a JDK on the analytics tier's StarRocks nodes is intrinsic, not avoidable.

## Decision

**3 FE (1 Leader + 2 Follower, BDB-JE majority quorum) + 3 BE. Tables `DISTRIBUTED BY HASH(...) BUCKETS n` with `replication_num = 3` so tablets are sharded across all 3 BE and replicated on all 3.**

- **FE layout** (canon `vms.yaml`): `sr-fe-leader` (`.31`), `sr-fe-follower-1` (`.32`), `sr-fe-follower-2` (`.33`). The first FE bootstraps alone (becomes Leader); the two Followers join via `ALTER SYSTEM ADD FOLLOWER` and replicate the BDB-JE metadata log. All three are voting members → majority = 2, tolerates one FE loss.
- **BE layout**: `sr-be-1/2/3` (`.34`/`.35`/`.36`), each joined via `ALTER SYSTEM ADD BACKEND`. The FE Leader's tablet scheduler places + balances tablets across all three.
- **Table replication**: demo + showcase tables are created `DISTRIBUTED BY HASH(<key>) BUCKETS <n>` (n ≥ number of BE, so every BE gets tablets) with `PROPERTIES("replication_num" = "3")` → every tablet has a copy on all 3 BE. This is the maximum-availability lab posture; production tables would commonly use `replication_num = 3` on ≥3 BE too, so this is realistic, not inflated.
- **FE/BE communication is internal** over the VMnet10 backplane; FE serves MySQL protocol on `:9030` (query) + HTTP on `:8030` (REST/admin) on the VMnet11 service NIC; BE serves `:9060` (BE thrift) + `:8040` (BE HTTP) + `:9050` (heartbeat) on the backplane.
- **Leader vs Follower is dynamic.** `sr-fe-leader` is only the *initial* Leader (it bootstraps first); after the quorum forms, any FE can win election. The hostname records the bootstrap role, not a permanent identity — the smoke gate proves re-election by killing the current Leader and confirming a Follower takes over.

## Consequences

### Positive

- **Genuinely sharded AND replicated AND metadata-HA**, all provable: `SHOW TABLET FROM <table>` (or `information_schema.be_tablets`) shows tablets distributed across all 3 BE; each tablet's 3 replicas land on distinct BE; `SHOW FRONTENDS` shows 1 Leader + 2 Follower; killing the Leader triggers a sub-minute re-election (`SHOW FRONTENDS` shows a new Leader); killing a BE triggers tablet re-replication / query reroute (`SHOW BACKENDS` marks it down, queries still succeed). Satisfies "no toy databases" at the gate.
- **Single stable query endpoint without a VIP** — any FE accepts MySQL-protocol queries and DDL (Followers forward DDL to the Leader transparently), so clients connect to any FE via round-robin DNS (ADR-0031), no SPOF.
- **`replication_num = 3` on 3 BE** means a single BE loss never makes any tablet unavailable; the cluster stays fully queryable + writable.

### Negative

- **JDK on the StarRocks nodes.** FE is Java (a real heap, right-sized to 4 GB from canon 8 GB — logged in `vms.yaml`). Intrinsic to StarRocks; not avoidable like ClickHouse's coordinator JVM was.
- **3-replica tablets cost 3× storage** for the demo data. Negligible at lab data volumes; the property (survive any single BE loss) is worth it for the showcase.
- **FE quorum of 3 tolerates only one FE loss.** Losing 2 FE loses majority → metadata plane is read-only until restored. Acceptable at lab scale; production would add Observers or a 5-FE quorum.

### Neutral

- **`BUCKETS n` is a per-table tuning knob**, not a topology constant; the topology (3 FE + 3 BE, `replication_num=3`) is fixed. The demo schema picks `n` ≥ 3 so distribution is visible; app schemas tune per data volume.
- **StarRocks speaks the MySQL wire protocol on `:9030`** — clients use any MySQL driver / `mysql` CLI. This is what lets `nexus-cli`'s StarRocksAdapter shell out to on-node `mysql` (ADR-0024 invariant: no managed DB driver in the AOT binary).

## Verification

`smoke-0.G.6.ps1` asserts: `SHOW FRONTENDS` = 3 rows, exactly 1 `Role=LEADER` + 2 `Role=FOLLOWER`, all `Alive=true`; `SHOW BACKENDS` = 3 rows all `Alive=true`; a demo table's tablets (`SHOW TABLET`) distributed across all 3 BE with 3 replicas each on distinct BE; an FE-Leader-loss re-election (stop the Leader → a Follower becomes Leader → DDL still works); a BE-loss check (stop a BE → `SHOW BACKENDS` marks it down → queries still return full results from surviving replicas). Recorded in `nexus-infra-analytics/docs/verification/0.G.6-starrocks.md`.
