# DEMO-07 · Personalized recommendations emerge from interactions

## 1. What this shows

A stream of user interactions into Kafka is consumed by a Kafka Streams GlobalKTable and joined with an ML.NET MatrixFactorization model; the `recoengine` API returns personalized Top-N recommendations whose relevance improves visibly as more interactions flow in. Target persona: AI-forward.

## 2. Runtime + prerequisites

- **Environment target** — `ml` (subset)
- **VMs required** — dc-nexus, vault-1, pxc-node-1/2/3, proxysql-1, kafka-east-1/2/3, recoengine svc on swarm-manager-1, unleash-1, obs-*
- **External services** — Kafka topic `interactions.v1`, Percona schema `recoengine`
- **Seed data** — `nexus-cli seed reco --profile=showcase`
- **Expected duration** — 5 min
- **Reset command** — `nexus-cli demo run DEMO-07 --reset`

## 3. Architecture snapshot

*Filled in when the project ships.*

## 4. Step-by-step script

- CLI creates a synthetic user with a biased interaction profile (prefers outdoor gear).
- Producer replays 5 minutes of interactions at 10x.
- Kafka Streams topology updates GlobalKTable of (user → affinity vector).
- CLI fetches `/recommendations/{userId}` once at t=0 and again at t=30s; rankings shift.
- A/B variant (Unleash flag) toggles between pure MF and hybrid scoring.
- Grafana NDCG panel improves in the right tail.

## 5. Observability trail

- **Grafana** — dashboard `recoengine-live` · panels `request p95`, `NDCG@10 rolling`, `variant split`
- **Jaeger** — service `recoengine.api`; trace depth 6
- **Seq** — query `UserId = '{id}'`
- **URLs** — `http://obs-metrics.nexus.local:3000/d/recoengine-live`

## 6. Code pointers

*Filled in when the project ships.*

## 7. Variations

*Filled in when the project ships.*

## 8. Troubleshooting

*Filled in when the project ships.*

## 9. What this proves

- **.NET engineering + architecture** — Modular Monolith, ML.NET in-process inference, Streamiz Kafka Streams.
- **Advanced SQL + analytics** — recursive CTE on category tree for candidate generation, Percona PXC cluster consistency.
- **Python** — offline MF benchmark, NDCG evaluation harness.
- **DevOps** — Unleash-driven A/B, CI reproducibility on seeded randomness.
