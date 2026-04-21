# Network Canon

Every NexusPlatform VM is dual-NIC: one interface on **VMnet10** (cluster backplane, Host-Only, isolated) and one on **VMnet11** (management + applications, Host-Only, routed through a dedicated `nexus-gateway` VM for internet egress). This document is the canonical description of those networks, the IP plan, and the procedures to create, verify, and rebuild them.

## Overview

| VMnet | Mode | CIDR | DHCP | Role | Default gateway |
|---|---|---|---|---|---|
| VMnet10 | Host-Only | 192.168.10.0/24 | Off | Cluster backplane — replication, heartbeats, Raft peers, Galera SST, CH Keeper, Patroni REST, Mongo replication, Kafka controller quorum | none (isolated) |
| VMnet11 | Host-Only | 192.168.70.0/24 | Off (served by `nexus-gateway` dnsmasq, scoped 192.168.70.200–.250 for Packer only) | Mgmt, SSH/RDP, application traffic, app-facing endpoints, internet egress for the lab | `192.168.70.1` (`nexus-gateway` VM) |

Host adapter IPs (verified on `10.0.70.101`):

| Adapter | Host IP | Notes |
|---|---|---|
| VMware Network Adapter VMnet10 | `192.168.10.1/24` | Host sits on the backplane for nexus-cli probes; no default gateway |
| VMware Network Adapter VMnet11 | `192.168.70.254/24` | `.1` reserved for `nexus-gateway` VM; host has no default gateway on this adapter |

Both VMnets are **freshly created** on the host. Existing VMnet1 / VMnet8 belong to other tenants and are not touched.

## Platform constraints (VMware Workstation Pro on Windows)

These are hard limits of the platform — not choices. They shape the canon.

| # | Constraint | Consequence |
|---|---|---|
| 1 | Exactly 20 virtual networks: `vmnet0..vmnet19` (enforced by `C:\ProgramData\VMware\netmap.conf`) | Canon cannot use VMnet20+; we use VMnet10 + VMnet11. |
| 2 | **Exactly one NAT network per host** (slot held by existing VMnet8) | VMnet11 cannot be NAT. Lab egress is provided by the `nexus-gateway` VM (Linux NAT), not by VMware NAT. |
| 3 | `vnetlib64.exe` on Workstation Pro 17.5+ silently no-ops many sub-commands (`set vnet … addr`, `add nat`, `add dhcp`) | Subnet / NAT / DHCP wiring must be done in `vmnetcfg.exe` GUI. `vnetlib64 add adapter` still works and is used as a preparatory step. |

## `nexus-gateway` — the lab edge router

VMnet11 is Host-Only at the VMware layer. Internet egress for all 65 lab VMs is provided by a dedicated Linux router VM (`nexus-gateway`), which is **VM #0** of the fleet — built before any other lab VM so that apt/yum/apt pulls and Docker image fetches just work.

| Attribute | Value |
|---|---|
| Hostname | `nexus-gateway.nexus.local` |
| OS | Debian 13 minimal (Packer-built) |
| vCPU / RAM / Disk | 1 / 512 MB / 4 GB |
| NIC 0 | Bridged to physical LAN — obtains internet via home DHCP/router |
| NIC 1 | VMnet11 — static `192.168.70.1/24` |
| NIC 2 | VMnet10 — static `192.168.10.1/24` (for backplane visibility only; **no** routing between VMnets) |
| Services | `nftables` (masquerade 192.168.70.0/24 → NIC 0), `dnsmasq` (DHCP .200–.250, DNS forwarder), `chrony` (NTP source for lab), `node_exporter` |
| Monitoring | Prometheus blackbox probe from host every 30s to `192.168.70.1:9100` |
| HA | Single VM; cold-standby snapshot nightly. For Tier-1 HA rework see ADR-0142 (planned). |

Packer template lives at `nexus-infra-vmware/packer/nexus-gateway/` (Phase 0.B deliverable). Cloud-init provisioning pulls `nftables.conf` and `dnsmasq.conf` from the repo so every rebuild is byte-identical.

> **Why not Windows RRAS / ICS?** Rejected — host-specific, not reproducible, not versioned, breaks on Windows Updates. Canon requires every piece of infra to be code.

## Creation — Windows 11 host

Open **Virtual Network Editor** (`vmnetcfg.exe`, run as Administrator — bundled with VMware Workstation Pro).

### VMnet10 (Host-Only, isolated backplane)

1. Click **Add Network**, pick `VMnet10`. Click OK.
2. With VMnet10 selected, set **Type → Host-only**.
3. ✅ Check *Connect a host virtual adapter to this network* (host sits at `.1` for nexus-cli probes).
4. ❌ **Uncheck** *Use local DHCP service to distribute IP addresses to VMs* (all IPs static).
5. Set **Subnet IP** to `192.168.10.0`, **Subnet mask** to `255.255.255.0`.
6. Click **Apply**.

### VMnet11 (Host-Only, routed via `nexus-gateway`)

1. Click **Add Network**, pick `VMnet11`. Click OK.
2. With VMnet11 selected, set **Type → Host-only**. **Not NAT** — see Platform Constraint #2.
3. ✅ Check *Connect a host virtual adapter to this network*.
4. ❌ **Uncheck** *Use local DHCP service to distribute IP addresses to VMs* (`nexus-gateway` dnsmasq serves DHCP, not VMware).
5. Set **Subnet IP** to `192.168.70.0`, **Subnet mask** to `255.255.255.0`.
6. Click **Apply**.

### Host adapter bind

After applying, cycle the adapters in an elevated pwsh session so Windows re-binds:

```powershell
Disable-NetAdapter -Name 'VMware Network Adapter VMnet10','VMware Network Adapter VMnet11' -Confirm:$false
Start-Sleep 2
Enable-NetAdapter  -Name 'VMware Network Adapter VMnet10','VMware Network Adapter VMnet11' -Confirm:$false
```

If Windows ends up with APIPA (`169.254.x.x`), hard-set the host IPs:

```powershell
New-NetIPAddress -InterfaceAlias 'VMware Network Adapter VMnet10' -IPAddress 192.168.10.1  -PrefixLength 24
New-NetIPAddress -InterfaceAlias 'VMware Network Adapter VMnet11' -IPAddress 192.168.70.254 -PrefixLength 24
```

`192.168.70.1` is reserved for `nexus-gateway`; the host takes `.254` on VMnet11.

## IP plan

VMnet10 third octet encodes cluster role so that IPs read as cluster identity:

| Third octet | Cluster | VMnet10 range | Corresponding VMnet11 |
|---|---|---|---|
| 10.10.x | SQL Server (FCI + AG) | .10–.14 | .10–.17 (VIPs .15–.17) |
| 10.20.x | Kafka (East + West) | .21–.26 | .21–.26 |
| 10.30.x | StarRocks | .31–.36 | .31–.36 |
| 10.40.x | ClickHouse | .41–.49 | .41–.49 |
| 10.50.x | Percona + ProxySQL | .50–.55 | .50 VIP · .51–.55 |
| 10.60.x | PostgreSQL Patroni + etcd + HAProxy | .61–.67 | .61–.67 |
| 10.70.x | MongoDB | .71–.73 | .71–.73 |
| 10.80.x | Redis cluster · MM2 · REST Proxy | .81–.89 | .81–.89 |
| 10.90.x | obs stack · Schema Registry · Connect · ksqlDB | .85–.98 | .85–.98 |
| 10.10.111+ | Swarm managers | .111–.113 | .111–.113 |
| 10.10.115+ | Platform tools (registry, prefect, unleash, marquez, backstage) | .115, .140, .146–.148 | same |
| 10.10.121+ | Vault cluster | .121–.123 | .121–.123 |
| 10.10.131+ | Swarm workers | .131–.133 | .131–.133 |
| 10.10.14x | Spark + MinIO + JupyterHub | .140–.145 | .140–.145 |
| 10.10.150 | Windows workstations | .150 | .150 |

Reserved on VMnet11: **`.1` = nexus-gateway**, **`.2`–`.9` = reserved for future edge appliances (pfSense standby, WireGuard bastion)**, **`.254` = host**.

Static-vs-DHCP policy: **all production VMs are static on both NICs.** DHCP on VMnet11 (served by `nexus-gateway`) is scoped to `.200–.250` and used only by Packer during template creation.

Complete VM → IP map lives in [`vms.yaml`](./vms.yaml).

## DNS

- `nexus-gateway` runs a `dnsmasq` DNS forwarder — authoritative for `*.nexus.local`, forwards everything else to `1.1.1.1` / `1.0.0.1`.
- `dc-nexus` (192.168.70.10) runs Active Directory DNS once built. Windows VMs join AD domain `nexus.local`.
- Linux VMs use `nexus-gateway` (192.168.70.1) as primary resolver.
- Service names (e.g. `obs-metrics.nexus.local`, `sql-ag-listener.nexus.local`) resolve host-wide from the workstation by adding `192.168.70.1` as a secondary DNS on `VMware Network Adapter VMnet11`.

## Firewall posture

- **Linux** — `nftables` on every VM. Default deny inbound, default allow outbound. SSH (22) allowed from VMnet11 only. Cluster ports allowed from 192.168.10.0/24 on VMnet10 only.
- **Windows** — Windows Firewall on, **Domain profile** since all Windows VMs are AD-joined. WinRM (5985/5986), RDP (3389), SQL (1433) allowed per-VM as required by role.
- **nexus-gateway** — nftables rules: masquerade 192.168.70.0/24 out NIC 0; drop 192.168.10.0/24 → NIC 0 (backplane never egresses); accept established/related.
- **Cluster backplane** — all replication / quorum / SST traffic binds to the VMnet10 IP. App traffic binds to the VMnet11 IP.
- **Management** — SSH and RDP on VMnet11 only.

## mTLS posture (E15)

Enhancement **E15** — **Consul Connect** provides mutual TLS between services running on Docker Swarm. Service identities are issued by Vault PKI; certificates rotate every 24 hours for app tokens and 7 days for service identities. Forward reference: `nexus-infra-swarm-nomad` repo, Phase 0.E implementation.

## Panic button — rebuild both VMnets

If VMnet10 / VMnet11 configuration becomes inconsistent (e.g., after a VMware upgrade, or after an accidental "Restore Defaults"), follow this procedure from an elevated pwsh:

```powershell
# 1. Stop every running VM first (nexus-cli handles this if available)
nexus-cli infrastructure stop-all

# 2. Remove the current VMnet10/11 adapters
$vl = 'C:\Program Files (x86)\VMware\VMware Workstation\vnetlib64.exe'
& $vl -- remove adapter vmnet10
& $vl -- remove adapter vmnet11

# 3. Re-add the adapters (vnetlib64 'add adapter' still works on WS 17.5+)
& $vl -- add adapter vmnet10
& $vl -- add adapter vmnet11

# 4. Complete subnet/type configuration in vmnetcfg.exe GUI (see "Creation" section above).
#    vnetlib64 sub-commands for subnet/NAT/DHCP silently no-op on WS 17.5+; GUI is the only reliable path.
Start-Process 'C:\Program Files (x86)\VMware\VMware Workstation\vmnetcfg.exe' -Verb RunAs

# 5. Cycle adapters + verify host IPs
Disable-NetAdapter -Name 'VMware Network Adapter VMnet10','VMware Network Adapter VMnet11' -Confirm:$false
Start-Sleep 2
Enable-NetAdapter  -Name 'VMware Network Adapter VMnet10','VMware Network Adapter VMnet11' -Confirm:$false
Get-NetIPAddress -InterfaceAlias 'VMware Network Adapter VMnet10','VMware Network Adapter VMnet11' |
    Where-Object AddressFamily -eq IPv4 | Format-Table InterfaceAlias, IPAddress, PrefixLength

# 6. Rebuild nexus-gateway (Packer, ~3 min) and power on
cd <nexus-infra-vmware>
packer build packer/nexus-gateway
terraform -chdir=terraform/gateway apply -auto-approve

# 7. Ping probe between two template VMs
nexus-cli infrastructure verify-network
```

After the panic button, re-run `nexus-cli infrastructure verify-network` which pings every pair of known VMs across both VMnets and prints a pass/fail matrix.
