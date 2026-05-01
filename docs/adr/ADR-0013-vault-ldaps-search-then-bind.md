# ADR-0013 — LDAPS to AD via search-then-bind without `upndomain`; `secrets/ldap` over deprecated `ad`

- **Status**: Accepted
- **Date**: 2026-05-01 (Phase 0.D.3 close-out)
- **Deciders**: Greg Zapantis
- **Supersedes**: original 0.D.3 plain-LDAP/389 design (rejected mid-phase after the LDAPServerIntegrity 2/1/0 sweep)
- **Superseded by**: —
- **Related**: ADR-0011 (Vault cluster), ADR-0012 (PKI issues the LDAPS leaf), `MASTER-PLAN.md` Phase 0.D.3, `docs/infra/network.md`

## Context

Phase 0.D.3 wires Vault to AD: humans login via `vault login -method=ldap`; `secrets/ldap` rotates passwords on AD service accounts (`svc-demo-rotated` daily). Two cross-cutting choices forced explicit decisions:

1. **Transport: plain LDAP/389 vs LDAPS/636.** Originally scoped as plain-LDAP because the 0.D LDAPS was intended for 0.D.5. Empirically, plain-LDAP simple bind from non-Windows clients (Vault's go-ldap) fails wholesale in this AD env regardless of `LDAPServerIntegrity` (tested values 2 / 1 / 0 — all reject). The error is `LDAP Result Code 8 "Strong Auth Required"` even when `LDAPServerIntegrity=0` (which the docs claim accepts unsigned binds).
2. **Engine: deprecated `ad` vs unified `secrets/ldap`.** Vault's original `ad` secrets engine was deprecated when the unified `secrets/ldap` engine became GA in Vault 1.12. The `ldap` engine handles both AD and OpenLDAP via `schema=ad|openldap|racf|...`.
3. **Bind shape: search-then-bind vs UPN-bind.** A subtle Vault behavior: `auth/ldap/config`'s `upndomain` field, when set, silently rewrites `{{.Username}}` in `userfilter` to `<user>@<upndomain>` before the search executes. This works for UPN-bind flows but breaks search-then-bind: the userfilter `(&(objectClass=user)(sAMAccountName={{.Username}}))` becomes `(... sAMAccountName=svc-vault-smoke@nexus.lab ...)` which AD never matches (sAMAccountName has no @-suffix). Vault issue #27276; pre-1.19 there's no opt-out flag.

## Decision

1. **Transport: LDAPS pulled forward from 0.D.5 to 0.D.3.** Mid-phase deviation; canon-mapping table in the 0.D.3 commit log + `feedback_master_plan_authority.md` deviation note. The `vault_ldaps_cert` overlay issues a leaf cert from `pki_int/issue/vault-server` for `dc-nexus.nexus.lab`, installs into dc-nexus's `LocalMachine\My`, restarts NTDS. AD then auto-discovers the cert and serves LDAPS on TCP/636. Vault's `auth/ldap` and `secrets/ldap` both bind via `ldaps://192.168.70.240:636` with the PKI root CA bundle inline as the `certificate` field.
2. **Engine: `secrets/ldap` (`schema=ad`).** Configures `password_policy=nexus-ad-rotated` (Vault password policy with AD complexity-compatible character classes + 24 chars). Static rotate-role for `svc-demo-rotated` with `rotation_period=24h` rotates the AD password daily; consumers read via `vault read ldap/static-cred/svc-demo-rotated`.
3. **Bind: search-then-bind with `upndomain=""`.** Vault binds as `svc-vault-ldap` (the bind account in `OU=ServiceAccounts`), runs the literal userfilter `(&(objectClass=user)(sAMAccountName={{.Username}}))`, gets the user's DN, then rebinds as that DN with the user-supplied password. `upndomain` left empty so the userfilter executes verbatim.
4. **AD-side delegation.** The `svc-vault-ldap` bind account holds 4 ACEs on `OU=ServiceAccounts` (Reset Password extended right, Change Password extended right, RP/WP on `userAccountControl`) — delegated via `dsacls /I:S` (NEVER via Account Operators shortcut, which over-permissions). Without these ACEs, `vault write -force ldap/rotate-role/<name>` fails with `LDAP Result Code 50 INSUFF_ACCESS_RIGHTS`.
5. **Onboarding gotcha: `skip_import_rotation=true` + explicit force-rotate.** Fresh AD onboarding requires `skip_import_rotation=true` on the static-role + `skip_static_role_import_rotation=true` on the engine config + an explicit `vault write -force ldap/rotate-role/<name>` to take ownership. Default behavior tries to bind as the target account with the AD-side initial password (which Vault doesn't know) and fails AD `data 52e`.
6. **AD-group → policy mapping.** `nexus-vault-admins` → `nexus-admin` (full sudo); `nexus-vault-operators` → `nexus-operator` (read/write `nexus/*` + cert issuance, no sudo); `nexus-vault-readers` → `nexus-reader` (read-only).

## Consequences

### Positive

- Vault becomes the only auth surface for human ops on the lab. Every login is auditable + AD-group-mapped.
- AD password rotation is Vault-managed: `svc-demo-rotated`'s password rotates daily without human touch; consumers read the current value via `static-cred`.
- Search-then-bind without `upndomain` correctly handles AD's `sAMAccountName` semantics; UPN-bind path stays available for future use cases via separate `auth/ldap/config` writes.
- LDAPS leaf cert chains through ADR-0012's intermediate; same trust anchor as Vault listeners. Operator workflow doesn't need a second CA bundle.

### Negative / accepted

- LDAPS requires AD to serve a server cert with EKU `serverAuth` and SAN matching the FQDN clients connect to. dc-nexus's cert is reissued from `pki_int/` on every security env apply — works, but the cert install + NTDS restart is the longest single step in the security-env apply (~30 s).
- Bind account cred lives in Vault KV (`nexus/foundation/ad/svc-vault-ldap`, written by 0.D.4 seed). If the bind cred ever rotates, the operator must re-apply the security env to push the new bindpass into `auth/ldap/config`. Documented in handbook §1i.
- Pre-1.19 has no `enable_samaccountname_login` flag; we work around via empty `upndomain`. When Vault bumps to 1.19+, this overlay can simplify.

### Neutral

- The `secrets/ldap` engine's `schema=ad` covers our use case (AD password rotation). Future OpenLDAP integration would mount a separate path (e.g., `secrets/ldap-openldap`) with `schema=openldap`.

## Lessons captured (now memory canon)

- `feedback_ad_ldap_simple_bind_signing.md` — modern AD rejects ALL plain-LDAP simple binds from non-Windows clients regardless of `LDAPServerIntegrity` setting (signing-required is conceptually orthogonal but practically gated together).
- `feedback_vault_ldap_ad_upn_bind.md` — `upndomain` silently rewrites `{{.Username}}` in userfilter (Vault issue #27276); default empty for LDAPS+search-then-bind.
- `feedback_vault_ldap_ad_acl_delegation.md` — bind account needs 4 specific ACEs on the target OU; delegate via `dsacls`, never Account Operators.
- `feedback_vault_ldap_static_role_skip_import.md` — fresh AD onboarding requires the 3-state import-rotation incantation.
- `feedback_ad_ldaps_required_for_password_writes.md` — AD hard-requires LDAPS/StartTLS for `unicodePwd` writes regardless of signing.

## Operational rules

- Smoke: `pwsh -File scripts\security.ps1 smoke -Phase 0.D.3`. Probes LDAPS port reachability, auth/ldap config shape, group → policy mappings, end-to-end smoke login as `svc-vault-smoke`, secrets/ldap config, static-role rotate cadence.
- Force-rotate `svc-demo-rotated` on demand: `vault write -force ldap/rotate-role/svc-demo-rotated`.
- Adding a new rotated AD account: create the AD account in `OU=ServiceAccounts` (foundation env overlay), then add a `static-role` overlay in security env mirroring the demo-rotated shape.
- Bindpass rotation: edit `nexus/foundation/ad/svc-vault-ldap` in Vault KV, then `terraform apply -target=null_resource.vault_ldap_auth` to push the new bindpass into `auth/ldap/config`.
