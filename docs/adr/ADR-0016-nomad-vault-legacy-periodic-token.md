# ADR-0016 — Phase 0.E.3.3b: Nomad-Vault integration via legacy periodic-token role (vs. Workload Identity)

- **Status**: Accepted
- **Date**: 2026-05-06
- **Deciders**: Greg Zapantis
- **Related**: ADR-0011 (Vault cluster), ADR-0012 (PKI hierarchy), ADR-0014 (foundation creds via AppRole + KV)

## Context

Phase 0.E.3.3b lights up Nomad's `vault {}` agent stanza so jobs running on the cluster can request Vault secrets at runtime via standard `template { vault { ... } }` blocks in their job spec. Nomad supports two integration models:

1. **Legacy periodic-token (Nomad ≤1.6 default; still supported in 1.7+)** — Each Nomad server holds a long-lived token tied to a Vault token role. When a job's template requests secrets, Nomad mints a child token via `vault token create -role=<role>` (inheriting the role's policy by default), passes it to the job's allocation, and revokes it when the alloc terminates.
2. **Workload Identity / JWT (Nomad 1.7+ default)** — Each allocation receives a Nomad-signed JWT identifying the job. Vault's `auth/jwt` backend validates the JWT and issues a short-lived token bound to a role mapped per-job. No long-lived tokens, no Nomad-side mint-then-pass flow.

Workload Identity is the modern recommended pattern (better blast-radius isolation; no single token shared by Nomad servers; no orphan tokens on Nomad failure). But it requires:
- Vault `auth/jwt` backend mounted at a known path (e.g., `auth/jwt-nomad/`)
- One Vault role per Nomad job (or per `default_identity`)
- Nomad servers pre-configured with the `default_identity` block + JWT signing key
- Per-job `identity` blocks mapping JWT claims to Vault roles

The Phase 0.E.3.3b deliverable is **infrastructure scaffolding for future workloads**, not a specific job's secrets access. We have no Nomad jobs yet (Phase 0.E.4 deploys Portainer via *Docker Swarm*, not Nomad). Real Nomad jobs land starting in Phase 0.F+.

## Decision

**Use the legacy periodic-token model** for the 0.E.3.3b infrastructure scaffolding:

- Vault policy `nomad-jobs` (lab-permissive: `read` on `secret/data/*` + `secret/metadata/*` + token self-management). Tighten per-job at workload onboarding.
- Vault token role `nomad-cluster`:
  - `allowed_policies = ["nomad-jobs"]`
  - `period = 72h` (auto-renew indefinitely so long as renewal lands within each 72h window)
  - `orphan = false` (revoking the parent cascades to children)
  - `renewable = true`
- 3 Nomad managers each receive a periodic token at apply time, persisted to `/etc/nomad.d/60-vault-token.txt` (mode 0640 root:nomad). Nomad's `vault {}` stanza:

```hcl
vault {
  enabled          = true
  address          = "https://192.168.70.121:8200"
  ca_file          = "/etc/vault-agent/ca-bundle.crt"
  create_from_role = "nomad-cluster"
  token_file       = "/etc/nomad.d/60-vault-token.txt"
  task_token_ttl   = "1h"
}
```

- One-shot terraform-side mint (idempotent skip-if-populated). Nomad takes over renewal post-startup. We never overwrite a populated token file — that would orphan Nomad's renewal accounting.
- Manager-only deployment (3 nodes). Workers don't need their own vault stanza — they inherit child tokens from the server's bootstrap token at job-allocation time.

### Why legacy now, Workload Identity later

1. **No jobs to identity-map yet.** Workload Identity needs per-job role mappings (or a default-identity policy). Until we have actual Nomad jobs in 0.F+, those roles would be theoretical. The legacy model lets us provision the integration WITHOUT predicting the workload shape.
2. **Migration path is clean.** When 0.F+ lands real jobs, we can:
   - Mount `auth/jwt-nomad/` and add `default_identity` to Nomad's vault stanza alongside the existing token-based config.
   - Migrate jobs from `template { vault { policies = [...] } }` (legacy) to `template { vault { } } + identity { vault { ... } }` (Workload Identity) one at a time.
   - Once all jobs migrate, drop the periodic token + `create_from_role` config.
3. **Smaller blast radius for the lab.** A leaked manager-side periodic token compromises the `nomad-jobs` policy (read-only on `secret/data/*`). In a lab where the policy is broad-by-design, this is acceptable. Production would never be this permissive regardless of integration model.

## Consequences

**Positive:**
- Nomad-Vault integration provisioned in a single 0.E.3.3b apply; no per-job pre-work.
- Operator can verify via `curl /v1/agent/self` (config.Vaults[].Enabled=true + Addr=https://...:8200).
- Token renewal is fully automatic; no operator intervention required.

**Negative / accepted:**
- Long-lived periodic token on managers. Worth 72h period (auto-renew on each manager-side write). Compromise = need to revoke + re-mint.
- Legacy model deprecated upstream. Migration to Workload Identity will require coordinated work in Phase 0.F+ when first real Nomad job lands.
- The `nomad-jobs` policy is intentionally permissive at the lab tier. Production-shape policy (least-privilege per-secret-path) needs per-workload analysis.

**Migration trigger:** When the first 0.F+ Nomad job needs secrets access, evaluate whether to add `auth/jwt-nomad/` + per-job identity then, or to keep using `nomad-jobs` for that job's lifetime. The decision can be per-job — Workload Identity coexists with periodic-token in the same Nomad cluster.

## Operational artefacts

- Code: `nexus-infra-vmware/terraform/envs/security/role-overlay-vault-nomad-jobs-policy.tf`, `role-overlay-vault-agent-swarm-policies.tf` v3→v4 (manager `auth/token/create/nomad-cluster` + `auth/token/roles/nomad-cluster` capabilities)
- Code: `nexus-infra-swarm-nomad/terraform/envs/swarm-nomad/role-overlay-nomad-vault.tf`
- Smoke: `scripts/smoke-0.E.3.3.ps1` — verifies `pki_int/...` policy + `nomad-cluster` token role exists with period 72h + manager `60-vault.hcl` + `60-vault-token.txt` rendered + `/v1/agent/self` reports `Vaults[].Enabled=true`
- Lesson memorial: `feedback_nomad_acl_no_agent_token_in_config.md` (related; agent identity is mTLS-based, not config-token-based)
