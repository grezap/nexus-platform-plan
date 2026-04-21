# pulsenlp — Schemas

## Ownership

| Store | Database / schema | Role |
|---|---|---|
| PostgreSQL Patroni | `pulsenlp_registry` | Model registry + training corpus metadata |
| ClickHouse | `pulsenlp_analytics` | Per-document inference analytics |
| StarRocks | `dwh.nlp_marts` | Training set materializations (Spark offline features) |

**Migration tool:** FluentMigrator (PostgreSQL) + DbUp (ClickHouse, StarRocks).
**Status:** DDL planned, authoring begins in Phase 5.

## PostgreSQL — `pulsenlp_registry`

| Table | Description |
|---|---|
| `models` | Model family — sentiment, ner, classifier. |
| `model_versions` | Specific trained version; ONNX blob path, opset, tokenizer hash. |
| `training_corpora` | Versioned training datasets — e.g., `financial_news_sentiment_v3`. |
| `training_runs` | Per-run metadata — duration, hyperparameters, metrics. |
| `evaluations` | Held-out evaluation metrics per version (F1, precision, recall, BLEU where applicable). |
| `label_schemas` | NER tag schemas (PER/ORG/LOC/MONEY/DATE/...) with per-project overrides. |
| `deployment_history` | Which version served which tenant when. |

## ClickHouse — `pulsenlp_analytics`

| Table | Description |
|---|---|
| `documents_local` | ReplicatedMergeTree — per-document inference record. |
| `documents` | Distributed. |
| `tokens_local` | Token-level outputs where applicable (NER spans). |
| `sentiment_predictions` | Confidence, label, latency per document. |
| `ner_predictions` | Entity span, type, confidence. |
| `classifier_predictions` | Multi-class output with top-3 probabilities. |
| `inference_latency_mv` | Rolling p50/p95/p99 per model_version per hour. |

## StarRocks — `dwh.nlp_marts`

Labeled training-set snapshots. Versioned by hash. Consumed by Spark training jobs (E21).

## Advanced SQL artifacts required (E28)

- `unnest()` on ClickHouse array columns holding NER spans.
- Window function computing per-model rolling F1 vs ground truth.
- PostgreSQL range types for model version lifecycle (`tstzrange` of serving window).
