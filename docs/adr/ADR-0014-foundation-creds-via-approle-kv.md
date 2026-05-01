# ADR-0014 — Foundation env reads bootstrap creds from Vault KV via AppRole-authenticated `vault_kv_secret_v2` data sources

- **Status**: Accepted
- **Date**: 2026-05-01 (Phase 0.D.4 close-out)
- **Deciders**: Greg Zapantis
- **Supersedes**: plaintext variable defaults in `terraform/envs/foundation/variables.tf` (DSRM, local Administrator, nexusadmin, Vault userpass)
- **Superseded by**: —
- **Related**: ADR-0011 (Vault cluster), ADR-0012 (CA bundle), ADR-0013 (LDAP-auth bindpass also reads from KV after this)

## Context

Phase 0.D.1–0.D.3 left the foundation env's role overlays consuming plaintext password defaults from `variables.tf`:

- `dsrm_password = "NexusDSRM!1"` — Install-ADDSForest DSRM
- `local_administrator_password = "NexusAdmin!1"` — local Administrator pre-promotion
- `nexusadmin_password = "NexusPackerBuild!1"` — post-promote AD reset + jumpbox Add-Computer
- `vault_userpass_password = "NexusVaultOps!1"` — Vault userpass user

Plus the runtime-generated AD service account creds (`svc-vault-ldap`, `svc-vault-smoke`) that lived only in `$HOME\.nexus\vault-ad-bind.json` on the build host.

Phase 0.D's exit gate explicitly requires `vault kv get nexus/foundation/<path>` to return populated records. This ADR captures the migration design.

Three migration shapes considered:

1. **Move all reads via SSH+`vault CLI`+ root-token in local-exec scripts.** Rejected — mixes patterns (Terraform's job is declarative state; SSH+CLI is imperative). Not what the task scope ("`vault_kv_secret_v2` data sources") asked for.
2. **Vault provider with userpass auth.** Rejected — userpass is for humans; encoding a password in the provider config is no better than the plaintext variable defaults.
3. **Vault provider with AppRole auth via cached role-id+secret-id JSON sidecar.** Selected. AppRole is the canonical TF/CI auth pattern; role-id is stable across applies, secret-id is regenerated per security-env apply.

## Decision

1. **Two new Vault objects in security env.**
   - **Policy `nexus-foundation-reader`**: read on `nexus/data/foundation/*` + `nexus/metadata/foundation/*`; write on `nexus/data/foundation/ad/*` only (where the bind/smoke overlays push generated creds at create time); token-self lookup/renew. NO sudo. NO writes outside `nexus/data/foundation/ad/*`.
   - **AppRole `nexus-foundation-reader`** with the policy above. `secret_id_ttl=0` + `secret_id_num_uses=0` (lab convention; production-grade rotation lands in 0.D.5 with Vault Agent + ~1 h TTLs). `bind_secret_id=true`.
2. **Sidecar JSON file.** Security env's `role-overlay-vault-foundation-approle.tf` writes role-id + secret-id to `$HOME\.nexus\vault-foundation-approle.json` (mode 0600 via icacls). Foundation env's `provider "vault"` block reads via `pathexpand("~/...") + try(file(...), "")`.
3. **Provider shape (`hashicorp/vault` ~> 4.0).** Generic `auth_login` block — NOT `auth_login_approle`, which doesn't exist as a typed block in v4.x:
   ```hcl
   provider "vault" {
     address      = "https://192.168.70.121:8200"
     ca_cert_file = pathexpand("~/.nexus/vault-ca-bundle.crt")
     auth_login {
       path = "auth/approle/login"
       parameters = {
         role_id   = local.approle_role_id
         secret_id = local.approle_secret_id
       }
     }
     skip_child_token = true
   }
   ```
4. **Six KV paths under `nexus/foundation/...`:**
   - `dc-nexus/dsrm` (consumed by Install-ADDSForest)
   - `dc-nexus/local-administrator` (consumed by pre-promotion local admin pwd set)
   - `identity/nexusadmin` (consumed by post-promote AD reset + jumpbox Add-Computer)
   - `vault/userpass-nexusadmin` (informational; security env's `vault_post_init` still seeds via variable for chicken-and-egg reasons — bootstrapping userpass needs the pwd before KV exists)
   - `ad/svc-vault-ldap` (written by foundation env's bind overlay or seeded from legacy JSON; consumed by security env's LDAP-auth)
   - `ad/svc-vault-smoke` (same shape as bind, consumed by smoke gate)
5. **Sticky one-time seed.** Security env's `role-overlay-vault-foundation-seed.tf` probes each path; writes only when empty. Operator-driven rotation (`vault kv put`) wins; seed never overwrites.
6. **Foundation env consumer pattern.** Three `vault_kv_secret_v2` data sources gated on `enable_vault_kv_creds`. A `local.foundation_creds` block centralizes the ternary: `enable_vault_kv_creds ? KV value : variable default`. Consumer overlays read `local.foundation_creds.dsrm` etc. instead of `var.dsrm_password`.
7. **Default flip.** `enable_vault_kv_creds` flipped `false → true` at 0.D.4 close-out per `feedback_terraform_partial_apply_destroys_resources.md` (defaults reflect steady state; opt-out is the explicit override). Greenfield bring-up uses `foundation apply -Vars enable_vault_kv_creds=false` for the first apply, then security apply seeds KV, then foundation apply (default true) consumes.
8. **KV writeback for AD bind/smoke.** Foundation env's `dc_vault_ad_bind` + `dc_vault_ad_smoke_account` overlays write the freshly-generated random pwd to `nexus/foundation/ad/<account>` after creating the AD account. Best-effort: WARN+skip when `vault-init.json` is absent (security env not yet applied). The seed step's JSON-migration path covers the bootstrap case where Vault came up after the AD accounts.

## Consequences

### Positive

- Plaintext defaults stay only as fallback for greenfield first-apply; steady-state reads from Vault.
- Capability scoping enforced: AppRole token can read ALL of `nexus/foundation/*` but write ONLY `nexus/foundation/ad/*` (verified via positive + 2 negative tests in smoke gate).
- AppRole secret-id rotates on every security env apply; role-id stable. Compromise of one secret-id is bounded by the cadence between security applies.
- LDAP-auth refactored to prefer KV bindpass (with JSON-file fallback for resilience) — eliminates the cross-env JSON file as the authoritative store.
- `vault-ad-bind.json` becomes vestigial after 0.D.4 close-out; can be deleted operationally without breaking either env.

### Negative / accepted

- Provider config can't be conditional. The provider block always initializes; with `enable_vault_kv_creds=false` no API call happens because all data sources have `count=0`. With dummy UUIDs from `try()` on missing JSON file, plan succeeds on greenfield even though the values are useless.
- `pathexpand()` resolves `~/` but NOT `$HOME`. Security env's PowerShell-side defaults use `$HOME/...` (via `ExecutionContext.InvokeCommand.ExpandString`); foundation env's HCL-side defaults use `~/...`. Same physical files, different syntax — documented in foundation `variables.tf` description.
- Vault userpass pwd creation is bootstrap chicken-and-egg: `vault_post_init` writes `auth/userpass/users/nexusadmin` BEFORE KV is populated. Resolved by keeping the variable default for that one cred; KV seed mirrors it but `vault_post_init` doesn't read from KV.

### Neutral

- AppRole TTLs are lab-scope (no expiry on secret-id). Production-grade rotation cadence lands in ADR-0015 (0.D.5 Transit + Vault Agent).
- `hashicorp/vault` provider v5 dropped the `auth_login_approle` typed block; v4 is the LTS-friendly anchor for our auth shape (saved as `feedback_terraform_vault_provider_approle.md`).

## Lessons captured (now memory canon)

- `feedback_terraform_vault_provider_approle.md` — hashicorp/vault v4 has NO `auth_login_approle` block; AppRole goes through generic `auth_login { path; parameters }`. Pin v4; v5 changes auth shape further.
- `feedback_terraform_partial_apply_destroys_resources.md` — `-Vars X=true` is the FULL override set, not a patch on prior apply. Same rule that drove `enable_vault_dhcp_reservations` and `enable_vault_ad_integration` defaults to true now drives `enable_vault_kv_creds`.

## Operational rules

- Smoke: `pwsh -File scripts\security.ps1 smoke -Phase 0.D.4`. Verifies AppRole creds JSON shape, policy paths + capabilities, AppRole login → token-with-policy, all 6 KV paths populated, 2 negative scope-guard tests.
- Greenfield bring-up sequence: `foundation apply -Vars enable_vault_kv_creds=false` → `security apply` → `foundation apply` (default true).
- Cred rotation: `vault kv put nexus/foundation/<path> password=...`. Re-apply consumer overlay to pick up the new value (`terraform apply -target=null_resource.dc_nexus_promote` etc.).
- AppRole secret-id force-rotate: `terraform apply -target=null_resource.vault_foundation_approle` in security env. The new secret-id is written to the JSON; foundation env reads it on next apply.
