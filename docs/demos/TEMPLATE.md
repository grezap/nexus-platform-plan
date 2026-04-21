# DEMO-NN · &lt;Title&gt;

> Playbook template. Every demo file in this directory must contain all 9 sections below. CI lints for section headings.

## 1. What this shows

One paragraph. Plain language. Name the workflow and state the single insight a viewer should leave with. Avoid jargon. Include the personas this scenario targets.

## 2. Runtime + prerequisites

- **Environment target** — one of `full` · `data-engineering` · `ml` · `saas` · `microservices` · `demo-minimal` (see MASTER-PLAN §5.3).
- **VMs required** — list exact VM names from `docs/infra/vms.yaml`.
- **External services** — Kafka topics (list by name), Vault paths, registry images, S3/MinIO buckets.
- **Seed data** — which generator from `docs/demo-data/` is required; command to run it.
- **Expected duration** — wall-clock.
- **Reset command** — `nexus-cli demo run DEMO-NN --reset`.

## 3. Architecture snapshot

Single interactive SVG rendered by the portfolio site (link). Static fallback PNG at `assets/DEMO-NN/architecture.png`. List the components by role and note the data paths traversed in this demo.

## 4. Step-by-step script

Numbered steps. Each step contains: **Action**, **Expected observable**, **Screenshot ref**. This is the section viewers read while they watch the recording. Aim for 8–15 steps per scenario.

**Worked example (for authoring reference — delete in real playbooks):**

1. **Action.** Run `nexus-cli demo run DEMO-01` on the host workstation.
   **Expected observable.** The CLI prints `starting DEMO-01: Place an order, watch it flow everywhere` followed by a readiness probe summary: seven green checks (SQL AG, Kafka East brokers, Schema Registry, StarRocks FE, ClickHouse, Grafana, Jaeger). The terminal then pauses with `press Enter to place the order…`
   **Screenshot.** `assets/DEMO-01/step-01.png`
2. **Action.** Press Enter.
   **Expected observable.** The CLI issues a POST to the Orders service (`nexus-platform`) through the Gateway VIP. The HTTP response contains an `X-Trace-Id` header that the CLI records. The CLI then opens three browser tabs via the OS default handler: Grafana (dataflow-studio dashboard), Jaeger (service=gateway, lookup=trace-id), Seq (filtered on trace-id).
   **Screenshot.** `assets/DEMO-01/step-02.png`
3. **Action.** Switch to the Jaeger tab.
   **Expected observable.** A distributed trace with 14 spans across `gateway → orders-api → outbox-publisher → kafka (topic=orders.v1) → dataflow-studio.cdc-ingestor → schema-registry (lookup) → starrocks-sink → clickhouse-sink`. End-to-end span duration under 450 ms.
   **Screenshot.** `assets/DEMO-01/step-03.png`

Real playbooks continue to step N with the same structure.

## 5. Observability trail

- **Grafana** — dashboard UID(s) and panel names that light up during the demo.
- **Jaeger** — service names to filter on and expected trace depth / span count.
- **Seq** — saved signal query name or the URL-encoded filter expression.
- **Marquez** — lineage asset the demo touches (if applicable).
- **URLs** — every URL copy-pasteable (`http://obs-metrics.nexus.local:3000/d/...`).

## 6. Code pointers

List the relevant files in the project repo(s) with their purpose. One bullet per file. *Filled in when the project ships.*

## 7. Variations

How to run the same scenario with altered conditions (e.g., simulated network latency, cache cold vs. warm, tenant A vs. tenant B). *Filled in when the project ships.*

## 8. Troubleshooting

Common failure modes and their recovery paths. The **panic button** command (from the runbook) is repeated here. *Filled in when the project ships.*

## 9. What this proves

Map the scenario to the four portfolio dimensions (MASTER-PLAN §2). One bullet per dimension — .NET engineering + architecture, advanced SQL + analytics, Python, DevOps — each citing the exact artefact in the scenario that demonstrates that dimension.

---

### Asset conventions

- **Screenshots** — `docs/demos/assets/DEMO-NN/step-XX.png` (PNG, viewport 1920×1080, cropped per step).
- **Architecture diagram** — `docs/demos/assets/DEMO-NN/architecture.png` (SVG source in portfolio repo).
- **Full recording** — `docs/demos/assets/DEMO-NN/recording.mp4` and `recording.gif`.
- **VHS tape** — `docs/demos/assets/DEMO-NN/terminal.tape`.
- **Playwright test** — `tests/demos/DEMO-NN.spec.ts` in the owning project repo.
