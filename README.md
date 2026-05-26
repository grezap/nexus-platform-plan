# nexus-platform-plan

> Master implementation plan, canon specifications, and demo playbook index for the **NexusPlatform portfolio** by **Greg Zapantis** — Senior .NET & Data Engineer.

This repository is the single source of truth that links the **14 Volumes of design docs**
(`Vol00-Master-Blueprint` through `Vol13-Portfolio-Presentation`, plus the newly introduced
`Vol14-Lakehouse-Core`) to **executable work** across 14 application projects, 7 built
infrastructure repositories, ~75 ADRs, ~150 database tables, and 93 VMs (built/cold-rebuild-proven through Phase 0.L.5).

It contains no application code. Every other repo in the portfolio references this one.

## Entry points

| You are... | Start here |
|---|---|
| Recruiter / non-technical viewer | [`docs/start-here.md`](./docs/start-here.md) — pick a 3–8 min demo scenario |
| CTO / prospective client | [`MASTER-PLAN.md`](./MASTER-PLAN.md) — full scope, phases, acceptance gates |
| **DevOps operator / lab rebuilder** | **[`docs/setup-guides.md`](./docs/setup-guides.md) — exact step-by-step replay path for every tier (93 VMs, 8 tiers): which VMs come alive in what order, how to bring each up from zero, selective-ops index ("set up only X")** |
| Engineer reading the code | [`docs/skills-coverage.md`](./docs/skills-coverage.md) — which project demonstrates what |
| Data architect | [`schemas/`](./schemas/) — enterprise DDL per project |
| DevOps reviewer | [`docs/infra/`](./docs/infra/) — VM inventory, network canon, phase gates |

## Portfolio scope at a glance

- **14 application projects** (Clean Arch / Vertical Slice / Modular Monolith / Microservices)
- **7 built infrastructure repos** (vmware, swarm-nomad, kafka, oltp, analytics, lakehouse, registry) + planned (k8s, vitess/citus sharding, shared NuGets)
- **30 enhancements** (E1–E30) layered on top of the Volume docs to reach enterprise caliber
- **17 guided demo scenarios** (DEMO-01 → DEMO-17, incl. the analytics/lakehouse/registry infra tours), auto-recorded via Playwright + VHS
- **Four skill dimensions** every project demonstrates: .NET engineering & architecture, advanced SQL & analytics, Python, DevOps literacy
- **Three deployment tiers**: VMware Workstation Pro (Tier 1) → Docker Swarm + Nomad (Tier 2) → Kubernetes manifests (Tier 3)
- **Target: 72 weeks** (14 infra + 58 application), solo cadence

## How this repo is used

Every project repo (`dataflow-studio`, `tenantcore`, …) links back here for:

- Its **schema DDL** (authored in `schemas/<project>/`)
- Its **ADR index entries** (assigned in `docs/adr/index.md`)
- Its **demo playbook** (`docs/demos/DEMO-NN-*.md`)
- Its **VM assignments** (`docs/infra/vms.yaml`)
- Its **acceptance gate** (defined in `MASTER-PLAN.md`)

Changes to canon (network, enhancements, gates) land here first, then propagate to consumers.

## Status

- **Phase 0 — Infrastructure** *(in flight, ~85% complete)*. All five core infra repos are live and cold-rebuildable; the operator CLI is at `v0.5.0` (**all 5 master-plan verbs live, Phase 0.F closed**); the Kafka ecosystem tier is tagged `v0.1.0`; the **OLTP tier is SEALED 5/5** — Redis + MongoDB + Percona/ProxySQL + Patroni/etcd/HAProxy + **SQL Server FCI + Always On AG** (live-ratified 2026-05-22, `smoke-0.G.7.ps1` ALL GREEN 56/56).
- Phases closed: **0.B / 0.C / 0.D / 0.E / 0.F / 0.H** + **Phase 0.G.1-0.G.3 + 0.G.3.5** (OLTP first 3 clusters cold-rebuild proven). Phase 0.D foundation tier (Vault HA + PKI + LDAPS + Transit auto-unseal + GMSA scaffold + Vault Agents) ✅; Phase 0.E orchestration tier (3+3 Swarm + Nomad + Consul + Portainer CE, mTLS end-to-end) ✅ — tagged `v0.2.0`; Phase 0.H Kafka ecosystem tier ✅ — tagged `v0.1.0`; **Phase 0.F operator CLI ✅ tagged `v0.5.0`**; **Phase 0.G.1-0.G.3 + 0.G.3.5 ✅ all cold-rebuild proven 2026-05-18 via per-cluster envs + per-engine templates** (per the architectural canon born from 0.G.3's 16-transient stall).
- **Phase 0.G.4 (Patroni PG HA + etcd + HAProxy HA pair) ✅ CLOSED 2026-05-19**, **8 VMs** (3 patroni + 3 etcd + **2 HAProxy** with VRRP VIP `.60`, mirroring the 0.G.3 proxysql-1/2 pattern — no SPOF on the LB tier): smoke gate **152/152 ALL GREEN** end-to-end. Ratification surfaced 18 transients (PG-17 PGDG t64-bookworm fallback · patronictl 4 CLI shape · tmpfs /tmp limit on small VMs · dnsmasq nexus.local vs nexus.lab domain · etcdctl JSON leader-id field · Patroni 4 password_file unsupported in restapi.auth · Patroni 4 ignores bootstrap.users · HAProxy needs CAP_SYS_CHROOT + `default-server check` keyword · PS quote/scope traps in smoke · etc) — all permanently fixed in source (handbook §3.4 18-row chronology table).
- **Phase 0.G.7 (SQL Server FCI + Always On AG) ✅ LIVE-RATIFIED 2026-05-22**, **4 ws2025-desktop nodes** (2-node FCI `sqlfci` @ `.70.16` sharing an iSCSI LUN from nexus-gateway + 2 async AG replicas; AG Listener `sql-ag-listener` @ `.70.17`): `smoke-0.G.7.ps1` **56/56 ALL GREEN**. First Windows-fleet data cluster + first real GMSA consumer + first iSCSI shim. 40+ ratification transients fixed in source (handbook §3.5b + §3.5c). **OLTP tier SEALED (5/5).**
- **Phase 0.G analytics tier ✅ SEALED 2026-05-23** — `grezap/nexus-infra-analytics` tagged `v0.1.0`: ClickHouse (0.G.5, 3 shards × 2 replicas + 3 Keeper) + StarRocks (0.G.6, 3 FE + 3 BE shared-nothing) both live-ratified **and cold-rebuild-proven** (`smoke-0.G.5.ps1` 129/129 · `smoke-0.G.6.ps1` 73/73 GREEN). **Phase 0.G data tier COMPLETE** (OLTP `v0.1.0` + analytics `v0.1.0`).
- **Phase 0.L lakehouse + registry + analytics-extension ◐ IN PROGRESS** — `grezap/nexus-infra-lakehouse` **0.L.1 MinIO + 0.L.2 Iceberg/Nessie (dedicated PG HA) + 0.L.3 Spark HA (ZooKeeper-elected) all SEALED** (live-ratified + cold-rebuild-proven; `smoke-0.L.{1,2,3}.ps1` 41/41 · 28/28 · 28/28 GREEN; ADRs 0033-0035), `grezap/nexus-infra-registry` **0.L.4 HA Harbor SEALED 2026-05-25** (2 app nodes + dedicated PG/Redis HA + MinIO S3 blobs + Trivy + cosign + Vault OIDC; `smoke-0.L.4.ps1` 41/41 GREEN; ADR-0036), and `grezap/nexus-infra-analytics` **0.L.5 StarRocks shared-data SEALED 2026-05-26** (3 FE BDB-JE + 2 stateless Compute Nodes, internal cloud-native tables in a MinIO storage volume `s3://starrocks/`, dedicated `nexus-starrocks-app` identity + scoped `starrocks-tenant` policy, `smoke-0.L.5.ps1` 69/69 GREEN with CN-loss chaos default-on; ADR-0037). Next: **0.L.6** close-out (tags: lakehouse `v0.1.0`, registry `v0.1.0`, analytics `v0.2.0`).

### Roadmap (status 2026-05-25)

```
INFRASTRUCTURE
  1. 0.G.5/0.G.6  Analytics (ClickHouse + StarRocks)        ✅ DONE (nexus-infra-analytics v0.1.0)
  2. 0.L          Lakehouse + registry                      ◐ IN PROGRESS
       0.L.1 MinIO · 0.L.2 Iceberg · 0.L.3 Spark            ✅ SEALED (nexus-infra-lakehouse)
       0.L.4 Harbor HA                                      ✅ SEALED (nexus-infra-registry; ADR-0036)
       0.L.5 StarRocks shared-data/CN                       ✅ SEALED (nexus-infra-analytics extension; ADR-0037; smoke 69/69 with chaos)
       0.L.6 close-out (3 tags + cold-rebuild proofs)       ← NEXT
  3. 0.I          Observability (LAST — monitors full fleet)
  4. 0.M          2nd AD DC (foundation HA)
  5. 0.N          MongoDB sharded cluster (extends nexus-infra-oltp)
  6. 0.O          nexus-infra-vitess  (MySQL sharding — NEW repo)
  7. 0.P          nexus-infra-citus   (PostgreSQL sharding — NEW repo)
        ↓
  nexus-cli adapters  — 7 base + VitessAdapter + CitusAdapter + sharded-Mongo
        ↓
  0.J nexus-shared → 0.K portfolio → app projects 1–14
```

Deferred into 0.L: the **StarRocks CN / shared-data** (storage-compute-separation) tier — it needs object storage (MinIO), so it lands once 0.L MinIO is up. Build MinIO first in 0.L (Iceberg, Spark, and the StarRocks CN tier all depend on it).

See [`CHANGELOG.md`](./CHANGELOG.md) for canon history and [`MASTER-PLAN.md`](./MASTER-PLAN.md) for the full roadmap detail.

## Related repos

- [`grezap/portfolio-index`](https://github.com/grezap/portfolio-index) — the public front door + skills matrix
- [`grezap/local-data-stack`](https://github.com/grezap/local-data-stack) — Tier-0 dev substrate (`v0.1.0` shipped)
- [`grezap/nexus-infra-vmware`](https://github.com/grezap/nexus-infra-vmware) — Tier-1 foundation: Vault HA + PKI + AD DS + dnsmasq gateway. **Phase 0.D fully closed**; also the host of the **cross-tier overlays every later tier consumes** — PKI roles + per-host AppRole sidecars + sticky-seeded KV creds for swarm/kafka/oltp/analytics/lakehouse/registry, the gateway dhcp-host reservations + round-robin DNS + VRRP VIP records for all tiers, the iSCSI target for the SQL FCI (ADR-0026), and the **Vault OIDC provider** for the Harbor registry (0.L.4).
- [`grezap/nexus-infra-swarm-nomad`](https://github.com/grezap/nexus-infra-swarm-nomad) — Tier-2 orchestration (Docker Swarm + Nomad + Consul + Portainer CE). **`v0.2.0` tagged 2026-05-08 — Phase 0.E fully closed.** All 6 sub-phases sealed (0.E.1 swarm bring-up · 0.E.2 Consul harden · 0.E.3 Nomad harden · 0.E.4 Portainer CE · 0.E.4e cold-rebuild gate + 3 structural fixes · 0.E.5 close-out canon batch). Cold-rebuild proven end-to-end.
- [`grezap/nexus-infra-kafka`](https://github.com/grezap/nexus-infra-kafka) — Tier-3 Kafka ecosystem (15 VMs: two 3-node KRaft clusters + Schema Registry HA pair + REST Proxy + Kafka Connect + Debezium + ksqlDB + MirrorMaker 2 cross-cluster DR pair). **`v0.1.0` tagged 2026-05-15 — Phase 0.H fully closed.** All 6 sub-phases sealed (0.H.1 KRaft bring-up · 0.H.2 broker mTLS · 0.H.3 Schema Registry + REST · 0.H.4 Connect + Debezium + ksqlDB · 0.H.5 MirrorMaker 2 + the phase exit gate · 0.H.6 close-out canon batch + cold-rebuild proof). Cold-rebuild proven end-to-end.
- [`grezap/nexus-infra-oltp`](https://github.com/grezap/nexus-infra-oltp) — Tier-4 OLTP data tier — **SEALED 5/5, 26 VMs cold-rebuild proven.** Phase 0.G.1-0.G.4 + 0.G.7: Redis Cluster + MongoDB RS + Percona/ProxySQL (VRRP VIP `.50`) + Patroni PG 17/etcd/HAProxy HA pair (VRRP VIP `.60`) + **SQL Server FCI + Always On AG** on Windows Server 2025 (FCI `.16` + AG Listener `.17`; live-ratified 2026-05-22). Per-engine templates + per-cluster states (the 0.G.3.5 architectural refactor); ~85 transients root-caused + permanently fixed across the 5 clusters.
- [`grezap/nexus-infra-analytics`](https://github.com/grezap/nexus-infra-analytics) — Tier-4 analytics — **`v0.1.0` SEALED 2026-05-23** (15 VMs). ClickHouse (3 shards × 2 replicas + 3-node Keeper, 0.G.5) + StarRocks (3 FE + 3 BE shared-nothing, 0.G.6); round-robin DNS front door, no VIP (ADR-0031). Both live-ratified + cold-rebuild-proven.
- [`grezap/nexus-infra-lakehouse`](https://github.com/grezap/nexus-infra-lakehouse) — lakehouse tier (`08-spark`, 16 VMs) — **0.L.1 MinIO + 0.L.2 Iceberg/Nessie (dedicated PG HA) + 0.L.3 Spark HA (ZooKeeper-elected) all SEALED** (cold-rebuild-proven; ADRs 0033-0035). End-to-end Spark→Iceberg→MinIO write path.
- [`grezap/nexus-infra-registry`](https://github.com/grezap/nexus-infra-registry) — registry tier (`09-platform`, 4 VMs + VIP) — **0.L.4 HA Harbor SEALED 2026-05-25** (cold-rebuild-proven; ADR-0036): 2 stateless app nodes + dedicated PG/Redis HA datastore; MinIO S3 blobs; Trivy + cosign; Vault OIDC SSO.
- [`grezap/nexus-cli`](https://github.com/grezap/nexus-cli) — operator surface; .NET 10 Native AOT, 22.75 MB win-x64 binary (under the 25 MB exit gate, 2.25 MB headroom). **`v0.5.0` tagged 2026-05-15 — Phase 0.F closed; all 5 master-plan verbs live**: `cluster-status` · `infrastructure {list, status, suspend, resume}` · `failover-test {consul-leader, nomad-leader, swarm-manager}` · `demo {list, run, record}` · **`kafka failover {east-to-west, west-to-east}`**. Live RTOs verified end-to-end: 1.55 s · 2.716 s · 21.59 s · 13.20 s · 13.57 s, all under their master-plan budgets.
- Repos below are planned; links will be added as each ships:
  - `nexus-shared` · `nexus-infra-k8s` · `nexus-infra-vitess` · `nexus-infra-citus` (0.O/0.P sharding)
  - 14 application projects (see MASTER-PLAN)

## License

MIT — see [`LICENSE`](./LICENSE). Individual project repos are licensed separately.

## Contact

- **Email:** gzapas@gmail.com
- **GitHub:** [@grezap](https://github.com/grezap)
- **LinkedIn:** [grigoris-zapantis](https://www.linkedin.com/in/grigoris-zapantis-1a0638b/)
