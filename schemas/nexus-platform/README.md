# nexus-platform — Schemas

Microservices reference implementation. Per-service databases. Full `/k8s` manifests.

## Service → store map

| Service | Store | Database/schema | Migration tool |
|---|---|---|---|
| Order Service | PostgreSQL Patroni | `nexusplatform_orders` (Event Store) | FluentMigrator |
| Inventory Service | Percona MySQL PXC | `nexusplatform_inventory` | FluentMigrator |
| Payment Service | PostgreSQL Patroni | `nexusplatform_payments` | FluentMigrator |
| Notification Service | MongoDB RS | `nexusplatform_notifications` | `IMongoCollection<T>` index initializers |
| Analytics Service | ClickHouse | `nexusplatform_analytics` | DbUp |
| API Gateway (Ocelot) | Redis Cluster | — (key conventions only) | — |

**Status:** DDL planned, authoring begins in Phase 11.

## Order Service — `nexusplatform_orders` (PostgreSQL, Event Store)

Stream: `order-{orderId}`. Events: `OrderPlaced, PaymentRequested, PaymentCompleted, PaymentFailed, InventoryReserved, InventoryReservationFailed, OrderConfirmed, OrderCancelled, OrderShipped, OrderDelivered`.

| Table | Description |
|---|---|
| `streams` | Stream registry. |
| `events` | Append-only log. |
| `snapshots` | Aggregate snapshots. |
| `read_orders` | Projected read model — latest state per order. |
| `read_customers` | Denormalized customer view. |
| `sagas` | Saga instance state (choreography bookkeeping + orchestration StateMachine). |
| `outbox` | MassTransit Outbox. |

## Inventory Service — `nexusplatform_inventory` (Percona)

| Table | Description |
|---|---|
| `products` | SKU catalogue. |
| `warehouses` | Warehouses with region + capacity. |
| `stock_levels` | (productId, warehouseId) → on_hand, reserved, available. |
| `stock_movements` | Audit trail of every +/- change. |
| `reservations` | Temporary reservations from order saga. |
| `replenishment_triggers` | Auto-reorder events when below threshold. |
| `outbox` | MassTransit Outbox. |

## Payment Service — `nexusplatform_payments` (PostgreSQL)

| Table | Description |
|---|---|
| `payment_intents` | Incoming payment requests with idempotency key. |
| `payment_transactions` | Capture / refund / void records. |
| `payment_methods` | Tokenized method refs (never raw PAN). |
| `gateway_events` | Raw webhook payloads (audit + replay). |
| `disputes` | Chargeback / dispute lifecycle. |
| `outbox` | MassTransit Outbox. |

## Notification Service — `nexusplatform_notifications` (MongoDB)

| Collection | Description |
|---|---|
| `notifications` | Queued + delivered notifications. |
| `templates` | Email / SMS / push templates. |
| `delivery_attempts` | Provider response per attempt. |
| `user_preferences` | Per-user channel opt-in/out. |
| `bounce_log` | Bounce + complaint tracking. |

## Analytics Service — `nexusplatform_analytics` (ClickHouse)

| Table | Description |
|---|---|
| `platform_events_local` | All cross-service events landed via Kafka consumer. |
| `platform_events` | Distributed. |
| `order_funnel_mv` | AggregatingMergeTree MV — placed → paid → confirmed → shipped → delivered. |
| `revenue_hourly_mv` | Revenue by hour by region. |
| `payment_success_rate_mv` | Gateway success-rate trends. |

## Advanced SQL artifacts required (E28)

- PostgreSQL CTE for saga state reconstruction from Event Store.
- Percona recursive category traversal.
- ClickHouse funnel function for multi-step conversion analysis.
- MongoDB aggregation with `$facet` for multi-dimensional notification analytics.
- Cross-service data contracts — AsyncAPI specs in `docs/api/asyncapi/*.yaml`.
