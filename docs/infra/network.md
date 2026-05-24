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

VMnet11 is Host-Only at the VMware layer. Internet egress for all 54 lab VMs (50 currently live + 4 SQL Server FCI+AG nodes scaffolded at Phase 0.G.7; OLTP tier sealed 2026-05-20 with all 5 OLTP clusters scaffolded) is provided by a dedicated Linux router VM (`nexus-gateway`), which is **VM #0** of the fleet — built before any other lab VM so that apt/yum/apt pulls and Docker image fetches just work. nexus-gateway also hosts an iSCSI target (tgt) serving the FCI shared LUN per ADR-0026, in addition to its existing NFSv4 export for Portainer.

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
| 10.60.x | PostgreSQL Patroni + etcd + HAProxy HA pair | .61–.68 (3 patroni · 3 etcd · 2 haproxy) | **VIP `.60` (VRRP)** · .61–.68 |
| 10.70.x | MongoDB | .71–.73 | .71–.73 |
| 10.80.x | Redis cluster · MM2 · REST Proxy | .81–.89 | .81–.89 |
| 10.90.x | obs stack · Schema Registry · Connect · ksqlDB | .85–.98 | .85–.98 |
| 10.10.111+ | Swarm managers | .111–.113 | .111–.113 |
| 10.10.115+ | Platform tools — registry-1 (Harbor) `.115` (Phase 0.L.4); prefect/unleash/marquez/backstage `.116`–`.119` (future 0.I/0.J/0.K) | .115–.119 | same |
| 10.10.121+ | Vault cluster | .121–.123 | .121–.123 |
| 10.10.131+ | Swarm workers | .131–.133 | .131–.133 |
| 10.10.14x–15x | **Lakehouse (`08-spark`, Phase 0.L)** — spark-master-1 `.140`; MinIO `.141`–`.144`; spark-worker-1/2 `.145`/`.146`; iceberg-rest `.147`/`.148`; iceberg-pg `.149`/`.150`; **catalog-DB VIP `.151`** (VRRP); JupyterHub `.152` (future); spark-master-2 `.153`; spark-worker-3 `.154`; ZooKeeper `.155`–`.157` | .140–.157 | .140–.157 (VMnet10 backplane; VIP `.151` is VMnet11-only) |
| 10.10.160 | Windows workstations (`nexusdesk-dev`) — moved off `.150` (now iceberg-pg-2) when the lakehouse tier claimed the `.14x` decade | .160 | .160 |

Reserved on VMnet11: **`.1` = nexus-gateway**, **`.2`–`.9` = reserved for future edge appliances (pfSense standby, WireGuard bastion)**, **`.254` = host**.

**Floating VRRP VIPs on VMnet11** (each LB tier mirrors its cluster's HA promise — see [ADR-0025](../adr/ADR-0025-ha-promise-covers-lb-tier.md)):

| VIP | Owners (MASTER · BACKUP) | Service | Notes |
|---|---|---|---|
| `192.168.70.50` | `proxysql-1` (prio 110) · `proxysql-2` (prio 100) | OLTP — Percona XtraDB Cluster front door (MySQL :3306, ProxySQL admin :6032) | unicast VRRP; client connection string `mysql://...@192.168.70.50:3306/...` |
| `192.168.70.60` | `haproxy-pg-1` (prio 110) · `haproxy-pg-2` (prio 100) | OLTP — Patroni PG HA front door (PG read-write :5000 → current Leader, PG read-only :5001 → replicas, stats :7000) | unicast VRRP; client connection string `postgresql://...@192.168.70.60:5000/...` (RW) or `:5001` (RO) |
| `192.168.70.15` | WSFC-managed (no priority; cluster-owned) | OLTP — WSFC cluster management IP for `sql-fci-cluster` (Phase 0.G.7) | NOT a SQL endpoint; `Get-Cluster`/`Get-ClusterNode` ops from anywhere on VMnet11 |
| `192.168.70.16` | WSFC role `SQL Server (MSSQLSERVER)` (migrates between sql-fci-1/2) | OLTP — SQL Server FCI virtual server `sqlfci` (Phase 0.G.7); SQL clients targeting the FCI directly | client connection string `sqlfci.nexus.lab,1433` or `192.168.70.16,1433`; cert IP-SAN includes .16 (the FCI virtual name `sqlfci` is distinct from the WSFC CNO `sql-fci-cluster` at .15) |
| `192.168.70.17` | WSFC role `sql-ag-listener` (migrates with AG primary) | OLTP — AG Listener (Phase 0.G.7; the LB-tier HA primitive per ADR-0025) | client connection string `sql-ag-listener.nexus.lab,1433` or `192.168.70.17,1433`; cert IP-SAN includes .17 |

The VIPs are not DHCP reservations:
- The keepalived VIPs (.50, .60) float between Linux LB pairs via unicast VRRP.
- The SQL Server VIPs (.15, .16, .17) are owned by WSFC and migrate atomically with their respective cluster roles (cluster, FCI, AG). WSFC uses NetFT (Network Fault Tolerance) for heartbeats which works fine on VMware Host-Only networks (no L2 multicast needed for the broadcast heartbeats unlike VRRP multicast).

Pinging any VIP from anywhere on VMnet11 reaches whichever node currently
owns the role.

**Analytics tier (ClickHouse 0.G.5 + StarRocks 0.G.6) has NO VIP — by design.**
Both engines are natively any-node-addressable (ClickHouse `Distributed` reads/writes
from any of the 6 data nodes; StarRocks accepts MySQL-protocol queries on any of the
3 FE, with Followers forwarding DDL to the Leader), so there is no single fixed
endpoint that would be a SPOF without a VIP. The stable client endpoint is delivered
by **round-robin DNS** (multi-A `host-record`, the same mechanism as `portainer.nexus.lab`)
rather than a VRRP VIP + LB pair. This is the documented "client-side multi-endpoint"
branch of [ADR-0025](../adr/ADR-0025-ha-promise-covers-lb-tier.md), resolved for the
analytics tier in [ADR-0031](../adr/ADR-0031-analytics-client-front-door-round-robin-dns.md).
The analytics clusters carry no `virtual_ips:` block in `vms.yaml`, and that absence
is intentional.

Static-vs-DHCP policy: **all production VMs are static on both NICs.** DHCP on VMnet11 (served by `nexus-gateway`) is scoped to `.200–.250` and used only by Packer during template creation.

Complete VM → IP map lives in [`vms.yaml`](./vms.yaml).

## DNS

- `nexus-gateway` runs a `dnsmasq` DNS forwarder — authoritative for `*.nexus.local`, forwards everything else to `1.1.1.1` / `1.0.0.1`.
- `dc-nexus` (192.168.70.10) runs Active Directory DNS once built. Windows VMs join AD domain `nexus.local`.
- Linux VMs use `nexus-gateway` (192.168.70.1) as primary resolver.
- Service names (e.g. `obs-metrics.nexus.local`, `sql-ag-listener.nexus.local`) resolve host-wide from the workstation by adding `192.168.70.1` as a secondary DNS on `VMware Network Adapter VMnet11`.
- **Round-robin (multi-A) `host-record` entries** on `nexus-gateway`'s dnsmasq give cluster front doors a single stable name resolving to all member nodes (resolvers rotate; the engines' native multi-host clients retry the next on failure):
  - `portainer.nexus.lab` → swarm managers `.111`–`.113` (Phase 0.E.4c)
  - `clickhouse.nexus.lab` → ClickHouse data nodes `.44`–`.49` (Phase 0.G.5; the 6 shard-replica nodes — every one is an equal `Distributed`-table entry point)
  - `starrocks-fe.nexus.lab` → StarRocks FE `.31`–`.33` (Phase 0.G.6; MySQL protocol `:9030`, HTTP `:8030` — any FE serves queries + forwards DDL to the Leader)
  - `minio.nexus.lab` → MinIO nodes `.141`–`.144` (Phase 0.L.1; S3 API `:9000` — every node is an equal erasure-set entry point; per-host `minio-server` PKI certs carry this name in their SANs)
  - `iceberg.nexus.lab` → Nessie REST nodes `.147`/`.148` (Phase 0.L.2; Iceberg REST API HTTPS `:19120` — two stateless catalog instances, any one serves any request; per-host `iceberg-server` PKI certs carry this name in their SANs)
  - `iceberg-db.nexus.lab` → catalog-DB **VRRP VIP `.151`** (Phase 0.L.2; PostgreSQL `:5432` — keepalived floats the VIP to the current master of the iceberg-pg `.149`/`.150` master-replica pair; the PG leaf cert IP-SANs/SAN carry this name + `.151`)
  - `spark-master.nexus.lab` → the 2 Spark HA masters `.140`/`.153` (Phase 0.L.3; round-robin for the Web UI `:8080` — the Spark cluster's multi-master URL `spark://…:7077,…:7077` uses node IPs, and ZooKeeper `.155`–`.157` elects the live master). ZooKeeper has no VMnet11 DNS — it is backplane-IP-only by design.

### Analytics-tier MAC reservations (VMnet11 dhcp-host)

The 15 analytics nodes get static-pinned VMnet11 IPs via dnsmasq `dhcp-host` reservations on `nexus-gateway` (the contiguous MAC block after the OLTP tier, which ends at `:89`). Secondary NICs (VMnet10 backplane) use the same sixth byte with fifth byte `01` and are statically assigned by firstboot (no DHCP). Primary MAC plan (`00:50:56:3F:00:XX`):

| Node | VMnet11 | Primary MAC `…:00:` | Node | VMnet11 | Primary MAC `…:00:` |
|---|---|---|---|---|---|
| ch-keeper-1 | .41 | `8A` | ch-shard3-rep1 | .48 | `91` |
| ch-keeper-2 | .42 | `8B` | ch-shard3-rep2 | .49 | `92` |
| ch-keeper-3 | .43 | `8C` | sr-fe-leader | .31 | `93` |
| ch-shard1-rep1 | .44 | `8D` | sr-fe-follower-1 | .32 | `94` |
| ch-shard1-rep2 | .45 | `8E` | sr-fe-follower-2 | .33 | `95` |
| ch-shard2-rep1 | .46 | `8F` | sr-be-1 | .34 | `96` |
| ch-shard2-rep2 | .47 | `90` | sr-be-2 | .35 | `97` |
|  |  |  | sr-be-3 | .36 | `98` |

### Lakehouse-tier MAC reservations (VMnet11 dhcp-host)

The 16 lakehouse nodes (Phase 0.L, tier `08-spark`) get static-pinned VMnet11 IPs
via dnsmasq `dhcp-host` reservations on `nexus-gateway` (the contiguous MAC block
after the analytics tier, which ends at `:98`). Secondary NICs (VMnet10 backplane)
use the same sixth byte with fifth byte `01`. Primary MAC plan (`00:50:56:3F:00:XX`):

| Node | VMnet11 | Primary MAC `…:00:` | Node | VMnet11 | Primary MAC `…:00:` |
|---|---|---|---|---|---|
| spark-master-1 | .140 | `99` | spark-worker-2 | .146 | `9F` |
| minio-1        | .141 | `9A` | iceberg-rest-1 | .147 | `A0` |
| minio-2        | .142 | `9B` | iceberg-rest-2 | .148 | `A1` |
| minio-3        | .143 | `9C` | iceberg-pg-1   | .149 | `A2` |
| minio-4        | .144 | `9D` | iceberg-pg-2   | .150 | `A3` |
| spark-worker-1 | .145 | `9E` | (catalog-DB VIP `.151` — VRRP, no MAC) | | |

The StarRocks shared-data/CN tier (Phase 0.L.5, extends `04-analytics`) reserves
`A4`–`A9`: registry-1 (Harbor, `09-platform`) `.115` `A4`, then SR FE
`.37`/`.38`/`.39` + CN `.30`/`.40` (the CN-2 `.40` is a documented spillover into
the first free ClickHouse-decade slot, because the StarRocks `.3x` decade had only
4 free slots and Greg chose full-HA 3 FE + 2 CN).

The **0.L.3 Spark HA expansion** continues the block at `AA`–`AE` (after the
`A4`–`A9` reservation): spark-master-2 `.153` `AA`, spark-worker-3 `.154` `AB`,
zookeeper-1/2/3 `.155`/`.156`/`.157` `AC`/`AD`/`AE`.

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
