# ADR-0032 — Phase 0.G.5/0.G.6: Analytics backup repository — NFS export from nexus-gateway (MinIO deferred to 0.L)

- **Status**: Accepted
- **Date**: 2026-05-22
- **Deciders**: Greg Zapantis
- **Related**: ADR-0017 (Portainer state via NFS-from-gateway — same "gateway as the lab's NFS server" pattern), ADR-0026 (SQL FCI iSCSI-from-gateway — same "gateway as the storage shim" philosophy), MASTER-PLAN 0.L (MinIO + Harbor)

## Context

The `nexus-cli` data-cluster verb surface includes a `backup` verb group (take/restore) that every cluster must implement. For ClickHouse this is `BACKUP TABLE/DATABASE ... TO Disk(...)` + `RESTORE`; for StarRocks it is `CREATE REPOSITORY` + `BACKUP SNAPSHOT` / `RESTORE SNAPSHOT`. Both engines' backup machinery writes to a **backup destination** — either object storage (S3) or a filesystem path (local disk or a network mount).

The natural object-storage destination for the whole lab is **MinIO** (S3-compatible) — both ClickHouse (`Disk` of type `s3`) and StarRocks (`CREATE REPOSITORY ... WITH BROKER` / native S3) support it directly. But **MinIO is not stood up until Phase 0.L** (Spark + Iceberg + MinIO + Harbor), which is sequenced *after* the analytics phases (0.G.5/0.G.6 → 0.L → 0.I). The analytics tier therefore needs a backup destination that exists *now*.

Two options exist today:

1. **Local disk on each node** — `BACKUP ... TO Disk('backups', ...)` to a local path. Simplest, but the backup lives on the same VM as the data (lost if the VM is lost) and a multi-node `RESTORE` can't read another node's local backup. Defeats the point of a backup for a *cluster*.
2. **A shared network filesystem** — an NFS export mounted at the same path on every analytics node. The lab already has a proven pattern for this: `nexus-gateway` runs `nfs-kernel-server` and exports `/srv/nfs/portainer-data` to the Swarm managers (ADR-0017, Phase 0.E.4a). The same gateway already serves as the lab's storage shim for iSCSI (SQL FCI, ADR-0026).

## Decision

**Provision an NFS export from `nexus-gateway` (`/srv/nfs/analytics-backups`, NFSv4) mounted at `/var/backups/analytics` on every analytics node, as the backup repository for both ClickHouse and StarRocks. Migrate to MinIO/S3 when Phase 0.L lands.**

- `nexus-gateway` exports `/srv/nfs/analytics-backups` NFSv4-only (same `fsid`-based pseudo-root + `nftables` tcp/2049 allow-from-analytics-IPs pattern as the Portainer export, `feedback_nfsv4_fsid0_pseudo_root.md`). A dedicated export (not a shared one) keeps backup blast radius isolated.
- Every analytics node mounts it at `/var/backups/analytics` (subdir per cluster: `.../clickhouse`, `.../starrocks`).
- **ClickHouse**: a `<backups><allowed_disk>` + a `Disk` of type `local` pointing at the NFS mount; `BACKUP TABLE <t> TO Disk('analytics_backups', '<name>.zip')` / `RESTORE`. Because the mount is shared, any node can restore a backup any node took — the cluster-level backup/restore the `backup` verb promises.
- **StarRocks**: `CREATE REPOSITORY <name> WITH BROKER` is the legacy path; modern StarRocks supports a filesystem repository directly. The shared NFS mount backs the repository so `BACKUP SNAPSHOT` / `RESTORE SNAPSHOT` is cluster-wide.
- **Forward migration is a destination swap, not a redesign.** When 0.L stands up MinIO, the ClickHouse `Disk` flips type `local`→`s3` and the StarRocks repository flips to an S3 repository; the `backup` verb's surface and the demos are unchanged. This ADR is explicitly an *interim* decision with a named successor (S3/MinIO), recorded so the swap at 0.L is a planned step, not a surprise.

## Consequences

### Positive

- **A working cluster-wide backup repository today**, without waiting for 0.L. The `backup` verb group is implementable + demoable + smoke-provable in this phase, as the directive requires.
- **Reuses a proven pattern.** `nexus-gateway`-as-NFS-server is already in production for Portainer state; the analytics export is the same playbook with a different path + ACL. No new infrastructure class.
- **Shared mount = real cluster backup/restore.** Any node restores any node's backup, which is the only meaningful definition of "cluster backup" — a local-disk backup would not survive the node it lives on.
- **Clean migration path.** The destination is an implementation detail behind the `backup` verb; the 0.L swap to MinIO/S3 is local + reversible.

### Negative

- **`nexus-gateway` becomes a backup SPOF + a bandwidth chokepoint.** The gateway is already a foundation always-on VM (its loss is a lab-wide event regardless), and backup traffic is occasional, so this is acceptable for a lab. Production would use replicated object storage. Noted, not mitigated (the mitigation is 0.L's MinIO).
- **NFS, not object storage**, so neither engine's S3-native features (parallel multipart, lifecycle) are exercised here — those come with the 0.L MinIO migration. The lab demonstrates the *backup/restore verb* now and the *S3 path* at 0.L.

### Neutral

- **Disk budget.** `/srv/nfs/analytics-backups` lives on the gateway's disk; lab-scale demo backups are small. Sized in the foundation overlay; grows trivially if needed.

## Verification

`smoke-0.G.5.ps1` / `smoke-0.G.6.ps1` assert: the NFS export is mounted at `/var/backups/analytics` on every node (`findmnt`); a `BACKUP` (CH) / `BACKUP SNAPSHOT` (SR) of a demo table writes artifacts to the shared mount; and a cross-node `RESTORE` (take on one node, restore from another) round-trips the data — proving the repository is genuinely cluster-shared. Recorded in the per-cluster verification docs.
