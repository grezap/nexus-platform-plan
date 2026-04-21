# DEMO-01 · Place an order, watch it flow everywhere

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

*Filled in when the project ships.*

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
