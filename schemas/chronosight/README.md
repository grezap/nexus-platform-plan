# chronosight — Schemas

## Ownership

| Store | Database / schema | Role |
|---|---|---|
| ClickHouse | `chronosight_ts` | Time-series raw + derived (OHLCV) |
| StarRocks | `dwh.ts_marts` | Training-set materializations |
| Redis Cluster | — | Forecast result cache, series-metadata lookup |

**Migration tool:** DbUp for ClickHouse + StarRocks.
**Status:** DDL planned, authoring begins in Phase 8.

## ClickHouse — `chronosight_ts`

| Table | Description |
|---|---|
| `series_metadata` | Series catalog — symbol/instrument id, type (financial/demand/other), frequency, unit. |
| `raw_ticks_local` | ReplicatedMergeTree partitioned by month — timestamp, seriesId, value, volume. |
| `raw_ticks` | Distributed view. |
| `ohlcv_1m_mv` | AggregatingMergeTree MV — 1-minute OHLCV windows. |
| `ohlcv_5m_mv` | 5-min candles. |
| `ohlcv_daily_mv` | Daily candles with high-water-mark and realized volatility. |
| `forecasts_local` | Per-run forecast output — seriesId, horizonMin, forecastAt, actualAtHorizon (backfilled), errorAbs, errorPct. |
| `forecasts` | Distributed. |
| `forecast_accuracy_mv` | Rolling MAE / MAPE per series per model_version. |
| `correlation_matrix_local` | Cross-symbol rolling correlation coefficients. |
| `changepoints` | Detected regime changes (SSA CPD output). |

## StarRocks — `dwh.ts_marts`

Training snapshots: (seriesId, window, features, target). Materialized nightly by PySpark job (E21). Iceberg-backed via E21 lakehouse integration.

## Redis key conventions

- `cs:forecast:{seriesId}:{horizonMin}` — latest forecast tuple, TTL 60s
- `cs:meta:{seriesId}` — series metadata, TTL 1h

## Advanced SQL artifacts required (E28)

- ClickHouse `windowFunnel` and `quantileTDigest` on `raw_ticks`.
- AggregatingMergeTree chained MVs (raw → 1m → 5m → daily).
- StarRocks colocation group on `ts_marts` for join locality.
- Generic Math `RollingWindow<T> where T : IFloatingPoint<T>` for Mean, StdDev, MAE, MAPE.
- Iceberg time-travel query on Bronze layer to re-run a forecast from a historical snapshot.
