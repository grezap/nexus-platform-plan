# DEMO-21 · Vitess-sharded MySQL: kill a shard primary — VTOrc auto-reparents, cluster stays writable

## 1. What this shows

NexusPlatform's Vitess cluster (Phase 0.O) demonstrates **relational** horizontal
sharding: the keyspace `commerce` is split across 2 shards (`-80` / `80-`) by a
hash vindex on `customer_id`, each shard a 3-tablet group (1 PRIMARY + 2 REPLICA)
over Percona Server 8.4. A single MySQL-protocol front door (`vtgate` on `:15306`)
routes every query to the owning shard. This demo kills a shard's PRIMARY mid-write
and shows that (a) **VTOrc** detects the dead primary and promotes a replica
(auto-reparent) in seconds, (b) `vtgate` re-routes transparently, (c) writes
continue (semi-sync durability means no acked write is lost), and (d) the killed
tablet rejoins as a REPLICA when restarted. Sharding + per-shard replication
compose: a single-tablet loss is invisible to the application.

Personas: **infra engineer** (HA verification), **data engineer** (sharded query
routing + vindex design), **platform owner** (BCDR for relational workloads).

## 2. Runtime + prerequisites

- **Environment target** — `full` (or any env with Phase 0.O applied).
- **VMs required** — `nexus-gateway` · 3 etcd (`vitess-etcd-1/2/3`) · 1 control
  (`vitess-control-1` = vtctld + VTOrc) · 2 vtgate (`vitess-vtgate-1/2`) · 6
  tablets (`vitess-shard1-tablet-1..3` + `vitess-shard2-tablet-1..3`). Detail in
  [`docs/infra/vms.yaml`](../infra/vms.yaml) cluster `vitess`.
- **External services** — Vault `vitess-server` PKI role + KV `nexus/vitess/*`
  (mysql + vtorc creds); etcd topo (cell `nexus`).
- **Client auth** — clients connect to vtgate `:15306` over TLS as user `nexus`
  (static-auth, password = `nexus/vitess/mysql-app-password`).
- **Seed data** — `commerce.customer` (100 rows seeded by
  `role-overlay-vitess-schema.tf`, hash-distributed across both shards).
- **Expected duration** — 8–12 min wall-clock.
- **Reset command** — `nexus-cli demo run DEMO-21 --reset` (power any stopped
  tablet back on; VTOrc + replication catch up; `PlannedReparentShard` back if desired).

## 3. Architecture snapshot

```
client ──TLS:15306──> vtgate (RR-DNS vtgate.nexus.lab) ──gRPC mTLS──> vttablet ──> Percona 8.4
                                   │                                      ▲
                              etcd topo (cell nexus)                  VTOrc (watches commerce,
                              vtctld (control)                         auto-reparents on PRIMARY loss)
shard -80: tablet-1/2/3 (1P+2R)     shard 80-: tablet-1/2/3 (1P+2R)     [hash vindex on customer_id]
```
Static fallback at `assets/DEMO-21/architecture.png`.

## 4. Step-by-step script

1. **Action.** Run `nexus-cli demo run DEMO-21`.
   **Expected observable.** CLI reads readiness checks (etcd quorate, both shards
   1P+2R, vtgate pair answering :15306, `commerce.customer` has 100 rows split
   across both shards). Pauses at `press Enter to begin`.
   **Screenshot.** `assets/DEMO-21/step-01.png`

2. **Action.** Press Enter. CLI starts a write loop via `vtgate-1`: every 500ms
   `INSERT INTO customer(...) VALUES(<rand>, ...)` + `SELECT` by id + logs latency.
   **Expected observable.** Each iteration logs `ok` + latency (typical 3–9ms).
   **Screenshot.** `assets/DEMO-21/step-02.png`

3. **Action.** CLI prints per-shard counts (`SELECT COUNT(*) FROM customer` against
   `commerce/-80` and `commerce/80-`).
   **Expected observable.** Both shards non-empty (~50/50) — the hash vindex splits
   the rows. The sharding proof.
   **Screenshot.** `assets/DEMO-21/step-03.png`

4. **Action.** CLI identifies shard `-80`'s current PRIMARY via
   `vtctldclient GetTablets --keyspace commerce --shard -80`. Prompts
   `press Enter to kill <PRIMARY tablet>`.
   **Expected observable.** Prompt shows the PRIMARY alias (e.g. `nexus-100`) + IP.
   **Screenshot.** `assets/DEMO-21/step-04.png`

5. **Action.** CLI stops `nexus-vttablet` + `nexus-mysqlctld` on that tablet
   (or `vmrun stop … hard`).
   **Expected observable.** The write loop briefly errors (`primary is not serving`)
   for ~10–20s, then resumes `ok`. VTOrc has promoted a replica.
   **Screenshot.** `assets/DEMO-21/step-05.png`

6. **Action.** CLI re-runs `GetTablets --shard -80`.
   **Expected observable.** A NEW PRIMARY (a former replica). Killed tablet shows
   not-serving/unreachable. 1 PRIMARY + 1 REPLICA + 1 down.
   **Screenshot.** `assets/DEMO-21/step-06.png`

7. **Action.** CLI runs a cross-shard query via vtgate:
   `SELECT COUNT(*) FROM customer`.
   **Expected observable.** Returns 100+ (seed + retry-buffer inserts) — vtgate
   transparently routes to shard `-80`'s new PRIMARY + shard `80-`'s PRIMARY.
   **Screenshot.** `assets/DEMO-21/step-07.png`

8. **Action.** Restart the killed tablet (`systemctl start nexus-mysqlctld` then
   `nexus-vttablet`). Wait ~2–3 min.
   **Expected observable.** Returning tablet rejoins as REPLICA (replication catches
   up). Final state: 1 PRIMARY + 2 REPLICA again.
   **Screenshot.** `assets/DEMO-21/step-08.png`

9. **Action.** CLI emits final summary.
   **Expected observable.** `DEMO-21 PASS. Shard primary loss auto-reparented by
   VTOrc in <Ns. vtgate re-routed transparently. Sharded keyspace writable
   throughout. Sharding + per-shard replication composition proven.`
   **Screenshot.** `assets/DEMO-21/step-09.png`

## 5. Observability trail

- **Web UIs** — vtctld `http://192.168.70.193:15000` (shard/tablet states flip
  live), VTOrc `http://192.168.70.193:16000` (the reparent decision log), vtgate
  `http://192.168.70.194:15001` (`/debug/vars` query routing counters), vttablet
  `http://<tablet>:15101`.
- **Grafana** — dashboard `vitess` panels: `Tablet type by shard` (PRIMARY flips
  at step 5), `QPS via vtgate` (steady with brief dip), `VTOrc reparent count`.
- **Loki** — `{job="vitess", host=~"vitess-control-1"}` shows the VTOrc analysis +
  `RecoverDeadPrimary` log at step 5.
- **SSH** — `sudo /usr/local/sbin/nexus-vtctldclient GetTablets --keyspace commerce`.

## 6. Code pointers

- [`nexus-infra-vitess/terraform/envs/vitess/role-overlay-vitess-reparent.tf`](https://github.com/grezap/nexus-infra-vitess/blob/main/terraform/envs/vitess/role-overlay-vitess-reparent.tf) — durability policy + initial PRS election.
- [`nexus-infra-vitess/terraform/envs/vitess/role-overlay-vitess-gate.tf`](https://github.com/grezap/nexus-infra-vitess/blob/main/terraform/envs/vitess/role-overlay-vitess-gate.tf) — vtctld + vtgate + VTOrc bring-up.
- [`nexus-infra-vitess/scripts/smoke-0.O.ps1`](https://github.com/grezap/nexus-infra-vitess/blob/main/scripts/smoke-0.O.ps1) — §10 reparent-on-kill check.
- [ADR-0041](../adr/ADR-0041-vitess-sharded-mysql-cluster.md) — topology decision.

## 7. Variations

- **Kill an etcd node.** Raft re-quorates (2/3); topo reads continue; no data-plane impact.
- **Kill a vtgate.** Clients on `vtgate.nexus.lab` round-robin to the survivor (stateless).
- **Kill 2 tablets in one shard** (no PRIMARY possible). Queries to that shard's
  key-range fail; the other shard keeps serving.
- **Planned reparent.** `vtctldclient PlannedReparentShard commerce/-80 --new-primary <alias>` — graceful, zero-error handoff.

## 8. Troubleshooting

| Symptom | Cause | Recovery |
|---|---|---|
| Write loop never recovers after step 5 | VTOrc not watching the keyspace | check `--clusters_to_watch commerce` in vtorc.env; `systemctl restart nexus-vtorc` |
| New primary stuck NOT_SERVING | semi-sync ack stall (both replicas behind) | `vtctldclient PlannedReparentShard commerce/-80 --new-primary <healthy>` |
| **Panic button:** | revert demo state | `pwsh -File scripts\vitess.ps1 apply` |

## 9. What this proves

- **.NET engineering + architecture** — a well-written client (connection-pool retry
  on `ER_OPTION_PREVENTS_STATEMENT` / not-serving) sees sharded-cluster failover as a
  sub-second blip; `vtgate` speaks the MySQL wire protocol so existing MySQL drivers
  (MySqlConnector) work unchanged.
- **Advanced SQL + analytics** — vindex (shard-key) design IS the analytic dimension;
  cross-shard aggregation is transparent through vtgate.
- **Python** — `mysql-connector-python` against `vtgate.nexus.lab:15306` is identical
  to talking to a single MySQL.
- **DevOps** — sharding + per-shard replication composition; VTOrc auto-reparent with
  zero client-side intervention; full mTLS on every hop. Live-ratified + cold-rebuild-proven (handbook §3.1).
