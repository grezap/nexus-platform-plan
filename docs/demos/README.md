# Demo Playbooks — Index

Guided scenarios that show NexusPlatform working. Each is a self-contained tour of a real workflow — no staged screenshots, no rehearsed videos. The scenarios are the acceptance evidence for the portfolio.

Two series: **DEMO-01..17** are the planned **application + infra scenarios** (they light up as their underlying capability ships), and **DEMO-18..32** are **realized infra + CLI tours** — each ships alongside a sealed `nexus-infra-*` tier or a `nexus-cli` adapter/verb release and is live-verified today.

## Scenario catalog (DEMO-01..17 — application + infra scenarios)

| ID | Title | Projects touched | Persona | Duration | Status |
|---|---|---|---|---|---|
| [DEMO-01](./DEMO-01.md) | Place an order, watch it flow everywhere | dataflow-studio · nexus-platform · obs stack | data-architect | 6 min | planned |
| [DEMO-02](./DEMO-02.md) | Detect a fraudulent transaction in real time | sentinelml · streamcore | AI-forward | 5 min | planned |
| [DEMO-03](./DEMO-03.md) | Onboard a new SaaS tenant | tenantcore | CTO | 4 min | planned |
| [DEMO-04](./DEMO-04.md) | Ask LocalMind about your own portfolio | localmind | AI-forward | 5 min | planned |
| [DEMO-05](./DEMO-05.md) | Inspect a defect in a product image | visioncore | AI-forward | 4 min | planned |
| [DEMO-06](./DEMO-06.md) | Forecast next-hour trading ticks | chronosight · lakehouse-core | data-architect | 6 min | planned |
| [DEMO-07](./DEMO-07.md) | Personalized recommendations from interactions | recoengine | AI-forward | 5 min | planned |
| [DEMO-08](./DEMO-08.md) | Survive a Kafka region failure | streamcore · infra | CTO | 7 min | planned |
| [DEMO-09](./DEMO-09.md) | Catch a query regression with AI rewrite | querylens · localmind | data-architect | 6 min | planned |
| [DEMO-10](./DEMO-10.md) | Field-sync offline-first | fieldsync | CTO | 5 min | planned |
| [DEMO-11](./DEMO-11.md) | Native Windows DBA tour | nexus-desk · SQL AG | recruiter | 4 min | planned |
| [DEMO-12](./DEMO-12.md) | Lakehouse Bronze to Silver to Gold | lakehouse-core · dataflow-studio | data-architect | 8 min | planned |
| [DEMO-13](./DEMO-13.md) | Chaos: kill a broker, survive gracefully | streamcore · infra | CTO | 6 min | planned |
| [DEMO-14](./DEMO-14.md) | Traverse a single order's entire journey | META — all 14 projects | recruiter | 10 min | planned |
| [DEMO-15](./DEMO-15.md) | Analytics warehouse: sharded + replicated, survive a node loss | analytics infra (ClickHouse + StarRocks) | data-architect · CTO | 7 min | planned |
| [DEMO-16](./DEMO-16.md) | Lakehouse: object store + table format + compute, survive a node loss | lakehouse infra (MinIO + Iceberg + Spark) | data-architect | 8 min | planned |
| [DEMO-17](./DEMO-17.md) | Container registry: push, scan, sign — survive a node loss | registry infra (Harbor HA) | CTO · DevOps | 6 min | planned |

## Realized tours (DEMO-18..32 — infra failure-mode + `nexus-cli` operator tours)

These ship with a sealed tier or a `nexus-cli` release and are **live-verified today** (the System B JSON demos under [`nexus-cli/docs/demos/`](https://github.com/grezap/nexus-cli/tree/main/docs/demos) are their executable form).

| ID | Title | Projects touched | Persona | Status |
|---|---|---|---|---|
| [DEMO-18](./DEMO-18.md) | StarRocks shared-data: storage-compute separation, survive a CN loss | analytics infra (StarRocks-SD) | data-architect | done |
| [DEMO-19](./DEMO-19.md) | Foundation HA: kill the primary AD DC — auth + DNS survive | foundation infra (2-DC AD) | CTO | done |
| [DEMO-20](./DEMO-20.md) | MongoDB sharded: kill a shard primary — cluster stays writable | oltp infra (mongo-sharded) | data-architect | done |
| [DEMO-21](./DEMO-21.md) | Vitess-sharded MySQL: kill a shard primary — VTOrc auto-reparents | vitess infra | data-architect | done |
| [DEMO-22](./DEMO-22.md) | Citus-sharded PostgreSQL: kill a worker Patroni leader — VIP follows | citus infra | data-architect | done |
| [DEMO-23](./DEMO-23.md) | Drive the Vault trust root from the CLI — step-down, snapshot, recover-ha | nexus-cli · vault | SRE · DevOps | live |
| [DEMO-24](./DEMO-24.md) | Drive the orchestration tier from the CLI — three-raft failover, drain, cert-rotate | nexus-cli · swarm | SRE · DevOps | live |
| [DEMO-25](./DEMO-25.md) | Drive the observability tier from the CLI — VRRP cutover, ring scale-out, honest health | nexus-cli · observability | SRE | live |
| [DEMO-26](./DEMO-26.md) | Drive the lakehouse tier from the CLI — one tool over MinIO + Iceberg/Nessie + Spark + ZK | nexus-cli · lakehouse | SRE · data-architect | live |
| [DEMO-27](./DEMO-27.md) | Drive the Harbor registry tier from the CLI — app pair + datastore pair + MinIO | nexus-cli · registry | CTO · DevOps | live |
| [DEMO-28](./DEMO-28.md) | Day-2 capacity ops from the CLI — vertical resize, cluster-safety gate, guarded restore | nexus-cli | SRE · DevOps | live |
| [DEMO-29](./DEMO-29.md) | Lakehouse catalog DB failover — iceberg-pg VRRP cutover, controlled DR re-seed | nexus-cli · lakehouse | SRE · data-architect | live |
| [DEMO-30](./DEMO-30.md) | Harbor datastore failover — registry-db VRRP cutover, controlled DR re-seed | nexus-cli · registry | CTO · DevOps | live |
| [DEMO-31](./DEMO-31.md) | Vitess engine-native backup — `file` BackupStorage on NFS + xtrabackup, restore onto a replica | nexus-cli · vitess | SRE · data-architect | live |
| [DEMO-32](./DEMO-32.md) | Sharded-Mongo wire mTLS — zero-downtime online cert rotation (no re-election) | nexus-cli · mongo-sharded | SRE · data-architect | live |

## Playbook template enforcement

Every demo file in this directory conforms to [`TEMPLATE.md`](./TEMPLATE.md). The template has **9 required sections**; CI lints every playbook against the template structure and rejects missing sections, and the acceptance gate for each project (MASTER-PLAN §6) requires at least one demo playbook passing lint.

## Auto-recording pipeline

Recordings are produced by the build; no human captures video manually.

- **Terminal scenes** — [Charm VHS](https://github.com/charmbracelet/vhs) `.tape` scripts per demo. One tape per terminal scene. Output: MP4 + GIF at a fixed 120×30 viewport.
- **Browser scenes** — Playwright tests with `video: 'on'` and `trace: 'on'`. One test per browser scene. Output: WebM transcoded to MP4.
- **Concatenation** — `ffmpeg -f concat` assembles the terminal and browser scenes into the final deliverable.
- **Trigger** — `nexus-cli demo record --all` iterates every playbook; CI runs this on release tags.
- **Output path** — `docs/demos/assets/DEMO-NN/recording.{mp4,gif}` plus per-step stills at `docs/demos/assets/DEMO-NN/step-XX.png`.

## `nexus-cli demo` subcommand surface

| Command | Purpose |
|---|---|
| `nexus-cli demo list` | List all demos with status and duration. |
| `nexus-cli demo run DEMO-NN` | Execute the demo against the currently-booted environment. Idempotent. |
| `nexus-cli demo run DEMO-NN --reset` | Restore prerequisite state (truncate tables, reset topics) before running. |
| `nexus-cli demo trail DEMO-NN` | Open Grafana / Jaeger / Seq pre-filtered to the trace the demo will produce. |
| `nexus-cli demo status` | Show last-run outcome and timings per demo. |
| `nexus-cli demo record DEMO-NN` | Re-record assets for one demo. |
| `nexus-cli demo record --all` | Full re-record; used in CI on release tags. |

## Live Tour grouping

The portfolio website's Live Tour groups scenarios by persona:

- **Recruiter tour** — DEMO-11 · DEMO-14 · DEMO-03 (highest "wow", lowest prerequisite).
- **CTO tour** — DEMO-08 · DEMO-13 · DEMO-15 · DEMO-17 · DEMO-10 · DEMO-03 (failure modes, operations).
- **Data architect tour** — DEMO-01 · DEMO-12 · DEMO-15 · DEMO-16 · DEMO-06 · DEMO-09 (data flow + analytics depth).
- **AI-forward tour** — DEMO-04 · DEMO-02 · DEMO-05 · DEMO-07 (ML under the hood).
- **Operator / SRE tour** — DEMO-23 · DEMO-24 · DEMO-25 · DEMO-26 · DEMO-27 · DEMO-28 · DEMO-29 · DEMO-30 · DEMO-31 · DEMO-32 (drive + recover every tier from one `nexus-cli` binary — failover, cert-rotate, scale, guarded restore, DR re-seed, engine-native backup, zero-downtime mTLS rotation).

Each tour stitches the recordings back-to-back with transition cards between them.
