# DEMO-27 · Drive the Harbor registry tier from the CLI — the supply-chain front door, one tool over an app pair + a datastore pair + MinIO

## 1. What this shows

The Phase-0.L.4 registry plane — a **Harbor container registry HA** deployment (the platform's private
image registry, Trivy vulnerability scanning, cosign signing, Vault-OIDC SSO) — is now a first-class
`nexus-cli` cluster (ClusterId `registry`, nexus-cli v0.8.5). It is the **fifth and LAST non-data-tier
adapter** (after v0.8.1 Vault/foundation-ad, v0.8.2 Swarm, v0.8.3 Observability, v0.8.4 Lakehouse) — and
with it the CLI's deep adapter surface covers **EVERY cluster in the fleet**: full-fleet `IClusterAdapter`
coverage is achieved. The operator now manages everything from one tool, data and non-data tiers alike.

The headline is that **one component-aware adapter** spans a stateless **Harbor app pair** + a stateful
**PostgreSQL/Redis datastore pair** + an **external MinIO object store** — and the operator just runs
`nexus status registry`. Internally the adapter resolves the vms.yaml cluster `platform-tools` but **filters
to the four `registry-*` nodes** (the unbuilt prefect/unleash/marquez/backstage reservations classify
`other` and are excluded), then classifies each node by name-prefix (`registry-` → harbor / `registry-pg-`
→ datastore) and dispatches the right probe per component. There is **no managed Harbor / Npgsql / Redis
driver** (NetArchTest-enforced) — the Harbor API is a `sudo curl` over SSH and PG/Redis/VRRP/chaos/cert
control runs over node SSH.

The access posture matches the observability + lakehouse tiers (decided by diagnosing the live contract
first): the Harbor API (HTTPS :443, nginx) is probed **over SSH with each node's own
`/etc/nexus-registry/tls/ca.crt`** — self-consistent regardless of the build host's current CA generation —
and the Harbor admin password comes from Vault KV `nexus/registry/harbor-admin` (field `value`) via the
build-host `INexusVaultClient`.

An operator drives the whole tier from one tool: observe the rolled-up state, prove every component's signal
path is green (the Harbor 8-component health checklist, the PG streaming replication, the Redis master/replica
link, the cross-tier MinIO `s3://harbor` blob canary, the VRRP VIP), read the topology, take a `pg_dump`
backup of the Harbor metadata and round-trip it, rotate certs across all four nodes, list Harbor users, and
inject chaos on an app node (the RR-DNS pair tolerates one loss).

Personas: **platform engineer** (one tool to verify the whole supply-chain front door + a portable metadata
backup), **SRE** (the same panic-button verbs as every data tier — chaos, cert-rotate, the VRRP failover
drill), **security engineer** (creds never leave Vault KV; the adapter trusts each node's own CA; no managed
driver; the registry-db failover + the OIDC `acl grant` are honestly deferred to DR/onboarding runbooks rather
than silently doing something unsafe).

## 2. Runtime + prerequisites

- **Environment target** — the 4-VM registry tier (Phase 0.L.4) on the always-on foundation base, plus the
  lakehouse MinIO tier reachable as the `s3://harbor` blob backend.
- **VMs required** — the 4 registry nodes (`registry-1/2` Harbor app, `registry-pg-1/2` datastore — cluster
  `platform-tools` filtered to `registry-*` in [`docs/infra/vms.yaml`](../infra/vms.yaml)) + the keepalived
  VRRP VIP `.119` (`registry-db.nexus.lab`) + the **4 MinIO nodes** (lakehouse tier) up for the `s3://harbor`
  blob backend.
- **Env vars** — `VAULT_ADDR` · `VAULT_TOKEN` · `VAULT_CACERT` (to read the Harbor admin password from Vault
  KV `nexus/registry/harbor-admin`, field `value`) · `NEXUS_SSH_KEY` · `NEXUS_VMS_YAML`. (`scratch/nx.ps1`
  in `nexus-cli` sets these.)
- **Seed data** — none; the Harbor admin password is read from Vault KV and each node's `ca.crt` is read on
  the node over SSH.
- **Expected duration** — 4–6 min wall-clock (the cert-rotate ≈ 29 s + the chaos recover dominate).
- **Reset command** — none needed; chaos auto-recovers to green and `backup` is a non-destructive round-trip.
  `failover --direction registry-db` is intentionally NOT exercised — the keepalived `demote.sh` re-attaches
  Redis but not PG, so a VRRP cutover split-brains the datastore (a DR re-seed runbook). `acl grant/revoke` on
  a real user is deferred too — Harbor in `oidc_auth` mode returns 403 on local-user creation (users onboard
  via the AD→Vault-OIDC browser flow).

## 3. Architecture snapshot

4 VMs carry the registry tier. **registry-1/2** run the Harbor stack as docker-compose
(core/portal/registry/jobservice/trivy/nginx); they are **stateless behind round-robin DNS**
`registry.nexus.lab` (no VIP) on HTTPS :443 via nginx, API `/api/v2.0/*`. **registry-pg-1/2** are a dedicated
**PostgreSQL 17 streaming-replication pair + co-located Redis** master/replica behind a keepalived **VRRP VIP
`.119`** (`registry-db.nexus.lab`) — the PG primary + Redis master follow the VIP. The durable state is
**EXTERNAL**: image **blobs → MinIO `s3://harbor`** (lakehouse tier, EC-durable), metadata → the registry PG,
cache → Redis. SSO is **Vault OIDC** (`auth_mode=oidc_auth`) — operators log in to Harbor via the AD→Vault
OIDC browser flow, not local Harbor accounts. The supply-chain story end-to-end is **push → MinIO `s3://harbor`
blob → Trivy scan → cosign signature**, with project/robot access governed through the Harbor API.

## 4. The greenfield reality this tier was found in (and how the CLI handled it honestly)

Like the observability + lakehouse tiers, the registry tier was offline during the v0.8.1 Vault greenfield, so
it carried the same casualty class — but worse: it was found **operationally broken**, not just old-root.
Harbor was down (only `harbor-log` up), the PG replication was dead (both nodes primary), and the vault-agents
were old-root/unusable. A Greg-authorized **cold-rebuild to the new Vault root** was required to get a healthy
tier to live-verify against — and it deliberately put **both Harbor and MinIO on the new root**, resolving the
cross-tier CA split (`smoke-0.L.4.ps1` ALL CHECKS PASSED).

The rebuild surfaced a **cross-tier transient of the CA-rollover class — the MinIO root-password KV drift**:
the v0.8.1 greenfield had rotated the KV `nexus/lakehouse/minio/root-password` to an orphaned value while the
running MinIO kept its build-time root, so the harbor-config bucket step failed with `mc: signature does not
match`. The fix reconciled the **KV → the running MinIO's actual root** (a new KV-v2 version, old retained for
rollback; Greg-consented; data-preserving — no MinIO restart, no EC touch) + pre-reconciled the MinIO
`nexus-lakehouse-app` IAM key (Harbor's S3 credential) to the current KV. The apply then completed. (The
v0.8.3 obs rebuild noted this drift but could ignore it; Harbor surfaces it because the bucket step needs the
root creds.) The verb matrix then re-ran green against the rebuilt tier.

## 5. Walkthrough (operator commands)

> Driven via `nexus-cli/scratch/nx.ps1` (sets the runtime env, calls the freshly built `nexus.exe`).

| # | Command | What you see | WHERE observed · What it proves |
|---|---------|--------------|---------------------------------|
| 1 | `nexus status registry` | One 4-row table: the 2 Harbor app nodes (RR-DNS `registry.nexus.lab`), the datastore primary (the VIP `.119` holder, labelled) + the replica; reachable nodes **alive**; the future platform-tools reservations filtered out. | The CLI · one rolled-up view over an app pair + a datastore pair; the VIP holder is resolved live (it drifts), not assumed. |
| 2 | `nexus health registry` | `overall=green`: harbor-app **2/2** · **components 8/8 healthy** (core/database/redis/registry/registryctl/jobservice/portal/trivy) · systeminfo `auth_mode=oidc_auth` · pg-replication **1 streaming standby** · redis **master + 1 linked replica** · **s3-backend MinIO 200** · VIP `.119` bound. | The Harbor `/api/v2.0/health` checklist + every datastore signal in one report — including the cross-tier `s3://harbor` blob canary (the same trust probe that was RED before the rebuild). Proves the full supply-chain front door is healthy. |
| 3 | `nexus topology registry` | The 4 `registry-*` nodes (harbor-app ×2, datastore primary+replica) + the `.119` VIP pseudo-node + the MinIO `s3://harbor` blob-store. Shards = null (not data-sharded). | The full shape of the tier, including the external blob backend it depends on. |
| 4 | `nexus failover-test cluster registry --direction registry-db --yes` | A graceful, actionable **DR-deferred N/A**: the keepalived `demote.sh` re-attaches Redis but **not PG**, so a VRRP cutover of `.119` would promote the peer's PG while leaving the demoted node a second primary (split-brain) → a DR runbook (promote + fence + `pg_basebackup` re-seed). The VRRP+promote+Redis code path is verified against the live keepalived scripts; the app tier (RR-DNS) needs no failover and the verb refuses an app-direction with that pointer. | The CLI refuses an unsafe operation honestly instead of doing it and leaving the datastore broken — the lakehouse iceberg-pg + obs grafana-db precedent. |
| 5 | `nexus backup take registry --yes` then `nexus backup restore registry --yes` | `pg_dump` of the Harbor **metadata DB** (`registry`: projects, repos, artifacts, users, robots, replication rules) on the PG primary → **49 tables**, node-local gzip on registry-pg-1; restore reloads into a throwaway `registry_restore_verify` DB, counts **49 tables**, drops it. | A portable point-in-time copy of the adapter-ownable authoritative state + a non-destructive restore proof. Blobs are already EC-durable in MinIO and Redis is ephemeral cache, so only the metadata is snapshotted. |
| 6 | `nexus cert-rotate registry --yes` | Each node's vault-agent force-re-renders its `pki_int` leaf → **fresh leaf serials on all 4 nodes**, 0 errors, ≈ 29 s; then nginx container restart on the app nodes (picks up `harbor.crt`) + PG ssl reload on the datastore nodes, the **VIP holder (registry-pg-1) LAST**. | Cert rotation that respects each role's real reload path — not a blunt restart-everything; the VIP holder is rotated last so the front door stays up. |
| 7 | `nexus acl list registry` | The Harbor users via `/api/v2.0/users`, each enriched with project + robot-account counts (e.g. `harbor scope: 1 projects, 0 robot accounts`); the built-in `admin` flagged revoke-protected (break-glass); on a fresh OIDC tier there are no onboarded users yet. | Day-2 Harbor user/sysadmin management through the same `acl` surface every tier has. `grant`/`revoke` toggle the sysadmin flag (`PUT /users/{id}/sysadmin`) — the API path + user-resolution + protected-admin guard are verified; toggling a real target needs an OIDC-onboarded user (local-user creation is 403 in `oidc_auth` mode). |
| 8 | `nexus chaos registry process-kill --yes` | `docker` is killed on `registry-2` → `health` shows harbor-app **1/2** (the RR-DNS pair keeps serving from registry-1); the service restarts (`docker compose up -d`) and a health poll recovers it. The datastore VIP holder + PG primary + S3 are spared and unaffected. | The RR-DNS app pair's fault tolerance, exercised + recovered through the standard chaos verb. |

## 6. What this proves

One CLI now manages the entire registry tier — a stateless Harbor app pair, a stateful PostgreSQL/Redis
datastore pair, and the external MinIO blob store — through the same verb surface as every data and non-data
tier, with no managed drivers, creds confined to Vault KV, and honest reporting (the registry-db failover is
refused as a DR re-seed; the OIDC `acl grant` is deferred to the onboarding flow; one live-caught probe bug —
the unauthenticated `/systeminfo` omitting `harbor_version` — was fixed by re-gating on `auth_mode`). With the
registry adapter, **all 5 non-data-tier adapters are live and the CLI's deep adapter surface covers every
cluster in the fleet — full-fleet `IClusterAdapter` coverage is complete.** Full verb walkthrough + the
cold-rebuild proof:
[`nexus-cli/docs/verification/0.8.5-registry.md`](https://github.com/grezap/nexus-cli/blob/main/docs/verification/0.8.5-registry.md)
+ ADR-0026. The executable System B JSON demos are `nexus-cli/docs/demos/DEMO-147..159`.
