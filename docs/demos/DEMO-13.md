# DEMO-13 · Chaos: kill a broker, survive gracefully

## 1. What this shows

The Chaos Harness in `streamcore` injects a broker kill mid-stream via Pumba; consumers rebalance; the topology's RocksDB state stores heal; end-to-end processing completes without data loss. Target persona: CTO.

## 2. Runtime + prerequisites

- **Environment target** — `data-engineering`
- **VMs required** — kafka-east-1/2/3, schema-registry-1, ch-shard1-rep1, swarm-manager-1/2, obs-*
- **External services** — Kafka topic `events.v1`, ClickHouse `streamcore.aggregates`
- **Seed data** — continuous producer
- **Expected duration** — 6 min
- **Reset command** — `nexus-cli demo run DEMO-13 --reset`

## 3. Architecture snapshot

*Filled in when the project ships.*

## 4. Step-by-step script

- Producer emits 1000 msg/s into `events.v1`; 4-topology Streams app consumes.
- Baseline throughput captured for 30 s.
- `nexus-cli chaos broker kill --cluster=east --node=2` triggers Pumba pause.
- Consumer group rebalances; p99 latency spikes and recovers.
- State stores reopen on new partition assignment.
- CLI brings broker back; ISR restores.
- Result: zero duplicate writes, zero missing records (ClickHouse count matches producer count).

## 5. Observability trail

- **Grafana** — dashboard `streamcore-chaos` · panels `throughput`, `consumer lag`, `p99 latency`, `ISR count`
- **Jaeger** — service `streamcore.topology`; gap visible during rebalance
- **Seq** — query `Event = 'chaos-injected' OR Event = 'rebalance'`
- **URLs** — `http://obs-metrics.nexus.local:3000/d/streamcore-chaos`

## 6. Code pointers

*Filled in when the project ships.*

## 7. Variations

*Filled in when the project ships.*

## 8. Troubleshooting

*Filled in when the project ships.*

## 9. What this proves

- **.NET engineering + architecture** — Streamiz topologies, exactly-once semantics, idempotent sinks.
- **Advanced SQL + analytics** — ClickHouse exactly-once sink via deduplication.
- **Python** — chaos orchestration driver.
- **DevOps** — Pumba integration, `nexus-cli chaos` surface, game-day runbook.
