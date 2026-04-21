# Host setup — Phase 0.A: VMnet bootstrap

Canonical runbook for preparing host `10.0.70.101` (Windows 11 Pro, VMware Workstation Pro) for the NexusPlatform 65-VM lab.

## Prerequisites

| Item | Requirement |
|---|---|
| OS | Windows 11 Pro 24H2+ |
| VMware | Workstation Pro 17.5 or later |
| Memory | 256 GB total (≥ 200 GB reserved for lab) |
| Storage | `D:\VMS` (Striped) + `H:\VMS` (NVMStriped) |
| PowerShell | 7.x (pwsh) — needed by the bootstrap script |
| Shell | Must be **Run as Administrator** |

### Platform limits

VMware Workstation Pro on Windows supports exactly **20 virtual networks**: `vmnet0` through `vmnet19`. This is enforced by `C:\ProgramData\VMware\netmap.conf` and cannot be extended. `vmnet0` is reserved for Bridged; `vmnet1` (Host-Only) and `vmnet8` (NAT) are the defaults. On this host both vmnet1 and vmnet8 are in use by other tenants and **must not be touched**.

## Canon — networks to create

| Device | Role | Subnet | Gateway | DHCP | Purpose |
|---|---|---|---|---|---|
| `vmnet10` | Host-Only | 192.168.10.0/24 | — (isolated) | **Disabled** | Cluster backplane — AG/Patroni/Galera/Kafka Raft/Mongo RS/CH Keeper replication |
| `vmnet11` | NAT | 192.168.70.0/24 | 192.168.70.2 (VMware NAT) | Scoped 192.168.70.200–.250 (Packer only) | Mgmt (SSH/RDP), app traffic, app-facing endpoints |

All VM-assigned IPs are **static** per `docs/infra/vms.yaml`. The narrow DHCP scope on vmnet11 exists only so fresh Packer builds receive a bootstrap lease; production VMs never hit it.

## Path A — scripted (preferred)

```powershell
# From an ELEVATED pwsh 7 session on the host:
cd 'F:\_CODING_\Repos\Local Development And Test\Portfolio_Project_Ideas\workspace\nexus-platform-plan'
./scripts/phase-0a-create-vmnets.ps1                  # apply
./scripts/phase-0a-create-vmnets.ps1 -WhatIfOnly      # dry-run first
```

The script:

1. Stops VMware NAT + DHCP services.
2. Registers `vmnet10` as Host-Only with subnet `192.168.10.0/24`, DHCP removed.
3. Registers `vmnet11` as NAT with subnet `192.168.70.0/24`, DHCP + NAT services attached.
4. Restarts NAT + DHCP services.
5. Applies updates and enumerates `Get-NetAdapter` to verify.

## Path B — GUI fallback (Virtual Network Editor)

Launch `C:\Program Files (x86)\VMware\VMware Workstation\vmnetcfg.exe` as Administrator.

### Create VMnet10

1. **Add Network…** → pick `VMnet10` → OK.
2. Select `VMnet10`. Type = **Host-only**.
3. Subnet IP = `192.168.10.0`, Subnet mask = `255.255.255.0`.
4. **Uncheck** "Use local DHCP service to distribute IP addresses to VMs".
5. **Uncheck** "Connect a host virtual adapter to this network" *only if* you want host-side isolation from this backplane; keep it checked if you want to reach VMs from the host directly (recommended).

### Create VMnet11

1. **Add Network…** → pick `VMnet11` → OK.
2. Select `VMnet11`. Type = **NAT**.
3. Subnet IP = `192.168.70.0`, Subnet mask = `255.255.255.0`.
4. Check "Use local DHCP service…".
5. **DHCP Settings…** → Starting IP `192.168.70.200`, Ending IP `192.168.70.250`, lease 30 min.
6. **NAT Settings…** → Gateway IP should auto-populate as `192.168.70.2`.

Click **Apply** and **OK**. Wait ~10 seconds for services to cycle.

## Verification

Run in a regular (non-elevated) pwsh session:

```powershell
Get-NetAdapter | Where-Object { $_.Name -match 'VMnet(10|11)$' } |
    Select-Object Name, Status, MacAddress, LinkSpeed | Format-Table

Get-NetIPAddress -InterfaceAlias 'VMware Network Adapter VMnet10' |
    Select-Object IPAddress, PrefixLength

Get-NetIPAddress -InterfaceAlias 'VMware Network Adapter VMnet11' |
    Select-Object IPAddress, PrefixLength
```

Expected:

| Adapter | Host IP | Status |
|---|---|---|
| VMware Network Adapter VMnet10 | 192.168.10.1/24 | Up |
| VMware Network Adapter VMnet11 | 192.168.70.1/24 | Up |

NAT check:

```powershell
Get-Service 'VMware NAT Service' | Select-Object Status, StartType
# Expected: Running / Automatic
```

Config sanity (read-only — do not edit by hand):

```powershell
Get-Content 'C:\ProgramData\VMware\vmnetnat.conf'   | Select-String 'vmnet11|192.168.70'
Get-Content 'C:\ProgramData\VMware\vmnetdhcp.conf'  | Select-String 'vmnet11|192.168.70'
Get-Content 'C:\ProgramData\VMware\netmap.conf'     | Select-String 'vmnet1[01]'
```

## Evidence to commit

After a successful run, attach to this repo:

- `docs/infra/evidence/phase-0a-get-netadapter.txt` — `Get-NetAdapter` output
- `docs/infra/evidence/phase-0a-vnet-editor.png` — screenshot of Virtual Network Editor showing vmnet10 + vmnet11
- `docs/infra/evidence/phase-0a-ping.txt` — `ping 192.168.10.1` + `ping 192.168.70.2` output

(Evidence is tracked separately so re-runs on new hosts do not pollute history.)

## Rollback

If vmnet10 or vmnet11 is wrong, remove cleanly in an elevated shell:

```powershell
$vl = 'C:\Program Files (x86)\VMware\VMware Workstation\vnetlib64.exe'
& $vl -- stop nat
& $vl -- stop dhcp
& $vl -- remove adapter vmnet10
& $vl -- remove adapter vmnet11
& $vl -- start dhcp
& $vl -- start nat
```

Then re-run `./scripts/phase-0a-create-vmnets.ps1`.

## Next phase

Once vmnet10/11 are verified, proceed to **Phase 0.B — `nexus-infra-vmware` bootstrap**: Packer HCL templates for Debian 13, Ubuntu 24.04, Windows Server 2025 (Core + Desktop), Windows 11 Enterprise, each producing a base image tagged with the git SHA of the template. That phase is tracked separately in the `nexus-infra-vmware` repo.
