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

- **v0.1.0 — Plan** (current) — canon published, no implementation yet.
- Next: Phase 0.A — VMnet20 + VMnet21 creation on the target host.

See [`CHANGELOG.md`](./CHANGELOG.md).

## Related repos

- [`grezap/portfolio-index`](https://github.com/grezap/portfolio-index) — the public front door + skills matrix
- [`grezap/local-data-stack`](https://github.com/grezap/local-data-stack) — Tier 0 dev substrate (v0.1.0 shipped)
- Repos below are planned; links will be added as each ships:
  - `nexus-shared` · `nexus-infra-vmware` · `nexus-infra-swarm-nomad` · `nexus-infra-k8s` · `nexus-infra-registry`
  - `nexus-cli`
  - 14 application projects (see MASTER-PLAN)

## License

MIT — see [`LICENSE`](./LICENSE). Individual project repos are licensed separately.

## Contact

- **Email:** gzapas@gmail.com
- **GitHub:** [@grezap](https://github.com/grezap)
- **LinkedIn:** [grigoris-zapantis](https://www.linkedin.com/in/grigoris-zapantis-1a0638b/)
