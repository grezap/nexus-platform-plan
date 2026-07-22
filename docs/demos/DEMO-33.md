# DEMO-33 · Emit OpenLineage into Marquez and answer "what breaks downstream?" — a 2-job / 3-dataset run graph read back over TLS, on an HA lineage store

## 1. What this shows

The Phase 0.Q.1 platform-tools tier stands up the platform's **OpenLineage backend** — a Marquez node
fronted by an nginx TLS terminator, backed by a **dedicated PostgreSQL 17 HA pair** with a keepalived
VRRP VIP. This demo does exactly what a real emitter (dataflow-studio, Prefect, Spark) does: it **POSTs
OpenLineage run events** describing a two-stage pipeline and then **reads the resulting lineage graph
back** through the REST read model — the namespace, both jobs, all three datasets, and the edges that
connect them.

The single insight: lineage is only useful if you can answer *"if I change `raw.orders`, what downstream
breaks?"* — and here that is **proven on live lab data, not asserted**. The committed data-flow script
emits `raw.orders --[curate-orders]--> curated.orders --[load-dwh]--> dwh.fact_order`, each job as a
**START then a COMPLETE** event (every POST returns **201**), into namespace `nexus-lineage-demo` at
`https://marquez.nexus.lab/api/v1/lineage`. Then a traversal from the source dataset
(`GET /api/v1/lineage?nodeId=dataset:nexus-lineage-demo:raw.orders&depth=10`) walks the **full downstream
graph** — reaching `dwh.fact_order` through both jobs. The graph persists to the HA PG pair, whose VIP
Marquez reaches `sslmode=verify-full`, with streaming replication to the standby.

Personas: **data architect** (impact analysis — the downstream-of-a-dataset query is the lineage tool's
whole reason to exist), **platform engineer** (a real OpenLineage ingest endpoint over a TLS front door,
the target every emitter in the platform will point at), **SRE** (the lineage store is an HA PG pair
behind a VRRP VIP — a lineage catalog is not something you want on a single database).

## 2. Runtime + prerequisites

- **Environment target** — the always-on foundation base (6 VMs) plus the full platform-tools Marquez tier
  (3 VMs): the `marquez` app node (`.127`, Docker CE + docker-compose: Marquez api `:5000` / admin `:5001`
  / web `:3000` behind an nginx `:443` TLS terminator) and a `marquez-pg` PostgreSQL 17 streaming pair
  (`.134` primary / `.135` replica) with a keepalived VRRP VIP `marquez-db.nexus.lab` (`.136`).
- **VMs required** — `marquez` · `marquez-pg-1` · `marquez-pg-2` (exact names in
  [`docs/infra/vms.yaml`](../infra/vms.yaml)).
- **Build host** — Windows; `pwsh` + SSH to the guests.
- **External services** — **Vault** at `VAULT_ADDR` for the `platform-tools-server` PKI leaves (the nginx
  front-door leaf carries the `marquez.nexus.lab` SAN; both PG leaves carry the VIP `.136` SAN); each node
  runs a **Vault Agent** rendering its own leaf.
- **Env vars** — `NEXUS_SSH_KEY` (the demo script defaults `-SshKey ~/.ssh/nexus_gateway_ed25519`).
- **Seed data** — none: the demo *is* the data — it emits its own OpenLineage run graph into namespace
  `nexus-lineage-demo` (kept distinct from the apply-time exit-gate namespace `nexus-lineage`, so runs
  never collide) and is idempotent (re-run to re-emit).
- **Expected duration** — ~30 s: the four OpenLineage POSTs + read-back are sub-second; most of the wall
  clock is SSH round-trips.
- **Reset command** — none needed: the emit is additive (Marquez upserts jobs/datasets/runs by name) and
  the read-back mutates nothing.

## 3. Architecture snapshot

An emitter POSTs OpenLineage run events to `https://marquez.nexus.lab/api/v1/lineage`; nginx terminates
TLS on `:443` (leaf from PKI role `platform-tools-server`, CN/SAN `marquez.nexus.lab`) and proxies to the
Marquez **api** container on `:5000`, with the **web** UI on `:3000` and the admin/health port on `:5001`.
Marquez persists the lineage model to its PostgreSQL datastore over `sslmode=verify-full` through the
keepalived VIP `marquez-db.nexus.lab` (`.136`) — so a datastore failover moves the VIP without Marquez
re-pointing, and **both** PG leaves carry `.136` in their SANs so `verify-full` survives the move. The
`marquez-pg` pair is a PG17 primary/replica with streaming replication (`pg_stat_replication` → `streaming`).
The committed data-flow demo (`scripts/marquez-lineage-demo.ps1`) emits two jobs (`curate-orders`,
`load-dwh`) each as a START then a COMPLETE event across three datasets (`raw.orders`, `curated.orders`,
`dwh.fact_order`), then reads the graph back via the REST model — namespace, jobs, datasets, and the
lineage traversal from `raw.orders`. All probes are **SSH-local-curl on the marquez node** against its own
CA (the Windows build host's schannel curl cannot validate the leaf by IP SAN); nothing is emitted from
the build host directly.

## 4. Walkthrough (operator commands)

> Driven from the `nexus-infra-platform-tools` repo root. Executable System B demo: `DEMO-171`.

| # | Command | What you see | WHERE observed · What it proves |
|---|---------|--------------|---------------------------------|
| 1 | `pwsh -File scripts/smoke-0.Q.1.ps1` | ALL PASSED across seven sections: reachability · docker-compose services · Marquez API/admin/web/front-door · PG streaming replication · VIP bound + TLS through the VIP · cert SANs · an OpenLineage run-event round-trip. | stdout · the tier is healthy before the lineage drill: compose up, replication `streaming`, the VIP `.136` bound on exactly one PG node, and both leaves carry the VIP SAN. |
| 2 | `pwsh -File scripts/marquez-lineage-demo.ps1` | Four OpenLineage POSTs each return **201** (`curate-orders START/COMPLETE`, `load-dwh START/COMPLETE`); the read-back lists **2 jobs + 3 datasets** and the edges from `raw.orders`; ends `Lineage graph verified`. | stdout + `ssh nexusadmin@192.168.70.127 'docker compose -f /etc/nexus-marquez/docker-compose.yml ps'` · a real emitter round-trip into namespace `nexus-lineage-demo` over the nginx TLS front door — the api/web/nginx containers are Up and serving OpenLineage ingest (`:5000`) behind `:443`. **Cold-rebuild-proven 2026-07-21.** `DEMO-171`. |
| 3 | `ssh … 192.168.70.127 "curl --cacert /etc/ssl/certs/platform-tools-ca.pem --resolve marquez.nexus.lab:443:192.168.70.127 'https://marquez.nexus.lab/api/v1/lineage?nodeId=dataset:nexus-lineage-demo:raw.orders&depth=10'"` | The downstream graph from `raw.orders`: `raw.orders → curate-orders → curated.orders → load-dwh → dwh.fact_order`. | stdout · an **independent** operator read of the read model — traversing from the source dataset reaches the DWH fact through **both** jobs, proving the **edges** (not just the nodes) persisted. This is the "what breaks downstream?" answer. `DEMO-171`. |
| 4 | `ssh … 192.168.70.134 "sudo -u postgres psql -d marquez -c 'SELECT state,sync_state FROM pg_stat_replication'"` | `marquez-pg-1` (primary) shows its replica `streaming`. | stdout + `ssh … 192.168.70.134 'ip -brief addr \| grep 136'` · the lineage just emitted is committed to the **dedicated PG17 HA pair** and shipped to the standby; the VRRP VIP `.136` (the address Marquez dials `verify-full`) is held by exactly one node. The lineage catalog HA is real, not decorative. |

## 5. What this proves

- **Advanced SQL + data engineering** — a working **OpenLineage** backend: a two-stage pipeline
  (`raw.orders --[curate-orders]--> curated.orders --[load-dwh]--> dwh.fact_order`) is emitted as
  START/COMPLETE run events and the **downstream-impact query** (`/api/v1/lineage?nodeId=…&depth=10`)
  returns the full traversable graph — column/table lineage and impact analysis proven on live data, the
  metadata layer that makes the warehouse governable.
- **.NET engineering + architecture** — the tier is composed the platform way: a per-engine Packer template
  per node role, one Terraform env with an ordered apply (nftables → vault-agents → TLS → pg-replication →
  compose → lineage exit gate), and a committed, idempotent data-flow demo that both emits and verifies —
  a throwaway harness would have been a gap.
- **Python / DevOps** — the OpenLineage ingest endpoint (`OPENLINEAGE_URL=https://marquez.nexus.lab`) is the
  target every emitter in the platform (dataflow-studio, Prefect, Spark) points at, delivered as a
  **cold-rebuild-proven** tier (destroy → from-zero apply → smoke ALL GREEN, exit gate PASSED, 2026-07-21).
- **Advanced infra / HA** — the lineage store is not a single database: a dedicated PG17 primary/replica
  pair with streaming replication behind a **keepalived VRRP VIP** (`marquez-db.nexus.lab` `.136`) that
  Marquez reaches `sslmode=verify-full`, both leaves carrying the VIP SAN so a datastore failover is
  transparent to the app.

Full replay + playbook:
[`nexus-infra-platform-tools/docs/handbook.md`](https://github.com/grezap/nexus-infra-platform-tools/blob/main/docs/handbook.md)
§1 (build + verify) + §1.4 (emit lineage) + §3 (operator runbooks). Data-flow demo:
`nexus-infra-platform-tools/scripts/marquez-lineage-demo.ps1`. Executable System B demo:
`nexus-cli/docs/demos/DEMO-171`.
