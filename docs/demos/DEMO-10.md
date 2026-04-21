# DEMO-10 · Field-sync offline-first

## 1. What this shows

The `fieldsync` MAUI app (Windows variant) captures a field submission while the network is down; the device airplane-mode is lifted; the submission reconciles against the MongoDB server and propagates to StarRocks. On-device ONNX OCR extracts text from an attached image before sync. Target persona: CTO.

## 2. Runtime + prerequisites

- **Environment target** — `demo-minimal` + fieldsync
- **VMs required** — mongo-1/2/3, sr-fe-leader, sr-be-1/2/3, fieldsync svc on swarm-manager-1, nexusdesk-dev (MAUI host), obs-*
- **External services** — MongoDB `fieldsync.submissions`, StarRocks `fact_submission`
- **Seed data** — prior 200 submissions for baseline
- **Expected duration** — 5 min
- **Reset command** — `nexus-cli demo run DEMO-10 --reset`

## 3. Architecture snapshot

*Filled in when the project ships.*

## 4. Step-by-step script

- MAUI app launched on nexusdesk-dev; network disabled.
- User fills form, attaches image; on-device ONNX OCR extracts fields into form.
- Submission queued locally in SQLite.
- Network restored; sync client opens gRPC bidi stream, streams queue.
- Server applies conflict-free reconciliation, writes to Mongo.
- CDC into StarRocks updates `fact_submission`.
- Portfolio dashboard shows submission count tick.

## 5. Observability trail

- **Grafana** — dashboard `fieldsync-ops` · panels `queue depth by device`, `sync p95`, `conflict rate`
- **Jaeger** — service `fieldsync.sync`; trace shows gRPC bidi lifecycle
- **Seq** — query `DeviceId = '{id}'`
- **URLs** — `http://obs-metrics.nexus.local:3000/d/fieldsync-ops`

## 6. Code pointers

*Filled in when the project ships.*

## 7. Variations

*Filled in when the project ships.*

## 8. Troubleshooting

*Filled in when the project ships.*

## 9. What this proves

- **.NET engineering + architecture** — MAUI multi-target, gRPC bidi streams, SQLite offline store.
- **Advanced SQL + analytics** — Mongo aggregation for conflict detection, StarRocks primary-key table.
- **Python** — device-simulation harness for load testing.
- **DevOps** — protobuf schema governance, MSIX MAUI distribution.
