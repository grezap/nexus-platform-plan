# ADR-0035 — Spark compute: standalone HA (2 masters + Apache ZooKeeper quorum)

- **Status:** accepted
- **Date:** 2026-05-24
- **Phase:** 0.L.3 (`nexus-infra-lakehouse`, tier `08-spark`)
- **Relates to:** [ADR-0033](./ADR-0033-minio-distributed-erasure-coded-object-storage.md) (S3 warehouse), [ADR-0034](./ADR-0034-iceberg-catalog-nessie-pg-master-replica.md) (Iceberg REST catalog), [ADR-0025](./ADR-0025-ha-promise-covers-lb-tier.md) (HA covers the control tier)

## Context

Phase 0.L.3 adds the Apache Spark compute engine that reads/writes the lakehouse
(Iceberg tables via the Nessie REST catalog of 0.L.2; Parquet in the MinIO
warehouse of 0.L.1). The platform is an HA showcase, so per ADR-0025 the cluster
*control plane* must not be a SPOF. A Spark standalone cluster's control plane is
the **master** (schedules apps onto workers). A single master is a SPOF for
submitting/scheduling new apps — so the topology needs master HA, not just
multiple workers.

The original roadmap sketched "1 master + 2 workers, FILESYSTEM recovery." Greg
rejected that as not enterprise-HA (the lone master is the weak point) and chose
true master HA: **2 masters + 3 workers**, coordinated by a quorum.

## Decision

Deploy **Spark 3.5.3 standalone in HA mode: 2 masters (`spark-master-1/2`,
`.140`/`.153`) + 3 workers (`spark-worker-1/2/3`, `.145`/`.146`/`.154`),
coordinated by a dedicated 3-node Apache ZooKeeper ensemble (`zookeeper-1/2/3`,
`.155`–`.157`).**

- **`spark.deploy.recoveryMode=ZOOKEEPER`** — the two masters run active/standby;
  ZooKeeper elects the live leader and persists the cluster state (workers + apps)
  so a master failure recovers without losing running work. Workers and clients
  use the **multi-master URL** `spark://192.168.70.140:7077,192.168.70.153:7077`;
  there is **no VIP** — the ZK election is the front door. (A keepalived VIP over
  two standalone masters does *not* work: without ZK they don't coordinate and
  would split-brain. The PG pair of ADR-0034 gets a VIP because one node is the
  writable primary; stateless equal endpoints — MinIO/Nessie — get round-robin
  DNS; the Spark masters get ZK election. The right HA primitive for each tier.)
- **Coordination backend = Apache ZooKeeper** — *the one deliberate exception to
  the platform's zero-Apache-ZooKeeper identity* (Kafka is KRaft; the analytics
  tier uses ClickHouse Keeper; the lab otherwise runs no ZooKeeper). Rationale:
  Spark standalone's only mainstream-tested master-HA mechanism is ZooKeeper.
  Guaranteed compatibility was chosen over brand purity (Greg, 2026-05-24).
- **ZooKeeper security = network segmentation.** The ensemble (client `:2181` +
  quorum `:2888`/`:3888`) runs **plaintext on the VMnet10 backplane only**;
  nftables trusts `192.168.10.0/24` and exposes nothing on VMnet11. The data ZK
  holds is non-secret Spark master-election metadata. ZK has no Vault footprint.
- **Spark RPC security = authenticated + encrypted, no certs.**
  `spark.authenticate=true` with a shared secret sticky-seeded in Vault KV
  (`nexus/lakehouse/spark/auth-secret`), plus `spark.network.crypto.enabled` (AES
  of the control/data RPC, keyed by that secret). The Master/Worker Web UI is HTTP
  on the nftables-restricted VMnet11 (UI TLS deferred — Spark standalone's
  `spark.ssl` keystore namespaces are a poor cost/benefit for an internal,
  firewalled UI). Outbound HTTPS to Nessie + MinIO validates against the Vault CA
  imported into the JVM truststore.
- **Spark cluster-peer RPC firewall.** Executors dial the driver back on a
  *dynamic* port (random `spark.driver.port`/`blockManager.port`), so opening only
  the fixed ports (7077/8080/8081) leaves executors unable to register. nftables
  on each Spark node accepts all TCP from the 5 Spark-node VMnet11 IPs — one trust
  domain, the VMnet11 analogue of the trusted backplane. The driver must also
  advertise its own IP (`spark.driver.host`/`bindAddress`), because the node's
  reverse DNS resolves to the round-robin `spark-master.nexus.lab` and would send
  executors to the wrong master.
- **Lakehouse wiring:** Iceberg tables via the Nessie REST catalog registered as
  Spark catalog `nexus` (`type=rest`,
  `uri=https://iceberg.nexus.lab:19120/iceberg/`, **warehouse referenced by NAME**
  `warehouse` — a URI yields "Warehouse not known"; Nessie owns the location +
  server-side S3 config). Iceberg client IO uses **`S3FileIO` (AWS SDK v2, the
  baked `iceberg-aws-bundle`)** for the `s3://warehouse` locations Nessie vends
  (`client.region` required); the Spark session catalog is `in-memory` (no
  embedded Hive/Derby metastore). Versions pinned for the known-good matrix: Spark
  3.5.3 (bin-hadoop3 → Hadoop 3.3.4) + `iceberg-spark-runtime-3.5_2.12` 1.7.1 +
  `iceberg-aws-bundle` 1.7.1 + `hadoop-aws` 3.3.4 + `aws-java-sdk-bundle` 1.12.262.

RAM right-sized: masters/workers 4 GB, ZooKeeper 2 GB ([feedback_prefer_less_memory]).

## Consequences

- The Spark control plane is **no longer a SPOF** — either master can be lost and
  the cluster keeps scheduling (ZK re-elects; running jobs survive).
- The lab now runs **exactly one Apache ZooKeeper ensemble**, scoped to Spark
  master HA and isolated on the backplane. This is a documented, deliberate
  exception; the rest of the platform stays ZK-free (KRaft / ClickHouse Keeper).
- 0.L.3 proves the **end-to-end lakehouse write path** that 0.L.1/0.L.2 deferred:
  a Spark job creates an Iceberg table through the Nessie REST catalog and writes
  Parquet to the MinIO warehouse (the exit-gate round-trip).
- **Cold-rebuild proven 2026-05-24** (destroy → from-zero apply → `smoke-0.L.3.ps1`
  ALL GREEN incl. ZK quorum, master HA election, 3 workers, and the Spark →
  Nessie → MinIO write round-trip). Apply-time transients fixed in source are
  chronicled in handbook §3.

## Alternatives considered

- **1 master + FILESYSTEM/NFS recovery:** simplest, running jobs survive a master
  restart, but the master is a SPOF for new-app submission during the outage —
  rejected for an HA showcase (ADR-0025).
- **ClickHouse Keeper as the ZK-wire-compatible quorum** (to keep "zero Apache
  ZK"): elegant on paper and on-brand, but Spark + ClickHouse-Keeper is a
  non-mainstream combination with real integration risk — rejected for a
  cold-rebuild-must-pass deliverable. Reusing the *analytics* CH Keeper was also
  rejected (couples the lakehouse to another tier, breaking ADR-0033/0034's
  self-contained principle).
- **Spark on Nomad / Kubernetes** (no long-lived master): the modern-enterprise
  pattern with no master SPOF at all, but a much larger scope change that couples
  the lakehouse to the orchestration tier — deferred (the future K8s tier is the
  natural home for orchestrated Spark).
- **VRRP VIP over the 2 masters:** does not provide Spark master HA — standalone
  masters don't coordinate without ZooKeeper, so a VIP alone yields split-brain.
- **Spark Web UI over TLS** (`spark.ssl` + PKCS#12 keystore): deferred — the
  `spark.ssl` standalone/ui namespaces are finicky and the UI is internal +
  firewalled; the substantive RPC security (authenticate + AES crypto) is in place.
