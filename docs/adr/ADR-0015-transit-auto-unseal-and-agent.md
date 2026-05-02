# ADR-0015 — Phase 0.D.5: Transit auto-unseal + Vault Agent on member servers + leaf TTL drop + GMSA scaffolding + bootstrap-creds rotation

- **Status**: Accepted (code-complete 2026-05-03; greenfield re-cluster operator-driven)
- **Date**: 2026-05-03
- **Deciders**: Greg Zapantis
- **Supersedes**: per-cluster shamir-only seal from ADR-0011 (transit-mode replaces shamir for the 3-node cluster's day-to-day unseal); 1-year leaf TTL from ADR-0012 (90 d at this phase)
- **Superseded by**: —
- **Related**: ADR-0011 (Vault cluster), ADR-0012 (PKI hierarchy), ADR-0013 (LDAPS auth), ADR-0014 (foundation creds via AppRole + KV)

## Context

Phase 0.D.5 closes Phase 0.D by tightening five orthogonal posture knobs after 0.D.1–0.D.4 left the lab functionally complete on the read-path side. The five sub-deliverables and the rationale for grouping them:

1. **`MinPasswordLength=14` + KV-managed AD-cred rotation** (5.1) — pre-0.D.5 the policy was 12 (sized to the original `NexusAdmin!1` bootstrap pwd). Vault's `nexus-ad-rotated` policy generates 24-char pwds; rotation overlay can sync KV→AD without humans. Bumping to 14 is safe + strictly tighter.
2. **Leaf cert TTL 1y → 90 d** (5.2) — the `vault_pki_rotate_listener` overlay's `>30 days remaining` probe was already in place; dropping TTL from 365 d to 90 d quarterizes the rotation cadence.
3. **GMSA infrastructure** (5.3) — Group Managed Service Accounts replace Windows-side svc-account passwords with auto-rotating managed accounts. Phase 0.D.5 scaffolds the KDS root key + AD group + sample GMSA so Phase 0.G+ workloads (SQL Server svc account, IIS app pool identities) just slot in.
4. **Vault Agent on member servers** (5.4) — per-host AppRole + Agent renders foundation creds locally, replacing the build-host-side AppRole pattern from 0.D.4 for production-shaped consumers.
5. **Transit auto-unseal** (5.5) — eliminates manual unseal at boot. The 3-node cluster delegates seal/unseal to a single-node `vault-transit` companion via the `seal "transit"` stanza.

The five are grouped because they share an operator workflow (security env apply with new toggles + foundation env re-apply for KV-dependent state) and share the underlying infrastructure (Vault PKI from 0.D.2; KV from 0.D.4; AppRole pattern from 0.D.4).

## Decision

### 5.1 — MinPasswordLength=14 + KV→AD rotation overlay

- Foundation env's `dc_password_min_length` default 12 → 14. Foundation seed-mirror defaults bumped to ≥14 chars (`NexusDSRMBootstrap!2026`, `NexusLocalAdminBootstrap!2026`).
- New `role-overlay-dc-rotate-bootstrap-creds.tf` syncs KV → AD whenever a triggered cred changes:
  - **In scope:** domain Administrator + nexusadmin (via `Set-ADAccountPassword`).
  - **NOT in scope:** DSRM. Discovered 2026-05-02 that ntdsutil's password prompt uses `GetConsoleMode`/`ReadConsole` APIs that fail under SSH/redirected stdin with WIN32 0x1 (ERROR_INVALID_FUNCTION). Skip + manual ops via RDP+ntdsutil console (handbook §1k.1). Memory: `feedback_ntdsutil_dsrm_console_mode_ssh.md`.
- Pre-flight skip when any KV pwd is shorter than `MinPasswordLength` (avoids first-apply policy-violation false-failure).
- New `scripts/rotate-foundation-creds.ps1` operator helper generates 24-char Vault-policy-compliant pwds + writes them to `nexus/foundation/dc-nexus/{dsrm,local-administrator}` and `nexus/foundation/identity/nexusadmin`.

**Sub-decision: nexusadmin membership remediation overlay** — diagnostic 2026-05-02 found `nexusadmin` was NOT in Domain Admins or Enterprise Admins, despite the original `dc_nexus_promote` v4 step intending to add it. The chained semicolon-separated one-liner silently failed at the `Add-ADGroupMember` step. New `role-overlay-dc-nexusadmin-membership.tf` idempotently asserts membership using the domain Administrator's credentials (read from KV). Required for the GMSA KDS-root + future Enterprise-Admins-gated cmdlets.

### 5.2 — Leaf cert TTL 1y → 90d

- `vault_pki_leaf_ttl` default `8760h` → `2160h` (90 days).
- `vault_ldaps_cert_ttl` default `8760h` → `2160h`.
- `vault_pki_rotate_listener` overlay v1 → v2: idempotency probe gains a 3rd condition — cert validity span (`notAfter - notBefore`) must be within ±10 % of `LEAF_TTL`. Without this, a 1y cert with 360 days remaining would skip rotation forever after the operator dropped TTL to 90d.
- Same span-check added to dc-nexus LDAPS cert overlay (`role-overlay-vault-ldaps-cert.tf` v4 → v5).
- `scripts/smoke-0.D.2.ps1` `MinLeafTtlDays` default 300 → 30 (matches the rotate-listener overlay's reissue threshold).

### 5.3 — GMSA scaffolding (no consumers yet)

- `role-overlay-dc-gmsa.tf` provisions:
  - `nexus-gmsa-consumers` AD security group in `OU=Groups`.
  - Sample GMSA `gmsa-nexus-demo$` in `OU=ServiceAccounts` with `PrincipalsAllowedToRetrieveManagedPassword` = consumers group. Idempotent `Set-ADServiceAccount -PrincipalsAllowed...` post-create; some `New-ADServiceAccount` calls silently drop this field when caller lacks Enterprise Admins.
  - KDS root key — **probe-only** at 0.D.5.5 close-out. `Add-KdsRootKey` on Server 2025 returns ERROR_NOT_SUPPORTED (HRESULT 0x80070032) under SSH; `Invoke-Command -Credential Administrator` returns a fake GUID without persisting. Same console-session-required class as ntdsutil DSRM. Memory: `feedback_kds_rootkey_server2025_ssh.md`. Manual remediation via RDP into dc-nexus (handbook §1k.2).

### 5.4 — Vault Agent on member servers

- Two narrow Vault policies (`nexus-agent-dc-nexus`, `nexus-agent-nexus-jumpbox`); each grants read on ONLY the KV paths its host actually consumes.
- Two AppRoles bound to those policies; role-id+secret-id JSON sidecars on the build host (`$HOME\.nexus\vault-agent-{dc-nexus,nexus-jumpbox}.json`, mode 0600).
- `role-overlay-windows-vault-agent.tf` installs Vault Agent as the `nexus-vault-agent` Windows service on each host:
  - Downloads `vault_<version>_windows_amd64.zip` from `releases.hashicorp.com` via `nexus-gateway` egress.
  - Stages role-id, secret-id, CA bundle, agent.hcl, render.tpl to `C:\ProgramData\nexus\agent\` (NTFS ACL: SYSTEM + Administrators only).
  - Creates the Windows service via `New-Service` (NOT `sc.exe` — PS argv parsing eats embedded double quotes around `binPath` when expanding `$binPath`; `sc.exe` dumps usage help instead of creating).
  - Verifies the rendered cred file is non-empty within 30 s.
- Render targets (proof-of-concept):
  - dc-nexus: `nexus/foundation/dc-nexus/dsrm` → `C:\ProgramData\nexus\agent\dsrm.txt`
  - nexus-jumpbox: `nexus/foundation/identity/nexusadmin` → `C:\ProgramData\nexus\agent\nexusadmin-pwd.txt`

### 5.5 — Transit auto-unseal

- New `vault-transit` VM (single node, file storage backend, shamir-init manual unseal). Same Packer template as cluster nodes; firstboot's IP→hostname map gains a 4th class (`192.168.70.124 → vault-transit`). Per `memory/feedback_vmware_per_vm_folders.md`: own subdir `01-foundation/vault-transit/`.
- Transit secrets engine + key `nexus-cluster-unseal` + Vault policy `nexus-cluster-unseal` (encrypt+decrypt on that key only) + non-expiring 720h-period token issued for cluster auth.
- `seal "transit"` stanza delivered to vault-1/2/3 as `/etc/vault.d/seal-transit.hcl` drop-in. Vault server's `-config=/etc/vault.d/` (DIRECTORY) merges `vault.hcl` + `seal-transit.hcl`. **Packer rebuild required** for the directory-mode `vault.service` ExecStart.
- Cluster init in transit-mode uses `-recovery-shares` / `-recovery-threshold` (returns `recovery_keys_b64`; auto-unseal handles day-to-day). Followers skip manual unseal entirely.
- **Greenfield** chosen over `vault operator migrate -from=shamir -to=transit`: lab-acceptable since all state recreates from TF. Operator sequence:
  1. `pwsh -File scripts\security.ps1 destroy`
  2. `Push-Location packer\vault; packer init .; packer build .; Pop-Location`
  3. `pwsh -File scripts\security.ps1 apply -Vars enable_vault_transit_unseal=true`
  4. `pwsh -File scripts\foundation.ps1 apply` (re-seeds KV-dependent state)
  5. `pwsh -File scripts\security.ps1 smoke`

## Consequences

### Positive

- Vault cluster reboots without operator-driven unseal (transit handles it).
- KV-managed bootstrap creds round-trip end-to-end: Vault generates → KV → foundation env applies KV → AD live state in sync.
- 90 d leaf-cert cadence quarterizes rotation; existing rotate-listener probe (>30 days remaining) handles renewal without operator action between cycles.
- GMSA scaffold lets future SQL Server / IIS workloads (Phase 0.G+) slot in without retrofitting AD.
- Vault Agent pattern proven on the 2 existing Windows hosts; same overlay shape extends to future Windows fleet members.

### Negative / accepted

- Two structural Server-2025-via-SSH limits surfaced + canonized (DSRM password reset, KDS root key add). Both deferred to manual RDP/console ops as quarterly tasks. Documented in handbook §1k.1, §1k.2.
- Greenfield re-cluster destroys the existing live state (KV data, init keys, PKI CA, LDAP config). All recreates from TF on apply, but the operator must remember to re-apply foundation env after security env to re-seed KV.
- vault-transit's listener cert is the 0.D.1-style self-signed bootstrap until a future PKI rotation; cluster→transit handshake uses `tls_skip_verify=true`. Lab-acceptable; production would issue vault-transit's cert from PKI before the cluster's first init.
- vault-transit can't auto-unseal itself (it IS the unseal key custodian); manual unseal once per reboot of vault-transit. 0.D.6+ could chain a second transit Vault for HSM-style topology if needed.
- Phase A code (this commit) causes a one-time idempotent cascade replacement of ~20 resources on next security apply (new triggers added). Each replacement is a no-op in shamir mode; ~15 min total. Greg can apply naively OR skip directly to greenfield-with-transit.

### Neutral

- AppRole secret-id rotation cadence (lab: `secret_id_ttl=0`) matches ADR-0014 for the foundation-reader AppRole + the new agent AppRoles.
- vault-transit RAM 2 GB (deviation from vms.yaml's 4 GB default for foundation deb13s, matching the cluster's 0.D.1 deviation; ratified in vms.yaml).

## Lessons captured (now memory canon)

- `feedback_ntdsutil_dsrm_console_mode_ssh.md` — ntdsutil pwd prompt uses console-mode reads that fail under SSH; manual ops only.
- `feedback_kds_rootkey_server2025_ssh.md` — Add-KdsRootKey on Server 2025 returns ERROR_NOT_SUPPORTED under SSH; Invoke-Command returns fake GUID without persisting.
- `feedback_vmware_per_vm_folders.md` — each VM gets its own subdir under tier dir; team-grouping is via tier+naming, not nested team subdirs.

## Operational rules

- Smoke: `pwsh -File scripts\security.ps1 smoke` (chains 0.D.1–5; 0.D.5.5 transit checks gate-on operator flag once greenfield runs).
- Quarterly DSRM rotation: `vault kv put nexus/foundation/dc-nexus/dsrm password=...` then RDP into dc-nexus + `ntdsutil "set dsrm password" "reset password on server null" "q" "q"` interactively. See handbook §1k.1.
- KDS root key add: RDP into dc-nexus as Administrator + `Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10))`. See handbook §1k.2.
- Force-regenerate AppRole secret-id: `terraform taint null_resource.vault_foundation_approle && terraform apply -target=...` (or the agent_approles equivalent for Vault Agent role-ids).
