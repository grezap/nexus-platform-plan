# ADR-0024 — Phase 0.G.0: AOT exit gate raised to ≤30 MB; cluster-adapter framework for the data-tier verb expansion

- **Status**: Accepted
- **Date**: 2026-05-15
- **Deciders**: Greg Zapantis
- **Related**: ADR-0007 (SSH.NET as the managed AOT-compatible SSH driver), ADR-0008 (nexus-cli kafka failover via vmrun + on-broker `kafka-*` CLI shell-out), `feedback_cli_verb_terminology.md` (scale-out vs scale-up), `feedback_demo_playbook_canon.md` (two existing demo systems), `feedback_dry_single_source_of_truth.md`, `feedback_master_plan_authority.md`

## Context

Phase 0.F closed `nexus-cli` `v0.5.0` at **22.75 MB win-x64** AOT — under the master-plan ≤25 MB exit gate (2.25 MB headroom). Phase 0.G expands the data tier with **7 new clusters** (Redis Cluster · MongoDB RS · Percona XtraDB Cluster · PostgreSQL Patroni · ClickHouse · StarRocks · SQL Server FCI/AG) and a paired `nexus-cli` expansion of **13 verb groups** per cluster:

`cluster-status` · `failover-test` · **`scale-out`** add/remove (cluster-membership change) · **`scale-up`** (VM CPU/RAM/disk resize, see `feedback_cli_verb_terminology.md` for the distinction) · `backup` take/restore · `health` · `topology --watch` · `cert-rotate` · `chaos` · `acl` · `demo`.

That is **~91 verb invocations** (13 × 7) over the data tier alone. Each cluster needs a tier-specific adapter — the SSH/native-CLI orchestration pattern that ADR-0008 already proved out for `kafka failover`. Linking 7 cluster adapters into the existing nexus-cli is estimated to add ~3 MB of AOT-reachable code, which would push the binary to **~25-26 MB**, busting the ≤25 MB gate.

Three alternatives considered:

1. **Trim verbs to fit ≤25 MB.** Drops `scale-out` / `backup` / `chaos` / `acl` and the more exotic verbs to make the budget. Violates Greg's "everything is a must" instruction (2026-05-15) and regresses master-plan E29 ("nexus-cli is the operator surface — no raw Terraform for daily ops") on the data tier.

2. **Plugin model — split nexus-cli into a core + per-cluster plugins.** Each cluster adapter ships as a separate AOT binary; the core nexus-cli loads them on demand. **Rejected**: managed-plugin loading is not supported by the .NET 10 AOT toolchain — plugins require JIT or a custom IL-injection path. Drops the single-binary master-plan invariant. A multi-binary AOT scheme is implementable (per-cluster `nexus-redis.exe` etc.) but would force operators to install + path-resolve 8 binaries instead of 1.

3. **Raise the gate to ≤30 MB + adopt an `IClusterAdapter` framework SPI.** Each cluster adapter is a thin SSH-shell-out orchestrator that mirrors ADR-0008's pattern — no managed DB drivers linked. ~150-300 KB per adapter; 7 × ~250 KB + framework boilerplate ≈ ~2-3 MB total. Single binary preserved; full verb coverage; ~3-4 MB of headroom under the new ≤30 MB gate.

## Decision

**Adopt alternative 3.** Phase 0.G's `nexus-cli` AOT exit gate is **≤30 MB** (linux-x64 + win-x64). The `IClusterAdapter` SPI is the framework for cluster-specific verb implementations.

### Framework — `IClusterAdapter` SPI

- **One concrete adapter per cluster**: `RedisAdapter` · `MongoAdapter` · `PerconaAdapter` · `PatroniAdapter` · `ClickHouseAdapter` · `StarRocksAdapter` · `SqlFciAdapter` · `SqlAgAdapter` (+ a `KafkaAdapter` retrofit absorbing the v0.5.0 `kafka failover` logic per ADR-0008).
- Lives in `Nexus.Cli.Core.Adapters.<Cluster>Adapter.cs`; wired via DI in `Nexus.Cli.Composition`.
- Implements `IClusterAdapter`: `Task<TStatus> GetStatusAsync()` · `Task<FailoverResult> FailoverAsync(FailoverRequest)` · `Task<ScaleOutResult> ScaleOutAsync(ScaleOutRequest)` · `Task<HealthReport> HealthAsync()` · `Task<TopologySnapshot> TopologyAsync()` · `Task<BackupResult> BackupAsync(BackupRequest)` · `Task<RestoreResult> RestoreAsync(RestoreRequest)` · `Task<CertRotationResult> RotateCertAsync()` · `Task<ChaosOutcome> ApplyChaosAsync(ChaosScenario)` · `Task<AclSnapshot> AclAsync(AclOperation)`.
- `scale-up` is **generic** — a single `IVmResizer` service (not per-adapter) operates on any VM via vmrun stop → `.vmx` edit → start, with cluster-awareness consulting each adapter's `CanResize(vmName, role) ⇒ bool` to refuse primary resize without `--force-primary`.

### SSH-shell-out invariant (mirrors ADR-0008)

All cluster operations dispatch via SSH.NET 2025.1.0 (already linked, ~11 MB AOT) to on-node native CLIs:

| Cluster | On-node CLI | Auth identity |
|---|---|---|
| Redis | `redis-cli --tls --cacert ... -a $auth` | per-node mTLS client cert (Vault PKI) |
| MongoDB | `mongosh --tls --tlsCAFile ...` | X.509 client cert |
| Percona PXC | `mysql --ssl-mode=VERIFY_CA` + Galera `wsrep_*` queries | mTLS |
| Patroni | `patronictl` + `psql` over `sslmode=verify-full` | mTLS |
| ClickHouse | `clickhouse-client --secure --user ...` | mTLS |
| StarRocks | `mysql --ssl-mode=VERIFY_CA` (FE speaks MySQL wire) | mTLS |
| SQL FCI | `Get-Cluster` / `Move-ClusterGroup` PowerShell on WSFC nodes via SSH-to-Windows | domain auth |
| SQL AG | `sqlcmd -E` + `ALTER AVAILABILITY GROUP ... FAILOVER` | domain auth |

**No managed DB drivers are linked.** Explicitly NOT in `nexus-cli`'s package graph: `StackExchange.Redis` (~5 MB AOT-reachable), `MongoDB.Driver` (~6 MB), `Npgsql`, `MySqlConnector`, `Microsoft.Data.SqlClient`, `ClickHouse.Client`. Adapter authoring discipline: every new adapter PR runs `dotnet publish -c Release -r win-x64 -p:PublishAot=true -p:PublishTrimmed=true` and the trimmer warnings are reviewed; any new package addition gates on AOT-size impact.

### Extended System B JSON demo spec shape

Per the existing `nexus-cli/docs/demos/` convention (`feedback_demo_playbook_canon.md`), the System B JSON spec is extended with **optional** fields:

```json
{
  "id": "DEMO-NN-<cluster>-<verb>",
  "title": "...",
  "description": "...",
  "prerequisites": {
    "vmsAlive": ["..."],
    "envVars": ["NEXUS_SSH_KEY", "VAULT_ADDR", "VAULT_CACERT"]
  },
  "steps": [
    {
      "command": "nexus ...",
      "waitAfterSeconds": 3,
      "expectedExitCode": 0,
      "expectedOutputContains": ["..."],
      "observe": [
        { "where": "stdout",                            "what": "..." },
        { "where": "Grafana panel <name> on obs-metrics", "what": "..." },
        { "where": "Seq query <expression>",            "what": "..." }
      ]
    }
  ],
  "whatProves": "..."
}
```

All five additions are **optional**. The v0.4.0 `JsonDemoCatalog` reader ignores unknown JSON properties — existing `DEMO-01-cluster-status.json` and `DEMO-02-infrastructure.json` keep working. The reader is extended (Phase 0.G.0d) to enforce `expectedExitCode` + `expectedOutputContains` during `nexus demo run <id>` — turning System B demos into self-verifying artifacts.

### AOT gate ≤30 MB

- Applies to Phase 0.G's `v0.6.x` → `v0.7.0` ships.
- Phase 0.F's historical `v0.5.0` ≤25 MB gate stays sealed — that exit was met (22.75 MB observed).
- CI gate: each `release.yml` run validates `dotnet publish -c Release -r {linux-x64,win-x64} -p:PublishAot=true` produces a binary ≤30 MB.
- Each Phase 0.G.N close-out re-measures + records in the verification doc.
- Future raises of the gate require a new ADR (no silent canon drift per `feedback_master_plan_authority.md`).

## Consequences

### Positive

- **Single binary preserved.** No multi-binary deployment, no plugin runtime — the existing "drop one `.exe`, run it" operator story is unchanged.
- **Adapter pattern aligns with proven canon.** ADR-0008 already validated the SSH-shell-out pattern for `kafka failover` (RTOs 13.20 s / 13.57 s observed). The SPI generalises that one-off into a fleet-wide framework.
- **AOT footprint stays predictable.** Each new adapter is a thin orchestrator; no managed-driver explosion. Estimate at v0.7.0: ~26-27 MB (~3-4 MB headroom under the new gate).
- **Demos become self-verifying.** Adding `expectedExitCode` + `expectedOutputContains` to System B specs makes `nexus demo run <id>` double as a verification harness — every failover/scale-out/backup demo is now an executable test.
- **Verb-surface evolution lives in canon.** MASTER-PLAN E29 carries the "nexus-cli is the operator surface" invariant; ADR-0024 carries the gate-raise rationale; per-adapter ADRs in `nexus-cli/docs/adr/` carry the cluster-specific decisions. Three-tier canon, DRY per `feedback_dry_single_source_of_truth.md`.

### Negative

- **MASTER-PLAN exit-gate amendment is a canon change.** This ADR is the formal record per `feedback_master_plan_authority.md` (deviations must be enhancements feeding back to canon). The raise is justified as an enhancement to support the agreed Phase 0.G data-tier scope; no canon-of-fiction posture (the implementation matches the new canon, not vice-versa).
- **SSH dependency on every cluster node.** Every cluster's nodes must run `sshd` reachable from the build host. Already a lab invariant per `feedback_lab_host_reachability.md`, but worth re-asserting: any future cluster posture that hardens SSH off must ship a replacement orchestration surface.
- **Adapters tied to on-node CLI versions.** Cluster CLI argument deprecations (e.g., a future MySQL CLI change to ProxySQL admin syntax) ripple into adapter test breakage. Mitigated by Packer-pinned cluster versions in the new `oltp-node` + `analytics-node` templates.
- **`scale-up` is cluster-aware but generic.** A single `IVmResizer` could mis-resize a primary if the per-cluster `CanResize` check has a bug. Mitigation: every adapter ships `CanResize` unit tests with explicit "primary refused" + "replica allowed" cases.

### Neutral

- **Plugin model deferred, not rejected.** If Phase 0.L (Spark) or Phase 1+ (apps) push nexus-cli past ~35 MB, a plugin model becomes the natural next architectural step. The `IClusterAdapter` SPI is already plugin-ready — each adapter is a self-contained type that could be loaded from a separate assembly with minimal refactoring.
- **Matches ADR-0008 + ADR-0007 lineage.** ADR-0007 picked SSH.NET (managed, AOT-compatible) over `ssh.exe` shell-out or native `libssh`; ADR-0008 picked vmrun + on-broker CLI shell-out for kafka failover. ADR-0024 generalises both into a framework — no architectural shift, just a sizing recalibration + SPI formalisation.
- **Demo extension is backwards-compatible.** Existing 2 System B specs keep working; the new fields are opt-in.

## Verification

- **AOT gate check (CI):** `dotnet publish -c Release -r {linux-x64,win-x64} -p:PublishAot=true` produces a binary ≤30 MB. Fails the release pipeline if exceeded.
- **Adapter architecture (NetArchTest):** every concrete `*Adapter` implements `IClusterAdapter`; no `*Adapter` references a managed-driver type (`StackExchange.Redis`, `MongoDB.Driver`, `Npgsql`, `MySqlConnector`, `Microsoft.Data.SqlClient`, `ClickHouse.Client`).
- **Per-cluster live verification:** each Phase 0.G.N close-out records measured RTOs/throughputs in `nexus-cli/docs/verification/0.G.N-<cluster>.md` against the master-plan §5.3 budget table.
- **System B reader extension (unit):** `JsonDemoCatalog` reads the new fields when present, ignores when absent, and `DemoRunner` asserts `expectedExitCode` + `expectedOutputContains` per step during `demo run`.

## References

- ADR-0007 — SSH.NET as the managed AOT-compatible SSH driver
- ADR-0008 — `kafka failover` via vmrun + on-broker `kafka-*` CLI shell-out (the canonical example of the SSH-shell-out pattern this ADR generalises)
- MASTER-PLAN.md §4 — Phase 0.F + Phase 0.G rows (the canonical Source of the gate values)
- `feedback_cli_verb_terminology.md` — `scale-out` vs `scale-up` definitions
- `feedback_demo_playbook_canon.md` — the two existing demo systems (System A scenarios + System B verb specs)
- `feedback_master_plan_authority.md` — canon-change discipline (this ADR conforms)
- `feedback_dry_single_source_of_truth.md` — single canonical home per fact (this ADR is the single home for the gate-amendment rationale)
