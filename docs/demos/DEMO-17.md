# DEMO-17 · Container registry: push, scan, sign — survive a node loss

## 1. What this shows

The `09-platform` registry tier as the protagonist (an infra demo in the spirit
of DEMO-08 / DEMO-13 / DEMO-15). A DevOps engineer pushes a container image to a
**highly-available Harbor** and watches the supply-chain controls fire — then we
kill a registry node and pushes/pulls keep working:

- **HA app tier, no SPOF** (Phase 0.L.4): two stateless Harbor nodes
  (`registry-1`/`registry-2`) behind **round-robin DNS** `registry.nexus.lab`
  (ADR-0031). All state is external — **image blobs in MinIO S3** (the 0.L.1
  object store, ADR-0033), metadata in PostgreSQL, cache/job-queue in Redis — so
  either app node can be lost and the registry keeps serving.
- **HA datastore** (ADR-0036): a dedicated PostgreSQL 17 + Redis master-replica
  pair (`registry-pg-1/2`) with a **keepalived VRRP VIP** `registry-db.nexus.lab`
  (the proven 0.L.2 pattern); stop the primary → the VIP floats, the standby
  promotes, Harbor keeps serving.
- **Supply-chain integrity**: every push is **Trivy**-scanned for CVEs; images
  are **cosign**-signed and Harbor surfaces the signature.
- **SSO**: login is delegated to **Vault as an OIDC provider** (`auth_mode=oidc_auth`),
  which authenticates against AD via its existing `auth/ldap` — a local admin is
  the break-glass account.

Target persona: CTO / DevOps who wants to see that "private registry" means
*clustered, S3-backed, scanned, signed, SSO'd, and fault-tolerant* — not a single
`docker run registry:2`.

## 2. Runtime + prerequisites

- **Environment target** — `full` (or a `data-engineering` subset + the foundation)
- **VMs required** — nexus-gateway, dc-nexus, vault-1/2/3, vault-transit,
  minio-1/2/3/4 (the S3 blob backend), registry-1, registry-2, registry-pg-1,
  registry-pg-2
- **External services** — MinIO bucket `harbor` (blobs); PostgreSQL DB `registry`
  + Redis on `registry-db.nexus.lab`; Vault OIDC provider `nexus-registry`;
  Harbor project `library`
- **Seed data** — none; the bootstrap pushes `busybox` retagged as
  `registry.nexus.lab/library/smoke:v1`
- **Expected duration** — 6 min
- **Reset command** — `nexus-cli demo run DEMO-17 --reset`

## 3. Architecture snapshot

```
            round-robin DNS (no VIP, ADR-0031)
   registry.nexus.lab ─┬─ registry-1 (Harbor: core/portal/jobservice/registry/nginx/Trivy)
                       └─ registry-2 (same, stateless)
                                  │            │
              blobs ──────────────┘            └──────── DB + cache
        MinIO S3 (s3://harbor)            registry-db.nexus.lab  (keepalived VRRP VIP .119)
        minio.nexus.lab:9000              ├─ registry-pg-1  PostgreSQL primary + Redis master
        (0.L.1, ADR-0033)                 └─ registry-pg-2  PostgreSQL standby + Redis replica

   SSO: Vault OIDC provider (nexus-registry) ──auth/ldap──> AD (dc-nexus)
```

## 4. Step-by-step script

1. **Resolve the front door.** `dig +short registry.nexus.lab @192.168.70.1` → two
   IPs (`.115` + `.116`) — round-robin, no VIP.
2. **Both nodes healthy.** `curl --cacert ca.crt https://registry-1.nexus.lab/api/v2.0/health`
   and `…registry-2…` → every component `healthy`.
3. **Login + push.** On a node (or the build host): `docker login registry.nexus.lab -u admin`
   then `docker push registry.nexus.lab/library/smoke:v1`. The push streams layers.
4. **Blobs landed in MinIO, not local disk.** On minio-1: `mc ls --recursive nexuslocal/harbor`
   → docker/registry blob objects — the registry is genuinely S3-backed.
5. **Trivy scanned it.** Harbor UI (or API) → `library/smoke` artifact →
   scan overview `Success` with a CVE summary.
6. **cosign signed it.** `cosign verify --key cosign.pub registry.nexus.lab/library/smoke@<digest>`
   → verified; Harbor shows the signature accessory on the artifact.
7. **SSO is OIDC.** `GET /api/v2.0/configurations` → `auth_mode: oidc_auth`;
   the Harbor login page offers "Login via nexus-vault" (redirects to Vault).
8. **Kill an app node.** Stop `registry-2`'s Harbor stack. `docker pull
   registry.nexus.lab/library/smoke:v1` still succeeds via `registry-1` (shared
   state: same S3 blobs, same DB). Restart `registry-2` → rejoins.
9. **(Manual runbook) Kill the datastore primary.** Stop `registry-pg-1` → the VIP
   floats to `registry-pg-2`, which promotes PG + Redis; Harbor keeps serving.
   (Recovery re-seeds the old primary as the new standby — handbook §3.3.)

## 5. Observability trail

- Harbor: `/api/v2.0/health` (per-component), `/api/v2.0/systeminfo`,
  `/api/v2.0/projects/library/repositories/smoke/artifacts?with_scan_overview=true&with_accessory=true`.
- Datastore: on registry-pg-1 `sudo -u postgres psql -c 'SELECT * FROM pg_stat_replication'`;
  `redis-cli -a … info replication` (role master/slave); `ip addr show nic0` (the VIP).
- MinIO: `mc ls --recursive nexuslocal/harbor`; `mc admin info nexuslocal`.
- (Phase 0.I) Prometheus node_exporter on every registry node feeds Grafana.

## 6. Code pointers

- [`nexus-infra-registry`](https://github.com/grezap/nexus-infra-registry) —
  `terraform/envs/registry-harbor/` (overlays: nftables / vault-agents / tls /
  pg-replication / harbor-config / cluster-bootstrap) +
  `packer/registry-{harbor,pg}-node/` + `scripts/smoke-0.L.4.ps1`.
- Cross-tier: `nexus-infra-vmware` foundation
  `role-overlay-gateway-registry-{reservations,dns}.tf` + security
  `role-overlay-vault-{pki-registry,agent-registry-*,registry-creds-seed,oidc-registry}.tf`.
- ADRs: [0036](../adr/ADR-0036-harbor-registry-ha.md) (registry HA) ·
  [0033](../adr/ADR-0033-minio-distributed-erasure-coded-object-storage.md) (S3 blobs) ·
  [0031](../adr/ADR-0031-analytics-client-front-door-round-robin-dns.md) (round-robin) ·
  [0025](../adr/ADR-0025-ha-promise-covers-lb-tier.md) (HA covers the LB tier) ·
  [0013](../adr/ADR-0013-vault-ldaps-search-then-bind.md) (Vault↔AD).
- System B verb demos: deferred until the nexus-cli `HarborAdapter` lands.

## 7. Variations

- **Severity gate**: set a project CVE policy (block on HIGH/CRITICAL) and push a
  vulnerable image — the pull is refused.
- **Cosign enforcement**: enable "prevent unsigned" on `library`; an unsigned pull
  is refused.
- **OIDC group → role**: map an AD group to a Harbor project role via the OIDC
  groups claim; an AD user inherits it on first SSO login.

## 8. Troubleshooting

- A single-host `docker pull` that resolves the round-robin name once + pins can
  land on a just-killed node — retry (the no-VIP tradeoff, ADR-0031). Removing the
  dead node's A-record makes it deterministic.
- Datastore failover is **not** auto-reversible — recover the old primary as a
  fresh standby per handbook §3.3.
- If a push 500s on the S3 backend, check the `harbor` bucket exists +
  `nexus-lakehouse-app` can write it (`mc` on minio-1) and Harbor's
  `storage_service.ca_bundle` trusts the MinIO cert.

## 9. What this proves

The registry is not a toy: an **HA app tier** (round-robin, no SPOF) over an **HA
datastore** (PG streaming replication + Redis + VRRP VIP) with **S3-backed
storage** (MinIO), **vulnerability scanning** (Trivy), **image signing** (cosign),
and **SSO through the platform's identity hub** (Vault OIDC → AD). It survives an
app-node loss while serving correct content, and a datastore failover via the VIP
— the MASTER-PLAN "no toy infrastructure" mandate, proven by killing things on
stage.

---

**Status:** planned. The infra (0.L.4) is implementable now — every step maps to
`smoke-0.L.4.ps1` + the `registry-cluster-bootstrap` exit gate. The `nexus-cli
demo run DEMO-17` wrapper fills in when the CLI `HarborAdapter` lands.
