# Network Canon

Every NexusPlatform VM is dual-NIC: one interface on **VMnet10** (cluster backplane, host-only) and one on **VMnet11** (management + applications, NAT). This document is the canonical description of those networks, the IP plan, and the procedures to create, verify, and rebuild them.

## Overview

| VMnet | Mode | CIDR | DHCP | Role | Default gateway |
|---|---|---|---|---|---|
| VMnet10 | Host-Only | 192.168.10.0/24 | Off | Cluster backplane — replication, heartbeats, Raft peers, Galera SST, CH Keeper, Patroni REST, Mongo replication, Kafka controller quorum | none (isolated) |
| VMnet11 | NAT | 192.168.70.0/24 | Scoped 192.168.70.200–.250 (Packer only) | Mgmt, SSH/RDP, application traffic, app-facing endpoints | 192.168.70.2 (VMware NAT device) |

Both VMnets are **freshly created** on host `10.0.70.101`. Existing VMnet1 / VMnet8 are not used to avoid IP collisions with other lab tenants.

## Creation — Windows 11 host

Open **Virtual Network Editor** (run as admin; bundled with VMware Workstation Pro 25H2).

### VMnet10 (Host-Only)

1. Click **Add Network**, pick `VMnet10`. Click OK.
2. With VMnet10 selected, set **Type → Host-only**.
3. **Uncheck** *Use local DHCP service to distribute IP addresses to VMs*.
4. Set **Subnet IP** to `192.168.10.0`, **Subnet mask** to `255.255.255.0`.
5. **Uncheck** *Connect a host virtual adapter to this network* (we do not want the host itself to appear on the backplane).
6. Click **Apply**.

### VMnet11 (NAT)

1. Click **Add Network**, pick `VMnet11`. Click OK.
2. With VMnet11 selected, set **Type → NAT**.
3. **Check** *Use local DHCP service to distribute IP addresses to VMs*.
4. Click **DHCP Settings…**; set **Start IP** `192.168.70.200`, **End IP** `192.168.70.250`. OK.
5. Set **Subnet IP** to `192.168.70.0`, **Subnet mask** to `255.255.255.0`.
6. Click **NAT Settings…**; confirm **Gateway IP** is `192.168.70.2`. OK.
7. **Check** *Connect a host virtual adapter to this network* (host needs to SSH/RDP into VMs).
8. Click **Apply**.

Screenshots will be added at `docs/infra/assets/network/vnet20-*.png` and `vnet21-*.png` during Phase 0.A.

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

Static-vs-DHCP policy: **all production VMs are static on both NICs.** DHCP on VMnet11 is scoped to `.200–.250` and used only by Packer during template creation.

Complete VM → IP map lives in [`vms.yaml`](./vms.yaml).

## DNS

- `dc-nexus` (192.168.70.10) runs Active Directory DNS. All Windows VMs join the AD domain `nexus.local` and receive DNS automatically.
- Linux VMs use `dc-nexus` as primary resolver with `/etc/hosts` fallback during early bring-up (before AD is live).
- Reverse zones configured for both subnets.
- Service names (e.g. `obs-metrics.nexus.local`, `sql-ag-listener.nexus.local`) resolve host-wide from the workstation via Windows' DNS client.

## Firewall posture

- **Linux** — UFW enabled on every VM. Default deny inbound, default allow outbound. SSH (22) allowed from VMnet11 only. Cluster ports allowed from the 192.168.10.0/24 subnet on VMnet10 only.
- **Windows** — Windows Firewall on, **Domain profile** since all Windows VMs are AD-joined. WinRM (5985/5986), RDP (3389), SQL (1433) allowed per-VM as required by role.
- **Cluster backplane** — all replication / quorum / SST traffic binds to the VMnet10 IP. App traffic binds to the VMnet11 IP.
- **Management** — SSH and RDP on VMnet11 only.

## mTLS posture (E15)

Enhancement **E15** — **Consul Connect** provides mutual TLS between services running on Docker Swarm. Service identities are issued by Vault PKI; certificates rotate every 24 hours for app tokens and 7 days for service identities. Forward reference: `nexus-infra-swarm-nomad` repo, Phase 0.E implementation.

## Panic button — rebuild both VMnets

If VMnet10 / VMnet11 configuration becomes inconsistent (e.g., after a VMware upgrade, or after an accidental "Restore Defaults"), follow this procedure from a Windows admin PowerShell:

```
# 1. Stop every running VM first (nexus-cli handles this if available)
nexus-cli infrastructure stop-all

# 2. Blow away the current VMnet10/21 definitions
"C:\Program Files (x86)\VMware\VMware Workstation\vnetlib64.exe" -- remove adapter vmnet10
"C:\Program Files (x86)\VMware\VMware Workstation\vnetlib64.exe" -- remove adapter vmnet11

# 3. Re-add them
"C:\Program Files (x86)\VMware\VMware Workstation\vnetlib64.exe" -- add adapter vmnet10
"C:\Program Files (x86)\VMware\VMware Workstation\vnetlib64.exe" -- set vnet vmnet10 addr 192.168.10.0
"C:\Program Files (x86)\VMware\VMware Workstation\vnetlib64.exe" -- set vnet vmnet10 mask 255.255.255.0
"C:\Program Files (x86)\VMware\VMware Workstation\vnetlib64.exe" -- update dhcp vmnet10         # (no-op — DHCP disabled)

"C:\Program Files (x86)\VMware\VMware Workstation\vnetlib64.exe" -- add adapter vmnet11
"C:\Program Files (x86)\VMware\VMware Workstation\vnetlib64.exe" -- set vnet vmnet11 addr 192.168.70.0
"C:\Program Files (x86)\VMware\VMware Workstation\vnetlib64.exe" -- set vnet vmnet11 mask 255.255.255.0

# 4. Verify Windows-side adapters
ipconfig /all | findstr VMnet

# 5. Restart VMware services
net stop "VMware NAT Service"
net start "VMware NAT Service"
net stop "VMware DHCP Service"
net start "VMware DHCP Service"

# 6. Ping probe between two template VMs
nexus-cli infrastructure verify-network
```

After the panic button, re-run `nexus-cli infrastructure verify-network` which pings every pair of known VMs across both VMnets and prints a pass/fail matrix.
