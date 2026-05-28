# DEMO-19 · Foundation HA: kill the primary AD DC — auth and DNS survive

## 1. What this shows

NexusPlatform's foundation tier has two domain controllers in multi-master replication. This demo destroys one mid-flight: an operator kills `dc-nexus` (the original forest root) while a workload is mid-authenticate, mid-DNS-resolve, and mid-LDAPS-bind. The replica DC `dc-nexus-2` continues to serve every role, the workload doesn't notice, and Vault's `auth/ldap` (which was pointed at the dead DC) follows over to the survivor with no operator intervention. The single-DC SPOF that survived Phase 0.D is closed.

Personas: **infra engineer** (HA verification), **platform owner** (BCDR story), **security engineer** (Vault LDAP failover).

## 2. Runtime + prerequisites

- **Environment target** — `full` (or any env that has Phase 0.M applied — the 2nd DC is a foundation-tier change so it's in scope for every downstream env).
- **VMs required** — `nexus-gateway` · `dc-nexus` · `dc-nexus-2` · `vault-1`/`vault-2`/`vault-3` (LDAP consumer) · `nexus-jumpbox` (domain member used to confirm logon survives DC1 loss). Cluster definitions in [`docs/infra/vms.yaml`](../infra/vms.yaml).
- **External services** — Vault `auth/ldap` config (uses the round-robin DNS in the `ldap_url`); KV path `nexus/foundation/identity/svc-vault-smoke` for the smoke login.
- **Seed data** — none. Demo uses the `svc-vault-smoke` AD account already provisioned by the 0.D.3 overlay.
- **Expected duration** — 10–12 min wall-clock.
- **Reset command** — `nexus-cli demo run DEMO-19 --reset` (power cycle `dc-nexus` back on; verify replication catches up; restore Vault LDAP config to `dc-nexus.nexus.lab` if it was bumped to `dc-nexus-2.nexus.lab` during the demo).

## 3. Architecture snapshot

Two DCs in `01-foundation` tier; both register A records + SRV records for `_ldap._tcp.nexus.lab`; both serve the `nexus.lab` zone (AD-integrated, multi-master). The gateway's dnsmasq forwards `nexus.lab` queries to either DC (round-robin). Vault `auth/ldap`'s `ldap_url` could be a single DC (canonical post-0.D.3 state) or both (post-0.M enhancement). Workload consumers (`nexus-jumpbox`, every other domain-joined VM) resolve DC SRVs via DNS — DC Locator picks a live one automatically.

Static fallback at `assets/DEMO-19/architecture.png`.

## 4. Step-by-step script

1. **Action.** Run `nexus-cli demo run DEMO-19` from the build host.
   **Expected observable.** CLI prints `starting DEMO-19: Foundation HA — kill DC1, watch DC2 carry the load` followed by a 6-check readiness probe (both DCs Get-ADDomain healthy, replication PASS via `repadmin /replsummary`, Vault `auth/ldap` enabled, `svc-vault-smoke` AD account present, jumpbox domain-joined, gateway dnsmasq up). Pauses with `press Enter to begin`.
   **Screenshot.** `assets/DEMO-19/step-01.png`

2. **Action.** Press Enter — CLI authenticates to Vault using `svc-vault-smoke` via `auth/ldap` (current `ldap_url` = `ldap://192.168.70.240:389`, which is dc-nexus). Token granted.
   **Expected observable.** CLI prints `auth/ldap login OK (token issued by dc-nexus); ttl=24h`.
   **Screenshot.** `assets/DEMO-19/step-02.png`

3. **Action.** CLI starts a background loop: every 5 seconds, resolve `dc-nexus.nexus.lab` via Get-ADDomainController and do a fresh `auth/ldap` login. Loop output streams to stdout.
   **Expected observable.** Lines like `[t+5s] DC=dc-nexus, login OK (token=hvs.XXX...)`. Steady cadence.
   **Screenshot.** `assets/DEMO-19/step-03.png`

4. **Action.** CLI prompts `press Enter to KILL dc-nexus` — operator confirms.
   **Expected observable.** CLI runs `vmrun stop dc-nexus hard` from the build host. dc-nexus drops off the network within 2 seconds.
   **Screenshot.** `assets/DEMO-19/step-04.png`

5. **Action.** The background loop continues.
   **Expected observable.** For ~15 seconds the loop emits `[t+NNs] login FAILED: connection refused` — Windows DC Locator cache still pointing at dc-nexus. Then automatically switches: `[t+30s] DC=dc-nexus-2, login OK (token=hvs.YYY...)`. From here every loop iteration is green; Vault's `auth/ldap` re-resolves the DC SRV records when its current LDAP connection breaks, and picks dc-nexus-2 (the only live DC).
   **Screenshot.** `assets/DEMO-19/step-05.png`

6. **Action.** Switch to the jumpbox (RDP into `nexus-jumpbox` at 192.168.70.241). Try to open MMC + Active Directory Users and Computers.
   **Expected observable.** MMC connects to `dc-nexus-2` automatically (DC Locator picks the only live DC). OU tree visible, accounts editable.
   **Screenshot.** `assets/DEMO-19/step-06.png`

7. **Action.** On the jumpbox, run `nltest /dsgetdc:nexus.lab`. Then on dc-nexus-2 (via SSH from the build host): `Get-ADReplicationFailure -Target dc-nexus-2.nexus.lab`.
   **Expected observable.** `nltest` shows dc-nexus-2 as the located DC. `Get-ADReplicationFailure` shows a single FAIL row for dc-nexus (expected — it's powered off; the failure clears on power-on).
   **Screenshot.** `assets/DEMO-19/step-07.png`

8. **Action.** Power dc-nexus back on (`vmrun start dc-nexus`). Wait ~3 min for boot + AD DS bootstrap.
   **Expected observable.** dc-nexus boots; replication catches up automatically (USN backlog from dc-nexus-2 flows in). `Get-ADReplicationFailure` returns 0 failures within ~5 min. Both DCs healthy again.
   **Screenshot.** `assets/DEMO-19/step-08.png`

9. **Action.** CLI emits final summary.
   **Expected observable.** `DEMO-19 PASS. Auth uninterrupted across DC1 loss (max gap: 30s). DNS continued via dc-nexus-2. Vault auth/ldap follow-over: AUTOMATIC. Replication recovery: AUTOMATIC after DC1 power-on. Single-DC SPOF closed.`
   **Screenshot.** `assets/DEMO-19/step-09.png`

## 5. Observability trail

- **Grafana** — dashboard `foundation-ha` panels: `AD DC count up` (drops 2→1 at step 4, back to 2 at step 8), `Vault auth/ldap login rate` (steady), `Vault auth/ldap failure rate` (spike 5/5s at step 4 → 0 after step 5).
- **Loki** — query `{job="vault"} |= "auth/ldap"` shows the brief connection-refused burst then resumption against dc-nexus-2.
- **Tempo** — N/A for this demo (no app-level distributed traces involved; pure infra HA).
- **Marquez** — N/A.
- **URLs** — Grafana dashboard `https://grafana.nexus.lab/d/foundation-ha`.

## 6. Code pointers

- [`nexus-infra-vmware/terraform/envs/foundation/role-overlay-dc-nexus-2-promotion.tf`](https://github.com/grezap/nexus-infra-vmware/blob/main/terraform/envs/foundation/role-overlay-dc-nexus-2-promotion.tf) — the 7-step apply graph that lands dc-nexus-2 (rename → wait → join → wait → promote → wait → verify).
- [`nexus-infra-vmware/scripts/smoke-0.M.ps1`](https://github.com/grezap/nexus-infra-vmware/blob/main/scripts/smoke-0.M.ps1) — the 25-check smoke gate that proves replication round-trip + 2-DC visibility.
- [`nexus-infra-vmware/docs/handbook.md` §1m](https://github.com/grezap/nexus-infra-vmware/blob/main/docs/handbook.md) — operator runbook + selective ops + manual recovery procedures.

## 7. Variations

- **Power off dc-nexus-2 instead.** Same gap (Windows DC Locator cache TTL ≈ 15-30s); workload follows back to dc-nexus.
- **Network-partition (not power-off) dc-nexus.** dc-nexus stays alive but unreachable from VMnet11; replication queue builds. Recovers on partition heal; no manual reconciliation needed.
- **Kill dc-nexus DURING a Vault `auth/ldap` config change.** The config-write commits to Vault (Vault Raft, independent of the AD layer); the new config takes effect on next LDAP request and routes to dc-nexus-2.

## 8. Troubleshooting

| Symptom | Cause | Recovery |
|---|---|---|
| Vault `auth/ldap` login fails for >60s after step 4 | `ldap_url` is hard-pinned to `ldap://192.168.70.240:389` (single-DC IP) | Bump `auth/ldap` config to `ldap://dc.nexus.lab:389` (round-robin DNS resolves to whichever DC is live) — committed at 0.M close-out. |
| DC Locator on jumpbox returns dc-nexus despite step 4 | `Netlogon` cache stale | `nltest /sc_reset:nexus.lab` from jumpbox; cache clears immediately. |
| Replication doesn't recover after step 8 | Time drift (W32Time) > 5 min between DCs | `w32tm /resync` on both DCs; check `(Get-Service W32Time).Status -eq 'Running'`. |
| **Panic button:** | revert demo state | `pwsh -File scripts\foundation.ps1 apply` — re-applies the steady-state config; powers dc-nexus back on if needed. |

## 9. What this proves

- **.NET engineering + architecture** — the Vault Agent on every member server (Phase 0.D.5.4) doesn't break across DC1 loss — its renewer reads from the local Vault Raft cluster, not directly from AD. Production-grade decoupling of identity from auth-server availability.
- **Advanced SQL + analytics** — N/A for this scenario (no SQL workload in scope).
- **Python** — N/A in scope.
- **DevOps** — multi-master AD with automatic DC Locator failover, replicated DNS, Vault `auth/ldap` follow-over via SRV resolution, zero-touch recovery on DC1 power-on. The HA promise is hardware-level, not just "I drew it on a slide."
