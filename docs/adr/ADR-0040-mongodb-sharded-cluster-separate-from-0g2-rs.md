# ADR-0040 · Phase 0.N: MongoDB sharded cluster — separate from the 0.G.2 3-node RS

**Status:** accepted
**Date:** 2026-05-28
**Phase:** 0.N
**Scope:** new `nexus-infra-oltp/terraform/envs/oltp-mongo-sharded/` env + `nexus-platform-plan/docs/infra/vms.yaml` (new `mongo-sharded` cluster).

> **Update 2026-07-10 — the deferred 0.N.1 wire mTLS is DONE + LIVE-VERIFIED.** The mTLS gap called out below (points 7/8, Consequences) is closed: `net.tls.mode = requireTLS` on all 11 nodes + per-host `mongo-sharded-server` Vault-PKI leaf certs (per-host Vault Agents) + online `rotateCertificates` (via MongoShardedAdapter `cert-rotate`, no restart / no re-election), bringing the sharded cluster to parity with the 0.G.2 RS posture. `clusterAuthMode` stays keyFile for member auth. Verified via an 11-VM cold-rebuild (one from-zero pass, 92 resources, zero transients); smoke-0.N §9 GREEN.

## Context

Phase 0.G.2 shipped a 3-node MongoDB replica set (`mongo-1/2/3` at .71/.72/.73) showcasing replica-set HA. But the OLTP tier's broader portfolio narrative is HA-by-replication; the **sharding** axis was only demonstrated where it's the engine's native idiom (Redis hash-slots, Kafka partitions, ClickHouse shards, StarRocks tablets). To round out the relational+document sharding showcase, Phase 0.N adds a MongoDB sharded cluster (committed 2026-05-22 alongside 0.M / 0.O / 0.P).

## Decision

Build a **completely independent** sharded cluster (11 NEW VMs: 3 config + 2×3 shards + 2 mongos). The 0.G.2 RS stays as the canonical "replica set" showcase; 0.N is the "sharded cluster" showcase. No coupling between the two.

### Key sub-decisions

1. **Separate cluster, NOT reuse 0.G.2 as shard-1.** Pros: 0.G.2's PROVEN cold-rebuild state stays untouched; clean portfolio narrative (RS vs sharded). Cons: +12 GB RAM. RAM is the cheaper trade-off given the build host has 128 GB and the 0.G.2 stop/cold-rebuild discipline gives back its ~24 GB when not running.

2. **2 shard RSes (minimum per the master-plan), each 3 nodes.** Demonstrates the sharding mechanic (chunks distributed across multiple shards); a single shard would just be a replica set with extra config-server overhead. 3 shards was a third option (stronger sharding showcase) but adds 3 more VMs (~+6 GB RAM); 2 is the minimum viable proof. The pattern is extensible — adding shard-3 later is purely additive.

3. **2 mongos query routers (no VIP).** mongos is stateless; clients connect to `mongos.nexus.lab` (round-robin DNS over .58/.59 per ADR-0031 for write paths). No VRRP VIP — clients retry the other mongos on connection failure. This mirrors the analytics-tier "no VIP for write paths" pattern.

4. **Reuse the `oltp-mongo-node` Packer template, extended to include `mongodb-org-mongos`.** Per the per-engine-template canon ([[feedback_per_cluster_state_per_engine_template.md]]) — engine = MongoDB, so ONE template covers both 0.G.2 RS and 0.N sharded. The package set grows by 1 (`mongodb-org-mongos`). The 0.G.2 cluster doesn't use mongos but having the binary present is harmless.

5. **Standard MongoDB port split:** configsvr 27019, shardsvr 27018, mongos 27017. Distinguishes service roles in nftables logs + `ss`/`netstat` output. The 0.G.2 RS runs on 27017 (it's a flat RS with no role split); the sharded cluster respects the convention to avoid confusion.

6. **Shared keyFile across the entire sharded cluster, sourced from Vault KV at `nexus/oltp/mongo/keyfile`.** Reuses the same KV path the 0.G.2 RS uses. Operationally simpler than per-cluster keyFiles. MongoDB requires all cluster members + mongos to share the same keyFile for internal cluster auth.

7. **No mTLS in 0.N v1.** The 0.G.2 RS uses per-host Vault Agent + per-host PKI leaf cert + mongod.conf `net.tls.mode=requireTLS`. Extending that pattern to 11 nodes requires 11 new AppRoles + 11 JSON sidecars in the security env — substantial scope. **0.N v1 ships keyFile-only auth (no TLS on the wire)**; the 0.N.1 enhancement adds Vault Agent + mTLS to bring the sharded cluster to parity with the 0.G.2 RS posture. This is a deliberate scope trade: prove the sharding mechanic now, harden the posture in a follow-up.

8. **Simpler keyFile distribution (no per-host Vault Agent).** Operator fetches the keyFile content from KV on the build host via `vault kv get`, SCPs to each of the 11 nodes at `/etc/nexus-mongo/keyfile` (0400 mongodb:mongodb). Avoids extending the security env with 11 new AppRoles. The 0.N.1 enhancement moves to the per-host Vault Agent pattern (which also gives cert rotation).

9. **IP allocation in free OLTP slots:** cfg .74/.75/.76, shard-1 .77/.78/.79, shard-2 .80/.56/.57, mongos .58/.59. The .80→.56 decade spill mirrors the 0.L.5 SR-shared-data `.30`/`.40` slot decision when the natural decade ran out of contiguous space. MAC pool **`:C0–:CA`** (11 contiguous after the observability tier ending at `:BF`) — corrected from the initially-proposed `:8A–:94`, which collided with the analytics tier (ClickHouse `:8A–:92` + StarRocks `:93–:94`); the conflict surfaced as a runtime DHCP collision at first apply. See `feedback_mac_pool_pre_apply_audit.md` (the pre-apply MAC-uniqueness grep that now guards every new tier).

## Consequences

### Positive

- **Closes the document-store sharding gap** in the portfolio narrative. The 7 cluster adapters in the future nexus-cli phase now have a sharded Mongo target distinct from the 0.G.2 RS.
- **0.G.2 RS untouched**, preserving its PROVEN cold-rebuild state.
- **Pattern extensibility** — adding shard-3 (or more) is purely additive to the TF env: add 3 module.vm blocks + 3 entries in `local.sharded_nodes` + an additional rs.initiate iteration + a third sh.addShard call. No structural refactoring.
- **Cold-rebuild proven.** 0.N ships with `smoke-0.N.ps1` (~50 checks across 8 sections) + a cold-rebuild proof (destroy → re-apply from zero → smoke ALL GREEN). Same bar as every other tier.

### Negative

- **+12 GB RAM** (11 nodes × 2 GB shards/cfg + 1 GB mongos pair). Foundation tier RAM total after 0.N: ~64 GB. Build host (128 GB) has slack.
- **No mTLS in v1** — a deliberate scope trade. Documented as 0.N.1 enhancement. Anyone reading the portfolio at this point sees the gap explicitly.
- **Shared keyFile across cluster** = single secret blast radius. Acceptable for a lab; production would split keyFiles per cluster + use x509 user auth (the 0.N.1 enhancement direction).
- **2 shards is the MINIMUM showcase.** The sharding mechanic is proven but a casual viewer might wonder why not 3. The decision narrative + extensibility note in this ADR is the answer.

### Risks

- **MongoDB 8.0 localhost-exception interaction** (already encountered + worked around in 0.G.2) recurs here. The rs-initiate overlay uses `__system` cluster auth via the keyFile content as password — same workaround as 0.G.2. Documented in `feedback_mongodb_8_keyfile_localhost_exception.md`.
- **Destroy-cluster-leaves-config-server-state interaction.** If the operator runs `enable_mongo_cfg_*=false` (destroying config-server VMs) WITHOUT first destroying the shard cluster, the shard RSes lose their config-server pointer. Recovery requires reinstating config + re-running sh.addShard. Documented in handbook §1n.5.

## Alternatives considered

1. **Reuse 0.G.2 RS as shard-1** (8 NEW VMs total). Pros: lighter on RAM. Cons: refactors a SEALED cluster + couples two phase deliverables. Rejected.

2. **3 shard RSes** (14 NEW VMs total). Pros: stronger sharding showcase. Cons: marginal portfolio value vs 2 shards; +6 GB RAM. Deferred — 0.N.2 could add shard-3 if portfolio narrative demands.

3. **Defer 0.N entirely; consolidate on the 0.G.2 RS for Mongo demonstration.** Pros: less work. Cons: sharding is the explicit committed enhancement (2026-05-22). Rejected.

4. **Use mongodb-org-server v7.0 instead of 8.0** to avoid the localhost-exception quirk. Pros: simpler bootstrap. Cons: version-skew with 0.G.2 RS (8.0) — two versions of the same engine in the OLTP tier is operationally worse than the workaround. Rejected.

## See also

- [Phase 0.N tracker](../../../nexus-infra-oltp/memory/project_nexus_infra_0n_phase.md)
- [`role-overlay-mongo-config.tf`](../../../nexus-infra-oltp/terraform/envs/oltp-mongo-sharded/role-overlay-mongo-config.tf) — per-role mongod.conf / mongos.conf rendering
- [`role-overlay-mongo-rs-initiate.tf`](../../../nexus-infra-oltp/terraform/envs/oltp-mongo-sharded/role-overlay-mongo-rs-initiate.tf) — 3-RS init via for_each
- [`role-overlay-mongo-add-shards.tf`](../../../nexus-infra-oltp/terraform/envs/oltp-mongo-sharded/role-overlay-mongo-add-shards.tf) — sh.addShard one-shot
- [`scripts/smoke-0.N.ps1`](../../../nexus-infra-oltp/scripts/smoke-0.N.ps1) — ~50-check smoke gate
- [`docs/handbook.md` §1n](../../../nexus-infra-oltp/docs/handbook.md) — operator runbook
- [DEMO-20](../demos/DEMO-20.md) — persona demo (kill a shard primary, cluster stays writable)
- [`feedback_mongodb_8_keyfile_localhost_exception.md`](../../../nexus-infra-oltp/memory/feedback_mongodb_8_keyfile_localhost_exception.md) — the bootstrap quirk
- [`feedback_per_cluster_state_per_engine_template.md`](../../../nexus-infra-oltp/memory/feedback_per_cluster_state_per_engine_template.md) — per-engine template canon
- [planned-sharding-ha-enhancements memory](../../../nexus-infra-oltp/memory/project_planned_sharding_ha_enhancements.md) — 0.M-0.P commit narrative
