# DEMO-24 · Drive the orchestration tier from the CLI — three-raft failover, drain, cert-rotate

## 1. What this shows

The Tier-2 orchestration plane — Docker Swarm + HashiCorp Nomad + Consul, with a Portainer UI, across 3
managers + 3 workers — is now a first-class `nexus-cli` cluster (ClusterId `swarm`, Phase 0.E, nexus-cli
v0.8.2). It is the **most reusable** adapter: the `ConsulClient`, `NomadClient`, `PortainerClient`,
`ClusterStatusService` and `FailoverTestService` shipped in v0.1–v0.5 for the standalone `cluster-status`
and `failover-test` commands are wired **verbatim** into the full `IClusterAdapter` surface.

An operator drives all three independent raft rings from one tool: observe the rolled-up state, fail over the
**Consul**, **Nomad**, or **Swarm** leader (the last via a vmrun host-level VM suspend) and watch each ring
re-elect, drain a node out of scheduling and add it back, take a verified Consul+Nomad snapshot, rotate every
node's mTLS leaf, and inject chaos on a worker while the managers keep quorum.

Crucially the same build-host posture as the Vault adapter (DEMO-23): the Consul/Nomad management tokens stay
on the build host (read from Vault KV), and there is **no managed Docker/Consul/Nomad driver** — everything is
HTTP + SSH (NetArchTest-enforced). The dangerous op is fenced: `backup restore` on the live cluster is refused.

Personas: **infra engineer** (three-ring HA verification + DR drills), **platform owner** (the orchestration
tier has the same panic-button verbs as every data tier), **security engineer** (tokens never leave the build
host; bootstrap/agent ACL tokens are revoke-protected).

## 2. Runtime + prerequisites

- **Environment target** — the 6-VM orchestration tier (tier `06-orchestration`) on top of the always-on
  foundation base. If it has been offline > 168 h, cold-rebuild it first: `pwsh scripts/swarm.ps1 cycle` in
  `nexus-infra-swarm-nomad`.
- **VMs required** — `swarm-manager-1/2/3` · `swarm-worker-1/2/3` (cluster `swarm` in
  [`docs/infra/vms.yaml`](../infra/vms.yaml)). Portainer runs as a manager-pinned Swarm service (no VM).
- **Env vars** — `VAULT_ADDR` · `VAULT_TOKEN` · `VAULT_CACERT` (to read the Consul/Nomad mgmt tokens from
  Vault KV `nexus/swarm/{consul,nomad}-bootstrap-token`) · `NEXUS_SSH_KEY` · `NEXUS_VMS_YAML`.
  (`scratch/nx.ps1` in `nexus-cli` sets these.)
- **Seed data** — none; the tokens are read from Vault KV.
- **Expected duration** — 6–9 min wall-clock (the swarm-manager failover + cert-rotate dominate).
- **Reset command** — none needed; failover auto-recovers, scale-out remove is reversed by scale-out add, the
  snapshot is a read, and chaos recovers to green.

## 3. Architecture snapshot

Each of the 3 managers runs a Consul server + a Nomad server + a Swarm manager; each of the 3 workers runs a
Consul client + a Nomad client + a Swarm worker + a Portainer agent. The **three raft rings elect
independently** — the Swarm, Consul and Nomad leaders are usually on different managers and are each read from
their own source (`docker node ls` / `/v1/status/leader` ×2). The build host doesn't resolve `*.nexus.lab`, so
the CLI addresses a manager IP for all three HTTP control planes (the CA-pinned client validates the chain, not
the SAN). mTLS leaves are issued by each node's own `nexus-vault-agent` from `pki_int`.

## 4. Step-by-step script

| # | Persona action | Command | Expected observation |
|---|---|---|---|
| 1 | See the whole tier | `nexus status swarm` | 6-row table: 3 managers (one **manager/leader**, two reachable) + 3 workers, all **alive**; overall green. |
| 2 | Prove every plane | `nexus health swarm` | 9 green probes: Consul members + leader, Nomad servers/leader/clients, Portainer reachable, Swarm 3+3 Ready + 1 leader. |
| 3 | Fail over Consul | `nexus failover-test cluster swarm --direction consul-leader --yes` | SSH-stop consul on the leader → a different manager is elected, **RTO ≈ 2 s**, original restarted. |
| 4 | Fail over Nomad | `nexus failover-test cluster swarm --direction nomad-leader --yes` | Same shape on the Nomad ring, **RTO ≈ 3 s**. |
| 5 | Fail over the Swarm manager VM | `nexus failover-test cluster swarm --direction swarm-manager --yes` | **vmrun SUSPENDS** the Swarm raft-leader VM → a new manager becomes Leader (**RTO ≈ 21 s**), VM resumed, all 3 managers Ready again. |
| 6 | Drain + re-add a node | `nexus scale-out remove swarm swarm-worker-3 --yes` then `nexus scale-out add swarm --role worker --yes` | Reversible: `docker node drain` + `nomad node drain`, then re-activate — the VM stays a raft/gossip member throughout. |
| 7 | Take a verified backup | `nexus backup take swarm --tag demo` | `consul snapshot save` + `consul snapshot inspect` (round-trip verify) + `consul kv export` + `nomad operator snapshot save`, downloaded to a build-host file. |
| 8 | Confirm restore is fenced | `nexus backup restore swarm any-id --yes` | **Refused** (exit 2, actionable) — restore would overwrite the live KV/jobs; the DR runbook restores onto an isolated cluster. |
| 9 | Rotate every mTLS leaf | `nexus cert-rotate swarm --yes` | 6 nodes, **new serial ≠ old serial** on each (the verb force-reissues; a bare vault-agent restart reuses the cached `pkiCert`), consul rolling + nomad parallel, 0 errors. |
| 10 | Inject chaos on a worker | `nexus chaos swarm network-partition --target swarm-worker-3 --duration 30 --yes` | The worker is partitioned off the backplane (Consul 5/1, Swarm 2/3 during), then `docker` is restarted after the nft lift and the cluster **recovers to green**. |

## 5. What it proves

- The orchestration tier carries the same verb surface as every data-tier cluster, over **three independent
  raft rings** rolled into one operator view.
- **Maximum reuse, zero new control-plane code:** the Consul/Nomad/Portainer clients + the status/failover
  services built in v0.1–v0.5 power the adapter unchanged.
- **Security posture:** the mgmt tokens stay on the build host; no managed orchestration driver is linked;
  bootstrap/agent ACL tokens are revoke-protected; restore is fenced.
- **Availability:** all three leaders re-elect on demand (service-level for Consul/Nomad, host-level VM
  suspend for Swarm); a worker can be drained, lost to a partition, or have its certs rotated with the cluster
  staying up.

Companion executable (System B) demos, one per verb: `nexus-cli/docs/demos/DEMO-110..123`. Adapter decisions:
`nexus-cli` ADR-0023. Verification evidence: `nexus-cli/docs/verification/0.8.2-swarm.md`.
