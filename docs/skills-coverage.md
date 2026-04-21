# Skills Coverage Matrix

Every one of the 14 application projects demonstrates all four portfolio dimensions. This document lists concrete evidence — specific files, patterns, and measurements — per project per dimension.

Legend: **●** primary · **◐** substantial · **○** light

| # | Project | .NET eng + arch | SQL + analytics | Python | DevOps |
|---:|---|:---:|:---:|:---:|:---:|
| 0 | portfolio | ● | ◐ | ○ | ● |
| 1 | dataflow-studio | ● | ● | ◐ | ● |
| 2 | tenantcore | ● | ● | ○ | ◐ |
| 3 | sentinelml | ◐ | ◐ | ● | ● |
| 4 | localmind | ● | ◐ | ◐ | ◐ |
| 5 | pulsenlp | ● | ◐ | ● | ◐ |
| 6 | visioncore | ● | ○ | ● | ◐ |
| 7 | recoengine | ● | ◐ | ◐ | ◐ |
| 8 | chronosight | ◐ | ● | ● | ◐ |
| 9 | querylens | ● | ● | ○ | ● |
| 10 | fieldsync | ● | ◐ | ○ | ◐ |
| 11 | nexus-platform | ● | ◐ | ○ | ● |
| 12 | streamcore | ● | ◐ | ◐ | ● |
| 13 | nexus-desk | ● | ● | ○ | ◐ |
| 14 | lakehouse-core | ◐ | ● | ● | ● |

## Evidence per project

### 0. portfolio
Blazor Server site with interactive SVG architecture diagrams; MudBlazor component library; Docs-as-Code pipeline that ingests the 14 Volume txt files into site pages. SQL shows up in the portfolio's own analytics (page-view aggregation, lightweight CTEs over visitor telemetry). DevOps is first-class: CI renders `dbt docs`, Grafana iframes, Playwright recordings into the Live Tour. Python presence is minimal — a couple of content-conversion helpers.

### 1. dataflow-studio
The reference showcase. .NET 10 Modular Monolith enforced by NetArchTest across `Ingestion`, `Transform`, `Serve`, `Observability` modules. Advanced SQL is the point: SQL Server temporal tables, CDC, FOR JSON PATH outbox, MERGE with OUTPUT for SCD2, ClickHouse AggregatingMergeTree materialized views, StarRocks colocate joins. Python produces the synthetic retail dataset (Bogus for .NET, Faker for Python) and a PySpark bronze-silver conformance job. DevOps exercises FluentMigrator up/down, Docker Swarm stack, K8s manifests, `nexus-cli deploy dataflow-studio`.

### 2. tenantcore
Clean Architecture with per-tenant schema isolation on Percona PXC (ProxySQL routing). ASP.NET Identity, Hangfire background jobs, source-generated Mapperly mappers. SQL demonstrates tenant-scoped MERGE, recursive CTEs for feature inheritance, row-level security via views. Python appears only in load-test data seeding. DevOps shipping: blue/green via Swarm rolling updates, Vault dynamic MySQL creds rotated hourly.

### 3. sentinelml
Vertical Slice .NET pattern (one command per feature, MediatR). Real-time fraud scoring via ONNX Runtime. SQL against PostgreSQL Patroni for feature store reads, ClickHouse for event telemetry, window functions to compute PSI drift over rolling feature distributions. Python is load-bearing: training notebooks, PSI calculation, Spark offline-feature jobs, MLflow model registration. DevOps: Prefect flows emit OpenLineage, Alertmanager routes on model-drift thresholds.

### 4. localmind
Clean Architecture OpenAI-compatible gateway with a Named Pipes Windows service bridge. RAG from v0.1 uses pgvector on PG Patroni and MongoDB for conversation state. SQL work includes pgvector HNSW tuning, Mongo aggregation pipelines for chat history search. Python handles document ingestion chunking and embedding generation (sentence-transformers). DevOps: Ollama model management, health probes, Vault-issued API keys.

### 5. pulsenlp
Vertical Slice. .NET-only inference using ML.NET + DistilBERT + BERT NER all via ONNX — zero Python runtime in production. SQL on PostgreSQL (corpus metadata) + ClickHouse (token-level analytics). Python trains the DistilBERT fine-tune on Spark with Hugging Face, exports to ONNX, runs evaluation harness. DevOps: model-artifact pinning, reproducible training with seeded randomness.

### 6. visioncore
Clean Architecture PyTorch-to-ONNX defect detector. C# inference via ONNX Runtime; image manipulation strictly via ImageSharp (no OpenCV). SQL layer is light — MongoDB document queries. Python is heavy: PyTorch training, dataset augmentation, ONNX export, inference benchmarking. DevOps: GPU detection fallback to CPU, MinIO-backed model artifact storage.

### 7. recoengine
Modular Monolith. ML.NET MatrixFactorization plus a Kafka Streams GlobalKTable co-processor for real-time personalization. SQL on Percona PXC for user-interaction joins, advanced recursive CTEs for category hierarchies. Python runs offline matrix factorization benchmarks and produces evaluation datasets. DevOps: A/B experimentation with Unleash feature flags.

### 8. chronosight
Vertical Slice time-series forecasting. ClickHouse stores ticks; StarRocks serves aggregates; ksqlDB generates 1-minute OHLCV. SQL is the exhibit — AggregatingMergeTree, ASOF JOIN, FINAL semantics, StarRocks colocate joins, Iceberg time-travel queries. Python trains Prophet + Chronos-Bolt forecasters via Prefect. .NET API exposes forecasts via Generic Math-based rolling windows. DevOps: Prefect schedules, forecast-accuracy alerts.

### 9. querylens
Vertical Slice. SQL Server DMV polling, Event Sourcing on PG, change-point detection, AI rewrite suggestions via LocalMind. Core SQL exhibit: plan-hash comparisons, query-store deltas, regression detection CTEs. Python used only to seed synthetic workload. DevOps: Grafana panel for regression trend, Alertmanager hooks to ticket system.

### 10. fieldsync
Clean Architecture MAUI (Android + Windows). gRPC bidirectional streams, offline-first with SQLite local store reconciled against MongoDB server. On-device ONNX OCR. SQL at the server side aggregates submissions into StarRocks. Python absent except for device-simulation harness. DevOps: protobuf schema governance, rolling MAUI updates via app center.

### 11. nexus-platform
Microservices — 6 services (Orders, Payments, Inventory, Notifications, Analytics, Gateway). Choreography + orchestration sagas; full `/k8s` manifests; PactNet contract tests between services. SQL per service DB (SQL Server, Mongo, Percona mix). DevOps is the exhibit: K8s, Helm, Istio sidecars, OPA policies, canary rollouts.

### 12. streamcore
Vertical Slice. Four Kafka Streams topologies in .NET (Streamiz). Live MM2 DR demonstration, Chaos Harness. SQL work in ClickHouse for materialized aggregates, PG for Event Store. Python in the Chaos Harness driver. DevOps-heavy: Pumba chaos injection, `nexus-cli kafka failover`, failover RTO measurements.

### 13. nexus-desk
Monorepo, four Windows apps (WinForms DBA Studio, WPF+Rx trading terminal, WinUI3 AI Assistant, WinUI3+WPF hybrid). Advanced SQL demonstrations via the DBA Studio (deadlock graphs, plan cache analysis, AG dashboards). Python absent. DevOps: MSIX packaging, auto-update channel, code signing.

### 14. lakehouse-core
Medallion architecture (Bronze/Silver/Gold) on Iceberg + MinIO. dbt Core with dbt-starrocks + dbt-clickhouse adapters. PySpark batch jobs, dbt snapshots for SCD2, Trino federation queries. .NET appears as the `nexus-cli lakehouse` operator commands and an Iceberg catalog browser. SQL and Python are both primary dimensions; dbt tests gate the pipeline. DevOps: Prefect orchestration, OpenLineage to Marquez, Iceberg maintenance jobs (compaction, snapshot expiry).
