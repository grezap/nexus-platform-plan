# DEMO-04 · Ask LocalMind about your own portfolio

## 1. What this shows

A chat against the `localmind` OpenAI-compatible gateway answers a question about NexusPlatform itself — the corpus is the Volume docs and this meta-repo — returning a grounded answer with citations. Target persona: AI-forward.

## 2. Runtime + prerequisites

- **Environment target** — `ml` (minimal subset)
- **VMs required** — dc-nexus, vault-1, mongo-1/2/3, pg-primary (pgvector), redis-1, localmind svc on swarm-manager-1, obs-*
- **External services** — Ollama endpoint, MongoDB `localmind.conversations`, PG `embeddings` schema with pgvector HNSW
- **Seed data** — ingest the 14 Volume txt files via `nexus-cli localmind ingest --corpus=volumes`
- **Expected duration** — 5 min
- **Reset command** — `nexus-cli demo run DEMO-04 --reset` clears conversation history only.

## 3. Architecture snapshot

*Filled in when the project ships.*

## 4. Step-by-step script

- CLI issues an OpenAI-compatible chat completion: "Explain how DataFlow Studio handles CDC."
- Gateway classifies intent as RAG-eligible.
- Retrieval runs pgvector HNSW query; top-8 chunks returned with cosine scores.
- Reranker trims to 4.
- LLM composes answer with inline `[Vol01:§3]` citations.
- Answer streamed via SSE; CLI renders incrementally.
- Click any citation → browser opens the Volume page at the anchor.

## 5. Observability trail

- **Grafana** — dashboard `localmind-rag` · panels `retrieval p95`, `tokens/sec`, `cache hit rate`
- **Jaeger** — service `localmind.gateway`; trace depth 9 (classify → embed → retrieve → rerank → generate)
- **Seq** — query `Service = 'localmind' AND ConversationId = '{id}'`
- **URLs** — `http://obs-metrics.nexus.local:3000/d/localmind-rag`

## 6. Code pointers

*Filled in when the project ships.*

## 7. Variations

*Filled in when the project ships.*

## 8. Troubleshooting

*Filled in when the project ships.*

## 9. What this proves

- **.NET engineering + architecture** — Clean Architecture, SSE streaming via IAsyncEnumerable, Named Pipes Windows service variant.
- **Advanced SQL + analytics** — pgvector HNSW tuning, Mongo aggregation pipelines for history search.
- **Python** — embedding ingest pipeline, evaluation harness on golden Q&A set.
- **DevOps** — Ollama model registry, Vault-issued API keys with rotation.
