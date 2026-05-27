# NexusPlatform — Master Implementation Plan

> **Status:** v0.1.0 (Plan) · **Owner:** Greg Zapantis · **Target:** 72 weeks from 2026-04-20

This document is the **single source of truth** for the NexusPlatform portfolio. The design
lives in the 14 Volume `.docx` files under `../DOCS/`; this plan turns those volumes into a
sequenced, gated, acceptance-criteria-bearing execution plan.

Rules of engagement:

1. **The DOCS are canon.** Enhancements add capability; they never overwrite.
2. **Enterprise caliber.** Schemas are multi-table relational models with up/down migrations. No toy databases.
3. **Portfolio intent applies to every project.** Each of the 14 projects must demonstrate all four skill dimensions (§2).
4. **Acceptance gates are hard gates.** No project ships v0.1.0 without every box checked (§6).

---

## 1. Portfolio scope

### 1.1 Application projects (14)

| # | Project | Architecture | Primary store | Distinguishing pitch | Weeks |
|---:|---|---|---|---|---:|
| 0 | `portfolio` | Clean Arch | SQL Server + Redis | Blazor Server portfolio site + interactive SVG + Docs-as-Code pipeline | Phase 0.K |
| 1 | `dataflow-studio` | Modular Monolith | SQL Server AO → StarRocks + ClickHouse | SQL Server CDC → Kafka (Avro) → Kimball DWH + analytics | 4 |
| 2 | `tenantcore` | Clean Arch | Percona PXC + ProxySQL | Multi-tenant SaaS with per-tenant schemas, Identity, Hangfire | 4 |
| 3 | `sentinelml` | Vertical Slice | PostgreSQL Patroni | Fraud + anomaly ONNX inference, PSI drift → retrain, ksqlDB | 5 |
| 4 | `localmind` | Clean Arch | MongoDB RS + pgvector | Local LLM gateway · OpenAI-compat · **RAG from v0.1** · Named Pipes Win service | 4 |
| 5 | `pulsenlp` | Vertical Slice | PostgreSQL + ClickHouse | ML.NET + DistilBERT + BERT NER all via ONNX, no Python runtime | 4 |
| 6 | `visioncore` | Clean Arch | MongoDB RS | PyTorch → ONNX → C# inference, ImageSharp only, no OpenCV | 4 |
| 7 | `recoengine` | Modular Monolith | Percona PXC | ML.NET MatrixFactorization + Kafka Streams GlobalKTable | 4 |
| 8 | `chronosight` | Vertical Slice | ClickHouse + StarRocks | Time-series forecast · ksqlDB OHLCV · Generic Math rolling windows | 4 |
| 9 | `querylens` | Vertical Slice | SQL Server + PG ES | DMV → Event Store → changepoint → AI rewrite via LocalMind | 4 |
| 10 | `fieldsync` | Clean Arch | MongoDB + SQLite | MAUI (Android + Windows) · gRPC bidi · offline-first · on-device ONNX | 5 |
| 11 | `nexus-platform` | Microservices | Per-service | 6 services · choreography + orchestration sagas · full `/k8s` | 6 |
| 12 | `streamcore` | Vertical Slice | ClickHouse + PG + Redis | 4 Streams topologies · live MM2 DR demo · Chaos Harness | 5 |
| 13 | `nexus-desk` | Monorepo (4 apps) | shared via gRPC | WinForms DBA Studio · WPF+Rx Trading · WinUI3 AI Assistant · WinUI3+WPF Hybrid | 5 |
| **14** | **`lakehouse-core`** | **Medallion (Bronze/Silver/Gold)** | **Iceberg on MinIO** | **Full lakehouse · PySpark + dbt + time travel · SCD2 via dbt snapshots · Trino federation** | **5** |

### 1.2 Infrastructure repositories (7 + data-tier repos)

| # | Repo | Role |
|---:|---|---|
| I1 | `nexus-shared` | NuGet library family — `Nexus.Kafka`, `Nexus.Observability`, `Nexus.Outbox`, `Nexus.Avro`, `Nexus.Vault`, `Nexus.Primitives`, `Nexus.Audit`, `Nexus.Tenancy`, `Nexus.Migrations`, `Nexus.Analyzers` |
| I2 | `nexus-infra-vmware` | Packer HCL + Terraform (`vmware-desktop` provider) + Ansible playbooks for Tier 1 |
| I3 | `nexus-infra-swarm-nomad` | Swarm + Nomad + Consul + Vault bootstrap onto Tier 1 VMs |
| I4 | `nexus-infra-k8s` | Kubernetes cluster bootstrap + per-app manifest index |
| I5 | `nexus-infra-registry` | Harbor private registry (image hosting, Trivy scanning, OIDC) |
| I6 | `nexus-infra-vitess` | **Vitess-sharded MySQL/Percona showcase (Phase 0.O, committed 2026-05-22)** — relational MySQL sharding (distinct from PXC/Galera replication) |
| I7 | `nexus-infra-citus` | **Citus-sharded PostgreSQL showcase (Phase 0.P, committed 2026-05-22)** — relational PG sharding (distinct from Patroni streaming replication) |

> Data-tier infra repos spun out under Phase 0.G/0.H/0.L are tracked in their own phase rows: `nexus-infra-oltp` (0.G.1-0.G.4 + 0.G.7), `nexus-infra-kafka` (0.H), `nexus-infra-analytics` (0.G.5/0.G.6), `nexus-infra-lakehouse` (0.L.1-0.L.3). The registry tier shipped as `nexus-infra-registry` (I5) at 0.L.4.

### 1.3 Already shipped / in flight

| Repo | Status |
|---|---|
| `portfolio-index` | 🟢 v0.1.0 — the grid + skills matrix |
| `local-data-stack` | 🟢 v0.1.0 Compose mode; → v1.0.0 will add VMware-native deployment (Phase 0.G) |
| `nexus-platform-plan` | 🟢 v0.1.0 — **this repo** |

---

## 2. Portfolio intent — the four skill dimensions

Every one of the 14 application projects must *demonstrably exercise* all four:

| Dimension | What "demonstrated" means |
|---|---|
| **.NET engineering + architecture** | Pattern enforced by tests (NetArchTest dependency rules, xUnit architecture tests). ADRs explain trade-offs. Modern idioms enforced by `Nexus.Analyzers` Roslyn package (E25). |
| **Advanced SQL + analytics** | ≥3 non-trivial SQL artifacts per project in `docs/sql-showcase.md`. Catalogued in the portfolio-wide `docs/sql-depth.md` (E28). |
| **Python** | Where applicable per grid (lakehouse-core, DataFlow Studio, ChronoSight, SentinelML, PulseNLP, VisionCore). Modern toolchain enforced: uv + Ruff + mypy --strict + Pydantic v2 + Polars (E27). Notebooks render in GitHub. |
| **DevOps literacy** | Operator surface is `nexus-cli`, not raw Terraform/kubectl. Runbooks are teaching-material with "what you'll see" sections. Every resource has a panic button (E29). |

Every PR template forces checks in all four boxes. Missing evidence blocks merge.

---

## 3. Enhancement catalog (E1–E30)

Layered on top of the Volume docs to reach enterprise caliber. Each enhancement either fills a doc gap or adopts a current best practice the docs predate.

### Docs gaps (E1–E11)

| # | Enhancement | Resolution |
|---|---|---|
| E1 | Migration tool unspecified | **FluentMigrator** (SQL Server / Percona / PostgreSQL) with explicit `Up()` + `Down()`. **DbUp** for ClickHouse + StarRocks (SQL-script-based). CI gate: up → down → up on fresh container. |
| E2 | No alerting | **Alertmanager** + **Karma UI**. Alert rules versioned alongside Grafana dashboards. |
| E3 | No long-term metrics storage | **VictoriaMetrics** single-node on NVMe. 30-day Prometheus remains for scraping. |
| E4 | AOT + EF Core tension | **Dapper + FluentMigrator** on AOT paths (nexus-cli, PulseNLP ingestion, LocalMind API, DataFlow Studio Kafka workers). **EF Core** permitted on non-AOT paths. Per-project ADR. |
| E5 | Terraform provider mismatch for Workstation | **`vmware/vmware-desktop`** community provider as primary, **`vmrun` + PowerShell** wrappers as fallback. The Vol01 `hashicorp/vsphere` code is retained as "upgrade path to ESXi." |
| E6 | Enterprise DDL under-specified | Complete multi-table DDL authored per project in `schemas/<project>/`. Standard audit columns everywhere: `created_utc, created_by, modified_utc, modified_by, row_version, is_deleted`. |
| E7 | Data contracts not visualizable | **Data Contract Portal** module in the portfolio website — Blazor UI over Schema Registry + AsyncAPI specs. Diff / approve / deprecate. (IDEA-0006 promoted.) |
| E8 | Cross-project code duplication | `nexus-shared` NuGet family (see I1). Extraction triggered by second consumer, not first. |
| E9 | Chaos engineering in backlog only | **Kafka Chaos Harness** promoted (IDEA-0007) + **Pumba** for Swarm chaos + `nexus-cli chaos` commands. |
| E10 | Docs-as-code not automated | Portfolio website auto-ingests `../DOCS/_build/txt/*.txt` and renders as site pages. Doc changes propagate via CI. (IDEA-0010 promoted.) |
| E11 | No private container registry | **Harbor** on dedicated VM (registry-1, .70.115). Trivy vulnerability scanning, OIDC via Vault, replication. |

### Operational excellence (E12–E20)

| # | Enhancement | Detail |
|---|---|---|
| E12 | Testing strategy codified | xUnit + FluentAssertions (unit) · Testcontainers (integration — real Kafka/SQL/PG/Mongo/CH/SR) · PactNet (contract — NexusPlatform services) · NetArchTest (architecture) · Stryker.NET (mutation, app-layer) · Verify.Xunit (snapshot) · WireMock.Net (HTTP stub). Coverage gate: 80% application layer, 60% overall. |
| E13 | Performance/load testing | **NBomber** per API service. Baseline in CI, full runs weekly via Nomad batch. Grafana panel for trend. |
| E14 | API contract governance | **OpenAPI** (`docs/api/openapi.yaml`) per REST service. **AsyncAPI** (`docs/api/asyncapi.yaml`) per Kafka topic. Rendered through the Data Contract Portal (E7). |
| E15 | Security posture | **mTLS** via Consul Connect between Swarm services · **Vault dynamic secrets** for DB creds (rotate 24h app tokens, 7d service creds) · **OWASP ZAP** baseline scans in CI · **Trivy** image scans via Harbor · **Syft → CycloneDX SBOM** per release. |
| E16 | Data lineage | **OpenLineage** emitted by DataFlow Studio + SentinelML + lakehouse-core + Prefect flows. **Marquez** UI on obs-metrics VM. |
| E17 | Feature flags | **Unleash** self-hosted (PG-backed). **OpenFeature** .NET SDK in every service. |
| E18 | Chaos engineering | **Pumba** for Docker Swarm (network delay, packet loss, kill) · custom `nexus-cli chaos` commands for VM-level · game-day runbook. |
| E19 | Developer experience | **Devcontainers** per repo (VS Code + Rider) · **Renovate** bot · **Conventional Commits** enforced via Husky + commitlint · pre-commit: `dotnet format` + markdownlint + yamllint. |
| E20 | Service catalog (optional) | **Backstage** on dedicated VM — auto-discovers all 14 repos via `backstage.yaml`. |

### Data + analytics depth (E21–E24)

| # | Enhancement | Detail |
|---|---|---|
| E21 | Spark + Iceberg + MinIO | New infra row `nexus-infra-spark` — Apache Spark 3.5+ (1 master + 2 workers), **Apache Iceberg** table format, **MinIO** S3-compatible object store. PySpark + Scala both usable. |
| E22 | dbt Core transformation layer | dbt-starrocks + dbt-clickhouse adapters. All Kimball SCD2 + aggregation logic in dbt models. dbt docs published to portfolio site. Schema + custom tests as quality gates. |
| E23 | Workflow orchestrator | **Prefect 3** (OSS self-host, PG-backed). Worker pool on Nomad. OpenLineage emission wired so Marquez (E16) renders the full asset graph. Prefect UI on `prefect-server` VM. |
| E24 | Notebooks | **JupyterHub** on dedicated VM. PySpark kernel → Spark cluster. Iceberg tables in MinIO visible. Interactive data storytelling for portfolio demos. |

### Portfolio intent (E25–E29)

| # | Enhancement | Detail |
|---|---|---|
| E25 | Modern .NET / C# standard | Roslyn analyzers in `Nexus.Analyzers` enforce: primary constructors · collection expressions · required members · `IAsyncEnumerable<T>` streaming APIs · Problem Details (RFC 7807) via `IProblemDetailsService` · **Result pattern** (`ErrorOr` or `OneOf`) in application layer · `Microsoft.AspNetCore.RateLimiting` · **source-generated mappers** (Riok.Mapperly, not AutoMapper) · **source-generated validators** (FluentValidation 12+ with source gen). |
| E26 | .NET Aspire 10 for local dev | Every app ships an `AppHost` composing the project + deps (Kafka, SQL, CH, Redis, obs). Hands out connection strings via service discovery. Replaces Compose for inner-dev loop; Compose stays for CI + `local-data-stack`. |
| E27 | Python modern toolchain | **uv** (package + venv) · **Ruff** (format + lint) · **mypy --strict** · **Pydantic v2** · **Polars** (preferred) · **PyArrow** · **pytest + pytest-asyncio + pytest-benchmark**. CI: `ruff check && mypy --strict && pytest`. |
| E28 | Advanced SQL showcase catalog | `docs/sql-depth.md` at portfolio-index level cross-references every technique. Minimum coverage: recursive CTE · window functions with frames · MERGE with OUTPUT · temporal tables · FOR JSON PATH / JSON_VALUE · columnstore indexes · ClickHouse AggregatingMergeTree MVs · Iceberg time-travel · dbt snapshots · dbt parametrized macros. |
| E29 | DevOps guardrails | (a) **nexus-cli is the operator surface** — no raw Terraform for daily ops. (b) **Panic button** in every runbook — one command to last-known-good. (c) **Heavily commented IaC** — every Terraform resource has block comment; `terraform-docs` CI check fails on uncommented resources. |

### Demo playbooks (E30)

| # | Enhancement | Detail |
|---|---|---|
| E30 | Portfolio Demo Playbooks | 17 guided scenarios (DEMO-01 → DEMO-17, incl. the analytics/lakehouse/registry infra tours). Markdown step-by-step + annotated screenshots (primary). **Auto-generated recordings only** — VHS (.tape) for terminal + Playwright (`video: 'on'`) for browser + ffmpeg concat for combined flows. `nexus-cli demo record --all` in CI on release tags. No manual video. See [`docs/demos/README.md`](./docs/demos/README.md). |

---

## 4. Build phases

### Phase 0 — Infrastructure (~14 weeks)

| ID | Duration | Outputs | Exit gate |
|---|---|---|---|
| 0.A | 1 day | VMnet10 (HO 192.168.10.0/24) + VMnet11 (HO 192.168.70.0/24) on host 10.0.70.101 — both Host-Only due to WS Pro Windows single-NAT-slot limit; egress deferred to nexus-gateway | Host adapters bind 192.168.10.1 + 192.168.70.254; vmnetcfg.exe shows both vnets |
| 0.B | 1 wk | (0) `nexus-gateway` Debian 13 built FIRST (Bridged + VMnet11 + VMnet10 NICs; nftables masquerade; dnsmasq DHCP+DNS; chrony NTP). Then Packer templates in `nexus-infra-vmware`: deb13, ubuntu24, ws2025-core, ws2025-desktop, win11ent | `nexus-gateway` powered on; lab VM can `apt update` through it; 5 golden `.vmx` in `H:\VMS\NexusPlatform\_templates\` |
| 0.C | 2 wk | Terraform modules in `nexus-infra-vmware` + `nexus-infra-swarm-nomad`: `vmware-desktop` provider, module per cluster, env targets (`full`, `data-engineering`, `ml`, `saas`, `microservices`, `demo-minimal`) | `terraform apply -target=module.foundation` boots dc-nexus + 3× vault + 3× obs |
| 0.D | 5 sub-phases (~3 wk) | 3-node Vault Raft + PKI + LDAPS-to-AD + foundation cred migration into KV + Transit auto-unseal/GMSA/Vault Agent. Sub-phases below. | `vault kv get nexus/foundation/dc-nexus/dsrm` returns; `vault kv get nexus/sqlserver/oltpdb` lands when 0.E or data env writes the path. |
| 0.D.1 | 3 d | 3-node Vault Raft cluster on the foundation tier. Dual-NIC (VMnet11 service .121–.123 via dnsmasq dhcp-host MAC reservations + VMnet10 backplane 192.168.10.121-.123). Per-clone self-signed bootstrap TLS. KV-v2 mount at `nexus/`. userpass + AppRole auth methods. `nexus-bootstrap` AppRole with `default` policy. Smoke secret at `nexus/smoke/canary`. | `vault status` on all 3 = initialized + unsealed; `raft list-peers` shows 3 peers + 1 leader; cross-node read of smoke secret succeeds from all 3. |
| 0.D.2 | 2 d | Internal PKI: `pki/` root CA (`CN=NexusPlatform Root CA`, 10 y) + `pki_int/` intermediate (`CN=NexusPlatform Intermediate CA`, 5 y). `vault-server` PKI role with allow_ip_sans + 1 y leaf TTL. Per-node listener cert reissue (atomic-swap into `/etc/vault.d/tls/` + SIGHUP reload). Root CA distributed to build host (`$HOME\.nexus\vault-ca-bundle.crt`) + every Vault node's system trust store. Legacy 0.D.1 trust shuffle retired on followers. | Operator drops `VAULT_SKIP_VERIFY` and sets `VAULT_CACERT=$HOME\.nexus\vault-ca-bundle.crt`; .NET TLS handshake validates against the bundle without skip-verify. |
| 0.D.3 | 4 d | LDAPS-to-AD pulled forward from 0.D.5: `vault_ldaps_cert` overlay issues a leaf cert from `pki_int/` for `dc-nexus.nexus.lab`, installs into `LocalMachine\My`, restarts NTDS. Vault `auth/ldap` (LDAPS, search-then-bind, no `upndomain`) + `secrets/ldap` (`schema=ad`, `password_policy=nexus-ad-rotated`, daily rotate-role for `svc-demo-rotated`). Foundation env creates 3 svc accounts (`svc-vault-ldap`, `svc-vault-smoke`, `svc-demo-rotated`) + 3 AD groups (`nexus-vault-{admins,operators,readers}`) + delegates 4 ACEs to `svc-vault-ldap` on `OU=ServiceAccounts`. AD-group → Vault-policy mapping: admins → `nexus-admin`, operators → `nexus-operator`, readers → `nexus-reader`. | `vault login -method=ldap -username=<u>` returns a token with the AD-group-mapped policy; `vault read ldap/static-cred/svc-demo-rotated` returns a Vault-managed password rotated daily. |
| 0.D.4 | 2 d | Foundation cred migration: `nexus-foundation-reader` policy + AppRole + sticky one-time seed of plaintext defaults + JSON migration into `nexus/foundation/{dc-nexus,identity,vault,ad}/*`. Foundation env's `provider "vault"` (~> 4.0) authenticates via AppRole role-id+secret-id JSON; `vault_kv_secret_v2` data sources resolve `dsrm` / `local-administrator` / `nexusadmin` for the `dc-nexus` + jumpbox overlays. Bind/smoke overlays write back to KV after generating fresh AD pwds. LDAP-auth refactored to prefer KV bindpass with JSON-file fallback. | `vault kv get nexus/foundation/dc-nexus/dsrm` returns; AppRole login yields a token with `nexus-foundation-reader` policy; `terraform plan` resolves data sources cleanly; capability scoping (read on `nexus/foundation/*`, write only on `nexus/foundation/ad/*`) enforced in positive + 2 negative tests. |
| 0.D.5 | 4 d | Transit auto-unseal (HSM-shaped pattern: a small one-node Vault provides the unseal key for the 3-node lab cluster, eliminates manual unseal on reboot) + GMSA on Windows fleet + `MinPasswordLength=14` tightening + Vault Agent on member servers (auto-renewing cert + KV cred templates) + leaf cert auto-rotation cadence dropped from 1 y to 90 d. | Vault cluster reboots without operator-driven unseal; Vault Agent renders `nexus/foundation/...` creds into config files on the consumer hosts; `Get-ADDefaultDomainPasswordPolicy` shows MinPasswordLength=14. |
| 0.E | 4 sub-phases (~5 wk) | Tier-2 orchestration: 6-node Docker Swarm (3 managers + 3 workers) + co-located Nomad + Consul + Portainer CE. Hardened with mTLS for inter-agent RPC, ACL deny-mode for both control planes, and Vault Agent rendering all per-node secrets. Sub-phases below. | `docker node ls` shows 6; `nomad server members` shows 3; `consul members` shows 6; `https://portainer.nexus.lab:9443` reachable with CA-validated TLS; ~180-check chained smoke gate green. |
| 0.E.1 | 4 d | `swarm-node` Packer template (Debian 13 + Docker CE + Consul + Nomad pre-installed) + Terraform clones for the 6 swarm-nodes (per-VM dirs under `06-orchestration/`; dual-NIC VMnet11 service `.111-.113`/`.131-.133` + VMnet10 backplane). `docker swarm init` on manager-1 + `docker swarm join` on the other 5. Gateway dnsmasq dhcp-host reservations pin canonical IPs. | `docker node ls` reports 6 nodes (3 managers Ready + Active, 3 workers Ready + Active); SSH from build host reaches all 6 on VMnet11; `consul members` reports 6 alive; `nomad server members` reports 3 alive. |
| 0.E.2 | 4 d | Consul harden across 3 sub-phases: **(0.E.2.1)** gossip encryption — Vault Agent renders `/etc/consul.d/10-encrypt.hcl` from `nexus/swarm/consul-gossip-key`, sequential rolling restart converges keyring. **(0.E.2.2)** TLS — per-node leaf cert from `pki_int/issue/consul-server` rendered by Vault Agent + post-render bundle split, mutual TLS for internal RPC + Raft + server-only TLS for HTTPS API on 8501; plain HTTP/8500 hard-cut via systemd drop-in `-http-port=-1`. **(0.E.2.3)** ACL — transition-mode bootstrap (allow → deny) with mgmt token persisted to Vault KV at `nexus/swarm/consul-bootstrap-token` + 6 per-host policies + tokens at `nexus/swarm/agent-tokens/<host>`; Vault Agent renders `/etc/consul.d/30-acl-token.hcl` per node. | Consul keyring at `[6/6]` on a single key; HTTPS:8501 returns 200 with mgmt-token; plain HTTP:8500 connection-refused; anonymous HTTPS GET `/v1/agent/self` returns 403 across all 6 nodes; chained smoke gate (~95 probes through 0.E.2.3) green. |
| 0.E.3 | 6 d | Nomad harden + Vault integration across 4 sub-phases: **(0.E.3.1)** TLS — per-node leaf cert from `pki_int/issue/nomad-server` (SAN includes `server.global.nomad`/`client.global.nomad` for `verify_server_hostname=true`), mTLS for RPC + raft + HTTPS API on 4646; systemd drop-in switches `-config=` from single-file to dir mode; parallel big-bang restart for cluster reconvergence. **(0.E.3.2)** ACL — `acl{enabled=true}` cluster-wide, mgmt token persisted to `nexus/swarm/nomad-bootstrap-token` + shared `nomad-agent` policy + 6 per-host operator tokens at `nexus/swarm/nomad-agent-tokens/<host>`. Inter-agent RPC authenticates via the mTLS cert SAN (Nomad's `acl{}` block has no `token` field). **(0.E.3.3a)** Nomad → Consul HTTPS rewire — Vault Agent renders Consul agent token to `/etc/nomad.d/42-consul-token.hcl`; static config in `42-consul.hcl` with scheme-less `address=127.0.0.1:8501 + ssl=true + ca_file`; legacy `consul{address="127.0.0.1:8500"}` block sed-removed from `nomad.hcl`. **(0.E.3.3b)** Nomad-Vault integration — managers' `vault{}` stanza loaded with one-shot terraform-side periodic-token mint via `vault token create -role=nomad-cluster` (period 72h, allowed_policies=`nomad-jobs`); Nomad takes over renewal post-startup. | `nomad server members` over HTTPS reports 3 alive; `nomad node status` reports 3 ready clients; anonymous HTTPS GET `/v1/agent/self` returns 403 cluster-wide; `/v1/agent/self` JSON shows `Consuls[].Addr=127.0.0.1:8501 + EnableSSL=true` AND `Vaults[].Addr=https://192.168.70.121:8200 + Enabled=true` on managers; chained smoke gate (~155 probes through 0.E.3.3) green. |
| 0.E.4 | 5 d | Portainer CE clustered Swarm service + supporting infra. **(0.E.4a)** NFS — `nfs-kernel-server` on `nexus-gateway` exporting `/srv/nfs/portainer-data` NFSv4-only with `fsid=0` pseudo-root to manager IPs; per-manager mount via `192.168.70.1:/` at `/var/lib/portainer-data`. Gateway nftables in-place patched for tcp/2049 from manager IPs. **(0.E.4b)** TLS — `pki_int/roles/portainer-server` (CN `portainer.nexus.lab` + per-host IP SANs); per-manager Vault Agent template renders + split-script writes `/etc/portainer/tls/{server.crt,server.key,ca.pem}`. **(0.E.4c)** DNS — dnsmasq `host-record=portainer.nexus.lab,IP1,IP2,IP3` (multi-A round-robin). **(0.E.4d)** Stack deploy — sticky-seeded `nexus/portainer/admin-bcrypt` (24-char alphanumeric plaintext + bcrypt cost=10); per-manager Vault Agent renders bcrypt to `/etc/portainer/admin-password.txt` (HCL heredoc; not inline-string); `docker stack deploy -c portainer-stack.yml portainer` from manager-1 with server (1 replica, manager-pinned) + agent (mode global, 6 tasks). nftables `flush ruleset` + Docker iptables-nft conflict resolved via per-overlay sequential dockerd restart (rebuilds DOCKER-INGRESS DNAT). | `docker stack ls` includes `portainer`; `docker service ls` shows server 1/1 + agent 6/6; `https://portainer.nexus.lab:9443/api/system/status` returns 200 with TLS chain validating against the build-host CA bundle; admin login works with the plaintext from KV; ~180-check chained smoke gate (`smoke-0.E.4.ps1`) green. |
| 0.E.4e | 1 d | **Cold-rebuild gate + structural fixes** that 0.E.4 close-out missed. Three fixes: (1) `server.crt = leaf || intermediate` via Vault Agent split-script (`consul_tls_v=7`, `nomad_tls_v=5`, `portainer_tls_v=2`); ca.pem stays as intermediate (internal mTLS unchanged). Off-cluster clients with stock root-only bundle now validate without augmentation. (2) `inet filter forward` chain accept rules for `docker_gwbridge`+`docker0` (Linux runs all FORWARD chains; empty drop on the inet table killed swarm ingress mesh DNAT for off-cluster traffic, even though Docker's `ip filter FORWARD` accepted). Both Packer-baked + runtime hot-fix overlay. (3) Stage1 ssh stdin-pipe pattern in 3 TLS overlays (was failing past ~6KB single-quoted argv on Windows ssh.exe; v7 split-script edit pushed it over the threshold). New `scripts/smoke-0.E.4e.ps1` (409 checks; Block C asserts off-cluster TLS validation **from build host** with **stock root-only CA bundle**). ADR-0019. | **Cold rebuild proven end-to-end:** `terraform destroy` → `packer build` (swarm-node template rebuilt) → `terraform apply` → `smoke-0.E.4e.ps1` ALL GREEN with stock root-only CA bundle on build host. Single operator-runbook prerequisite (wipe stale `nexus/swarm/{,nomad-}{bootstrap,agent}-token{,s}` from Vault KV between rebuilds — canonical self-validating fix deferred). **`v0.1.1` tagged 2026-05-08.** |
| 0.E.5 | 1 d | **Close-out canon batch.** MASTER-PLAN sub-phase rows finalized (above); `docs/infra/vms.yaml` ratified (managers 6 GB RAM / workers 4 GB RAM observed-sufficient deviations; gateway acquired NFS server role for Portainer state); `docs/glossary.md` extended for Docker / Docker Swarm / HashiCorp Nomad / HashiCorp Consul / Portainer CE; ADRs 0011-0019 cover Vault HA + PKI hierarchy + LDAPS + KV creds + Transit auto-unseal + Nomad-Vault periodic-token + Portainer-NFS-via-gateway + nftables `flush ruleset` Docker conflict + TLS full-chain on wire; `nexus-infra-swarm-nomad` handbook §1-§3 covers walkthrough + cold-rebuild canon (§3.6) + 0.E.4e walkthrough (§3.7) + 5 operator runbooks; phase status table (handbook §2) marks all 0.E.* rows closed; both repos' CHANGELOGs reflect Phase 0.E complete; `nexus-infra-swarm-nomad` tagged `v0.2.0` ("Phase 0.E orchestration tier — fully closed"). | All canon artefacts present and cross-linked; cold-rebuild canon proven against the running cluster; the lab's "rebuildable at any time" claim is gated by the 0.E.4e cold-rebuild verification doc. **Phase 0.E closed 2026-05-08.** |
| 0.F | 2 wk | `grezap/nexus-cli` — .NET 10 Native AOT; commands: `cluster-status`, `infrastructure {list, status, suspend, resume}`, `failover-test {consul-leader, nomad-leader, swarm-manager}`, `demo {list, run, record}`, `kafka failover {east-to-west, west-to-east}`. **`v0.5.0` tagged 2026-05-15 — Phase 0.F fully closed; all 5 master-plan verbs live.** AOT binary 22.75 MB win-x64 (under the 25 MB gate, 2.25 MB headroom). Live RTOs verified end-to-end: consul-leader 1.55 s · nomad-leader 2.716 s · swarm-manager 21.59 s · kafka east→west 13.20 s · kafka west→east 13.57 s. ADRs 0001-0008 cover framework + AOT + layout + auth + Dapper + vms.yaml-reader + SSH.NET + kafka-failover demo-grade design. | Single binary ≤25 MB on linux-x64 + win-x64; **all 5 verbs live**. **Phase 0.F closed 2026-05-15.** |
| 0.G | ~8 sub-phases (~8-12 wk) | `local-data-stack` audit + port to VMware (tagged `v1.0.0`). Two new infra repos: **`nexus-infra-oltp`** (Redis Cluster · MongoDB RS · Percona PXC + ProxySQL · Patroni + etcd + HAProxy · SQL Server FCI + AG — 25 VMs across tiers `02-sqlserver` + `05-oltp`) + **`nexus-infra-analytics`** (ClickHouse Keeper + shards · StarRocks FE + BE — 15 VMs on tier `04-analytics`). Each cluster ships paired with a `nexus-cli` `v0.6.x` release adding the **`IClusterAdapter` framework SPI** (one adapter per cluster, SSH-shell-out per [ADR-0008](./docs/adr/) — no managed DB drivers linked) + **13 verb groups**: `cluster-status` · `failover-test` · **`scale-out` add/remove** (cluster membership change per [`feedback_cli_verb_terminology.md`](../../) memory) · **`scale-up`** (VM CPU/RAM/disk resize) · `backup` take/restore · `health` · `topology --watch` · `cert-rotate` · `chaos` · `acl` · `demo`. AOT exit gate raised **≤25 MB → ≤30 MB** (ADR-0024) to accommodate the 7 cluster adapters; the Phase 0.F historical `v0.5.0` ≤25 MB gate stays sealed. Per-verb demos: ~91 System B JSON specs in `nexus-cli/docs/demos/` using the **extended observability shape** (optional `prerequisites` · `expectedExitCode` · `expectedOutputContains` · `observe[]` · `whatProves`). System A backfills: DEMO-08 (kafka region failure) + DEMO-11 (SQL AG DBA tour, when 0.G.7 lands) + DEMO-13 (chaos broker kill). Sub-phases below. **0.G.1 + 0.G.2 + 0.G.3 + 0.G.3.5 closed (cluster framework + nexus-cli adapters deferred to 0.G.4-0.G.7).** | All 6 Linux data clusters healthy on VMware + SQL FCI/AG live; **all 13 verb groups operational** per cluster with measured RTOs/throughputs; both new infra repos cold-rebuildable + tagged `v0.1.0`; `nexus-cli` tagged `v0.7.0` (≤30 MB AOT validated); `local-data-stack` tagged `v1.0.0`. (Grafana dashboards = Phase 0.I, deferred.) |
| 0.G.1 | 3 d | **Redis Cluster (6 nodes, 3 masters + 3 replicas).** `terraform/envs/oltp-redis/` (post-0.G.3.5 per-cluster state) + `packer/oltp-redis-node/` (per-engine template; Debian 13 + apt `redis-server` 8.0.2 + DISABLED `nexus-redis.service`). 6 VMs at `192.168.70.{81,82,83,84,87,89}` on VMnet11 + dual-NIC VMnet10. Per-host Vault PKI mTLS + `--cluster-replicas 1` + `cluster-announce-ip` per node. Smoke gate `smoke-0.G.1.ps1` ~50 checks. | `cluster_state:ok` + size=3 + known=6 + slots_assigned=16384 + 3 masters + 3 replicas + cross-shard SET/GET round-trip via `redis-cli -c`. **Phase 0.G.1 closed 2026-05-17** (monolithic cold-rebuild proven) + **re-proven 2026-05-18 via per-cluster envs** in 0.G.3.5c chunk 1. |
| 0.G.2 | 3 d | **MongoDB Replica Set `nexus-rs` (3 nodes).** `terraform/envs/oltp-mongo/` + `packer/oltp-mongo-node/` (vendor APT `mongodb-org-server` 8.0.23 + DISABLED `nexus-mongo.service`). 3 VMs at `192.168.70.{71,72,73}`. Per-host Vault PKI mTLS + shared keyFile internal-auth (sticky-seeded in Vault KV at `nexus/oltp/mongo/keyfile`). Bootstrap via `__system` cluster-auth (Mongo 8.0 + keyFile + `authorization=enabled` deactivates the localhost-exception bypass; documented in handbook). Smoke gate `smoke-0.G.2.ps1` ~45 checks. | `rs.status()` shows 1 PRIMARY + 2 SECONDARY + 3 members all `health:1`; replicated write/read round-trip via `readPreference=secondary` + `readConcern=majority`. **Phase 0.G.2 closed 2026-05-17** (monolithic cold-rebuild proven) + **re-proven 2026-05-18 via per-cluster envs** in 0.G.3.5c chunk 1. |
| 0.G.3 | 5 d | **Percona XtraDB Cluster (3 PXC + 2 ProxySQL + VRRP VIP).** `terraform/envs/oltp-percona/` + `packer/oltp-pxc-node/` (Percona Server 8.0.45-36.1 + WSREP 26.1.4.3 + xtrabackup-v2 SST) + `packer/oltp-proxysql-node/` (ProxySQL 2.6 + keepalived). 5 VMs at `192.168.70.{51,52,53,54,55}`. mTLS-only on :3306 via per-host PKI cert; Galera replication encrypted via `pxc-encrypt-cluster-traffic=ON`; ProxySQL `galera_hostgroups` (writer=10 / backup_writer=20 / reader=30 / offline=40) + `clustercheck` health user; VRRP-floated VIP `192.168.70.50` between proxysql-1 (priority 110) MASTER + proxysql-2 (priority 100) BACKUP, **unicast** mode (VMware VMnet11 doesn't reliably forward multicast). Smoke gate `smoke-0.G.3.ps1` ~80 checks. Initial monolithic ratification 2026-05-18 hit 16 transients (Debian 13 t64 transition libaio1/libldap-2.5-0 fallback to bookworm; AppArmor mysqld profile disable for custom datadir; `nexus-pxc-mysql` auth-mode-aware wrapper; v3 bootstrap-vs-join ordering; etc.) — 15 fixed, transient #16 (joiner SST never synced) deferred. **Per-cluster refactor (0.G.3.5) root-caused #16** to two compounding bugs: `wsrep_sst_auth` moved [mysqld]→[sst] in PXC 8.0 + `pxc-encrypt-cluster-traffic = ON` newline gap caused `ON!include` concatenation. All 16 + 11 new refactor transients permanently fixed. | All 3 PXC nodes Synced + Primary on mutual TLS; ProxySQL admin :6032 shows 3 backends + galera_hostgroups; VIP `.50` bound on MASTER only; end-to-end write via VIP propagates to every PXC backend; smoke `ALL 0.G.3 SMOKE CHECKS PASSED`. **Phase 0.G.3 closed 2026-05-18 via per-cluster envs.** |
| 0.G.4 | 5 d | **Patroni PostgreSQL HA + etcd DCS + HAProxy HA pair (3 + 3 + 2 = 8 nodes).** `terraform/envs/oltp-patroni/` + `packer/oltp-patroni-node/` (PostgreSQL 17 from apt.postgresql.org PGDG-bookworm + Patroni 4.0.5 from PyPI with `[etcd3]` extras + `nexus-patronictl` wrapper) + `packer/oltp-etcd-node/` (etcd 3.5.16 upstream tarball + `nexus-etcdctl` wrapper) + `packer/oltp-haproxy-node/` (HAProxy 3.0 LTS from haproxy.debian.net + `keepalived` for VRRP VIP). 8 VMs at `192.168.70.{61,62,63,64,65,66,67,68}` + **VRRP-floated VIP `192.168.70.60`** between `haproxy-pg-1` (priority 110) MASTER and `haproxy-pg-2` (priority 100) BACKUP. Apps connect to `.60:5432` regardless of which HAProxy holds it; same proven `unicast_src_ip` + `unicast_peer` pattern as the 0.G.3 proxysql VIP (VMware VMnet11 doesn't reliably forward IPv4 multicast `224.0.0.18`, baked at 0.G.3.5c chunk 1 transient #22). mTLS-only on :5432/:2379/:2380/:8008 via per-host PKI cert (one shared `patroni-server` role, 26 allowed_domains covering all 8 hostnames in bare + `.nexus.lab` + `.patroni.nexus.lab` forms); haproxy nodes carry the VIP `.60` in their cert IP-SANs so client handshakes against the VIP validate regardless of which haproxy currently holds it. etcd 3-member raft quorum with HTTP basic-auth RBAC (KV-seeded `root` password); Patroni 4 etcd3 client (gRPC v3) holds the DCS at `/service/nexus-pg/`; PG streaming replication over mTLS on the VMnet10 backplane. Both HAProxy nodes run identical `haproxy.cfg`: frontend `:5432` → `backend pg_pool` using `option httpchk GET /leader` against Patroni REST :8008 (200 only on leader; 503 on replicas); stats UI on :8404 with HTTP basic-auth (KV-seeded). 5 sticky-seeded Vault KV creds at `nexus/oltp/patroni/{etcd-root,patroni-rest,postgres-superuser,postgres-replication,haproxy-stats}-password` (32-char hex each). 4 System B JSON demos at `nexus-cli/docs/demos/demo-0.G.4-*.json` covering Patroni switchover, mTLS round-trip via VIP, **VRRP VIP cutover** (genuine VIP failover now that HAProxy is HA), and etcd 1-member loss + raft re-election + Patroni unaffected. Smoke gate `smoke-0.G.4.ps1` ~90 checks across 13 sections. | All 3 Patroni nodes in 1-Leader + 2-Streaming-Replica shape over mTLS; etcd 3-member quorum with RBAC enabled + leader elected; VIP `.60` bound on exactly one HAProxy node (MASTER); both HAProxy `pg_pool` backends show the same leader UP; end-to-end write via `<VIP>:5432` replicates to both replicas via `pg_stat_replication`; smoke ALL GREEN. **Phase 0.G.4 closed 2026-05-19 via per-cluster envs — full HA promise (no SPOF on the LB tier — mirrors the 0.G.3 proxysql HA pair pattern); ratification surfaced 18 transients all permanently fixed in source; smoke gate 152/152 ALL GREEN.** |
| 0.G.5 | 4 d | **ClickHouse — 3 shards × 2 replicas + 3-node Keeper quorum (9 nodes).** New repo **`grezap/nexus-infra-analytics`** (tier `04-analytics`). Per-engine templates `packer/analytics-clickhouse-keeper-node/` + `packer/analytics-clickhouse-server-node/` (Debian 13 + ClickHouse vendor apt `clickhouse-keeper` / `clickhouse-server`; DISABLED `nexus-*` units + shared firstboot identity) + per-cluster state `terraform/envs/analytics-clickhouse/` (per `feedback_per_cluster_state_per_engine_template.md`). 9 VMs at `192.168.70.{41,42,43,44,45,46,47,48,49}` on VMnet11 + dual-NIC VMnet10 backplane. **ClickHouse Keeper, NOT ZooKeeper** (dedicated 3-node C++ RAFT quorum; lab has zero ZooKeeper VMs — [ADR-0028](./docs/adr/ADR-0028-clickhouse-keeper-not-zookeeper.md)). `Distributed` tables over `ReplicatedMergeTree` with `internal_replication=true` + per-node `{shard}`/`{replica}` macros so one `CREATE TABLE ... ON CLUSTER nexus_analytics` self-identifies each node ([ADR-0029](./docs/adr/ADR-0029-clickhouse-shard-replica-topology.md)). **Client front door = round-robin DNS `clickhouse.nexus.lab` (6 data nodes), NO VRRP VIP** — every data node is an equal `Distributed` entry point, so no fixed-endpoint SPOF ([ADR-0031](./docs/adr/ADR-0031-analytics-client-front-door-round-robin-dns.md)). Backup repository = NFS export `/srv/nfs/analytics-backups` from `nexus-gateway` (MinIO deferred to 0.L — [ADR-0032](./docs/adr/ADR-0032-analytics-backup-repository-nfs-gateway.md)); `BACKUP/RESTORE TO Disk`. mTLS-only on `9000`/`9009`/`9010`/`8443` + Keeper `9181`/`9234` via per-host `clickhouse-server` Vault PKI cert; SQL-driven RBAC (`CREATE USER/ROLE/GRANT`, admin + least-priv app role, KV-seeded creds). RAM right-sized (keeper 4→2 GB, data 16→6 GB; `feedback_prefer_less_memory.md`, logged in `vms.yaml`). Smoke gate `smoke-0.G.5.ps1`. `nexus-cli` `ClickHouseAdapter` deferred to the unified later CLI phase; System B demos (11 verb groups) + System A analytics tour authored now. | `system.clusters` shows `nexus_analytics` = 3 shards × 2 replicas all reachable; `system.replicas` healthy (`is_readonly=0`, queue not stuck); a `Distributed` INSERT fans across all 3 shards; replica convergence (insert on shard-rep1 → read from shard-rep2); Keeper quorum survives a 1-node loss + re-elects; `clickhouse.nexus.lab` resolves all 6 data nodes; cross-node `BACKUP`→`RESTORE` round-trips; smoke ALL GREEN; **cold-rebuild proven** (`destroy` → `packer build` → from-zero `apply` → smoke ALL GREEN). **SEALED 2026-05-23 — live-ratified + cold-rebuild-proven** (destroy → packer build → from-zero apply → `smoke-0.G.5.ps1` **129/129 GREEN**; 9 apply-time transients fixed in source, handbook §3.x). `grezap/nexus-infra-analytics` tagged `v0.1.0`. |
| 0.G.6 | 4 d | **StarRocks — 3 FE (BDB-JE quorum: 1 leader + 2 follower) + 3 BE (6 nodes).** Same repo `nexus-infra-analytics`. Per-engine templates `packer/analytics-starrocks-fe-node/` + `packer/analytics-starrocks-be-node/` (Debian 13 + StarRocks FE/BE + JDK; DISABLED units + firstboot) + per-cluster state `terraform/envs/analytics-starrocks/`. 6 VMs at `192.168.70.{31,32,33,34,35,36}` + dual-NIC VMnet10. FE metadata quorum via Berkeley DB JE (majority of 3 tolerates one FE loss + re-elects); BE tablet plane scheduled by the FE Leader. Tables `DISTRIBUTED BY HASH(...) BUCKETS n` (n ≥ 3) with `replication_num=3` so tablets are sharded across all 3 BE AND replicated on all 3 ([ADR-0030](./docs/adr/ADR-0030-starrocks-fe-quorum-be-tablet-sharding.md)). **Client front door = round-robin DNS `starrocks-fe.nexus.lab` (3 FE, MySQL `:9030` + HTTP `:8030`), NO VRRP VIP** — any FE serves queries + forwards DDL to the Leader, no fixed-endpoint SPOF ([ADR-0031](./docs/adr/ADR-0031-analytics-client-front-door-round-robin-dns.md)). Backup repository = NFS from `nexus-gateway`; `CREATE REPOSITORY` + `BACKUP/RESTORE SNAPSHOT` ([ADR-0032](./docs/adr/ADR-0032-analytics-backup-repository-nfs-gateway.md)). mTLS via per-host `starrocks-server` Vault PKI cert; SQL-driven RBAC (users/roles/grants, admin + least-priv app role, KV-seeded creds). RAM right-sized (FE 8→4 GB, BE 16→6 GB; logged in `vms.yaml`). Smoke gate `smoke-0.G.6.ps1`. `StarRocksAdapter` (shells out to on-node `mysql`; StarRocks speaks MySQL protocol) deferred to the later CLI phase; System B demos (11 verb groups) + System A tour authored now. Builds AFTER 0.G.5 is sealed + its VMs stopped (`feedback_minimal_running_vms.md`). | `SHOW FRONTENDS` = 3 rows (1 `LEADER` + 2 `FOLLOWER`, all `Alive=true`); `SHOW BACKENDS` = 3 rows all `Alive=true`; a demo table's tablets distributed across all 3 BE with 3 replicas each on distinct BE (`SHOW TABLET`); FE-Leader-loss re-election (stop Leader → a Follower wins → DDL still works); BE-loss re-replication / query reroute; `starrocks-fe.nexus.lab` resolves all 3 FE; cross-node backup/restore; smoke ALL GREEN; **cold-rebuild proven**; **`grezap/nexus-infra-analytics` tagged `v0.1.0`** at close-out. **SEALED 2026-05-23 — live-ratified + cold-rebuild-proven (shared-nothing)** (StarRocks **3.5.17** on JDK 21; destroy → packer build FE+BE → from-zero apply → `smoke-0.G.6.ps1` **73/73 GREEN**; 7 apply-time transients fixed in source, handbook §3.B). `grezap/nexus-infra-analytics` tagged `v0.1.0`. The CN / shared-data (storage-compute-separation) tier is deferred to Phase 0.L (object storage). |
| 0.G.7 | 5 d | **SQL Server FCI + Always On AG (4 ws2025-desktop nodes; 2 FCI + 2 AG-replica).** `terraform/envs/oltp-sqlserver/` (9 role-overlays) + `packer/oltp-sqlserver-node/` (clones `ws2025-desktop.vmx` baked at Phase 0.B.5; layers SQL Server 2025 Developer Edition + Failover-Clustering + Multipath-IO + iSCSI-Initiator features + firstboot pre-staging) + nexus-infra-vmware foundation v6 (4 SQL MAC reservations at `.70.11/.12/.13/.14` + iSCSI tgt target on nexus-gateway exporting `iqn.2026-05.local.nexus:sql-fci.lun1` to FCI pair) + 5 security overlays (PKI role `sqlserver-server` + 4 AppRoles + 5 KV sticky-seeds + `gmsa-sql-engine$` GMSA + `nexus-sql-cluster-members` AD group). 4 VMs at `192.168.70.{11,12,13,14}` + **3 WSFC-managed VIPs**: WSFC cluster `.70.15`, FCI virtual server `.70.16`, **AG Listener `.70.17`** (per ADR-0025 the Listener IS the LB-tier HA primitive — WSFC migrates the IP atomically with the AG primary). Hybrid architecture: sql-fci-1/2 form a 2-node FCI sharing iSCSI LUN at S:\\; sql-ag-rep-1/2 hold async AG replicas of the FCI's user databases. WSFC quorum spans all 4 nodes (NodeMajority, tolerates 1 failure). mTLS via `pki_int/issue/sqlserver-server` (21 allowed_domains spanning 4 hostnames + FCI virtual + AG Listener in bare + `.nexus.lab` + `.sqlserver.nexus.lab` forms; FCI virtual cert IP-SAN `.70.16`, Listener cert IP-SAN `.70.17`). AG endpoint authentication = certificate-based per **ADR-0027** (avoids Windows endpoint-hop service login sprawl; mirrors the patroni pg_hba cert-based replication pattern). SQL service identity = `nexus.lab\gmsa-sql-engine$` (GMSA; Phase 0.G.7 is the first real GMSA consumer — 0.D.5 scaffolded the infrastructure). FCI shared storage via iSCSI from `nexus-gateway` per **ADR-0026** (Workstation Pro has no shared-disk primitive; tgt is the smallest tractable shim). 5 sticky-seeded Vault KV creds at `nexus/oltp/sqlserver/{sa,ag-endpoint-cert,wsfc-cluster-admin,iscsi-chap-secret,listener-cert}-password` (32-char hex each) + 1 gmsa-info JSON pointer. Smoke gate `smoke-0.G.7.ps1` ~165 checks across 14 sections (reachability + domain-join + GMSA + Vault Agent + TLS + iSCSI + WSFC + FCI install + AG sync state + Listener ownership + IP-SAN cert verify + sqlcmd via Listener + Listener failover sequence per ADR-0025 + FCI failover sequence). | 4 SQL nodes domain-joined to `nexus.lab` (FCI nodes in `nexus-sql-cluster-members` for gmsa retrieval); WSFC `sql-fci-cluster` healthy at `.70.15` (NodeMajority, 4 nodes Up); FCI virtual server `sqlfci` online at `.70.16` with the iSCSI LUN as a clustered Physical Disk (`S:\`); AG `nexus-ag` with the FCI as primary + sql-ag-rep-1/2 as SYNCHRONIZING+HEALTHY async secondaries (`nexus_demo` replicated via MANUAL seeding); AG Listener `sql-ag-listener` online at `.70.17` — remote domain client `sqlcmd -E -N` (Encrypt + strict cert-chain validate) returns the primary across the listener; smoke ALL GREEN. **Phase 0.G.7 PROVEN COLD-REBUILDABLE 2026-05-22 — first Windows-fleet data cluster + first real GMSA consumer + first iSCSI shim on nexus-gateway + OLTP tier SEALED (5/5 clusters: redis + mongo + percona + patroni + sqlserver-fci-ag, ALL cold-rebuild proven). Full `terraform destroy` → `packer build -force` → from-zero `terraform apply` → `smoke-0.G.7.ps1` ALL GREEN 56/56; 40+ ratification + 4 cold-rebuild transients (#30-#33: bake sqlcmd/ODBC · S:\SQLData root · cluster-disk drive-letter drift · ADD-DATABASE-before-backup) all root-caused + fixed in source (handbook §3.5b-§3.5d); `scripts/cold-rebuild-prereqs.ps1` codifies the AD/iSCSI destroy-cleanup prerequisite.** |
| 0.G.3.5 | 2 d | **Architectural refactor: per-cluster Terraform state + per-engine Packer template** (per [`memory/feedback_per_cluster_state_per_engine_template.md`](../../) — the architectural canon born from this phase). Drove by the 16-transient stall on 0.G.3 monolithic: the 30-min per-iteration cost (full 14-VM apply cascade) made each new transient too expensive to root-cause. The refactor: monolithic `packer/oltp-node/` split into 4 per-engine templates (`oltp-{redis,mongo,pxc,proxysql}-node/`); monolithic `terraform/envs/oltp/` split into 3 per-cluster states (`envs/oltp-{redis,mongo,percona}/`); per-cluster nftables overlays (no cross-cluster cascade); per-cluster operator scripts (`oltp-{redis,mongo,percona}.ps1`). Iteration loop shrunk from ~30 min monolithic → ~5-10 min per cluster. Three chunks: **0.G.3.5a** per-engine templates (4 NEW, [commit `61ebad8`](https://github.com/grezap/nexus-infra-oltp/commit/61ebad8)) → **0.G.3.5b** per-cluster states + scripts ([commit `ad4f563`](https://github.com/grezap/nexus-infra-oltp/commit/ad4f563)) → **0.G.3.5c** chunk 1 live cold-rebuild + 11 transient permanent fixes ([commit `d076abd`](https://github.com/grezap/nexus-infra-oltp/commit/d076abd)) + chunk 2 delete legacy + canonicalization ([commits `ef4fe78` + `3dee5be`](https://github.com/grezap/nexus-infra-oltp/commits/main)). The architectural canon now applies to 0.G.4+ (Patroni), 0.G.5+ (analytics), 0.G.7 (SQL FCI/AG), 0.I (observability), 0.L (Spark + Harbor). | All 3 OLTP clusters proven cold-rebuildable from per-engine templates + per-cluster states; legacy paths removed; CI matrix scoped down (4 packer + 3 terraform). Architectural lesson canonicalized in memory + handbook §3.x's 11-row transient table. **Phase 0.G.3.5 closed 2026-05-18.** |
| 0.H | 6 sub-phases (~2 wk) | Kafka ecosystem (`grezap/nexus-infra-kafka`): two 3-node KRaft clusters (East primary + West DR) + Schema Registry HA pair + REST Proxy + Kafka Connect + Debezium + ksqlDB + MirrorMaker 2 — 15 VMs on the `03-kafka` tier. Sub-phases below. **All 6 sub-phases closed; `nexus-infra-kafka` tagged `v0.1.0`.** | Produce a record to `kafka-east` → it appears on the mirrored topic on `kafka-west` via MM2; all 15 `03-kafka` VMs up; chained smoke gates ALL GREEN. |
| 0.H.1 | 3 d | Repo scaffold + one parameterised `kafka-node` Packer template (Debian 13 + Temurin JDK 21 + Apache Kafka 3.8.1 + Confluent Community 7.7.1; all 6 role systemd units delivered **disabled** — the Terraform role-overlays enable one per node). Both 3-node KRaft clusters brought up on the VMnet10 backplane (combined broker+controller, PLAINTEXT, RF=3); per-cluster cluster-UUID minted at Terraform time. Gateway dnsmasq dhcp-host reservations pin all 15 kafka MACs. | `kafka-east` + `kafka-west` each report a 3-voter KRaft quorum + an elected controller; RF=3 produce/consume round-trip verified; `smoke-0.H.1.ps1` (38 checks) green. |
| 0.H.2 | 2 d | Broker mutual TLS. Vault PKI `kafka-broker` role (server+client EKU, 90-day leaf TTL) + per-node `nexus-vault-agent.service` (narrow per-host AppRole) renders a leaf cert; both clusters flip PLAINTEXT→mTLS on the existing 9092/9093 ports (`ssl.client.auth=required` on the client + controller listeners). Kafka 3.8 native PEM keystore — no JKS/keytool/password. | Every broker listener requires a client cert; KRaft quorum + RF=3 round-trip verified over mTLS; `smoke-0.H.2.ps1` (92 checks) green. |
| 0.H.3 | 2 d | Schema Registry HA pair (`schema-registry-1/2`, Kafka-group-elected leader) + Confluent REST Proxy (`kafka-rest-1`). `role-overlay-ecosystem-tls.tf` renders a per-node Vault-PKI PEM keystore; each is a Kafka client of `kafka-east` over mTLS + serves its own HTTPS listener (server-side TLS only). The `kafka-broker` PKI role's `allowed_domains` extended to all 15 tier hostnames. | SR register-on-1 / fetch-from-2 round-trip; REST Proxy produce/consume round-trip; `smoke-0.H.3.ps1` (37 checks) green. |
| 0.H.4 | 2 d | Kafka Connect distributed cluster (`kafka-connect-1/2`, Debezium Postgres + SQL Server connector plugins loaded) + ksqlDB cluster (`ksqldb-1/2`). Both are Kafka clients of `kafka-east` over mTLS + serve their own HTTPS listeners. `role-overlay-ecosystem-tls.tf` now also emits a `keytool`-built PKCS#12 keystore/truststore — Apache Kafka's Connect `RestServer` + ksqlDB's `KsqlRestConfig` reject `ssl.keystore.type=PEM` (unlike Confluent `rest-utils`, which Schema Registry / REST Proxy use). | `/connector-plugins` lists the Debezium classes; ksqlDB pair agrees on `ksql.service.id` + `kafkaClusterId`; `smoke-0.H.4.ps1` (48 checks) green. |
| 0.H.5 | 2 d | MirrorMaker 2 cross-cluster DR pair (`mm2-1` east→west, `mm2-2` west→east) — Apache Kafka `connect-mirror-maker` in dedicated mode, one replication flow per node, mTLS to **both** clusters (per-cluster `<alias>.ssl.*` PEM auto-cascades to the producer/consumer/admin clients in dedicated mode). All 15 `03-kafka` VMs now up. | **Phase 0.H exit gate:** a fresh record produced to `kafka-east` appears on the mirrored `east.*` topic on `kafka-west` (and the `west.*` reverse); `smoke-0.H.5.ps1` (38 checks) green. |
| 0.H.6 | 1 d | **Close-out canon batch + cold-rebuild proof.** MASTER-PLAN sub-phase rows (above); `docs/infra/vms.yaml` ratified (all 15 kafka VMs run at the `kafka-node` template's baked 8 GB — `modules/vm`'s `memory_mb` resize is reserved-not-applied, tracked as a future enhancement; `ksqldb-2` IP typo `.99`→`.98` fixed); `docs/glossary.md` extended for the Confluent REST Proxy; ADRs 0020-0023 (KRaft combined broker+controller mode · Kafka-tier mTLS — Vault PKI PEM + PKCS#1→PKCS#8 + the Confluent PEM/PKCS#12 listener split · Terraform overlay ordering via `depends_on` not upstream-`.id` triggers · MirrorMaker 2 dedicated-mode one-flow-per-node topology); `nexus-infra-kafka` handbook (§1 walkthrough + §2 phase status + §3 operator runbooks incl. cold-rebuild canon + apply-time VM-layer recovery); both repos' CHANGELOGs reflect Phase 0.H complete; `nexus-infra-kafka` tagged `v0.1.0`. | All canon artefacts present and cross-linked; cold rebuild proven (`kafka.ps1 destroy` → `security.ps1 apply` → `kafka.ps1 apply` → the post-bring-up smoke gates `0.H.2`-`0.H.5` ALL GREEN — 92/37/48/38; `0.H.1` is the PLAINTEXT-era gate, correctly superseded by `0.H.2` once the brokers flip to mTLS). The rebuild surfaced four VMware-under-load VM-layer transients (recovered per handbook §3.7) + one verification-robustness fix (the MM2 journal-window). **Phase 0.H closed 2026-05-15.** |
| 0.I | 7 sub-phases (~2-3 wk) | **Status 2026-05-27: 0.I.1 through 0.I.5 SEALED (all live-ratified + cold-rebuild-proven). 14 obs VMs + 2 VRRP VIPs built. 0.I.5 added the OTel Collector active-active pair fronted by RR DNS `otel.nexus.lab` (no VIP per ADR-0031); receives OTLP gRPC :4317 + HTTP :4318 and routes traces -> Tempo, metrics -> Prom remote-write, logs -> Loki native OTLP. 4 transients (T30-T33) surfaced during 0.I.5 ratification (otelcol->otel rename / overlay hardcoded-user / PowerShell scope-qualifier / Terraform `$$` heredoc escape) all permanently fixed in source. 35 total transients across §3.A-§3.E. 0.I.6 (fleet-wide Vector + node_exporter shipper rollout) + 0.I.7 (close-out, tag `nexus-infra-observability v0.1.0`) pending.** **Observability tier (`grezap/nexus-infra-observability`, foundation tier `01-foundation` extension).** Grafana LGTM stack with full HA across the LB tier per ADR-0025 (supersedes the singleton obs-{metrics,tracing,logging} reservation, ADR-0038). **14 VMs + 2 VRRP VIPs.** Stack = Prometheus HA pair (each scrapes every fleet target; Grafana datasource dedups) + Alertmanager mesh (co-resident on Prom pair) + Loki simple-scalable × 3 on MinIO S3 + Tempo scalable × 3 on MinIO S3 + Grafana HA pair (active-active over shared PG, VRRP VIP `.184`) + Grafana PG HA (streaming repl, VRRP VIP `.185`) + OTel Collector pair (RR DNS, no VIP per ADR-0031 for write paths). Hybrid shipper: Prom *scrapes* `node_exporter` on every Linux VM + `windows_exporter` on ws2025 + engine-specific exporters; Vector *pushes* journald + `/var/log/*` to Loki; apps *push* OTLP traces to the OTel Collector. C# and Python equal-class via OpenTelemetry SDKs + Serilog's Loki sink (C#) + `python-logging-loki` / OTel logs (Py). MinIO reused as object store (dedicated `nexus-loki-app` + `nexus-tempo-app` tenants with scoped policies — mirrors 0.L.5 SR-shared-data pattern). Per-engine Packer + per-cluster TF env canon. Sub-phases: **0.I.1** Prom HA + Alertmanager (2 VMs) → **0.I.2** Loki SSD on MinIO (3 VMs) → **0.I.3** Tempo scalable on MinIO (3 VMs) → **0.I.4** Grafana HA + Grafana PG HA (2+2 VMs + 2 VIPs) → **0.I.5** OTel Collector pair (2 VMs) → **0.I.6** fleet-wide shipper rollout (Vector + node_exporter retrofit into 9 existing per-engine templates + ws2025 windows_exporter) → **0.I.7** close-out (DEMO-15 full-fleet obs tour + System B JSON demos + handbook playbooks + 3-layer canon sweep + tag `grezap/nexus-infra-observability v0.1.0`). | Sample app emits OTLP → trace in Tempo + Grafana Explore, metric in Prom HA + Grafana, log in Loki + Grafana; Grafana VIP failover sequence (ADR-0025 5-step gate) sub-second; both Proms scrape every fleet VM with `up=1`; Loki/Tempo memberlist rings tolerate 1 node loss; smoke gates `smoke-0.I.{1..7}.ps1` ALL GREEN; cold-rebuild proven (`terraform destroy` → `packer build` × 6 templates → from-zero `apply` → smoke ALL GREEN); `grezap/nexus-infra-observability` tagged `v0.1.0`. |
| 0.J | 1 wk | `nexus-shared` NuGet family published to GitHub Packages | DataFlow Studio v0.1 consumes ≥3 packages |
| 0.K | 2 wk | `portfolio` website shell (Blazor Server + MudBlazor + interactive SVG + Docs-as-Code pipeline + Live Tour skeleton) | localhost serves; CI green |
| 0.L | ~6 sub-phases (~2 wk) | **Lakehouse + registry tier.** New repo **`nexus-infra-lakehouse`** (tier `08-spark`, renamed from the planned `nexus-infra-spark` — more accurately captures MinIO + Iceberg + Spark; sealed w/ Greg 2026-05-23) = **0.L.1** MinIO distributed EC + **0.L.2** Iceberg REST catalog + dedicated PG master-replica HA (keepalived VIP `.151`) + **0.L.3** Spark (1 master + 2 workers). New repo **`nexus-infra-registry`** (tier `09-platform`) = **0.L.4** Harbor (Trivy + Vault OIDC). Existing **`nexus-infra-analytics`** extended = **0.L.5** StarRocks shared-data/CN (3 FE + 2 CN, MinIO storage volume; full HA per Greg). **0.L.6** close-out. 17 new VMs (11 lakehouse `.140-.150` + 1 Harbor `.115` + 5 SR shared-data `.37-.40`+`.30`). ADRs 0033-0037. Sub-phases ratified + cold-rebuild-proven individually (per `feedback_minimal_running_vms`). | MinIO bucket created + erasure-set node-loss tolerant · Iceberg table via REST in MinIO · Spark job writes Iceberg + time-travel · `docker push registry-1.nexus.lab/test:v1` + Trivy scan · StarRocks shared-data table in MinIO + CN elastic add. **0.L.1 MinIO SEALED 2026-05-23** — live-ratified + cold-rebuild-proven (`smoke-0.L.1.ps1` 41/41 GREEN; 2 transients fixed in source, handbook §3). **0.L.2 Iceberg catalog SEALED 2026-05-24** — Project Nessie ×2 (round-robin `iceberg.nexus.lab`) on a dedicated PostgreSQL 17 master-replica HA pair + keepalived VRRP VIP `iceberg-db.nexus.lab .151`; live-ratified + cold-rebuild-proven (`smoke-0.L.2.ps1` 28/28 GREEN; 8 transients fixed in source, handbook §3.4; ADR-0034). **0.L.3 Spark SEALED 2026-05-24** — Apache Spark 3.5.3 standalone **HA: 2 masters (ZooKeeper-elected) + 3 workers** + a dedicated 3-node **Apache ZooKeeper** ensemble (the one deliberate Apache-ZK exception; `recoveryMode=ZOOKEEPER`, no master VIP); Iceberg writes via the Nessie REST catalog (warehouse-by-name + `S3FileIO`/SDK-v2) into MinIO; live-ratified + cold-rebuild-proven (`smoke-0.L.3.ps1` 28/28 GREEN; 10 transients fixed in source incl. the executor-RPC firewall gap, handbook §3.6; ADR-0035). Lakehouse tier now 16 VMs. **0.L.4 Harbor SEALED 2026-05-25** — new repo **`nexus-infra-registry`** (tier `09-platform`), **HA Harbor** (ADR-0036): 2 stateless app nodes (`registry-1/2`, round-robin DNS `registry.nexus.lab`) + a dedicated PostgreSQL 17 + Redis master-replica HA datastore (`registry-pg-1/2`, keepalived VRRP VIP `registry-db.nexus.lab .119`); **image blobs in MinIO S3** (the 0.L.1 object store — registry's first non-lakehouse S3 consumer); **Trivy** scan + **cosign** signing; **Vault OIDC SSO** (Vault `identity/oidc` provider → AD via auth/ldap; local admin break-glass); mTLS via per-host Vault PKI; Harbor 2.14.4 offline installer (images baked, zero apply-time egress). Live-ratified + cold-rebuild-proven (`smoke-0.L.4.ps1` 41/41 GREEN; 7 apply-time transients fixed in source, handbook §3.2). Registry tier 4 VMs + 1 VIP. **0.L.5 StarRocks shared-data SEALED 2026-05-26** — `grezap/nexus-infra-analytics` extended with the second StarRocks cluster (parallel to the sealed shared-nothing one): **3 FE BDB-JE quorum (`sr-sd-fe-1/2/3` at `.37`/`.38`/`.39`) + 2 stateless CN (`sr-sd-cn-1` at `.30`, `sr-sd-cn-2` at `.40` — documented decade-spill from `.3x` to first free `.4x` slot)** running `run_mode=shared_data`; internal cloud-native tables in a MinIO storage volume `nexus_minio_starrocks` → `s3://starrocks/` (dedicated `nexus-starrocks-app` service account with a scoped `starrocks-tenant` MinIO policy; ADR-0037 chose this tighter least-privilege over reusing the lakehouse-app key). New per-engine Packer templates `packer/analytics-starrocks-sd-fe-node/` + `packer/analytics-starrocks-sd-cn-node/` (full isolation from the sealed cluster's templates, per-engine-template canon). Front door `starrocks-sd-fe.nexus.lab` (round-robin DNS over the 3 FE; ADR-0031). mTLS via per-host `starrocks-sd-server` Vault PKI; KV-seeded SQL RBAC + S3 creds. Live-ratified + **cold-rebuild proven** (`smoke-0.L.5.ps1` **69/69 GREEN** with chaos default-on: CN-loss → query still returns full results from shared MinIO; FE-leader-loss → re-election; 5 apply-time transients fixed in source — handbook §3.C — incl. the MinIO agent KV-read gap for new tenants, VMware DHCP-service-stopped fault, PowerShell backtick+`.Method` continuation, `SHOW STORAGE VOLUMES` returns name-only, and StarRocks shared-data's `tablet_create_timeout_second=10s` too short for first-write to S3). Fleet 88 → **93 VMs** (cluster `starrocks-sd` added to `vms.yaml`; analytics tier `04-analytics` now 20 VMs). **0.L.6 close-out 2026-05-26** — all 3 phase-0.L repos tagged: `nexus-infra-lakehouse v0.1.0` (covers 0.L.1+0.L.2+0.L.3) · `nexus-infra-registry v0.1.0` (covers 0.L.4) · `nexus-infra-analytics v0.2.0` (extends v0.1.0 with 0.L.5). **PHASE 0.L COMPLETE.** |
| 0.M | 2 d | **Foundation HA — 2nd AD domain controller** (`dc-nexus-2` on `01-foundation`). AD DS replica promoted into `nexus.lab` (multi-master replication) + DNS secondary; Vault `auth/ldap` + every domain-joined consumer point at both DCs. Closes the foundation's last SPOF (committed 2026-05-22). Scheduled AFTER 0.G.5/0.G.6 + 0.L + 0.I. | `Get-ADDomainController -Filter *` shows 2 DCs; `repadmin /replsummary` clean; power off `dc-nexus` → domain auth + DNS still served by `dc-nexus-2`; Vault LDAPS still authenticates; cold-rebuild proven. |
| 0.N | 5 d | **MongoDB sharded cluster** (extends `nexus-infra-oltp`): config-server replica set (3) + ≥2 shard replica sets (3 each) + `mongos` routers (2). New per-engine template(s) + per-cluster TF env + operator wrapper + smoke gate + handbook playbooks + System A/B demos + ADR + nexus-cli sharded-Mongo adapter coverage. Adds the **document-store sharding** showcase the 3-node RS (0.G.2) doesn't demonstrate (committed 2026-05-22). | `sh.status()` shows ≥2 shards + balancer ON; a sharded collection's chunks distributed across shards; write via `mongos` routes to the correct shard; kill a shard's primary → shard re-elects, cluster stays writable; smoke ALL GREEN; cold-rebuild proven. |
| 0.O | ~1.5 wk | **NEW infra project `nexus-infra-vitess`** — Vitess-sharded MySQL/Percona (`vtgate` routers + `vttablet` per MySQL instance + `vtctld` + etcd topo; ≥2 shards each with replicas). Full first-class treatment: Packer templates + per-cluster TF env + operator wrapper + smoke gate + handbook + System A/B demos + ADRs + cold-rebuild proof + tag `v0.1.0` + nexus-cli `VitessAdapter`. Adds the **relational (MySQL) sharding** showcase that PXC/Galera (0.G.3 — synchronous full replication, NOT sharding) doesn't provide (committed 2026-05-22). | `vtctldclient GetTablets` shows a sharded keyspace; query via `vtgate` fans out across shards; reshard / `PlannedReparentShard` demo; smoke ALL GREEN; CI green; cold-rebuild proven; tagged `v0.1.0`. |
| 0.P | ~1.5 wk | **NEW infra project `nexus-infra-citus`** — Citus-sharded PostgreSQL (1 coordinator + ≥2 workers; distributed tables via `create_distributed_table` + reference tables; coordinator HA optional). Full first-class treatment: Packer templates + per-cluster TF env + operator wrapper + smoke gate + handbook + System A/B demos + ADRs + cold-rebuild proof + tag `v0.1.0` + nexus-cli `CitusAdapter`. Adds the **relational (PostgreSQL) sharding** showcase that Patroni (0.G.4 — streaming replication, NOT sharding) doesn't provide (committed 2026-05-22). | `citus_shards` / `pg_dist_shard` show shards across all workers; a distributed query parallelizes across workers; add-a-worker + `rebalance_table_shards` demo; smoke ALL GREEN; cold-rebuild proven; tagged `v0.1.0`. |

**Phase 0 total: ~18 weeks** (0.D expanded to 5 sub-phases / ~3 wk; 0.E expanded from a one-week monolith to 6 sub-phases / ~5 wk — 0.E.1 + 0.E.2.x + 0.E.3.x + 0.E.4 closed and tagged `v0.1.0` 2026-05-07; **0.E.4e (cold-rebuild gate + 3 structural fixes) closed and tagged `v0.1.1` 2026-05-08**; **0.E.5 close-out canon batch closed and tagged `v0.2.0` 2026-05-08** marking Phase 0.E complete; **0.H expanded to 6 sub-phases / ~2 wk — 0.H.1-0.H.5 closed 2026-05-14, 0.H.6 close-out canon batch + cold-rebuild proof closed 2026-05-15, `nexus-infra-kafka` tagged `v0.1.0`** marking Phase 0.H complete; **0.G expanded to 8 sub-phases — 0.G.0 pre-flight + 0.G.1 (Redis Cluster) + 0.G.2 (MongoDB RS) closed 2026-05-17, 0.G.3 (Percona PXC + ProxySQL) closed 2026-05-18 via 0.G.3.5 architectural refactor (per-cluster Terraform state + per-engine Packer template — the canon born from 0.G.3's 16-transient stall, now applicable to 0.G.4+/0.G.7/0.I/0.L); 0.G.4 (Patroni + etcd + HAProxy HA pair, 8 VMs) CLOSED 2026-05-19 — ratification cycle surfaced 18 transients (Debian 13 trixie t64 PG-17 PGDG libicu72+libldap-2.5-0 bookworm fallback · patronictl 4 has no --version flag · vmrun vNIC no-carrier on fresh clone · tmpfs /tmp full on 1-GB-RAM etcd/haproxy nodes during Vault Agent install · dnsmasq serves nexus.local not nexus.lab · etcdctl JSON uses `"leader":<id>` not `"isLeader":true` · sudo required for /etc/nexus-*/etcd-root-password traverse · Patroni 4 doesn't honor password_file in restapi.authentication · pg_hba VMnet10-only blocked VMnet11 replication · Patroni 4 silently ignores bootstrap.users · haproxy chroot needs CAP_SYS_CHROOT so systemd unit can't have User= · haproxy default-server needs `check` keyword · PS quote/scope-qualifier traps in smoke gate · etc) — ALL fixed in source (handbook §3.4 18-row table); smoke gate 152/152 ALL GREEN; live ratification + cold-rebuild proof pending; the per-cluster framework + nexus-cli adapters + 0.G.5/0.G.6/0.G.7 sub-phases remain in plan.** Phase 0 total stays at ~18 weeks; remaining sub-phases 0.F-0.G (post-0.G.4) + 0.I-0.L unchanged from the original cadence).

**Committed architecture enhancements (2026-05-22): phases 0.M-0.P add ~4 weeks.** After the three remaining infrastructure phases — analytics (0.G.5/0.G.6) → Spark + Harbor (0.L) → observability (0.I, run last so it monitors the full fleet) — the plan adds four committed enhancements (Greg, 2026-05-22) to round out the **HA + sharding** coverage: **0.M** 2nd AD DC (foundation HA), **0.N** MongoDB sharded cluster (document-store sharding), **0.O** `nexus-infra-vitess` (MySQL/Percona sharding — distinct from 0.G.3's Galera *replication*), **0.P** `nexus-infra-citus` (PostgreSQL sharding — distinct from 0.G.4's Patroni *streaming replication*). Rationale: the OLTP relational/document tier (Mongo RS · Percona PXC/Galera · Patroni PG · SQL FCI+AG) is clustered + HA-via-**replication** by design; sharding was only demonstrated where it is the engine's native idiom (Redis · Kafka · ClickHouse · StarRocks). These phases add an explicit *relational + document sharding* axis as first-class showcase projects (full repos/templates/TF envs/operator wrappers/smoke gates/handbooks/System A+B demos/ADRs/cold-rebuild proofs/nexus-cli adapters/3-layer canon sweep). The nexus-cli adapter phase scope expands accordingly (adds `VitessAdapter`, `CitusAdapter`, sharded-Mongo coverage on top of the 7 base cluster adapters). Revised Phase 0 total ≈ 22 weeks.

### Phases 1–14 — application projects

Sequenced by dependency. Each phase ends when the **acceptance gate** (§6) passes.

| Phase | Project | Weeks | Hard prerequisites |
|---|---|---|---|
| 1 | dataflow-studio | 4 | 0.* complete · SQL AG · Kafka · Schema Registry · StarRocks · ClickHouse |
| 2 | tenantcore | 4 | Percona PXC · Vault · Kafka |
| 3 | sentinelml | 5 | PostgreSQL Patroni · ksqlDB · ClickHouse · Spark (for offline features) |
| 4 | localmind (with RAG v0.1) | 4 | MongoDB · pgvector on PG Patroni · Redis · Ollama |
| 5 | pulsenlp | 4 | PostgreSQL · ClickHouse · Spark (for DistilBERT training) |
| 6 | visioncore | 4 | MongoDB · ClickHouse |
| 7 | recoengine | 4 | Percona PXC · Kafka Streams |
| 8 | chronosight | 4 | ClickHouse · StarRocks · Spark · Prefect |
| 9 | querylens | 4 | SQL Server · PG Event Store · LocalMind |
| 10 | fieldsync | 5 | MongoDB · StarRocks · gRPC · MAUI Android SDK |
| 11 | nexus-platform | 6 | All above services usable as references |
| 12 | streamcore | 5 | East+West Kafka · MM2 · Chaos Harness |
| 13 | nexus-desk | 5 | AG listener · LocalMind Named Pipes · Docker Engine API · Nomad/Consul/Vault APIs |
| **14** | **lakehouse-core** | **5** | **Spark · MinIO · Iceberg · dbt · Prefect · JupyterHub** |

**Phases 1–14 total: ~58 weeks. Grand total: 72 weeks.**

---

## 5. Canon

### 5.1 Network

| VMnet | Mode | CIDR | DHCP | Role |
|---|---|---|---|---|
| **VMnet10** | Host-Only | **192.168.10.0/24** | Off | Cluster backplane — SQL replication, Kafka controller quorum, Vault cluster, etcd peer, Galera SST, CH Keeper raft, Redis cluster bus, Patroni REST, Mongo replication |
| **VMnet11** | NAT | **192.168.70.0/24** | On, scope .200–.250 (Packer builds only) | Mgmt + application traffic — all static IPs .10–.199 |

Both VMnets are **newly created** on host 10.0.70.101 — the host's existing VMnet1/VMnet8 are not used by NexusPlatform to avoid IP collisions with other tenants on the host.

Every NexusPlatform VM is dual-NIC (VMnet10 + VMnet11). Apps connect via VMnet11 IPs. Cluster-internal protocols bind to VMnet10.

Full IP plan in [`docs/infra/network.md`](./docs/infra/network.md).

### 5.2 Storage — per-VM directory layout

```
H:\VMS\NexusPlatform\          ← active VMs (NVMe stripe, ~5.37 TB free)
├── _templates\                ← Packer golden images
├── 01-foundation\             ← dc-nexus, vault-1..3, obs-*
├── 02-sqlserver\              ← sql-fci-1..2, sql-ag-rep-1..2, starwind
├── 03-kafka\                  ← east/west brokers, SR, Connect, ksqlDB, MM2, REST
├── 04-analytics\              ← StarRocks FE+BE, ClickHouse Keeper+shards
├── 05-oltp\                   ← Percona, PG+Patroni, Mongo, Redis
├── 06-orchestration\          ← Swarm managers+workers
├── 07-windows-workstations\   ← nexusdesk-dev
├── 08-spark\                  ← spark-master, spark-worker-1..2, minio-1, jupyterhub-1
├── 09-platform\               ← registry-1 (Harbor), prefect-server, unleash, marquez, backstage
└── 10-scratch\                ← dynamic provisioning, demo recording rigs

D:\VMS\NexusPlatform\          ← cold storage (2.49 TB free)
├── _iso\                      ← Debian 13, WS2025, Win11 ISOs
├── _packer-cache\
├── _snapshots\                ← per-release snapshots
└── _archive\                  ← decommissioned VMs
```

**Every VM lives in its own directory.** Mirrored in VMware Workstation Pro's Library pane as a folder tree (`📁 NexusPlatform / 00 Templates / 01 Foundation / …`).

Complete VM inventory with sizes, IPs, and directory paths in [`docs/infra/vms.yaml`](./docs/infra/vms.yaml).

### 5.3 Resource budget

- Host: 256 GB RAM total, 200 GB allocatable to NexusPlatform lab.
- Full fleet (107 VMs built/cold-rebuild-proven through 0.I.5; growing with the remaining observability + sharding tiers) well exceeds the host's RAM at max load → requires **environment targeting**:
  - `full` — all VMs (requires suspension strategy between clusters)
  - `data-engineering` — ~20 VMs (SQL AG + Kafka + Analytics + Spark + obs)
  - `ml` — ~20 VMs (PG Patroni + Kafka + ClickHouse + Spark + obs)
  - `saas` — ~14 VMs (Percona + Kafka + Swarm + Vault + obs)
  - `microservices` — ~24 VMs (all OLTPs + Kafka + Swarm + obs)
  - `demo-minimal` — ~10 VMs (enough to run one demo scenario at a time)
- Suspension via `nexus-cli infrastructure suspend-cluster <name>` — VMware Workstation Pro saves RAM state to disk, resumes in seconds.

### 5.4 RTO canon (from Vol00 Part 9)

See MASTER-PLAN §6 in the DOCS for the full table. Summary:
- SQL Server FCI node failover: ~25 s
- SQL Server AG sync: ~8 s auto
- PostgreSQL Patroni: ~12 s
- Percona PXC node: ~3 s
- ClickHouse replica: ~5 s
- StarRocks BE: ~15 s
- MongoDB primary: ~10 s
- Redis shard primary: ~3 s
- Kafka DR (east→west): <60 s via `nexus-cli kafka failover`
- Swarm service: <5 s
- Nomad job: <10 s

---

## 6. Acceptance gate — every project ships v0.1.0 only when all 17 boxes are checked

- [ ] Architecture pattern enforced by NetArchTest dependency rules
- [ ] ≥5 ADRs authored (Vol11 canon)
- [ ] ≥3 advanced SQL artifacts documented in `docs/sql-showcase.md`
- [ ] ≥1 PySpark job OR ML training script (where applicable per grid)
- [ ] Runbook with **panic button** section
- [ ] `nexus-cli deploy <project>` works end-to-end
- [ ] `.NET Aspire` AppHost runs locally in <60 s
- [ ] OTel traces, metrics, and logs visible in obs stack
- [ ] ≥80% application-layer coverage (E12 gate)
- [ ] Dockerfile + Swarm stack.yml + K8s manifests
- [ ] FluentMigrator up → down → up passes in CI
- [ ] README follows Vol11 14-section template
- [ ] Hero GIF + 3 screenshots + case study in `docs/`
- [ ] CHANGELOG, LICENSE (MIT), CONTRIBUTING, `.github/` present
- [ ] **≥1 Demo Playbook** in `docs/demos/DEMO-NN-*.md` following TEMPLATE
- [ ] **`nexus-cli demo run <DEMO-ID>`** wired and idempotent
- [ ] **Auto-recording** — VHS tape OR Playwright script reproducible in CI

---

## 7. Repo governance

### 7.1 Canonical repo naming

`grezap/nexus-*` for all infrastructure. Application project repos use the grid name directly (`dataflow-studio`, `tenantcore`, …). No exceptions.

### 7.2 Branching

- `main` protected.
- Feature branches: `feat/<short-topic>`, `fix/<short-topic>`, `chore/<short-topic>`.
- Semantic versioning per repo; each v0.1.0 requires the acceptance gate green.

### 7.3 Change control

- **Canon changes** (network, enhancements, gates, phase order) land here (`nexus-platform-plan`) first via PR, reviewed by self, then propagate to consumers.
- **Schema changes** bump the FluentMigrator version and ship a new DDL file in `schemas/<project>/`; the corresponding project repo picks up on next release.
- **ADR lifecycle**: `planned` → `proposed` → `accepted` | `deprecated` | `superseded`. Tracked in `docs/adr/index.md`.

### 7.4 Dependency discipline

- Shared code lands in `nexus-shared` NuGet only when a **second consumer** needs it (not prematurely).
- Inter-project HTTP / Kafka contracts live in `docs/api/{openapi,asyncapi}/` of the producer repo and are consumed via schema-first tooling.

---

## 8. Demo framework

See [`docs/demos/README.md`](./docs/demos/README.md) for the full specification. Summary:

- **14 scenarios** (DEMO-01 … DEMO-14). DEMO-14 is the cross-project "single row traverses everything" meta-scenario.
- **Every playbook** follows [`docs/demos/TEMPLATE.md`](./docs/demos/TEMPLATE.md) exactly — 9 required sections.
- **Non-technical entry point**: [`docs/start-here.md`](./docs/start-here.md).
- **Recording pipeline** is deterministic and automated (VHS + Playwright + ffmpeg). No manual video capture.
- **Seed data**: enterprise-quality synthetic datasets in `docs/demo-data/` — 10K customers, 500K orders, 26M financial ticks, 200-doc corpus, etc. Reproducible via code generators.

---

## 9. Immediate next actions

1. ✅ Meta-repo `nexus-platform-plan` created and v0.1.0 (Plan) committed.
2. ⏭ Amend `portfolio-index` with 5 new infra rows + `lakehouse-core` Vol 14 row + link to this repo.
3. ⏭ Phase 0.A: create VMnet10 + VMnet11 on host 10.0.70.101.
4. ⏭ Phase 0.B: begin `nexus-infra-vmware` repo with Packer templates.

---

## Appendix A — Quick reference

| Canon item | Value |
|---|---|
| Host | Windows 11 Pro, 10.0.70.101, 256 GB RAM |
| Hypervisor | VMware Workstation Pro 25H2 (Type-2) |
| VMnet10 | Host-Only, 192.168.10.0/24 |
| VMnet11 | NAT, 192.168.70.0/24 |
| Active VMs path | `H:\VMS\NexusPlatform\` (NVMe stripe) |
| Cold storage path | `D:\VMS\NexusPlatform\` |
| Linux base | Debian 13 (Trixie) + Ubuntu 24.04 LTS (per doc) |
| Windows base | Server 2025 Standard (Core + Desktop) + Windows 11 Enterprise 24H2 |
| .NET | .NET 10 / C# 13 everywhere |
| Migration tool | FluentMigrator + DbUp |
| Orchestrator | Prefect 3 |
| Lakehouse | Iceberg on MinIO |
| Transformation | dbt Core |
| Notebooks | JupyterHub |
| Registry | Harbor |
| Metrics long-term | VictoriaMetrics |
| Lineage | OpenLineage + Marquez |
| Feature flags | Unleash + OpenFeature |
| Testing | xUnit + Testcontainers + PactNet + NetArchTest + Stryker.NET |
| Python | uv + Ruff + mypy --strict + Pydantic v2 + Polars |

---

_Last updated 2026-04-20 · Plan v0.1.0_
