# ADR-0020 — Phase 0.H.1: KRaft combined broker+controller mode for the Kafka tier

- **Status**: Accepted
- **Date**: 2026-05-15
- **Deciders**: Greg Zapantis
- **Related**: ADR-0006 (event serialization — Avro), `nexus-infra-kafka` Phase 0.H

## Context

Phase 0.H stands up the Kafka tier: two clusters (East primary + West DR) on the `03-kafka` VMware tier. Kafka needs a metadata/coordination layer, and there are three axes to decide:

1. **ZooKeeper vs KRaft.** ZooKeeper is the legacy coordination layer; it is deprecated as of Kafka 3.5 and **removed entirely in Kafka 4.0**. KRaft (Kafka Raft) is GA since Kafka 3.3 and is the only forward path.
2. **Combined vs separate roles.** In KRaft a node can run as `broker`, `controller`, or both (`broker,controller` — "combined mode"). Separate-role deployments dedicate nodes to the controller quorum; combined-mode nodes do both jobs.
3. **Cluster count + size.** The MASTER-PLAN (line 160) calls for an East primary + a West DR cluster; `vms.yaml` budgets three VMs per cluster.

The binding constraint is the same one that shapes the whole lab: **build-host RAM is finite** (`feedback_prefer_less_memory.md`). A separate-role KRaft deployment at "3 brokers + 3 controllers per cluster" would be 12 VMs for the two clusters before a single ecosystem node; combined mode is 6.

## Decision

**KRaft, combined `broker,controller` mode, two 3-node clusters.**

- Every broker VM runs `process.roles=broker,controller` — it is both a data broker and a member of the controller quorum.
- Each cluster is a 3-node Raft quorum (`controller.quorum.voters` lists all three) → tolerates one node down.
- **No ZooKeeper VMs.** The tier is 15 VMs total (6 brokers + 9 ecosystem), not 21+.
- The per-cluster **cluster UUID is minted at Terraform time** by `role-overlay-kraft-format.tf` and passed to `kafka-storage format` — it is not in `server.properties`. A cold rebuild mints a fresh UUID; an in-place re-apply recovers the existing one (`--ignore-formatted`).
- KRaft listeners: `PLAINTEXT`/`SSL` on `9092` (client + inter-broker), `CONTROLLER` on `9093`, both advertised on the VMnet10 backplane.

## Consequences

### Positive

- **Half the VM count.** 6 broker VMs instead of 12+; the saved RAM/disk/CPU budget goes to the ecosystem tier and the rest of the lab.
- **Forward-compatible.** KRaft is the only mode that survives the Kafka 4.0 cut; no ZooKeeper migration debt is ever incurred.
- **Simpler bring-up.** One Packer template, one firstboot path, one role unit for the brokers — no separate ZooKeeper template/role/quorum to coordinate before Kafka can start.
- **Self-contained quorum.** Controller election is internal to the three broker VMs; there is no external dependency to fail.

### Negative

- **Combined mode is a small-cluster choice.** The Kafka docs recommend separate-role deployments for production scale, where controller load and broker load should not contend for the same JVM/heap/disk. The lab's traffic is demo-scale, so the contention is academic here — but `streamcore` and any production-shaped sizing exercise must explicitly note this as a lab deviation.
- **A node loss costs both a broker and a controller voter.** Losing one of three combined nodes drops the cluster to 2 brokers AND a 2-voter quorum simultaneously. Acceptable at RF=3 / 3-node scale (still has quorum), but it is a tighter failure envelope than separate roles.

### Neutral

- **The DR story is cross-cluster, not intra-cluster.** Single-cluster resilience is "survive one node"; the real DR posture (survive a whole cluster / site) is MirrorMaker 2 between East and West — see ADR-0023.
- **Combined mode does not change the client contract.** Producers/consumers see a normal broker; the controller role is invisible on `9092`.

## Verification

`smoke-0.H.1.ps1` (38 checks) asserts each cluster reports a 3-voter KRaft quorum with an elected controller (`kafka-metadata-quorum ... describe --status`) and a verified RF=3 produce/consume round-trip. Both cluster UUIDs (`kafka-east` `ZD-HhB5fQfioHydHQWiHkw`, `kafka-west` `FezdEIKlRCWP6nCSrHNJww`) are recorded in `nexus-infra-kafka/docs/verification/0.H.1-kraft-bringup.md` and survive the 0.H.2 mTLS flip unchanged.
