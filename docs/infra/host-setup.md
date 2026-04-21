# Host setup — Phase 0.A: VMnet bootstrap

Canonical runbook for preparing host `10.0.70.101` (Windows 11 Pro, VMware Workstation Pro) for the NexusPlatform 65-VM lab. **Revision history:** v0.1.1 assumed `vnetlib64.exe` could fully automate this; host verification proved it cannot on Workstation Pro 17.5+. v0.1.2 (this document) uses the GUI as the canonical configuration surface and limits `vnetlib64.exe` to adapter creation only.

## Prerequisites

| Item | Requirement |
|---|---|
| OS | Windows 11 Pro 24H2+ |
| VMware | Workstation Pro 17.5 or later |
| Memory | 256 GB total (≥ 200 GB reserved for lab) |
| Storage | `D:\VMS` (Striped) + `H:\VMS` (NVMStriped) |
| PowerShell | 7.x (pwsh) — elevated for the adapter-creation step |
| Shell | Must be **Run as Administrator** for steps that touch services or network adapters |

## Platform constraints (discovered during Phase 0.A; hard limits)

| # | Constraint | Consequence |
|---|---|---|
| 1 | Exactly 20 virtual networks (`vmnet0..vmnet19`) | Canon uses VMnet10 + VMnet11 (VMnet20/21 of the original plan were unreachable) |
| 2 | **One NAT network per host** (slot held by VMnet8, in use by other tenants) | VMnet11 is **Host-Only**; internet egress is provided by the `nexus-gateway` VM (Phase 0.B, VM #0) |
| 3 | `vnetlib64.exe` sub-commands `set vnet … addr`, `add nat`, `add dhcp` silently no-op on WS 17.5+ | Subnet / NAT / DHCP wiring must be done in `vmnetcfg.exe` GUI. Only `add adapter` and `remove adapter` from `vnetlib64` are reliable. |

## Canon — networks to create

| Device | Type | Subnet | DHCP | Host-side adapter IP | Gateway for VMs |
|---|---|---|---|---|---|
| `vmnet10` | Host-Only | 192.168.10.0/24 | Off | `192.168.10.1` | — (isolated backplane) |
| `vmnet11` | Host-Only | 192.168.70.0/24 | Off (served by `nexus-gateway` dnsmasq scope `.200–.250`) | `192.168.70.254` | `192.168.70.1` (`nexus-gateway` VM) |

All VM-assigned IPs are **static** per [`vms.yaml`](./vms.yaml). The narrow DHCP scope on vmnet11 exists only so fresh Packer builds receive a bootstrap lease; production VMs never hit it.

## Step 1 — Create the adapters (scripted, elevated)

```powershell
cd 'F:\_CODING_\Repos\Local Development And Test\Portfolio_Project_Ideas\workspace\nexus-platform-plan'
./scripts/phase-0a-create-vmnets.ps1 -WhatIfOnly   # dry-run
./scripts/phase-0a-create-vmnets.ps1               # apply
```

The script registers `vmnet10` and `vmnet11` adapters via `vnetlib64.exe -- add adapter`. It also *attempts* to configure subnet/NAT/DHCP via `vnetlib64` sub-commands, but those silently no-op on WS 17.5+ — that's OK, we do it in the GUI next. The script's adapter-count verification at the end may say "found 0" on older PowerShell binding — ignore, run the manual verification at end of Step 3.

## Step 2 — Configure subnets + DHCP in `vmnetcfg.exe` (GUI, elevated)

```powershell
Start-Process 'C:\Program Files (x86)\VMware\VMware Workstation\vmnetcfg.exe' -Verb RunAs
```

### VMnet10 — Host-Only, isolated backplane

1. Select `VMnet10` in the list.
2. **Type** → `Host-only`.
3. ✅ "Connect a host virtual adapter to this network"
4. ❌ "Use local DHCP service to distribute IP addresses to VMs"
5. **Subnet IP** `192.168.10.0`, **Subnet mask** `255.255.255.0`.
6. **Apply**.

### VMnet11 — Host-Only, routed via `nexus-gateway` (NOT NAT)

> **Do not try to set Type=NAT.** VMware will refuse with *"Cannot change network to NAT: Only one network can be set to NAT."* Platform Constraint #2. Use Host-Only.

1. Select `VMnet11`.
2. **Type** → `Host-only`.
3. ✅ "Connect a host virtual adapter to this network"
4. ❌ "Use local DHCP service to distribute IP addresses to VMs" (dnsmasq on `nexus-gateway` serves DHCP, not VMware).
5. **Subnet IP** `192.168.70.0`, **Subnet mask** `255.255.255.0`.
6. **Apply** → **OK**.

## Step 3 — Bind host adapter IPs

After the GUI applies, Windows sometimes keeps APIPA (`169.254.x.x`) on the new adapters until they are cycled. In an elevated pwsh:

```powershell
Disable-NetAdapter -Name 'VMware Network Adapter VMnet10','VMware Network Adapter VMnet11' -Confirm:$false
Start-Sleep 2
Enable-NetAdapter  -Name 'VMware Network Adapter VMnet10','VMware Network Adapter VMnet11' -Confirm:$false
```

If Windows still shows APIPA after the cycle, hard-set the host IPs (this path was used on `10.0.70.101` during the Phase 0.A run that produced this document):

```powershell
New-NetIPAddress -InterfaceAlias 'VMware Network Adapter VMnet10' -IPAddress 192.168.10.1   -PrefixLength 24
New-NetIPAddress -InterfaceAlias 'VMware Network Adapter VMnet11' -IPAddress 192.168.70.254 -PrefixLength 24
```

`192.168.70.1` is reserved for `nexus-gateway` (Phase 0.B); the host takes `.254` on VMnet11.

## Step 4 — Verification

```powershell
Get-NetIPAddress -InterfaceAlias 'VMware Network Adapter VMnet10','VMware Network Adapter VMnet11' |
    Where-Object AddressFamily -eq IPv4 |
    Select-Object InterfaceAlias, IPAddress, PrefixLength | Format-Table -AutoSize

Get-Service 'VMware NAT Service','VMnetDHCP' | Select-Object Name, Status | Format-Table -AutoSize
```

Expected:

| Adapter | Host IP | Status |
|---|---|---|
| VMware Network Adapter VMnet10 | 192.168.10.1/24 | Up |
| VMware Network Adapter VMnet11 | 192.168.70.254/24 | Up |
| VMware NAT Service | Running |
| VMnetDHCP | Running |

## Evidence to commit

After a successful run, save under `docs/infra/evidence/`:

- `phase-0a-get-netadapter.txt` — `Get-NetAdapter` + `Get-NetIPAddress` output
- `phase-0a-vnet-editor.png` — screenshot of Virtual Network Editor showing vmnet10 + vmnet11 both Host-Only
- `phase-0a-host-services.txt` — VMware service statuses

Evidence is git-tracked but not part of the canon itself — re-runs on new hosts overwrite freely.

## Rollback

If vmnet10 or vmnet11 need to be recreated cleanly:

```powershell
$vl = 'C:\Program Files (x86)\VMware\VMware Workstation\vnetlib64.exe'
& $vl -- remove adapter vmnet10
& $vl -- remove adapter vmnet11
# Then re-run Steps 1-3 above.
```

## Next phase

Phase 0.A closes when the verification table in Step 4 matches expected. Proceed to **Phase 0.B** in `nexus-infra-vmware`:

1. **VM #0 — `nexus-gateway`** (Debian 13, 512 MB, Bridged + VMnet11 + VMnet10, nftables + dnsmasq + chrony). Must be built first so subsequent VMs can `apt update`.
2. Packer golden images: `deb13`, `ubuntu24`, `ws2025-core`, `ws2025-desktop`, `win11ent`.
3. Terraform `vmware-desktop` provider modules, env targets (`foundation`, `data`, `ml`, `saas`, `microservices`, `demo-minimal`).
