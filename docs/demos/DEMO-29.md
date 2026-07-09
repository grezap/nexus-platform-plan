# DEMO-29 · A catalog-DB failover that keeps the lakehouse open — VRRP cutover + fence + auto re-seed

## 1. What this shows

The Iceberg data lakehouse's REST catalog (Project Nessie) keeps ALL its table metadata in a dedicated
PostgreSQL HA pair behind a keepalived VRRP VIP (`iceberg-db.nexus.lab` `.151`). If that catalog DB has
no safe failover, the whole lakehouse is one node away from an outage — you can't read or write an Iceberg
table without the catalog.

This demo runs a **real one-shot catalog-DB failover** from the CLI:
`nexus failover-test cluster lakehouse --direction iceberg-pg`. It stops keepalived on the primary, lets
the standby take the VIP and promote itself, then **fences and `pg_basebackup`-re-seeds the old primary as
a fresh streaming standby** — so you end with 1 primary + 1 standby, never a split-brain. Throughout,
**Nessie stays served**: the promoted node admits the `nessie` role, so the catalog front door never
lands on a PG that Nessie can't use.

The single insight: this was a **graceful "N/A"** until now — a naïve VRRP cutover would have left two
primaries (split-brain) AND a promoted standby whose `pg_hba.conf` refused Nessie (crash-loop). The first
pre-Phase-1 infra-hardening pass (0.L.2.1) fixed both in the Terraform overlay, so the CLI can now drive
the failover **safely and deterministically** — with a reseed helper guarded so it can *never* wipe a live
primary.

Personas: **SRE** (a rehearsable DR drill for the catalog DB with a measured RTO), **data engineer** (the
lakehouse survives a catalog-DB node loss without losing the Iceberg catalog), **platform engineer** (the
same VRRP + fence + re-seed pattern the registry-db datastore is next to get).

## 2. Runtime + prerequisites

- **Environment target** — the always-on foundation base (6 VMs) plus the lakehouse catalog nodes:
  `iceberg-pg-1` (.149) + `iceberg-pg-2` (.150) for the failover itself; add `iceberg-rest-1` (.147) +
  `iceberg-rest-2` (.148) (Nessie) only to *observe* the catalog staying served. **MinIO is not required**
  (the catalog metadata is in PG; only warehouse data IO uses S3).
- **VMs required** — `iceberg-pg-1`, `iceberg-pg-2` (+ `iceberg-rest-1/2` to observe) — names in
  [`docs/infra/vms.yaml`](../infra/vms.yaml).
- **Build host** — Windows; `nexus.exe` (AOT) + SSH to the guests.
- **Env vars** — `NEXUS_SSH_KEY` · `NEXUS_SSH_USER` · `NEXUS_VMS_YAML`. `nexus-cli/scratch/nx.ps1` sets these.
- **Seed data** — none (the 0.L.2 catalog-bootstrap already created a namespace/table).
- **Expected duration** — ~1 min per failover (RTO ~2–3 s; ~8.5 s end-to-end incl. the re-seed).
- **Reset command** — the drill is symmetric: re-run it to fail back to the original primary.

## 3. Architecture snapshot

The catalog PG pair runs PostgreSQL 17 streaming replication with a keepalived VRRP VIP `.151`
(`state BACKUP` + `nopreempt`). The 0.L.2.1 hardening (in `nexus-infra-lakehouse`
`role-overlay-iceberg-pg-replication.tf`) added: the **`NEXUS-ICEBERG-HBA` block on BOTH nodes** (a
promoted standby admits the `nessie` role — `pg_hba.conf` lives in `/etc`, not `PGDATA`, so
`pg_basebackup` never carried it over); a guarded **`/usr/local/sbin/nexus-iceberg-reseed.sh`** (fence +
`pg_basebackup -R` re-seed, refuses to touch a node that holds the VIP or a source that isn't a primary);
and keepalived **`notify_fault`** as the unattended-crash self-heal backstop. `LakehouseAdapter.FailoverAsync`
drives the orchestrated path deterministically (it holds the nexusadmin key and reaches both nodes, so no
inter-node SSH), mirroring the registry-db VRRP cutover.

## 4. Walkthrough (operator commands)

> Driven via `nexus-cli/scratch/nx.ps1`. Executable System B demo: `DEMO-167`.

| # | Command | What you see | WHERE observed · What it proves |
|---|---------|--------------|---------------------------------|
| 1 | `ssh nexusadmin@192.168.70.149 "sudo -u postgres psql -tAc 'SELECT pg_is_in_recovery()'"` (and `.150`) | `.149` → `f` (primary, holds VIP), `.150` → `t` (streaming standby). | SSH/psql · confirms a healthy 1-primary + 1-standby pair before the drill. |
| 2 | `nexus failover-test cluster lakehouse --direction iceberg-pg --yes` | GREEN `vrrp-cutover:iceberg-pg`; `original primary iceberg-pg-1 → new primary iceberg-pg-2`; `recovery recovered`; hint *"iceberg-pg-1 re-seeded as a streaming standby of iceberg-pg-2"*; timeline RTO ~2–3 s, ~8.5 s total. | stdout · a real one-shot VRRP cutover + deterministic fence + re-seed. **Live-verified 2026-07-08.** `DEMO-167`. |
| 3 | re-query `pg_is_in_recovery()` + `pg_stat_wal_receiver` on both nodes | The roles have swapped: `.150` primary + VIP, `.149` streaming standby; the new primary's `pg_stat_replication` shows `.149` streaming. | SSH/psql · **no split-brain** — the old primary auto-rejoined as the standby. |
| 4 | `curl -sk https://iceberg.nexus.lab:19120/api/v2/trees` | **HTTP 200** with the branch list, AFTER the cutover. | curl · Nessie reconnected through the VIP onto the promoted node — `pg_stat_activity` there then shows a `nessie/192.168.70.147` connection. The catalog never went dark. `DEMO-167`. |
| 5 | `nexus failover-test cluster lakehouse --direction iceberg-pg --yes` (again) | Symmetric GREEN — fails back to `iceberg-pg-1` primary. | stdout · the drill is reversible; both directions proven. |

## 5. What this proves

- **Advanced infra / HA** — a keepalived VRRP catalog-DB failover that is *actually safe*: promote +
  fence + `pg_basebackup` re-seed in one shot, with a reseed guard (`REFUSE … holds VIP`) that makes it
  impossible to wipe a live primary. The prior naïve cutover's two failure modes (split-brain +
  Nessie-refusing `pg_hba`) were both closed in the IaC overlay.
- **.NET engineering + architecture** — `LakehouseAdapter.FailoverAsync --direction iceberg-pg` composes
  the on-node primitives (keepalived promote hook + the reseed helper) into a deterministic, observable
  drill that reports RTO + recovery, reusing the registry-db cutover shape (one SPI, many tiers).
- **DevOps** — the operation that's easiest to get wrong (a DB VIP cutover) is a single reviewed verb with
  a measured RTO, a self-heal backstop (`notify_fault`), and an honest recovery hint — not a hand-run DR runbook.
- **Data engineering** — the Iceberg lakehouse survives a catalog-DB node loss without losing its table
  catalog; Nessie keeps serving reads/writes through the VIP.

Full verb reference + playbook:
[`nexus-cli/docs/handbook.md`](https://github.com/grezap/nexus-cli/blob/main/docs/handbook.md) §1
(footnote ⁶¹) + §3.6.1. Verification: `nexus-cli/docs/verification/0.L.2.1-iceberg-pg-failover-fencing.md`.
Executable System B demo: `nexus-cli/docs/demos/DEMO-167`.
