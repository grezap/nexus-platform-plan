# Changelog

All notable changes to this repository will be documented in this file.
The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — 2026-04-20 — "Plan"

Initial canon publication. No implementation — planning artifacts only.

### Added

- `MASTER-PLAN.md` — 14 projects, 30 enhancements (E1–E30), 12 build phases, acceptance gates.
- `docs/start-here.md` — non-technical entry point with demo scenario cards.
- `docs/skills-coverage.md` — 4-dimension skill matrix per project.
- `docs/demos/` — 14 demo playbook stubs (DEMO-01 … DEMO-14), playbook template, auto-recording spec.
- `docs/demo-data/README.md` — synthetic seed data kit specification.
- `docs/adr/index.md` — ~75 planned ADRs catalogued with owners and status.
- `docs/infra/vms.yaml` — ~65-VM inventory with IPs, VMnets, host directories, roles.
- `docs/infra/network.md` — VMnet20 (Host-Only 192.168.10.0/24) + VMnet21 (NAT 192.168.70.0/24) canon.
- `schemas/` — 14 project subdirectories seeded with DDL skeletons.

### Canon decisions locked

- Migration tool: **FluentMigrator** (SQL stores) + **DbUp** (analytical).
- Native AOT paths: **Dapper + FluentMigrator**; non-AOT: EF Core permitted.
- Terraform VMware provider: `vmware/vmware-desktop` + `vmrun` fallback.
- Workflow orchestrator: **Prefect 3** (OSS self-host).
- Lakehouse table format: **Apache Iceberg**.
- Object store: **MinIO**.
- Transformation layer: **dbt Core** (adapters: starrocks, clickhouse).
- Notebooks: **JupyterHub**.
- Private registry: **Harbor**.
- Long-term metrics: **VictoriaMetrics**.
- Alerting: **Alertmanager** + Karma UI.
- Feature flags: **Unleash** (self-host).
- Data lineage: **OpenLineage** + **Marquez**.
- Service catalog (optional): **Backstage**.
- Testing: xUnit + Testcontainers + PactNet + NetArchTest + Stryker.NET + Verify.Xunit + WireMock.Net.
- Load testing: **NBomber**.
- Python toolchain: **uv** + **Ruff** + **mypy --strict** + **Pydantic v2** + **Polars**.
- RAG (LocalMind v0.1): **pgvector** on PostgreSQL Patroni + local ONNX embeddings (bge-small-en).
