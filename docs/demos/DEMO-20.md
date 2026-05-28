# DEMO-20 · MongoDB sharded cluster: kill a shard primary — cluster stays writable

## 1. What this shows

NexusPlatform's MongoDB sharded cluster (Phase 0.N) demonstrates document-store sharding: a collection's chunks distribute across multiple replica-set "shards", and a query router (mongos) fan-outs reads + targeted writes to the right shard. This demo kills the PRIMARY of one shard mid-write and shows that (a) the shard re-elects a new PRIMARY in under 10 seconds, (b) the mongos detects the topology change and re-routes traffic, (c) the sharded collection stays writable throughout — only the brief window during failover sees retries. Sharding + replication compose: each shard is its own 3-node RS, so a single-node loss is invisible to the application.

Personas: **infra engineer** (HA verification), **data engineer** (sharded query routing), **platform owner** (BCDR story for document workloads).

## 2. Runtime + prerequisites

- **Environment target** — `full` (or any env with Phase 0.N applied).
- **VMs required** — `nexus-gateway` · 3 config-server nodes (`mongo-cfg-1/2/3`) · 6 shard nodes (`mongo-shard-1-1..3` + `mongo-shard-2-1..3`) · 2 mongos routers (`mongo-mongos-1/2`). Detail in [`docs/infra/vms.yaml`](../infra/vms.yaml) cluster `mongo-sharded`.
- **External services** — Vault KV `nexus/oltp/mongo/keyfile` (shared cluster keyFile, sticky-seeded by 0.G.2).
- **Seed data** — `nexus_n_smoke.samples` (200 docs hashed-sharded on `k`, seeded by `role-overlay-mongo-add-shards.tf` at first apply).
- **Expected duration** — 8–10 min wall-clock.
- **Reset command** — `nexus-cli demo run DEMO-20 --reset` (power any stopped shard nodes back on; wait for replication catch-up).

## 3. Architecture snapshot

3-tier sharded topology:
- **Config-server RS** (`config`) on cfg-1/2/3 @ port 27019 — holds chunk-to-shard metadata.
- **Shard RSes** (`shard-1`, `shard-2`) each 3 nodes @ port 27018 — hold user data; chunks distribute across the shards based on the shard key.
- **mongos routers** (mongos-1, mongos-2 @ port 27017) — stateless; clients connect here; mongos queries config-server for chunk locations and routes ops to the right shard.

Round-robin DNS `mongos.nexus.lab → .58, .59`. Static fallback at `assets/DEMO-20/architecture.png`.

## 4. Step-by-step script

1. **Action.** Run `nexus-cli demo run DEMO-20`.
   **Expected observable.** CLI reads ~10 readiness checks (sh.status shows 2 shards, both shard RSes 1P/2S, mongos pair responding to ping, sharded collection has 200 docs). Pauses at `press Enter to begin`.
   **Screenshot.** `assets/DEMO-20/step-01.png`

2. **Action.** Press Enter. CLI starts a write loop against `nexus_n_smoke.samples` via `mongos-1`: every 500ms inserts `{k: random, v: "demo-{timestamp}"}` + reads {k: 50} + logs the response.
   **Expected observable.** Each iteration logs `ok` + latency (typical: 3-8ms). Steady cadence.
   **Screenshot.** `assets/DEMO-20/step-02.png`

3. **Action.** CLI prints `sh.status()` from mongos showing chunk distribution: ~50% on shard-1, ~50% on shard-2.
   **Expected observable.** Hashed shard key distributes chunks evenly.
   **Screenshot.** `assets/DEMO-20/step-03.png`

4. **Action.** CLI identifies shard-1's current PRIMARY via `rs.status()` (e.g. mongo-shard-1-1 if just-bootstrapped). Prompts `press Enter to kill <PRIMARY-NODE>`.
   **Expected observable.** Prompt shows the PRIMARY hostname + IP.
   **Screenshot.** `assets/DEMO-20/step-04.png`

5. **Action.** CLI runs `vmrun stop <PRIMARY-NODE>.vmx hard` from the build host.
   **Expected observable.** Within 1 second the PRIMARY is gone. The write loop briefly errors with `not master + not primary` for 5-12 seconds, then resumes with `ok` responses again.
   **Screenshot.** `assets/DEMO-20/step-05.png`

6. **Action.** CLI runs `rs.status()` on a surviving shard-1 SECONDARY.
   **Expected observable.** New PRIMARY elected (one of the previous SECONDARYs). The killed node is `(not reachable/healthy)`. 1 PRIMARY + 1 SECONDARY + 1 down.
   **Screenshot.** `assets/DEMO-20/step-06.png`

7. **Action.** CLI runs a sharded query: `db.samples.aggregate([{$count: "n"}])` via mongos.
   **Expected observable.** Returns 200+ (the seed + any new inserts from step 5's retry buffer). Proves the cluster is fully operational — mongos routes to shard-1's new PRIMARY + shard-2's PRIMARY transparently.
   **Screenshot.** `assets/DEMO-20/step-07.png`

8. **Action.** Power killed node back on: `vmrun start <PRIMARY-NODE>.vmx`. Wait ~3 min for catch-up.
   **Expected observable.** Returning node rejoins as SECONDARY (oplog catches up). Final state: 1 PRIMARY + 2 SECONDARY again.
   **Screenshot.** `assets/DEMO-20/step-08.png`

9. **Action.** CLI emits final summary.
   **Expected observable.** `DEMO-20 PASS. Shard primary loss recovered in 5-12s. mongos auto-routed during failover. Sharded collection writable throughout (1 brief retry window). Replica-set + sharded composition proven.`
   **Screenshot.** `assets/DEMO-20/step-09.png`

## 5. Observability trail

- **Grafana** — dashboard `mongo-sharded` panels: `Shard primary health` (drops at step 5, recovers at step 8), `Write ops/sec via mongos` (steady with brief dip), `Election count` (increments at step 5).
- **Loki** — query `{job="mongo-sharded", host=~"shard-1-.*"}` shows the election logs.
- **Tempo** — N/A (no app-level OTLP in this demo).
- **URLs** — `https://grafana.nexus.lab/d/mongo-sharded`.

## 6. Code pointers

- [`nexus-infra-oltp/terraform/envs/oltp-mongo-sharded/role-overlay-mongo-add-shards.tf`](https://github.com/grezap/nexus-infra-oltp/blob/main/terraform/envs/oltp-mongo-sharded/role-overlay-mongo-add-shards.tf) — `sh.addShard` choreography + sharded-collection bootstrap.
- [`nexus-infra-oltp/scripts/smoke-0.N.ps1`](https://github.com/grezap/nexus-infra-oltp/blob/main/scripts/smoke-0.N.ps1) — ~50-check smoke gate.
- [ADR-0040](../adr/ADR-0040-mongodb-sharded-cluster-separate-from-0g2-rs.md) — sharded-cluster topology decision.

## 7. Variations

- **Kill a config-server PRIMARY.** Config RS re-elects in 5-15s; cluster stays available (chunk lookups continue via the new PRIMARY).
- **Kill both mongos.** All client connections drop; bringing one back restores service immediately (stateless).
- **Kill 2 nodes in a single shard** (shard down — no PRIMARY possible). Writes to chunks owned by that shard fail; reads succeed for chunks on the other shard.

## 8. Troubleshooting

| Symptom | Cause | Recovery |
|---|---|---|
| Write loop never recovers after step 5 | Election deadlocked (network partition during recovery) | `rs.reconfig({force: true})` on a surviving node |
| Chunks all on one shard (sh.status post-step-3) | Balancer paused | `sh.startBalancer()` via mongos |
| **Panic button:** | revert demo state | `pwsh -File scripts\mongo-sharded.ps1 apply` |

## 9. What this proves

- **.NET engineering + architecture** — mongos's session-level retry semantics + readPreference + writeConcern make sharded-cluster failover invisible to a well-written client (set `retryWrites=true`, default in Mongo 4.4+).
- **Advanced SQL + analytics** — N/A (NoSQL document store; sharding key design IS the analytic dimension).
- **Python** — `pymongo` MongoClient with the 2-host seed list (`mongos.nexus.lab`) is the same shape; auto-handles router-level retry on failover.
- **DevOps** — replica-set + sharded-cluster composition (each shard is a 3-node RS); sub-15s failover with zero client-side intervention; cold-rebuild proven from zero in ~45 min.
