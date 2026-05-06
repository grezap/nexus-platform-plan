# ADR-0018 — Phase 0.E.4d: nftables `flush ruleset` + Docker iptables-nft conflict resolution

- **Status**: Accepted
- **Date**: 2026-05-07
- **Deciders**: Greg Zapantis
- **Related**: ADR-0017 (Portainer CE deployment)

## Context

On Debian 13 (and similar modern systemd distros), the `iptables` CLI is `iptables-nft` (legacy iptables interface translated to the kernel's nftables backend). Docker uses iptables to install its bridge + ingress mesh rules at daemon startup, so they end up in the kernel's nftables ruleset alongside any other nftables config.

The Debian-default `/etc/nftables.conf` starts with:

```
#!/usr/sbin/nft -f
flush ruleset

table inet filter { ... }
```

Running `nft -f /etc/nftables.conf` — the canonical way to apply nftables config changes atomically — invokes `flush ruleset` first, which **drops the ENTIRE kernel ruleset across all tables**. That includes Docker's auto-installed rules. Specifically, Docker Swarm's routing-mesh DNAT rules in `nat/DOCKER-INGRESS` vanish.

**Symptom observed during 0.E.4d:**
- Portainer Server replica running, listening on 9443 inside the container.
- `docker service inspect` shows published-port mapping `*:9443->9443`.
- `ss -tlnp` on the host shows dockerd listening on `*:9443`.
- BUT `iptables -t nat -L DOCKER-INGRESS -n` shows the chain with only `RETURN` (no DNAT rules to the ingress namespace).
- Result: external connections to `https://<manager-ip>:9443` time out. Localhost-direct connections (`https://127.0.0.1:9443`) work because they bypass the routing mesh.

This isn't a Portainer-specific problem — it affects ANY Docker Swarm service with published ports if `nft -f` runs at any point after Docker daemon startup.

## Decision

**Adopt the "flush + restart docker" pattern for any nftables apply on Swarm hosts**:

Every overlay or operator script that runs `nft -f /etc/nftables.conf` against a Docker host MUST follow with `systemctl restart docker` to rebuild Docker's iptables-nft rules. For Swarm clusters, the restart MUST be sequential across managers (3 nodes; raft tolerates 1 down at a time).

Implementation in [`role-overlay-portainer-firewall.tf`](https://github.com/grezap/nexus-infra-swarm-nomad/blob/main/terraform/envs/swarm-nomad/role-overlay-portainer-firewall.tf):

```bash
# After patching /etc/nftables.conf in-place + atomic ruleset reload:
sudo nft -f /etc/nftables.conf

# Rebuild Docker's iptables rules (wiped by flush-ruleset above):
sudo systemctl restart docker
sleep 4

# Verify ingress mesh DNAT rule exists:
DNAT_COUNT=$(sudo iptables -t nat -L DOCKER-INGRESS -n 2>/dev/null \
  | grep -cE 'DNAT.*tcp dpt:(9443|8000)' || true)
```

Per-node sequential application + 5s settle window between nodes preserves Swarm raft quorum (3-of-3 raft tolerates 1 manager down; sequential ensures only one manager restarts at a time).

### Alternatives considered + rejected

1. **Use `nft -f` WITHOUT `flush ruleset`** at the top of `/etc/nftables.conf`. Adds rules without flushing, so Docker's tables survive.
   - **Rejected**: loses the declarative-config property. The file no longer describes "the canonical state" but rather "additions to whatever's there", so re-applies duplicate rules + diverge from the file's content.
2. **Switch Docker's firewall backend to nftables-native** via `/etc/docker/daemon.json` `"firewall-backend": "nftables"` (Docker 25+).
   - **Rejected for now**: Docker 25's nftables backend puts rules in different tables (`docker-{bridge,ingress}-mark` etc.). Our `/etc/nftables.conf` would need to NOT flush those tables — same problem just shifted, plus the Docker rules become harder to reason about because they're spread across multiple inet/ip/ip6 families.
   - **Worth revisiting** in Phase 0.E.6+ when we have time for a clean migration. For now, the iptables-nft + Docker iptables backend pair works correctly with the restart-after-flush pattern.
3. **Move the firewall config out of `/etc/nftables.conf` entirely**, e.g., into `/etc/nftables.d/*.conf` files loaded by individual `include` directives.
   - **Rejected**: Debian's nftables.service systemd unit specifically loads `/etc/nftables.conf`; supporting a `.d/` directory needs a custom unit drop-in. Add complexity for marginal benefit.
4. **Run `nft -f` only at first apply, never on re-apply**. Patch the running ruleset via `nft add rule` for incremental changes.
   - **Rejected**: per `feedback_nftables_runtime_add_after_drop.md`, `nft add rule` lands at chain end AFTER `counter drop`, making the rule unreachable. The position-dependent semantics make incremental patching unreliable. Idempotent declarative apply is better.

## Consequences

**Positive:**
- Single-source-of-truth `/etc/nftables.conf` describes the canonical firewall state. Re-applies are idempotent + consistent.
- Docker Swarm's ingress mesh re-installs cleanly on dockerd restart, so the rebuild is automatic + verifiable via `iptables -t nat -L`.
- Sequential per-node restart preserves raft quorum; cluster has zero downtime from a customer perspective (Portainer might briefly reschedule but Swarm handles transparently).

**Negative / accepted:**
- **Brief container restart on each node** during the docker daemon restart. Containers with `restart_policy: condition: on-failure` (default for Swarm services) come back automatically; `restart_policy: condition: none` would die permanently. Lab uses defaults so no concern.
- **5s sleep between nodes** in the firewall overlay's per-node loop adds ~30s to the apply for a 6-node cluster. Acceptable; this is a one-time setup cost.
- **`flush ruleset` is destructive at the kernel level**. If anyone runs `nft -f /etc/nftables.conf` outside the canonical overlay path (e.g., manual operator action), they MUST follow with `systemctl restart docker` or accept that Swarm services lose ingress.

**Operational guidance**: documented in `nexus-infra-swarm-nomad/docs/handbook.md` §3.3 (NFS troubleshooting also covers this since the gateway nftables patch + reload is on the same hot-path).

## Operational artefacts

- Code: `nexus-infra-swarm-nomad/terraform/envs/swarm-nomad/role-overlay-portainer-firewall.tf` (canonical overlay)
- Code (gateway side, no Docker — single `nft -f` is fine): `nexus-infra-vmware/terraform/envs/foundation/role-overlay-gateway-nfs-portainer.tf`
- Smoke: 0.E.4 smoke gate verifies HTTPS:9443 reachability via build-host-CA-validated TLS, which catches any DNAT regressions
- Lesson memorial: `feedback_nftables_flush_ruleset_wipes_docker.md`
