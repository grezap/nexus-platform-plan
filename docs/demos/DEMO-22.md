# DEMO-22 · Citus-sharded PostgreSQL: kill a worker Patroni leader — Patroni promotes the standby, the VIP follows, the distributed query stays up

## 1. What this shows

NexusPlatform's Citus cluster (Phase 0.P) demonstrates **PostgreSQL-native**
horizontal sharding: the `events` table is a *distributed table* hash-partitioned
on `tenant_id` into 32 shards spread across 2 worker node-groups; the *coordinator*
holds the distributed catalog (`pg_dist_node` / `pg_dist_shard`) and routes /
aggregates queries; a *reference table* (`tenants`) is replicated to every node for
local joins. HA is orthogonal and supplied by **Patroni** — every node-group
(coordinator + each worker) is a 2-node Patroni cluster over a shared etcd DCS,
each fronted by a **keepalived VRRP VIP** that floats to the current leader. This
demo kills a worker group's Patroni leader mid-query and shows that (a) Patroni
promotes the streaming standby in seconds, (b) the keepalived VIP rebinds on the
new leader, (c) because the coordinator registered the worker **by its VIP**, the
`pg_dist_node` entry stays valid with no rewrite, and (d) cross-shard queries keep
returning through the coordinator. Sharding + per-group streaming HA compose: a
single PG node loss is invisible to the application.

Personas: **infra engineer** (HA verification), **data engineer** (distributed-
table / reference-table / colocation design), **platform owner** (BCDR for
relational workloads).

## 2. Runtime + prerequisites

- **Environment target** — `full` (or any env with Phase 0.P applied).
- **VMs required** — `nexus-gateway` · 3 etcd (`citus-etcd-1/2/3`) · coordinator
  pair (`citus-coord-1/2`) · worker-1 pair (`citus-worker1-1/2`) · worker-2 pair
  (`citus-worker2-1/2`). Detail in [`docs/infra/vms.yaml`](../infra/vms.yaml)
  cluster `citus`.
- **External services** — Vault `citus-server` PKI role + KV `nexus/citus/*`
  (superuser / replication / patroni-rest / citus-app creds); etcd DCS (the
  Patroni quorum store); 3 VIP DNS records (`coord/worker1/worker2.citus.nexus.lab`).
- **Client auth** — clients connect to `coord.citus.nexus.lab:5432` over TLS as
  `citus_app` (password = `nexus/citus/citus-app-password`); a client cert from
  the lab CA is required (`clientcert=verify-ca`).
- **Seed data** — `events` (800+ rows, hash-distributed across both workers),
  `event_tags` (colocated), `tenants` (reference) seeded by
  `role-overlay-citus-distribute.tf`.
- **Expected duration** — 6–10 min wall-clock.
- **Reset command** — `nexus-cli demo run DEMO-22 --reset` (restart any stopped
  PG node; Patroni catches it up as a replica).

## 3. Architecture snapshot

```
client ──TLS:5432──> coord.citus.nexus.lab (VIP .211, follows coord leader)
                          │  coordinator: pg_dist_node + routes/aggregates
        ┌─────────────────┴───────────────────┐
   worker1.citus.nexus.lab (VIP .212)    worker2.citus.nexus.lab (VIP .213)
   coord<->worker over verify-full mTLS   [hash shards of events on tenant_id]
   Patroni pair (1 leader + 1 replica)    Patroni pair (1 leader + 1 replica)
                          │
                  etcd DCS (3 nodes, /citus/<scope>)  + keepalived vrrp_script -> REST /leader
```
Static fallback at `assets/DEMO-22/architecture.png`.

## 4. Step-by-step script

1. **Action.** Run `nexus-cli demo run DEMO-22`.
   **Expected observable.** Readiness checks (etcd quorate; all 3 Patroni scopes
   1 leader + 1 replica; pg_dist_node = coordinator + 2 active workers; `events`
   shards split across both workers). Pauses at `press Enter to begin`.
   **Screenshot.** `assets/DEMO-22/step-01.png`

2. **Action.** Press Enter. CLI starts a query loop via `coord.citus.nexus.lab`:
   every 500ms `INSERT INTO events(...)` for a random tenant + `SELECT count(*)
   FROM events` (cross-shard aggregate) + logs latency.
   **Expected observable.** Each iteration logs `ok` + a growing count + latency.
   **Screenshot.** `assets/DEMO-22/step-02.png`

3. **Action.** CLI prints per-worker shard counts
   (`SELECT nodename, count(*) FROM citus_shards WHERE table_name='events'::regclass GROUP BY nodename`).
   **Expected observable.** Both workers non-empty (~16 shards each) — the hash
   distribution. The sharding proof.
   **Screenshot.** `assets/DEMO-22/step-03.png`

4. **Action.** CLI identifies worker-1's current Patroni leader
   (`nexus-patronictl list citus-worker1`). Prompts `press Enter to kill <leader>`.
   **Expected observable.** Prompt shows the leader member (e.g. `citus-worker1-1`)
   + which node holds VIP .212.
   **Screenshot.** `assets/DEMO-22/step-04.png`

5. **Action.** CLI stops `nexus-patroni` on that node (or `vmrun stop … hard`).
   **Expected observable.** The query loop briefly errors for ~10–20s, then resumes
   `ok`. Patroni has promoted the standby; keepalived rebinds VIP .212 on it.
   **Screenshot.** `assets/DEMO-22/step-05.png`

6. **Action.** CLI re-runs `nexus-patronictl list citus-worker1` +
   `ip addr show` on both worker-1 nodes.
   **Expected observable.** A NEW leader (the former replica); VIP .212 now bound on
   the new leader; killed node down. `pg_dist_node` UNCHANGED (still points at
   `worker1.citus.nexus.lab`).
   **Screenshot.** `assets/DEMO-22/step-06.png`

7. **Action.** CLI runs a cross-shard query + a colocated join via the coordinator.
   **Expected observable.** `SELECT count(*) FROM events` returns 800+; the
   `events ⋈ event_tags` colocated join executes — the coordinator transparently
   reaches the new worker-1 leader via the (moved) VIP.
   **Screenshot.** `assets/DEMO-22/step-07.png`

8. **Action.** Restart the killed node (`systemctl start nexus-patroni`). Wait ~1–2 min.
   **Expected observable.** Returning node rejoins as REPLICA (streaming catches up).
   Final state: worker-1 back to 1 leader + 1 replica.
   **Screenshot.** `assets/DEMO-22/step-08.png`

9. **Action.** CLI emits final summary.
   **Expected observable.** `DEMO-22 PASS. Worker Patroni leader loss promoted in
   <Ns; keepalived VIP followed the new leader; pg_dist_node unchanged; distributed
   queries served throughout. PG-native sharding + Patroni HA composition proven.`
   **Screenshot.** `assets/DEMO-22/step-09.png`

## 5. Observability trail

- **Patroni REST** — `https://<node>:8008/cluster` (JSON: leader + replica + lag);
  `/leader` returns 200 only on the leader (this is the keepalived vrrp_script probe).
- **Grafana** — dashboard `citus` panels: `Patroni role by node` (worker-1 leader
  flips at step 5), `Coordinator QPS` (steady with brief dip), `Shard count by node`.
- **Loki** — `{job="citus", host=~"citus-worker1.*"}` shows the Patroni
  `promoted self to leader` + keepalived `Entering MASTER STATE` at step 5.
- **SSH** — `sudo /usr/local/sbin/nexus-patronictl list citus-worker1` ·
  `sudo -u postgres psql -h /var/run/nexus-citus -d citus -c 'SELECT * FROM pg_dist_node'`.

## 6. Code pointers

- [`nexus-infra-citus/terraform/envs/citus/role-overlay-citus-patroni-bootstrap.tf`](https://github.com/grezap/nexus-infra-citus/blob/main/terraform/envs/citus/role-overlay-citus-patroni-bootstrap.tf) — 3 Patroni scopes + shared_preload=citus + verify-ca mTLS.
- [`nexus-infra-citus/terraform/envs/citus/role-overlay-citus-keepalived.tf`](https://github.com/grezap/nexus-infra-citus/blob/main/terraform/envs/citus/role-overlay-citus-keepalived.tf) — VIP-follows-leader vrrp_script.
- [`nexus-infra-citus/terraform/envs/citus/role-overlay-citus-extension.tf`](https://github.com/grezap/nexus-infra-citus/blob/main/terraform/envs/citus/role-overlay-citus-extension.tf) — citus_add_node by VIP.
- [`nexus-infra-citus/scripts/smoke-0.P.ps1`](https://github.com/grezap/nexus-infra-citus/blob/main/scripts/smoke-0.P.ps1) — §9 worker-failover check.
- [ADR-0042](../adr/ADR-0042-citus-sharded-postgresql-cluster.md) — topology decision.

## 7. Variations

- **Kill an etcd node.** Raft re-quorates (2/3); Patroni DCS reads continue; no data-plane impact.
- **Kill the coordinator leader.** coord VIP .211 floats to the coord standby; clients on `coord.citus.nexus.lab` reconnect to the new leader; the distributed catalog is preserved (streaming replica).
- **Kill both nodes of one worker group.** That group's shards become unavailable; queries touching those shards fail; the other worker keeps serving its shards.
- **Online scale-out.** `citus_add_node` a 3rd worker group + `rebalance_table_shards('events')` — shards redistribute online (DEMO-29).

## 8. Troubleshooting

| Symptom | Cause | Recovery |
|---|---|---|
| Query loop never recovers after step 5 | keepalived didn't move the VIP (vrrp_script failing) | check `journalctl -u nexus-keepalived` + that REST `/leader` answers 200 on the new leader; `systemctl restart nexus-keepalived` |
| Coordinator errors `could not connect to worker` | new worker leader's cert missing the VIP SAN, or `.pgpass` stale | confirm the worker cert covers `worker1.citus.nexus.lab` + `.212`; re-run the tls overlay |
| **Panic button:** | revert demo state | `pwsh -File scripts\citus.ps1 apply` |

## 9. What this proves

- **.NET engineering + architecture** — a well-written client (Npgsql with
  connection-pool retry) sees a worker failover as a sub-second blip; the
  coordinator speaks plain PostgreSQL wire so existing PG drivers work unchanged.
- **Advanced SQL + analytics** — distribution key + colocation design IS the
  analytic dimension; cross-shard aggregation + reference-table joins are
  transparent through the coordinator.
- **Python** — `psycopg`/`asyncpg` against `coord.citus.nexus.lab:5432` is identical
  to talking to a single PostgreSQL.
- **DevOps** — PG-native sharding + per-group streaming-replication HA composition;
  VIP-follows-Patroni-leader so distributed metadata needs no rewrite on failover;
  full Vault-PKI mTLS on every hop. Live-ratified + cold-rebuild-proven (handbook §3.1).
