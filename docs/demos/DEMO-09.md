# DEMO-09 · Catch a query regression with AI rewrite

## 1. What this shows

`querylens` polls SQL Server DMVs, detects a plan regression on a deliberately-degraded query, and asks LocalMind for a rewrite; the suggested rewrite is reviewed and applied, and the regression clears. Target persona: data architect.

## 2. Runtime + prerequisites

- **Environment target** — `data-engineering` + localmind
- **VMs required** — sql-fci-1/2, sql-ag-rep-1/2, pg-primary (event store), localmind svc, querylens svc on swarm-manager-1, obs-*
- **External services** — SQL Server `SalesDb`, PG `querylens.events`
- **Seed data** — `nexus-cli seed querylens --profile=regression-fixture`
- **Expected duration** — 6 min
- **Reset command** — `nexus-cli demo run DEMO-09 --reset`

## 3. Architecture snapshot

*Filled in when the project ships.*

## 4. Step-by-step script

- Baseline workload generator runs for 60 s; plan captures stored.
- Demo adds a skewed statistic and a missing index hint, re-runs workload.
- `querylens` ingester flags a plan-hash change with duration delta > 5x.
- Changepoint detector fires; story emitted to PG event store.
- UI shows regression card with before/after plan, metric deltas.
- LocalMind invoked via `/ai/rewrite`; returns candidate with reasoning.
- Reviewer approves; rewrite applied.
- Next workload pass shows regression resolved.

## 5. Observability trail

- **Grafana** — dashboard `querylens-regressions` · panels `regression count`, `avg duration delta`, `rewrite adoption rate`
- **Jaeger** — service `querylens.ingester`; trace shows DMV poll → diff → publish
- **Seq** — query `RegressionId = '{id}'`
- **URLs** — `http://obs-metrics.nexus.local:3000/d/querylens-regressions`

## 6. Code pointers

*Filled in when the project ships.*

## 7. Variations

*Filled in when the project ships.*

## 8. Troubleshooting

*Filled in when the project ships.*

## 9. What this proves

- **.NET engineering + architecture** — Vertical Slice, Event Sourcing, integration with LocalMind via typed client.
- **Advanced SQL + analytics** — DMV queries, plan-hash comparison, Query Store deltas, changepoint detection CTEs.
- **Python** — synthetic workload driver.
- **DevOps** — rewrite audit log, one-click apply with rollback tether.
