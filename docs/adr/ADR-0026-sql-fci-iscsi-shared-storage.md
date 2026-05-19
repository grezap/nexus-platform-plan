# ADR-0026 — SQL Server FCI shared storage: iSCSI target on nexus-gateway

- **Status**: Accepted
- **Date**: 2026-05-20
- **Deciders**: Greg Zapantis
- **Related**: Phase 0.G.7 (SQL FCI+AG), ADR-0024 (cluster-adapter framework), ADR-0025 (HA promise covers LB tier), `vms.yaml` sqlserver cluster, `memory/project_nexus_infra_oltp_0g7_phase.md`

## Context

Phase 0.G.7's SQL Server cluster (per `vms.yaml` canon, sealed with Greg 2026-05-20) is a **hybrid FCI + AG architecture**:

- 2 FCI nodes (`sql-fci-1`/`sql-fci-2`) form a 2-node WSFC Failover Cluster Instance. SQL Server's FCI architecture *requires* shared storage — the user databases live on a single block device that both nodes can attach (only one at a time owns the SQL Server cluster role; the other is a passive failover target).
- 2 AG replica nodes hold async copies of the FCI's user DBs on local storage.

VMware Workstation Pro has **no shared-disk primitive**. The `scsi0:N.sharing = "multi-writer"` flag is ESXi-only; Workstation's UI doesn't expose it, and even manual `.vmx` edits don't activate sharing semantics (verified at 0.G.7 scaffold 2026-05-20). So an FCI on Workstation requires an external shared-block layer.

Three alternatives considered:

1. **Storage Spaces Direct (S2D).** Pool the FCI nodes' locally-attached disks across an RDMA-capable network into a software-defined shared volume. **Rejected**: S2D needs 2+ Windows Server nodes contributing local disks + a low-latency RDMA fabric; the lab has 4-VM nodes on a software-routed VMnet (not RDMA-capable). Adds another distributed system layer (S2D itself is a cluster) to manage. Also stages a chicken-and-egg: S2D requires WSFC, WSFC requires shared storage. The classic bootstrap.

2. **SMB 3 file-share witness "shared storage".** SQL Server FCI from 2017+ supports SMB 3 file shares as the shared-disk path. **Rejected**: the SMB share would itself need HA, pushing the SPOF up one layer. The lab's NFS export on nexus-gateway (0.E.4a Portainer pattern) is non-HA; promoting it to HA SMB would require its own multi-VM clustering effort. Doesn't simplify the situation.

3. **iSCSI target on nexus-gateway.** Run the Linux Target Framework (`tgt`) on the existing edge gateway VM; export a single sparse-file-backed LUN to the FCI pair only; CHAP-authed + per-IP ACL on the source side; consumed via the standard Windows iSCSI initiator + Multipath I/O (MPIO) features (added at Packer bake time).

## Decision

**Adopt alternative 3.** A `tgt`-based iSCSI target on `nexus-gateway` exports a 60 GB sparse LUN to the FCI pair via VMnet11 tcp/3260.

### iSCSI target configuration

- **Daemon**: `tgt` (Linux SCSI Target Framework). Available in Debian 13's `apt` main repo; single binary; conf-file driven.
- **Backing file**: `/srv/iscsi/sql-fci-shared.img` on nexus-gateway. 60 GB sparse (uses ~0 disk until SQL writes data; thin-provisioned at the host filesystem layer).
- **Lives outside** `/srv/nfs/` (the 0.E.4a Portainer NFS export) for isolation. Different operational surface; different daemon; different ACL semantics.
- **Target IQN**: `iqn.2026-05.local.nexus:sql-fci.lun1`. Year-month + reverse-DNS + service + LUN convention (RFC 3720 §3.2.6.3.1).
- **Initiator allowlist** (per-IP ACL inside the `<target>` block): only `192.168.70.11` and `.12` (the FCI pair). AG replicas at `.13`/`.14` do NOT need iSCSI — their databases are local-storage replicas.
- **Authentication**: ONEWAYCHAP. Incoming-user `sql-fci-initiator` + 32-char hex secret (`openssl rand -hex 16`) sticky-seeded into Vault KV at `nexus/oltp/sqlserver/iscsi-chap-secret`. The CHAP secret is the only secret that LEAVES the Vault — written to host-side sidecar `$HOME/.nexus/iscsi-sqlfci-chap.json` so the foundation env's iSCSI target overlay can consume it (mirrors the `vault-init.json` / `vault-ad-bind.json` pre-Phase-0.E pattern).
- **nftables rule** on nexus-gateway: `ip saddr 192.168.70.11/12 tcp dport 3260 accept`. No other source IPs can reach the LUN. Patched into `/etc/nftables.conf` via in-place `awk` edit + `nft -f` reload (per `memory/feedback_nftables_runtime_add_after_drop.md` — runtime `nft add rule` lands after the canonical drop and is unreachable).
- **MaxRecvDataSegmentLength / FirstBurstLength** tuned for SQL workloads: 256 KB (default 8 KB is too low; matches Windows iSCSI initiator default + reduces interrupt overhead).

### Initiator configuration (on sql-fci-1/2)

- Windows feature `iSCSI-Initiator` installed at Packer bake time + service `msiscsi` set to Manual (terraform's `role-overlay-iscsi-attach.tf` flips it to Automatic on the FCI pair only).
- `New-IscsiTargetPortal -TargetPortalAddress 192.168.70.1 -InitiatorPortalAddress <vmnet11>`.
- `Connect-IscsiTarget -NodeAddress iqn.2026-05.local.nexus:sql-fci.lun1 -AuthenticationType ONEWAYCHAP -ChapUsername sql-fci-initiator -ChapSecret <secret> -IsPersistent $true`.
- On `sql-fci-1` ONLY: `Initialize-Disk` (GPT) + `New-Partition` (drive letter `S:`) + `Format-Volume` (NTFS, 64 KB allocation unit, label `SQL_FCI_SHARED`).
- On `sql-fci-2`: `Set-Disk -IsOffline $false` (just online the existing partition; do NOT format — would destroy `sql-fci-1`'s data).
- WSFC takes ownership via `Add-ClusterDisk` + `Add-ClusterSharedVolume` on the FCI cluster bootstrap step.

## Consequences

### Positive

- **Smallest tractable shim.** No new VM (reuses `nexus-gateway`); no RDMA requirement; no SMB-HA bootstrap; no S2D cluster.
- **Operational consistency.** `nexus-gateway` already runs DHCP + DNS + NTP + NFS (Portainer) + nftables — adding `tgt` is in the same operational envelope.
- **Sparse-file backing**: uses ~0 host disk until SQL writes data. Lab host disk budget preserved.
- **Standard Windows iSCSI initiator path**: every Windows admin knows `Connect-IscsiTarget` + `Set-IscsiChapSecret`. No exotic SDKs.
- **Multipath I/O ready**: `Multipath-IO` Windows feature installed at bake time; if the lab gains a redundant network path later, MPIO is one cmdlet away from active.

### Negative

- **nexus-gateway becomes a load-bearing single point of failure for SQL FCI shared storage.** If `nexus-gateway` reboots (the canonical recovery scenario for the host), the FCI loses access to its LUN until the gateway comes back. Mitigation: nexus-gateway is the simplest VM in the lab (Debian 13 minimal); rebuild time ~3 min via Packer.
- **Network-path dependency**: iSCSI traffic rides VMnet11 alongside management + app traffic. A noisy neighbor on VMnet11 could degrade SQL I/O. Mitigation: lab-scale workloads don't saturate even a single VMnet11; production-grade installs would split iSCSI onto a dedicated VLAN.
- **CHAP is one-way only**: no mutual CHAP for initiator-validates-target. For a lab with one trusted target this is fine; production would use mutual CHAP or IPsec.
- **Performance ceiling**: tgt with sparse-file backing isn't a SAN. Lab-scale demos (sub-100 GB user databases, low TPS) work fine; load tests would hit the ceiling early. Out of scope.

### Neutral

- **Reuses existing canon patterns.** The CHAP-secret-via-Vault-KV-then-host-sidecar indirection mirrors `vault-init.json` + `vault-ad-bind.json`. The nftables-in-place edit pattern mirrors the 0.E.4a NFS gateway export. The Packer-bake-feature install pattern mirrors the Linux clusters' Ansible role for cluster ports.
- **Decision is reversible.** If a future phase brings a real shared-storage primitive (e.g., the lab migrates to ESXi with multi-writer VMDK), the iSCSI shim can be retired in a single sub-phase: detach iSCSI targets on FCI nodes → reformat new shared disk → re-create FCI cluster role on new disk. The AG layer is independent of FCI shared-storage choice.

## Verification

- **iSCSI target reachable**: `iscsiadm -m discovery -t st -p 192.168.70.1` from sql-fci-1 returns the target IQN.
- **LUN visible as cluster shared volume**: `Get-ClusterSharedVolume` on any WSFC member returns 1 Online CSV.
- **smoke-0.G.7 Section 6** (iSCSI) probes session active + LUN online + CSV present.
- **Failover test**: `Move-ClusterGroup "SQL Server (MSSQLSERVER)" -Node sql-fci-2` migrates the FCI role to sql-fci-2; `sqlcmd -S sql-fci-cluster,1433 -Q "SELECT @@SERVERNAME"` returns `sql-fci-2`; no client connection loss beyond the ~10-15 sec WSFC role-migration window.

## References

- Phase 0.G.7 in MASTER-PLAN.md
- ADR-0024 — cluster-adapter framework + AOT gate amendment
- ADR-0025 — HA promise covers LB tier
- ADR-0027 — SQL AG endpoint cert auth
- `memory/project_nexus_infra_oltp_0g7_phase.md`
