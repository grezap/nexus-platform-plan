# DEMO-14 · Traverse a single order's entire journey

## 1. What this shows

The meta-scenario. A single customer order is placed in `nexus-platform`; it flows through `dataflow-studio` into the lakehouse, is scored for fraud by `sentinelml`, generates a recommendation by `recoengine`, appears in `querylens` as a captured query, is queryable by `localmind` via natural-language Q&A, appears as a field-submission mirror on `fieldsync`, is rendered by `nexus-desk`, forecast-adjusted by `chronosight`, and finally lands in `lakehouse-core` gold marts. Target persona: recruiter (the closing number).

## 2. Runtime + prerequisites

- **Environment target** — `full` (suspend/resume between clusters as needed)
- **VMs required** — effectively all 65 VMs across foundation, sqlserver, kafka-east, analytics, oltp, swarm, spark, platform-tools, windows-workstations
- **External services** — every Kafka topic, every primary store, Iceberg catalog, Trino
- **Seed data** — `nexus-cli seed all --profile=meta`
- **Expected duration** — 10 min
- **Reset command** — `nexus-cli demo run DEMO-14 --reset` (takes ~3 min)

## 3. Architecture snapshot

*Filled in when the project ships.*

## 4. Step-by-step script

- One order placed via Gateway.
- `nexus-platform` Orders service commits, outbox emits to Kafka.
- `dataflow-studio` ingests; Avro schema validated; row lands in SQL AG → StarRocks → ClickHouse.
- `sentinelml` scores the transaction; flagged or cleared.
- `recoengine` updates user affinity; refreshed Top-N.
- `querylens` captures the `SELECT` performed by the billing job and labels it.
- `localmind` chat: "Show me orders > $500 in the last hour" returns grounded answer citing `fact_order`.
- `fieldsync` device picks up the order as a follow-up inspection task.
- `nexus-desk` DBA Studio shows the write in AG synchronization panel.
- `chronosight` rolls the order into hourly forecast baselines.
- `lakehouse-core` bronze→silver→gold chain closes; dbt snapshot updates `dim_customer_scd2`.
- Marquez renders the full cross-project lineage graph.

## 5. Observability trail

- **Grafana** — dashboard `meta-order-journey` · one panel per project stage
- **Jaeger** — root trace spanning 30+ services; linked across domains via trace-id header propagation
- **Seq** — query `OrderId = '{id}'` across all services
- **Marquez** — complete cross-project asset graph
- **URLs** — all of the above with the captured order-id filter preset

## 6. Code pointers

*Filled in when the project ships.*

## 7. Variations

*Filled in when the project ships.*

## 8. Troubleshooting

*Filled in when the project ships.*

## 9. What this proves

- **.NET engineering + architecture** — end-to-end trace-id propagation across 14 projects, consistent `Nexus.*` shared libraries, every architecture pattern represented.
- **Advanced SQL + analytics** — one row visible in OLTP, DWH, lakehouse, analytics, and forecasts concurrently.
- **Python** — PySpark silver/gold, dbt snapshots, fraud/reco/forecast ML all participate.
- **DevOps** — full obs stack correlates every hop; environment-target suspension strategy keeps memory footprint viable.
