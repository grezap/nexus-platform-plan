# ADR-0041 · Phase 0.O: Vitess-sharded MySQL (Percona Server) — new repo `nexus-infra-vitess`

**Status:** accepted
**Date:** 2026-05-30
**Phase:** 0.O
**Scope:** NEW repo `grezap/nexus-infra-vitess` (tier `07-vitess`) + `nexus-platform-plan/docs/infra/vms.yaml` (new `vitess` cluster) + foundation dnsmasq reservations (v8).

## Context

The OLTP relational tier shows HA-by-**replication** (Percona XtraDB Cluster = Galera synchronous multi-master replication in 0.G.3; Patroni = PostgreSQL streaming replication in 0.G.4) but NOT relational **sharding**. Phase 0.N added document-store sharding (MongoDB `mongos`); Phase 0.O adds the **relational MySQL sharding** axis via **Vitess** — the CNCF-graduated system that shards MySQL horizontally behind a MySQL-protocol query router. Greg's committed direction (2026-05-22): a **completely separate first-class repo** (not an extension of `nexus-infra-oltp`), mirroring how 0.P Citus will be its own repo.

## Decision

Build a **Vitess-managed sharded MySQL cluster** as the new repo `nexus-infra-vitess` (tier `07-vitess`), 12 VMs:

| Role | Count | Hosts | VMnet11 | Port(s) |
|---|---|---|---|---|
| etcd topo server (global+local) | 3 | `vitess-etcd-1/2/3` | `.190/.191/.192` | 2379/2380 |
| Control plane (vtctld + VTOrc) | 1 | `vitess-control-1` | `.193` | vtctld grpc 15999 / web 15000; VTOrc 16000 |
| vtgate query router | 2 | `vitess-vtgate-1/2` | `.194/.195` | MySQL 15306 / grpc 15991 / web 15001 |
| shard-1 tablets (Percona + vttablet) | 3 | `vitess-shard1-tablet-1/2/3` | `.196/.197/.198` | vttablet grpc 16101 / web 15101; mysqld 3306 |
| shard-2 tablets (Percona + vttablet) | 3 | `vitess-shard2-tablet-1/2/3` | `.199/.200/.201` | vttablet grpc 16101 / web 15101; mysqld 3306 |

Keyspace `commerce`, **2 shards** range-split `-80` / `80-` over a `hash` vindex on the sharding key. Each shard is a Vitess "shard" = 1 PRIMARY tablet + 2 REPLICA tablets, each tablet a (vttablet sidecar + local Percona Server 8.0 mysqld) pair. VTOrc performs automated failover/reparenting.

### Key sub-decisions

1. **Separate repo, NOT an `nexus-infra-oltp` extension** (Greg, 2026-05-22). Vitess is a distinct system (its own control plane + topology server + query routers), and the portfolio reads cleaner as "MySQL sharding = its own project" alongside "PG sharding = nexus-infra-citus (0.P)". Per-cluster-state + per-engine-template canon applies within the new repo.

2. **3 tablets per shard (1 PRIMARY + 2 REPLICA)** (Greg, 2026-05-30). Matches the lab's 3-node-RS pattern everywhere else (0.G.2 Mongo RS, 0.N shards, Patroni, etcd) and gives VTOrc a quorum-friendly reparent + 2 read replicas. The leaner 2-per-shard (primary+replica+semi-sync) was the alternative; rejected for consistency.

3. **Percona Server 8.4 LTS as the mysqld flavor; Vitess v24.0.1.** *(amended 2026-06-01)* Originally locked at Percona Server 8.0 for consistency with 0.G.3's PXC (8.0.45). Switched to **8.4 LTS** after confirming (a) MySQL/Percona **8.0 reached EOL April 2026** — building a NEW cluster on an EOL engine in mid-2026 is poor portfolio optics; (b) **Vitess v24.0.1** (latest GA) supports both 8.0 and 8.4 and **VTGate advertises 8.4 by default**. Percona keeps the lab's MySQL flavor consistent with 0.G.3 (both Percona), just on the current LTS. Install: `percona-release setup ps-84-lts` → `apt install percona-server-server`. Vitess binaries from the upstream prebuilt tarball `vitess-24.0.1-*.tar.gz`. vttablet manages the mysqld lifecycle via `mysqlctld`; Percona's apt-shipped `mysql.service` is masked at bake (Vitess owns the lifecycle).

4. **etcd 3-node topology server.** Vitess needs a topo service (etcd/ZooKeeper/Consul); etcd is the default + we already have a proven etcd build pattern (0.G.4 `oltp-etcd-node`, etcd 3.5.x upstream static binaries). 3 nodes = majority quorum tolerates 1 loss. Global + local (cell `nexus`) topo both live on this etcd.

5. **2 vtgate routers, round-robin DNS `vtgate.nexus.lab`, NO VIP** (per ADR-0031, the lab's analytics/mongos write-path pattern). vtgate is stateless; clients speak the MySQL protocol to `:15306` and retry the other gate on failure. Mirrors 0.N's stateless mongos pair.

6. **vtctld + VTOrc co-located on one control node.** vtctld is the admin/topology daemon (consumed by `vtctldclient` for `ApplySchema`, `ApplyVSchema`, `Reshard`, `PlannedReparentShard`); VTOrc is the automated-failover orchestrator (1 per cell). Co-locating them on `vitess-control-1` saves a VM with no HA loss (both are control-plane, restart-recoverable; the data plane — tablets + vtgate — has no SPOF).

7. **Full mTLS now (Vault PKI on all gRPC + MySQL)** (Greg, 2026-05-30). Every Vitess gRPC channel (vtgate↔vttablet, vtctld↔vttablet, VTOrc↔vttablet, components↔etcd) + the mysqld wire + the vtgate MySQL listener get per-host Vault-PKI leaf certs (`pki_int/issue/vitess-server`), matching the lab's mTLS-everywhere standard (Kafka, OLTP, analytics). No 0.O.1 security-posture backfill (contrast 0.N, which deferred mTLS). The security env gains a `vitess-server` PKI role + per-host AppRole sidecars + KV-seeded credentials (MySQL root/app/repl users, VTOrc topo user).

8. **IP allocation `.190-.201` (VMnet11) + `.10.190-.201` (VMnet10 backplane); MAC `:CB-:D6`** — pre-apply MAC+IP audit ALL CLEAR against every foundation reservation file (per `feedback_mac_pool_pre_apply_audit.md`, the lesson from 0.N's first apply). VMnet10 carries all intra-cluster gRPC + MySQL replication; VMnet11 carries SSH + the client-facing vtgate MySQL port.

## Consequences

### Positive

- **Closes the relational-MySQL-sharding gap** in the portfolio narrative — the explicit complement to 0.G.3's Galera *replication* and 0.N's document-store sharding.
- **Reusable patterns** — etcd build pattern from 0.G.4, the round-robin-DNS-no-VIP front door from ADR-0031, the per-engine-template + per-cluster-state canon, the Vault-PKI mTLS overlay shape from every prior tier.
- **Real Vitess mechanics proven** — a `Reshard` (2→4 shards) or `MoveTables` would be a natural 0.O.1/demo extension; the v1 cold-rebuild proves the steady-state sharded keyspace.

### Negative

- **12 VMs (~28-32 GB RAM)** — the heaviest single sharding tier. Mitigated by the minimal-running-VMs discipline (stopped when not the active phase; 0.N's 11 mongo VMs were stopped to make room).
- **Full mTLS = more overlays + transient surface** — Vitess's many gRPC channels each need the cert path wired (`-grpc_cert/-grpc_key/-grpc_ca` + `-grpc_server_ca`); the first ratification will surface cert/SAN transients (chronicled in the handbook §3).
- **Vitess operational complexity** — vttablet↔mysqlctld lifecycle, `InitShardPrimary`/`PlannedReparentShard`, vschema vs schema, the topo-server bootstrap order. The TF overlay graph is longer than 0.N's (etcd → mysql/vttablet bring-up → InitShardPrimary per shard → vtgate → ApplySchema/ApplyVSchema → reshard-less seed).

### Risks

- **Topo bootstrap ordering** — vtctld/vttablet/vtgate all need etcd healthy first; tablets must register in topo before `InitShardPrimary`. The apply graph orders etcd → tablets(register) → reparent → vtgate → schema.
- **VTOrc + mTLS** — VTOrc connects to every tablet's gRPC + each mysqld; its cert + topo creds must be in place before it can reparent. Likely a first-ratification transient.
- **Percona Server 8.0 + Vitess version pinning** — Vitess release must match the Percona 8.0 minor (Vitess validates the mysqld flavor/version at vttablet start).

## Alternatives considered

1. **Extend `nexus-infra-oltp` (like 0.N did for Mongo).** Rejected per Greg's explicit "completely separate first-class project" direction (2026-05-22) — Vitess's control plane + topo server make it structurally its own system.
2. **Vanilla MySQL or MariaDB instead of Percona Server.** Rejected — Percona keeps the lab's MySQL flavor consistent with 0.G.3 PXC; Vitess supports it first-class.
3. **ZooKeeper or Consul topo instead of etcd.** Rejected — etcd is Vitess's default + we have the proven 0.G.4 etcd build pattern; the lab already runs zero ZooKeeper outside the deliberate 0.L.3 Spark exception.
4. **Defer mTLS to 0.O.1 (like 0.N).** Rejected by Greg (2026-05-30) — do full Vault-PKI mTLS now, no posture gap to backfill.
5. **2 tablets per shard.** Rejected by Greg (2026-05-30) — 3 for 3-node-RS consistency + stronger reparent quorum.

## See also

- [`feedback_mac_pool_pre_apply_audit.md`](../../../nexus-infra-oltp/memory/feedback_mac_pool_pre_apply_audit.md) — the pre-apply MAC+IP audit (ALL CLEAR for `:CB-:D6` / `.190-.201`)
- [`feedback_per_cluster_state_per_engine_template.md`](../../../nexus-infra-oltp/memory/feedback_per_cluster_state_per_engine_template.md) — per-engine template + per-cluster state canon
- [ADR-0031](./ADR-0031-analytics-client-front-door-round-robin-dns.md) — round-robin DNS front door, no VIP for write paths (vtgate follows it)
- [ADR-0040](./ADR-0040-mongodb-sharded-cluster-separate-from-0g2-rs.md) — the 0.N document-store sharding sibling
- [planned-sharding-ha-enhancements memory](../../../nexus-infra-oltp/memory/project_planned_sharding_ha_enhancements.md) — the 0.M-0.P commit narrative
