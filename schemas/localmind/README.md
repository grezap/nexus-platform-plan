# localmind — Schemas

## Ownership

| Store | Database / schema | Role |
|---|---|---|
| MongoDB RS | `localmind` | Conversations, messages (document model), templates |
| PostgreSQL Patroni | `localmind_rag` | **pgvector** — document chunks + embeddings (RAG v0.1, E30) |
| ClickHouse | `localmind_analytics` | LLM usage events, token accounting, latency |
| Redis Cluster | — | Rate limiting, API-key resolution cache, session state |

**Migration tool:** FluentMigrator (PostgreSQL) + DbUp (ClickHouse). MongoDB managed via typed `IMongoCollection<T>` index initializers.
**Status:** DDL planned, authoring begins in Phase 4. **RAG ships in v0.1 (E30 decision).**

## MongoDB — `localmind`

| Collection | Description |
|---|---|
| `conversations` | Conversation root document — id, tenantId, userId, model, createdUtc, status. |
| `messages` | Per-message records within a conversation (role, content, tokenCount, latencyMs, finishReason). |
| `templates` | Prompt templates with variables (Handlebars); versioned; watched via change streams. |
| `template_bindings` | Which tenant/app binds which template (overrides, A/B). |
| `api_keys` | Tenant-scoped API keys; hashed; rate-limit policies attached. |
| `tenant_settings` | Per-tenant model preferences, token caps, allowed providers. |
| `feedback` | Thumbs-up/down on messages; links to conversations + messages. |
| `audit_events` | Admin operations — key issued/revoked, template changed. |

## PostgreSQL — `localmind_rag` (pgvector)

| Table | Description |
|---|---|
| `documents` | Uploaded source docs — id, tenantId, title, mimeType, sha256, bytes, sourceUri. |
| `document_versions` | Version history per document (re-ingested when source changes). |
| `chunks` | Semantic-chunked content; parent document_version, ordinal, text, tokenCount. |
| `chunk_embeddings` | **`vector(384)`** column — bge-small-en ONNX embeddings; HNSW index. |
| `ingestion_jobs` | Background jobs that chunked + embedded a document; metrics. |
| `retrieval_logs` | Every query's top-K retrieval trace — for RAG evaluation (RAGAS metrics). |
| `evaluations` | Run-level RAGAS scores (faithfulness, answer relevance, context precision/recall). |
| `rerank_logs` | bge-reranker-base score deltas per retrieval. |

## ClickHouse — `localmind_analytics`

| Table | Description |
|---|---|
| `llm_events_local` | Per-inference record — tenantId, model, tokensIn, tokensOut, latencyMs, cached. |
| `llm_events` | Distributed view. |
| `token_usage_hourly_mv` | AggregatingMergeTree MV — cost/token accounting. |
| `retrieval_quality_mv` | Rolling RAG metrics surface for Grafana. |

## Advanced SQL artifacts required (E28)

- pgvector HNSW index (`USING hnsw (embedding vector_cosine_ops)`).
- Hybrid search: pgvector similarity × BM25 `tsvector` rank (PostgreSQL full-text).
- ClickHouse quantileTDigest for latency percentiles.
- MongoDB aggregation pipeline with `$graphLookup` on conversation message threads.

## RAG v0.1 pipeline (E30 detail)

1. Upload → chunker (Microsoft.ML.Tokenizers, semantic split) → embedder (bge-small-en ONNX) → pgvector insert.
2. Query → query-embed → top-K HNSW search → reranker (bge-reranker-base ONNX) → Semantic Kernel memory store → LLM response.
3. Evaluation harness → RAGAS metrics in `evaluations` table → Grafana panel via ClickHouse MV.
