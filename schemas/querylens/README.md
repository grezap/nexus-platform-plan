# querylens — Schemas

## Ownership

| Store | Database / schema | Role |
|---|---|---|
| SQL Server AG | `QueryLensDb` | Observed target DBs registry, applied rewrites, alerts |
| PostgreSQL Patroni | `querylens_events` | Event Store — stream-per-query-hash |
| ClickHouse | `querylens_ts` | DMV time-series + per-plan perf history |

**Migration tool:** FluentMigrator (SQL Server, PostgreSQL) + DbUp (ClickHouse).
**Status:** DDL planned, authoring begins in Phase 9.

## SQL Server — `QueryLensDb`

| Table | Description |
|---|---|
| `Targets` | Registered observed DBs — connection string (Vault-referenced), polling interval. |
| `QueryHashes` | Distinct `query_hash` values discovered on targets. |
| `PlanHashes` | Distinct `plan_hash` values with cached plan XML snippet. |
| `SqlTexts` | Normalized SQL text per query_hash (deduplicated). |
| `RewriteSuggestions` | Suggestions from LocalMind — id, queryHash, originalSql, rewriteSql, expectedImprovement, reasoning. |
| `AppliedRewrites` | History of rewrites deployed; before/after metrics, author, approvedUtc. |
| `Alerts` | Regression alerts (severity, first-seen, ack, resolved). |
| `QueryStories` | Narrative timeline per queryHash — commits, plan changes, alerts, rewrites. |
| `DmvSnapshotRuns` | Poll-run headers — target, startUtc, endUtc, rowsInserted. |

## PostgreSQL — `querylens_events`

Stream naming: `query-{hash}`. Event types: `QueryObserved`, `QueryPerformanceSnapshot`, `PlanRegressionDetected`, `RewriteSuggested`, `RewriteApproved`, `RewriteApplied`, `PerformanceImproved`.

| Table | Description |
|---|---|
| `streams` | Stream registry. |
| `events` | Append-only log — id, streamId, version, type, payloadJsonB, metadata, occurredUtc. |
| `snapshots` | Aggregate snapshots. |
| `checkpoints` | Projection read-model checkpoints. |

## ClickHouse — `querylens_ts`

| Table | Description |
|---|---|
| `dmv_snapshots_local` | ReplicatedMergeTree — per-sample DMV reading (queryHash, planHash, totalCpuMs, totalLogicalReads, executionCount, sampleUtc). |
| `dmv_snapshots` | Distributed. |
| `plan_changepoints` | Detected changepoints per (queryHash, metric) using SSA CPD. |
| `perf_trend_mv` | Rolling averages — 1h / 24h / 7d per queryHash. |
| `regression_candidates_mv` | Materialized set of currently-suspect queries for UI ranking. |

## Advanced SQL artifacts required (E28)

- Window functions with `LAG/LEAD` on `dmv_snapshots` for delta calc.
- Recursive CTE decomposing plan XML operator tree.
- SQL Server 2022 `sys.dm_exec_query_stats` + `sys.query_store_plan` joins.
- Pattern matching exhaustiveness on `AlertSeverity = LowSeverity | MediumSeverity | CriticalSeverity`.
