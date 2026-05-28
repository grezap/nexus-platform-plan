# ADR-0039 · Phase 0.M: Foundation HA — 2nd AD DC (`dc-nexus-2`) via `Install-ADDSDomainController`

**Status:** accepted
**Date:** 2026-05-28
**Phase:** 0.M
**Scope:** `nexus-infra-vmware/terraform/envs/foundation/` (the `dc_nexus_2` module + the `dc_nexus_2_promotion` overlay) + `nexus-platform-plan/docs/infra/vms.yaml` (foundation cluster row).

## Context

Through Phase 0.D the lab ran a single AD domain controller (`dc-nexus`). Every other lab role — Vault `auth/ldap`, every domain-joined member server, every workload that requires Kerberos for SQL/Kafka/Spark — depends on AD for identity. A `dc-nexus` outage takes the entire fleet offline for auth/DNS regardless of how HA the other tiers are. This is the last single-point-of-failure in the foundation.

Phase 0.M was committed 2026-05-22 (see [planned-sharding-ha-enhancements memory](../../../nexus-infra-vmware/memory/project_planned_sharding_ha_enhancements.md)) to close it: a second replica DC, multi-master replication, replicated DNS, DC Locator failover. Scheduled AFTER 0.G.5/0.G.6 + 0.L + 0.I (deliberate — the HA tiers below need to be in place before the foundation HA story is meaningful).

## Decision

Add a single replica DC `dc-nexus-2` to the existing `nexus.lab` forest, in the same site (`Default-First-Site-Name`), promoted via `Install-ADDSDomainController` from the existing `ws2025-desktop` Packer template. No site separation, no read-only DC (RODC), no separate cluster.

### Key sub-decisions

1. **One replica DC, not two.** The lab is single-host (one Workstation Pro instance, one physical machine); a 3-DC fleet would not improve HA, it would just consume more RAM. Two DCs already deliver the multi-master + failover invariant; production multi-site clusters with 3+ DCs are a different topology and deferred.

2. **No site separation.** Both DCs sit in `Default-First-Site-Name` on the same VMnet11 subnet. Cross-site replication (a third site with its own subnet) is an interesting production pattern but adds no HA value in a single-host lab.

3. **Same template, same OS.** `dc-nexus-2` clones from the same `ws2025-desktop` Packer template as `dc-nexus`. No specialized "DC template" — the DC role gets installed at promotion time via `Install-WindowsFeature AD-Domain-Services`. Keeps the Packer surface small.

4. **DHCP-pool IP `.242`, no `dhcp-host` reservation.** Mirrors the actual reality of `dc-nexus@.240` + `jumpbox@.241`. The canonical `.10`/`.11` slots in `vms.yaml` remain a pre-existing canon-vs-reality drift (`dc-nexus` has always run at `.240` despite vms.yaml saying `.10`); realigning would have wide blast radius into every overlay that hardcodes `.240`. Decided 2026-05-28 (see role-overlay file header for the analysis).

5. **`.11` is owned by `sql-fci-1`.** vms.yaml had `dc-nexus-2` and `sql-fci-1` both at `.11` (scaffolding error). Sub-decision 4 resolves the conflict in favour of sql-fci-1's PROVEN OLTP cold-rebuild state (whose iSCSI tgt + WSFC IP-SAN cert + AG Listener all hardcode `.11`).

6. **7-step apply graph** (`rename` → `wait_renamed` → `join` → `wait_joined` → `promote` → `wait_promoted` → `verify`), mirroring the dc-nexus 5-step + jumpbox 3-step combined. Each `null_resource` is independently `-target`-able per [`feedback_selective_provisioning.md`](../../../nexus-infra-vmware/memory/feedback_selective_provisioning.md).

7. **`Install-ADDSDomainController` parameters.** `-DomainName nexus.lab -Credential NEXUS\nexusadmin -SafeModeAdministratorPassword <DSRM> -ReplicationSourceDC dc-nexus.nexus.lab -SiteName Default-First-Site-Name -InstallDns:$true -CreateDnsDelegation:$false -Force:$true -NoRebootOnCompletion:$false`. The `-NoRebootOnCompletion:$false` auto-reboots at the end; the `wait_promoted` resource polls for `(Get-ADDomain).Forest == nexus.lab` to come back up post-reboot.

8. **Domain admin credential = `NEXUS\nexusadmin`.** Reads from Vault KV at `nexus/foundation/identity/nexusadmin` (same path the rotate-bootstrap-creds overlay uses to sync KV → AD). DSRM password reads from `nexus/foundation/dc-nexus/dsrm`. No new KV paths.

9. **`sshd_config` patch in step 3 join.** Removes `AllowUsers nexusadmin` before the domain-join reboot. Same fix the jumpbox-domainjoin overlay applies — post-join the SSH user appears as `NEXUS\nexusadmin` which doesn't match the bare-username directive. Without this patch, SSH/22 to dc-nexus-2 would reject every login with "not allowed because not listed in AllowUsers" (the canonical fail described in [`feedback_addsforest_post_promotion.md`](../../../nexus-infra-vmware/memory/feedback_addsforest_post_promotion.md)).

10. **No Vault `auth/ldap` config change.** Phase 0.M ships the 2nd DC; the Vault `auth/ldap` config remains pinned to `dc-nexus.nexus.lab` post-0.M. Migrating `auth/ldap` to a round-robin `dc.nexus.lab` is a follow-up enhancement (DC Locator does most of the failover work at the AD client layer; Vault's go-ldap is single-target). Tracked as a 0.M.1 enhancement; not a 0.M blocker.

## Consequences

### Positive

- **Single-DC outage no longer cascades to fleet-wide auth/DNS outage.** A `vmrun stop dc-nexus hard` survives — domain members re-resolve `_ldap._tcp.nexus.lab` SRV records → land on dc-nexus-2 → keep working. Same for DNS forwards: `dc-nexus-2` also hosts the `nexus.lab` AD-integrated zone, replicated.
- **AD operations have failover.** `Get-ADUser`, `Set-ADAccountPassword`, GPO updates — all now work against either DC. The Vault `secrets/ldap` static-role rotations (which write to AD) continue working when dc-nexus is down (via DC Locator picking dc-nexus-2).
- **Foundation tier ratifies the production-grade HA story** that the OLTP/analytics/lakehouse/observability tiers have been claiming since Phase 0.G. The lab now matches its blueprint.
- **Cold-rebuild proven.** Phase 0.M ships with `smoke-0.M.ps1` (~25 checks) + a cold-rebuild proof (destroy + re-apply from zero → smoke ALL GREEN). Same bar as every other tier per [`feedback_zero_touch_autonomous_delivery.md`](../../../nexus-infra-vmware/memory/feedback_zero_touch_autonomous_delivery.md).

### Negative

- **+4 GB RAM** (`dc-nexus-2` matches `dc-nexus` at 4 GB). Foundation tier total 48 → 52 GB. Build host (128 GB) has plenty of slack.
- **Replication lag** (~5-15 sec in practice) introduces a tiny eventual-consistency window where a write to dc-nexus is not yet visible on dc-nexus-2. Acceptable for AD (the domain is built on eventual consistency); not relevant to any user-facing workflow.
- **DSRM password is shared between DCs** (`nexus/foundation/dc-nexus/dsrm` reused for `dc-nexus-2`). Microsoft best practice is per-DC DSRM; lab convenience trumps here. If we ever need DSRM on dc-nexus-2 specifically, rotate via RDP + ntdsutil per [`feedback_ntdsutil_dsrm_console_mode_ssh.md`](../../../nexus-infra-vmware/memory/feedback_ntdsutil_dsrm_console_mode_ssh.md).
- **Vault `auth/ldap` is still pinned to dc-nexus's IP.** When dc-nexus dies, Vault's LDAP login fails for ~30s until its connection re-establishes via DNS SRV (Vault's go-ldap respects DNS). Not zero-downtime; near-zero-downtime. The 0.M.1 enhancement to bump `auth/ldap.ldap_url` to `ldap://dc.nexus.lab:389` (round-robin DNS) is the explicit closure.

### Risks

- **Promotion is one-way.** Demoting dc-nexus-2 (if needed) requires `Uninstall-ADDSDomainController -DemoteOperationMasterRole -ForceRemoval` via RDP + reboot. Handbook §1m.5 documents the procedure.
- **Sysprep of dc-nexus-2's Packer template** is shared with dc-nexus + jumpbox + sql-fci-*. Any change to the underlying template requires re-validation across all consumers.

## Alternatives considered

1. **RODC (read-only DC) for dc-nexus-2.** Pros: smaller blast radius if dc-nexus-2 itself gets compromised. Cons: doesn't help with writes (rotate-creds, password resets) when dc-nexus is down. Rejected — defeats the purpose.

2. **3-DC fleet.** Pros: tolerates 2-DC loss. Cons: no incremental HA value in a single-host lab. Deferred to a multi-site production sizing exercise; not part of 0.M scope.

3. **Active Directory Application Mode (AD LDS) sidecar.** Pros: lighter than a full DC. Cons: doesn't replicate the forest's auth/DNS layer — only the directory data. Rejected; doesn't close the SPOF.

4. **Defer to "Phase 1+ production sizing."** Pros: less work now. Cons: every tier built since Phase 0.D claims HA but rests on a non-HA AD substrate — the portfolio narrative falls apart on close inspection. Rejected; foundation HA is foundational, can't be deferred indefinitely.

## See also

- [Phase 0.M tracker](../../../nexus-infra-vmware/memory/project_nexus_infra_phase.md) (project memory for nexus-infra-vmware)
- [`role-overlay-dc-nexus-2-promotion.tf`](../../../nexus-infra-vmware/terraform/envs/foundation/role-overlay-dc-nexus-2-promotion.tf) — the 7-step apply graph (with header comment + live-ratify checklist)
- [`scripts/smoke-0.M.ps1`](../../../nexus-infra-vmware/scripts/smoke-0.M.ps1) — ~25-check smoke gate
- [`docs/handbook.md` §1m](../../../nexus-infra-vmware/docs/handbook.md) — operator runbook
- [DEMO-19](../demos/DEMO-19.md) — persona demo: kill DC1, auth + DNS continue on DC2
- [`feedback_addsforest_post_promotion.md`](../../../nexus-infra-vmware/memory/feedback_addsforest_post_promotion.md) — post-promotion sshd_config + AD group remediation (carried into 0.M's join step)
- [`feedback_windows_ssh_automation.md`](../../../nexus-infra-vmware/memory/feedback_windows_ssh_automation.md) — 5 structural rules for Windows-over-SSH automation (all 5 baked into 0.M overlays)
