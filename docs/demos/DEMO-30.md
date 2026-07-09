# DEMO-30 · A container-registry datastore failover with no split-brain — VRRP cutover + Redis re-master + auto PG re-seed

## 1. What this shows

The private container registry (Harbor) keeps its metadata in a dedicated PostgreSQL + Redis datastore
pair behind a keepalived VRRP VIP (`registry-db.nexus.lab` `.119`). This demo runs a **one-shot datastore
failover** from the CLI: `nexus failover-test cluster registry --direction registry-db`. It stops
keepalived on the datastore primary, promotes the peer's PostgreSQL, re-masters its Redis, then **fences
and `pg_basebackup`-re-seeds the old primary as a fresh streaming standby** — so you end with 1 primary +
1 standby (PG) and a master/replica Redis pair, never a split-brain.

The single insight: the failover *used to* re-master Redis but leave the old node a **second PostgreSQL
primary** (a split-brain the operator had to fix by hand — "a DR runbook"). The pre-Phase-1 hardening pass
(0.L.4.1) added the same fence + re-seed treatment the lakehouse catalog DB got (0.L.2.1), so the CLI now
completes the whole cycle safely and deterministically, with a reseed helper guarded so it can *never*
wipe a live primary.

Personas: **SRE** (a rehearsable datastore DR drill with a measured RTO and no manual re-seed),
**platform engineer** (the registry survives a datastore node loss; the same VRRP+fence+re-seed pattern is
now shared by the lakehouse catalog DB and the registry datastore), **DevOps** (the split-brain footgun is
closed in code, not left to a runbook).

## 2. Runtime + prerequisites

- **Environment target** — the always-on foundation base (6 VMs) plus the registry datastore pair:
  `registry-pg-1` (.117) + `registry-pg-2` (.118). The Harbor app nodes (`registry-1/2`) are round-robin
  DNS and **not required** for the drill (power them on only to watch Harbor end-to-end).
- **VMs required** — `registry-pg-1`, `registry-pg-2` — names in [`docs/infra/vms.yaml`](../infra/vms.yaml).
- **Build host** — Windows; `nexus.exe` (AOT) + SSH to the guests.
- **Env vars** — `NEXUS_SSH_KEY` · `NEXUS_SSH_USER` · `NEXUS_VMS_YAML`. `nexus-cli/scratch/nx.ps1` sets these.
- **Seed data** — none (the 0.L.4 build seeded a Harbor project + artifacts).
- **Expected duration** — ~1 min per failover (RTO ~1.3–3 s).
- **Reset command** — the drill is symmetric: re-run it to fail back to the original primary.

## 3. Architecture snapshot

The datastore pair runs PostgreSQL 17 streaming replication **and** a co-located Redis master/replica,
both fronted by keepalived VRRP VIP `.119` (`state BACKUP` + `nopreempt`). The 0.L.4.1 hardening (in
`nexus-infra-registry` `role-overlay-registry-pg-replication.tf`) added: the **`NEXUS-REGISTRY-HBA` block
on BOTH nodes** (a promoted standby admits the Harbor DB user — `pg_hba.conf` is in `/etc`, not `PGDATA`,
so `pg_basebackup` never carried it over); a guarded **`/usr/local/sbin/nexus-registry-reseed.sh`** (fence
+ `pg_basebackup -R`, refuses to touch a VIP-holder or a non-primary source); and **`demote.sh`**
(keepalived `notify_backup`) now re-points Redis **and** re-seeds the demoted PG as a self-heal backstop.
`RegistryAdapter.FailoverAsync` drives the orchestrated path deterministically, reusing the iceberg-pg
(0.L.2.1) shape.

## 4. Walkthrough (operator commands)

> Driven via `nexus-cli/scratch/nx.ps1`. Executable System B demo: `DEMO-168`.

| # | Command | What you see | WHERE observed · What it proves |
|---|---------|--------------|---------------------------------|
| 1 | `ssh nexusadmin@192.168.70.117 "sudo -u postgres psql -tAc 'SELECT pg_is_in_recovery()'"` (and `.118`) | `.117` → `f` (primary, holds VIP), `.118` → `t` (streaming standby). | SSH/psql · a healthy 1-primary + 1-standby pair before the drill. |
| 2 | `nexus failover-test cluster registry --direction registry-db --yes` | GREEN `vrrp-cutover:registry-db`; `original primary registry-pg-1 → new primary registry-pg-2`; `recovery recovered`; hint *"registry-pg-1 re-seeded as a streaming standby … + its Redis re-pointed to the new master"*; RTO ~1.3–3 s. | stdout · a real one-shot datastore failover (was DR-deferred). **Live-verified 2026-07-08.** `DEMO-168`. |
| 3 | re-query `pg_is_in_recovery()` + `redis-cli … info replication` on both nodes | Roles swapped: `.118` PG primary + VIP + Redis `role:master`; `.117` PG streaming standby + Redis `role:slave`. | SSH/psql + redis-cli · **no split-brain** — the old primary auto-rejoined as the standby and its Redis re-attached. |
| 4 | `psql "host=192.168.70.118 dbname=registry user=harbor sslmode=require"` | Admitted on the promoted node (`in_recovery=false`). | psql · the promoted node's `pg_hba` admits the Harbor DB user (pre-0.L.4.1 it was refused) — Harbor reconnects through the VIP. `DEMO-168`. |
| 5 | `nexus failover-test cluster registry --direction registry-db --yes` (again) | Symmetric GREEN — fails back to `registry-pg-1`. | stdout · the drill is reversible; both directions proven. |

## 5. What this proves

- **Advanced infra / HA** — a keepalived VRRP datastore failover that is *actually safe*: PG promote +
  Redis re-master + fence + `pg_basebackup` re-seed in one shot, with a reseed guard that makes wiping a
  live primary impossible. The prior split-brain (primary-only `pg_hba` + Redis-only demote) is closed in
  the IaC overlay.
- **.NET engineering + architecture** — `RegistryAdapter.FailoverAsync --direction registry-db` reuses the
  lakehouse iceberg-pg fence/re-seed pattern (one SPI shape, two Postgres-VRRP tiers), composing on-node
  primitives into a deterministic, observable drill that reports RTO + recovery.
- **DevOps** — a datastore VIP cutover — a classic split-brain footgun — is a single reviewed verb with a
  measured RTO and a self-heal backstop (`demote.sh`), not a hand-run runbook.
- **Data engineering** — the container registry survives a datastore node loss without losing Harbor's
  metadata; both PostgreSQL and Redis re-form their primary/replica roles automatically.

Full verb reference + playbook:
[`nexus-cli/docs/handbook.md`](https://github.com/grezap/nexus-cli/blob/main/docs/handbook.md) §1
(footnote ⁶⁹) + §3.6.2. Verification: `nexus-cli/docs/verification/0.L.4.1-registry-db-failover-reseed.md`.
Executable System B demo: `nexus-cli/docs/demos/DEMO-168`. Companion: `DEMO-29` (the lakehouse iceberg-pg
catalog-DB failover — the same pattern).
