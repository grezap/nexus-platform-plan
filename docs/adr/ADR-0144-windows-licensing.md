# ADR-0144 — Windows licensing posture

- **Status**: Accepted
- **Date**: 2026-04-22
- **Deciders**: Greg Zapantis
- **Supersedes**: —
- **Superseded by**: —
- **Related**: ADR-0140 (toolchain split), Phase 0.B–0.D in MASTER-PLAN

## Context

The NexusPlatform 66-VM lab runs multiple Windows guests (non-optional):

- `dc-nexus` — **Windows Server 2025 Desktop Experience** (AD DC + DNS + RSAT host)
- SQL Server AG nodes — **Windows Server 2025 Core** (headless, SQL Server 2022 FCI + AG)
- `nexus-desk` test workstations — **Windows 11 Enterprise** (for WinForms/WPF/WinUI 3 app verification)

Windows guests require activation. Four paths exist:

1. Microsoft Evaluation Center — 180-day (Server) / 90-day (Win11) eval ISOs, rearm-able, free, desktop-edition watermark.
2. Visual Studio subscription (MSDN) — dev/test keys for Server + Win11 Enterprise, valid while subscription is active, no watermark, no rearm.
3. Azure Hybrid Benefit — requires an existing EA; not applicable.
4. Retail keys — overkill for a lab.

## Decision

1. **Primary path: Visual Studio (MSDN).** The repo owner holds an active Visual Studio subscription; MSDN dev/test keys are used for all Windows Packer builds performed on host `10.0.70.101`.
2. **Documented fallback: Evaluation Center.** The blueprint also works end-to-end with Evaluation ISOs so that any third party cloning the repos can reproduce the lab without an MSDN subscription. Rearm cadence is automated by `nexus-cli infrastructure rearm-windows`.
3. **Secret custody: Vault KV v2.** MSDN product keys live exclusively at `nexus/windows/product-keys/{ws2025-core, ws2025-desktop, win11ent}` (Phase 0.D onwards). Packer reads them at build time via the `vault` function. They are never written to disk outside of the guest's `Autounattend.xml` inside the VM.
4. **Pre-Phase-0.D bootstrap.** Until Vault is online, MSDN keys sit in `%USERPROFILE%\.nexus\secrets\windows-keys.json` (NTFS-ACL-locked to the repo owner) and are referenced via a gitignored Packer var-file. A pre-commit hook + CI `gitleaks` scan blocks any accidental key from entering git.
5. **Keys never in git.** `.gitignore` blocks `Autounattend.xml` at any path — only `Autounattend.xml.tpl` templates are versioned. Keys substitute at build time.
6. **Build-time transparency.** Every Packer build logs `product_source = msdn|evaluation` (not the key). `packer build` aborts with a clear error if `product_source=msdn` and no key is resolvable from Vault / bootstrap file.
7. **Public-facing docs default to Evaluation.** `nexus-platform-plan/docs/infra/licensing.md` and `nexus-infra-vmware/docs/licensing.md` lead with the Evaluation path (portfolio viewers without MSDN follow along). MSDN is documented as the "actual builds" override.

## Consequences

### Positive

- Blueprint reproducible by anyone (Evaluation path) while the owner's actual builds stay clean (MSDN).
- Single canonical secret location (Vault) that matches all other infra secrets.
- Zero chance of a key in git (templated `Autounattend`, `.gitignore`, `gitleaks`).
- Rearm dance avoided on owner's fleet — Evaluation rearm logic still there as a safety net.

### Negative / accepted

- Bootstrap chicken-and-egg: before Vault is online, keys must sit on local disk. Mitigated by (a) NTFS ACL, (b) gitignore, (c) pre-commit hook, (d) 30-day rotation policy from Phase 0.D onwards.
- Two code paths in every Windows Packer template (`msdn` vs `evaluation`). Mitigated by shared `_shared/ansible/roles/windows_base` with a single parameter.

### Neutral

- Portfolio viewers cloning the repo without MSDN will get 180-day / 90-day Eval VMs with a small desktop watermark — fine for a lab and fully legal.

## Operational rules

- **Key rotation**: MSDN doesn't expire unless the subscription lapses. If a key is compromised or the subscription changes, run `nexus-cli windows rotate-keys` which:
  1. Fetches new keys from MSDN portal (manual paste into `vault kv put`).
  2. Triggers Packer rebuilds for all three templates.
  3. `terraform apply` replaces the running Windows VMs in rolling fashion.
- **Compliance**: MSDN dev/test terms prohibit production use; this lab is explicitly portfolio/dev/test, which fits.
- **Offboarding**: if the repo is ever handed to another developer, they switch `product_source` from `msdn` to `evaluation` in a single tfvar override — no repo changes needed.

## Artefacts produced

- `docs/infra/licensing.md` — canonical how-to.
- `nexus-infra-vmware/docs/licensing.md` — implementation-side how-to.
- `.gitleaks.toml` + `.gitignore` entries in every repo that could plausibly hold keys.
- `scripts/check-no-product-key.ps1` in `nexus-infra-vmware` (pre-commit + CI).
