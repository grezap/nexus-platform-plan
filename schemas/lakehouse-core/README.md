# lakehouse-core — Schemas (Vol 14)

## Ownership

| Store | Namespace | Role |
|---|---|---|
| **Apache Iceberg on MinIO** | `bronze.*` | Raw landed CDC + Kafka payloads, immutable |
| Iceberg on MinIO | `silver.*` | Cleansed, typed, SCD2-dimensionalized (via dbt snapshots) |
| Iceberg on MinIO | `gold.*` | Business marts, denormalized for BI |
| StarRocks | `dwh.lh_federation` | Federated query entry — Trino external tables over Iceberg |
| ClickHouse | `lh_analytics` | Fast serving of gold-layer aggregates for Blazor dashboards |
| PostgreSQL Patroni | `lakehouse_catalog` | Iceberg catalog (Nessie or REST catalog) backing store |

**Migration tool:** DbUp (analytical) + dbt (transformations). Iceberg schema evolution via PySpark `ALTER TABLE`.
**Status:** DDL planned, authoring begins in Phase 14.

## Bronze layer (raw) — Iceberg

| Table | Description |
|---|---|
| `bronze.orders_raw` | CDC payloads from SQL Server `dbo.Orders` — partitioned by ingest date. |
| `bronze.customers_raw` | CDC from `dbo.Customers`. |
| `bronze.products_raw` | CDC from `dbo.Products`. |
| `bronze.transactions_raw` | CDC from `dbo.Transactions`. |
| `bronze.kafka_events_raw` | Sampled events from pipeline-events / ml-inference-events / etc. |
| `bronze.ingestion_metadata` | Per-micro-batch metadata — offsets, row counts, latency. |

## Silver layer (cleansed + dimensionalized) — Iceberg via dbt

| Table | Description |
|---|---|
| `silver.dim_customer_scd2` | SCD2 customer dimension via **dbt snapshots** — surrogate key, effective_from/to, is_current. |
| `silver.dim_product_scd2` | SCD2 product dimension. |
| `silver.dim_date` | Conformed date dimension. |
| `silver.dim_warehouse` | SCD1. |
| `silver.fact_order` | Order grain with surrogate FKs. |
| `silver.fact_order_line` | Line-item grain. |
| `silver.fact_transaction` | Payment transaction grain. |
| `silver.dq_rules` | dbt test outputs — one row per (test_id, run_id, pass/fail). |
| `silver.lineage_events` | OpenLineage (E16) emissions from every dbt run. |

## Gold layer (marts) — Iceberg via dbt

| Table | Description |
|---|---|
| `gold.mart_customer_360` | Full customer view — lifetime value, last purchase, preferred category, churn score. |
| `gold.mart_product_performance` | Product sales trend, margin, return rate. |
| `gold.mart_warehouse_yield` | Warehouse throughput + accuracy KPIs. |
| `gold.mart_rfm_segmentation` | Recency / Frequency / Monetary segment per customer. |
| `gold.mart_forecast_input` | Pre-built feature table used by ChronoSight + RecoEngine training. |

## StarRocks — `dwh.lh_federation`

Trino-backed external tables pointing at Iceberg. Lets BI tools query the lakehouse without Spark. Co-exists with native StarRocks marts from DataFlow Studio.

## ClickHouse — `lh_analytics`

Selected gold-layer rollups materialized into ClickHouse for sub-second Blazor queries.

## Advanced SQL artifacts required (E28)

- **Iceberg time-travel query**: `SELECT * FROM bronze.orders_raw VERSION AS OF <snapshot_id>` — point-in-time restoration demo in DEMO-12.
- **dbt snapshots** replacing hand-rolled SCD2 logic — versioned by snapshot timestamp.
- **dbt macros** parameterizing Kimball fact builds (fact_order, fact_transaction share a macro).
- **dbt exposures** — declaring which downstream dashboards depend on which gold tables.
- **Iceberg row-level deletes** — GDPR "right to be forgotten" demo.
- **Trino federation** — single query joining `bronze.orders_raw` (Iceberg) with `dwh.dim_customer` (StarRocks).
- **PySpark batch job** reading CDC → Bronze; uses Structured Streaming for exactly-once delivery.

## Medallion discipline

- **Bronze** is immutable — append-only, never edited.
- **Silver** applies schema + types + SCD2; idempotent re-runs acceptable.
- **Gold** is denormalized, query-optimized, built for specific consumers.
- Every layer transition is a Prefect flow (E23) with OpenLineage (E16) emission.
