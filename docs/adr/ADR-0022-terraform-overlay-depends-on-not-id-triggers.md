# ADR-0022 — Phase 0.H.3-0.H.4: Terraform overlay ordering via `depends_on`, never upstream resource `.id` triggers

- **Status**: Accepted
- **Date**: 2026-05-15
- **Deciders**: Greg Zapantis
- **Related**: ADR-0018 / ADR-0019 (Phase 0.E structural fixes), `nexus-infra-kafka` Phase 0.H

## Context

The `nexus-infra-*` repos drive configuration onto running VMs with a recurring Terraform shape: a `null_resource` "overlay" whose `local-exec` provisioner SSHes to the target nodes, and whose `triggers` map decides when the provisioner re-runs. Overlays must run **in order** (cert render before service config before service start), and the natural-looking way to express "run B after A" is to put A's id into B's triggers:

```hcl
# ANTI-PATTERN
resource "null_resource" "kafka_broker_config" {
  triggers = {
    nftables_id = null_resource.kafka_nftables_backplane.id   # <-- wrong
  }
}
```

This **looks** like an ordering hint. It is actually a **re-run subscription**: a `null_resource`'s `.id` changes every time it is replaced, so `kafka_broker_config` now re-runs on every single re-run of `kafka_nftables_backplane` — even when nothing `kafka_broker_config` cares about has changed.

In Phase 0.H this cascaded into real damage:

- Bumping the nftables overlay's version (to add the 0.H.3/0.H.4/0.H.5 ecosystem IPs) changed `kafka_nftables_backplane.id`.
- `kafka_broker_config`'s `nftables_id` trigger fired → it re-ran and **re-rendered PLAINTEXT `server.properties` over the 0.H.2 mTLS config**.
- `kafka_kraft_format` and `kafka_broker_start_verify` were chained on `kafka_broker_config.id` the same way → they re-ran too.
- `kafka_broker_start_verify`'s PLAINTEXT quorum probe then hit the still-mTLS brokers and **OOM'd** — a PLAINTEXT Kafka client reading a TLS handshake interprets the first bytes as a message length and tries to allocate gigabytes of heap.

The same shape had already been hit (and patched piecemeal) earlier in the phase: `va_ids` on `kafka_tls` / `kafka_ecosystem_tls` (re-ran the broker mTLS flip on every security-env apply, because secret-id rotation churns Vault Agent ids), and `tls_id` / `sr_id` on the Schema Registry / REST overlays.

## Decision

**An overlay's `triggers` map keys ONLY on that overlay's own inputs. Ordering between overlays is expressed exclusively via `depends_on`.**

```hcl
# CANON
resource "null_resource" "kafka_broker_config" {
  triggers = {
    brokers   = jsonencode(local.kafka_enabled_brokers)   # own input: the node set
    overlay_v = "2"                                       # own input: config version
  }
  depends_on = [null_resource.kafka_nftables_backplane]     # ordering only -- no re-run coupling
}
```

Rules:

1. **`triggers` = "what would make THIS overlay's rendered output different."** The node set, the rendered config's version string, a `filesha256()` of a source file. Never another resource's `.id`.
2. **`depends_on` = "what must have run before this, this apply."** It sequences the graph without subscribing to re-runs.
3. **Overlays must be individually re-runnable and idempotent.** Because `depends_on` does not force a re-run, each overlay carries its own skip-guards (e.g. `kafka_broker_config` skips any broker that already has `/etc/nexus-kafka/client-ssl.properties` — the reliable mTLS-flip marker) and its verification is wire-mode-aware (`kafka_broker_start_verify` detects the marker and probes with `--command-config` when the broker is mTLS).
4. **Version-string triggers (`overlay_v = "N"`) are the deliberate re-run lever.** Bumping the string is how an operator says "this overlay's logic changed, re-run it" — an explicit, reviewable, in-the-diff action, not an invisible cascade.

## Consequences

### Positive

- **Re-applies stop churning.** A security-env apply (which rotates every Vault Agent secret-id) no longer re-runs the broker mTLS flip; an nftables version bump no longer re-renders `server.properties`. Each overlay re-runs only when its own inputs change.
- **Blast radius is legible.** `terraform plan` shows exactly which overlays will re-run and why — the `triggers` diff names the changed input. There is no "why is this 6 resources downstream being replaced" archaeology.
- **The fix is uniform.** Every 0.H overlay follows the rule; the pattern is greppable (`grep -n '\.id$' role-overlay-*.tf` should return nothing in a `triggers` block).

### Negative

- **`depends_on` does not re-run downstream on upstream change — by design — so idempotence is mandatory, not optional.** An overlay that is not safely re-runnable, or whose skip-guard is wrong, will silently no-op when it should have re-run. The discipline shifts from "trust the cascade" to "every overlay proves it converges." This is more up-front work per overlay.
- **Cross-overlay state changes need an explicit version bump.** If overlay A's output changes the environment in a way overlay B depends on, the operator must bump B's `overlay_v` by hand — there is no automatic propagation. That is the intended trade (explicit > invisible), but it is a step that can be forgotten.

### Neutral

- **This is a Terraform-pattern ADR, not an infrastructure decision.** It is recorded here because the anti-pattern caused real, debugging-expensive damage across three 0.H sub-phases, and because every `nexus-infra-*` repo uses the same overlay shape — the rule applies fleet-wide, not just to the Kafka tier.
- **Consistent with HashiCorp's own guidance.** `depends_on` is the documented mechanism for ordering; `triggers` is documented as "values that, when changed, force recreation." Keying `triggers` on a peer `.id` abuses the second mechanism to fake the first.

## Verification

`grep` discipline at review time: no `*.id` appears in any `triggers` block in `nexus-infra-kafka/terraform/envs/kafka/role-overlay-*.tf`. Behaviourally: a `nexus-infra-vmware` `security.ps1 apply` followed by `nexus-infra-kafka` `kafka.ps1 plan` reports **no changes** to the broker overlays (the secret-id rotation no longer cascades). The 0.H.4 verification doc (`nexus-infra-kafka/docs/verification/0.H.4-connect-ksqldb.md`, "Step 2 — the bug chain") records the full incident and the fix.
