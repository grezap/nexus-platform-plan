# ADR Index

Architecture Decision Records across the portfolio. Shared ADRs (0001–0010) are owned by `nexus-platform-plan`; per-project ADRs live in each project repo under `docs/adr/` and are listed here for traceability.

**Lifecycle:** `planned` → `proposed` → `accepted` | `deprecated` | `superseded`.

## Shared ADRs (owner: nexus-platform-plan)

| ID | Title | Status | Added |
|---|---|---|---|
| 0001 | Migration tool choice — FluentMigrator (OLTP) + DbUp (analytical) | planned | 2026-04-20 |
| 0002 | Native AOT + EF Core resolution — Dapper on AOT paths, EF Core on non-AOT | planned | 2026-04-20 |
| 0003 | VMware provider — vmware/vmware-desktop + vmrun fallback | planned | 2026-04-20 |
| 0004 | Workflow orchestrator — Prefect 3 over Dagster/Airflow | planned | 2026-04-20 |
| 0005 | Lakehouse table format — Iceberg over Delta Lake | planned | 2026-04-20 |
| 0006 | Event serialization — Avro for pipelines, Protobuf for gRPC | planned | 2026-04-20 |
| 0007 | Testing stack — xUnit + Testcontainers + PactNet + NetArchTest + Stryker.NET | planned | 2026-04-20 |
| 0008 | Roslyn analyzer package — Nexus.Analyzers enforces modern .NET idioms | planned | 2026-04-20 |
| 0009 | Result pattern library — ErrorOr vs. OneOf | proposed | 2026-04-20 |
| 0010 | Python toolchain — uv + Ruff + mypy --strict + Pydantic v2 + Polars | planned | 2026-04-20 |
| 0011 | [3-node Vault Raft cluster on the foundation tier](./ADR-0011-vault-3-node-raft.md) | accepted | 2026-04-30 |
| 0012 | [Vault PKI hierarchy (root + intermediate) for lab-internal TLS](./ADR-0012-vault-pki-hierarchy.md) | accepted | 2026-05-01 |
| 0013 | [LDAPS to AD via search-then-bind without `upndomain`; `secrets/ldap` over deprecated `ad`](./ADR-0013-vault-ldaps-search-then-bind.md) | accepted | 2026-05-01 |
| 0014 | [Foundation env reads bootstrap creds from Vault KV via AppRole-authenticated `vault_kv_secret_v2` data sources](./ADR-0014-foundation-creds-via-approle-kv.md) | accepted | 2026-05-01 |
| 0015 | [Phase 0.D.5: Transit auto-unseal + Vault Agent on member servers + leaf TTL drop + GMSA scaffolding + bootstrap-creds rotation](./ADR-0015-transit-auto-unseal-and-agent.md) | accepted | 2026-05-03 |
| 0016 | [Phase 0.E.3.3b: Nomad-Vault integration via legacy periodic-token role (vs. Workload Identity)](./ADR-0016-nomad-vault-legacy-periodic-token.md) | accepted | 2026-05-06 |
| 0017 | [Phase 0.E.4: Portainer CE single-replica + NFS-via-gateway state continuity](./ADR-0017-portainer-ce-nfs-via-gateway.md) | accepted | 2026-05-07 |
| 0018 | [Phase 0.E.4d: nftables `flush ruleset` + Docker iptables-nft conflict resolution](./ADR-0018-nftables-flush-ruleset-docker-conflict.md) | accepted | 2026-05-07 |
| 0019 | [Phase 0.E.4e: TLS full-chain on the wire + `inet filter forward` accept rules](./ADR-0019-tls-fullchain-on-wire.md) | accepted | 2026-05-08 |
| 0020 | [Phase 0.H.1: KRaft combined broker+controller mode for the Kafka tier](./ADR-0020-kraft-combined-mode.md) | accepted | 2026-05-15 |
| 0021 | [Phase 0.H.2-0.H.5: Kafka-tier mTLS — Vault PKI PEM keystores, PKCS#1→PKCS#8, and the Confluent PEM/PKCS#12 listener split](./ADR-0021-kafka-tier-mtls-pem-pkcs12.md) | accepted | 2026-05-15 |
| 0022 | [Phase 0.H.3-0.H.4: Terraform overlay ordering via `depends_on`, never upstream resource `.id` triggers](./ADR-0022-terraform-overlay-depends-on-not-id-triggers.md) | accepted | 2026-05-15 |
| 0023 | [Phase 0.H.5: MirrorMaker 2 dedicated mode, one replication flow per node](./ADR-0023-mirrormaker2-dedicated-mode-one-flow-per-node.md) | accepted | 2026-05-15 |
| 0024 | [Phase 0.G.0: AOT exit gate raised to ≤30 MB; cluster-adapter framework for the data-tier verb expansion](./ADR-0024-aot-gate-amendment-and-cluster-adapter-framework.md) | accepted | 2026-05-15 |
| 0025 | [Phase 0.G.4: HA promise covers the load-balancer tier; LB SPOFs are first-class regressions](./ADR-0025-ha-promise-covers-lb-tier.md) | accepted | 2026-05-19 |
| 0026 | [Phase 0.G.7: SQL FCI shared storage — iSCSI target on nexus-gateway](./ADR-0026-sql-fci-iscsi-shared-storage.md) | accepted | 2026-05-20 |
| 0027 | [Phase 0.G.7: SQL AG endpoint authentication — certificate-based](./ADR-0027-sql-ag-endpoint-cert-auth.md) | accepted | 2026-05-20 |
| 0028 | [Phase 0.G.5: ClickHouse Keeper, not ZooKeeper, for replication coordination](./ADR-0028-clickhouse-keeper-not-zookeeper.md) | accepted | 2026-05-22 |
| 0029 | [Phase 0.G.5: ClickHouse topology — 3 shards × 2 replicas, Distributed over ReplicatedMergeTree](./ADR-0029-clickhouse-shard-replica-topology.md) | accepted | 2026-05-22 |
| 0030 | [Phase 0.G.6: StarRocks topology — FE quorum (BDB-JE) + BE tablet sharding/replication](./ADR-0030-starrocks-fe-quorum-be-tablet-sharding.md) | accepted | 2026-05-22 |
| 0031 | [Phase 0.G.5/0.G.6: Analytics client front door — round-robin DNS, no VRRP VIP (resolves ADR-0025's analytics open questions)](./ADR-0031-analytics-client-front-door-round-robin-dns.md) | accepted | 2026-05-22 |
| 0032 | [Phase 0.G.5/0.G.6: Analytics backup repository — NFS export from nexus-gateway (MinIO deferred to 0.L)](./ADR-0032-analytics-backup-repository-nfs-gateway.md) | accepted | 2026-05-22 |
| 0144 | [Windows licensing posture — MSDN primary, Evaluation fallback](./ADR-0144-windows-licensing.md) | accepted | 2026-04-22 |

## Per-project ADRs

Each project ships a minimum of 5 ADRs (architecture pattern, primary store, async communications, deployment topology, domain/ML choice) per Vol11 §5 minimum. Additional ADRs may be added by the project repo as design decisions arise. Prefixes are project-specific.

### DFS — dataflow-studio

| ID | Title | Status | Added |
|---|---|---|---|
| DFS-0001 | Modular Monolith over Microservices for DataFlow Studio | planned | 2026-04-20 |
| DFS-0002 | SQL Server AG as source + StarRocks (BI) + ClickHouse (real-time) | planned | 2026-04-20 |
| DFS-0003 | Kafka CDC via Debezium with Avro + Schema Registry | planned | 2026-04-20 |
| DFS-0004 | Swarm stack for v0.1; K8s manifests shipped but not primary | planned | 2026-04-20 |
| DFS-0005 | Kimball SCD2 in StarRocks via dbt snapshots | planned | 2026-04-20 |

### TC — tenantcore

| ID | Title | Status | Added |
|---|---|---|---|
| TC-0001 | Clean Architecture for tenantcore | planned | 2026-04-20 |
| TC-0002 | Percona PXC + ProxySQL for multi-tenant isolation | planned | 2026-04-20 |
| TC-0003 | Kafka for tenant lifecycle events, no sync fan-out | planned | 2026-04-20 |
| TC-0004 | Swarm rolling deploy with Vault dynamic MySQL creds | planned | 2026-04-20 |
| TC-0005 | Per-tenant schema strategy over shared-schema with discriminator | planned | 2026-04-20 |

### SML — sentinelml

| ID | Title | Status | Added |
|---|---|---|---|
| SML-0001 | Vertical Slice pattern over Clean Architecture | planned | 2026-04-20 |
| SML-0002 | PostgreSQL Patroni for feature store + ClickHouse for events | planned | 2026-04-20 |
| SML-0003 | ksqlDB for stream enrichment, consumer groups for inference | planned | 2026-04-20 |
| SML-0004 | Nomad batch jobs for retrain; Prefect for orchestration | planned | 2026-04-20 |
| SML-0005 | ONNX Runtime for inference with PSI drift monitoring | planned | 2026-04-20 |

### LM — localmind

| ID | Title | Status | Added |
|---|---|---|---|
| LM-0001 | Clean Architecture with Named Pipes Windows service variant | planned | 2026-04-20 |
| LM-0002 | MongoDB for chat state + pgvector for embeddings | planned | 2026-04-20 |
| LM-0003 | SSE (not WebSockets) for streaming chat responses | planned | 2026-04-20 |
| LM-0004 | Ollama as local LLM runtime with gateway-level routing | planned | 2026-04-20 |
| LM-0005 | RAG mandatory in v0.1 (not post-v0.1 enhancement) | planned | 2026-04-20 |

### PN — pulsenlp

| ID | Title | Status | Added |
|---|---|---|---|
| PN-0001 | Vertical Slice for pulsenlp feature handlers | planned | 2026-04-20 |
| PN-0002 | PostgreSQL metadata + ClickHouse token analytics | planned | 2026-04-20 |
| PN-0003 | Kafka for ingestion, back-pressure via consumer group scaling | planned | 2026-04-20 |
| PN-0004 | Swarm service deployment; no K8s in v0.1 | planned | 2026-04-20 |
| PN-0005 | ML.NET + DistilBERT + BERT NER via ONNX, no Python in prod path | planned | 2026-04-20 |

### VC — visioncore

| ID | Title | Status | Added |
|---|---|---|---|
| VC-0001 | Clean Architecture for visioncore | planned | 2026-04-20 |
| VC-0002 | MongoDB document store + MinIO for image artifacts | planned | 2026-04-20 |
| VC-0003 | Synchronous REST inference; no streaming | planned | 2026-04-20 |
| VC-0004 | Swarm deployment with CPU-first, GPU-probe fallback | planned | 2026-04-20 |
| VC-0005 | PyTorch training → ONNX export; C# inference via ImageSharp | planned | 2026-04-20 |

### RE — recoengine

| ID | Title | Status | Added |
|---|---|---|---|
| RE-0001 | Modular Monolith with GlobalKTable co-processor | planned | 2026-04-20 |
| RE-0002 | Percona PXC primary; Redis for hot Top-N cache | planned | 2026-04-20 |
| RE-0003 | Kafka Streams via Streamiz for real-time affinity updates | planned | 2026-04-20 |
| RE-0004 | Unleash for A/B variants; OpenFeature SDK | planned | 2026-04-20 |
| RE-0005 | ML.NET MatrixFactorization over ALS external library | planned | 2026-04-20 |

### CS — chronosight

| ID | Title | Status | Added |
|---|---|---|---|
| CS-0001 | Vertical Slice for chronosight forecasting features | planned | 2026-04-20 |
| CS-0002 | ClickHouse raw/bars + StarRocks for serving forecasts | planned | 2026-04-20 |
| CS-0003 | ksqlDB for OHLCV aggregation in-stream | planned | 2026-04-20 |
| CS-0004 | Prefect schedules forecaster; Spark for training | planned | 2026-04-20 |
| CS-0005 | Prophet + Chronos-Bolt over LSTM/Transformer baselines | planned | 2026-04-20 |

### QL — querylens

| ID | Title | Status | Added |
|---|---|---|---|
| QL-0001 | Vertical Slice with Event Sourcing on the regression audit trail | planned | 2026-04-20 |
| QL-0002 | SQL Server DMVs as primary source; PG Event Store | planned | 2026-04-20 |
| QL-0003 | Polling over Extended Events for portability | planned | 2026-04-20 |
| QL-0004 | Swarm deployment; no K8s in v0.1 | planned | 2026-04-20 |
| QL-0005 | LocalMind integration for rewrite suggestions | planned | 2026-04-20 |

### FS — fieldsync

| ID | Title | Status | Added |
|---|---|---|---|
| FS-0001 | Clean Architecture for fieldsync server and client | planned | 2026-04-20 |
| FS-0002 | MongoDB server store + SQLite device store | planned | 2026-04-20 |
| FS-0003 | gRPC bidirectional streams for sync | planned | 2026-04-20 |
| FS-0004 | MAUI multi-target (Android + Windows) | planned | 2026-04-20 |
| FS-0005 | On-device ONNX for OCR; no server round-trip | planned | 2026-04-20 |

### NP — nexus-platform

| ID | Title | Status | Added |
|---|---|---|---|
| NP-0001 | Microservices with 6 bounded contexts | planned | 2026-04-20 |
| NP-0002 | Per-service database (SQL Server, Mongo, Percona mix) | planned | 2026-04-20 |
| NP-0003 | Choreography via Kafka + Orchestration sagas where needed | planned | 2026-04-20 |
| NP-0004 | Kubernetes as primary deploy target; Helm charts per service | planned | 2026-04-20 |
| NP-0005 | Gateway with YARP; PactNet contract tests as CI gate | planned | 2026-04-20 |

### SC — streamcore

| ID | Title | Status | Added |
|---|---|---|---|
| SC-0001 | Vertical Slice per topology | planned | 2026-04-20 |
| SC-0002 | ClickHouse aggregates + PG Event Store + Redis cache | planned | 2026-04-20 |
| SC-0003 | MM2 for east/west DR, not mirror-maker v1 | planned | 2026-04-20 |
| SC-0004 | Swarm deploy with Pumba chaos sidecar | planned | 2026-04-20 |
| SC-0005 | Streamiz over Confluent.Kafka raw for topology authoring | planned | 2026-04-20 |

### ND — nexus-desk

| ID | Title | Status | Added |
|---|---|---|---|
| ND-0001 | Monorepo housing 4 Windows apps | planned | 2026-04-20 |
| ND-0002 | Local SQLite per app for UI state | planned | 2026-04-20 |
| ND-0003 | gRPC (over Named Pipes) for intra-suite communication | planned | 2026-04-20 |
| ND-0004 | MSIX packaging with code-signing and auto-update | planned | 2026-04-20 |
| ND-0005 | WinForms + WPF + WinUI3 intentional spread to showcase breadth | planned | 2026-04-20 |

### LHC — lakehouse-core

| ID | Title | Status | Added |
|---|---|---|---|
| LHC-0001 | Medallion (Bronze/Silver/Gold) architecture | planned | 2026-04-20 |
| LHC-0002 | Iceberg on MinIO; REST catalog | planned | 2026-04-20 |
| LHC-0003 | Kafka bronze-ingest via Connect → Iceberg sink | planned | 2026-04-20 |
| LHC-0004 | Prefect + Spark on Swarm; dbt Core for transforms | planned | 2026-04-20 |
| LHC-0005 | Trino federation (Iceberg gold + StarRocks live) | planned | 2026-04-20 |
