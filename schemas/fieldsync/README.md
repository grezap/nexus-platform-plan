# fieldsync — Schemas

## Ownership

| Store | Database / schema | Role |
|---|---|---|
| SQLite (on-device, MAUI) | `fieldsync.db` | Offline-first local store on Android + Windows |
| MongoDB RS (server) | `fieldsync` | Server-side submission store (document model) |
| StarRocks | `dwh.fieldsync_marts` | Reporting DWH |
| ClickHouse | `fieldsync_analytics` | Sync event analytics, device telemetry |

**Migration tool:** FluentMigrator for both SQLite and MongoDB metadata; DbUp for ClickHouse + StarRocks. SQLite migrations ship inside the MAUI app bundle.
**Status:** DDL planned, authoring begins in Phase 10.

## SQLite (on-device) — `fieldsync.db`

| Table | Description |
|---|---|
| `submissions` | Local submission record — id (GUID), formId, formVersion, payloadJson, status, createdUtc, syncedUtc. |
| `attachments` | File attachments pending sync — local path, mimeType, bytes, submissionId. |
| `outbox` | Pending sync items — id, type, payload, attempts, nextAttemptUtc. |
| `form_definitions` | Cached form schemas fetched from server. |
| `form_versions` | Version history — allows offline compatibility check. |
| `device_state` | Device metadata + last-sync timestamps. |
| `inference_cache` | On-device ONNX inference results for suggestion reuse. |
| `sync_log` | Sync history entries — attempted, succeeded, failed with reason. |

## MongoDB — `fieldsync` (server)

| Collection | Description |
|---|---|
| `submissions` | Materialized server-side record. |
| `submission_attachments` | GridFS-backed large files. |
| `form_definitions` | Authoritative form schema. |
| `form_versions` | Server version history. |
| `devices` | Registered device inventory with fingerprint. |
| `users` | Field-worker identity + device bindings. |
| `sync_sessions` | Per-gRPC-session metadata — device, startUtc, endUtc, itemsSynced. |
| `conflicts` | Detected conflicts requiring human resolution. |
| `conflict_resolutions` | Resolution records (last-write-wins / merged / manual). |

## StarRocks — `dwh.fieldsync_marts`

| Table | Description |
|---|---|
| `dim_device` | SCD1 — device fingerprint, OS, model, registered date. |
| `dim_user` | SCD2 — user + role + team assignment. |
| `dim_form` | Form catalog with version lineage. |
| `fact_submission` | Submission grain — date, device, user, form_version, latency, sync_attempts. |
| `fact_attachment` | File-level grain for storage accounting. |

## ClickHouse — `fieldsync_analytics`

| Table | Description |
|---|---|
| `sync_events_local` | ReplicatedMergeTree — per-sync-attempt record. |
| `sync_events` | Distributed. |
| `offline_duration_mv` | AggregatingMergeTree MV — per-device offline-time buckets. |
| `sync_reliability_mv` | Success rate trends. |

## Advanced SQL artifacts required (E28)

- SQLite CTE traversing pending outbox with dependency order.
- MongoDB aggregation `$merge` writing into `conflicts` collection on version mismatch.
- ClickHouse `windowFunnel` on sync attempt sequence.
- gRPC bidirectional streaming contract: `SyncSubmissions (stream SubmissionBatch) returns (SyncAck)`.
