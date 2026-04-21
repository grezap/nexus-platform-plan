# DEMO-12 · Lakehouse Bronze to Silver to Gold

## 1. What this shows

Raw CDC events land in Iceberg Bronze on MinIO; a PySpark silver job conforms them; dbt snapshots build SCD2 dimensions and gold marts; Trino federates a query across Iceberg gold and StarRocks real-time. Target persona: data architect.

## 2. Runtime + prerequisites

- **Environment target** — `data-engineering` + spark/minio
- **VMs required** — spark-master, spark-worker-1/2, minio-1, jupyterhub-1, prefect-server, sr-fe-leader, sr-be-1/2/3, ch-keeper-1, obs-*, marquez
- **External services** — Iceberg catalog (REST), MinIO bucket `lakehouse`, Trino gateway
- **Seed data** — `nexus-cli seed retail --profile=medium` (500K orders) plus CDC replay into bronze
- **Expected duration** — 8 min
- **Reset command** — `nexus-cli demo run DEMO-12 --reset`

## 3. Architecture snapshot

*Filled in when the project ships.*

## 4. Step-by-step script

- Prefect flow `bronze-ingest` kicked off; writes CDC events to `bronze.orders`.
- `silver-conform` PySpark job deduplicates, casts types, writes to `silver.fact_order`.
- dbt snapshots build `silver.dim_customer_scd2` (shows Type-2 history).
- `gold-marts` dbt run builds `gold.mart_customer_360`.
- Trino query joins `gold.mart_customer_360` with StarRocks `live.orders_today`.
- JupyterHub notebook renders an Iceberg time-travel query (yesterday vs. today).
- Marquez asset graph shows bronze → silver → gold lineage chain.

## 5. Observability trail

- **Grafana** — dashboard `lakehouse-ops` · panels `flow duration by layer`, `dbt test pass rate`, `Iceberg snapshot count`
- **Jaeger** — service `lakehouse.api`; federated query trace
- **Seq** — query `Workflow IN ('bronze-ingest','silver-conform','gold-marts')`
- **Marquez** — full asset graph bronze→silver→gold
- **URLs** — `http://prefect-server.nexus.local:4200`, `http://obs-metrics.nexus.local:3001`

## 6. Code pointers

*Filled in when the project ships.*

## 7. Variations

*Filled in when the project ships.*

## 8. Troubleshooting

*Filled in when the project ships.*

## 9. What this proves

- **.NET engineering + architecture** — `nexus-cli lakehouse` commands, Iceberg catalog client.
- **Advanced SQL + analytics** — Iceberg time travel, dbt snapshots for SCD2, Trino federation, StarRocks colocate join.
- **Python** — PySpark jobs, dbt adapter configuration, Prefect flow authoring.
- **DevOps** — Prefect orchestration, OpenLineage emission, Iceberg maintenance (compaction, snapshot expiry).
