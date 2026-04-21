# DEMO-02 · Detect a fraudulent transaction in real time

## 1. What this shows

A synthetic payment stream flows through `streamcore` into `sentinelml`; one deliberately anomalous transaction is flagged within 300 ms by an ONNX model, an alert fires to Alertmanager, and the drift monitor keeps baseline PSI unchanged. Target persona: AI-forward viewer.

## 2. Runtime + prerequisites

- **Environment target** — `ml`
- **VMs required** — dc-nexus, vault-1, obs-*, kafka-east-1/2/3, schema-registry-1, ksqldb-1, pg-primary, pg-replica-1, etcd-1/2/3, ch-keeper-1, ch-shard1-rep1, swarm-manager-1
- **External services** — Kafka topics `payments.v1`, `payments.scored.v1`, `payments.alerts.v1`; PostgreSQL Patroni feature store schema `feature_store`
- **Seed data** — `nexus-cli seed finance --profile=fraud-fixture`
- **Expected duration** — 5 min
- **Reset command** — `nexus-cli demo run DEMO-02 --reset`

## 3. Architecture snapshot

*Filled in when the project ships.*

## 4. Step-by-step script

- Producer injects 1,000 payments/sec into `payments.v1` for 30 s.
- `sentinelml` inference service pulls features from PG, scores with ONNX, publishes to `payments.scored.v1`.
- The poisoned transaction (known fingerprint) crosses the decision threshold.
- Alertmanager receives the score-based alert; Karma UI shows the incident.
- ksqlDB rollup counts scored vs. flagged in 5-second windows.
- Grafana shows PSI stable within tolerance band.
- CLI prints decision latency histogram.

## 5. Observability trail

- **Grafana** — dashboard `sentinelml-live` · panels `scoring p95`, `flagged rate`, `PSI by feature`
- **Jaeger** — service `sentinelml.inference`; trace depth 7
- **Seq** — query `Service = 'sentinelml' AND Level = 'Warning'`
- **Alertmanager** — route `fraud-alerts` fires once, resolves after 60 s
- **URLs** — `http://obs-metrics.nexus.local:3000/d/sentinelml-live`, `http://obs-metrics.nexus.local:9093`

## 6. Code pointers

*Filled in when the project ships.*

## 7. Variations

*Filled in when the project ships.*

## 8. Troubleshooting

*Filled in when the project ships.*

## 9. What this proves

- **.NET engineering + architecture** — Vertical Slice, MediatR, ONNX Runtime in-process, IAsyncEnumerable streaming.
- **Advanced SQL + analytics** — ClickHouse window functions for PSI computation, PG JSONB feature store.
- **Python** — training notebook produced the ONNX artefact; PSI baseline built by Polars job.
- **DevOps** — Alertmanager routing, Vault dynamic PG creds, Prefect orchestration of retrain trigger.
