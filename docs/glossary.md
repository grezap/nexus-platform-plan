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
*In NexusPlatform:* hosts the entire lab (140 VMs built through Phase 0.P) on one Windows 11 workstation (`10.0.70.101`).
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

### FSMO roles (Flexible Single Master Operation)
AD is multi-master — most changes can be made on any DC and replicate out — but five operations must be performed by a single role-holding DC to avoid conflicts: **Schema Master** + **Domain Naming Master** (forest-wide) and **PDC Emulator** + **RID Master** + **Infrastructure Master** (per-domain). A healthy forest has all 5 roles seized + reachable.
*In NexusPlatform:* a single-domain forest `nexus.lab` holds all 5 roles on `dc-nexus`; the `FoundationAdAdapter` `health` verb enumerates all 5 (and proves them reachable) as one of its checks.

### KDS root key
The forest-wide **Key Distribution Service** root key from which GMSA passwords are derived. Must exist before any GMSA can be created or retrieved.
*In NexusPlatform:* added once at Phase 0.D.5 (via RDP on Server 2025 — broken over SSH, per memory); the `FoundationAdAdapter` `health` verb proves it present via the AD object.

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

### Transit auto-unseal
On start, a Raft Vault node is **sealed** — its data is encrypted and it can't serve until the unseal key is supplied. **Auto-unseal** delegates that step to another Vault's Transit engine: the node asks the transit Vault to decrypt its sealed root key, so no human types unseal shards on every reboot. The transit Vault itself still uses classic Shamir key shares.
*In NexusPlatform:* `vault-1/2/3` (the HA cluster) auto-unseal against `vault-transit`; `vault-transit` is the Shamir-seal custodian at the bottom of the chain. A host reboot can race the two (`vault-transit` not yet up when the cluster boots) — see *recover-ha*.

### Raft snapshot
A consistent point-in-time backup of a Raft-backed Vault's entire data store, taken with `vault operator raft snapshot save`. Restoring it overwrites live state, so it's a backup primitive to guard, not run casually against a trust root.
*In NexusPlatform:* the nexus-cli `VaultAdapter` `backup` verb takes a raft snapshot + non-destructively inspects its `meta.json` (gzip/tar); restore is deliberately refused on the live trust root.

### recover-ha (boot-race recovery)
A bespoke nexus-cli verb (a new `IRecoverableCluster` capability) for the foundation Vault: the declarative fix for the post-reboot seal race — **unseal `vault-transit` from its Shamir key file → restart `vault-1/2/3` → poll until unsealed**. It is the *only* exposed unseal path in the CLI.
*In NexusPlatform:* shipped with `VaultAdapter` (`v0.8.1`); codifies the manual `recover-vault-ha.ps1` runbook into a single operator verb.

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
*In NexusPlatform:* `localmind`, `visioncore`, `fieldsync`. Phase 0.G.2 ships a 3-node **replica set** (HA showcase); Phase 0.N ships a **sharded cluster** (horizontal-scaling showcase) — see below.

### MongoDB sharded cluster (mongos · config server · shard)
A MongoDB cluster that partitions a collection's documents across multiple **shards** by a **shard key** (range or hashed), giving horizontal write/storage scale beyond one replica set. Three roles: a **shard** is a replica set holding a subset of the data (chunks); the **config server** is its own replica set holding cluster metadata (which chunk lives on which shard); **`mongos`** is a stateless query *router* — clients connect to it, it reads chunk locations from the config servers and routes each operation to the owning shard. Sharding (partitioning) and replication (per-shard RS) compose: each shard tolerates a node loss independently.
*In NexusPlatform:* Phase 0.N — 3 config-server RS (`config`, port 27019) + 2 shard RSes (`shard-1`/`shard-2`, port 27018, 3 nodes each) + 2 `mongos` routers (port 27017, round-robin DNS `mongos.nexus.lab`). keyFile internal auth; clients auth as `nexus-sharded-admin` against the admin DB (mongos forbids the `local` DB that `__system` uses). Distinct from the 0.G.2 replica set — the RS is the *replication* showcase, the sharded cluster the *sharding* showcase ([ADR-0040](adr/ADR-0040-mongodb-sharded-cluster-separate-from-0g2-rs.md)). 0.N.1 added Vault-PKI wire mTLS (requireTLS, per-host mongo-sharded-server leaves, online rotateCertificates), parity with the 0.G.2 RS.

### vtgate
Vitess's stateless **MySQL-protocol query router** — the client front door (`:15306`). Apps connect to it exactly as they would a single MySQL server; it reads the topology for shard/tablet locations and routes each query to the owning shard (fanning out + merging for cross-shard reads). No state of its own, so it scales horizontally and sits behind round-robin DNS with no VIP.
*In NexusPlatform:* Phase 0.O — 2 vtgate routers (`vitess-vtgate-1/2` @ `.194/.195`, round-robin DNS `vtgate.nexus.lab`, MySQL listener `:15306`) front the `commerce` keyspace; the vtgate MySQL listener + every gRPC channel run Vault-PKI mTLS.

### vttablet
Vitess's **per-tablet sidecar** that fronts a single MySQL (Percona) instance. It serves queries from vtgate, registers the tablet in the topology (etcd), manages the local mysqld (via `mysqlctld`), and participates in VTOrc-driven reparenting (promotion/demotion). One vttablet+mysqld pair per tablet.
*In NexusPlatform:* Phase 0.O — 6 tablets (2 shards × 3), each a vttablet + Percona Server 8.4 LTS mysqld pair; one initial PRIMARY + 2 REPLICA per shard.

### vtctld
Vitess's **cluster control / admin daemon** (gRPC + web UI `:15000`). Executes administrative operations — `ApplySchema`, `ApplyVSchema`, `PlannedReparentShard`, reshard workflows — against the topology and tablets; the `vtctldclient` CLI talks to it.
*In NexusPlatform:* Phase 0.O — runs on `vitess-control-1` (@ `.193`) alongside VTOrc; mTLS on its gRPC channels.

### VTOrc
Vitess's **automated failover orchestrator** (one per cell). Continuously monitors tablet + replication health and **auto-reparents** a shard — promoting a healthy replica to PRIMARY — when the current PRIMARY dies. The relational-sharding analogue of MongoDB's RS auto-election or Patroni's PG leader election.
*In NexusPlatform:* Phase 0.O — co-resident with vtctld on `vitess-control-1`; the smoke gate kills a shard PRIMARY and proves VTOrc re-elects a new one (~15s) with the cluster staying writable.

### Vitess BackupStorage
Vitess's **pluggable backup backend** — where `vtctldclient BackupShard` writes and `RestoreFromBackup` reads a shard's physical image. Implementations: `file` (a shared filesystem, e.g. NFS, seen by all tablets + vtctld), `s3`, `gcs`, `ceph`, `azblob`. Orthogonal is the **backup *engine*** — `builtin` (Vitess's own file copy; drains the tablet) or `xtrabackup` (Percona XtraBackup hot physical backup; no serving drain). `BackupShard` auto-picks a REPLICA/RDONLY so the PRIMARY keeps serving.
*In NexusPlatform:* Phase 0.O.1 (2026-07-09) — a `file` BackupStorage on shared **NFSv4** (`/vt-backups`; NFS server co-located on the control node, exported to the VMnet10 backplane, mounted on all 6 tablets) + the **`xtrabackup`** engine. Three deploy gotchas: vttablet needs `--mycnf-file` (mysqld is `mysqlctld`-owned) and must **drop `--db-socket`** to enter managed mode (else it skips the my.cnf and can't back up), and xtrabackup reads its DB password only from the my.cnf's `[xtrabackup]` group — placed in `ssl.cnf` (already in the live `EXTRA_MY_CNF`) so it survives every my.cnf regeneration. The nexus-cli `backup take/restore vitess` verbs drive it (`BackupShard` / `RestoreFromBackup`; restore is dry-run by default, real onto a replica with `--confirm-destructive`).

### keyspace
A Vitess **logical database**, horizontally partitioned into one or more **shards**. Tables in a keyspace are sharded according to its VSchema; an unsharded keyspace is a single shard.
*In NexusPlatform:* Phase 0.O — keyspace `commerce`, split into 2 shards (`-80` / `80-`) on a hash vindex.

### vindex
A Vitess **"vindex" (Vitess index)**: the function that maps a table column (the **sharding key**) to a `keyspace_id`, which in turn determines the owning shard. A `hash` vindex spreads rows evenly across shards; other types (lookup, unicode) support secondary routing. The vindex is what lets vtgate route a keyed query to exactly one shard instead of fanning out.
*In NexusPlatform:* Phase 0.O — a `hash` vindex on the `commerce` sharding key splits 100 inserted rows ~53/47 across shards `-80` and `80-` (proven in `smoke-0.O.ps1`).

### Citus
A **PostgreSQL extension** (`shared_preload_libraries='citus'`) that turns a set of PostgreSQL servers into a distributed database — the PG-native analogue of Vitess for MySQL. Unlike Vitess (external query router + topology server), Citus is "just PostgreSQL": clients speak the normal PG wire protocol to the coordinator. Distribution metadata lives in the coordinator's `pg_dist_*` catalog; HA is orthogonal and supplied by Patroni streaming-replication.
*In NexusPlatform:* Phase 0.P — PostgreSQL 17 + Citus 14.x, the relational-PG-sharding showcase (sibling of 0.O Vitess). 9 VMs, full Patroni HA + Vault-PKI mTLS.

### coordinator (Citus)
The Citus node that holds the **distributed catalog** (`pg_dist_node` / `pg_dist_shard` / `pg_dist_partition`) and is the client entry point. It **routes** single-shard queries to the owning worker and **fans out + merges** cross-shard aggregates. It stores no table data itself (only the metadata + reference-table copies). A coordinator outage makes the whole distributed DB unqueryable, so it is the highest-value HA target.
*In NexusPlatform:* Phase 0.P — a 2-node Patroni pair (`citus-coord-1/2`) behind VIP `coord.citus.nexus.lab` (`.211`); clients connect here on `:5432`.

### worker (Citus)
A Citus node that **holds the shards** of every distributed table. The coordinator dials workers (over verify-full mTLS) to push down query fragments. Workers are registered in `pg_dist_node` via `citus_add_node(...)`.
*In NexusPlatform:* Phase 0.P — 2 worker node-groups (`citus-worker1`/`citus-worker2`), each a 2-node Patroni pair behind a VIP (`.212`/`.213`); registered **by VIP** so a worker failover needs no `pg_dist_node` rewrite.

### distributed table
A table whose rows are **hash-partitioned into shards spread across the workers** (`create_distributed_table('t','dist_col')`). Queries filtered on the distribution column route to a single shard; aggregates fan out and merge at the coordinator. The Citus equivalent of a Vitess sharded table.
*In NexusPlatform:* Phase 0.P — `events` (distributed on `tenant_id`, 32 shards across both worker groups); `smoke-0.P.ps1` proves the shards span both workers + a `count(*)` cross-shard aggregate returns the full seeded set.

### reference table
A small table **fully replicated to every node** (workers + coordinator) via `create_reference_table('t')`, so joins against distributed tables resolve locally with no reshuffle. The Citus analogue of a "broadcast"/dimension table.
*In NexusPlatform:* Phase 0.P — `tenants` is a reference table joined against the distributed `events`.

### colocation
Two distributed tables sharded on the **same key with the same shard count** are *colocated* — their matching shards live on the same worker, so joins on the distribution key are **worker-local** (no cross-node repartition). Created with `colocate_with => '<table>'`.
*In NexusPlatform:* Phase 0.P — `event_tags` is colocated with `events` on `tenant_id`; the colocated join executes worker-locally (proven in `smoke-0.P.ps1`).

### Redis Cluster
**Sharded in-memory key-value store**. Sub-millisecond latency for caching, rate limiting, pub/sub. The cluster mode shards keys across multiple shards with replicas per shard.
*In NexusPlatform:* 3 shards × 2 replicas. Powers the `localmind` RAG cache and `tenantcore` session store.

### MinIO
A high-performance, **S3-compatible object store** written in Go (single binary). In *distributed* mode it spreads objects across a set of drives/nodes with **erasure coding** (Reed–Solomon) — data is split into data + parity shards so the cluster survives drive/node loss without replication's full-copy overhead. It is the lakehouse's storage layer: Iceberg table data, Spark event logs, and StarRocks shared-data storage volumes all live in MinIO buckets.
*In NexusPlatform:* Phase 0.L.1 — a **4-node distributed erasure-coded** cluster (`minio-1..4`, each with a dedicated xfs data drive, default EC:2 → tolerates one node read-write / two nodes read-only). Inter-node erasure/heal traffic rides the VMnet10 backplane; clients reach it via round-robin DNS `minio.nexus.lab:9000` with no VIP (every node is an equal entry point — [ADR-0033](adr/ADR-0033-minio-distributed-erasure-coded-object-storage.md)). mTLS via per-host Vault PKI; the warehouse/spark-events/lakehouse buckets + a least-priv `nexus-lakehouse-app` service account are provisioned at bootstrap.

### ClickHouse
A **columnar OLAP database**. Built for scanning billions of rows quickly with aggregations and analytical queries. Not for OLTP, not for join-heavy workloads, but staggeringly fast for analytical scans. Scales horizontally by **sharding** (split data across nodes) and tolerates failure by **replication** (copy each shard to ≥2 nodes).
*In NexusPlatform:* Phase 0.G.5 — a genuine **3 shards × 2 replicas** cluster (6 data nodes) coordinated by a 3-node ClickHouse Keeper quorum. Powers the analytics half of `dataflow-studio`, `chronosight` time-series queries, `pulsenlp` token analytics, and `streamcore` aggregates.

### ClickHouse Keeper
A **Raft-based coordination service** ClickHouse ships as a C++ replacement for Apache ZooKeeper. It speaks the ZooKeeper wire protocol (so `clickhouse-server` config is unchanged) but uses ClickHouse's own RAFT implementation — no JVM, lower memory, vendor-recommended for all new clusters. It holds the replication log, replica registry, and `ON CLUSTER` DDL coordination state.
*In NexusPlatform:* a **dedicated 3-node Keeper RAFT quorum** (`ch-keeper-1/2/3`) coordinates the 6 ClickHouse data nodes (Phase 0.G.5, [ADR-0028](adr/ADR-0028-clickhouse-keeper-not-zookeeper.md)). The lab runs **zero ZooKeeper VMs** anywhere — the same "drop the legacy JVM coordinator" call Kafka made with KRaft.

### ReplicatedMergeTree
ClickHouse's **replicated table engine family**. A `ReplicatedMergeTree` table's data is automatically copied to every replica of its shard, coordinated through Keeper — insert on one replica, read it from another. The `Replicated*` prefix is what turns a single-node MergeTree table into a fault-tolerant replicated one.
*In NexusPlatform:* every analytics local table is a `ReplicatedMergeTree`; the per-node `{shard}`/`{replica}` macros let one `CREATE TABLE ... ON CLUSTER` statement give each node the right identity (Phase 0.G.5, [ADR-0029](adr/ADR-0029-clickhouse-shard-replica-topology.md)).

### Distributed (ClickHouse table engine)
ClickHouse's **sharding front for queries**. A `Distributed` table holds no data itself; it fans a query/insert out across the shards listed in `remote_servers` (scatter), merges the partial results (gather), and presents them as one table. Clients read/write the `Distributed` table from any node.
*In NexusPlatform:* the `nexus_analytics` cluster (3 shards × 2 replicas) is fronted by `Distributed` tables; `internal_replication=true` lets each shard's `ReplicatedMergeTree` (not the Distributed table) handle the replica copy, the correct anti-double-write setting.

### Shard / Replica
**Shard** = a horizontal slice of a dataset living on a distinct node (more shards = more storage + more parallel scan). **Replica** = a redundant copy of a shard on another node (lose a node, the shard stays available). Sharding is about *scale*; replication is about *availability* — orthogonal, and a "no toy database" cluster has both.
*In NexusPlatform:* every clustered store proves both axes in its smoke gate — Redis (3 shards × 2 replicas), ClickHouse (3 shards × 2 replicas), Kafka (partitions × RF=3), StarRocks (tablets × `replication_num=3`). Pure replication (no sharding) is called out as such — Mongo RS, Percona/Galera, Patroni — with sharding for those engines added later as dedicated phases (0.N Mongo, 0.O Vitess, 0.P Citus).

### StarRocks
A **real-time analytical (MPP) database** with a separated **frontend (FE)** + **backend (BE)** architecture and a MySQL-compatible wire protocol. Joins-friendly OLAP — bridges the gap between OLTP and ClickHouse-style scans; strong at high-concurrency BI and real-time updates.
*In NexusPlatform:* Phase 0.G.6 — a genuine **3 FE (BDB-JE quorum) + 3 BE** cluster; tables `DISTRIBUTED BY HASH(...) BUCKETS n` with `replication_num=3` so tablets are sharded + replicated across all 3 BE. Powers `dataflow-studio`'s interactive BI layer, `chronosight` forecast serving, and `fieldsync` analytics ([ADR-0030](adr/ADR-0030-starrocks-fe-quorum-be-tablet-sharding.md)).

### FE / BE (StarRocks Frontend / Backend)
**FE (Frontend)** = StarRocks's Java metadata + query-coordination plane. FE nodes form a replicated quorum via embedded Berkeley DB Java Edition (BDB-JE), electing one **Leader** (owns metadata writes/DDL) with the rest as **Followers** (replicate metadata, serve reads, forward DDL). **BE (Backend)** = the C++ storage + compute plane that holds tablets and does the actual scan/aggregate/join work; the FE Leader schedules tablet placement and re-replicates on BE loss.
*In NexusPlatform:* 1 Leader + 2 Followers (majority quorum, survives one FE loss + re-elects) + 3 BE; clients connect to any FE via round-robin DNS `starrocks-fe.nexus.lab` on MySQL `:9030` (Phase 0.G.6).

### Tablet (StarRocks)
The **unit of data sharding + replication in StarRocks**. A table is hash-distributed into `BUCKETS n` tablets; each tablet is copied `replication_num` times across the BE nodes. Tablets are what the FE scheduler places, balances, and re-replicates — the StarRocks analogue of a ClickHouse shard-replica or a Kafka partition-replica.
*In NexusPlatform:* demo + showcase tables use `BUCKETS ≥ 3` × `replication_num = 3` so every BE holds tablets and no single BE loss makes any tablet unavailable; the smoke gate proves tablet distribution across all 3 BE via `SHOW TABLET`.

### Shared-data mode (StarRocks `run_mode=shared_data`)
StarRocks's **storage-compute-separation** deployment model (3.x). The FE still holds metadata (BDB-JE quorum, no change), but tablets are no longer replicated across local BE disks — instead, each cloud-native table's data lives in a **storage volume** (an S3-compatible object store) and the data plane is one or more stateless **Compute Nodes (CN)**. Durability comes from the object store's own EC/replication; HA comes from "any CN can serve any query from shared storage". The opposite is `run_mode=shared_nothing` (the classic FE+BE topology where tablets × `replication_num` deliver HA at the StarRocks layer). The two modes are mutually exclusive within a cluster — you choose one at cluster creation and cannot mix.
*In NexusPlatform:* Phase 0.L.5 (ADR-0037) deploys a SECOND StarRocks cluster in shared-data mode (3 FE + 2 CN), parallel to the sealed shared-nothing 0.G.6 cluster. Internal cloud-native tables land in a MinIO storage volume `s3://starrocks/`. The headline HA property — any CN serves from shared storage — is exercised by `smoke-0.L.5.ps1` running CN-loss chaos by default.

### Compute Node (StarRocks CN)
The **stateless data-plane node** in a StarRocks shared-data cluster. Same binary as the BE (`/opt/starrocks/be/`) but started via `start_cn.sh` with `cn.conf` instead of `start_be.sh`/`be.conf`, and added to the cluster via `ALTER SYSTEM ADD COMPUTE NODE "host:9050"` (vs. `ADD BACKEND` for a BE). A CN holds no durable data; it executes scan/agg/join against a storage volume + a local datacache (`storage_root_path` is cache + spill only). Losing a CN does NOT lose data — any peer CN serves the same shared storage.
*In NexusPlatform:* sr-sd-cn-1/2 (`.30`/`.40`); the smoke proves CN-loss tolerance by killing one CN and re-running the query.

### Storage volume (StarRocks)
A **named pointer to an object-storage location** that holds cloud-native table data. Created via SQL `CREATE STORAGE VOLUME <name> TYPE = S3 LOCATIONS = ('s3://bucket/path/') PROPERTIES(...)`; one is designated the default (`SET <name> AS DEFAULT STORAGE VOLUME`) and subsequent `CREATE TABLE` statements without an explicit `STORAGE VOLUME` clause land there. Each storage volume's PROPERTIES carry the S3 endpoint + credentials, so you can move data to a different bucket / different object store without rebaking the FE — `fe.conf` deliberately does not hold S3 secrets.
*In NexusPlatform:* `nexus_minio_starrocks` → `s3://starrocks/` on the MinIO 4-node EC cluster, scoped to the `nexus-starrocks-app` MinIO service account with the `starrocks-tenant` policy (s3:* on the starrocks bucket only; no cross-bucket access, proven negatively in the tenant-bootstrap exit gate).

### MinIO
**S3-compatible object store**, self-hosted. Same API as Amazon S3, so any S3 client works against it unchanged.
*In NexusPlatform:* backs Iceberg tables in `lakehouse-core` plus general object storage for Spark, Backstage, and demo recordings.

### Apache Iceberg
A **table format for data lakes**. Lets you treat a directory of Parquet files in S3/MinIO as if it were a SQL table — with schema evolution, time-travel, and ACID semantics over object storage. The basis of the modern "lakehouse" architecture.
*In NexusPlatform:* bronze/silver/gold layers in `lakehouse-core`, queryable from Spark, Trino, and dbt.
*Common alternatives:* Delta Lake (Databricks-flavored), Apache Hudi.

### Iceberg REST catalog
The **catalog** is the service that maps a table name (`db.table`) to its current Iceberg metadata pointer in object storage — engines ask the catalog "where is this table now?" before reading/writing. The **REST catalog** is the standardized HTTP protocol for that lookup (Iceberg's `/v1/config`, `/v1/namespaces`, …), so any engine (Spark, StarRocks, Trino) talks to one catalog the same way. The catalog needs a durable metadata store behind it (a SQL DB), which is the thing that must be made HA.

### Project Nessie
An **Iceberg REST catalog implementation** (Quarkus/Java) with a Git-like data model — namespaces and table pointers live on **branches** you can commit, tag, and merge, giving the warehouse version control + cross-table transactions. Pluggable "version store"; the JDBC store keeps state in PostgreSQL.
*In NexusPlatform:* the `08-spark` catalog (0.L.2) — two stateless Nessie instances behind round-robin DNS (`iceberg.nexus.lab`), `JDBC2` version store on a dedicated PostgreSQL master-replica HA pair (keepalived VRRP VIP `iceberg-db.nexus.lab`), warehouse data in MinIO (ADR-0034).
*Common alternatives:* the Tabular/`iceberg-rest-fixture` reference image (non-HA demo), Lakekeeper (Rust), AWS Glue / Polaris.

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
- **Kafka ACLs / StandardAuthorizer** — Kafka's authorization layer. The KRaft-native `StandardAuthorizer` checks every request against per-principal Allow/Deny rules (managed with `kafka-acls`); with `allow.everyone.if.no.acl.found=false` it is **deny-by-default**, and `super.users` is the bypass list. A "principal" here is the mTLS client certificate's identity (`User:CN=<host>.kafka.nexus.lab`). *In NexusPlatform:* enabled at Phase 0.H.7 (so the `nexus acl` verb enforces) with `super.users` = all 15 tier principals — the brokers (inter-broker + controller quorum) **and** the ecosystem services (Schema Registry, REST, Connect, ksqlDB, MirrorMaker 2), which are all Kafka clients — leaving ordinary application principals deny-by-default.

*In NexusPlatform:* two 3-node KRaft clusters (East primary + West DR) with a MirrorMaker 2 pair between them; Schema Registry HA pair for governance; a REST Proxy for HTTP-only clients; Connect + Debezium streams Postgres + SQL Server changes into Kafka; ksqlDB powers real-time aggregations. Stood up as Phase 0.H (`nexus-infra-kafka`, 15 VMs, every node holding a per-node Vault-PKI keystore and talking to the brokers over mutual TLS); `streamcore` later exercises the whole stack as a portfolio demo. The `nexus-cli` `kafka-east`/`kafka-west`/`kafka-ecosystem` adapters (v0.6.7) drive the whole tier.

---

## 6. Analytics & data platform

### Apache Spark
A **distributed compute engine** for large-scale batch and streaming data processing. Originally a Hadoop replacement, now the standard for large-scale ETL pipelines and ML feature engineering. Programs in Scala, Python (PySpark), or SQL.
*In NexusPlatform:* the `08-spark` tier (0.L.3) runs Spark **standalone in HA** — **2 masters (active/standby, ZooKeeper-elected) + 3 workers** — writing Iceberg tables through the Nessie REST catalog into the MinIO warehouse (S3A). The master HA election lives in a dedicated ZooKeeper ensemble (`recoveryMode=ZOOKEEPER`); cluster RPC is authenticated + AES-encrypted with a Vault-seeded shared secret (ADR-0035). Also serves offline ML feature builds for `sentinelml` and `pulsenlp`.
- **standalone mode** — Spark's built-in cluster manager (a master scheduling apps onto workers), as opposed to running Spark on YARN or Kubernetes. The master is the control plane, so HA needs ≥2 masters + a coordination quorum.

### Apache ZooKeeper
A **distributed coordination service** — a small, strongly-consistent hierarchical key-value store (znodes) with leader election, used by older distributed systems to agree on "who is the leader" and to store cluster metadata. Runs as an odd-sized ensemble (3/5 nodes) for quorum fault-tolerance.
*In NexusPlatform:* the **one deliberate Apache-ZooKeeper exception** — a single 3-node ensemble on the `08-spark` backplane that coordinates Spark standalone master HA (0.L.3, ADR-0035). The platform otherwise runs **zero** ZooKeeper: Kafka uses **KRaft** and ClickHouse uses **Keeper** (a ZK-protocol-compatible C++ reimplementation). ZooKeeper was chosen here only because it is Spark standalone's sole mainstream-tested HA mechanism.

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
*In NexusPlatform:* every .NET and Python app is instrumented with OTel. Apps push OTLP to the **OTel Collector pair** (`otel.nexus.lab` round-robin DNS over `.182`/`.183`, Phase 0.I.5), which fans out traces → Tempo, metrics → Prometheus remote-write, logs → Loki. The collector pair is the single egress point for app telemetry; round-robin DNS per ADR-0031 (write paths retry).

### OTel Collector
The **vendor-neutral routing daemon** in the OpenTelemetry project. Accepts OTLP (gRPC `:4317` / HTTP `:4318`) and exports to multiple backends (Tempo, Prom, Loki, Jaeger, etc.) via pipelines configured in YAML.
*In NexusPlatform:* runs as the `otel-collector-1/2` HA pair (Phase 0.I.5); the only direct OTLP recipient for the app fleet. Per ADR-0038 it routes traces → Tempo, metrics → Prom remote-write, logs → Loki.

### Prometheus
A **pull-based metrics database**. Periodically scrapes HTTP `/metrics` endpoints from your services, stores time-series, and exposes a query language (PromQL) for dashboards and alerts.
*In NexusPlatform:* deployed as a **2-VM HA pair** `prom-1/2` (Phase 0.I.1, ADR-0038) — each Prometheus independently scrapes every fleet target (node_exporter on every Linux VM + windows_exporter on ws2025 desktops + per-engine exporters); Grafana's Prometheus datasource dedupes on the read side. No long-term storage in v0.1.0 — retention bounded by local disk. Adding Grafana Mimir on MinIO is a tracked future enhancement.

### Grafana
A **dashboard UI for time-series data**. Connects to many sources (Prometheus, ClickHouse, PostgreSQL, …), renders charts, alerts on PromQL/SQL conditions.
*In NexusPlatform:* deployed as a **2-VM active-active HA pair** behind a **VRRP VIP** `grafana.nexus.lab` `.184` (Phase 0.I.4, ADR-0038 + ADR-0025). Shared state lives in a dedicated `grafana-pg` Postgres HA pair (master-replica + keepalived VIP `.185`, mirroring the 0.L.2 iceberg-db / 0.L.4 registry-db pattern). Pre-provisioned datasources: Prometheus HA, Loki, Tempo. Operators bookmark one URL — atomic sub-second failover on either node loss.

### Loki
**Grafana's log aggregation backend.** Designed like Prometheus but for log lines — indexes labels (`{host="kafka-east-1", service="kafka"}`), stores log bodies on object storage, queries via LogQL. JSON-line logs get structured filtering via `| json | OrderId="42"`.
*In NexusPlatform:* deployed in **simple-scalable mode** across **3 VMs** `loki-1/2/3` (Phase 0.I.2, ADR-0038) — each node runs all components (read + write + backend) in a memberlist gossip ring; durable storage in MinIO `bucket=loki` via the dedicated `nexus-loki-app` tenant (scoped policy). C# devs push via `Serilog.Sinks.Grafana.Loki`; Python devs via `python-logging-loki` or OTel logs SDK; infra logs via Vector tailing journald + `/var/log/*`.

### Tempo
**Grafana's distributed-tracing backend.** OTLP/Jaeger/Zipkin protocols accepted; trace data stored on object storage; correlation links to Loki logs and Prometheus metrics in Grafana.
*In NexusPlatform:* deployed in **single-binary scalable mode** across **3 VMs** `tempo-1/2/3` (Phase 0.I.3, ADR-0038) — each node runs all components (distributor + ingester + querier + query-frontend + compactor) in a memberlist ring; durable storage in MinIO `bucket=tempo` via the dedicated `nexus-tempo-app` tenant. OTLP receivers on `:4317`/`:4318` accept traces from the OTel Collector pair.

### Alertmanager
Part of the Prometheus stack. **Routes Prometheus-fired alerts** to channels (Slack, email, PagerDuty), with grouping, silencing, and de-duplication.
*In NexusPlatform:* deployed as a **2-node gossip mesh co-resident on the Prom HA pair** `prom-1/2` (Phase 0.I.1, ADR-0038). Both Proms fire to both Alertmanagers; the mesh dedupes. Routes lab alerts to a single channel — production-shape but lab-scale.

### Vector
A **lightweight Rust log-shipping daemon** (similar role to Fluent Bit / Logstash but faster and smaller). Tails files + journald + Windows event log, structures into JSON, ships to a backend (Loki, Elasticsearch, S3, etc.) with batching and retries.
*In NexusPlatform:* baked into the deb13 baseline + every per-engine template (Phase 0.I.6 fleet-wide rollout). Default config tails journald + `/var/log/syslog` + `/var/log/auth.log` + engine-specific log files; pushes JSON to `https://loki.nexus.lab:3100/loki/api/v1/push`. ws2025 desktops use `winlogbeat` → Vector relay on the obs tier.

### node_exporter / windows_exporter
**Host-level Prometheus exporters** — `node_exporter` for Linux (CPU/RAM/disk/network/systemd unit state) and `windows_exporter` for Windows (Perfmon counters, services, Windows events).
*In NexusPlatform:* `node_exporter` on every Linux VM (port `:9100`) and `windows_exporter` on every ws2025 desktop (port `:9182`); both Proms scrape them by service-discovery file generated from `vms.yaml` consumer list. Engine-specific exporters (kafka-exporter, postgres-exporter, redis-exporter, mongodb-exporter, mysqld-exporter, etc.) sit alongside on the same VMs where canonical.

### Jaeger
A **distributed-tracing UI**. Visualizes a single request as it propagates through multiple services, with timing per hop. Click a slow request → see exactly where the time went.
*In NexusPlatform:* **NOT deployed.** The original obs tier draft listed Jaeger; ADR-0038 (Phase 0.I, 2026-05-26) replaced it with **Tempo** (above) — same OTLP protocol, Grafana-native UI, single-pane-of-glass with metrics + logs.

### Seq
A **structured-log search UI**, .NET-flavored. Like Splunk but lightweight and free for single-user deployments.
*In NexusPlatform:* **NOT deployed.** The original obs tier draft listed Seq for .NET-friendly structured logs; ADR-0038 (Phase 0.I, 2026-05-26) replaced it with **Loki** (above) for two reasons: (1) Seq Free Edition is single-node only — no FOSS HA without paid Seq cluster, which would violate ADR-0025; (2) C# / Python equal-class treatment via OTel logs + Serilog's Loki sink. The Serilog property model is preserved in Loki via JSON-line labels — querying via `| json | OrderId="123"` is the LogQL equivalent of Seq's native property syntax.

### VictoriaMetrics
A **long-term metrics storage backend** that's wire-compatible with Prometheus but more efficient for retention beyond a few weeks.
*In NexusPlatform:* **NOT deployed.** The original obs tier draft listed VictoriaMetrics; ADR-0038 (Phase 0.I, 2026-05-26) chose plain **Prometheus HA pair** instead. Adding Grafana Mimir on MinIO for long-term metrics retention is a tracked future enhancement (post-Phase-0).

---

## 8. Platform & supply chain

### Harbor
A **self-hosted container registry**. Replaces Docker Hub for private + air-gapped use. Built-in vulnerability scanning, image signing, replication, RBAC, and OIDC SSO.
*In NexusPlatform:* every Docker image built by CI is pushed to **`registry.nexus.lab`** — a **highly-available** Harbor (Phase 0.L.4, tier `09-platform`, ADR-0036): 2 stateless app nodes behind round-robin DNS, backed by a dedicated PostgreSQL + Redis master-replica HA pair (keepalived VRRP VIP), with **image layers stored in MinIO S3** (the 0.L.1 object store), Trivy scanning, cosign signing, and **Vault OIDC** single sign-on. Deployed via Harbor's official docker-compose installer.

### Trivy
A **vulnerability scanner** for container images and binaries. Reads an image's contents, looks up known CVEs in distro packages and language packages.
*In NexusPlatform:* runs as a Harbor component (`--with-trivy`) and scans on every image push; CI fails if HIGH or CRITICAL vulnerabilities appear.

### cosign (Sigstore)
A tool for **signing and verifying container images**. Cryptographic provenance answering "did *we* build this image, or was it replaced?"
*In NexusPlatform:* every CI-built image is cosign-signed and Harbor surfaces the signature; deployments verify signatures before pulling (the 0.L.4 exit gate signs + verifies a pushed image).

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
*In NexusPlatform:* `gmsa-sql-engine$` at Phase 0.G.7 — first real GMSA consumer (0.D.5 scaffolded the infrastructure). SQL Server service identity on the **2 FCI nodes** (a cluster-shared identity is what an FCI needs); the standalone AG replicas run as `NT AUTHORITY\NETWORK SERVICE` (AG endpoints authenticate via certificate per ADR-0027, so a gmsa there buys nothing). Only the FCI computer accounts are in `nexus-sql-cluster-members` (PrincipalsAllowedToRetrieveManagedPassword). Per `memory/feedback_kds_rootkey_server2025_ssh.md`, KDS root key must be added via RDP on Server 2025 (broken over SSH).

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
