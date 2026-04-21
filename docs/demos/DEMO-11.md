# DEMO-11 · Native Windows DBA tour

## 1. What this shows

The `nexus-desk` DBA Studio (WinForms) connects to the SQL Server AG listener, shows a live dashboard of the Availability Group, an active deadlock graph, plan cache top offenders, and kicks off a failover test — all from a Windows-native UI. Target persona: recruiter (visually striking, short path to "this is real work").

## 2. Runtime + prerequisites

- **Environment target** — `data-engineering` (subset) + `nexusdesk-dev`
- **VMs required** — sql-fci-1/2, sql-ag-rep-1/2, dc-nexus, nexusdesk-dev
- **External services** — SQL AG listener VIP
- **Seed data** — AdventureWorks + internal-ops schema pre-seeded
- **Expected duration** — 4 min
- **Reset command** — N/A (read-only tour)

## 3. Architecture snapshot

*Filled in when the project ships.*

## 4. Step-by-step script

- Launch `nexus-desk` DBA Studio on nexusdesk-dev.
- Connect via AG listener using integrated auth; health tiles go green.
- Open AG dashboard; replicas and synchronization state shown.
- Deadlock simulator (built-in) triggers a classic two-transaction deadlock.
- XEvent ring buffer surfaces the deadlock graph; user clicks to view XML.
- Plan cache tab shows top CPU offenders; user inspects a query's plan.
- Failover test initiated; passes in ~25 s; dashboard reflects role swap.

## 5. Observability trail

- **Grafana** — dashboard `sql-ag-health` · panels `replica sync`, `log send queue`, `failover history`
- **Jaeger** — N/A (in-app telemetry only)
- **Seq** — query `Service = 'nexus-desk.dbastudio'`
- **URLs** — `http://obs-metrics.nexus.local:3000/d/sql-ag-health`

## 6. Code pointers

*Filled in when the project ships.*

## 7. Variations

*Filled in when the project ships.*

## 8. Troubleshooting

*Filled in when the project ships.*

## 9. What this proves

- **.NET engineering + architecture** — WinForms app with modern C# 13 idioms, reactive data grids, Microsoft.Data.SqlClient.
- **Advanced SQL + analytics** — DMV queries, AG DMFs, deadlock graph XML parsing, plan cache analysis.
- **Python** — not used in this scenario.
- **DevOps** — failover validation, MSIX signing, auto-update channel.
