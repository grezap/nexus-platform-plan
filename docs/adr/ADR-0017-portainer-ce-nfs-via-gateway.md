# ADR-0017 — Phase 0.E.4: Portainer CE single-replica + NFS-via-gateway state continuity

- **Status**: Accepted
- **Date**: 2026-05-07
- **Deciders**: Greg Zapantis
- **Related**: ADR-0011 (Vault cluster), ADR-0012 (PKI hierarchy), ADR-0016 (Nomad-Vault integration)

## Context

Phase 0.E.4 deploys Portainer as the cluster's container-orchestration UI on top of the 6-node Docker Swarm. Three orthogonal decisions:

1. **Edition**: Portainer EE (paid; native HA across replicas) vs. CE (free; single-replica only).
2. **Storage for `/data` (BoltDB + admin state)**: Local volume (state lost on replica reschedule) vs. shared storage (NFS / CSI / replicated block).
3. **NFS server location** (if NFS): dedicated VM + tier vs. consolidated on existing infra-host.

Lab constraints:
- No EE license; lab is portfolio-facing, not production.
- 3 Swarm managers; the active Portainer Server replica is constrained to `node.role==manager` so it can read the docker.sock for cluster operations.
- Swarm reschedules a failed Server replica onto a different manager automatically.

## Decision

### Edition: CE single-replica + global Agent

- **Server**: 1 replica, `node.role==manager` constraint, `replicas: 1` (Portainer CE has no native HA — running multiple replicas would race-condition the BoltDB).
- **Agent**: `mode: global` (1 task per node × 6 nodes), no constraint. Agent provides cluster-wide visibility for the Server replica.
- Communication via overlay network `agent_network` (attachable, driver=overlay) — Server reaches all 6 agents via `tasks.agent` DNS round-robin.

### Storage: NFSv4 from nexus-gateway

- **NFS server**: nexus-gateway (the existing edge router/DNS/NTP host).
- **Export**: `/srv/nfs/portainer-data` NFSv4-only (`fsid=0` makes it the NFSv4 pseudo-root; clients mount via `:/`).
- **Access control**: per-manager-IP allow on the export (`192.168.70.111(rw,sync,no_root_squash,...)`). Workers don't get access — Portainer Server runs only on managers.
- **Firewall**: gateway `/etc/nftables.conf` patched in-place to allow tcp/2049 from the 3 manager IPs only. No DNS/portmapper/lockd dynamic ports because NFSv4-only.
- **Per-manager mount**: `/var/lib/portainer-data` via NFSv4.2 (`hard,bg,_netdev` for boot-survivability + I/O reliability). Bind-mounted into the Portainer container as `/data:/data`.

### Why nexus-gateway hosts NFS (not a dedicated VM)

- **Gateway already plays infra-host role** (dnsmasq + nftables NAT + chrony + node_exporter). Adding nfs-kernel-server doesn't compromise its purpose.
- **No new tier in vms.yaml** = lower portfolio churn. Adding a `08-storage/` tier or a dedicated NFS VM would require a Packer template + Terraform module + smoke + ADR for ANOTHER architectural artefact, all to host one filesystem export.
- **Lab-pragmatic, with explicit production deviation note.** Production would split NFS onto a dedicated appliance (NetApp, TrueNAS, Pure Storage, etc.). The deviation is documented in the role-overlay's preamble + at the canon-batch sub-phase. Future portfolio work might add a `nexus-infra-storage/` repo with a real NFS appliance — this ADR's "lab consolidates state services on the edge router" pattern is explicitly NOT canonical for production.

### Why CE (not EE)

- No commercial license; not pursuing one for the lab.
- Single-replica + Swarm-reschedule + shared NFS state is functionally adequate for the lab's HA story:
  - Manager-1 hosting Server crashes → Swarm reschedules to manager-2 → manager-2 mounts the SAME NFS `/data` → BoltDB state preserved → operator login still works.
  - Failover RTO: ~30s (Swarm task-respawn delay + Portainer init). Acceptable for lab.
- Deferred-EE migration path: if a real workload mandates HA active/active (multi-region writes, sub-second failover, etc.), revisit. EE's HA model uses the same `/data` directory shape; adding it later means license + replication-tuning, not structural rework.

## Consequences

**Positive:**
- Single-tier integration (gateway already exists; no new VMs).
- TLS via Vault PKI's `pki_int/roles/portainer-server` role with shared CN `portainer.nexus.lab` + per-manager IP SANs — same cert validates regardless of which manager is hosting the active replica.
- dnsmasq multi-A `host-record=portainer.nexus.lab,IP1,IP2,IP3` gives any manager IP as a connect target; Swarm's routing mesh routes to the active replica.
- Admin password sticky-seeded at `nexus/portainer/admin-bcrypt` (bcrypt + plaintext); operator retrieves plaintext via `vault kv get`.

**Negative / accepted:**
- **Single point of failure**: nexus-gateway. If it dies, NFS goes with it. Mitigation: gateway is also the dnsmasq + NAT host, so its loss takes down the lab anyway. Acceptable single-fate-share for portfolio purposes.
- **`no_root_squash` on the NFS export**: Portainer CE runs as UID 0 in-container; BoltDB writes need root ownership on the share. Lab-acceptable; production would map to a non-root UID via NFSv4 idmap.
- **CE has no native HA**: rescheduled Server replica needs ~30s to re-init from BoltDB. No simultaneous-active replicas. For Portainer's role (operator UI, not data-plane), acceptable.
- **`flush ruleset` + Docker iptables-nft conflict** (see ADR-0018): the nftables overlay must restart dockerd after `nft -f` to rebuild Docker's ingress mesh rules. Choreographed sequentially in `role-overlay-portainer-firewall.tf`.

**Future migration paths:**
- **EE upgrade**: if a license becomes available, switch image tag + add `--license-key` flag. State on NFS is forward-compatible.
- **Dedicated NFS appliance**: stand up `nexus-infra-storage` repo with a TrueNAS or similar. Migrate Portainer's `/data` via `rsync` cutover during a maintenance window. The portainer-stack overlay's bind-mount only needs a single env var change.
- **K8s migration**: Portainer Edge agents talk to Kubernetes clusters via the same agent network. Phase 0.E.4 lays this foundation; Phase 0.G+ K8s clusters will register as Portainer endpoints.

## Operational artefacts

- Code: `nexus-infra-vmware/terraform/envs/foundation/role-overlay-gateway-nfs-portainer.tf`, `role-overlay-gateway-portainer-dns.tf`
- Code: `nexus-infra-vmware/terraform/envs/security/role-overlay-vault-pki-portainer.tf`, `role-overlay-vault-portainer-admin-seed.tf`
- Code: `nexus-infra-swarm-nomad/terraform/envs/swarm-nomad/role-overlay-portainer-{nfs-mount,tls,admin-render,stack,firewall}.tf`
- Smoke: `scripts/smoke-0.E.4.ps1` — ~30 0.E.4-specific probes covering NFS server + per-manager mount + TLS render + DNS + admin-bcrypt KV + admin-password file render + stack deploy + HTTPS:9443 with valid CA chain
- Operator runbook: `nexus-infra-swarm-nomad/docs/handbook.md` §3 (admin-password retrieval, NFS troubleshooting)
- Lesson memorials: `feedback_nfsv4_fsid0_pseudo_root.md`, `feedback_vault_agent_template_hcl_heredoc.md`, `feedback_nftables_flush_ruleset_wipes_docker.md`
