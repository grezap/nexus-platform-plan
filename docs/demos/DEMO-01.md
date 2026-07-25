# DEMO-01 · Place an order, watch it flow everywhere

> **Status: the `dataflow-studio` spine is SEALED `v0.1.0` (2026-07-25).** The pipeline — OltpDb → CDC →
> Debezium → curated Avro → StarRocks star + ClickHouse telemetry, with all three self-observation planes
> (Tempo, ClickHouse, Marquez) — is complete, tested to the §6 gate, orchestrated (Aspire) and packaged
> (Docker/Swarm/K8s). Still pending for the *full* scenario below: the `nexus-platform` Gateway + Orders
> API + outbox (that project has not started). The original status note follows.
>
> **partially live (2026-07-19).** The `dataflow-studio` spine of this scenario —
> **OltpDb → SQL Server CDC → Debezium → curated Avro → StarRocks Kimball star (SCD2 dims + facts)**,
> **plus the ClickHouse telemetry leg** — is built and runs on the lab today; you can replay all of it
> from zero right now (see §3a). The pipeline now also **observes itself**: per-stage latency,
> end-to-end CDC lag and structured errors reach ClickHouse through **native Kafka-engine ingestion**
> (dataflow-studio Week 3d, ADR-0008). Still pending: the `nexus-platform` Gateway + Orders API +
> outbox (that project has not started) and the obs/trace leg (Week 3e). The scenario flips to fully
> realized when those land.

## 1. What this shows

A single customer order placed through the `nexus-platform` Gateway propagates through 9 systems in under one second: the Orders API commits to SQL Server AG, the outbox publisher emits to Kafka East, `dataflow-studio` CDC ingests it, the Avro-governed event lands in StarRocks for BI and ClickHouse for real-time analytics, and the obs stack shows a complete distributed trace. Target persona: the data architect who wants to see an end-to-end pipeline with proper governance.

## 2. Runtime + prerequisites

- **Environment target** — `data-engineering`
- **VMs required** — dc-nexus, vault-1, obs-metrics, obs-tracing, obs-logging, sql-fci-1/2, sql-ag-rep-1/2, kafka-east-1/2/3, schema-registry-1, sr-fe-leader, sr-be-1/2/3, ch-keeper-1, ch-shard1-rep1, swarm-manager-1
- **External services** — Kafka topic `orders.v1`, Schema Registry subject `orders.v1-value`, StarRocks table `dwh.fact_order`, ClickHouse table `analytics.pipeline_events`
- **Seed data** — retail generator, small profile: `nexus-cli seed retail --profile=small`
- **Expected duration** — 6 min
- **Reset command** — `nexus-cli demo run DEMO-01 --reset`

## 3. Architecture snapshot

```
OltpDb (SQL Server AG, FCI .16)         source of truth — 11 tables, temporal + audit cols
   │  SQL Server CDC (log-based; the pipeline never queries the OLTP tables)
   ▼
Debezium  (Kafka Connect .95/.96)       oltp.OltpDb.dbo.*  — raw JSON CDC envelopes (10 tables)
   │  .NET curation worker (Ingestion module, data-driven catalog — ADR-0007)
   ▼
Curated Avro (Schema Registry .91)      dfs.<entity>.changed.v1 — 10 typed, versioned contracts
   │  .NET Warehouse sink (ADR-0006)
   ▼
StarRocks dwh (FE .31 / BE .34-.36)     Kimball star: SCD2 dim_customer/dim_product + 4 facts
   │  telemetry emitted by BOTH stages -> dfs.telemetry.* (JSON)
   ▼
ClickHouse analytics (.44-.49)          pipeline_events · cdc_lag_seconds · error_events
                                        ingested NATIVELY by ClickHouse's own Kafka engine + MVs
   ⋯ OpenLineage → Marquez + OTel traces (Week 3e)
```

### 3a. Replay the live segment today

```powershell
# from the dataflow-studio repo — each step is idempotent
.\scripts\dfs-seed.ps1            # representative order-flow dataset into OltpDb
.\scripts\dfs-curate.ps1          # raw CDC -> curated Avro (10 topics, 59 records on a fresh seed)
.\scripts\dfs-warehouse-sink.ps1  # curated Avro -> StarRocks dwh (SCD2 dims + facts)
.\scripts\dfs-trace.ps1           # follow ONE record across the faces
.\scripts\dfs-telemetry.ps1 all   # read back the pipeline's own telemetry; prove both error paths
```

From-zero replay + the transient ledger:
[`dataflow-studio/docs/handbook.md`](https://github.com/grezap/dataflow-studio/blob/main/docs/handbook.md).
By-hand walkthrough (SSMS + Kafka console + DataGrip), including watching an SCD2 version appear:
[`docs/demos/watch-the-pipeline.md`](https://github.com/grezap/dataflow-studio/blob/main/docs/demos/watch-the-pipeline.md).

## 4. Step-by-step script

- Readiness probe confirms all 9 upstream systems green.
- CLI places one order via POST to Gateway; captures `X-Trace-Id`.
- Jaeger shows 14-span trace from gateway through outbox, Kafka, CDC ingestor, to dual sinks.
- Grafana "DataFlow Studio — E2E" dashboard updates order-count and latency-p95 panels.
- Seq query `TraceId == "..."` returns the full log thread across services.
- StarRocks `SELECT` against `dwh.fact_order` shows the row arrived.
- ClickHouse `SELECT` against `analytics.pipeline_events` shows ingestion latency under 500 ms.
- Schema Registry UI proves the Avro contract was consulted (request count ticked).
- Marquez shows one dataset lineage edge added.
- CLI prints summary and links.

## 5. Observability trail

- **Grafana** — dashboard UID `dataflow-e2e` · panels: `orders.v1 throughput`, `p95 end-to-end`, `CDC lag seconds`, `sink write errors`. URL: `http://obs-metrics.nexus.local:3000/d/dataflow-e2e`
- **Jaeger** — service `gateway`, operation `POST /orders`; expect 14 spans, root duration ≤ 450 ms. URL: `http://obs-tracing.nexus.local:16686`
- **Seq** — signal `DEMO-01 trail`; filter `TraceId = '{captured}'`. URL: `http://obs-logging.nexus.local:5341`
- **Marquez** — dataset `orders.v1` → `dwh.fact_order` edge. URL: `http://obs-metrics.nexus.local:3001`

## 6. Code pointers

*Filled in when the project ships.*

## 7. Variations

*Filled in when the project ships.*

## 8. Troubleshooting

*Filled in when the project ships.*

## 9. What this proves

- **.NET engineering + architecture** — outbox pattern, CDC ingestor, Avro serialization via `Nexus.Avro`, NetArchTest-enforced module boundaries.
- **Advanced SQL + analytics** — SQL Server temporal table + CDC, StarRocks MERGE SCD2, ClickHouse AggregatingMergeTree.
- **Python** — retail dataset generator (Faker) seeded this run; PySpark conformance job is the silver-layer equivalent.
- **DevOps** — full trace/metric/log propagation, Vault-sourced connection strings, Kafka consumer groups deployed via Swarm stack.
