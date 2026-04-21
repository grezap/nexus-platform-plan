# nexus-desk — Schemas

Monorepo of 4 Windows apps sharing `NexusDesk.Core` + `NexusDesk.Infrastructure`. Each app has a tiny local SQLite store for UI state. Remote data comes from backing project APIs (AG listener, LocalMind Named Pipes, Docker Engine API, Nomad/Consul/Vault HTTP).

## Per-app local SQLite — `nexusdesk_{app}.db`

**Migration tool:** FluentMigrator SQLite; migrations ship inside each app bundle.
**Status:** DDL planned, authoring begins in Phase 13.

### NexusDesk.DbaStudio (WinForms)

| Table | Description |
|---|---|
| `connections` | Saved SQL Server connection profiles (Vault AppRole references, no plaintext). |
| `ag_health_snapshots` | Local cached AG health polls for offline review. |
| `failover_history` | User-initiated failover operations and outcomes. |
| `custom_queries` | Saved T-SQL snippets with tags. |
| `query_runs` | Execution history with duration + row count. |

### NexusDesk.TradingDesk (WPF + ReactiveUI)

| Table | Description |
|---|---|
| `watchlists` | Named lists of symbols. |
| `alerts` | Price / indicator alerts — threshold, triggered_at. |
| `orders_simulated` | Paper-trading order log (demo mode only). |
| `layouts` | Window / grid layout persistence. |

### NexusDesk.AiAssistant (WinUI 3)

| Table | Description |
|---|---|
| `conversations_local` | Local mirror of LocalMind conversations (id + last-synced-utc). |
| `draft_messages` | Unsent drafts. |
| `pinned_responses` | Starred assistant responses with tags. |
| `app_settings` | Per-user model preferences. |

### NexusDesk.InfraControl (WinUI 3 + WPF XamlIsland hybrid)

| Table | Description |
|---|---|
| `cluster_snapshots` | Periodic topology snapshots — what ran where when. |
| `failover_audit` | Triggered failover actions. |
| `dashboard_layouts` | Embedded Grafana/Portainer panel positions. |
| `ssh_sessions` | Recent SSH session metadata (no credentials; Vault-sourced). |

## Shared cross-app

| Table | Description |
|---|---|
| `vault_token_cache` | Encrypted cached Vault AppRole token (via Windows Credential Manager DPAPI). |
| `update_channels` | ClickOnce / MSIX update channel config per app. |
| `telemetry_events` | Local usage telemetry (opt-in) — buffered, OTLP-exported. |

## Advanced SQL artifacts required (E28)

- SQL Server DMV joins for AG health — `sys.availability_replicas` × `dm_hadr_availability_replica_states` × `dm_hadr_database_replica_states` (DbaStudio).
- Generic Math static abstract members on indicator calculations (Bollinger, EMA, force-directed graph layout) in `NexusDesk.Core.Math`.
- Reactive SQLite change-tracking via `SQLiteChangeTracking` + `IObservable<ChangeEvent>` (TradingDesk).
