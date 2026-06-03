# ADR-0042 · Phase 0.P: Citus-sharded PostgreSQL with full Patroni HA — new repo `nexus-infra-citus`

**Status:** accepted
**Date:** 2026-06-03
**Phase:** 0.P
**Scope:** NEW repo `grezap/nexus-infra-citus` (tier `08-citus`) + `nexus-platform-plan/docs/infra/vms.yaml` (new `citus` cluster) + foundation dnsmasq reservations (citus overlay) + VIP DNS A-records.

## Context

The relational tier of the portfolio now demonstrates two of the three axes:

- **Replication HA** — Percona XtraDB Cluster (Galera synchronous multi-master, 0.G.3) and Patroni (PostgreSQL streaming replication, 0.G.4).
- **MySQL horizontal sharding** — Vitess (0.O), which shards MySQL behind a MySQL-protocol query router.

The missing axis is **PostgreSQL-native horizontal sharding**. Phase 0.P adds it via the **Citus** extension — PostgreSQL's native distributed-table engine, where a *coordinator* holds the distributed metadata and routes/aggregates queries against shards spread across *worker* nodes. Greg's committed direction (2026-05-22): a **completely separate first-class repo** (not an extension of `nexus-infra-oltp`), mirroring how 0.O Vitess was its own repo.

Unlike Vitess (which uses an external topology server + query router and replicates *within* each shard via MySQL replication), Citus is "just PostgreSQL" — distribution is a `shared_preload_libraries` extension. So HA is orthogonal and supplied the same way the lab already proved at 0.G.4: **Patroni + etcd streaming-replication clusters**, one per Citus node-group, each fronted by a keepalived VRRP VIP so the Citus metadata (`pg_dist_node`) can reference a stable endpoint that survives a failover.

Greg's decision (2026-06-03, AskUserQuestion): build **full Patroni HA** — every Citus node-group (the coordinator and each worker) is a 2-node Patroni cluster, not a single node. This matches the Vitess precedent of intra-shard replication and removes every PostgreSQL SPOF.

## Decision

Build a **Citus-sharded PostgreSQL cluster with full Patroni HA** as the new repo `nexus-infra-citus` (tier `08-citus`), **9 VMs + 3 VRRP VIPs**:

| Role | Count | Hosts | VMnet11 | VMnet10 | Port(s) |
|---|---|---|---|---|---|
| etcd DCS (Patroni quorum store) | 3 | `citus-etcd-1/2/3` | `.202/.203/.204` | `.10.202-.204` | 2379/2380 |
| Coordinator Patroni pair | 2 | `citus-coord-1/2` | `.205/.206` | `.10.205-.206` | PG 5432 / Patroni REST 8008 |
| Worker-group-1 Patroni pair | 2 | `citus-worker1-1/2` | `.207/.208` | `.10.207-.208` | PG 5432 / Patroni REST 8008 |
| Worker-group-2 Patroni pair | 2 | `citus-worker2-1/2` | `.209/.210` | `.10.209-.210` | PG 5432 / Patroni REST 8008 |

**VRRP VIPs (keepalived unicast, float to the current Patroni leader of each group):**

| VIP | VMnet11 | Fronts | DNS |
|---|---|---|---|
| coordinator | `.211` | coord-1/2 leader | `coord.citus.nexus.lab` |
| worker-1 | `.212` | worker1-1/2 leader | `worker1.citus.nexus.lab` |
| worker-2 | `.213` | worker2-1/2 leader | `worker2.citus.nexus.lab` |

Engine = **PostgreSQL 17 + Citus 14.x** (latest GA Citus supporting PG 17), `shared_preload_libraries = 'citus'`. The coordinator registers each worker in `pg_dist_node` **by its VIP** (`citus_add_node('192.168.70.212', 5432)` …), so a Patroni failover within a worker group moves the VIP to the new leader and the Citus metadata stays valid with no `pg_dist_node` rewrite.

### Key sub-decisions

1. **Separate repo, NOT an `nexus-infra-oltp` extension** (Greg, 2026-05-22). Citus is the PG-sharding sibling of Vitess (MySQL-sharding); the portfolio reads cleanest as "MySQL sharding = `nexus-infra-vitess`, PG sharding = `nexus-infra-citus`". Per-cluster-state + per-engine-template canon applies within the new repo ([[per-cluster-state-per-engine-template]]).

2. **Full Patroni HA — every node-group is a 2-node Patroni cluster** (Greg, 2026-06-03). The coordinator holds the distributed catalog (`pg_dist_*`) — a coordinator outage makes the *entire* distributed database unqueryable, so it is the highest-value HA target; each worker holds a slice of every distributed table's shards. Patroni gives automated leader election + streaming replication + failover per group. The leaner "1 coordinator + N workers, no per-node standby" option was rejected by Greg for a stronger HA story consistent with Vitess's 1P+2R-per-shard.

3. **2 nodes per Patroni group (1 leader + 1 sync/async replica).** A 2-node group with the 3-node shared etcd providing the DCS quorum is sufficient for automated failover (etcd, not PostgreSQL node count, provides the quorum). 3-per-group was rejected as RAM-prohibitive for a 3-group cluster (would be 12 PG VMs); the shared etcd quorum makes the 3rd PG node redundant for failover safety.

4. **Shared 3-node etcd DCS for all three Patroni groups.** One etcd cluster serves all three Patroni scopes (`citus-coord`, `citus-worker1`, `citus-worker2`) under distinct DCS namespaces (`/citus/coord`, `/citus/worker1`, `/citus/worker2`). Reuses the proven 0.G.4 / 0.O `*-etcd-node` build pattern (etcd 3.5.x upstream static binaries, full mTLS, client-cert-auth). 3 nodes tolerate 1 loss.

5. **keepalived VRRP VIP per node-group, NOT HAProxy** (refinement of the 0.G.4 pattern). 0.G.4 used an HAProxy HA pair in front of a single Patroni cluster. For Citus we need *three* leader endpoints (coordinator + 2 workers), and the consumer (the Citus coordinator reaching workers; clients reaching the coordinator) only needs "route to the current leader." A keepalived VIP co-located on the PG nodes, gated by a `vrrp_script` that probes the local Patroni REST `/leader` (HTTP 200 only on the leader), floats each VIP to its group's leader with no extra LB VMs. Saves 6 LB VMs vs. an HAProxy pair per group. The `vrrp_script` must exec the **absolute versioned** `pg_isready`/curl binary, not a wrapper symlink ([[keepalived-check-needs-versioned-binary]]).

6. **Full mTLS now (Vault PKI on the PG wire + etcd + Patroni REST)** (consistent with 0.O). Every PostgreSQL connection (client↔coordinator, coordinator↔worker, Patroni↔PG, streaming replication), the etcd peer+client channels, and the Patroni REST API get per-host Vault-PKI leaf certs (`pki_int/issue/citus-server`). PG `hostssl … clientcert=verify-full` enforces mTLS. The security env gains a `citus-server` PKI role + per-host AppRole sidecars + KV-seeded credentials (PG superuser, replication user, Patroni REST user, the `citus-app` distributed-table owner). VIP IP-SANs are baked into each PG node's cert so a connection to the VIP validates regardless of which leader currently holds it.

7. **IP allocation `.202-.210` (VMnet11, 9 nodes) + `.211-.213` (3 VIPs) + `.10.202-.213` (VMnet10 backplane); MAC `:D7-:DF`** — pre-apply MAC+IP audit ALL CLEAR against every foundation reservation file (highest prior MAC `:D6` vitess, highest prior pinned IP `.201` vitess) per [[mac-pool-pre-apply-audit]] (the lesson from 0.N's first apply). VMnet10 carries all intra-cluster PG replication + coordinator↔worker traffic + etcd; VMnet11 carries SSH + the client-facing coordinator endpoint. VIPs are virtual (no DHCP pin / MAC) — only the 9 node MACs are dnsmasq reservations and trigger keys ([[terraform-partial-apply-destroys-resources]] N3 lesson).

### Topology rationale (Citus mechanics)

- **Distributed tables** (`create_distributed_table('t','col')`) — rows hash-partitioned into shards spread across the 2 worker groups; the coordinator routes/aggregates.
- **Reference tables** (`create_reference_table('t')`) — fully replicated to every worker (and the coordinator), for joins against distributed tables with no reshuffle.
- **Colocation** — two distributed tables sharded on the same key with the same shard count are colocated, so joins on the distribution key are worker-local (no repartition).
- The v1 demo seeds one distributed table + one colocated distributed table + one reference table, proves shards land on **both** worker groups (`citus_shards`, `pg_dist_shard_placement`), and proves a cross-shard aggregate is routed/merged by the coordinator.

## Consequences

### Positive

- **Closes the PostgreSQL-native-sharding gap** — the explicit PG complement to 0.O's Vitess MySQL sharding, and a distinct distribution model (extension-in-PG vs. external query router).
- **Reuses proven patterns** — the 0.G.4 etcd + Patroni bootstrap, the VRRP-VIP-with-versioned-check pattern, the per-engine-template + per-cluster-state canon, the Vault-PKI mTLS overlay shape from every prior tier.
- **Strongest relational HA story in the portfolio** — every PG node-group is HA; combined with sharding it demonstrates "HA *and* horizontal scale on PostgreSQL" together.
- **Natural extensions** — `citus_add_node` of a 3rd worker group (online scale-out) + `rebalance_table_shards` (online shard rebalance) are obvious 0.P.1/demo follow-ups.

### Negative

- **9 VMs (~18 GB RAM)** — heaviest of the relational HA tiers. Mitigated by the minimal-running-VMs discipline (stopped when not the active phase) ([[minimal-running-vms]]).
- **Three Patroni scopes + three VIPs = more overlay surface** — the bootstrap renders 3 distinct `patroni.yml` scopes and 3 keepalived configs; the first ratification will surface Patroni/Citus/cert transients (chronicled in handbook §3).
- **Citus + Patroni interaction** — Citus metadata must be initialised (`CREATE EXTENSION citus`, `citus_set_coordinator_host`, `citus_add_node`) only after all three Patroni groups have an elected leader and the VIPs are bound; the apply graph orders this strictly.

### Risks

- **Bootstrap ordering** — etcd healthy → all three Patroni groups elect a leader → VIPs bind → coordinator can `citus_add_node(worker-VIP)`. The overlay graph enforces this; a premature `citus_add_node` against an unbound VIP is the likely first-ratification transient.
- **VIP referenced in `pg_dist_node`** — relies on the worker cert carrying the VIP IP-SAN and keepalived correctly floating the VIP to the new leader on failover. The `vrrp_script` leader-probe must hit the Patroni REST `/leader` (200 only on leader), not merely `pg_isready` (which is up on replicas too) — otherwise the VIP could bind on a replica.
- **Citus version ↔ PG major pin** — Citus 14.x must match PG 17; the Citus apt repo (`citusdata`) pins the extension to the PG major. Baked at template time.

## Alternatives considered

1. **Extend `nexus-infra-oltp` (like 0.N did for Mongo).** Rejected per Greg's explicit "completely separate first-class project" direction (2026-05-22) — Citus is the PG-sharding sibling of the standalone `nexus-infra-vitess`.
2. **Lean 1 coordinator + N workers, no per-node HA.** Rejected by Greg (2026-06-03) for a stronger HA story; a coordinator SPOF makes the whole distributed DB unqueryable.
3. **HAProxy HA pair per group (the literal 0.G.4 LB pattern) instead of keepalived-on-PG VIPs.** Rejected — would add 6 LB VMs for three groups; keepalived co-located on the PG nodes with a Patroni-REST leader-probe achieves the same "route to leader" with zero extra VMs.
4. **Citus built-in statement-based shard replication (`citus.shard_replication_factor=2`) instead of Patroni.** Rejected — deprecated/discouraged upstream in favour of streaming replication (Patroni); Patroni also gives the lab a consistent HA mechanism across 0.G.4 and 0.P.
5. **3 nodes per Patroni group.** Rejected — RAM-prohibitive (12 PG VMs); the shared 3-node etcd provides the failover quorum, so 2 PG nodes per group is sufficient.
6. **Consul/ZooKeeper DCS instead of etcd.** Rejected — etcd is the proven lab DCS (0.G.4, 0.O); zero ZooKeeper outside the deliberate 0.L.3 Spark exception.

## See also

- [`feedback_mac_pool_pre_apply_audit.md`](../../../nexus-infra-oltp/memory/feedback_mac_pool_pre_apply_audit.md) — the pre-apply MAC+IP audit (ALL CLEAR for `:D7-:DF` / `.202-.213`)
- [`feedback_per_cluster_state_per_engine_template.md`](../../../nexus-infra-oltp/memory/feedback_per_cluster_state_per_engine_template.md) — per-engine template + per-cluster state canon
- [ADR-0041](./ADR-0041-vitess-sharded-mysql-cluster.md) — the 0.O MySQL-sharding sibling
- [ADR-0040](./ADR-0040-mongodb-sharded-cluster-separate-from-0g2-rs.md) — the 0.N document-store sharding sibling
- [planned-sharding-ha-enhancements memory](../../../nexus-infra-oltp/memory/project_planned_sharding_ha_enhancements.md) — the 0.M-0.P commit narrative
- 0.G.4 Patroni + etcd + HAProxy HA stack (`nexus-infra-oltp/terraform/envs/oltp-patroni`) — the etcd/Patroni/VRRP precedent ported here
