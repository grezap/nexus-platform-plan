# ADR-0034 — Iceberg REST catalog: Project Nessie on a dedicated PostgreSQL master-replica HA pair

- **Status:** accepted
- **Date:** 2026-05-24
- **Phase:** 0.L.2 (`nexus-infra-lakehouse`, tier `08-spark`)
- **Relates to:** [ADR-0033](./ADR-0033-minio-distributed-erasure-coded-object-storage.md) (the S3 warehouse this catalog points at)

## Context

Phase 0.L.2 stands up the Apache Iceberg table catalog the rest of the lakehouse
(Spark 0.L.3, StarRocks shared-data 0.L.5) reads and writes through. A catalog
needs two things: an **Iceberg REST API** front end that engines talk to, and a
**metadata store** that durably holds the namespace/table pointers. Both must be
HA — a single catalog endpoint or a single metadata DB would be a tier-wide SPOF
in an HA showcase, and table metadata loss is unrecoverable (the Parquet data in
MinIO is useless without the pointers).

Two decisions were required: which REST-catalog implementation, and what backs
its metadata.

## Decision

### REST catalog implementation = Project Nessie (Quarkus uber-jar)

Run **Project Nessie 0.107.5** as two independent instances (`iceberg-rest-1/2`,
`.147`/`.148`), fronted by **round-robin DNS** (`iceberg.nexus.lab` → both IPs) —
the same equal-endpoints pattern as MinIO (ADR-0033) and the analytics tier
([ADR-0031](./ADR-0031-analytics-client-front-door-round-robin-dns.md)). Each
instance is stateless; all shared state lives in the PostgreSQL pair below, so
either node can serve any request.

- **Ports (Quarkus split):** Iceberg REST API on **HTTPS :19120** (per-host PKI
  leaf, `QUARKUS_HTTP_SSL`, insecure-requests disabled); health/management on
  **HTTP :9000** (`/q/health`). The management interface is a *separate* listener
  from the app port — health probes hit `:9000/q/health`, never `:19120`.
- **Version store = `JDBC2`** on the **named `postgresql` datasource.** Nessie
  bundles that datasource but ships it `active=false`; it must be explicitly
  activated (`QUARKUS_DATASOURCE_POSTGRESQL_ACTIVE=true`) and selected
  (`NESSIE_VERSION_STORE_PERSIST_JDBC_DATASOURCE=postgresql`), or Nessie falls
  back to the inert default datasource and fails to start.
- **S3 warehouse** = `s3://warehouse` on MinIO, path-style, region `us-east-1`,
  endpoint `https://minio.nexus.lab:9000`. The compound access-key (name+secret)
  does **not** map cleanly from env vars — Quarkus config validation rejects the
  inline `access-key.name`/`.secret` form (SRCFG00050). It must be supplied as a
  **secret URN** (`urn:nessie-secret:quarkus:lakehouse-s3-creds`) resolved from a
  properties file pulled in via `QUARKUS_CONFIG_LOCATIONS`.
- **TLS trust:** the Vault CA is imported into the JVM truststore (`keytool` into
  `cacerts`) so Nessie's AWS S3 client trusts `minio.nexus.lab`.

### Metadata store = dedicated PostgreSQL 17 master-replica HA pair

Stand up **two dedicated PostgreSQL 17 nodes** (`iceberg-pg-1/2`, `.149`/`.150`)
as a streaming-replication pair behind a **keepalived VRRP VIP**
(`iceberg-db.nexus.lab` → **`.151`**). Nessie's JDBC URL targets the VIP, so a
primary failure transparently moves the write endpoint.

- **Streaming replication** over the VMnet10 backplane (`192.168.10.x`):
  `wal_level=replica`, the replica built by `pg_basebackup -R -Xs`; the
  walreceiver authenticates via a `postgres` `.pgpass` (basebackup `-R` does not
  embed the replication password in `primary_conninfo`).
- **keepalived** unicast VRRP, `state BACKUP` + **`nopreempt`** on both (a
  recovered old-primary never flaps the VIP back), priority 110/100,
  `notify_master` runs a promote hook that `pg_ctlcluster … promote`s the standby
  on failover. The `vrrp_script` health check must call the **versioned**
  `pg_isready` binary (`/usr/lib/postgresql/17/bin/pg_isready`), **not** the
  `/usr/bin/pg_isready` `pg_wrapper` symlink — the wrapper fails under
  keepalived's exec context, leaving `chk_pg` permanently down so no node ever
  takes MASTER and the VIP never binds.
- **mTLS** via per-host Vault PKI (`iceberg-server` role); the leaf SANs include
  `iceberg-db.nexus.lab` so clients validate the VIP. Replication rides the
  backplane (`pg_hba` `host replication … 192.168.10.0/24`); Nessie + admin
  connect over VMnet11 with `hostssl … scram-sha-256`.
- **Credentials** sticky-seeded in Vault KV (`nexus/lakehouse/iceberg/*`): PG
  superuser, replication, and the `nessie` DB-role password — read on-node via
  the local Vault Agent token, never transiting the build host.

RAM right-sized to 2 GB/node ([feedback_prefer_less_memory]); production reverts
to 8 GB+ on the PG pair.

## Consequences

- The lakehouse is **self-contained** — its catalog metadata lives in a PG pair
  it owns, with no dependency on the OLTP tier (ADR-0026/0027) or analytics.
  Combined with MinIO (ADR-0033), 0.L.1 + 0.L.2 form a complete standalone
  warehouse foundation.
- Both Nessie instances and both PG nodes stay up across the remaining lakehouse
  sub-phases (Spark, StarRocks shared-data consume the catalog); stopped only
  when the tier is idle, per minimal-running-VMs.
- **Cold-rebuild proven 2026-05-24** (destroy → from-zero apply → `smoke-0.L.2.ps1`
  ALL GREEN: PG streaming replication + VRRP VIP + 2× Nessie health + Iceberg
  REST `/v1/config` + namespace round-trip). Apply-time transients fixed in
  source are chronicled in handbook §3.

## Alternatives considered

- **Iceberg REST impl — Tabular/`iceberg-rest-fixture` or Lakekeeper:** the
  reference REST fixture is a non-HA demo image; Lakekeeper (Rust) is newer and
  less battle-tested. Nessie is a mature, Quarkus-native catalog with a JDBC
  version store that maps directly onto the dedicated PG pair, and adds Git-like
  branching/tagging for free. Chosen.
- **JDBC version store on a shared/existing PG (OLTP tier or analytics):**
  rejected — couples the lakehouse to another tier's lifecycle and blast radius;
  ADR-0033's self-contained principle extends to the catalog DB.
- **Single PG node for the catalog:** rejected — metadata loss is unrecoverable;
  a single DB is a tier-wide SPOF inconsistent with the HA promise (ADR-0025).
- **Patroni + etcd for the PG pair** (as scaffolded for 0.G.4): overkill for a
  2-node catalog store; keepalived VRRP + a promote hook delivers automatic
  failover with far less moving infrastructure, consistent with the LB-tier
  pattern used elsewhere in the platform.
- **VRRP VIP vs round-robin DNS for the REST tier:** Nessie nodes are stateless
  and equal, so round-robin DNS suffices (no VIP). The PG pair is *not* equal
  (one writable primary), so it gets the VIP — the right tool for each tier.
