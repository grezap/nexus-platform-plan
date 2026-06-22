# DEMO-25 · Drive the observability tier from the CLI — VRRP cutover, ring scale-out, honest health on a drifted tier

## 1. What this shows

The Phase-0.I observability plane — the **Grafana LGTM stack** (Prometheus + Loki + Grafana + Tempo +
Alertmanager + OTel Collector) across 14 VMs + 2 VRRP VIPs (grafana VIP `.184`, grafana-db VIP `.185`), with
MinIO (the lakehouse tier) as the Loki/Tempo S3 backend — is now a first-class `nexus-cli` cluster (ClusterId
`observability`, Phase 0.I, nexus-cli v0.8.3). It is the **third non-data-tier adapter** (after v0.8.1 Vault /
foundation-ad and v0.8.2 Swarm).

The interesting part is the **access posture**, which was decided by diagnosing the live contract first rather
than assuming. The obs node TLS leaves are on the tier's **OLD CA generation** — the tier was offline during
the v0.8.1 Vault greenfield — while the build host now trusts the **NEW root**. So the adapter does **not**
validate obs endpoints from the build host; it probes each service **over SSH using that node's own `ca.crt`**
and reads runtime creds from Vault KV via `INexusVaultClient` (every observability secret field = `value`).
There is **no managed Prometheus/Grafana/Loki driver** (NetArchTest-enforced).

An operator drives the whole tier from one tool: observe the rolled-up state, prove every signal path is green
(or honestly red where the tier has drifted), read the topology, fail the Grafana VRRP VIP over to its standby,
add and remove a Loki/Tempo memberlist ring member, inject chaos on a ring node, list Grafana users, and confirm
why `backup` is a deliberate no-op on this tier.

This tier is **partially degraded by design of the demo** — three infra divergences (all v0.8.1-Vault-
greenfield-while-obs-offline casualties, the same class as the swarm tier's Portainer drift) are surfaced
**honestly** by the verbs rather than papered over: a tier-wide vault-agent broken-trust state (which is exactly
why the adapter probes locally over SSH), the Grafana admin password drifted from KV, and a split grafana-pg
streaming replication. The demo shows the CLI telling the truth about all three.

Personas: **SRE / observability engineer** (signal-path verification + VIP DR drill), **platform owner** (the
observability tier has the same panic-button verbs as every data tier), **security engineer** (creds never
leave Vault KV; the adapter trusts each node's own CA, not a blanket bundle; restore is not even offered).

## 2. Runtime + prerequisites

- **Environment target** — the 14-VM observability tier (Phase 0.I) on top of the always-on foundation base,
  plus the lakehouse MinIO tier reachable as the Loki/Tempo S3 backend.
- **VMs required** — the 14 observability nodes (cluster `observability` in
  [`docs/infra/vms.yaml`](../infra/vms.yaml)) + the 2 VRRP VIPs (grafana `.184`, grafana-db `.185`). The
  Grafana-PG pair and the Loki/Tempo memberlist rings must be up.
- **Env vars** — `VAULT_ADDR` · `VAULT_TOKEN` · `VAULT_CACERT` (to read the observability runtime creds from
  Vault KV — every secret field is `value`) · `NEXUS_SSH_KEY` · `NEXUS_VMS_YAML`. (`scratch/nx.ps1` in
  `nexus-cli` sets these.)
- **Seed data** — none; the creds are read from Vault KV and each node's `ca.crt` is read on the node over SSH.
- **Expected duration** — 5–8 min wall-clock (the Grafana VRRP failover + the ring scale-out dominate).
- **Reset command** — none needed; failover auto-recovers (VIP returns on master re-priority), scale-out remove
  is reversed by scale-out add, and chaos recovers to green. `cert-rotate`, `failover grafana-db`, and `acl
  grant` are intentionally NOT exercised here — they need a Greg-authorized tier trust re-apply first.

## 3. Architecture snapshot

14 VMs carry the LGTM signal paths: Prometheus scrapes the fleet; Loki and Tempo each run a **memberlist hash
ring** over their members; Alertmanager runs a **gossip mesh**; Grafana is a VRRP-fronted pair backed by a
Grafana-PG **streaming-replication** pair (its own VIP); the OTel Collector is the single OTLP ingress. MinIO
(lakehouse tier) is the S3 object backend for Loki and Tempo. The two VRRP VIPs (grafana `.184`, grafana-db
`.185`) each float between a master and a standby. Because the build host's NEW root does not chain to the obs
nodes' OLD leaf CA, the adapter SSHes to each node and runs the health probe **locally** against that node's own
`ca.crt` — the trust is per-node, not a build-host bundle.

## 4. Step-by-step script

| # | Persona action | Command | Expected observation |
|---|---|---|---|
| 1 | See the whole tier | `nexus status observability` | A table of **14 nodes** + the **2 VIP holders** (which node currently owns grafana `.184` / grafana-db `.185`); reachable nodes **alive**. |
| 2 | Prove every signal path | `nexus health observability` | The full probe set: Prom ready + scrape-targets-up, Alertmanager mesh peers, Loki/Tempo memberlist rings, Grafana `database=ok`, OTel loopback, Grafana-PG streaming replication, MinIO S3 reachable, **both VIPs bound**. On this drifted tier the grafana-pg streaming-replication probe is **honestly RED** (the replication is split) — the verb does not hide it. |
| 3 | Read the topology | `nexus topology observability` | **14 nodes + 2 VIP pseudo-nodes** + the ring/scrape counts (memberlist ring sizes + Prometheus scrape-target count). |
| 4 | Fail over the Grafana VIP | `nexus failover-test cluster observability --direction grafana --yes` | **Grafana VRRP cutover** — the `.184` VIP moves to the standby and Grafana stays reachable, **RTO ≈ 1.2 s**; the VIP returns to master on re-priority. |
| 5 | Grow + shrink a ring | `nexus scale-out add observability --role loki --yes` then `nexus scale-out remove observability <member> --yes` | The Loki/Tempo **memberlist ring** add/remove is reversible; the fixed-HA roles (Grafana / Grafana-PG / OTel) correctly return **graceful N/A** (they don't scale by ring membership). |
| 6 | Inject chaos on a ring node | `nexus chaos observability process-kill --target <loki-or-tempo-node> --yes` | The targeted member drops out of its memberlist ring, then the process restarts and the **ring recovers to green** — `health` re-reports the ring at full size. |
| 7 | List Grafana users | `nexus acl list observability` | Reads Grafana users via `/api/admin/users`. On this drifted tier the Grafana admin password has drifted from KV, so `acl` **honestly returns HTTP 401** + the **reconcile command** to fix it — it does not silently fail or fake success. |
| 8 | Ask why there's no backup | `nexus backup take observability` | A **graceful, actionable "not applicable"** — MinIO is erasure-coded, the Grafana-PG repl is RPO≈0, dashboards are managed as-code, and the Prometheus TSDB is ephemeral, so there is no snapshot to take. |

## 5. What it proves

- The observability tier carries the same verb surface as every data-tier cluster — `status` / `health` /
  `topology` / `failover` / `scale-out` / `cert-rotate` / `acl` / `backup` — rolled into one operator view over
  the LGTM stack + its VIPs.
- **Honest health on a drifted tier:** rather than papering over the three v0.8.1-greenfield-while-obs-offline
  divergences, the verbs surface them — `health` reports the grafana-pg split RED and `acl` reports the admin
  drift as a 401 with the reconcile command. Truth over green.
- **Security posture:** the runtime creds stay in Vault KV; the adapter trusts **each node's own `ca.crt`**
  (probing over SSH locally) rather than a build-host bundle that wouldn't chain to the OLD obs CA; no managed
  observability driver is linked; `backup restore` is not even offered.
- **Availability:** the Grafana VRRP VIP cuts over to its standby on demand (RTO ≈ 1.2 s); a Loki/Tempo ring
  member can be added, removed, or lost to chaos with the ring recovering to green.

Companion executable (System B) demos, one per verb: `nexus-cli/docs/demos/DEMO-124..133`. Adapter decisions:
`nexus-cli` ADR-0024. Verification evidence: `nexus-cli/docs/verification/0.8.3-observability.md`.

> Note: on the live tier, `cert-rotate` (build-host `pki_int/observability-server` issue + SSH-push + per-service
> reload), `failover --direction grafana-db`, and `acl grant` are implemented but were **not** live-run on the
> degraded tier — they need a Greg-authorized tier trust re-apply first, after which this walkthrough extends to
> cover them.
