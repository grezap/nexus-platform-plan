# nexus-platform-plan

> Master implementation plan, canon specifications, and demo playbook index for the **NexusPlatform portfolio** by **Greg Zapantis** — Senior .NET & Data Engineer.

This repository is the single source of truth that links the **14 Volumes of design docs**
(`Vol00-Master-Blueprint` through `Vol13-Portfolio-Presentation`, plus the newly introduced
`Vol14-Lakehouse-Core`) to **executable work** across 14 application projects, 5 infrastructure
repositories, ~75 ADRs, ~150 database tables, and ~65 VMs.

It contains no application code. Every other repo in the portfolio references this one.

## Entry points

| You are... | Start here |
|---|---|
| Recruiter / non-technical viewer | [`docs/start-here.md`](./docs/start-here.md) — pick a 3–8 min demo scenario |
| CTO / prospective client | [`MASTER-PLAN.md`](./MASTER-PLAN.md) — full scope, phases, acceptance gates |
| **DevOps operator / lab rebuilder** | **[`docs/setup-guides.md`](./docs/setup-guides.md) — exact step-by-step replay path for every tier (28 VMs, 4 tiers): which VMs come alive in what order, how to bring each up from zero, selective-ops index ("set up only X")** |
| Engineer reading the code | [`docs/skills-coverage.md`](./docs/skills-coverage.md) — which project demonstrates what |
| Data architect | [`schemas/`](./schemas/) — enterprise DDL per project |
| DevOps reviewer | [`docs/infra/`](./docs/infra/) — VM inventory, network canon, phase gates |

## Portfolio scope at a glance

- **14 application projects** (Clean Arch / Vertical Slice / Modular Monolith / Microservices)
- **5 infrastructure repos** (vmware, swarm-nomad, k8s, shared NuGets, private registry)
- **30 enhancements** (E1–E30) layered on top of the Volume docs to reach enterprise caliber
- **14 guided demo scenarios** (DEMO-01 → DEMO-14), auto-recorded via Playwright + VHS
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

- **Phase 0 — Infrastructure** *(in flight, ~80% complete)*. Four of five infra repos are live and cold-rebuildable; the operator CLI is at `v0.5.0` (**all 5 master-plan verbs live, Phase 0.F closed**); the Kafka ecosystem tier is tagged `v0.1.0`; the **OLTP tier is SEALED 5/5** — Redis + MongoDB + Percona/ProxySQL + Patroni/etcd/HAProxy + **SQL Server FCI + Always On AG** (live-ratified 2026-05-22, `smoke-0.G.7.ps1` ALL GREEN 56/56).
- Phases closed: **0.B / 0.C / 0.D / 0.E / 0.F / 0.H** + **Phase 0.G.1-0.G.3 + 0.G.3.5** (OLTP first 3 clusters cold-rebuild proven). Phase 0.D foundation tier (Vault HA + PKI + LDAPS + Transit auto-unseal + GMSA scaffold + Vault Agents) ✅; Phase 0.E orchestration tier (3+3 Swarm + Nomad + Consul + Portainer CE, mTLS end-to-end) ✅ — tagged `v0.2.0`; Phase 0.H Kafka ecosystem tier ✅ — tagged `v0.1.0`; **Phase 0.F operator CLI ✅ tagged `v0.5.0`**; **Phase 0.G.1-0.G.3 + 0.G.3.5 ✅ all cold-rebuild proven 2026-05-18 via per-cluster envs + per-engine templates** (per the architectural canon born from 0.G.3's 16-transient stall).
- **Phase 0.G.4 (Patroni PG HA + etcd + HAProxy HA pair) ✅ CLOSED 2026-05-19**, **8 VMs** (3 patroni + 3 etcd + **2 HAProxy** with VRRP VIP `.60`, mirroring the 0.G.3 proxysql-1/2 pattern — no SPOF on the LB tier): smoke gate **152/152 ALL GREEN** end-to-end. Ratification surfaced 18 transients (PG-17 PGDG t64-bookworm fallback · patronictl 4 CLI shape · tmpfs /tmp limit on small VMs · dnsmasq nexus.local vs nexus.lab domain · etcdctl JSON leader-id field · Patroni 4 password_file unsupported in restapi.auth · Patroni 4 ignores bootstrap.users · HAProxy needs CAP_SYS_CHROOT + `default-server check` keyword · PS quote/scope traps in smoke · etc) — all permanently fixed in source (handbook §3.4 18-row chronology table).
- **Phase 0.G.7 (SQL Server FCI + Always On AG) ✅ LIVE-RATIFIED 2026-05-22**, **4 ws2025-desktop nodes** (2-node FCI `sqlfci` @ `.70.16` sharing an iSCSI LUN from nexus-gateway + 2 async AG replicas; AG Listener `sql-ag-listener` @ `.70.17`): `smoke-0.G.7.ps1` **56/56 ALL GREEN**. First Windows-fleet data cluster + first real GMSA consumer + first iSCSI shim. 40+ ratification transients fixed in source (handbook §3.5b + §3.5c). **OLTP tier SEALED (5/5).**
- Next: continue **0.G** (cluster framework + nexus-cli `IClusterAdapter` SqlFci/SqlAg adapters + System B demos), or pivot to **0.I** (observability), **0.J** (`nexus-shared`), **0.K** (`portfolio` website), **0.L** (`nexus-infra-spark` + Harbor), or app phases.

See [`CHANGELOG.md`](./CHANGELOG.md) for canon history and [`MASTER-PLAN.md`](./MASTER-PLAN.md) for the full roadmap.

## Related repos

- [`grezap/portfolio-index`](https://github.com/grezap/portfolio-index) — the public front door + skills matrix
- [`grezap/local-data-stack`](https://github.com/grezap/local-data-stack) — Tier-0 dev substrate (`v0.1.0` shipped)
- [`grezap/nexus-infra-vmware`](https://github.com/grezap/nexus-infra-vmware) — Tier-1 foundation: Vault HA + PKI + AD DS + dnsmasq gateway. **Phase 0.D fully closed** + the cross-tier Vault-side scaffolding consumed by Phase 0.E (consul/nomad/portainer PKI roles + AppRoles + per-host token sidecars) and Phase 0.H (kafka-broker PKI role + 15 AppRoles + sidecars).
- [`grezap/nexus-infra-swarm-nomad`](https://github.com/grezap/nexus-infra-swarm-nomad) — Tier-2 orchestration (Docker Swarm + Nomad + Consul + Portainer CE). **`v0.2.0` tagged 2026-05-08 — Phase 0.E fully closed.** All 6 sub-phases sealed (0.E.1 swarm bring-up · 0.E.2 Consul harden · 0.E.3 Nomad harden · 0.E.4 Portainer CE · 0.E.4e cold-rebuild gate + 3 structural fixes · 0.E.5 close-out canon batch). Cold-rebuild proven end-to-end.
- [`grezap/nexus-infra-kafka`](https://github.com/grezap/nexus-infra-kafka) — Tier-3 Kafka ecosystem (15 VMs: two 3-node KRaft clusters + Schema Registry HA pair + REST Proxy + Kafka Connect + Debezium + ksqlDB + MirrorMaker 2 cross-cluster DR pair). **`v0.1.0` tagged 2026-05-15 — Phase 0.H fully closed.** All 6 sub-phases sealed (0.H.1 KRaft bring-up · 0.H.2 broker mTLS · 0.H.3 Schema Registry + REST · 0.H.4 Connect + Debezium + ksqlDB · 0.H.5 MirrorMaker 2 + the phase exit gate · 0.H.6 close-out canon batch + cold-rebuild proof). Cold-rebuild proven end-to-end.
- [`grezap/nexus-infra-oltp`](https://github.com/grezap/nexus-infra-oltp) — Tier-4 OLTP data tier (**22 of eventual 25 VMs cold-rebuild proven**). **Phase 0.G.1 + 0.G.2 + 0.G.3 + 0.G.3.5 closed 2026-05-18** — 3 clusters from per-engine Packer templates + per-cluster Terraform states (Redis + MongoDB + Percona/ProxySQL with VRRP VIP). 0.G.3.5 was the **architectural refactor** (per-cluster state + per-engine template, born from 0.G.3's 16-transient stall + canonicalized as the rule for multi-cluster infra tiers). **Phase 0.G.4 (Patroni PG 17 HA + etcd 3.5 DCS + HAProxy 3 HA pair, 8 VMs) ✅ CLOSED 2026-05-19** end-to-end via the same per-cluster + per-engine pattern + same ratification discipline: smoke 152/152 ALL GREEN. Cumulative: **45 transients root-caused + permanently fixed across 4 clusters** (16 monolithic-0.G.3 + 11 0.G.3.5 + 18 0.G.4) — the per-cluster framework's small-blast-radius iteration loop made each one tractable. Remaining sub-phases: 0.G.7 SQL Server FCI + AG (Windows Server 2025) + 0.G's nexus-cli IClusterAdapter framework.
- [`grezap/nexus-cli`](https://github.com/grezap/nexus-cli) — operator surface; .NET 10 Native AOT, 22.75 MB win-x64 binary (under the 25 MB exit gate, 2.25 MB headroom). **`v0.5.0` tagged 2026-05-15 — Phase 0.F closed; all 5 master-plan verbs live**: `cluster-status` · `infrastructure {list, status, suspend, resume}` · `failover-test {consul-leader, nomad-leader, swarm-manager}` · `demo {list, run, record}` · **`kafka failover {east-to-west, west-to-east}`**. Live RTOs verified end-to-end: 1.55 s · 2.716 s · 21.59 s · 13.20 s · 13.57 s, all under their master-plan budgets.
- Repos below are planned; links will be added as each ships:
  - `nexus-shared` · `nexus-infra-k8s` · `nexus-infra-registry`
  - 14 application projects (see MASTER-PLAN)

## License

MIT — see [`LICENSE`](./LICENSE). Individual project repos are licensed separately.

## Contact

- **Email:** gzapas@gmail.com
- **GitHub:** [@grezap](https://github.com/grezap)
- **LinkedIn:** [grigoris-zapantis](https://www.linkedin.com/in/grigoris-zapantis-1a0638b/)
