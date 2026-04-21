# DEMO-08 · Survive a Kafka region failure

## 1. What this shows

A live producer writes to Kafka East; `nexus-cli kafka failover east-to-west` is executed mid-stream; MM2 has been mirroring, so consumers resume against Kafka West with under 60 seconds of downtime and zero data loss. Target persona: CTO.

## 2. Runtime + prerequisites

- **Environment target** — `data-engineering`
- **VMs required** — kafka-east-1/2/3, kafka-west-1/2/3, mm2-1/2, schema-registry-1/2, swarm-manager-1, obs-*
- **External services** — Kafka topics `orders.v1` (east) and mirrored `orders.v1` (west via MM2)
- **Seed data** — continuous producer started by the demo harness
- **Expected duration** — 7 min
- **Reset command** — `nexus-cli demo run DEMO-08 --reset`

## 3. Architecture snapshot

*Filled in when the project ships.*

## 4. Step-by-step script

- Producer emits 500 msg/s into Kafka East `orders.v1`.
- MM2 mirrors to Kafka West; consumer group lag checked both sides.
- CLI halts Kafka East VMs (vmrun stop) to simulate region loss.
- `nexus-cli kafka failover east-to-west` updates bootstrap config on consumers.
- Consumer group offsets restored from MM2 checkpoint topic.
- Stream resumes on West cluster; end-to-end RTO measured and printed.
- CLI brings East back; reverse-mirror reconciles.

## 5. Observability trail

- **Grafana** — dashboard `streamcore-dr` · panels `MM2 lag`, `consumer group lag`, `RTO wallclock`
- **Jaeger** — service `streamcore.producer`; trace gaps visible during outage
- **Seq** — query `Event = 'kafka-failover' OR Event = 'mm2-checkpoint'`
- **URLs** — `http://obs-metrics.nexus.local:3000/d/streamcore-dr`

## 6. Code pointers

*Filled in when the project ships.*

## 7. Variations

*Filled in when the project ships.*

## 8. Troubleshooting

*Filled in when the project ships.*

## 9. What this proves

- **.NET engineering + architecture** — resilient Kafka consumers via Nexus.Kafka, CancellationToken discipline.
- **Advanced SQL + analytics** — ClickHouse materialized view continues serving post-failover.
- **Python** — chaos driver that coordinates VM halts with RTO measurement.
- **DevOps** — MM2 topology, offset checkpoint translation, one-command failover.
