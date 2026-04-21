# sentinelml — Schemas

## Ownership

| Store | Database / schema | Role |
|---|---|---|
| PostgreSQL Patroni | `sentinelml_events` | Event Store (stream-per-aggregate, append-only) |
| PostgreSQL Patroni | `sentinelml_registry` | Model registry — metadata, artifacts, promotions |
| ClickHouse | `sentinelml_analytics` | Inference analytics, feature drift metrics |
| StarRocks | `dwh.ml_marts` | Training-set materializations (via Spark offline features) |

**Migration tool:** FluentMigrator (PostgreSQL) + DbUp (ClickHouse, StarRocks).
**Status:** DDL planned, authoring begins in Phase 3.

## PostgreSQL — `sentinelml_events`

Append-only Event Store. Stream naming: `fraud-{accountId}`, `model-{name}-lifecycle`, `drift-{feature}`.

| Table | Description |
|---|---|
| `streams` | Stream registry — id, type, version, created. |
| `events` | Append-only event log; Id, StreamId, Version, Type, PayloadJsonB, Metadata, OccurredUtc. |
| `snapshots` | Aggregate snapshots for fast rebuild. |
| `checkpoints` | Per-projection read-model checkpoints. |
| `subscriptions` | Catchup subscriber state. |

## PostgreSQL — `sentinelml_registry`

| Table | Description |
|---|---|
| `models` | Model family (fraud-classifier, anomaly-detector). |
| `model_versions` | Specific trained version; hash, ONNX blob path, hyperparameters. |
| `training_runs` | Training execution record — started/ended, metrics, dataset hash. |
| `training_datasets` | Versioned feature-set snapshots (reference to StarRocks `dwh.ml_marts`). |
| `promotions` | Staging → production promotion history with approvals. |
| `drift_detections` | PSI values per feature per check; threshold breaches. |
| `retraining_triggers` | Queued retrain jobs (drift-triggered, scheduled, manual). |
| `ground_truth_labels` | Delayed-label feedback from payment disputes. |
| `feature_definitions` | Feature catalog with owners + data-type contracts. |
| `feature_lineage` | Feature → upstream source mapping (feeds Marquez E16). |

## ClickHouse — `sentinelml_analytics`

| Table | Description |
|---|---|
| `inference_events_local` | ReplicatedMergeTree per-shard inference log. |
| `inference_events` | Distributed view across shards. |
| `feature_histograms` | AggregatingMergeTree — bucketed feature value distributions per hour. |
| `score_distribution` | Predicted-score histograms for model monitoring. |
| `drift_metrics_mv` | Materialized view computing PSI per feature per hour. |
| `alert_events` | Threshold breaches — surfaced in Blazor alerts panel. |

## StarRocks — `dwh.ml_marts`

Training-set snapshots materialized by Spark offline feature job. Versioned by dataset hash.

## Advanced SQL artifacts required (E28)

- Window function computing trailing-24h account velocity.
- PostgreSQL JSONB GIN index on `events.PayloadJsonB`.
- ClickHouse AggregatingMergeTree MV for per-hour drift PSI.
- ksqlDB streaming SQL (already in Vol05) — `fraud_score_buckets`, `high_risk_transactions`, `account_velocity`.
