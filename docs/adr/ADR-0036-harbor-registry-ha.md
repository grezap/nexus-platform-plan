# ADR-0036 — Container registry: Harbor HA (2 app nodes + dedicated PG/Redis HA, MinIO S3 blobs, Vault OIDC)

- **Status:** accepted
- **Date:** 2026-05-25
- **Phase:** 0.L.4 (`nexus-infra-registry`, tier `09-platform`)
- **Relates to:** [ADR-0033](./ADR-0033-minio-distributed-erasure-coded-object-storage.md) (S3 blob backend), [ADR-0034](./ADR-0034-iceberg-catalog-nessie-pg-master-replica.md) (the PG-HA pattern reused here), [ADR-0031](./ADR-0031-analytics-client-front-door-round-robin-dns.md) (round-robin DNS front door), [ADR-0025](./ADR-0025-ha-promise-covers-lb-tier.md) (HA covers the LB tier), [ADR-0013](./ADR-0013-vault-ldaps-search-then-bind.md) (Vault↔AD LDAPS)

## Context

Phase 0.L.4 adds the platform's container registry: the private, signed,
vulnerability-scanned store every CI-built image is pushed to. The chosen product
is **Harbor** (CNCF graduated). The platform is an HA showcase, so per ADR-0025 the
registry's control plane must not be a single point of failure, and per the
platform identity MinIO is "the storage foundation everything depends on."

Four either/or decisions were taken with Greg (2026-05-25). The first three were
answered directly; the HA choice then contradicted "bundled per-node datastore"
(Harbor HA cannot use per-node bundled PostgreSQL/Redis — two app nodes must
**share** one DB + cache or their state diverges), which a follow-up resolved.

- **Blob storage = MinIO S3** (not local disk) — on-brand; the registry exercises
  0.L.1, and the app nodes stay stateless for layers.
- **Topology = HA** (not the single-node canon originally sketched in vms.yaml).
- **Shared datastore = a dedicated, registry-tier PostgreSQL + Redis HA pair**
  (not Harbor's per-node bundled DB; not a coupling to the 0.L.2 iceberg PG; not a
  single-DB SPOF).
- **Auth = Vault OIDC SSO** (not AD LDAPS directly, not Harbor's built-in DB).

## Decision

Deploy **Harbor (latest stable 2.x, offline installer) in HA: 2 stateless
application nodes (`registry-1`/`registry-2`, `.115`/`.116`) + a dedicated
PostgreSQL 17 + Redis master-replica HA datastore (`registry-pg-1`/`registry-pg-2`,
`.117`/`.118`) with a keepalived VRRP VIP `registry-db.nexus.lab` (`.119`).**

- **App-tier HA = round-robin DNS, no VIP.** Both Harbor nodes run the full
  Harbor compose stack (core, portal, jobservice, registry, nginx, Trivy) and are
  *equal stateless front doors*; `registry.nexus.lab` resolves to `.115`+`.116`
  (ADR-0031 mechanism: an `addn-hosts` round-robin record). Docker/OCI clients
  retry across the A-records, so the LB tier itself has **no SPOF** — satisfying
  ADR-0025 without adding a load-balancer VM or a VIP over the app tier. (A VIP
  over two *stateless* nodes buys nothing round-robin DNS doesn't; the VIP is
  reserved for the *stateful* datastore where exactly one node is the writable
  primary.)
- **State is fully external** (the precondition for stateless app HA):
  - **Blobs → MinIO S3.** Harbor's `registry` component is configured with
    `storage_service.s3` → the `harbor` bucket on `minio.nexus.lab:9000`
    (path-style, the Vault-CA-trusted endpoint), using a dedicated MinIO service
    account. Layers never touch the app nodes' disks.
  - **Metadata → PostgreSQL 17** on the registry-pg HA pair (`harbor` databases),
    reached at the VIP `registry-db.nexus.lab:5432`.
  - **Cache / job-queue → Redis** co-located on the registry-pg pair, reached at
    the same VIP `:6379`.
- **Datastore HA reuses the proven 0.L.2 pattern (ADR-0034).** PostgreSQL
  streaming replication (primary `registry-pg-1` → hot standby `registry-pg-2`)
  over the VMnet10 backplane; keepalived VRRP (state BACKUP + `nopreempt` so a
  recovered old-primary never flaps the VIP back; `notify_master` promotes the
  standby on failover). **Redis follows the same VIP**: the VIP-holder runs the
  Redis primary, the peer a replica; on failover the promoted node's Redis becomes
  authoritative. Redis holds only cache + the job queue, so a cold cache after
  failover is acceptable (Harbor rebuilds it). One VRRP instance fronts both
  services — exactly one node holds `.119` at any time.
- **mTLS via per-host Vault PKI.** A shared `registry-server` PKI role issues
  per-host leaf certs. The Harbor nginx serves HTTPS `:443` with a cert whose SANs
  carry `registry.nexus.lab` (the round-robin front door) + both hostnames + node
  IPs, so a client handshake validates whichever app node answers. The PG/Redis
  certs carry `registry-db.nexus.lab` + the VIP IP `.119` so DB/cache TLS
  validates across failover. The fleet already trusts the nexus CA (deb13
  baseline); Harbor's containers trust it via the CA mounted into the registry +
  the host trust store.
- **Auth = Vault OIDC SSO.** Vault is configured as an **OIDC provider**
  (`identity/oidc/provider`) with a Harbor client; Harbor runs `auth_mode =
  oidc_auth` pointed at Vault's discovery URL. Login is delegated to Vault, which
  authenticates the user against AD via its existing `auth/ldap` (ADR-0013) — so
  the registry gets AD-backed SSO *through* the platform's identity hub rather than
  a second direct AD integration. The Harbor **local `admin`** account (password
  sticky-seeded in Vault KV `nexus/registry/harbor-admin`) is retained as the
  break-glass / automation account; the OIDC client secret + Harbor's encryption
  `secretKey` are likewise sticky-seeded in Vault KV.
- **HA secret coherence.** Harbor encrypts secrets stored in the shared DB with a
  16-byte `secretKey`; both app nodes MUST use the *same* key (and the same
  registry `http.secret` / core CSRF key) or tokens and stored credentials break
  across nodes. The `harbor-config` overlay reads these once from Vault KV and
  installs them identically on both nodes before `./prepare`.
- **Trivy + cosign.** Harbor is installed `--with-trivy` (vulnerability scanning
  on push; policy can gate by severity). **cosign** (baked CLI) signs a pushed
  image and Harbor surfaces the signature — the supply-chain-integrity showcase.

RAM right-sized: Harbor app nodes 4 GB (the compose stack is the heavier tier),
datastore nodes 2 GB ([feedback_prefer_less_memory]). App-node disk right-sized
**400 → 80 GB** vs the original single-node *local-blob* spec — image layers live
in MinIO S3, so the app node only holds Harbor's own component images + logs +
Trivy's DB cache (logged as a deviation in `vms.yaml`).

## Consequences

- The registry **control plane is no longer a SPOF**: either Harbor app node can
  be lost and `docker push`/`pull` keep working (round-robin DNS + external
  state); the datastore tolerates a PG/Redis node loss (VRRP failover + streaming
  replica promotion).
- 0.L.4 **exercises 0.L.1 end-to-end** as more than a Spark warehouse: MinIO now
  also backs the registry's blob store — the first non-lakehouse S3 consumer.
- The lab gains a **second, distinct PG-HA cluster** (registry-pg) on the same
  proven keepalived pattern as iceberg-pg (0.L.2), and its **first co-located
  Redis-HA** — both registry-tier-owned, no cross-tier coupling.
- **Vault becomes an OIDC provider** for the first time — a reusable capability
  later tiers (Grafana, Portainer SSO, future app consoles) can adopt.
- New tier `09-platform` is opened; the `.116`–`.119` slots previously pencilled
  in `network.md` for future prefect/unleash/marquez/backstage shift to
  `.120`–`.123` (canon updated). MAC block: `.115`=`:A4` (existing reservation) +
  `.116`=`:AF`, `.117`=`:B0`, `.118`=`:B1` (the `:A5`–`:A9` gap stays reserved for
  0.L.5 StarRocks shared-data).
- **Cold-rebuild proven** (destroy → from-zero apply → `smoke-0.L.4.ps1` ALL GREEN
  incl. round-robin DNS, mTLS, PG replication + VIP, Redis, both Harbor nodes
  healthy, S3 blob backend, a `docker push` + Trivy scan + cosign sign/verify, and
  the HA chaos checks). Apply-time transients fixed in source are chronicled in the
  repo handbook §3.

## Alternatives considered

- **Single-node Harbor with bundled PG/Redis + local-disk blobs** (the original
  vms.yaml sketch): simplest, 1 VM, but the registry is a full SPOF — rejected for
  an HA showcase (ADR-0025). It also wouldn't exercise MinIO.
- **HA with the bundled per-node datastore:** architecturally impossible — two
  Harbor nodes with independent PG/Redis diverge. Rejected (the contradiction that
  forced the follow-up decision).
- **Reuse the 0.L.2 iceberg PG (or 0.G.4 Patroni) for Harbor's DB:** would buy DB
  HA "for free" but couples the registry to the lakehouse/OLTP tier and breaks the
  self-containment principle (ADR-0033/0034). Rejected — the registry tier owns
  its own datastore.
- **A VIP / dedicated load-balancer in front of the 2 Harbor app nodes:** adds a
  VM (or a VIP) and an LB to maintain for no benefit over round-robin DNS, since
  the app nodes are stateless equals (ADR-0031). Rejected.
- **Patroni for the registry PG (vs streaming replication + keepalived):** the
  heavier Patroni+etcd+HAProxy stack (0.G.4) is overkill for a two-node datastore
  whose failover need is modest; the lighter keepalived-VRRP pattern (0.L.2) is the
  right fit. Rejected for this tier.
- **AD LDAPS directly from Harbor (vs Vault OIDC):** simpler and conventional, but
  a second direct AD integration; Vault OIDC routes SSO through the platform's
  identity hub and is the more distinctive showcase (and reusable by later tiers).
  Kept as the documented fallback if OIDC proves too brittle for zero-touch.
- **Distribution/registry:2 or zot instead of Harbor:** lighter, but no built-in
  UI, RBAC, scanning, signing, or replication — Harbor is the enterprise-grade
  choice the portfolio is demonstrating.
