# Licensing canon

How Windows guests in the NexusPlatform 66-VM lab are licensed. See [ADR-0144](../adr/ADR-0144-windows-licensing.md) for the decision record.

## TL;DR

| Guest | Primary (owner builds) | Fallback (portfolio viewers) |
|---|---|---|
| Windows Server 2025 Core | **MSDN dev/test key** from Vault `nexus/windows/product-keys/ws2025-core` | **Evaluation ISO** — 180 days, rearm-able 5× |
| Windows Server 2025 Desktop | **MSDN dev/test key** from Vault `nexus/windows/product-keys/ws2025-desktop` | **Evaluation ISO** — 180 days, rearm-able 5× |
| Windows 11 Enterprise | **MSDN dev/test key** from Vault `nexus/windows/product-keys/win11ent` | **Evaluation ISO** — 90 days, rearm-able |
| Any Linux guest | none required (FOSS) | none required |

Compliance: MSDN terms permit dev/test use only. This lab is explicitly a portfolio/dev/test environment.

## Path A — Evaluation Center (default for anyone cloning the blueprint)

For reproducibility, the public-facing plan defaults to Evaluation ISOs. No payment, no Microsoft account required beyond the download form.

### ISOs

| OS | URL |
|---|---|
| Windows Server 2025 (Core/Desktop selectable at install) | https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025 |
| Windows 11 Enterprise | https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise |

Packer reads the ISO URL + SHA256 from `packer/<template>/variables.pkr.hcl`. Override via:

```bash
packer build -var 'iso_url=file:///D:/ISOs/WinServer2025Eval.iso' -var 'iso_checksum=sha256:...' <template>
```

### Rearm

Evaluation editions expire. `nexus-cli infrastructure rearm-windows` runs weekly as a scheduled Nomad job:

```powershell
# What it does per VM, non-interactive:
slmgr /dlv                                 # read days left
if ($daysLeft -lt 14) { slmgr /rearm; shutdown /r /t 0 }
```

Server Eval rearms 5 times → ~3 years; Win11 Eval rearms fewer times → ~1 year. Since Packer rebuilds are cheap, the canonical answer to "VM nearing final expiry" is `make <template>` → `terraform apply -replace=module.<vm>`.

### Watermark

Evaluation Server Desktop and Windows 11 show a small bottom-right watermark. Does not affect functionality. Not present in demo screenshots taken from MSDN builds.

## Path B — MSDN / Visual Studio subscription (owner's actual builds)

Visual Studio Professional / Enterprise subscriptions include dev/test keys for:

- Windows Server 2025 (all editions)
- Windows 11 Enterprise

Keys: https://my.visualstudio.com → Downloads → Product Keys.

### Vault storage (from Phase 0.D onwards)

```bash
vault kv put nexus/windows/product-keys/ws2025-core \
  key="XXXXX-XXXXX-XXXXX-XXXXX-XXXXX" \
  edition="ServerStandard" \
  source="msdn"

vault kv put nexus/windows/product-keys/ws2025-desktop \
  key="XXXXX-XXXXX-XXXXX-XXXXX-XXXXX" \
  edition="ServerStandard" \
  source="msdn"

vault kv put nexus/windows/product-keys/win11ent \
  key="XXXXX-XXXXX-XXXXX-XXXXX-XXXXX" \
  edition="Enterprise" \
  source="msdn"
```

### Packer integration

```hcl
# packer/ws2025-core/variables.pkr.hcl
variable "product_source" {
  type    = string
  default = "evaluation"         # "msdn" or "evaluation"
}

locals {
  product_key = var.product_source == "msdn" ? vault("/nexus/windows/product-keys/ws2025-core", "key") : ""
  edition     = var.product_source == "msdn" ? "ServerStandard" : "ServerStandardEval"
}
```

Owner runs:

```bash
packer build -var product_source=msdn packer/ws2025-core
```

### Pre-Phase-0.D bootstrap (no Vault yet)

Because the very first Windows VM is needed before Vault comes up, Phase 0.B.4 uses a bootstrap file:

```
%USERPROFILE%\.nexus\secrets\windows-keys.json    (NTFS-ACL restricted to owner)
```

Format:

```json
{
  "ws2025-core":    { "key": "XXXXX-...", "edition": "ServerStandard" },
  "ws2025-desktop": { "key": "XXXXX-...", "edition": "ServerStandard" },
  "win11ent":       { "key": "XXXXX-...", "edition": "Enterprise" }
}
```

Referenced via a gitignored var-file: `packer/<template>/secrets.auto.pkrvars.hcl` (path pattern in `.gitignore`). Once Vault is online, the bootstrap file is destroyed (`Remove-Item -Force`) and `vault kv put` takes over.

## Preventing key leakage — defense in depth

1. **`.gitignore`** — blocks `Autounattend.xml` at every path (only `*.tpl` committed), `*.pkrvars.hcl` (owner-local overrides), `windows-keys.json`, `.nexus/`, `secrets/`, `*.pem`, `*.key`.
2. **`.gitleaks.toml`** — custom rule matches the Microsoft product key pattern `[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}`.
3. **Pre-commit hook** — `scripts/check-no-product-key.ps1` refuses commits containing product keys.
4. **CI workflow** — gitleaks runs on every PR in every repo; PR fails if match found.
5. **Packer build logs** — log level filtered to suppress keys; only `product_source` written.

## Operational playbook

### Add a new Windows template

1. Create `packer/<template>/` per repo convention.
2. Commit `Autounattend.xml.tpl` — template form with `{{ product_key }}` placeholder.
3. Add Vault path to the table in this doc.
4. Build: `packer build -var product_source=msdn packer/<template>` (or `evaluation`).

### Rotate a key

1. Update Vault: `vault kv put nexus/windows/product-keys/<template> key=...`.
2. Rebuild template: `make <template>`.
3. Rolling replace: `terraform apply -replace=module.<vm>`.

### Audit

`nexus-cli windows audit-licensing` prints:

```
Template         Source       Activation   DaysLeft
ws2025-core      msdn         Genuine      ∞
ws2025-desktop   msdn         Genuine      ∞
win11ent         msdn         Genuine      ∞
```

Any `source=evaluation` entries trigger a `nexus-cli` warning with `DaysLeft`.

## FAQ

**Q: Can I reproduce the lab without MSDN?**
A: Yes — everything works with Evaluation ISOs. You'll get a watermark on desktop Windows VMs and you'll need to rearm periodically, both non-issues for a lab.

**Q: What about Windows 11 Pro instead of Enterprise?**
A: Pro is not used. Enterprise is chosen because the `nexus-desk` apps target enterprise features (BitLocker, AppLocker demos, Windows Hello for Business).

**Q: Can I use a retail key?**
A: Technically yes — treat it as `source: retail` in Vault. But a retail key ties to one install; rebuilds would exhaust the activation count. MSDN or Evaluation is strongly preferred.

**Q: What about SQL Server?**
A: SQL Server 2022 Developer Edition is free for dev/test and has full Enterprise feature parity — used for all SQL Server nodes. No licensing concerns.

**Q: What about Visual Studio itself on Windows 11?**
A: Community Edition is free for dev/test; Professional/Enterprise comes from the MSDN subscription. Install orchestrated by Ansible `windows_base` role.
