# visioncore — Schemas

## Ownership

| Store | Database / schema | Role |
|---|---|---|
| MongoDB RS | `visioncore` | Inspection records, detections, attachments (document model) |
| ClickHouse | `visioncore_analytics` | Per-inference analytics, defect rate trends |

**Migration tool:** MongoDB via `IMongoCollection<T>` index initializers + FluentMigrator-style version tracking collection. DbUp for ClickHouse.
**Status:** DDL planned, authoring begins in Phase 6.

## MongoDB — `visioncore`

| Collection | Description |
|---|---|
| `inspections` | Inspection root — id, tenantId, productId, imageRef (blob URI), capturedUtc, status. |
| `inspection_images` | Image variants (original, thumbnail, preprocessed) — GridFS refs. |
| `defect_categories` | Catalog of defect types — id, name, severity, threshold. |
| `defect_detections` | Per-inspection detections — box, class, confidence, modelVersion. |
| `models` | Model family (defect-classifier, document-classifier). |
| `model_versions` | Loaded ONNX models — hash, accuracy, opset, preprocessing config. |
| `inference_runs` | Per-inference record (duplicates subset of detections for fast querying). |
| `quality_gates` | Rules: "fail if any critical defect with conf > 0.8"; evaluated per inspection. |
| `production_lines` | Physical source descriptor — line, station, camera. |
| `operators` | Users who reviewed/overrode inspection results. |
| `reviews` | Human QA overrides; feeds training data for next model version. |
| `change_stream_offsets` | Persisted resume tokens for MongoDB change stream consumers. |

## ClickHouse — `visioncore_analytics`

| Table | Description |
|---|---|
| `inspections_local` | Flattened per-inspection row for analytics. |
| `inspections` | Distributed. |
| `defect_counts_hourly_mv` | AggregatingMergeTree MV — defects per line per hour. |
| `model_accuracy_mv` | Rolling accuracy vs human review overrides. |
| `line_yield_mv` | Production-line yield percentage over rolling windows. |

## Advanced SQL artifacts required (E28)

- MongoDB change stream → SignalR push (documented in `docs/sql-showcase.md`).
- ClickHouse AggregatingMergeTree for per-line yield quantiles.
- Aggregation pipeline with `$bucket` for defect severity histograms.
