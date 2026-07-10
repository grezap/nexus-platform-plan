# DEMO-31 · An engine-native backup of a sharded keyspace — hot physical copy, validate, then a real replica restore that keeps the shard writable

## 1. What this shows

The Vitess tier shards the `commerce` keyspace across two shards (`-80` / `80-`) by a hash vindex on
`customer_id`, with three tablets per shard (1 PRIMARY + 2 REPLICA). This demo takes a **real,
engine-native backup** of that sharded keyspace from the CLI and proves it is restorable — first with a
**safe validation** and then with a **real restore onto a replica** — all without ever taking the shard's
write-primary offline.

The single insight: 0.O shipped with a *logical* `mysqldump` backup (a stopgap — a `.sql.gz` per shard
primary socket). 0.O.1 replaces it with the **actual Vitess BackupStorage path**: a `file` repo on shared
NFSv4 (`/vt-backups`) plus the **`xtrabackup`** engine (Percona hot physical backup), driven by
`vtctldclient BackupShard` / `RestoreFromBackup`. `backup take` runs `BackupShard`, which **auto-selects a
REPLICA** per shard — so the backup is a hot physical copy that never touches the PRIMARY. `backup restore`
is **safe by default** (a non-destructive dry-run that validates the newest backup per shard) and only
mutates state behind an explicit `--confirm-destructive` — and even then it restores onto a **REPLICA**,
so the shard stays writable while that replica rebuilds and rejoins.

Personas: **SRE** (a rehearsable, engine-native backup + restore drill with measured durations and no
write-window disruption), **DBA** (a physical hot backup of a horizontally-sharded MySQL/Vitess keyspace,
restored per-shard onto a replica that rejoins via GTID + `mysql_upgrade` — not a logical dump/reload),
**platform engineer** (backup/restore is one reviewed CLI verb over a proper BackupStorage backend, safe
by default).

## 2. Runtime + prerequisites

- **Environment target** — the always-on foundation base (6 VMs) plus the full Vitess tier (12 VMs):
  3 etcd, 1 control (`vitess-control-1` .193, which also serves the `/vt-backups` NFSv4 export), 2 vtgate,
  and 2 shards × 3 tablets.
- **VMs required** — `vitess-etcd-1..3` · `vitess-control-1` · `vitess-vtgate-1..2` ·
  `vitess-shard1-tablet-1..3` · `vitess-shard2-tablet-1..3` (exact names in
  [`docs/infra/vms.yaml`](../infra/vms.yaml)).
- **Build host** — Windows; `nexus.exe` (AOT) + SSH to the guests.
- **External services** — the **`/vt-backups` Vitess `file` BackupStorage** exported over NFSv4 from
  `vitess-control-1` (.193) and mounted on all 6 tablets; the **`xtrabackup`** engine on each tablet;
  `vtctld` on the control node. Vault at `VAULT_ADDR` for the tablet/vtgate mTLS material.
- **Env vars** — `NEXUS_SSH_KEY` · `NEXUS_VMS_YAML` · `VAULT_ADDR`/`VAULT_TOKEN`/`VAULT_CACERT`.
  `nexus-cli/scratch/nx.ps1` sets these.
- **Seed data** — none (the 0.O build seeded `commerce.customer`, split 54/47 across `-80`/`80-` by the
  hash vindex — 101 rows total).
- **Expected duration** — ~1 min: take ~7 s, dry-run ~1.4 s, real restore ~25 s, plus the health re-probe.
- **Reset command** — none needed: the take is additive (a new backup dir), the dry-run mutates nothing,
  and the destructive restore re-seeds a replica in place (the shard is unchanged from the client's view).

## 3. Architecture snapshot

`backup take` / `backup restore` in `VitessAdapter` were rewritten from logical `mysqldump` to
**engine-native `vtctldclient BackupShard` / `RestoreFromBackup`** against a real Vitess **BackupStorage**
backend: a `file` repo rooted at `/vt-backups`, which is a single **NFSv4** export served from
`vitess-control-1` (.193) and mounted on all 6 tablets, with the **`xtrabackup`** (Percona hot physical)
engine configured on every tablet. A **take** runs `BackupShard` per shard; Vitess **auto-picks a REPLICA**
as the source, so the physical copy runs off a replica and the PRIMARY keeps serving. Each backup lands
under `/vt-backups/commerce/<shard>/<timestamp>.<tablet-alias>/`. A **restore** resolves the newest backup
per shard; by default it only **validates** (dry-run, zero changes), and with `--confirm-destructive` it
runs `RestoreFromBackup` onto a **REPLICA** — wiping and rebuilding that replica's datadir from the
xtrabackup, then rejoining the shard via **GTID position + `mysql_upgrade`**. The command layer gates the
destructive form behind an interactive / `--yes` confirmation *in addition to* `--confirm-destructive`.

## 4. Walkthrough (operator commands)

> Driven via `nexus-cli/scratch/nx.ps1`. Executable System B demo: `DEMO-169`.

| # | Command | What you see | WHERE observed · What it proves |
|---|---------|--------------|---------------------------------|
| 1 | `nexus health vitess` | GREEN, 11/11 probes; both shards 1 PRIMARY + 2 REPLICA. | stdout · a healthy sharded keyspace before the drill. |
| 2 | `nexus backup take vitess --tag demo0O1 --json` | `backupId vitess-demo0O1-20260709-232309`, `sizeBytes 4988059` (~5 MB physical), `durationSec 6.957`; destination *"/vt-backups (Vitess file BackupStorage on NFSv4, xtrabackup engine) — -80=2026-07-09.232309.nexus-0000000102(2521433B), 80-=2026-07-09.232313.nexus-0000000201(2466626B)"*. | stdout + `ssh nexusadmin@192.168.70.193 'vtctldclient … GetBackups commerce/-80'` · a real `vtctldclient BackupShard` hot physical copy per shard onto the NFS `file` repo; the tablet aliases show BackupShard picked a **REPLICA** — the PRIMARY was never taken offline. **Live-verified 2026-07-09.** `DEMO-169`. |
| 3 | `nexus backup restore vitess vitess-demo0O1-20260709-232309 --yes --json` | **DEFAULT dry-run**: `itemsRestored 0`, `durationSec 1.404`; suffix *"[dry-run validated (no changes; --confirm-destructive to apply): -80:…nexus-0000000102@vitess-shard1-tablet-1, 80-:…nexus-0000000201@vitess-shard2-tablet-2]"*. | stdout · restore is **safe by default** — it resolves the newest backup per shard and the replica it *would* restore onto, but changes nothing. `nexus health vitess` stays GREEN. `DEMO-169`. |
| 4 | `nexus backup restore vitess vitess-demo0O1-20260709-232309 --confirm-destructive --yes --json` | **REAL restore**: `itemsRestored 101`, `durationSec 25.433`; suffix *"[restored: -80<-…nexus-0000000102@vitess-shard1-tablet-1(54 rows,rejoined), 80-<-…nexus-0000000201@vitess-shard2-tablet-2(47 rows,rejoined)]"*. `101 = 54 (-80) + 47 (80-)` = the hash-vindex `customer_id` split. | stdout + `vtctldclient … GetTablets --keyspace commerce` · `RestoreFromBackup` onto a **REPLICA** per shard, which rebuilds its datadir and rejoins via **GTID position + `mysql_upgrade`** — each shard keeps its one PRIMARY, so it stays **writable** throughout. **Live-verified 2026-07-09.** `DEMO-169`. |
| 5 | `nexus health vitess` | GREEN again, 11/11; both shards back to 1 PRIMARY + 2 REPLICA, the re-seeded replicas streaming. | stdout · the destructive restore left the tier healthy — the replica rejoined cleanly. |

## 5. What this proves

- **Advanced infra / HA** — a Vitess-native backup: `BackupShard` (xtrabackup hot physical) per shard onto
  a real `file` BackupStorage repo on shared NFSv4, sourced off a **REPLICA** so the write-primary is never
  taken offline; ~5 MB physical output per take. The restore re-seeds a **replica** (not the primary), so a
  full shard restore never costs the shard its write availability.
- **.NET engineering + architecture** — `VitessAdapter.BackupTake/RestoreAsync` were rewritten from a
  logical `mysqldump` stopgap to compose `vtctldclient BackupShard` / `RestoreFromBackup` over the engine's
  own BackupStorage SPI, with a **safe-by-default** restore (dry-run validation) gated behind an explicit
  `--confirm-destructive` *and* `--yes` — the destructive verb is an honest, reviewable guardrail.
- **Advanced SQL + data engineering** — a horizontally-sharded MySQL/Vitess keyspace (`commerce`, hash
  vindex on `customer_id`, `-80`/`80-`) is backed up and restored **per shard**; the restore proof is the
  exact `54 + 47 = 101`-row vindex split, restored physically and rejoined via GTID + `mysql_upgrade` — not
  a logical dump/reload.
- **DevOps** — backup and restore of a sharded database are a single CLI verb over a proper engine-native
  BackupStorage backend, safe by default, with the destructive path guarded by two explicit opt-ins —
  rather than a hand-run `mysqldump`/`xtrabackup` runbook.

Full verb reference + playbook:
[`nexus-cli/docs/handbook.md`](https://github.com/grezap/nexus-cli/blob/main/docs/handbook.md) §1
(`backup take` / `backup restore`) + §3 (Vitess 0.O.1). Executable System B demo:
`nexus-cli/docs/demos/DEMO-169`. Companion: `DEMO-166` (the vitess mysqld-wire cert-rotate).
