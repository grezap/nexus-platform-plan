# DEMO-23 · Drive the Vault trust root from the CLI — step-down, snapshot, recover-ha

## 1. What this shows

The platform's trust root — a 3-node HashiCorp Vault Raft cluster auto-unsealed by a single-node Shamir
custodian (`vault-transit`) — is now a first-class `nexus-cli` cluster (ClusterId `vault`, Phase 0.A-0.D/0.M,
nexus-cli v0.8.1). An operator drives the **full HA surface without ever touching the `vault` CLI or raw
unseal keys**: observe the cluster, force a leader **step-down** and watch a standby take over with the
cluster serving throughout, take a **Raft snapshot** and verify it non-destructively, and — the headline —
recover the whole HA cluster from the post-reboot boot-race with a single **`recover-ha`** verb.

Crucially, the operator's `VAULT_TOKEN` stays on the build host: the CLI's Vault control plane is HTTP from
the build host, so the root token is **never shipped to a node's process table**. And the two genuinely
dangerous operations are fenced off: `backup restore` on the live trust root is refused, and raw
`vault operator unseal` is never exposed — only the declarative, idempotent `recover-ha`.

Personas: **infra engineer** (HA verification + DR drills), **security engineer** (the token never leaves the
build host; unseal is gated), **platform owner** (the trust root has the same panic-button verbs as every
other tier).

## 2. Runtime + prerequisites

- **Environment target** — any env (the foundation tier is the always-on 6-VM base; this demo needs no extra
  cluster powered on).
- **VMs required** — `vault-1` · `vault-2` · `vault-3` · `vault-transit` (cluster `foundation` in
  [`docs/infra/vms.yaml`](../infra/vms.yaml)).
- **Env vars** — `VAULT_ADDR=https://192.168.70.121:8200` · `VAULT_TOKEN` (the operator root token from
  `~/.nexus/vault-init.json`) · `VAULT_CACERT=~/.nexus/vault-ca-bundle.crt` · `NEXUS_SSH_KEY` ·
  `NEXUS_VMS_YAML`. (`scratch/nx.ps1` in `nexus-cli` sets these.)
- **Seed data** — none. The Shamir keys for `recover-ha` are read from the operator's
  `~/.nexus/vault-transit-init.json` (build-host only).
- **Expected duration** — 4–6 min wall-clock.
- **Reset command** — none needed; every step is non-destructive or self-recovering (failover leaves a
  healthy standby; the snapshot is a read; `recover-ha` is idempotent).

## 3. Architecture snapshot

`vault-1/2/3` run in transit-auto-unseal mode (recovery-shamir): on boot they fetch their seal key from
`vault-transit`'s transit engine. `vault-transit` is Shamir-sealed and sits at the bottom of the chain — on a
build-host reboot it comes back **sealed**, and the HA nodes crash-loop fetching their seal key until it's
unsealed. The Raft leader **drifts** (it is not pinned to vault-1); the build-host `VAULT_ADDR` is usually a
follower (the API forwards). The CLI reads the active node dynamically and addresses each node directly for
per-node status. `vault-transit` is outside the build-host CA bundle, so the CLI drives it over SSH.

## 4. Step-by-step script

| # | Persona action | Command | Expected observation |
|---|---|---|---|
| 1 | See the whole trust root | `nexus status vault` | 4-row table: vault-1/2/3 (one **active**, two **standby**) + vault-transit; overall **green**; leader read dynamically. |
| 2 | Prove every HA layer | `nexus health vault` | 7 green probes: seal-status ×3, exactly 1 active, **Raft 3 voters / 1 leader**, transit-unseal serving, operator-auth (token authorized). |
| 3 | Force a leader change | `nexus failover-test cluster vault --yes` | `sys/step-down` on the active → a **standby is promoted**, RTO ≈ 2 s; the old active becomes a healthy standby; the cluster served throughout (Raft leadership is location-independent). |
| 4 | Take a verified backup | `nexus backup take vault --tag demo` | A **Raft snapshot** saved to a build-host file (~1.7 MiB) + a **non-destructive inspect** (gzip/tar `meta.json` → index/term). No data is touched on the cluster. |
| 5 | Confirm restore is fenced | `nexus backup restore vault any-id --yes` | **Refused** (exit 2, actionable) — restore would overwrite the live trust root; the DR runbook restores onto an isolated cluster. |
| 6 | Simulate a reboot recovery | `nexus recover-ha vault --yes` | The declarative boot-race recovery: unseal vault-transit from the Shamir key file → restart vault-1/2/3 → poll. All nodes **sealed=no**; idempotent (a no-op when already up). |

## 5. What it proves

- The trust root carries the same verb surface (status/health/topology/failover/scale-out/backup/cert-rotate/
  acl/chaos) as every data-tier cluster — plus the bespoke `recover-ha`.
- **Security posture:** the root token stays on the build host (HTTP control plane); the two dangerous ops
  (restore, raw unseal) are fenced — only the declarative `recover-ha` can unseal, and only the take-time
  inspect (never a restore) validates a snapshot on the live cluster.
- **Availability:** a forced step-down keeps the cluster serving (clients follow the active-node redirect);
  Raft re-elects in ≈ 2 s.
- **Operability:** the single most common foundation outage — the post-reboot transit boot-race — is now a
  one-line, idempotent CLI verb.

Companion executable (System B) demos, one per verb: `nexus-cli/docs/demos/DEMO-96..105`. Adapter decisions:
`nexus-cli` ADR-0022. Verification evidence: `nexus-cli/docs/verification/0.8.1-foundation.md`.
