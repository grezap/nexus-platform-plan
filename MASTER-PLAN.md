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

### 1.2 Infrastructure repositories (5)

| # | Repo | Role |
|---:|---|---|
| I1 | `nexus-shared` | NuGet library family — `Nexus.Kafka`, `Nexus.Observability`, `Nexus.Outbox`, `Nexus.Avro`, `Nexus.Vault`, `Nexus.Primitives`, `Nexus.Audit`, `Nexus.Tenancy`, `Nexus.Migrations`, `Nexus.Analyzers` |
| I2 | `nexus-infra-vmware` | Packer HCL + Terraform (`vmware-desktop` provider) + Ansible playbooks for Tier 1 |
| I3 | `nexus-infra-swarm-nomad` | Swarm + Nomad + Consul + Vault bootstrap onto Tier 1 VMs |
| I4 | `nexus-infra-k8s` | Kubernetes cluster bootstrap + per-app manifest index |
| I5 | `nexus-infra-registry` | Harbor private registry (image hosting, Trivy scanning, OIDC) |

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
| E30 | Portfolio Demo Playbooks | 14 guided scenarios (DEMO-01 → DEMO-14). Markdown step-by-step + annotated screenshots (primary). **Auto-generated recordings only** — VHS (.tape) for terminal + Playwright (`video: 'on'`) for browser + ffmpeg concat for combined flows. `nexus-cli demo record --all` in CI on release tags. No manual video. See [`docs/demos/README.md`](./docs/demos/README.md). |

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
| 0.E.4e | 1 d | Cold-rebuild gates the lab against off-cluster reachability with stock CA bundle (the test 0.E.4 lacked). Three structural fixes: (1) server.crt = leaf+intermediate via Vault Agent split-script (consul_tls v7, nomad_tls v5, portainer_tls v2); ca.pem stays as intermediate. (2) `inet filter forward` chain in Packer-baked nftables.conf + role-overlay-nftables-forward.tf hot-fix accept rules for docker_gwbridge + docker0 (Linux runs all FORWARD chains; empty drop killed swarm ingress DNAT for off-cluster sources). (3) stage1 ssh stdin-pipe pattern (was failing past ~6KB single-quoted argv on Windows ssh.exe). New smoke gate `scripts/smoke-0.E.4e.ps1` (409 checks; Block C asserts off-cluster TLS validation with stock root-only bundle). Cold-rebuild verified end-to-end. ADR-0019. **v0.1.1 tagged 2026-05-08.** | `terraform destroy` + `packer build` + `terraform apply` + `smoke-0.E.4e.ps1` → ALL GREEN with stock root-only CA bundle on build host. Single operator-runbook prerequisite: wipe stale `nexus/swarm/{,nomad-}{bootstrap,agent}-token{,s}` from Vault KV before re-apply (canonical self-validating fix tracked for 0.E.5+). |
| 0.E.4 | 5 d | Portainer CE clustered Swarm service + supporting infra. **(0.E.4a)** NFS — `nfs-kernel-server` on `nexus-gateway` exporting `/srv/nfs/portainer-data` NFSv4-only with `fsid=0` pseudo-root to manager IPs; per-manager mount via `192.168.70.1:/` at `/var/lib/portainer-data`. Gateway nftables in-place patched for tcp/2049 from manager IPs. **(0.E.4b)** TLS — `pki_int/roles/portainer-server` (CN `portainer.nexus.lab` + per-host IP SANs); per-manager Vault Agent template renders + split-script writes `/etc/portainer/tls/{server.crt,server.key,ca.pem}`. **(0.E.4c)** DNS — dnsmasq `host-record=portainer.nexus.lab,IP1,IP2,IP3` (multi-A round-robin). **(0.E.4d)** Stack deploy — sticky-seeded `nexus/portainer/admin-bcrypt` (24-char alphanumeric plaintext + bcrypt cost=10); per-manager Vault Agent renders bcrypt to `/etc/portainer/admin-password.txt` (HCL heredoc; not inline-string); `docker stack deploy -c portainer-stack.yml portainer` from manager-1 with server (1 replica, manager-pinned) + agent (mode global, 6 tasks). nftables `flush ruleset` + Docker iptables-nft conflict resolved via per-overlay sequential dockerd restart (rebuilds DOCKER-INGRESS DNAT). | `docker stack ls` includes `portainer`; `docker service ls` shows server 1/1 + agent 6/6; `https://portainer.nexus.lab:9443/api/system/status` returns 200 with TLS chain validating against the build-host CA bundle; admin login works with the plaintext from KV; ~180-check chained smoke gate (`smoke-0.E.4.ps1`) green. |
| 0.F | 2 wk | `grezap/nexus-cli` — .NET 10 Native AOT; commands: `infrastructure`, `cluster-status`, `failover-test`, `kafka failover`, `demo run/record`. **v0.1.0 alpha shipped 2026-05-07** (`cluster-status` vertical slice live; AOT binary 9.7 MB win-x64; 4 verbs stubbed for v0.2–v0.5). | Single binary ≤25 MB on linux-x64 + win-x64 |
| 0.G | 1 wk | local-data-stack audit + port to VMware, tagged v1.0.0 | All 6 data clusters healthy on VMware; 10 Grafana dashboards |
| 0.H | 2 wk | Kafka ecosystem: East + West KRaft · SR × 2 · Connect × 2 + Debezium · ksqlDB × 2 · MM2 × 2 · REST × 2 | Produce east → appears on west via MM2 |
| 0.I | 1 wk | Full observability roll-out: obs-metrics/tracing/logging · Alertmanager · VictoriaMetrics · Marquez · Prefect UI | Sample app emits OTLP → trace in Jaeger, metric in Prom+VM, log in Seq, lineage in Marquez |
| 0.J | 1 wk | `nexus-shared` NuGet family published to GitHub Packages | DataFlow Studio v0.1 consumes ≥3 packages |
| 0.K | 2 wk | `portfolio` website shell (Blazor Server + MudBlazor + interactive SVG + Docs-as-Code pipeline + Live Tour skeleton) | localhost serves; CI green |
| 0.L | 1 wk | `nexus-infra-spark` + `nexus-infra-registry` (Harbor) stood up | MinIO bucket created · Spark master reachable · `docker push registry-1.nexus.local/test:v1` works |

**Phase 0 total: ~18 weeks** (0.D expanded to 5 sub-phases / ~3 wk; 0.E expanded from a one-week monolith to 4 sub-phases / ~5 wk — the harden work (TLS, ACL, Nomad-Vault rewire, Portainer NFS-backed clustered deploy) was nontrivial; 0.E.1 + 0.E.2.x + 0.E.3.x + 0.E.4 all closed and tagged 2026-05-07 in `nexus-infra-swarm-nomad`. Phase 0 total bumps from ~14 to ~18 weeks; remaining sub-phases 0.F–0.L unchanged from the original cadence).

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
- Full fleet (~65 VMs) ≈ ~620 GB RAM at max load → requires **environment targeting**:
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
