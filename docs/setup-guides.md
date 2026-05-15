# Setup guides — rebuild any tier from zero

The single discoverable entry point for **"how do I set up X from scratch?"**
across the whole NexusPlatform lab. Every tier we have built has an exact,
operator-runnable step-by-step replay in its repo's `docs/handbook.md`; this
page is the **index** into all of them, with prerequisites, machine-order,
wall-clock estimates, and a selective-ops cross-reference.

Per `feedback_handbook_standard.md`: every infra repo's handbook must contain
an EXACT from-zero replay path with §0 prereqs · §1.1 Packer build · §1.2
cross-env operator order · §1.3 apply · §1.4 verify · §1.5 selective ops ·
§1.6 destroy · §3.1 cold-rebuild canon. This page is the cross-tier index;
each row links to the canonical detail.

## Inventory — what the lab has built so far (28 VMs across 4 tiers)

| Tier | Repo | VMs | Phase |
|---|---|---|---|
| **00-edge** | `nexus-infra-vmware` (`envs/foundation`) | `nexus-gateway` (1) | 0.B.1 |
| **01-foundation** | `nexus-infra-vmware` (`envs/foundation` + `envs/security`) | `dc-nexus`, `nexus-jumpbox`, `vault-1/2/3`, `vault-transit` (6) | 0.C.1-0.D.5 |
| **06-orchestration** | `nexus-infra-swarm-nomad` (`envs/swarm-nomad`) | `swarm-manager-1/2/3`, `swarm-worker-1/2/3` (6) | 0.E |
| **03-kafka** | `nexus-infra-kafka` (`envs/kafka`) | `kafka-east-1/2/3`, `kafka-west-1/2/3`, `schema-registry-1/2`, `kafka-rest-1`, `kafka-connect-1/2`, `ksqldb-1/2`, `mm2-1/2` (15) | 0.H |

**Total: 28 VMs. All tiers tagged + cold-rebuildable as of 2026-05-15.**

## Per-tier from-zero replay matrix

The canonical answer to **"how do I set up tier X from scratch?"** — every row
links to an exact handbook section with the commands, the machine-order, the
verification, and the selective-ops examples.

| To set up… | Go to (the canonical replay path) | Hard prereqs (which VMs MUST be alive first) | Time |
|---|---|---|---|
| **`nexus-gateway`** (edge: nftables masquerade + dnsmasq + NFSv4 + chrony) | [`nexus-infra-vmware/docs/handbook.md` §A](https://github.com/grezap/nexus-infra-vmware/blob/main/docs/handbook.md) (the gateway is step 1 of the foundation-tier replay) | None — `nexus-gateway` is VM #0 of the whole lab | ~5-10 min |
| **The foundation tier** (`nexus-gateway` + `dc-nexus` + `nexus-jumpbox` + AD DS forest) | [`nexus-infra-vmware/docs/handbook.md` §A — Foundation tier from zero](https://github.com/grezap/nexus-infra-vmware/blob/main/docs/handbook.md) | One-time host prep (§0 of vmware handbook) | ~45-60 min |
| **The security tier** (3-node Vault HA Raft + `vault-transit` + PKI hierarchy + LDAPS + `secrets/ldap` rotation + foundation-cred KV migration + 0.D.5 stack) | [`nexus-infra-vmware/docs/handbook.md` §B — Security tier from zero](https://github.com/grezap/nexus-infra-vmware/blob/main/docs/handbook.md) | Foundation tier **alive** (§A above must be ALL GREEN) | ~30-45 min |
| **The orchestration tier** (6-node Docker Swarm + Nomad + Consul + Portainer CE, mTLS end-to-end) | [`nexus-infra-swarm-nomad/docs/handbook.md` §1 — Phase 0.E full tier bring-up](https://github.com/grezap/nexus-infra-swarm-nomad/blob/main/docs/handbook.md) | Foundation tier **alive** + security tier **alive** (Vault HA serves the per-node Vault Agents) | ~25-35 min |
| **The Kafka tier** (two 3-node KRaft clusters + Schema Registry + REST Proxy + Connect + Debezium + ksqlDB + MirrorMaker 2) | [`nexus-infra-kafka/docs/handbook.md` §1 — Phase walkthrough](https://github.com/grezap/nexus-infra-kafka/blob/main/docs/handbook.md) | Foundation tier **alive** + security tier **alive** (the kafka env reads per-host AppRole sidecars from the security env at plan time) | ~30-40 min |

## Selective ops index — "set up only X"

Every tier supports **selective bring-up** — you can apply only one VM, only one
cluster, only one overlay. The toggles are documented in each handbook's §1.x
iteration section with copy-pasteable `-Vars` examples.

| To set up only… | Command (handbook reference) |
|---|---|
| Only `nexus-gateway` (skip the 3 Windows VMs + AD overlays) | `pwsh -File scripts\foundation.ps1 apply -Vars enable_dc_nexus=false, enable_jumpbox=false, enable_ad_ds=false, enable_jumpbox_join=false, enable_ad_hardening=false` — vmware handbook §A |
| Only `dc-nexus` (skip jumpbox + hardening) | `pwsh -File scripts\foundation.ps1 apply -Vars enable_jumpbox=false, enable_jumpbox_join=false` — vmware handbook §A |
| Only the Vault HA cluster (skip transit + PKI + LDAPS) | `pwsh -File scripts\security.ps1 apply -Vars enable_vault_transit=false, enable_vault_pki=false, enable_vault_ldap=false, ...` — vmware handbook §B |
| Only the kafka-tier Vault-side state (re-apply just the AppRoles + sidecars before a kafka rebuild) | `pwsh -File scripts\security.ps1 apply -Vars enable_kafka_agent_setup=true` — vmware handbook §B |
| Only the 3 Swarm managers (skip workers + cluster init) | `pwsh -File scripts\swarm.ps1 apply -Vars enable_swarm_worker_1=false, enable_swarm_worker_2=false, enable_swarm_worker_3=false, enable_swarm_init=false` — swarm-nomad handbook §1.4 |
| Iterate on the swarm cluster bring-up alone (assumes clones already exist) | `pwsh -File scripts\swarm.ps1 apply -Vars enable_swarm_init=true` — swarm-nomad handbook §1.4 |
| Only the east KRaft cluster (skip west + all ecosystem nodes) | `pwsh -File scripts\kafka.ps1 apply -Vars enable_kafka_west=false, enable_schema_registry=false, enable_kafka_rest=false, enable_kafka_connect=false, enable_ksqldb=false, enable_mm2=false` — kafka handbook §1.5 |
| Only the MirrorMaker 2 overlay (assumes the rest of the tier is up) | `pwsh -File scripts\kafka.ps1 apply -Vars enable_mm2_config=true` — kafka handbook §1.5 |

> **Gotcha (`feedback_terraform_partial_apply_destroys_resources.md`):** every
> `-Vars` invocation is the FULL override set for that apply — vars not passed
> default back, and `count = var.X ? 1 : 0` resources get **destroyed**. The
> defaults reflect steady state (everything enabled), so omitting `-Vars`
> entirely is the safe path. Use `-Vars` only when you genuinely want to skip
> something.

## Full-lab cold rebuild — every tier from zero, in dependency order

The absolute "rebuild everything from cold metal" path. Each step references the
canonical handbook section; this page just gives you the order.

```pwsh
# ─── PRE-FLIGHT (once) ─────────────────────────────────────────────────────
# Host-host prep: install Packer, Terraform, VMware Workstation Pro, OpenSSH,
# create VMnet10 + VMnet11, load the lab SSH key into ssh-agent.
# See: nexus-infra-vmware/docs/handbook.md §0.

# Then build every Packer template the 28-VM fleet needs (~45-60 min total):
cd nexus-infra-vmware\packer\deb13          && packer init . && packer build .
cd ..\ws2025-desktop                         && packer init . && packer build .
cd ..\vault                                  && packer init . && packer build .
cd ..\..\..

cd nexus-infra-swarm-nomad\packer\swarm-node && packer init . && packer build .
cd ..\..\..

cd nexus-infra-kafka\packer\kafka-node       && packer init . && packer build .
cd ..\..\..

# ─── TIER 1 — FOUNDATION (must come up FIRST, every other tier depends on it) ─
cd nexus-infra-vmware
pwsh -File scripts\foundation.ps1 apply        # ~45-60 min
pwsh -File scripts\foundation.ps1 smoke        # ALL GREEN -- gateway + dc-nexus + jumpbox + AD healthy

# ─── TIER 2 — SECURITY (Vault HA + transit + PKI + LDAPS; foundation must be alive) ─
pwsh -File scripts\security.ps1   apply        # ~30-45 min
pwsh -File scripts\security.ps1   smoke        # ALL GREEN -- vault-1/2/3 + vault-transit + PKI + LDAPS
cd ..

# ─── TIER 3 — ORCHESTRATION (Swarm + Nomad + Consul + Portainer; needs foundation + security) ─
cd nexus-infra-swarm-nomad
pwsh -File scripts\swarm.ps1      apply        # ~25-35 min -- full Phase 0.E (0.E.1 + 0.E.2 + 0.E.3 + 0.E.4 + 0.E.4e)
pwsh -File scripts\swarm.ps1      smoke -Phase 0.E.4e   # ~180 chained checks ALL GREEN
cd ..

# ─── TIER 4 — KAFKA (KRaft + SR + REST + Connect + ksqlDB + MM2; needs foundation + security) ─
cd nexus-infra-kafka
pwsh -File scripts\kafka.ps1      apply        # ~30-40 min -- 15 clones + firstboot + overlays + exit-gate test
foreach ($p in '0.H.2','0.H.3','0.H.4','0.H.5') {
    pwsh -File scripts\kafka.ps1  smoke -Phase $p
}
# Expect: ALL <p> SMOKE CHECKS PASSED for each (215 total checks across the 4 gates).
# 0.H.1 is the PLAINTEXT-era gate -- its plaintext probes correctly fail once
# 0.H.2 flips the brokers to mTLS, so it is NOT part of a built-tier sweep.
```

**Total wall-clock for a true cold rebuild of the whole 28-VM lab:** ~3 hours
(dominated by Packer builds the first time; subsequent rebuilds reuse the
templates and run in ~2 hours).

## Where the per-tier deep canon lives

For each tier the handbook is the **operator** canon (commands, machine-order,
recovery playbooks). The **architectural** canon lives elsewhere:

- **Architectural decisions:** [`nexus-platform-plan/docs/adr/`](./adr/) —
  ADRs 0011-0019 cover the foundation + orchestration tiers (Vault HA · PKI ·
  LDAPS · KV creds · Transit auto-unseal · Nomad-Vault · Portainer-NFS ·
  nftables/Docker conflict · TLS full-chain on the wire); ADRs 0020-0023 cover
  the Kafka tier (KRaft combined-mode · Kafka-tier mTLS · overlay
  `depends_on` discipline · MM2 dedicated-mode).
- **VM inventory:** [`docs/infra/vms.yaml`](./infra/vms.yaml) — every VM the
  lab will eventually run, with hostnames, IPs, MAC reservations, OS, RAM/CPU
  ratification notes.
- **Network canon:** [`docs/infra/network.md`](./infra/network.md) — VMnet10
  (backplane) + VMnet11 (mgmt + app) third-octet conventions.
- **Per-sub-phase verification records:** every repo's `docs/verification/`
  directory — what the smoke gate proved, what got fixed during the run.

## Operator handbooks (one per infra repo)

The "operator level" canon — commands, machine-order, recovery playbooks — lives
in each infra repo's `docs/handbook.md`:

- **`nexus-infra-vmware/docs/handbook.md`** — foundation tier (§A) + security
  tier (§B) Quick replay paths at the top; chronological per-phase walkthrough
  (§0 → §1 → §1a-§1k) as deep canon underneath.
- **`nexus-infra-swarm-nomad/docs/handbook.md`** — §0 prereqs · §1 full Phase
  0.E walkthrough · §2 phase status · §3 operator runbooks (incl. §3.6
  cold-rebuild canon + §3.7 0.E.4e apply pattern).
- **`nexus-infra-kafka/docs/handbook.md`** — the canonical exemplar. §0 prereqs
  · §1.1-§1.6 walkthrough · §2 phase status · §3 runbooks (incl. §3.1
  cold-rebuild canon + §3.4 the Kafka-CLI-`sudo` rule + §3.7 apply-time VM-layer
  recovery).
