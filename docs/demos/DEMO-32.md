# DEMO-32 · Wire mTLS for a running sharded MongoDB — a zero-downtime cert rotation across 11 nodes (no re-election) + a TLS backup round-trip

## 1. What this shows

The Phase 0.N sharded MongoDB cluster shards `nexus_n_smoke.samples` across two shard replica-sets behind
two stateless `mongos` routers, with a three-node config-server replica-set — **11 mongod/mongos in all**.
0.N shipped keyFile-only: members authenticate to each other with a shared keyFile, but client and
intra-cluster traffic crossed the wire **in the clear**. This demo shows the 0.N.1 hardening that closes
that gap — **Vault-PKI wire mTLS on every node** — and then exercises the two operations that prove it is
production-grade: a **zero-downtime certificate rotation across all 11 nodes** and a **TLS-encrypted backup
round-trip**.

The single insight: turning on `requireTLS` is the easy half — the hard half is *rotating* those certs
later without an outage on a sharded cluster. 0.N.1 makes every node run
`net.tls.mode: requireTLS` with a **per-host leaf** rendered by that node's own **Vault Agent** from PKI
role `mongo-sharded-server` (CN `<host>.mongo.nexus.lab`), while `clusterAuthMode` stays **keyFile** for
member auth (the two mechanisms are complementary, not redundant). `nexus cert-rotate mongo-sharded` then
re-issues all 11 leaves and reloads each **online** via `db.adminCommand({rotateCertificates:1})` — **no
mongod restart, and critically no shard re-election** — so the cluster never loses a write-primary during
the rotation. This reaches **parity with the non-sharded 0.G.2 mongo RS**, and it was delivered as a clean
**11-VM cold-rebuild** (destroy → from-zero apply, one pass, 92 resources, zero transients).

Personas: **security engineer** (client + intra-cluster traffic is now mutually authenticated and encrypted
with short-lived, per-host Vault-issued certs — and rotating them is a single reviewed verb, not a
maintenance window), **DBA** (a zero-downtime cert rotation on a *sharded* MongoDB with no stepdown/election
and a verified backup/restore over TLS), **platform engineer** (`cert-rotate` went from a graceful N/A to a
real in-CLI operation, matching the non-sharded RS shape).

## 2. Runtime + prerequisites

- **Environment target** — the always-on foundation base (6 VMs) plus the full 0.N sharded cluster
  (11 VMs): 3 config-server RS (`.74/.75/.76` :27019), shard-1 RS (`.77/.78/.79` :27018), shard-2 RS
  (`.80/.56/.57` :27018), and 2 `mongos` routers (`.58/.59` :27017).
- **VMs required** — `mongo-cfg-1..3` · `mongo-shard-1-1..3` · `mongo-shard-2-1..3` · `mongo-mongos-1..2`
  (exact names in [`docs/infra/vms.yaml`](../infra/vms.yaml)).
- **Build host** — Windows; `nexus.exe` (AOT) + SSH to the guests.
- **External services** — **Vault** at `VAULT_ADDR` for the per-host mTLS leaves (PKI role
  `mongo-sharded-server`); each node runs a **Vault Agent** that renders its own leaf to
  `/etc/nexus-mongo/tls/server.pem`.
- **Env vars** — `NEXUS_SSH_KEY` · `NEXUS_VMS_YAML` · `VAULT_ADDR`/`VAULT_TOKEN`/`VAULT_CACERT`.
  `nexus-cli/scratch/nx.ps1` sets these.
- **Seed data** — none (the 0.N build seeded `nexus_n_smoke.samples` — 200 docs, hashed shard key spread
  across both shards).
- **Expected duration** — ~2 min: the 11-node rotation is ~78 s, the backup take/restore are sub-second to
  ~1.3 s, plus the health re-probes.
- **Reset command** — none needed: the rotation is idempotent (re-run to rotate again), the backup take is
  additive, and the restore targets an isolated verify DB (`nexus_n_restore_verify`).

## 3. Architecture snapshot

Each mongod/mongos runs `mongod.conf` `net.tls: { mode: requireTLS, certificateKeyFile:
/etc/nexus-mongo/tls/server.pem, CAFile: /etc/nexus-mongo/tls/ca.crt, allowConnectionsWithoutCertificates:
false }` — so a plaintext client is rejected outright and every peer must present a valid, CA-chained cert.
The `server.pem` leaf is rendered by a **per-host Vault Agent** from PKI role `mongo-sharded-server` with
CN `<host>.mongo.nexus.lab`; `clusterAuthMode` stays **keyFile**, so member (replica-set + shard) auth is
unchanged — wire mTLS is layered *on top of* the existing keyFile trust, exactly as on the non-sharded
0.G.2 RS. `MongoShardedAdapter.RotateCertAsync` (previously a graceful not-applicable) now, per
node, forces that node's own vault-agent to **re-render a fresh leaf**, then reloads it **online** with
`db.adminCommand({rotateCertificates:1})` — an in-place swap of the running server's cert with **no
restart and no reparent**. The adapter's `backup take` / `backup restore` were also moved onto TLS:
`mongodump --ssl` / `mongorestore --ssl` through a `mongos`.

## 4. Walkthrough (operator commands)

> Driven via `nexus-cli/scratch/nx.ps1`. Executable System B demo: `DEMO-170`.

| # | Command | What you see | WHERE observed · What it proves |
|---|---------|--------------|---------------------------------|
| 1 | `nexus health mongo-sharded` | GREEN, **16/16** probes — and every probe now dials over mTLS. | stdout + `ssh nexusadmin@192.168.70.77 'echo \| sudo openssl s_client -connect 127.0.0.1:27018 \| openssl x509 -noout -subject'` · the shard-1 mongod serves a leaf `CN=mongo-shard-1-1.mongo.nexus.lab` — the per-host Vault-Agent cert, not a shared/self-signed one. A healthy sharded topology, now on `requireTLS`. |
| 2 | `nexus cert-rotate mongo-sharded --yes --json` | All **11 nodes** rotate GREEN, distinct serials, zero errors (e.g. `mongo-cfg-1 555E9FA8… → 4719E276…`); `durationSec 78.47`. | stdout + `ssh … journalctl -u mongod \| grep rotateCertificates` · each node's `db.adminCommand({rotateCertificates:1})` returned `ok:1` — an **online** reload, no restart line, no stepdown. A genuine Vault re-issue (on-disk serial changed **and persists**), not a cache replay. **Live-verified 2026-07-10.** `DEMO-170`. |
| 3 | `nexus health mongo-sharded` | Still GREEN, **16/16**, immediately after the rotation. | stdout · **NO shard re-election** — config RS still 1 PRIMARY + 2 SECONDARY, both shard RSes unchanged, both mongos serving. The rotation never cost the cluster a write-primary. |
| 4 | `nexus backup take mongo-sharded` | `backupId mongo-sharded-backup-20260710-125332`, archive `/var/backups/nexus-mongo-sharded/mongo-sharded-backup-20260710-125332.archive.gz`, `sizeBytes 1946`, `durationSec 0.4`. | stdout · a `mongodump --ssl` **through a mongos** (:27017) — the whole logical dump of `nexus_n_smoke` crossed the wire **encrypted**. `DEMO-170`. |
| 5 | `nexus backup restore mongo-sharded mongo-sharded-backup-20260710-125332 --yes` | `mongorestore --ssl` into `nexus_n_restore_verify`: `itemsRestored 200`, `durationSec 1.3`. | stdout · `200` = the full seeded `samples` set — the TLS backup **round-trips** end-to-end, restore-over-mTLS included. **Live-verified 2026-07-10.** `DEMO-170`. |

## 5. What this proves

- **Advanced infra / HA** — a *sharded* MongoDB (config RS + 2 shard RSes + 2 mongos, 11 nodes) gains
  Vault-PKI wire mTLS with **zero-downtime cert rotation**: all 11 leaves re-issued and reloaded **online**
  via `rotateCertificates` in ~78 s with **no restart and no shard re-election**, so health stays GREEN
  16/16 throughout. Delivered as a clean 11-VM cold-rebuild (92 resources, one pass, zero transients).
- **.NET engineering + architecture** — `MongoShardedAdapter.RotateCertAsync` went from a graceful
  not-applicable to a real verb that composes per-host Vault-agent re-render + an online
  `db.adminCommand({rotateCertificates:1})` reload, reusing the non-sharded 0.G.2 mongo shape (one SPI,
  sharded and non-sharded tiers). Its backup/restore were moved onto `--ssl` in the same pass.
- **Security engineering** — client and intra-cluster traffic are now mutually authenticated and encrypted
  with short-lived, per-host Vault-issued certs (CN `<host>.mongo.nexus.lab`), `requireTLS` rejecting any
  plaintext connection, with keyFile retained for member auth — and rotating that trust material is a
  single reviewed CLI verb, not a maintenance window.
- **Data engineering** — a 200-document sharded collection backs up and restores **over TLS** through a
  `mongos` (`mongodump --ssl` / `mongorestore --ssl`), proving the encrypted path is complete end-to-end,
  not just for live queries.

Full verb reference + playbook:
[`nexus-cli/docs/handbook.md`](https://github.com/grezap/nexus-cli/blob/main/docs/handbook.md) §1
(`cert-rotate` / `backup take` / `backup restore`) + §3 (mongo-sharded 0.N.1). Executable System B demo:
`nexus-cli/docs/demos/DEMO-170`. Companion: `DEMO-38` (the non-sharded 0.G.2 mongo cert-rotate — the same
Vault-issue pattern this reaches parity with).
