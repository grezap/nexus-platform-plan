# ADR-0028 — Phase 0.G.5: ClickHouse Keeper, not ZooKeeper, for replication coordination

- **Status**: Accepted
- **Date**: 2026-05-22
- **Deciders**: Greg Zapantis
- **Related**: ADR-0020 (KRaft-not-ZooKeeper for Kafka — same "drop the JVM coordinator" reasoning), ADR-0029 (ClickHouse shard/replica topology), `feedback_prefer_less_memory.md`, `nexus-infra-analytics` Phase 0.G.5

## Context

Phase 0.G.5 stands up the ClickHouse cluster on the `04-analytics` tier: 3 shards × 2 replicas (6 data nodes) coordinated by a 3-node quorum. ClickHouse's replication (`ReplicatedMergeTree`) and distributed DDL (`ON CLUSTER`) require an external consensus store that holds the replication log, replica registry, part-assignment metadata, and leader-election state. There are two options:

1. **Apache ZooKeeper** — the original and historically the only coordinator ClickHouse supported. A JVM service; needs a JDK on every quorum node; tuned via `zoo.cfg`; the de-facto standard for years.
2. **ClickHouse Keeper** (`clickhouse-keeper`) — a drop-in, ZooKeeper-protocol-compatible coordinator written in C++ and shipped by ClickHouse itself. GA and production-recommended since ClickHouse 22.x; speaks the ZooKeeper wire protocol (so `<zookeeper>` config in `clickhouse-server` points at it unchanged) but uses ClickHouse's own RAFT implementation (`NuRaft`), no JVM, lower memory, and is the path ClickHouse's own docs steer all new deployments toward.

The binding constraint is the same one that shaped the Kafka tier's KRaft decision (ADR-0020): **build-host RAM is finite** (`feedback_prefer_less_memory.md`). A ZooKeeper ensemble means a JDK + a JVM heap on each of the 3 coordinator VMs; Keeper is a single C++ binary that runs comfortably in the right-sized 2 GB the quorum nodes get. The lab also already made the identical "drop the legacy JVM coordinator for the engine-native RAFT coordinator" call for Kafka (ZooKeeper → KRaft); making the same call for ClickHouse keeps the platform's coordination story coherent.

## Decision

**ClickHouse Keeper (`clickhouse-keeper`), a dedicated 3-node RAFT quorum, no ZooKeeper anywhere in the lab.**

- Three dedicated Keeper nodes (`ch-keeper-1/2/3` at `192.168.70.41/.42/.43`) form a 3-server RAFT quorum (`<raft_configuration>` lists all three) → tolerates one node down.
- Keeper runs as a **dedicated role on its own VMs**, not co-located in the `clickhouse-server` process. Co-located (embedded) Keeper is supported, but a dedicated quorum keeps coordinator restarts/upgrades independent of data-node restarts and matches the canon `vms.yaml` topology (3 keeper + 6 data). This is the analytics-tier analogue of "separate roles" — the opposite of Kafka's combined mode, justified because the coordinator and data planes here have very different restart/resource profiles and the canon already budgets dedicated keeper VMs.
- `clickhouse-server` nodes reference the quorum through the standard `<zookeeper>` stanza (Keeper is wire-compatible) pointing at `ch-keeper-{1,2,3}:9181` over the VMnet10 backplane.
- Keeper's client port is `9181`; its RAFT inter-server port is `9234`. Both are opened only on the VMnet10 backplane (`feedback_cluster_template_nftables_backplane.md`).
- **No JDK is installed anywhere on the analytics tier** as a result of this decision (StarRocks FE/BE do need a JDK — that is ADR-0030's concern, unrelated to coordination).

## Consequences

### Positive

- **No JVM on the coordinator tier.** Keeper is a single C++ binary; the 3 quorum nodes run in 2 GB each (right-sized from the canon 4 GB — logged in `vms.yaml`), versus a ZooKeeper ensemble that would need JDK + heap headroom on each.
- **Forward-compatible + vendor-recommended.** ClickHouse's own documentation recommends Keeper for all new clusters; ZooKeeper support is maintained only for legacy migrations.
- **Coherent platform story.** Matches ADR-0020 (Kafka dropped ZooKeeper for KRaft). The lab has **zero ZooKeeper VMs** across all tiers — a clean talking point: "every coordinator in the platform is the engine's own native RAFT implementation."
- **Same package family.** `clickhouse-keeper` ships from the same ClickHouse apt repo as `clickhouse-server`; one vendor repo, one version line, no separate Apache ZooKeeper provisioning path.

### Negative

- **Keeper is younger than ZooKeeper.** Far fewer battle-decades than ZooKeeper, though it has been production-GA in ClickHouse for years and is what Cloud ClickHouse runs on. Lab-scale risk is negligible.
- **Dedicated quorum costs 3 VMs.** Embedded Keeper (co-located in `clickhouse-server`) would save the 3 keeper VMs. Rejected because canon budgets dedicated keeper nodes and the independent-restart property is worth the 3 right-sized 2 GB VMs.

### Neutral

- **Wire-compatible.** Because Keeper speaks the ZooKeeper protocol, `clickhouse-server`'s `<zookeeper>` config, `system.zookeeper`, and every replication code path are identical to a ZooKeeper deployment — only the server binary behind the port differs. If a future need ever forced ZooKeeper, the server config would not change.

## Verification

`smoke-0.G.5.ps1` asserts: each Keeper node answers the 4-letter-word `mntr` admin command with `zk_server_state` ∈ {`leader`,`follower`} and exactly one `leader` across the three; `SELECT * FROM system.zookeeper WHERE path = '/'` from a data node succeeds (proves server↔Keeper connectivity); and a Keeper-quorum 1-node-loss survival check (stop the Keeper leader → quorum re-elects → `ReplicatedMergeTree` inserts still commit). Recorded in `nexus-infra-analytics/docs/verification/0.G.5-clickhouse.md`.
