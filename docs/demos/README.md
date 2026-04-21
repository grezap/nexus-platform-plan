# Demo Playbooks — Index

Fourteen guided scenarios that show NexusPlatform working. Each is a self-contained tour of a real workflow — no staged screenshots, no rehearsed videos. The scenarios are the acceptance evidence for the portfolio.

## Scenario catalog

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
- **CTO tour** — DEMO-08 · DEMO-13 · DEMO-10 · DEMO-03 (failure modes, operations).
- **Data architect tour** — DEMO-01 · DEMO-12 · DEMO-06 · DEMO-09 (data flow + analytics depth).
- **AI-forward tour** — DEMO-04 · DEMO-02 · DEMO-05 · DEMO-07 (ML under the hood).

Each tour stitches the recordings back-to-back with transition cards between them.
