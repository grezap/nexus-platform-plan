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

- **Phase 0 — Infrastructure** *(in flight, ~75% complete)*. Four of five infra repos are live and cold-rebuildable; the operator CLI is at `v0.5.0` (**all 5 master-plan verbs live, Phase 0.F closed**); the Kafka ecosystem tier is tagged `v0.1.0`; the OLTP tier has 3 of 5 sub-clusters (Redis + MongoDB + Percona/ProxySQL) cold-rebuild proven.
- Phases closed: **0.B / 0.C / 0.D / 0.E / 0.F / 0.H** + **Phase 0.G.1-0.G.3 + 0.G.3.5** (OLTP tier first 3 clusters). Phase 0.D foundation tier (Vault HA + PKI + LDAPS + Transit auto-unseal + GMSA scaffold + Vault Agents) ✅; Phase 0.E orchestration tier (3+3 Swarm + Nomad + Consul + Portainer CE, mTLS end-to-end) ✅ — tagged `v0.2.0`; Phase 0.H Kafka ecosystem tier (two KRaft clusters on mTLS + Schema Registry + Connect + Debezium + ksqlDB + MirrorMaker 2 DR pair) ✅ — tagged `v0.1.0`; **Phase 0.F operator CLI ✅ tagged `v0.5.0` (all 5 verbs: `cluster-status` · `infrastructure` · `failover-test` · `demo` · `kafka failover`)**; **Phase 0.G.1 (6-node Redis Cluster mTLS) + 0.G.2 (3-node MongoDB RS mTLS+keyFile) + 0.G.3 (3 PXC + 2 ProxySQL + VRRP VIP) ✅ all cold-rebuild proven end-to-end 2026-05-18 via per-cluster envs + per-engine templates** (per the [feedback_per_cluster_state_per_engine_template.md](../../) architectural canon born from 0.G.3's 16-transient stall — 0.G.3.5 refactor closed in the same window).
- Next: continue **0.G** (Patroni / SQL FCI+AG / cluster framework + nexus-cli adapters), or pivot to **0.I** (observability roll-out), **0.J** (`nexus-shared` NuGet family), **0.K** (`portfolio` website shell), **0.L** (`nexus-infra-spark` + Harbor), or to the application phases (Vol01-Vol13 starting with `dataflow-studio`).

See [`CHANGELOG.md`](./CHANGELOG.md) for canon history and [`MASTER-PLAN.md`](./MASTER-PLAN.md) for the full roadmap.

## Related repos

- [`grezap/portfolio-index`](https://github.com/grezap/portfolio-index) — the public front door + skills matrix
- [`grezap/local-data-stack`](https://github.com/grezap/local-data-stack) — Tier-0 dev substrate (`v0.1.0` shipped)
- [`grezap/nexus-infra-vmware`](https://github.com/grezap/nexus-infra-vmware) — Tier-1 foundation: Vault HA + PKI + AD DS + dnsmasq gateway. **Phase 0.D fully closed** + the cross-tier Vault-side scaffolding consumed by Phase 0.E (consul/nomad/portainer PKI roles + AppRoles + per-host token sidecars) and Phase 0.H (kafka-broker PKI role + 15 AppRoles + sidecars).
- [`grezap/nexus-infra-swarm-nomad`](https://github.com/grezap/nexus-infra-swarm-nomad) — Tier-2 orchestration (Docker Swarm + Nomad + Consul + Portainer CE). **`v0.2.0` tagged 2026-05-08 — Phase 0.E fully closed.** All 6 sub-phases sealed (0.E.1 swarm bring-up · 0.E.2 Consul harden · 0.E.3 Nomad harden · 0.E.4 Portainer CE · 0.E.4e cold-rebuild gate + 3 structural fixes · 0.E.5 close-out canon batch). Cold-rebuild proven end-to-end.
- [`grezap/nexus-infra-kafka`](https://github.com/grezap/nexus-infra-kafka) — Tier-3 Kafka ecosystem (15 VMs: two 3-node KRaft clusters + Schema Registry HA pair + REST Proxy + Kafka Connect + Debezium + ksqlDB + MirrorMaker 2 cross-cluster DR pair). **`v0.1.0` tagged 2026-05-15 — Phase 0.H fully closed.** All 6 sub-phases sealed (0.H.1 KRaft bring-up · 0.H.2 broker mTLS · 0.H.3 Schema Registry + REST · 0.H.4 Connect + Debezium + ksqlDB · 0.H.5 MirrorMaker 2 + the phase exit gate · 0.H.6 close-out canon batch + cold-rebuild proof). Cold-rebuild proven end-to-end.
- [`grezap/nexus-infra-oltp`](https://github.com/grezap/nexus-infra-oltp) — Tier-4 OLTP data tier (14 of eventual 25 VMs: 6-node Redis Cluster + 3-node MongoDB Replica Set + 3-node Percona XtraDB Cluster + 2-node ProxySQL with VRRP-floated VIP). **Phase 0.G.1 + 0.G.2 + 0.G.3 + 0.G.3.5 closed 2026-05-18** — all 3 clusters cold-rebuild proven end-to-end from per-engine Packer templates + per-cluster Terraform states. 0.G.3.5 was the **architectural refactor** (per-cluster state + per-engine template, born from 0.G.3's 16-transient stall on the monolithic design + canonicalized as the architectural rule for multi-cluster infra tiers). 27 distinct transients root-caused + permanently fixed in source (16 monolithic + 11 refactor) including the previously-unsolved Galera SST joiner sync (PXC 8.0's `wsrep_sst_auth` moved [mysqld]→[sst] + wsrep.cnf newline gap). Remaining sub-phases: 0.G.4 Patroni + etcd + HAProxy · 0.G.7 SQL Server FCI + AG (Windows Server 2025) + 0.G's nexus-cli IClusterAdapter framework.
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
