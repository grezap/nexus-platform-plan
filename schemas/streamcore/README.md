# streamcore — Schemas

## Ownership

| Store | Database / schema | Role |
|---|---|---|
| ClickHouse | `streamcore_analytics` | Tick analytics, anomaly events, DR observations |
| PostgreSQL Patroni | `streamcore_state` | Chaos game-day records, MM2 checkpoint snapshots |
| Redis Cluster | — | Symbol metadata cache, rate limiting |

**Migration tool:** DbUp (ClickHouse) + FluentMigrator (PostgreSQL).
**Status:** DDL planned, authoring begins in Phase 12.

## ClickHouse — `streamcore_analytics`

| Table | Description |
|---|---|
| `tick_ingestion_local` | ReplicatedMergeTree — every tick received (pre-validation). |
| `tick_ingestion` | Distributed. |
| `tick_valid_local` | Validated ticks post-filter. |
| `ohlcv_1m_store_local` | Built by Kafka Streams job `ohlcv-builder` (output topic `ohlcv-1m`), mirrored to ClickHouse. |
| `price_anomalies` | Spikes / gaps detected by streaming logic. |
| `mm2_lag_observations` | Sampled MM2 replication lag between east ↔ west. |
| `cluster_health_snapshots` | Per-second broker health roll-ups. |
| `ingestion_rate_mv` | AggregatingMergeTree MV — messages/sec by partition by broker. |
| `anomaly_hourly_mv` | Per-hour anomaly counts for Grafana. |

## PostgreSQL — `streamcore_state`

| Table | Description |
|---|---|
| `chaos_events` | Start/end of every Chaos Harness invocation — target, attack type, blast radius, outcome. |
| `chaos_observations` | Time-series observations captured during a chaos event (latency, error rate, recovery time). |
| `dr_failovers` | Every `nexus-cli kafka failover` run — direction, initiated/completed, pre/post offsets, lag at switch, zero-loss verdict. |
| `mm2_checkpoints` | Persisted MM2 checkpoints by topic-partition — used to verify no-data-loss claim. |
| `game_day_reports` | Generated failover-report markdown metadata + artifact path. |
| `runbook_executions` | Which runbook, started/ended, exit status, who ran it (CI or human). |

## Advanced SQL artifacts required (E28)

- ClickHouse `quantileTDigestMerge` on sampled MM2 lag.
- Window functions with `PARTITION BY broker ORDER BY sampleUtc` for health smoothing.
- PostgreSQL range types (`tstzrange`) for chaos event time windows.
- Kafka Streams topology — `WindowStore` state store `ohlcv-1m-store`.
- Live MM2 DR demo (DEMO-08) with zero-loss verification.
