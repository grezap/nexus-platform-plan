# Changelog

All notable changes to this repository will be documented in this file.
The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added — Phase 0.O Vitess-sharded MySQL tier SEALED (2026-06-03)

- **New repo `nexus-infra-vitess` SEALED — `v0.1.0`.** The **relational (MySQL) horizontal-sharding** showcase, distinct from PXC/Galera *synchronous replication* (0.G.3). 12 VMs on tier `07-vitess`: 3 etcd topo (`vitess-etcd-1/2/3` @ `.190`-`.192`) + 1 control (`vitess-control-1` @ `.193`, vtctld + VTOrc) + 2 vtgate routers (`vitess-vtgate-1/2` @ `.194`/`.195`, round-robin DNS `vtgate.nexus.lab`, MySQL `:15306`, no VIP per ADR-0031) + shard `-80` (`vitess-shard1-tablet-1/2/3` @ `.196`-`.198`) + shard `80-` (`vitess-shard2-tablet-1/2/3` @ `.199`-`.201`). Engine = **Percona Server 8.4 LTS** tablets + **Vitess v24.0.1** (vtgate/vttablet/vtctld/VTOrc) + **etcd 3.5.16** topo. Keyspace `commerce`, 2 shards on a **hash vindex**. **Full Vault-PKI mTLS** on every gRPC channel + the mysqld wire + the vtgate MySQL listener. Live-ratified **and cold-rebuild-proven** (`smoke-0.O.ps1` **71/71 GREEN** both times); proven hash-vindex sharding (100 rows split 53/47 across both shards via one vtgate insert) + VTOrc auto-reparent-on-primary-kill (~15s).
- **[ADR-0041](docs/adr/ADR-0041-vitess-sharded-mysql-cluster.md)** — Vitess-sharded MySQL cluster topology (12 VMs, 2 shards × 3 tablets, hash vindex, full mTLS); already in `docs/adr/index.md`.
- **MASTER-PLAN.md** `0.O` row flipped to SEALED (topology + smoke 71/71 + fleet `119 → 131`); `I6` repo row marked SEALED `v0.1.0`; §5.3 fleet count `107 → 131`. **`docs/infra/vms.yaml`** — vitess cluster marked BUILT/SEALED; `vm_count: 131` (re-derived: 136 node rows − 5 unbuilt). **`docs/infra/network.md`** — `07-vitess` tier IP allocations (`.190`-`.201`) + the `:CB`-`:D6` MAC reservation sub-table (high-water `D6`). **`docs/glossary.md` §4** — 6 new entries: **vtgate**, **vttablet**, **vtctld**, **VTOrc**, **keyspace**, **vindex**. **`docs/demos/DEMO-21.md`** — System A persona demo (kill a shard primary → VTOrc auto-reparents); System B `demo-0.O-*` JSON demos (DEMO-24/25/26).

### Added — Phase 0.L COMPLETE 2026-05-26 — 3 repo releases tagged at close-out (0.L.6)

Phase 0.L (lakehouse + registry + analytics extension) is fully closed. All 5 sub-phases (0.L.1 MinIO · 0.L.2 Iceberg/Nessie + PG HA · 0.L.3 Spark HA · 0.L.4 Harbor HA · 0.L.5 StarRocks shared-data) live-ratified + cold-rebuild-proven (smoke gates 41/41 + 28/28 + 28/28 + 41/41 + 69/69 GREEN). 3 repos tagged simultaneously at the 0.L.6 close-out:

- `nexus-infra-lakehouse` **`v0.1.0`** — lakehouse tier (`08-spark`, 16 VMs): MinIO + Iceberg/Nessie + Spark HA. Covers 0.L.1-0.L.3 + the 0.L.5 cross-tier MinIO tenant for SR-SD.
- `nexus-infra-registry` **`v0.1.0`** — registry tier (`09-platform`, 4 VMs + VIP): HA Harbor.
- `nexus-infra-analytics` **`v0.2.0`** — analytics tier (`04-analytics`, 20 VMs) extended with the second StarRocks cluster (shared-data, ADR-0037).

Total: 5 ADRs (0033-0037), 1 new System A demo (DEMO-18), 32 apply-time transients diagnosed + fixed in source across the phase (handbook §3 chronologies in 3 repos). Fleet 78 → **93** VMs (lakehouse +16, registry +4, analytics-extension +5; vms.yaml `vm_count: 93`). **Next: Phase 0.I observability** — Prometheus + Grafana + Loki + Tempo + Jaeger; the last infrastructure phase before applications.

### Added — Phase 0.L.5 StarRocks shared-data tier SEALED (2026-05-26)

- **Second StarRocks cluster SEALED — running parallel to the sealed shared-nothing one.** `nexus-infra-analytics` extended (not a new repo) with a 5-VM cluster on `run_mode=shared_data`: 3 FE BDB-JE quorum (`sr-sd-fe-1/2/3` at `.37`/`.38`/`.39`) + 2 stateless **Compute Nodes** (`sr-sd-cn-1` at `.30`, `sr-sd-cn-2` at `.40` — documented decade-spill from SR `.3x` to first free ClickHouse-decade slot `.40`). Internal cloud-native tables in a MinIO storage volume `nexus_minio_starrocks` → `s3://starrocks/`. Tier `04-analytics` now **20 VMs**. Live-ratified + **cold-rebuild proven** (`smoke-0.L.5.ps1` **69/69 GREEN** with chaos default-on: CN-loss → query still returns full results from shared MinIO; FE-leader-loss → re-election). 5 apply-time transients fixed in source (handbook §3.C): MinIO agent KV-policy v1→v2 gap for new tenants · VMware DHCP-service-stopped on the build host · PowerShell backtick+`.Method` ParserError · `SHOW STORAGE VOLUMES` returns name-only (use `DESC` + `awk`) · StarRocks shared-data `tablet_create_timeout_second=10s` too short for first S3 write.
- **[ADR-0037](docs/adr/ADR-0037-starrocks-shared-data-cn-minio-storage-volume.md)** — shared-data tier topology + MinIO storage volume (amends ADR-0030); three either/or decisions sealed with Greg (dedicated `nexus-starrocks-app` MinIO identity over reusing `nexus-lakehouse-app`; two new dedicated Packer templates over reusing the sealed FE template; chaos-by-default in `smoke-0.L.5`). New entry in `docs/adr/index.md`.
- **MASTER-PLAN.md** `0.L` row updated to `0.L.5 SEALED 2026-05-26` (3 FE + 2 CN topology, MinIO storage volume, ADR-0037, fleet 88 → **93**). **`docs/infra/vms.yaml`** — new cluster `starrocks-sd` (5 rows: FE 3 GB, CN 4 GB per ADR-0037 sizing); `vm_count: 93`. **`docs/infra/network.md`** — adds `starrocks-sd-fe.nexus.lab` round-robin DNS + the `:A5`-`:A9` MAC sub-table (analytics tier 15 → 20). **`docs/glossary.md`** — three new entries: "Shared-data mode (StarRocks `run_mode=shared_data`)", "Compute Node (StarRocks CN)", "Storage volume (StarRocks)". **`docs/demos/DEMO-18.md`** — new System A persona demo (storage-compute separation; explicit DEMO-15 ↔ DEMO-18 compare-and-contrast table). **`docs/setup-guides.md`** — inventory + per-tier replay matrix updated with `analytics-starrocks-sd` row.

### Added — Phase 0.L.4 Harbor registry HA SEALED (2026-05-25)

- **New tier `09-platform` (`nexus-infra-registry`) — HA Harbor SEALED.** Live-ratified + cold-rebuild-proven (`smoke-0.L.4.ps1` 41/41 GREEN; 7 apply-time transients fixed in source). 2 stateless Harbor app nodes (`registry-1/2`, round-robin DNS `registry.nexus.lab`, ADR-0031) + a dedicated PostgreSQL 17 + Redis master-replica HA datastore (`registry-pg-1/2`, keepalived VRRP VIP `registry-db.nexus.lab .119`); **image blobs in MinIO S3** (the 0.L.1 object store); Trivy scanning + cosign signing; **Vault OIDC SSO** (Vault `identity/oidc` provider → AD via auth/ldap). mTLS via per-host Vault PKI; Harbor 2.14.4 offline installer.
- **[ADR-0036](docs/adr/ADR-0036-harbor-registry-ha.md)** — registry HA topology (the HA+bundled-datastore contradiction resolved to a dedicated registry-tier PG/Redis HA pair) + ADR index row.
- **MASTER-PLAN.md** `0.L` row + **`docs/infra/vms.yaml`** (registry tier 4 VMs, vm_count 78→82, registry-1 disk 400→80, future platform tools shifted to `.125`-`.128`) + **`docs/infra/network.md`** (registry IP plan `.115`-`.119`, MACs `A4`/`AF`/`B0`/`B1`, DNS round-robin + VIP) + **`docs/glossary.md`** (Harbor/Trivy/cosign expanded for HA, `.local`→`.lab` fix) + **`docs/setup-guides.md`** (analytics/lakehouse/registry tiers + replay rows; total 82) + **`docs/demos/`** (DEMO-17 registry + DEMO-16 lakehouse backfill).

### Added — Phase 0.G.7 SQL Server FCI + Always On AG LIVE-RATIFIED (2026-05-22)

- **OLTP tier SEALED 5/5 — SQL Server FCI + AG live-ratified.** 4 ws2025-desktop nodes: a 2-node WSFC Failover Cluster Instance (`sqlfci` @ `.70.16`, sharing an iSCSI LUN from `nexus-gateway` as a clustered Physical Disk) + 2 standalone Always On AG async replicas (`sql-ag-rep-1/2`). AG `nexus-ag` = FCI primary + both replicas SYNCHRONIZING + HEALTHY (`nexus_demo` MANUAL-seeded); AG Listener `sql-ag-listener` @ `.70.17` proven under strict TLS (remote domain client `sqlcmd -E -N` → primary). `smoke-0.G.7.ps1` **ALL GREEN 56/56**.
- **MASTER-PLAN.md** — `0.G.7` row flipped to LIVE-RATIFIED; exit-gate corrected (FCI virtual name `sqlfci` not `sql-fci-cluster`; iSCSI LUN is a clustered Physical Disk not a CSV).
- **`docs/infra/vms.yaml`** — `oltp_tier_status` → SEALED 2026-05-22 (5/5 LIVE); sqlserver `phase` → LIVE-RATIFIED; FCI virtual name + Physical-Disk + MANUAL-seeding corrections.
- **`docs/infra/network.md`** — FCI `.70.16` client connection string corrected to `sqlfci.nexus.lab` (distinct from the WSFC CNO `sql-fci-cluster` @ `.15`).
- 40+ ratification transients root-caused + fixed in source (nexus-infra-oltp handbook §3.5b + §3.5c). Key cold-rebuild fixes: `@@SERVERNAME` Packer-bake pinning (sp_dropserver/sp_addserver); MANUAL AG seeding (FCI `S:\` vs replica `C:\`); build-host PFX issuance (ws2025-desktop has no openssl) + CA-chain import; Kerberos SPN registration for the FCI + Listener virtual names; `sqlserver-server` PKI role gained `sqlfci`.

### Added — Phase 0.G.1 + 0.G.2 + 0.G.3 + 0.G.3.5 canonization (2026-05-18)

- **MASTER-PLAN.md** — the single `0.G` row expanded with sub-phase rows `0.G.1` (6-node Redis Cluster mTLS), `0.G.2` (3-node MongoDB Replica Set mTLS + keyFile internal auth), `0.G.3` (3 PXC + 2 ProxySQL + VRRP VIP `192.168.70.50`), `0.G.3.5` (architectural refactor — per-cluster Terraform state + per-engine Packer template). 0.G.3.5 was born from the 0.G.3 monolithic ratification's 16-transient stall: the 30-min full-tree iteration loop made root-causing each transient too expensive. The refactor split `packer/oltp-node/` into 4 per-engine templates + `terraform/envs/oltp/` into 3 per-cluster states + per-cluster nftables overlays + per-cluster operator scripts. Iteration loop shrunk from ~30 min monolithic → ~5-10 min per cluster. 27 distinct transients root-caused + permanently fixed across the two ratifications (16 monolithic + 11 refactor); the long-unsolved Galera SST joiner sync (transient #16) was root-caused to two compounding bugs: PXC 8.0 moved `wsrep_sst_auth` from [mysqld] → [sst]; chunk 3b wsrep.cnf render lacked trailing newline so chunk 3c step 6's `echo '!include' \| tee -a` concatenated into `pxc-encrypt-cluster-traffic = ON!include sst-auth.cnf` single garbage line. Phase 0 total line updated.
- **`docs/glossary.md` §4** — Percona XtraDB Cluster entry expanded with 0.G.3 specifics (PXC 8.0.45-36.1, WSREP 26.1.4.3, Galera SST/IST over VMnet10 backplane, mTLS-only :3306 via per-host Vault PKI). 4 NEW entries: **Galera (wsrep)** with the 0.G.3 lessons (wsrep_sst_auth section change + newline handling); **ProxySQL** (galera_hostgroups + 2-node pair fronting PXC + admin :6032 / frontend :6033); **keepalived (VRRP)** with the unicast-mandatory lesson (VMware Workstation VMnet11 doesn't reliably forward IPv4 multicast `224.0.0.18`; multicast VRRP causes split-brain).
- **README.md** — Phase 0 status bumped from `~65% complete` → `~75% complete` (4 of 5 infra repos live + cold-rebuildable); Phases closed list extended with 0.G.1-0.G.3 + 0.G.3.5; NEW `nexus-infra-oltp` repo entry under "Related repos" with the 14-VM scope + the 0.G.3.5 architectural-refactor narrative + the 27-transient summary; "Next" line updated to reflect 0.G.4 + 0.G.7 + cluster framework as the remaining 0.G work.

The canonical rule born from 0.G.3.5 ("multi-cluster infrastructure tiers MUST default to per-cluster Terraform state + per-engine Packer template") applies forward to 0.G.4+ (Patroni), 0.G.5+ (analytics), 0.G.7 (SQL FCI/AG), 0.I (observability), 0.L (Spark + Harbor). Recorded in private memory `feedback_per_cluster_state_per_engine_template.md`.

### Added — Phase 0.G.0 pre-flight canon (2026-05-15)

- **MASTER-PLAN.md** — Phase 0.G row expanded from the `1 wk` placeholder to reflect the agreed scope: two new infra repos (`nexus-infra-oltp` + `nexus-infra-analytics`), 40 new VMs across tiers `02-sqlserver` + `04-analytics` + `05-oltp`, the `nexus-cli` `IClusterAdapter` framework SPI, and 13 verb groups per cluster (`cluster-status` · `failover-test` · **`scale-out`** add/remove · **`scale-up`** · `backup` · `health` · `topology --watch` · `cert-rotate` · `chaos` · `acl` · `demo`). AOT exit gate **raised from ≤25 MB to ≤30 MB** for Phase 0.G's `v0.6.x → v0.7.0` ships; the Phase 0.F historical `v0.5.0` ≤25 MB gate stays sealed. Sub-phase rows (`0.G.1`-`0.G.8`) will be added at Phase 0.G close-out, mirroring the 0.E.5 + 0.H.6 expansion pattern.
- **ADR-0024** — *Phase 0.G.0: AOT exit gate raised to ≤30 MB; cluster-adapter framework for the data-tier verb expansion* — formalises the gate change rationale (full data-tier verb coverage at ~3 MB adapter cost; plugin model rejected as not AOT-friendly; trim-to-fit rejected as regressing master-plan E29), the `IClusterAdapter` SPI for one-adapter-per-cluster decomposition, the SSH-shell-out invariant for AOT-friendly footprint (mirrors ADR-0008), and the extended System B JSON demo spec shape (optional `prerequisites` / `expectedExitCode` / `expectedOutputContains` / `observe[]` / `whatProves` fields for self-verifying demos).
- **`docs/adr/index.md`** — registers ADR-0024 (row inserted between 0023 and the licensing 0144 entry).

### Added — Phase 0.H canonization (2026-05-15)

- **MASTER-PLAN.md** — the single `0.H` row expanded into sub-phase rows `0.H.1`-`0.H.6` (mirroring the 0.D / 0.E expansion); the Phase 0 total line notes Phase 0.H complete + `nexus-infra-kafka` tagged `v0.1.0`.
- **`docs/infra/vms.yaml`** — the `03-kafka` tier ratified: all 15 VMs run at the `kafka-node` template's baked 8 GB (`modules/vm`'s `memory_mb` resize is reserved-not-applied; the lighter per-role sizing is retained as a tracked future enhancement); `ksqldb-2`'s VMnet11 IP typo `.99` → `.98` fixed; `phase:` fields list the sub-phases.
- **`docs/glossary.md` §5** — extended for the **Confluent REST Proxy** + a fuller **MirrorMaker 2** entry (dedicated mode, source-alias prefix). The "In NexusPlatform" line updated to reflect the 15-VM Kafka tier as Phase 0.H.
- **ADR-0020** — *Phase 0.H.1: KRaft combined broker+controller mode for the Kafka tier* — combined-mode 3-node clusters (`process.roles=broker,controller`), no ZooKeeper VMs, per-cluster cluster-UUID minted at Terraform time.
- **ADR-0021** — *Phase 0.H.2-0.H.5: Kafka-tier mTLS — Vault PKI PEM keystores, PKCS#1→PKCS#8, and the Confluent PEM/PKCS#12 listener split* — per-node Vault Agent + `kafka-tls-split.sh` (PKCS#1→#8 conversion via `openssl pkcs8 -topk8`, PEM pair + `keytool`-built PKCS#12 pair); brokers / Kafka clients / Schema Registry / REST Proxy use PEM; Connect / ksqlDB HTTPS listeners use PKCS#12 (their REST servers reject PEM).
- **ADR-0022** — *Phase 0.H.3-0.H.4: Terraform overlay ordering via `depends_on`, never upstream resource `.id` triggers* — formalises the "id-trigger cascade anti-pattern" as a fleet-wide overlay-pattern rule: `triggers` key only on the overlay's own inputs; ordering via `depends_on`; overlays must be individually re-runnable + idempotent.
- **ADR-0023** — *Phase 0.H.5: MirrorMaker 2 dedicated mode, one replication flow per node* — `connect-mirror-maker` dedicated mode (not on the 0.H.4 Connect cluster — isolates DR from CDC); one flow per node (`mm2-1` east→west, `mm2-2` west→east); systemd drop-in appends `--clusters <target>` to the baked ExecStart; embedded Connect REST left off; per-cluster `<alias>.ssl.*` auto-cascades to producer/consumer/admin.
- **`docs/adr/index.md`** — six new shared-ADR rows added (0019-0023) including a previously-missing **ADR-0019** index entry.

### Added — Phase 0.E canonization (2026-05-08)

- **MASTER-PLAN.md** — the single `0.E` row expanded into sub-phase rows `0.E.1`-`0.E.5`; the Phase 0 total line notes Phase 0.E complete + `nexus-infra-swarm-nomad` tagged `v0.2.0`.
- **`docs/infra/vms.yaml`** — the `06-orchestration` tier RAM-ratified (managers 6 GB / workers 4 GB observed-sufficient deviations from the original 8 GB across-the-board canon); `nexus-gateway` acquired the NFS server role for Portainer state continuity.
- **`docs/glossary.md`** — extended for Docker / Docker Swarm / HashiCorp Nomad / HashiCorp Consul / Portainer CE.
- **ADRs 0011-0019** cover Phase 0.D + 0.E architectural decisions: Vault HA (0011) · PKI hierarchy (0012) · LDAPS search-then-bind (0013) · foundation creds via AppRole + KV (0014) · Transit auto-unseal + Vault Agent on member servers (0015) · Nomad-Vault legacy periodic token (0016) · Portainer CE single-replica + NFS-via-gateway (0017) · nftables `flush ruleset` + Docker iptables-nft conflict (0018) · TLS full-chain on the wire + `inet filter forward` accept rules (0019).

### Added — Phase 0.D.5 canonization (2026-05-03)

- **ADR-0015** (`docs/adr/ADR-0015-transit-auto-unseal-and-agent.md`) — Phase 0.D.5
  groups five orthogonal posture tightenings: (5.1) `MinPasswordLength=14` +
  KV-managed AD-cred rotation overlay (Administrator + nexusadmin synced
  from KV; DSRM deferred to manual ops per Server 2025 SSH console-mode
  limit); (5.2) leaf cert TTL `8760h → 2160h` (90 d) for Vault listeners +
  dc-nexus LDAPS, with rotate-listener probe gaining a span-check that
  catches TTL changes on existing certs; (5.3) GMSA scaffolding (KDS root
  key probe-only -- Add-KdsRootKey on Server 2025 returns ERROR_NOT_SUPPORTED
  under SSH; manual RDP/console ops -- plus `nexus-gmsa-consumers` AD group
  + sample GMSA `gmsa-nexus-demo$`); (5.4) Vault Agent on dc-nexus +
  nexus-jumpbox via per-host narrow AppRoles + creds JSON sidecars; (5.5)
  Transit auto-unseal via new single-node `vault-transit` companion VM
  (greenfield re-cluster operator-driven; code-complete, apply pending).

- **`docs/infra/vms.yaml`** — `vault-transit` row added to the foundation
  cluster (192.168.10.124 / 192.168.70.124, MAC `00:50:56:3F:00:43`, own
  subdir `01-foundation/vault-transit/` per `feedback_vmware_per_vm_folders.md`).

- **`docs/adr/index.md`** — registers ADR-0015.

### Added — Phase 0.D sub-phase canonization (2026-05-02 housekeeping batch)

- **`MASTER-PLAN.md` Phase 0.D expanded** from a one-week monolith to 5
  named sub-phases (0.D.1–0.D.5) with explicit exit gates per sub-phase.
  The original 1-week allocation in §4 stays neutral — 0.D.1 through 0.D.4
  are already shipped within the original window; 0.D.5 (Transit
  auto-unseal + GMSA + Vault Agent + leaf-TTL drop to 90 d) lands in the
  remaining slack. Acceptance criterion line updated to
  `vault kv get nexus/foundation/dc-nexus/dsrm` (the 0.D.4 deliverable
  shape) — the original `nexus/sqlserver/oltpdb` path lands when 0.E or
  the data env writes DB creds.

- **ADR-0011** (`docs/adr/ADR-0011-vault-3-node-raft.md`) — 3-node Vault
  Raft cluster on integrated Raft storage (no Consul dependency, since
  Consul is canonically Phase 0.E). Dual-NIC topology (VMnet11 service
  .121–.123 via dnsmasq dhcp-host MAC reservations; VMnet10 cluster
  backplane 192.168.10.121-.123). Init JSON to `$HOME\.nexus\vault-init.json`
  (mode 0600 via icacls), NOT in tfstate. KV-v2 mount at `nexus/`.
  Userpass + AppRole at post-init. Approved RAM deviation: 2 GB per node
  (vms.yaml originally said 4 GB; vms.yaml updated in this batch to match
  observed sufficient sizing).

- **ADR-0012** (`docs/adr/ADR-0012-vault-pki-hierarchy.md`) — two-tier PKI:
  `pki/` root CA (10 y, signs only the intermediate) + `pki_int/`
  intermediate (5 y) + `vault-server` PKI role (1 y leaf TTL,
  `allow_ip_sans=true`). Per-node listener cert reissue with atomic-swap
  + SIGHUP reload (zero-downtime). Root CA distributed to build host's
  `$HOME\.nexus\vault-ca-bundle.crt` + every Vault node's system trust
  store. Operator drops `VAULT_SKIP_VERIFY` and sets `VAULT_CACERT`
  pointing at the bundle. Legacy 0.D.1 trust shuffle retired.

- **ADR-0013** (`docs/adr/ADR-0013-vault-ldaps-search-then-bind.md`) —
  LDAPS pulled forward from 0.D.5 to 0.D.3 (mid-phase deviation, ratified
  via Canon mapping table) because plain LDAP/389 simple bind fails
  wholesale in this AD env regardless of `LDAPServerIntegrity` (tested
  values 2/1/0 — all reject). LDAPS leaf cert issued from `pki_int/issue/
  vault-server` for `dc-nexus.nexus.lab`, installed in
  `LocalMachine\My`, NTDS restarted. Vault auth/ldap = LDAPS,
  search-then-bind, **`upndomain=""`** (Vault issue #27276 — `upndomain`
  silently rewrites `{{.Username}}` in userfilter, breaking AD's
  `sAMAccountName` semantics). `secrets/ldap` (`schema=ad`,
  `password_policy=nexus-ad-rotated`) replaces deprecated `ad` engine.
  Static rotate-role for `svc-demo-rotated` rotates the AD password
  daily. AD-side bind account holds 4 ACEs on `OU=ServiceAccounts`
  (Reset Password, Change Password, RP/WP `userAccountControl`),
  delegated via `dsacls /I:S` — never via Account Operators shortcut.

- **ADR-0014** (`docs/adr/ADR-0014-foundation-creds-via-approle-kv.md`) —
  Foundation env's plaintext bootstrap defaults migrated to `nexus/foundation/...`
  in Vault KV. Six paths seeded sticky-one-time (preserves operator
  rotations): dsrm, local-administrator, nexusadmin, vault userpass,
  svc-vault-ldap bind cred, svc-vault-smoke. Foundation env's
  `provider "vault"` (~> 4.0) authenticates via AppRole role-id +
  secret-id JSON sidecar at `$HOME\.nexus\vault-foundation-approle.json`
  (mode 0600). Three `vault_kv_secret_v2` data sources resolve dsrm /
  local-administrator / nexusadmin for the dc-nexus + jumpbox overlays.
  `local.foundation_creds` ternary centralizes the
  `enable_vault_kv_creds ? KV : variable-default` logic. Bind/smoke
  overlays write back to KV after generating fresh AD pwds (best-effort
  with vault-init.json probe). `nexus-foundation-reader` policy enforces
  read on `nexus/foundation/*`, write only on `nexus/foundation/ad/*` —
  positive + 2 negative tests in smoke gate. Default
  `enable_vault_kv_creds` flipped `false → true` at close-out per
  `feedback_terraform_partial_apply_destroys_resources.md`.

### Updated

- **`docs/infra/vms.yaml`** — vault-1/2/3 `ram_gb 4 → 2` (approved
  deviation ratified at 0.D.4 close-out). Comment block above the nodes
  documents the deviation rationale + production-grade revert path.

- **`docs/adr/index.md`** — registers ADR-0011 / 0012 / 0013 / 0014 with
  their status + dates.

### Added — original (pre-0.D housekeeping)

- `.gitignore` — top-level ignore rules covering OS/editor junk and, as
  belt-and-suspenders for the planning repo, the same key-bearing-artifact
  blocks used downstream (`**/Autounattend.xml` except `.tpl`,
  `windows-keys.json`, `.nexus/`, `secrets/`, `*.pem`, `*.key`, `.env*`).
- `.gitleaks.toml` — mirrors `nexus-infra-vmware/.gitleaks.toml` with the
  `microsoft-product-key` custom rule.
- `.github/workflows/secret-scan.yml` — runs `gitleaks detect` on every PR
  and push to `main`.

## [0.1.3] — 2026-04-22 — "Windows licensing canon"

### Added

- **ADR-0144** (`docs/adr/ADR-0144-windows-licensing.md`) — decision record for
  the Windows licensing posture. Primary path: Visual Studio (MSDN) dev/test
  keys for all owner builds on host `10.0.70.101`. Documented fallback:
  Microsoft Evaluation Center ISOs (180 d Server, 90 d Win11, rearm-able) so
  any third party cloning the blueprint can reproduce the lab without an MSDN
  subscription.
- `docs/infra/licensing.md` — canonical how-to covering Path A (Evaluation)
  and Path B (MSDN), Vault KV paths `nexus/windows/product-keys/{ws2025-core,
  ws2025-desktop, win11ent}`, Packer integration snippet, pre-Phase-0.D
  bootstrap via NTFS-ACL'd `%USERPROFILE%\.nexus\secrets\windows-keys.json`,
  5-layer defense-in-depth against key leakage (`.gitignore` + `.gitleaks.toml`
  + pre-commit hook + CI gitleaks + Packer log filtering), operational
  playbook (add template / rotate key / audit), FAQ.

### Canon decisions locked

- **Primary activation path**: MSDN dev/test keys, Vault-custodied.
- **Fallback activation path**: Evaluation Center ISOs, rearm automated by
  `nexus-cli infrastructure rearm-windows`.
- **Keys-in-git posture**: zero. `Autounattend.xml` gitignored at every path;
  only `Autounattend.xml.tpl` templates are versioned. Keys substitute at
  Packer build time.
- **`product_source` Packer variable**: `msdn` (default for owner) or
  `evaluation` (default for the public blueprint) — single knob, no repo
  changes needed to switch paths.

## [0.1.2] — 2026-04-21 — "Phase 0.A closeout + nexus-gateway pattern"

### Discovered (platform constraints)

- **One NAT per host**: VMware Workstation Pro on Windows allows exactly one NAT
  virtual network, and the slot is held by the pre-existing VMnet8 (other tenants).
  `VMnet11` therefore cannot be NAT.
- **`vnetlib64.exe` regression on WS 17.5+**: sub-commands `set vnet … addr`,
  `add nat`, and `add dhcp` silently no-op (no stderr, no exit code). Only
  `add adapter` / `remove adapter` are reliable. `vmnetcfg.exe` GUI is the
  canonical configuration surface for subnet/DHCP.

### Changed (canon)

- **VMnet11 type: NAT → Host-Only** (subnet + role unchanged).
- **`nexus-gateway` VM** introduced as VM #0 of the fleet: Debian 13 minimal
  (512 MB / 1 vCPU / 4 GB disk) with NIC0 Bridged to physical LAN, NIC1 static
  `192.168.70.1/24` on VMnet11, NIC2 static `192.168.10.1/24` on VMnet10.
  Runs `nftables` masquerade, `dnsmasq` DHCP scope `.200–.250` + DNS forwarder,
  `chrony` NTP source. Must be built first in Phase 0.B so subsequent lab VMs
  have internet egress.
- **VM count**: 65 → 66 (lab VMs unchanged at 65; `nexus-gateway` is VM #0).
- **VMnet11 default gateway**: `192.168.70.2` (VMware NAT) → `192.168.70.1`
  (`nexus-gateway`).
- **Host-side adapter IPs**: VMnet10 = `192.168.10.1/24`, VMnet11 = `192.168.70.254/24`
  (`.1` reserved for `nexus-gateway`).
- **Phase 0.B exit gate**: now explicitly requires `nexus-gateway` powered on
  and a test VM able to `apt update` through it before the Packer template
  work is considered complete.

### Updated

- `docs/infra/network.md` — rewritten to document platform constraints #1–3,
  the nexus-gateway edge-router pattern, GUI-canonical config procedure,
  adapter-cycle and static-IP fallbacks, updated panic-button runbook.
- `docs/infra/host-setup.md` — revised end-to-end to reflect actual runbook
  used on host `10.0.70.101`; vnetlib64 limited to `add adapter`; GUI steps
  promoted to canonical; verification table matches what the host produced.
- `docs/infra/vms.yaml` — `vmnet11.mode: nat` → `host-only`, added
  `vmnet11.gateway: 192.168.70.1`, added `clusters.edge.nexus-gateway` node
  entry, bumped `vm_count` and `plan_version`.
- `MASTER-PLAN.md` — Phase 0.A/0.B table entries rewritten; Phase 0.B begins
  with nexus-gateway build before Packer template work.

## [0.1.1] — 2026-04-21 — "Phase 0.A errata + host bootstrap"

### Changed

- **Network canon amended**: `VMnet20` → **`VMnet10`**, `VMnet21` → **`VMnet11`**.
  VMware Workstation Pro on Windows caps virtual networks at `vmnet0..vmnet19`
  (confirmed by inspection of `C:\ProgramData\VMware\netmap.conf` which enumerates
  `network0..network19`). The originally-published VMnet20/21 numbers were
  unreachable on the platform. Subnets (192.168.10.0/24 and 192.168.70.0/24)
  and roles are unchanged. Updated: `MASTER-PLAN.md`, `docs/infra/network.md`,
  `docs/infra/vms.yaml`, `README.md`.

### Added

- `docs/infra/host-setup.md` — Phase 0.A runbook for creating `VMnet10`
  (Host-Only, 192.168.10.0/24, DHCP off) and `VMnet11` (NAT, 192.168.70.0/24,
  DHCP scoped .200–.250) on host `10.0.70.101` with both `vnetlib64.exe` CLI
  and `vmnetcfg.exe` GUI paths, plus verification.
- `scripts/phase-0a-create-vmnets.ps1` — elevated PowerShell that drives
  `vnetlib64.exe` to stop services, register vmnet10/11, set type/subnet,
  disable DHCP on vmnet10, scope DHCP on vmnet11, restart services, and
  verify adapters appear in `Get-NetAdapter`.

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
- `docs/infra/network.md` — VMnet10 (Host-Only 192.168.10.0/24) + VMnet11 (NAT 192.168.70.0/24) canon.
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
