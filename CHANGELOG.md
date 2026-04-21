# Changelog

All notable changes to this repository will be documented in this file.
The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `.gitignore` — top-level ignore rules covering OS/editor junk and, as
  belt-and-suspenders for the planning repo, the same key-bearing-artifact
  blocks used downstream (`**/Autounattend.xml` except `.tpl`,
  `windows-keys.json`, `.nexus/`, `secrets/`, `*.pem`, `*.key`, `.env*`).
- `.gitleaks.toml` — mirrors `nexus-infra-vmware/.gitleaks.toml` with the
  `microsoft-product-key` custom rule.
- `.github/workflows/secret-scan.yml` — runs `gitleaks detect` on every PR
  and push to `main`.

## [0.1.3] — 2026-04-22 — "Windows licensing canon"

### Added

- **ADR-0144** (`docs/adr/ADR-0144-windows-licensing.md`) — decision record for
  the Windows licensing posture. Primary path: Visual Studio (MSDN) dev/test
  keys for all owner builds on host `10.0.70.101`. Documented fallback:
  Microsoft Evaluation Center ISOs (180 d Server, 90 d Win11, rearm-able) so
  any third party cloning the blueprint can reproduce the lab without an MSDN
  subscription.
- `docs/infra/licensing.md` — canonical how-to covering Path A (Evaluation)
  and Path B (MSDN), Vault KV paths `nexus/windows/product-keys/{ws2025-core,
  ws2025-desktop, win11ent}`, Packer integration snippet, pre-Phase-0.D
  bootstrap via NTFS-ACL'd `%USERPROFILE%\.nexus\secrets\windows-keys.json`,
  5-layer defense-in-depth against key leakage (`.gitignore` + `.gitleaks.toml`
  + pre-commit hook + CI gitleaks + Packer log filtering), operational
  playbook (add template / rotate key / audit), FAQ.

### Canon decisions locked

- **Primary activation path**: MSDN dev/test keys, Vault-custodied.
- **Fallback activation path**: Evaluation Center ISOs, rearm automated by
  `nexus-cli infrastructure rearm-windows`.
- **Keys-in-git posture**: zero. `Autounattend.xml` gitignored at every path;
  only `Autounattend.xml.tpl` templates are versioned. Keys substitute at
  Packer build time.
- **`product_source` Packer variable**: `msdn` (default for owner) or
  `evaluation` (default for the public blueprint) — single knob, no repo
  changes needed to switch paths.

## [0.1.2] — 2026-04-21 — "Phase 0.A closeout + nexus-gateway pattern"

### Discovered (platform constraints)

- **One NAT per host**: VMware Workstation Pro on Windows allows exactly one NAT
  virtual network, and the slot is held by the pre-existing VMnet8 (other tenants).
  `VMnet11` therefore cannot be NAT.
- **`vnetlib64.exe` regression on WS 17.5+**: sub-commands `set vnet … addr`,
  `add nat`, and `add dhcp` silently no-op (no stderr, no exit code). Only
  `add adapter` / `remove adapter` are reliable. `vmnetcfg.exe` GUI is the
  canonical configuration surface for subnet/DHCP.

### Changed (canon)

- **VMnet11 type: NAT → Host-Only** (subnet + role unchanged).
- **`nexus-gateway` VM** introduced as VM #0 of the fleet: Debian 13 minimal
  (512 MB / 1 vCPU / 4 GB disk) with NIC0 Bridged to physical LAN, NIC1 static
  `192.168.70.1/24` on VMnet11, NIC2 static `192.168.10.1/24` on VMnet10.
  Runs `nftables` masquerade, `dnsmasq` DHCP scope `.200–.250` + DNS forwarder,
  `chrony` NTP source. Must be built first in Phase 0.B so subsequent lab VMs
  have internet egress.
- **VM count**: 65 → 66 (lab VMs unchanged at 65; `nexus-gateway` is VM #0).
- **VMnet11 default gateway**: `192.168.70.2` (VMware NAT) → `192.168.70.1`
  (`nexus-gateway`).
- **Host-side adapter IPs**: VMnet10 = `192.168.10.1/24`, VMnet11 = `192.168.70.254/24`
  (`.1` reserved for `nexus-gateway`).
- **Phase 0.B exit gate**: now explicitly requires `nexus-gateway` powered on
  and a test VM able to `apt update` through it before the Packer template
  work is considered complete.

### Updated

- `docs/infra/network.md` — rewritten to document platform constraints #1–3,
  the nexus-gateway edge-router pattern, GUI-canonical config procedure,
  adapter-cycle and static-IP fallbacks, updated panic-button runbook.
- `docs/infra/host-setup.md` — revised end-to-end to reflect actual runbook
  used on host `10.0.70.101`; vnetlib64 limited to `add adapter`; GUI steps
  promoted to canonical; verification table matches what the host produced.
- `docs/infra/vms.yaml` — `vmnet11.mode: nat` → `host-only`, added
  `vmnet11.gateway: 192.168.70.1`, added `clusters.edge.nexus-gateway` node
  entry, bumped `vm_count` and `plan_version`.
- `MASTER-PLAN.md` — Phase 0.A/0.B table entries rewritten; Phase 0.B begins
  with nexus-gateway build before Packer template work.

## [0.1.1] — 2026-04-21 — "Phase 0.A errata + host bootstrap"

### Changed

- **Network canon amended**: `VMnet20` → **`VMnet10`**, `VMnet21` → **`VMnet11`**.
  VMware Workstation Pro on Windows caps virtual networks at `vmnet0..vmnet19`
  (confirmed by inspection of `C:\ProgramData\VMware\netmap.conf` which enumerates
  `network0..network19`). The originally-published VMnet20/21 numbers were
  unreachable on the platform. Subnets (192.168.10.0/24 and 192.168.70.0/24)
  and roles are unchanged. Updated: `MASTER-PLAN.md`, `docs/infra/network.md`,
  `docs/infra/vms.yaml`, `README.md`.

### Added

- `docs/infra/host-setup.md` — Phase 0.A runbook for creating `VMnet10`
  (Host-Only, 192.168.10.0/24, DHCP off) and `VMnet11` (NAT, 192.168.70.0/24,
  DHCP scoped .200–.250) on host `10.0.70.101` with both `vnetlib64.exe` CLI
  and `vmnetcfg.exe` GUI paths, plus verification.
- `scripts/phase-0a-create-vmnets.ps1` — elevated PowerShell that drives
  `vnetlib64.exe` to stop services, register vmnet10/11, set type/subnet,
  disable DHCP on vmnet10, scope DHCP on vmnet11, restart services, and
  verify adapters appear in `Get-NetAdapter`.

## [0.1.0] — 2026-04-20 — "Plan"

Initial canon publication. No implementation — planning artifacts only.

### Added

- `MASTER-PLAN.md` — 14 projects, 30 enhancements (E1–E30), 12 build phases, acceptance gates.
- `docs/start-here.md` — non-technical entry point with demo scenario cards.
- `docs/skills-coverage.md` — 4-dimension skill matrix per project.
- `docs/demos/` — 14 demo playbook stubs (DEMO-01 … DEMO-14), playbook template, auto-recording spec.
- `docs/demo-data/README.md` — synthetic seed data kit specification.
- `docs/adr/index.md` — ~75 planned ADRs catalogued with owners and status.
- `docs/infra/vms.yaml` — ~65-VM inventory with IPs, VMnets, host directories, roles.
- `docs/infra/network.md` — VMnet10 (Host-Only 192.168.10.0/24) + VMnet11 (NAT 192.168.70.0/24) canon.
- `schemas/` — 14 project subdirectories seeded with DDL skeletons.

### Canon decisions locked

- Migration tool: **FluentMigrator** (SQL stores) + **DbUp** (analytical).
- Native AOT paths: **Dapper + FluentMigrator**; non-AOT: EF Core permitted.
- Terraform VMware provider: `vmware/vmware-desktop` + `vmrun` fallback.
- Workflow orchestrator: **Prefect 3** (OSS self-host).
- Lakehouse table format: **Apache Iceberg**.
- Object store: **MinIO**.
- Transformation layer: **dbt Core** (adapters: starrocks, clickhouse).
- Notebooks: **JupyterHub**.
- Private registry: **Harbor**.
- Long-term metrics: **VictoriaMetrics**.
- Alerting: **Alertmanager** + Karma UI.
- Feature flags: **Unleash** (self-host).
- Data lineage: **OpenLineage** + **Marquez**.
- Service catalog (optional): **Backstage**.
- Testing: xUnit + Testcontainers + PactNet + NetArchTest + Stryker.NET + Verify.Xunit + WireMock.Net.
- Load testing: **NBomber**.
- Python toolchain: **uv** + **Ruff** + **mypy --strict** + **Pydantic v2** + **Polars**.
- RAG (LocalMind v0.1): **pgvector** on PostgreSQL Patroni + local ONNX embeddings (bge-small-en).
