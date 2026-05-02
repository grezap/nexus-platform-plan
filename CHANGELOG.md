# Changelog

All notable changes to this repository will be documented in this file.
The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added — Phase 0.D.5 canonization (2026-05-03)

- **ADR-0015** (`docs/adr/ADR-0015-transit-auto-unseal-and-agent.md`) — Phase 0.D.5
  groups five orthogonal posture tightenings: (5.1) `MinPasswordLength=14` +
  KV-managed AD-cred rotation overlay (Administrator + nexusadmin synced
  from KV; DSRM deferred to manual ops per Server 2025 SSH console-mode
  limit); (5.2) leaf cert TTL `8760h → 2160h` (90 d) for Vault listeners +
  dc-nexus LDAPS, with rotate-listener probe gaining a span-check that
  catches TTL changes on existing certs; (5.3) GMSA scaffolding (KDS root
  key probe-only -- Add-KdsRootKey on Server 2025 returns ERROR_NOT_SUPPORTED
  under SSH; manual RDP/console ops -- plus `nexus-gmsa-consumers` AD group
  + sample GMSA `gmsa-nexus-demo$`); (5.4) Vault Agent on dc-nexus +
  nexus-jumpbox via per-host narrow AppRoles + creds JSON sidecars; (5.5)
  Transit auto-unseal via new single-node `vault-transit` companion VM
  (greenfield re-cluster operator-driven; code-complete, apply pending).

- **`docs/infra/vms.yaml`** — `vault-transit` row added to the foundation
  cluster (192.168.10.124 / 192.168.70.124, MAC `00:50:56:3F:00:43`, own
  subdir `01-foundation/vault-transit/` per `feedback_vmware_per_vm_folders.md`).

- **`docs/adr/index.md`** — registers ADR-0015.

### Added — Phase 0.D sub-phase canonization (2026-05-02 housekeeping batch)

- **`MASTER-PLAN.md` Phase 0.D expanded** from a one-week monolith to 5
  named sub-phases (0.D.1–0.D.5) with explicit exit gates per sub-phase.
  The original 1-week allocation in §4 stays neutral — 0.D.1 through 0.D.4
  are already shipped within the original window; 0.D.5 (Transit
  auto-unseal + GMSA + Vault Agent + leaf-TTL drop to 90 d) lands in the
  remaining slack. Acceptance criterion line updated to
  `vault kv get nexus/foundation/dc-nexus/dsrm` (the 0.D.4 deliverable
  shape) — the original `nexus/sqlserver/oltpdb` path lands when 0.E or
  the data env writes DB creds.

- **ADR-0011** (`docs/adr/ADR-0011-vault-3-node-raft.md`) — 3-node Vault
  Raft cluster on integrated Raft storage (no Consul dependency, since
  Consul is canonically Phase 0.E). Dual-NIC topology (VMnet11 service
  .121–.123 via dnsmasq dhcp-host MAC reservations; VMnet10 cluster
  backplane 192.168.10.121-.123). Init JSON to `$HOME\.nexus\vault-init.json`
  (mode 0600 via icacls), NOT in tfstate. KV-v2 mount at `nexus/`.
  Userpass + AppRole at post-init. Approved RAM deviation: 2 GB per node
  (vms.yaml originally said 4 GB; vms.yaml updated in this batch to match
  observed sufficient sizing).

- **ADR-0012** (`docs/adr/ADR-0012-vault-pki-hierarchy.md`) — two-tier PKI:
  `pki/` root CA (10 y, signs only the intermediate) + `pki_int/`
  intermediate (5 y) + `vault-server` PKI role (1 y leaf TTL,
  `allow_ip_sans=true`). Per-node listener cert reissue with atomic-swap
  + SIGHUP reload (zero-downtime). Root CA distributed to build host's
  `$HOME\.nexus\vault-ca-bundle.crt` + every Vault node's system trust
  store. Operator drops `VAULT_SKIP_VERIFY` and sets `VAULT_CACERT`
  pointing at the bundle. Legacy 0.D.1 trust shuffle retired.

- **ADR-0013** (`docs/adr/ADR-0013-vault-ldaps-search-then-bind.md`) —
  LDAPS pulled forward from 0.D.5 to 0.D.3 (mid-phase deviation, ratified
  via Canon mapping table) because plain LDAP/389 simple bind fails
  wholesale in this AD env regardless of `LDAPServerIntegrity` (tested
  values 2/1/0 — all reject). LDAPS leaf cert issued from `pki_int/issue/
  vault-server` for `dc-nexus.nexus.lab`, installed in
  `LocalMachine\My`, NTDS restarted. Vault auth/ldap = LDAPS,
  search-then-bind, **`upndomain=""`** (Vault issue #27276 — `upndomain`
  silently rewrites `{{.Username}}` in userfilter, breaking AD's
  `sAMAccountName` semantics). `secrets/ldap` (`schema=ad`,
  `password_policy=nexus-ad-rotated`) replaces deprecated `ad` engine.
  Static rotate-role for `svc-demo-rotated` rotates the AD password
  daily. AD-side bind account holds 4 ACEs on `OU=ServiceAccounts`
  (Reset Password, Change Password, RP/WP `userAccountControl`),
  delegated via `dsacls /I:S` — never via Account Operators shortcut.

- **ADR-0014** (`docs/adr/ADR-0014-foundation-creds-via-approle-kv.md`) —
  Foundation env's plaintext bootstrap defaults migrated to `nexus/foundation/...`
  in Vault KV. Six paths seeded sticky-one-time (preserves operator
  rotations): dsrm, local-administrator, nexusadmin, vault userpass,
  svc-vault-ldap bind cred, svc-vault-smoke. Foundation env's
  `provider "vault"` (~> 4.0) authenticates via AppRole role-id +
  secret-id JSON sidecar at `$HOME\.nexus\vault-foundation-approle.json`
  (mode 0600). Three `vault_kv_secret_v2` data sources resolve dsrm /
  local-administrator / nexusadmin for the dc-nexus + jumpbox overlays.
  `local.foundation_creds` ternary centralizes the
  `enable_vault_kv_creds ? KV : variable-default` logic. Bind/smoke
  overlays write back to KV after generating fresh AD pwds (best-effort
  with vault-init.json probe). `nexus-foundation-reader` policy enforces
  read on `nexus/foundation/*`, write only on `nexus/foundation/ad/*` —
  positive + 2 negative tests in smoke gate. Default
  `enable_vault_kv_creds` flipped `false → true` at close-out per
  `feedback_terraform_partial_apply_destroys_resources.md`.

### Updated

- **`docs/infra/vms.yaml`** — vault-1/2/3 `ram_gb 4 → 2` (approved
  deviation ratified at 0.D.4 close-out). Comment block above the nodes
  documents the deviation rationale + production-grade revert path.

- **`docs/adr/index.md`** — registers ADR-0011 / 0012 / 0013 / 0014 with
  their status + dates.

### Added — original (pre-0.D housekeeping)

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
