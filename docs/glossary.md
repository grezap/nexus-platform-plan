# Tool stack glossary — what is all this stuff?

NexusPlatform uses a lot of named tools. Most are industry-standard, but no single reader knows all of them. This page explains what each one **is** in plain English, and what role it plays in the lab.

The first cut covers **infrastructure tools** (Phase 0.A–0.L) — the foundational layer. The application stack (.NET, Blazor, MAUI, MediatR, MassTransit, ML.NET, ONNX, etc.) lives in [`docs/skills-coverage.md`](./skills-coverage.md) and will get its own glossary section in a later pass.

> **Format:** Each entry leads with a universal definition (something you could quote out of context), followed by an *In NexusPlatform:* line explaining the lab-specific role.

> **Reader path:** If you're new to all this, read top-to-bottom — sections are ordered by where in the stack each tool sits. If you're looking up a specific tool, ⌘-F / Ctrl-F.

---

## Sections

1. [Build & provision the lab](#1-build--provision-the-lab)
2. [Identity & secrets — the foundation tier](#2-identity--secrets--the-foundation-tier)
3. [Container orchestration](#3-container-orchestration)
4. [Data stores](#4-data-stores)
5. [Streaming & event flow](#5-streaming--event-flow)
6. [Analytics & data platform](#6-analytics--data-platform)
7. [Observability](#7-observability)
8. [Platform & supply chain](#8-platform--supply-chain)

---

## 1. Build & provision the lab

### VMware Workstation Pro
A **type-2 desktop hypervisor** for Windows and Linux hosts. Runs multiple guest VMs on a single physical machine, with virtual networks isolating them from each other. Free for personal use as of 2024.
*In NexusPlatform:* hosts the entire 66-VM lab on one Windows 11 workstation (`10.0.70.101`).
*Common alternatives:* VirtualBox (free, less stable under heavy load), Hyper-V (Windows-only).

### Packer (HashiCorp)
Builds **golden VM images** — reusable, pre-configured base templates from an OS install ISO. You define the image once in HCL; Packer drives the OS installer, runs your provisioning steps (Ansible, shell, PowerShell), and outputs an artifact you can clone many times. Same image format every time means every clone is identical.
*In NexusPlatform:* every VM in the fleet starts as a Packer-built template (`deb13`, `ubuntu24`, `ws2025-core`, `ws2025-desktop`, `win11ent`, `vault`, `swarm-node`, …). Cloning a template into a running VM takes seconds; without Packer, every VM would need to be installed by hand.

### Terraform (HashiCorp)
**Infrastructure-as-code.** You describe the desired state of your infrastructure in HCL files (`.tf`); Terraform calculates the diff against the current state and applies whatever creates/changes/destroys are needed to reach the desired state. State is tracked between runs so re-applies are incremental, not full rebuilds.
*In NexusPlatform:* every VM clone, every VM destroy, every config-overlay apply (DC promotion, Vault cluster bring-up, Swarm join, …) runs through Terraform. A single `terraform apply` can stand up a whole tier from scratch.
*Common alternatives:* Pulumi (same idea, in real programming languages), CloudFormation (AWS-only).

### Ansible
**Configuration management.** Connects to existing machines (over SSH or WinRM) and runs idempotent "playbooks" of YAML tasks to bring them to a defined state. Doesn't *create* infrastructure — it assumes the machine already exists, then configures it.
*In NexusPlatform:* runs inside Packer at template-build time. Four shared roles (`nexus_identity`, `nexus_network`, `nexus_firewall`, `nexus_observability`) configure every Linux template's baseline; per-template roles (e.g., `vault_node`, `swarm_node`) install the role-specific software on top.
*Common alternatives:* Chef, Puppet, Salt — all older, all in slow decline relative to Ansible.

### dnsmasq
A small DNS forwarder + DHCP server. Lightweight enough to run on a tiny VM; commonly used at the edge of small networks.
*In NexusPlatform:* runs on `nexus-gateway`, the lab's edge router. Handles DHCP for the management network (VMnet11) and forwards DNS queries to upstream resolvers, with per-MAC `dhcp-host` reservations pinning canonical IPs to known hosts (`vault-1` → `192.168.70.121`, `swarm-manager-1` → `192.168.70.111`, etc.).

### nftables
Linux's modern firewall framework (the successor to `iptables`). Defines packet-filtering, NAT, and connection-tracking rules.
*In NexusPlatform:* baseline firewall on every Linux VM (allow SSH from the management network, allow service-specific ports per role, deny everything else). On the gateway, also handles NAT masquerade for outbound internet egress + per-service inbound allowlists (NFS:2049 from manager IPs only, etc.).
*Footgun (Phase 0.E.4d):* Debian 13 routes `iptables` through `iptables-nft`, so Docker's iptables-installed rules end up in the kernel's nftables ruleset. Running `nft -f /etc/nftables.conf` (which starts with `flush ruleset`) wipes Docker's `DOCKER-INGRESS` DNAT rules, breaking Swarm published-port traffic until `systemctl restart docker` rebuilds them. Documented in [ADR-0018](./adr/ADR-0018-nftables-flush-ruleset-docker-conflict.md).

### NFS / NFSv4
**Network File System** — a protocol for sharing filesystems across machines over TCP. NFSv4 (the modern major version) collapses the v3-era multi-port mess (portmapper + mountd + nlockmgr + statd, all on dynamic ports) down to a single TCP/2049 listener — much friendlier for firewalled environments. Supports `fsid=0` to designate one export as the NFSv4 "pseudo-root" so clients mount via `server:/` rather than `server:/path`.
*In NexusPlatform:* `nexus-gateway` hosts a single NFSv4-only export (`/srv/nfs/portainer-data`) for Portainer CE's `/data` directory (BoltDB + admin state) — Phase 0.E.4a. Per-manager mount via `192.168.70.1:/` at `/var/lib/portainer-data`. The gateway-as-NFS-host pattern is a lab consolidation (production would use a dedicated NFS appliance like NetApp / TrueNAS / Pure Storage); documented as a deviation in [ADR-0017](./adr/ADR-0017-portainer-ce-nfs-via-gateway.md).
*Common alternatives:* CIFS/SMB (Windows-friendly), Ceph (distributed; for K8s CSI), GlusterFS (mostly retired).

---

## 2. Identity & secrets — the foundation tier

### Active Directory Domain Services (AD DS)
Microsoft's enterprise **directory service**. Stores user accounts, computer accounts, security groups, and policies in a hierarchical "domain" (or multi-domain "forest"). Provides centralized authentication (Kerberos), authorization, group policy, and DNS for Windows-heavy environments. The default identity provider in most corporate networks.
*In NexusPlatform:* a single forest `nexus.lab` runs on the `dc-nexus` domain controller. Every Windows VM joins the domain. Vault uses AD as its LDAP backend for human + service-account login and for automated password rotation.

### LDAP / LDAPS
**LDAP** (Lightweight Directory Access Protocol) is the wire protocol used to query and modify directory services like AD. **LDAPS** is LDAP over TLS — the encrypted form. Plain LDAP transmits credentials in cleartext; modern Windows defaults reject plain-LDAP simple binds, so LDAPS is the practical default.
*In NexusPlatform:* every connection from Vault to AD uses LDAPS on port 636, with the server cert issued by Vault's own internal PKI.

### HashiCorp Vault
A **secrets manager + cryptographic services platform**. Solves the problem "where do credentials, certificates, and encryption keys live, and how do humans + machines get them safely?" Stores arbitrary key-value secrets, can issue and rotate database/AD/cloud credentials on demand, runs as its own internal certificate authority, and exposes encryption-as-a-service over HTTP. Highly available via the Raft consensus algorithm.
*In NexusPlatform:* a 3-node cluster (`vault-1/2/3`) is the source of truth for every secret in the lab. A 4th single-node companion (`vault-transit`) auto-unseals the main cluster on reboot so operators don't have to hand-enter recovery keys after every power cycle.

Sub-features actively used in the lab:

- **KV v2 secrets engine** — Versioned key-value store, mounted at the `nexus/` path. The simplest secrets primitive: `vault kv put nexus/foo bar=baz`.
- **PKI secrets engine** — Vault as a private certificate authority. Issues short-lived TLS certs (90-day leaves in our setup) so services don't ship with hand-rolled self-signed certs.
- **AppRole auth method** — Machine-to-Vault authentication using a `role_id` + `secret_id` pair (think OAuth client credentials). Used by Terraform and by Vault Agent for unattended logins.
- **Transit secrets engine** — Encryption-as-a-service. Apps send plaintext, Vault returns ciphertext (or vice versa) without ever exposing the key. We additionally use it as the unseal key for the main cluster.
- **LDAP secrets engine** — Vault rotates passwords for AD service accounts on a schedule. Apps fetch the current password from Vault each time instead of storing it.
- **Vault Agent** — Sidecar process that authenticates to Vault and writes rendered secrets to disk for consumer apps. Refreshes them automatically before they expire so apps never see stale credentials.

### GMSA — Group Managed Service Account (Microsoft)
A special AD account whose password is generated and rotated automatically by AD itself. Only authorized computers/groups can retrieve the current password. Solves the perennial "this Windows service runs as a domain account, but who manages the password?" problem.
*In NexusPlatform:* Phase 0.D.5.3 scaffolded the consumer group + a sample GMSA; downstream Windows services use it instead of static passwords stored in scripts.

---

## 3. Container orchestration

### Docker
A **container runtime + image format**. Packages an app and its OS-level dependencies into a portable image (one filesystem layer per instruction in a `Dockerfile`); runs that image as an isolated process tree on Linux. The lingua franca of modern application packaging.
*In NexusPlatform:* every workload from Phase 0.G onward ships as a Docker image. The build host runs Docker Desktop for local builds; the lab runs Docker Engine on every Linux VM that hosts containers.

### Docker Swarm
Docker's **built-in clustering mode**. Joins multiple Docker hosts into a single virtual cluster ("swarm"). You define "services" with a desired replica count; Swarm spreads them across the nodes, restarts failed containers, and provides a virtual network mesh ("routing mesh") between them — published ports are reachable on every node IP and load-balanced via IPVS to active replicas. Simpler operating model than Kubernetes (no separate control plane to install) but less feature-rich.
*In NexusPlatform:* 6 nodes (3 managers + 3 workers) form the orchestration tier — Phase 0.E. Manager Raft quorum tolerates 1-of-3 down. Used for long-running services that don't need full Kubernetes (Portainer Server, future app workloads). Co-located with Nomad + Consul on the same VMs.
*Common alternatives:* Kubernetes (more powerful, heavier; we use it in Tier 3 via `nexus-infra-k8s`), Nomad (also runs containers but isn't container-only).

### HashiCorp Nomad
A **workload scheduler** that runs containers, raw binaries, JVM jars, and batch jobs across a cluster. Lighter than Kubernetes — one binary, no container-only constraint, unified scheduling for both long-running services and one-shot batch jobs.
*In NexusPlatform:* server-mode on the 3 Swarm managers, client-mode on the 3 workers — Phase 0.E.3. Hardened with mTLS for inter-agent RPC + raft (per-node leaf cert from `pki_int/issue/nomad-server` rendered by Vault Agent), HTTPS API on 4646 with `verify_server_hostname=true`, ACL `enabled=true` cluster-wide (mgmt token in Vault KV at `nexus/swarm/nomad-bootstrap-token`), and `vault {}` integration with the `nomad-cluster` periodic-token role (period=72h, allowed_policies=`nomad-jobs`) — Phase 0.E.3.3b. Inter-agent RPC authenticates via the mTLS cert SAN (Nomad's `acl{}` block doesn't have a `token` field). Complements Swarm by handling batch work (Spark drivers, ad-hoc data pipelines, NBomber load tests) that doesn't fit Swarm's "long-running service" model.
*Common alternatives:* Kubernetes (with Argo Workflows for batch), AWS Batch, Apache Mesos (mostly retired).

### HashiCorp Consul
**Service discovery + a small KV store + health checking + a service mesh**, all in one. When a service starts, it registers with Consul, gets a name (`postgres.service.consul`), and Consul's built-in DNS lets other services find it without hardcoded IPs. Health checks remove unreachable instances from rotation automatically. The "Consul Connect" subsystem provides mTLS between services backed by Vault PKI (deferred for now; Phase 0.E achieves transport-layer security via Vault PKI directly without Connect).
*In NexusPlatform:* server quorum runs on the 3 Swarm managers; client agents run on the 3 workers — Phase 0.E.2. Hardened with gossip encryption (32-byte symmetric key from `nexus/swarm/consul-gossip-key`), mutual TLS for internal RPC + Raft (per-node leaf from `pki_int/issue/consul-server`), HTTPS-only operator API on 8501 (plain HTTP/8500 hard-cut via systemd drop-in `-http-port=-1`), ACL `default_policy=deny` with 6 per-host agent tokens persisted to `nexus/swarm/agent-tokens/<host>`. Glues Swarm and Nomad together — Nomad's `consul{address=127.0.0.1:8501}` config (Phase 0.E.3.3a) gives jobs service discovery via Consul DNS.
*Common alternatives:* etcd (Kubernetes uses it), CoreDNS (DNS-only).

### Portainer CE
A **web UI on top of Docker / Swarm / Kubernetes**. Visual layer over the daily commands (`docker ps`, `docker service ls`, deployments, log tails, stack management). The CE is Community Edition — free, single-replica server (no native HA), unlimited nodes. Portainer EE adds active/standby HA + RBAC + audit logs; not needed at the lab tier.
*In NexusPlatform:* deployed as a 2-service Docker Swarm stack (Phase 0.E.4) — `server` (1 replica, manager-pinned via `node.role==manager` constraint, ports 9443/8000) + `agent` (mode global, 1 task per node × 6 = full cluster visibility). Server's `/data` (BoltDB + admin state) lives on an NFSv4 share from `nexus-gateway` so Swarm-rescheduled replicas pick up the same state on a different manager. TLS leaf cert from `pki_int/issue/portainer-server` (CN `portainer.nexus.lab` + per-host IP SANs); admin password sticky-seeded at `nexus/portainer/admin-bcrypt` (24-char alphanumeric plaintext + bcrypt hash). UI: `https://portainer.nexus.lab:9443`. See [ADR-0017](./adr/ADR-0017-portainer-ce-nfs-via-gateway.md).

---

## 4. Data stores

### PostgreSQL
General-purpose **relational database**. SQL-compliant, ACID transactions, strong type system, mature ecosystem of extensions (PostGIS, pgvector, TimescaleDB, …). Widely considered the best open-source RDBMS for new projects.
*In NexusPlatform:* the workhorse OLTP database for several app projects (`localmind` event store, `querylens`, others).

### Patroni
A **high-availability orchestrator for PostgreSQL**. Watches a Postgres primary; promotes a standby replica if the primary fails; uses a Distributed Configuration Store (DCS — etcd, Consul, or ZooKeeper) to elect the leader so split-brain can't happen. Runs as a long-lived Python supervisor process that owns PG's lifecycle (initdb, start, stop, promote, demote, pg_rewind), exposes a REST API (default :8008) for operator switchover/restart/reinitialize + LB health probes (`GET /leader` returns 200 only on the leader; 503 on replicas), and ships `patronictl` for cluster ops.
*In NexusPlatform:* a 3-node Patroni 4.0.5 cluster orchestrates PG 17 streaming replication; 3 etcd nodes hold the DCS at `/service/nexus-pg/`; HAProxy routes apps to the current leader via REST :8008 health probes. mTLS-only on :5432/:8008 via per-host Vault PKI; per-host `patroni.yml` rendered by the `oltp-patroni` Terraform overlay; operator wrapper `/usr/local/sbin/nexus-patronictl` pre-points patronictl at our config dir.

### etcd
A **Raft-replicated key-value store** designed as the metadata backbone for distributed systems (Kubernetes, Patroni, CoreDNS, ...). Strong consistency via the Raft consensus algorithm; survives `floor((N-1)/2)` member loss (3-member quorum tolerates 1; 5-member tolerates 2). HTTP+gRPC API; supports TLS for both client and peer connections + HTTP basic-auth or X.509-CN-based RBAC.
*In NexusPlatform:* a 3-node etcd 3.5.16 cluster (from upstream GitHub release tarballs) provides Patroni's DCS for cluster `nexus-pg`. Client API on :2379 (Patroni dials here); peer Raft on :2380 (ride VMnet10 backplane). TLS for wire encryption; HTTP basic-auth (root user, KV-seeded 32-char hex password) for RBAC. Operator wrapper `/usr/local/sbin/nexus-etcdctl` pre-loads endpoints + TLS material so `nexus-etcdctl endpoint status --cluster` works without operator typing.

### HAProxy
A **TCP/HTTP load balancer + reverse proxy**, the de-facto open-source LB for performance-sensitive backends. Active+passive health probes (TCP, HTTP, agent-check), per-backend routing rules, sticky sessions, request rewriting, and a real-time stats UI. Hot-reload via `-Ws` + SIGUSR2 (zero-downtime config reloads).
*In NexusPlatform:* a 2-node HA pair `haproxy-pg-1` + `haproxy-pg-2` fronts the 3-node Patroni cluster (mirrors the 0.G.3 proxysql-1/2 pattern). Both nodes run identical config; frontend `:5432` → `backend pg_pool` using `option httpchk GET /leader` against Patroni REST :8008 (200 only on leader; 503 on replicas/paused; HAProxy auto-routes to whichever backend returns 200). Stats UI on :8404 with HTTP basic-auth from KV-seeded `haproxy-stats-password`. **VRRP-floated VIP `192.168.70.60`** between the two nodes via `keepalived` (priority 110 MASTER + priority 100 BACKUP, **unicast mode** — VMware VMnet11 doesn't reliably forward IPv4 multicast `224.0.0.18`, lesson baked at 0.G.3.5c chunk 1 transient #22). Apps connect to `<VIP>:5432`; the cert IP-SANs on both haproxy nodes include the VIP so client TLS handshakes validate regardless of which node currently holds it.

### SQL Server (Microsoft)
Microsoft's **enterprise relational database**. Industry-standard in .NET shops; fully featured (T-SQL, columnstore, in-memory OLTP, native JSON). The lab exercises both classic HA modes:

- **FCI (Failover Cluster Instance)** — Two Windows nodes share one disk. If the active node fails, the passive node mounts the disk and the same SQL Server instance comes back up on the other host. Survives node failure but not disk failure.
- **AG (Always On Availability Group)** — Each node has its own disk; transactions replicate to one or more secondary replicas synchronously (or asynchronously). Survives both node and disk failure; secondaries can serve read-only queries.

*In NexusPlatform:* `dataflow-studio` and `querylens` use SQL Server. The lab demonstrates both FCI and AG topologies on Windows Server 2025.

### Percona XtraDB Cluster (PXC)
A **multi-master MySQL cluster** (a 5.7/8.0 fork of upstream MySQL). Every node accepts writes; Galera replication keeps all nodes synchronously in sync.
*In NexusPlatform:* `tenantcore` SaaS demo runs on PXC behind ProxySQL. 3-node PXC 8.0.45-36.1 (WSREP 26.1.4.3) on VMnet11, Galera SST/IST encrypted over VMnet10 backplane via `pxc-encrypt-cluster-traffic=ON`, mTLS-only on :3306 via per-host Vault PKI.

### Galera (wsrep)
A **synchronous multi-master replication library** used by Percona XtraDB Cluster + MariaDB Galera Cluster. Every write is certified across all nodes before commit. SST = State Snapshot Transfer (full datadir copy via xtrabackup-v2); IST = Incremental State Transfer (gcache replay).
*In NexusPlatform:* Galera underpins PXC. Lessons baked at 0.G.3 ratification: `wsrep_sst_auth` moved from [mysqld] to [sst] in PXC 8.0; `pxc-encrypt-cluster-traffic=ON` requires careful newline handling in wsrep.cnf when downstream tooling appends config.

### ProxySQL
A **MySQL-protocol-aware connection pooler + load balancer**. Sits between apps and MySQL/PXC nodes; routes queries by hostgroup, handles failover detection, splits reads vs writes. `mysql_galera_hostgroups` natively understands Galera member state for PXC.
*In NexusPlatform:* 2-node ProxySQL pair fronts the 3-node PXC cluster. Frontend on :6033, admin on :6032. `clustercheck` user probes Galera state; writer hostgroup (10) holds a single writable PXC node; backup_writer (20) + reader (30) take traffic on demote.

### keepalived (VRRP)
A **Linux daemon implementing VRRPv3** (Virtual Router Redundancy Protocol). Floats a virtual IP between cluster nodes by priority; the highest-priority healthy node holds the VIP. Health-script-driven priority demotion + preemption.
*In NexusPlatform:* used in two LB tiers — 2 ProxySQL nodes share VIP `.50` (0.G.3) and 2 HAProxy nodes share VIP `.60` (0.G.4). Both use **unicast mode** (`unicast_src_ip` + `unicast_peer`) — VMware Workstation's virtual networks (e.g., VMnet11) don't reliably forward IPv4 multicast `224.0.0.18`, so multicast VRRP causes split-brain. Lesson canonicalized at 0.G.3.5c chunk 1 ratification, applied uniformly to 0.G.4. Health-script wraps a simple `pgrep` (proxysql / haproxy) so a daemon crash demotes the node within one VRRP advertisement interval.

### MongoDB
A **document database**. Stores JSON-shaped records ("documents") with a flexible schema. Horizontal scaling via sharding, HA via replica sets.
*In NexusPlatform:* `localmind`, `visioncore`, `fieldsync`.

### Redis Cluster
**Sharded in-memory key-value store**. Sub-millisecond latency for caching, rate limiting, pub/sub. The cluster mode shards keys across multiple shards with replicas per shard.
*In NexusPlatform:* 3 shards × 2 replicas. Powers the `localmind` RAG cache and `tenantcore` session store.

### ClickHouse
A **columnar OLAP database**. Built for scanning billions of rows quickly with aggregations and analytical queries. Not for OLTP, not for join-heavy workloads, but staggeringly fast for analytical scans.
*In NexusPlatform:* powers the analytics half of `dataflow-studio` and `chronosight` time-series queries.

### ClickHouse Keeper
A **Raft-based coordination service** that replaces ZooKeeper for ClickHouse cluster metadata. Removes one external dependency; keeps the same protocol.
*In NexusPlatform:* a 3-node Keeper quorum coordinates the ClickHouse shards.

### StarRocks
A **real-time analytical database** with a separated frontend (FE) + backend (BE) architecture. Joins-friendly OLAP — bridges the gap between OLTP and ClickHouse-style scans.
*In NexusPlatform:* `dataflow-studio`'s interactive analytics layer.

### MinIO
**S3-compatible object store**, self-hosted. Same API as Amazon S3, so any S3 client works against it unchanged.
*In NexusPlatform:* backs Iceberg tables in `lakehouse-core` plus general object storage for Spark, Backstage, and demo recordings.

### Apache Iceberg
A **table format for data lakes**. Lets you treat a directory of Parquet files in S3/MinIO as if it were a SQL table — with schema evolution, time-travel, and ACID semantics over object storage. The basis of the modern "lakehouse" architecture.
*In NexusPlatform:* bronze/silver/gold layers in `lakehouse-core`, queryable from Spark, Trino, and dbt.
*Common alternatives:* Delta Lake (Databricks-flavored), Apache Hudi.

---

## 5. Streaming & event flow

### Apache Kafka
A **distributed log / streaming platform**. Producers write records to "topics"; consumers read them in order. Replicated across brokers, retains data for days or months, survives broker failures. The de-facto standard for event-driven architectures.

- **KRaft mode** (Kafka Raft) — Kafka's modern self-coordinating mode (no separate ZooKeeper required). All current Kafka versions use KRaft.
- **Schema Registry** (Confluent) — Stores Avro/Protobuf/JSON schemas for Kafka topics and enforces compatibility on producer writes. Prevents the "publisher updates schema, all consumers break" failure mode.
- **Kafka Connect** — Plugin framework for streaming data in and out of Kafka without writing custom producer/consumer code. *Source* connectors pull from external systems; *sink* connectors push to them.
- **Debezium** — A Kafka Connect plugin doing **change data capture (CDC)** — reads the database transaction log directly and emits row-level change events as Kafka records. Lets you stream every INSERT/UPDATE/DELETE into Kafka without app-side changes.
- **ksqlDB** — Streaming SQL on top of Kafka. `SELECT … FROM topic WHERE …` produces a continuously-updated result topic.
- **MirrorMaker 2** — Cross-cluster Kafka replication. Mirrors topics between clusters for DR or geographic distribution. Ships inside Apache Kafka as `connect-mirror-maker`; in "dedicated mode" each node runs a fixed replication flow (e.g. `east→west`) and prefixes mirrored topics with the source-cluster alias (`orders` on East → `east.orders` on West) so bidirectional replication stays loop-safe.
- **Confluent REST Proxy** — An HTTP front door to Kafka. Lets clients that can't (or shouldn't) embed a native Kafka client — browsers, scripts, non-JVM services — produce and consume records, manage topics, and look up schemas over plain REST/JSON instead of the Kafka wire protocol.

*In NexusPlatform:* two 3-node KRaft clusters (East primary + West DR) with a MirrorMaker 2 pair between them; Schema Registry HA pair for governance; a REST Proxy for HTTP-only clients; Connect + Debezium streams Postgres + SQL Server changes into Kafka; ksqlDB powers real-time aggregations. Stood up as Phase 0.H (`nexus-infra-kafka`, 15 VMs, every node holding a per-node Vault-PKI keystore and talking to the brokers over mutual TLS); `streamcore` later exercises the whole stack as a portfolio demo.

---

## 6. Analytics & data platform

### Apache Spark
A **distributed compute engine** for large-scale batch and streaming data processing. Originally a Hadoop replacement, now the standard for large-scale ETL pipelines and ML feature engineering. Programs in Scala, Python (PySpark), or SQL.
*In NexusPlatform:* 1 master + 2 workers run jobs in `lakehouse-core` (bronze→silver→gold transformations) and offline ML feature builds for `sentinelml` and `pulsenlp`.

### JupyterHub
A **multi-user Jupyter Notebook server**. Browser-based notebooks (Python, R, Scala) running against shared compute, with per-user authentication and isolation.
*In NexusPlatform:* front-end for ad-hoc Spark + ML experimentation against the data lake.

### Prefect
A **workflow orchestrator** — defines DAGs of tasks, schedules them, retries on failure, observability built in. Modern Python-native alternative to Airflow.
*In NexusPlatform:* schedules ETL DAGs (nightly bronze→silver→gold rebuilds, MirrorMaker monitoring jobs, etc.). Worker pool runs on Nomad.
*Common alternatives:* Apache Airflow (older, heavier), Dagster (newer competitor).

### Marquez (OpenLineage)
A **data-lineage backend**. Apps and pipelines emit OpenLineage events declaring which datasets they read and write; Marquez stores these and renders the resulting dependency graph. Lets you ask: "if I change source table X, what downstream pipelines / tables / dashboards break?"
*In NexusPlatform:* receives OpenLineage emissions from Prefect, Spark, and Kafka Connect; powers a "what-if I change this?" dependency view across the fleet.

### dbt (data build tool)
A **transformation framework** for warehouses. You write SQL `SELECT` statements as `models` (each becomes a table or view); dbt compiles + runs them in dependency order, captures lineage, and tests data quality. Standard in modern analytics engineering.
*In NexusPlatform:* drives the silver→gold transformations in `lakehouse-core`.

### Trino
A **distributed SQL query engine** that federates queries across heterogeneous data sources (Iceberg, Postgres, ClickHouse, Kafka, MongoDB, …). Lets a single SQL query join across multiple stores without moving data.
*In NexusPlatform:* gold-layer query layer in `lakehouse-core`; lets a Spark-built Iceberg table be queried alongside an OLTP Postgres table without ETL.

---

## 7. Observability

### OpenTelemetry (OTel)
A **vendor-neutral standard + libraries** for instrumenting code with the three pillars of observability: **traces** (call graphs across services), **metrics** (counters, gauges, histograms), and **logs**. Apps emit telemetry in OTLP format; collectors route it to backend stores. Replaces vendor-specific SDKs (Datadog, New Relic, etc.).
*In NexusPlatform:* every .NET service is instrumented with OTel; OTLP collectors fan the data out to Prometheus, Jaeger, and Seq.

### Prometheus
A **pull-based metrics database**. Periodically scrapes HTTP `/metrics` endpoints from your services, stores time-series, and exposes a query language (PromQL) for dashboards and alerts.
*In NexusPlatform:* short-term metrics. Long-term storage offloads to VictoriaMetrics.

### VictoriaMetrics
A **long-term metrics storage backend** that's wire-compatible with Prometheus but more efficient for retention beyond a few weeks.
*In NexusPlatform:* archives Prometheus data so 90-day Grafana panels work.

### Grafana
A **dashboard UI for time-series data**. Connects to many sources (Prometheus, ClickHouse, PostgreSQL, …), renders charts, alerts on PromQL/SQL conditions.
*In NexusPlatform:* 10 built-in dashboards covering every infra and application tier.

### Jaeger
A **distributed-tracing UI**. Visualizes a single request as it propagates through multiple services, with timing per hop. Click a slow request → see exactly where the time went.
*In NexusPlatform:* backend for OTel traces.

### Seq
A **structured-log search UI**, .NET-flavored. Like Splunk but lightweight and free for single-user deployments.
*In NexusPlatform:* receives OTel logs; primary log search interface for the .NET app fleet.

### Alertmanager
Part of the Prometheus stack. **Routes Prometheus-fired alerts** to channels (Slack, email, PagerDuty), with grouping, silencing, and de-duplication.
*In NexusPlatform:* routes lab alerts to a single channel — production-shape but lab-scale.

---

## 8. Platform & supply chain

### Harbor
A **self-hosted container registry**. Replaces Docker Hub for private + air-gapped use. Built-in vulnerability scanning, image signing, replication.
*In NexusPlatform:* every Docker image built by CI is pushed to `registry-1.nexus.local`.

### Trivy
A **vulnerability scanner** for container images and binaries. Reads an image's contents, looks up known CVEs in distro packages and language packages.
*In NexusPlatform:* runs in Harbor on every image push; CI fails if HIGH or CRITICAL vulnerabilities appear.

### cosign (Sigstore)
A tool for **signing and verifying container images**. Cryptographic provenance answering "did *we* build this image, or was it replaced?"
*In NexusPlatform:* every CI-built image is cosign-signed; deployments verify signatures before pulling.

### Backstage (Spotify)
An **internal developer portal**. A web UI listing all your services, owners, dependencies, docs, and runbooks — sourced from a YAML catalog file in each repo.
*In NexusPlatform:* optional in Phase 0.L; gives recruiters a "browse all 14 projects" UI.

### Unleash
A **self-hosted feature flag service**. Toggle features on/off per environment without redeploying.
*In NexusPlatform:* enables A/B testing and gradual rollouts of risky changes during demos.

### Syft + CycloneDX (SBOM tooling)
**Syft** generates a Software Bill of Materials (SBOM) — a complete inventory of every package in a container image or binary. **CycloneDX** is a standard SBOM format. Together they answer "what's actually in this artifact?" — the question that became urgent industry-wide after the Log4Shell incident.
*In NexusPlatform:* every release artifact ships with a CycloneDX SBOM produced by Syft.

### WSFC (Windows Server Failover Clustering)
The Windows-native clustering layer. Groups multiple Windows Server nodes into one logical cluster with shared resources, role failover, and quorum-based health. Provides the cluster heartbeat fabric (NetFT — Network Fault Tolerance), the role-migration primitives (move a resource from node A to B in seconds), and quorum (who's authoritative when nodes can't see each other).
*In NexusPlatform:* `sql-fci-cluster` at Phase 0.G.7 spans all 4 SQL Server nodes; hosts the FCI virtual server role (.70.16) and the AG Listener role (.70.17). Quorum=NodeMajority (tolerates 1 failure).

### FCI (SQL Server Failover Cluster Instance)
A single SQL Server instance inside a WSFC cluster — only ONE node owns the SQL service at any moment; others are passive failover targets sharing the same data files via shared storage. Differs from AG: FCI = 1 instance + 1 set of data files; AG = N instances + N independent data files synced via replication.
*In NexusPlatform:* sql-fci-1/2 form the FCI pair at Phase 0.G.7; share an iSCSI LUN per ADR-0026. On failover, the role + the .70.16 IP migrate atomically.

### Always On Availability Group (AG)
SQL Server's database-mirroring-evolved replication framework. 1 PRIMARY + N SECONDARY replicas, each an independent SQL instance. Transactions sync via TLS-encrypted HADR endpoint (port 5022). Sync replicas commit-block until acknowledged; async replicas lag but don't impact primary write latency.
*In NexusPlatform:* AG `nexus-ag` at Phase 0.G.7. FCI as SYNCHRONOUS_COMMIT primary + sql-ag-rep-1/2 as ASYNCHRONOUS_COMMIT secondaries. Endpoint auth = certificate-based per ADR-0027.

### AG Listener
DNS name + IP that SQL clients connect to instead of a specific node. WSFC migrates the Listener IP atomically with the AG primary on failover, so client connection strings work across failovers. Per ADR-0025 the Listener IS the LB-tier HA primitive for AG (no separate HAProxy/keepalived needed).
*In NexusPlatform:* `sql-ag-listener` at `.70.17`. Cert IP-SAN includes .17 so `Encrypt=True;TrustServerCertificate=False` validates across failover.

### GMSA (Group Managed Service Account)
AD-managed service account. AD stores + rotates the password (every 30 days by default, derived from the KDS root key); consuming servers retrieve it via `Install-ADServiceAccount`. Operator never sees the password; never in config; never in KV. Lateral-movement attacker gets a 30-day-bounded credential, not a static one.
*In NexusPlatform:* `gmsa-sql-engine$` at Phase 0.G.7 — first real GMSA consumer (0.D.5 scaffolded the infrastructure). SQL Server service identity on all 4 nodes. Per `memory/feedback_kds_rootkey_server2025_ssh.md`, KDS root key must be added via RDP on Server 2025 (broken over SSH).

### iSCSI Target / iSCSI Initiator
iSCSI = "SCSI over TCP" — block-storage protocol exposing a server's local disk as a LUN reachable over the network. **Target** = server (tgt on Linux); **Initiator** = client mounting the LUN as if it were a local SCSI disk.
*In NexusPlatform:* `nexus-gateway` runs tgt at Phase 0.G.7 (per ADR-0026), exporting one LUN to the FCI pair only. CHAP-authed + per-IP ACL. Enables SQL Server FCI on VMware Workstation Pro (which has no native shared-disk primitive).

### sqlcmd
SQL Server's canonical command-line client. Reads + executes T-SQL. Trivially scriptable from PowerShell + bash. Auth via Windows (`-E`), SQL (`-U user -P pwd`), or token. Per ADR-0024 the canonical operator surface for SQL clusters — no `Microsoft.Data.SqlClient` linked into nexus-cli's AOT binary.
*In NexusPlatform:* operator probes: `sqlcmd -E -S sql-ag-listener,1433 -Q "SELECT @@SERVERNAME"`. Smoke gate Section 12 + the nexus-cli SqlAgAdapter both shell out to sqlcmd over SSH.

---

## What's missing and coming later

This first cut is **infrastructure tools only**. A second pass will add:

- **.NET application stack** — ASP.NET Core, Blazor, Native AOT, gRPC, MAUI, MediatR, MassTransit, FluentValidation, …
- **ML stack** — ML.NET, ONNX Runtime, PyTorch, HuggingFace, Semantic Kernel, Ollama, …
- **Architecture patterns** — Clean Architecture, Vertical Slice, Modular Monolith, CQRS, Event Sourcing, Outbox, Sagas, …
- **Testing** — xUnit, Testcontainers, NBomber, Pumba, OWASP ZAP, …

Track [`docs/skills-coverage.md`](./skills-coverage.md) for the dense matrix of which project demonstrates which of those.

> If a tool name appears in any NexusPlatform document and isn't defined here yet, that's a doc bug — please flag it.
