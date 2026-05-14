# ADR-0023 — Phase 0.H.5: MirrorMaker 2 dedicated mode, one replication flow per node

- **Status**: Accepted
- **Date**: 2026-05-15
- **Deciders**: Greg Zapantis
- **Related**: ADR-0020 (KRaft combined-mode clusters), ADR-0021 (Kafka-tier mTLS), SC-0003 (`streamcore` — MM2 for east/west DR)

## Context

Phase 0.H.5 connects the East and West KRaft clusters with MirrorMaker 2 — the Phase 0.H exit gate is "produce a record to `kafka-east` → it appears on the mirrored topic on `kafka-west`." `vms.yaml` budgets two MM2 VMs (`mm2-1`, `mm2-2`). There are several ways to deploy MM2, and they are not equivalent:

1. **Driver:** MM2 ships *inside Apache Kafka* as `connect-mirror-maker` ("dedicated mode") — a properties-file-driven process that embeds its own Connect workers. The alternative is running the MM2 connectors *on top of* an existing Kafka Connect cluster. The lab already has a Connect cluster (0.H.4), so "reuse it" is tempting.
2. **Flow placement:** the DR design is bidirectional (East→West and West→East). Both flows could run on both MM2 nodes (each node configured with both directions enabled), or each node could own exactly one flow.
3. **`--clusters` semantics:** `connect-mirror-maker`'s `--clusters` flag is a *locality* hint — it scopes a node to "the connectors that produce **into** these clusters" and pins that node's Connect-internal topics there. It is easy to misread as a clean "only run flow Z" switch.
4. **TLS:** MM2 talks to **both** clusters, both of which require client certs (ADR-0021). How the per-cluster SSL config is expressed matters.

## Decision

**`connect-mirror-maker` in dedicated mode, one replication flow per node, deterministic per-node config.**

- **Dedicated mode, not on the 0.H.4 Connect cluster.** MM2 runs as its own `mm2.service` on `mm2-1` / `mm2-2`, driven by `/etc/nexus-kafka/mm2.properties`. Keeping MM2 off the Connect cluster isolates DR replication from the Debezium/CDC workload — a Connect-cluster rebalance or a bad connector deploy must not be able to stall cross-cluster DR, and vice versa.
- **One flow per node.** `mm2-1` owns `east→west`; `mm2-2` owns `west→east`. Each node's `mm2.properties` registers **both** clusters but enables exactly **one** direction (`<src>-><dst>.enabled = true`, the reverse `= false`). The two nodes do not cluster with each other.
- **`--clusters` as belt-and-suspenders, via a systemd drop-in.** The baked `mm2.service` `ExecStart` carries no flags; a per-node drop-in (`mm2.service.d/10-clusters.conf`) resets `ExecStart=` and re-specifies it with `--clusters <target>` (`west` for `mm2-1`, `east` for `mm2-2`). The single `enabled=true` line alone already pins the direction — `--clusters` additionally pins where the node's Connect-internal `mm2-{offsets,configs,status}.*.internal` topics land. The `enabled=` line is the source of truth; `--clusters` is the reinforcement.
- **Embedded Connect REST server left OFF.** `dedicated.mode.enable.internal.rest` defaults to `false`; it is only needed for *multi-node* MM2 clusters that coordinate task rebalancing. One node per flow needs no coordination → no REST server is stood up → the Apache-Kafka-`RestServer`-rejects-PEM problem (ADR-0021) never arises, and the `.p12` files on the MM2 nodes are simply unused.
- **Per-cluster mTLS, written once per alias.** In dedicated mode, cluster-level `<alias>.ssl.*` / `<alias>.security.protocol` **auto-cascade** to the producer/consumer/admin clients (`MirrorMakerConfig.clusterProps()` does `putIfAbsent("producer."+k, v)` etc.). So `east.ssl.*` + `west.ssl.*` is written once each and covers all three client types — the opposite of standalone Connect, which needs `producer.`/`consumer.`/`admin.` duplicated. All MM2 clients are Kafka clients → `ssl.keystore.type=PEM` throughout.
- **`DefaultReplicationPolicy`.** A topic `T` on `east` is mirrored to `west` as `east.T` (source-alias prefix). The prefix is what keeps the bidirectional pair **loop-safe** — `east.`-prefixed topics are recognised as already-remote and not re-mirrored back. `IdentityReplicationPolicy` (no prefix) is explicitly rejected: it cannot distinguish local from remote topics and would create replication loops.

## Consequences

### Positive

- **Deterministic and self-documenting.** Each node's `mm2.properties` shows exactly one enabled flow; an operator reading the file knows what that node does without reasoning about `--clusters` locality semantics.
- **Failure isolation.** DR replication and the CDC/Connect workload cannot stall each other — separate processes, separate VMs, separate internal-topic sets.
- **Less config than feared.** The dedicated-mode auto-cascade means the mTLS block is two short stanzas (`east.ssl.*`, `west.ssl.*`), not nine.
- **No REST/PEM friction.** Because the embedded REST server is off, the keystore-format split that bit Connect/ksqlDB (ADR-0021) is a non-issue for MM2.

### Negative

- **No MM2-node redundancy per direction.** Each flow runs on exactly one VM; if `mm2-1` is down, `east→west` replication stops until it is back. Acceptable for a lab DR demo (the gate is "replication works", not "replication is itself HA"); a production posture would run a multi-node MM2 cluster per flow with the internal REST server enabled for rebalancing — which is exactly the configuration this ADR opts out of.
- **Two VMs for two one-directional flows.** A single multi-node MM2 cluster could run both flows with rebalancing. The one-flow-per-node split trades that density for determinism and isolation — a deliberate lab-legibility choice.

### Neutral

- **`--clusters` is reinforcement, not the mechanism.** If the systemd drop-in were lost, the `enabled=` lines alone would still produce correct (if slightly less tidy — internal topics could land in the source cluster) behaviour. The drop-in is defence-in-depth, not load-bearing.
- **Matches `streamcore`'s SC-0003.** `streamcore` already commits to "MM2 for east/west DR, not mirror-maker v1"; this ADR is the infrastructure realisation of that application-tier decision.

## Verification

`smoke-0.H.5.ps1` (38 checks) asserts: each node's `mm2.properties` enables only its one flow + has per-cluster mTLS; the `--clusters` drop-in is present; the journal shows the three MM2 connectors with no TLS/auth errors; the `heartbeats` + `mm2-*.{src}.internal` topics appear on the target cluster; and — the **Phase 0.H exit gate** — a fresh record produced to `kafka-east` appears on `east.dr-gate-test` on `kafka-west`, and the `west.*` reverse. Verification doc: `nexus-infra-kafka/docs/verification/0.H.5-mirrormaker2.md`.
