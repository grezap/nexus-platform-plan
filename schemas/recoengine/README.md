# recoengine — Schemas

## Ownership

| Store | Database / schema | Role |
|---|---|---|
| Percona MySQL PXC | `recoengine` | Catalogue, user profiles, interactions |
| Redis Cluster | — | Per-user recommendation cache (TTL 1h), feature store |
| ClickHouse | `recoengine_analytics` | Interaction analytics, A/B test outcomes |
| StarRocks | `dwh.reco_marts` | Training-set materializations |

**Migration tool:** FluentMigrator (Percona) + DbUp (ClickHouse, StarRocks).
**Status:** DDL planned, authoring begins in Phase 7.

## Percona MySQL — `recoengine`

| Table | Description |
|---|---|
| `products` | Product catalogue — id, sku, name, categoryId, brand, attributes (JSON). |
| `categories` | Hierarchical category tree (parentId). |
| `product_features` | Dense feature vectors (factorization inputs) — serialized. |
| `users` | User profile — id, segment, locale, joinedUtc. |
| `user_features` | Per-user feature vector (serialized). |
| `interactions` | View/cart/purchase events — userId, productId, type, weight, occurredUtc. |
| `sessions` | Session-level grouping of interactions. |
| `recommendations` | Materialized top-K recommendations per user per context. |
| `matrix_factors` | Current ML.NET MatrixFactorization factors (versioned). |
| `experiments` | A/B experiment definitions — variants, traffic split, metrics. |
| `ab_assignments` | User → variant mapping with consistent hashing. |
| `ab_outcomes` | Per-experiment outcome metrics. |
| `training_runs` | Retraining history with metrics. |

## Redis key conventions

- `reco:user:{userId}:top` — precomputed top-20 recs, TTL 1h
- `reco:feature:user:{userId}` — per-user feature vector, TTL 24h
- `reco:feature:product:{productId}` — per-product feature vector, TTL 24h
- `reco:ab:{experimentId}:{userId}` — consistent variant assignment

## ClickHouse — `recoengine_analytics`

| Table | Description |
|---|---|
| `interactions_local` | ReplicatedMergeTree — every click/view/cart/purchase. |
| `interactions` | Distributed. |
| `ctr_hourly_mv` | CTR per category per hour. |
| `conversion_funnel_mv` | Funnel stage counts per user segment. |
| `ab_outcomes_mv` | Per-experiment running-mean outcomes. |

## StarRocks — `dwh.reco_marts`

Training-set snapshots of user × product × interaction for ML.NET retraining. Generated nightly by Spark job (E21).

## Advanced SQL artifacts required (E28)

- Window function computing per-user recency-weighted product affinity.
- MySQL CTE traversing hierarchical `categories` tree (MySQL 8 recursive CTE).
- ClickHouse AggregatingMergeTree for per-segment CTR quantiles.
- Generic Math cosine-similarity function in C# (Vol00 Table 9).
