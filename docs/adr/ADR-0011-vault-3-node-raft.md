# ADR-0011 — 3-node Vault Raft cluster on the foundation tier

- **Status**: Accepted
- **Date**: 2026-04-30 (Phase 0.D.1 close-out)
- **Deciders**: Greg Zapantis
- **Supersedes**: —
- **Superseded by**: —
- **Related**: ADR-0012 (PKI hierarchy), ADR-0013 (LDAPS auth), ADR-0014 (KV cred read pattern), `MASTER-PLAN.md` Phase 0.D, `docs/infra/vms.yaml` foundation tier

## Context

Phase 0.D's exit gate calls for "3-node Vault Raft, AppRole, KV-v2 `nexus/*` paths." The lab fleet (~66 VMs) needs a single secrets store for: AD bootstrap creds, Windows product keys (per ADR-0144), DB connection strings, OAuth client secrets, mTLS leaf certs (post-0.D.2), and Vault-managed password rotation for AD service accounts.

Three deployment shapes were considered:

1. **Single-node Vault** (development convenience). Rejected — the entire portfolio's narrative coherence depends on showing HA infrastructure (`feedback_master_plan_authority.md`); single-node Vault doesn't demonstrate Raft consensus or quorum behavior.
2. **3-node Vault on Consul backend.** Considered, then rejected for Phase 0.D — Consul is canonically Phase 0.E. Adding it to 0.D inflates the dependency graph.
3. **3-node Vault on integrated Raft storage.** Selected — Vault's built-in Raft (since 1.4) needs no external KV store, supports auto-pilot, and matches the lab's "minimum-moving-parts" preference.

## Decision

1. **Cluster shape: 3 Debian 13 nodes** (`vault-1`, `vault-2`, `vault-3`) on the foundation tier directory `H:\VMS\NexusPlatform\01-foundation\vault-N`.
2. **Dual-NIC topology** (matches every other lab cluster): primary on VMnet11 service network (.121/.122/.123 via dnsmasq dhcp-host MAC reservations on `nexus-gateway`); secondary on VMnet10 cluster backplane (192.168.10.121-.123, statically configured by `vault-firstboot.sh` per hostname mapping). `cluster_addr` rides VMnet10; `api_addr` rides VMnet11.
3. **Storage backend: integrated Raft.** No Consul dependency, no external KV store. Auto-pilot enabled; default heartbeat thresholds.
4. **Init shape: 5 unseal keys, threshold 3.** Init JSON (`{root_token, unseal_keys_b64, ...}`) persists at `$HOME\.nexus\vault-init.json` on the build host (mode 0600 via icacls). NOT in Terraform state — pre-Phase-0.E secrets stay out of state.
5. **Auth methods enabled at post-init**: `userpass` (initial human ops), `approle` (initial CI/automation; the `nexus-bootstrap` AppRole carries `default` policy until 0.D.4 introduces a tighter policy).
6. **KV-v2 mount at `nexus/`.** Per `MASTER-PLAN.md` Phase 0.D goal. All future paths under `nexus/...`.
7. **Approved RAM deviation: 2 GB per node** (vms.yaml says 4 GB). Vault runs comfortably at 2 GB at lab scale; build host RAM is the constraint per `feedback_prefer_less_memory.md`.

## Consequences

### Positive

- Self-contained cluster: no external etcd/Consul/Postgres dependency.
- Quorum behavior demonstrable in failover demos (`docker-style chaos`: power off vault-1; vault-2 or vault-3 wins the Raft election; cluster stays available).
- Smoke gate covers the full bring-up plus cross-node read consistency (24/24 checks per `scripts\smoke-0.D.1.ps1`).

### Negative / accepted

- Per-clone self-signed bootstrap TLS: each Vault VM generates its own listener cert at first-boot (`vault-firstboot.sh`). Cross-node TLS verification needs the leader's cert in the followers' system trust store at raft-join time. Pre-PKI hack; ADR-0012 (PKI) replaces it.
- Init JSON on disk: a compromised build host yields the entire cluster. Mitigated by NTFS ACL (icacls owner-only), gitignored `.nexus/` directory, and 0.D.5's Transit auto-unseal which moves the unseal key off the build host entirely.

### Neutral

- 3 nodes match canon (`docs/infra/vms.yaml` lines 55-57). RAM deviation logged here and in vms.yaml's lab-scale note.

## Lessons captured (now memory canon)

- `feedback_systemd_link_precedence_multi_nic.md` — `OriginalName=en*` matching is non-deterministic with two en* interfaces; `vault-firstboot.sh` discriminates by MAC OUI byte 5.
- `feedback_terraform_heredoc_powershell.md` — three rules for safe PowerShell escaping inside Terraform heredocs (`$${var}`, `$${var}:`, no backtick-letter inside inner here-strings).
- `feedback_smoke_gate_probe_robustness.md` — three rules for cross-platform smoke probes (`openssl -checkend`, intermediate-relay into `ExtraStore`, marker tokens + `-match` not strict-eq).

## Operational rules

- Bring-up: `pwsh -File scripts\security.ps1 apply`. Smoke: `pwsh -File scripts\security.ps1 smoke -Phase 0.D.1`.
- One Vault node at a time may be powered off without cluster impact. Two nodes off ⇒ quorum loss; cluster goes read-only until quorum returns.
- Reseal procedure: `vault operator seal` requires the root token (or `sudo` + `default` policy after 0.D.5's policy tightening).
