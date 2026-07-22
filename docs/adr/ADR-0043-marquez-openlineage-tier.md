# ADR-0043 · Phase 0.Q.1: Marquez / OpenLineage tier — new repo `nexus-infra-platform-tools` + dedicated PostgreSQL HA pair

**Status:** accepted
**Date:** 2026-07-20
**Phase:** 0.Q.1
**Scope:** NEW repo `grezap/nexus-infra-platform-tools` (tier `09-platform`) + `nexus-platform-plan/docs/infra/vms.yaml` (new `platform-marquez` cluster; phase-ID correction on the `.125-.128` / `.134-.136` band) + `docs/infra/network.md` (same correction) + `MASTER-PLAN.md` (E16 row rewrite, new phase 0.Q) + foundation dnsmasq reservations (platform-tools overlay) + VIP DNS A-record.

## Context

Enhancement **E16 (data lineage)** needs an OpenLineage backend: a service that
receives OpenLineage events from pipeline code and renders the resulting job /
dataset / run graph. The chosen product is **Marquez** — the OpenLineage
reference implementation (LF AI & Data).

The canon carried a stale placement for it. MASTER-PLAN's E16 row said "Marquez
UI on obs-metrics VM", but **ADR-0038 had already moved Marquez *out* of the
observability tier** when 0.I was designed as a pure Grafana-LGTM stack — Marquez
is a lineage-metadata service, not a telemetry backend, and it went back to its
platform-tools home. `vms.yaml` has always reserved a dedicated `marquez` VM at
`.127` in the `09-platform` band. So the reservation and ADR-0038 agreed; only
the MASTER-PLAN E16 row was stale. This ADR records the correction.

The **first emitter is the Phase-1 application `dataflow-studio`** (its ingest /
transform / load stages emit OpenLineage run events). Later emitters are
**SentinelML**, **lakehouse-core** (Spark + dbt lineage), and the **Prefect flows**
of E23 — i.e. Marquez is a *foundational, cross-application* service, not a
dataflow-studio component, which is what drives the deployment decisions below.

Four decisions were taken by Greg (2026-07-20) and are recorded here as locked.

## Decision

Build a **Marquez / OpenLineage tier as Phase 0.Q.1** in the new repo
`nexus-infra-platform-tools` (tier `09-platform`), **3 VMs + 1 VRRP VIP**:

| Role | Count | Hosts | VMnet11 | VMnet10 | Port(s) |
|---|---|---|---|---|---|
| Marquez app node (Docker Compose) | 1 | `marquez` | `.127` | `.10.127` | API 5000 / admin 5001 / web 3000 |
| Marquez PostgreSQL pair | 2 | `marquez-pg-1/2` | `.134/.135` | `.10.134-.135` | PG 5432 |

| VIP | VMnet11 | Fronts | DNS |
|---|---|---|---|
| Marquez DB | `.136` | `marquez-pg-1/2` primary | `marquez-db.nexus.lab` |

Sizing: `marquez` 2 vCPU / 4 GB / 40 GB (Docker CE + compose plugin);
`marquez-pg-1/2` 2 vCPU / 2 GB / 60 GB (PostgreSQL 17, streaming replication)
— smallest that runs the tier ([[prefer-less-memory]]).

### Key sub-decisions

1. **New repo `nexus-infra-platform-tools`, home of the whole platform-tools
   band.** The repo owns `.125-.128` + `.134-.136` — Marquez now, and
   **prefect (0.Q.2), unleash (0.Q.3), backstage (0.Q.4)** later. Rejected: a
   fourth single-tool repo (`nexus-infra-marquez`), which would force three more
   single-tool repos behind it for tools of the *same class* in the *same* VM
   tier; and folding Marquez into `nexus-infra-registry`, whose scope is the
   container registry, not "platform tools". One repo gives one phase ID, one CI
   workflow, and shared `_shared` Ansible roles across all four tools. (Citus and
   Vitess got their own repos because each is a *distinct data engine* with a
   distinct HA model — that reasoning does not transfer to four small
   docker-on-VM utilities.)

2. **A NEW phase ID `0.Q`.** The `vms.yaml` / `network.md` rows for this band
   previously carried "0.I/0.J/0.K", but all three are already allocated in
   MASTER-PLAN — **0.I** = the observability tier (ADR-0038), **0.J** =
   `nexus-shared` NuGet packages, **0.K** = the portfolio website shell — and none
   of them scopes platform-tool deployment. `0.Q` is the next free ID after
   **0.P** (Citus, ADR-0042). Corrected in `vms.yaml`, `network.md`, and
   MASTER-PLAN in the same change as this ADR.

3. **A DEDICATED PostgreSQL HA pair** (`marquez-pg-1/2` + keepalived VRRP VIP
   `marquez-db.nexus.lab`), **not** co-located on the `marquez` node and **not**
   sharing `registry-pg`. Lineage metadata is a first-class store with its own
   growth curve (one row-set per pipeline run, unbounded until a retention policy
   is applied) and its own retention/backup cadence; sharing `registry-pg` would
   couple the availability of the *lineage plane* to that of the *image registry*,
   two services with entirely unrelated failure domains. This mirrors the
   established per-tier-datastore pattern already proven three times —
   `registry-pg` (`.119`, ADR-0036), `iceberg-pg` (`.151`, ADR-0034), `grafana-pg`
   (`.185`, ADR-0038) — using the same lighter keepalived-VRRP + streaming-
   replication mechanism rather than Patroni. **The cost is recorded honestly:**
   this is the fleet's *third* dedicated PG pair, +2 VMs and +1 VRRP instance to
   operate and back up. Accepted, because per-tier datastore isolation is already
   platform canon and breaking it here for two VMs would be the exception that
   erodes it.

4. **Deploy form = Docker Compose on the VM.** Marquez ships as containers
   (`marquez-api` + `marquez-web`); **Harbor (ADR-0036) already set the
   docker-on-VM precedent in this exact tier**, so 0.Q.1 reuses the tier's
   established shape rather than inventing a second one. Rejected: running Marquez
   as a Nomad/Swarm workload on the 0.E orchestration tier — that would make a
   *foundational* lineage service depend on the orchestration plane, and the
   tier's other resident (Harbor) is deliberately standalone for exactly that
   reason. A platform-tools service must be reachable when the orchestrators are
   being rebuilt.

### Security + provisioning surface

- **New Vault PKI role `platform-tools-server`** (shared by the whole `0.Q` band,
  same shape as `registry-server`). The Marquez API/web is fronted by a
  Vault-PKI leaf whose SANs carry `marquez.nexus.lab` + the node IP; the PG certs
  carry `marquez-db.nexus.lab` + the VIP IP `.136` so DB TLS validates across a
  failover.
- **Vault KV** at `nexus/platform-tools/marquez/{db,replication,superuser}-password`
  — sticky-seeded, read by the overlay via per-host AppRole sidecars.
- **Two per-engine Packer templates** (`platform-marquez-node`,
  `platform-marquez-pg-node`) + **one per-cluster Terraform env**
  `terraform/envs/platform-marquez` with its own state, per
  [[per-cluster-state-per-engine-template]].
- **MACs `:E0`-`:E2`** (prior high-water `:DF`, Citus 0.P) — pre-apply MAC+IP
  audit against every foundation reservation file per [[mac-pool-pre-apply-audit]].
  The VIP `.136` is virtual (no MAC / no DHCP pin).
- **Smoke gate `smoke-0.Q.1.ps1`**, cold-rebuild-proven before sealing.

### Terraform state is gitignored (matching the siblings, not diverging from them)

`nexus-infra-platform-tools` **gitignores `terraform.tfstate*`**, using the
sibling repos' `.gitignore` verbatim. State lives on disk in the env directory
but is never tracked.

This is worth recording only because an earlier draft of this ADR asserted the
opposite — that the sibling infra repos *commit* state in-tree and that this repo
was deliberately diverging. **That was incorrect.** It came from observing the
`terraform.tfstate` files present on disk in `nexus-infra-registry` and inferring
they were tracked. They are not: `git ls-files` returns **zero** tracked tfstate
files across `nexus-infra-{registry,vmware,observability,lakehouse,citus,vitess}`,
and `git check-ignore` confirms `registry/.gitignore:9 *.tfstate` covers them.
There is no state exposure in any sibling repo, and nothing to remediate.

The real, surviving lesson is narrower and still binding: a `.gitignore` does not
untrack an *already-tracked* file, and suffixed backups can slip past a narrow
pattern — which is why the standing rule is **stage explicit paths, never
`git add -A`**, in this repo as in every other.

## Consequences

### Positive

- **Closes E16.** The platform gains a real OpenLineage backend that
  `dataflow-studio` (Phase 1) emits to today, and SentinelML / lakehouse-core /
  Prefect (E23) emit to later — lineage becomes a cross-application capability
  rather than one app's feature.
- **Opens the 0.Q platform-tools phase** with a repo and a proven tier shape, so
  prefect / unleash / backstage are incremental adds (`0.Q.2`-`0.Q.4`) rather than
  three more greenfield decisions.
- **Corrects three canon staleness bugs in one pass** — the MASTER-PLAN E16 row
  (obs-metrics → dedicated `marquez` node, aligning with ADR-0038), the
  "0.I/0.J/0.K" phase-ID collision on the platform-tools band, and the missing
  `0.Q` allocation.
- **Reuses the tier's existing patterns wholesale** — docker-on-VM (ADR-0036),
  keepalived VRRP + streaming replication (ADR-0034/0036/0038), Vault PKI leaf +
  AppRole sidecar, per-engine template + per-cluster state.

### Negative

- **Fleet 140 → 143** (+3 VMs), and the **third dedicated PG HA pair** to operate,
  monitor, and back up. Mitigated by minimal-running-VMs discipline
  ([[minimal-running-vms]]) — the tier runs only when the lineage plane is in use.
- **Marquez app tier is a single node** (unlike Harbor's 2 stateless nodes). Its
  state is fully external in `marquez-db`, so an HA second node is a later,
  cheap add (round-robin DNS, ADR-0031) — but as shipped, 0.Q.1's *app* tier is a
  SPOF. Accepted for a metadata-viewer whose loss does not stop pipelines: an
  OpenLineage emitter failing to reach Marquez must never fail the pipeline run.
- **A third PostgreSQL HA pair to operate** (after registry-pg and grafana-pg,
  plus iceberg-pg): +2 VMs, another streaming-replication pair and another
  keepalived VIP in the fleet's operational surface. Accepted because per-tier
  datastore isolation is already platform canon, and the alternative couples the
  lineage plane's availability to an unrelated tier's.

### Risks

- **Unbounded lineage growth.** Every pipeline run writes run/job/dataset/facet
  rows; without a retention policy `marquez-db` grows monotonically. The 60 GB PG
  disk is sized with headroom, but a retention/compaction job is an explicit
  0.Q.1 follow-up.
- **Emitter coupling.** `dataflow-studio` must treat OpenLineage emission as
  best-effort/async — a Marquez outage or a slow `POST /api/v1/lineage` must not
  block or fail the pipeline stage that emitted it.
- **Docker + nftables.** The tier's node runs Docker CE behind the lab's nftables
  ruleset; every `nft -f` reload must be followed by a Docker restart
  ([[nftables-flush-ruleset-wipes-docker]], ADR-0018) — the likely first-apply
  transient.

## Alternatives considered

1. **A fourth single-tool repo (`nexus-infra-marquez`).** Rejected — four tools of
   the same class in the same VM tier would become four repos, four phase IDs, and
   four copies of the same Ansible roles.
2. **Fold Marquez into `nexus-infra-registry`.** Rejected — that repo's scope is
   the container registry; Marquez shares only the IP band, not the concern.
3. **Marquez on the obs tier (the stale MASTER-PLAN E16 row).** Rejected —
   already reversed by ADR-0038; lineage metadata is not telemetry, and 0.I is a
   closed, sealed LGTM stack.
4. **Reuse `registry-pg` as Marquez's database.** Rejected — couples the lineage
   plane's availability to the image registry's, across two unrelated failure
   domains and backup cadences; breaks the per-tier-datastore canon (ADR-0034/0036).
5. **Bundled PostgreSQL in the Marquez compose stack (single node).** Rejected —
   a non-HA, un-backed-up store for first-class metadata, and it puts the DB in the
   same failure domain as the app.
6. **Marquez as a Nomad/Swarm workload on 0.E.** Rejected — a foundational service
   must not depend on the orchestration plane; Harbor is standalone in this tier for
   the same reason.
7. **Reuse an existing phase ID (0.I/0.J/0.K).** Rejected — all three are allocated
   to unrelated scopes in MASTER-PLAN; reusing one would corrupt the phase ledger.

## See also

- [ADR-0036](./ADR-0036-harbor-registry-ha.md) — the `09-platform` tier's
  docker-on-VM + dedicated-PG/keepalived precedent this tier follows
- [ADR-0038](./ADR-0038-observability-tier-grafana-stack-ha.md) — moved Marquez out
  of the observability tier; `grafana-pg` is the third instance of the PG-pair pattern
- [ADR-0034](./ADR-0034-iceberg-catalog-nessie-pg-master-replica.md) — the original
  keepalived-VRRP + streaming-replication PG-HA pattern
- [ADR-0042](./ADR-0042-citus-sharded-postgresql-cluster.md) — 0.P, the phase this
  one follows in the ledger
Operator memory notes this ADR leans on (these live in the build host's memory
store, outside any repo — referenced by name, deliberately not hyperlinked):

- `feedback_never_git_add_all_state` — stage explicit paths, never `git add -A`
- `feedback_mac_pool_pre_apply_audit` — the pre-apply MAC+IP audit (`:E0`-`:E2` /
  `.127`, `.134`-`.136`, ALL CLEAR 2026-07-20)
- `feedback_per_cluster_state_per_engine_template` — per-engine template +
  per-cluster state canon
- `feedback_vault_role_write_is_full_replace` — why `platform-tools-server` is a
  brand-new PKI role rather than a patch to an existing one
- `feedback_nftables_flush_ruleset_wipes_docker` — `nft -f` drops Docker's chains;
  `systemctl restart docker` after every ruleset reload on the marquez node
