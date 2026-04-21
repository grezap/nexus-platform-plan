# DEMO-05 · Inspect a defect in a product image

## 1. What this shows

`visioncore` accepts a product image, runs an ONNX defect detector in-process via C#, persists the inspection record and overlay to MongoDB + MinIO, and surfaces the result in the portfolio UI. Target persona: AI-forward.

## 2. Runtime + prerequisites

- **Environment target** — `ml` (subset)
- **VMs required** — dc-nexus, vault-1, mongo-1/2/3, minio-1, visioncore svc on swarm-manager-1, obs-*
- **External services** — MongoDB `visioncore.inspections`, MinIO bucket `visioncore-overlays`
- **Seed data** — `nexus-cli seed vision --set=defect-showcase` (50 paired good/defect images)
- **Expected duration** — 4 min
- **Reset command** — `nexus-cli demo run DEMO-05 --reset`

## 3. Architecture snapshot

*Filled in when the project ships.*

## 4. Step-by-step script

- CLI uploads one image via POST `/inspections`.
- Inspection handler decodes via ImageSharp, runs ONNX session, returns detections.
- Overlay rendered server-side (ImageSharp) and stored in MinIO.
- Inspection document inserted in MongoDB with presigned overlay URL.
- Browser opens the inspection detail page; overlay displays 3 defect boxes with confidence.
- CLI prints inference latency (expect ≤ 120 ms on CPU).

## 5. Observability trail

- **Grafana** — dashboard `visioncore-ops` · panels `inference p95`, `GPU fallback ratio`, `defect rate`
- **Jaeger** — service `visioncore.api`; trace shows decode → inference → overlay → persist
- **Seq** — query `InspectionId = '{id}'`
- **URLs** — `http://obs-metrics.nexus.local:3000/d/visioncore-ops`

## 6. Code pointers

*Filled in when the project ships.*

## 7. Variations

*Filled in when the project ships.*

## 8. Troubleshooting

*Filled in when the project ships.*

## 9. What this proves

- **.NET engineering + architecture** — Clean Architecture, ONNX Runtime session pooling, ImageSharp-only (no OpenCV).
- **Advanced SQL + analytics** — Mongo aggregation over defect categories.
- **Python** — PyTorch training pipeline, ONNX export, evaluation harness.
- **DevOps** — MinIO-backed model-artifact versioning, CPU/GPU probe + fallback.
