# DEMO-06 · Forecast next-hour trading ticks

## 1. What this shows

`chronosight` ingests 5-year synthetic OHLCV data into ClickHouse, ksqlDB continuously derives 1-minute bars, a Prefect-scheduled Prophet/Chronos-Bolt forecaster writes next-hour predictions to StarRocks, and the forecast-accuracy dashboard updates. Target persona: data architect.

## 2. Runtime + prerequisites

- **Environment target** — `data-engineering`
- **VMs required** — dc-nexus, kafka-east-1/2/3, schema-registry-1, ksqldb-1, ch-keeper-1/2/3, ch-shard1-rep1/2, sr-fe-leader, sr-be-1/2/3, spark-master, spark-worker-1/2, prefect-server, jupyterhub-1, obs-*
- **External services** — Kafka topic `ticks.v1`, ClickHouse `ohlcv_1m`, StarRocks `forecasts`
- **Seed data** — `nexus-cli seed finance --profile=5y-50sym` (~26M rows)
- **Expected duration** — 6 min
- **Reset command** — `nexus-cli demo run DEMO-06 --reset`

## 3. Architecture snapshot

*Filled in when the project ships.*

## 4. Step-by-step script

- Tick producer replays 1 hour of ticks into `ticks.v1` at 1000x.
- ksqlDB query materializes OHLCV 1-minute bars to `ohlcv_1m.v1`.
- ClickHouse sink connector writes to `analytics.ohlcv_1m`.
- Prefect flow triggers on window close, runs Prophet forecaster on Spark.
- Forecast rows written to StarRocks `forecasts`.
- JupyterHub notebook renders actual vs. forecast charts.
- Portfolio UI's trading page shows live updates.

## 5. Observability trail

- **Grafana** — dashboard `chronosight-live` · panels `forecast MAE`, `ingestion lag`, `flow run duration`
- **Jaeger** — service `chronosight.api`; forecast fetch under 50 ms from StarRocks
- **Seq** — query `Workflow = 'forecast-hourly'`
- **Marquez** — asset graph `ticks.v1 → ohlcv_1m → forecasts`
- **URLs** — `http://prefect-server.nexus.local:4200`, `http://obs-metrics.nexus.local:3001`

## 6. Code pointers

*Filled in when the project ships.*

## 7. Variations

*Filled in when the project ships.*

## 8. Troubleshooting

*Filled in when the project ships.*

## 9. What this proves

- **.NET engineering + architecture** — Vertical Slice, Generic Math rolling windows, IAsyncEnumerable streaming API.
- **Advanced SQL + analytics** — ClickHouse AggregatingMergeTree, ASOF JOIN, StarRocks colocate joins, Iceberg time-travel.
- **Python** — Prophet/Chronos-Bolt on PySpark, Prefect flow authoring, Polars feature prep.
- **DevOps** — Prefect scheduling, OpenLineage emission, forecast-accuracy Alertmanager rule.
