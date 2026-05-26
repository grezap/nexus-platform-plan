# ADR-0038 — Observability tier topology: Grafana LGTM stack on MinIO, 14 VMs HA, Grafana VRRP-VIP front door, hybrid shipper

- **Status:** accepted
- **Date:** 2026-05-26
- **Phase:** 0.I (new repo `grezap/nexus-infra-observability`; foundation tier `01-foundation`)
- **Supersedes:** the original `obs-{metrics,tracing,logging}` singleton reservation in `nexus-platform-plan/docs/infra/vms.yaml` (3 single-VM rows at `.90`/`.93`/`.94` — drafted pre-ADR-0025, never built)
- **Relates to:** [ADR-0025](./ADR-0025-ha-promise-covers-lb-tier.md) (LB HA rule — gates this ADR), [ADR-0031](./ADR-0031-analytics-client-front-door-round-robin-dns.md) (RR-DNS alternative for write paths), [ADR-0033](./ADR-0033-minio-distributed-erasure-coded-object-storage.md) (MinIO S3 backend), [ADR-0034](./ADR-0034-iceberg-catalog-nessie-pg-master-replica.md) + [ADR-0036](./ADR-0036-harbor-registry-ha.md) (dedicated-PG-HA-pair pattern reused here for Grafana state)

## Context

Phase 0.I is the last infrastructure phase before the application phases (1–14). It adds the observability tier — the **monitor-of-everything** that watches the 93 already-built VMs across 6 lab tiers (foundation · orchestration · kafka · OLTP 5/5 · analytics · lakehouse · registry).

The `vms.yaml` carried a three-row reservation since the original master-plan:

```
- obs-metrics  (.70.90, 4 vCPU / 12 GB / 120 GB) — Prometheus + VictoriaMetrics + Grafana + Alertmanager + Karma + Marquez
- obs-tracing  (.70.93, 2 vCPU /  8 GB /  80 GB) — Jaeger + OTel Collector
- obs-logging  (.70.94, 2 vCPU /  8 GB / 120 GB) — Seq + Vector
```

Three things are inconsistent with present canon, so the reservation is retired and replaced wholesale:

1. **Singletons** — three single VMs is exactly the SPOF shape ADR-0025 named "hollow HA." The dashboards' single URL (Grafana) must not be a SPOF — the observability tier is precisely what an operator needs **most** when something is failing, so it cannot itself be the weakest link.
2. **`Prometheus + VictoriaMetrics` co-located** — redundant TSDBs. Pick one (or pair them as scrape→long-term-store), don't double-up on one VM.
3. **Marquez on `obs-metrics`** — Marquez is OpenLineage UI (data-lineage), not metrics. It already has a dedicated row at `.127` under `platform-tools` for future 0.J. Per the DRY canon ([[feedback_dry_single_source_of_truth]]), it stays there; the obs tier does not re-host it.

Five either/or decisions were sealed with Greg 2026-05-26:

- **Stack composition = the Grafana LGTM stack** — Prometheus + Grafana + **L**oki + **T**empo + Alertmanager. C# and Python both get equal-class treatment via OpenTelemetry SDKs + Serilog's Loki sink (C#) + `python-logging-loki`/OTel logs (Py). The reserved-row Seq + Jaeger combo was rejected — Seq Free Edition is single-node only (no FOSS HA) and would split the C# devs into a private logs UI separate from the rest of the stack.
- **HA topology = 3-node clusters where the engine supports it** — Loki simple-scalable ring × 3, Tempo scalable × 3, Alertmanager mesh × 2 (co-located on the Prom pair). Prometheus stays as a 2-VM HA pair (each Prom scrapes every target independently; Grafana dedups via datasource). Grafana itself is a 2-VM active-active pair (shared PG state).
- **Grafana front door = 2-node HA pair behind VRRP VIP** (the ADR-0025 canonical pattern — mirrors 0.G.3 proxysql `.50`, 0.G.4 haproxy-pg `.60`, 0.L.2 iceberg-db `.151`, 0.L.4 registry-db `.119`). Operators bookmark **one URL**: `https://grafana.nexus.lab/`. Write-path endpoints (Prom remote-write, Loki push, Tempo OTLP ingest, OTel Collector) stay on round-robin DNS per ADR-0031 — clients retry, no VIP needed there.
- **Shipper model = hybrid** — Prometheus *pulls* infra metrics by scraping `node_exporter` on every VM; Vector *pushes* logs from `/var/log/*` + journald to Loki; apps *push* traces via OTLP to the OTel Collector pair. No fleet-wide Alloy/OTel-Collector unification (cleanest blueprint but would require a Packer-bake refresh of every existing tier template — deferred as a future enhancement). The hybrid matches the existing scrape-friendly fleet.
- **Storage backend for logs + traces = the existing 0.L.1 MinIO** (dedicated `nexus-loki-app` + `nexus-tempo-app` tenants with scoped policies — mirrors the 0.L.5 SR-shared-data tenant pattern). Reuses the lakehouse object store; Grafana PG holds only Grafana's own state.

## Decision

Deploy the **Grafana LGTM stack** as a new tier `01-foundation` (existing dir convention) inside a new repo `grezap/nexus-infra-observability`, with **14 VMs + 2 VRRP VIPs** organised as below.

### Topology

| # | Cluster | VMs | VMnet11 IPs | VMnet10 backplane | RAM | Disk | Role |
|---|---|---|---|---|---|---|---|
| 1 | **Prometheus + Alertmanager HA** | `prom-1`, `prom-2` | `70.170`/`.171` | `10.90.170`/`.171` | 4 GB ea | 80 GB | Both Proms scrape every target (datasource dedup in Grafana); Alertmanager mesh co-resident on both nodes |
| 2 | **Loki simple-scalable** | `loki-1/2/3` | `70.172`–`.174` | `10.90.172`–`.174` | 4 GB ea | 40 GB | Each node runs read + write + backend; memberlist gossip ring; MinIO S3 backend (`bucket=loki`, tenant `nexus-loki-app`) |
| 3 | **Tempo scalable** | `tempo-1/2/3` | `70.175`–`.177` | `10.90.175`–`.177` | 4 GB ea | 40 GB | Each node runs distributor + ingester + querier + query-frontend + compactor (single-binary scalable mode); memberlist ring; MinIO S3 backend (`bucket=tempo`, tenant `nexus-tempo-app`); OTLP receivers on `:4317`/`:4318` |
| 4 | **Grafana HA** | `grafana-1`, `grafana-2` | `70.178`/`.179` | `10.90.178`/`.179` | 3 GB ea | 40 GB | Active-active over shared PG state; sessions in PG; pre-provisioned datasources point at Prom HA + Loki ring + Tempo ring; admin password sticky-seeded in Vault KV |
| 5 | **Grafana PG HA** | `grafana-pg-1`, `grafana-pg-2` | `70.180`/`.181` | `10.90.180`/`.181` | 2 GB ea | 60 GB | PG 17 streaming replication + keepalived VRRP — mirrors the 0.L.2 iceberg-db / 0.L.4 registry-db pattern |
| 6 | **OTel Collector pair** | `otel-collector-1`, `otel-collector-2` | `70.182`/`.183` | `10.90.182`/`.183` | 2 GB ea | 40 GB | OTLP receivers (gRPC `:4317`, HTTP `:4318`); routes traces → Tempo, metrics → Prom remote-write, logs → Loki |
|   | **Grafana VRRP VIP** | (no VM) | `70.184` | — | — | — | `grafana.nexus.lab`; floats between `grafana-1` (MASTER prio 110) and `grafana-2` (BACKUP prio 100); unicast VRRP; cert IP-SAN includes `.184` |
|   | **Grafana PG VRRP VIP** | (no VM) | `70.185` | — | — | — | `grafana-db.nexus.lab`; floats between `grafana-pg-1` (MASTER prio 110) and `grafana-pg-2` (BACKUP prio 100); unicast VRRP; cert IP-SAN includes `.185` |

**Total: 14 VMs + 2 VIPs. Fleet 93 → 107.** Aggregate RAM 44 GB; aggregate disk 580 GB. Well inside the build host's 256 GB / 5.37 TB headroom.

### Network conventions honoured

- **VMnet10 backplane decade** `10.90.x` already canonically maps to "obs/platform" per `vms.yaml` line 46. All 14 obs VMs sit in that decade.
- **VMnet11 mgmt decade** uses `.170–.185` — a contiguous block in the free `.161–.199` range (just past `nexusdesk-dev` at `.160`). Adjacent free space remains for future obs growth (Mimir long-term metrics, distributed Tempo, additional Loki replicas).
- **Dual-NIC** on every VM. mTLS via per-host `obs-server` Vault PKI leaf cert. The cert's `allowed_domains` enumerate all 14 hostnames + the two VIPs in bare, `.nexus.lab`, and `.observability.nexus.lab` forms (so `verify-full` against either VIP validates regardless of which node currently holds it).

### Front-door pattern

- **Human UI (Grafana):** VRRP VIP `.184` → `grafana.nexus.lab`. One URL bookmarked by operators; atomic sub-second failover; cert IP-SAN-validated. This is the ADR-0025 canonical pattern — same shape proven 4× already (proxysql, haproxy-pg, iceberg-db, registry-db).
- **Machine endpoints (Prom remote-write, Loki push, Tempo OTLP, OTel Collector):** round-robin DNS per ADR-0031. `prometheus.nexus.lab` (2 A-records), `loki.nexus.lab` (3 A-records), `tempo.nexus.lab` (3 A-records), `otel.nexus.lab` (2 A-records). Clients (Vector, app SDKs) retry on connection failure — no VIP needed because there is no fixed-endpoint SPOF in the write path.
- **Grafana PG:** VRRP VIP `.185` → `grafana-db.nexus.lab`. Grafana's `database.host` points at the VIP; PG primary failover triggers VIP failover (keepalived `check_pg_isready` weight=-30).

### Storage backend on MinIO

Two new MinIO tenants, mirroring 0.L.5's `nexus-starrocks-app` pattern:

- **`nexus-loki-app`** service account + scoped `loki-tenant` policy → `s3:*` only on `arn:aws:s3:::loki/*` + bucket listing. Key/secret KV-seeded at `nexus/observability/loki/s3-{access,secret}-key`.
- **`nexus-tempo-app`** service account + scoped `tempo-tenant` policy → `s3:*` only on `arn:aws:s3:::tempo/*` + bucket listing. Key/secret KV-seeded at `nexus/observability/tempo/s3-{access,secret}-key`.

Both tenants land via a new overlay `nexus-infra-lakehouse/terraform/envs/lakehouse-minio/role-overlay-minio-observability-tenants.tf` (alongside the existing `role-overlay-minio-bucket-bootstrap.tf` and `role-overlay-minio-starrocks-tenant.tf`). The `loki` and `tempo` buckets are created by the same overlay.

### Shipper model — hybrid (decisions Q4)

- **Metrics pull (Prom scrape):** `prometheus-node-exporter` on every Linux VM + `windows_exporter` on ws2025 desktops, listening on `:9100` (`:9182` Windows). Engine-specific exporters added per tier where they exist as canonical sidecars (`kafka-exporter` on each kafka broker, `postgres-exporter` on Patroni nodes + iceberg-pg + registry-pg + grafana-pg, `redis-exporter`, `mongodb-exporter`, `mysqld-exporter` for Percona, `clickhouse` native `/metrics`, `starrocks` native `/metrics`, MinIO native `/minio/v2/metrics/cluster`, Vault native, Consul native, Nomad native, Docker daemon `/metrics`). Both Proms scrape every target via service-discovery file (Terraform-rendered from `vms.yaml` consumers list).
- **Logs push (Vector):** `vector` baked into the deb13 baseline; default config tails journald + `/var/log/syslog` + `/var/log/auth.log` + engine-specific log files; structures into JSON; pushes to `https://loki.nexus.lab:3100/loki/api/v1/push`. ws2025 desktops use `winlogbeat` → `vector` on the obs tier as a relay.
- **Traces push (app SDKs):** apps emit OTLP/gRPC to `https://otel.nexus.lab:4317` (or HTTP `:4318`). OTel Collector pair routes traces → Tempo, also accepts metrics + logs (so apps that prefer all-three-via-OTLP can do that uniformly).

**Why not unified Grafana Alloy on every VM?** Cleanest blueprint, but it would require a Packer-bake refresh of every existing tier template (kafka-node, oltp-*-node, analytics-*-node, lakehouse-*-node, registry-node, swarm-node, deb13 baseline) plus the ws2025-desktop template — ~9 templates × ~6 minute bake each = a long retrofit. Tracked as a future enhancement (post-Phase-0). The hybrid Prom-scrape + Vector + OTLP path is battle-tested and doesn't require fleet-wide bakes.

### mTLS, identity, KV

- **PKI role `observability-server`** — new role under `pki_int/`. `allowed_domains` = 14 hostnames + 2 VIPs + bare + `.nexus.lab` + `.observability.nexus.lab` forms. 90-day TTL leaf certs per [[feedback_smoke_gate_probe_robustness]].
- **14 per-host AppRoles** + 14 narrow policies (PKI issue + KV read scoped to `nexus/observability/<role>/*` + token self).
- **Sticky-seeded KV creds** at `nexus/observability/`:
  - `grafana/{admin-password,session-secret,oauth-client-secret}` (for future SSO)
  - `grafana-pg/{superuser-password,replication-password,grafana-db-password}`
  - `loki/{s3-access-key,s3-secret-key,ring-secret}` (the ring-secret seeds Loki's memberlist gossip)
  - `tempo/{s3-access-key,s3-secret-key,ring-secret}`
  - `prometheus/{alertmanager-webhook,slack-webhook}` (for alert routing — placeholder for now)
  - `otel-collector/{cert-bundle-version}` (rotation marker)

All KV objects have field `value` (binary creds) or `password` (passwords) per existing canon.

### Sub-phase plan (7 sub-phases, ~2-3 weeks)

| Sub | What | Bring-up order |
|---|---|---|
| 0.I.1 | Prom HA + Alertmanager (2 VMs) | first — gives a metrics surface for the rest of the build |
| 0.I.2 | Loki simple-scalable on MinIO (3 VMs) | depends on 0.L.1 MinIO |
| 0.I.3 | Tempo scalable on MinIO (3 VMs) | depends on 0.L.1 MinIO |
| 0.I.4 | Grafana HA pair + Grafana PG HA (2+2 VMs + 2 VIPs) | depends on 0.I.1/0.I.2/0.I.3 for datasource pre-provisioning |
| 0.I.5 | OTel Collector pair (2 VMs) | depends on 0.I.1/0.I.2/0.I.3 (the export targets) |
| 0.I.6 | Fleet-wide shipper rollout (Vector + node_exporter retrofit on the other 9 templates) | depends on 0.I.1-0.I.5 |
| 0.I.7 | Close-out — System A DEMO-15 (full-fleet observability tour) + System B JSON demos + ADR/glossary/skills-coverage sweep + tag `grezap/nexus-infra-observability v0.1.0` | last |

Each sub-phase ships: per-engine Packer template, per-cluster TF env, operator wrapper script (`observability.ps1`), smoke gate (`smoke-0.I.x.ps1`), handbook playbook (input · expected · observe · proves · prereqs), cold-rebuild proof. Per the [[per-cluster-state-per-engine-template]] canon — never one monolith.

### Acceptance gates

The phase-exit smoke gate per ADR-0025 includes the 5-step VIP failover sequence on the Grafana VIP:

1. Both grafana nodes pass health check (`/api/health` returns 200, both Prom datasources reachable, Loki ring `/ready`, Tempo ring `/ready`).
2. Grafana VIP `.184` bound on exactly one node (`grafana-1` MASTER).
3. Stop `grafana-1` keepalived → VIP migrates to `grafana-2` within 3 s.
4. `https://grafana.nexus.lab/api/health` over the failover returns 200 with cert chain validating against the build-host CA bundle (cert IP-SAN matches VIP).
5. Restart `grafana-1` keepalived → VIP returns to prio-110 owner.

Same sequence is run on the Grafana PG VIP `.185`.

End-to-end signal-flow verification (the phase exit gate):

1. Pick any fleet VM (e.g. `kafka-east-1`). Confirm `prom-1` AND `prom-2` are both scraping `kafka-east-1:9100` (Prom `/targets` page UP for both).
2. Confirm `vector` is shipping `kafka-east-1`'s journald to Loki: `logcli query '{host="kafka-east-1"}' --limit=5` returns recent lines.
3. Run a manual OTLP trace from the build host to `https://otel.nexus.lab:4317`; confirm it lands in Tempo via `tempo` API search; confirm it appears in Grafana Explore.
4. Trigger a test Alertmanager alert; confirm it fires on both `prom-1`/`prom-2` (cluster dedup) and routes to the configured channel.

## Consequences

**Positive:**

- The observability tier itself is **HA across the LB tier** per ADR-0025 — Grafana's single URL has atomic failover; the Prom HA pair survives a node loss without operator action; Loki/Tempo rings tolerate N-1 failures on the gossip mesh.
- **Equal C# / Python ergonomics.** Both languages have first-class Prom client libs + Serilog/OTel Loki sinks + OTel trace SDKs. The Grafana stack is single-pane-of-glass; no language gets a second-class signal.
- **MinIO is exercised harder** — Loki + Tempo make the lakehouse S3 store a transactional hot path for non-lakehouse data, validating the choice to keep `nexus-infra-lakehouse v0.1.0`'s MinIO as the lab's shared S3 service.
- **The hybrid shipper avoids fleet-wide bake refresh.** Vector + node_exporter retrofit into 9 templates is a single rebuild pass per template (~6 min each), not a Packer + Terraform full-cycle on every existing VM.
- **Reserved obs rows retired cleanly** without leaving orphans — Marquez moves back to its planned platform-tools home; VictoriaMetrics is retired (we picked plain Prom HA, not VM cluster); Seq is retired (single-node Free Edition).

**Negative:**

- **14 VMs vs the reserved 3** — quadruples the obs footprint. Justified by ADR-0025; the cheaper alternative (singletons-as-exception) was explicitly rejected.
- **Loki's `| json` query model is less ergonomic for C# devs than Seq's native property syntax.** Mitigated by Grafana's Explore UI auto-detecting structured fields + the Serilog Loki sink emitting JSON-shaped logs by default. Documented in glossary + handbook.
- **Future Mimir / Thanos upgrade is open work.** Plain Prom HA has no built-in long-term storage; metrics retention is bounded by `prom-1/2` disk. Adding Mimir (3-component MinIO-backed cluster) is a tracked future enhancement.
- **OTel Collector pair behind RR DNS, not VIP.** Apps that don't retry will see brief blips on a collector node loss. Acceptable for OTLP write paths (clients spec retry) but documented as a known limitation in the handbook.

**Operational:**

- `nexus-cli` `cluster-status` for the observability tier must report Grafana VIP owner + Grafana PG VIP owner + Prom scrape lag + Loki ring members + Tempo ring members. CLI adapter is part of the deferred adapter phase (Vol00 §Plan).
- The handbook §3.x runbooks include: Grafana failover, alert silencing, log query cookbook (LogQL → property-search idioms for Serilog users), trace search by service, MinIO bucket inspection for `loki`/`tempo`, OTel Collector pipeline debug.
- Cold rebuild of the whole tier follows the same shape proven 6× already (0.E.4e → 0.G.7 → 0.H.6 → 0.L.1 → 0.L.2 → 0.L.5): `terraform destroy` → `packer build` (every per-engine template) → `terraform apply` from zero → `smoke-0.I.*.ps1` ALL GREEN. Stale Vault KV obs tokens wiped between rebuilds per [[feedback_cold_rebuild_stale_kv_tokens]].

## Lessons applied up-front (born from prior phases)

- **VRRP unicast not multicast** — VMware Workstation VMnet11 doesn't reliably forward `224.0.0.18` ([[feedback_terraform_partial_apply_destroys_resources]] adjacent lesson, baked at 0.G.3.5c chunk 1).
- **keepalived check uses absolute versioned binary** for the PG health probe — `/usr/lib/postgresql/17/bin/pg_isready`, not the `/usr/bin/` wrapper ([[feedback_keepalived_check_versioned_binary]], caught at 0.L.2).
- **systemd RuntimeDirectory** for Prom/Loki/Tempo pid + tmp paths under `/var/run/<svc>/` ([[feedback_systemd_runtime_directory_tmpfs]]).
- **Vault Agent template body as HCL heredoc** for the cert/key/ca templates ([[feedback_vault_agent_template_hcl_heredoc]]).
- **Sudo every probe** that traverses `/etc/<svc>.d/` 0750 root:svc dirs in the smoke gate ([[feedback_sudo_required_for_consul_etc_traverse]]).
- **PowerShell scope-qualifier traps** in URL/IP smoke scripts ([[feedback_powershell_url_scope_qualifier]]).
- **Windows curl + schannel** doesn't validate IP SANs — smoke uses `--resolve dns:port:ip` or PS SslStream sync ([[feedback_windows_curl_schannel_no_ip_san]]).
- **PKI cert IP-SAN includes the VIP** on both nodes so `verify-full` works regardless of which holds it ([[feedback_ha_promise_covers_lb_tier]]).
- **Stale Vault KV tokens wiped between cold rebuilds** ([[feedback_cold_rebuild_stale_kv_tokens]]).
- **Per-engine Packer + per-cluster TF env** — never monolithic ([[per-cluster-state-per-engine-template]]).
