# ADR-0019 — Phase 0.E.4e: TLS full-chain on the wire + `inet filter forward` accept rules

- **Status**: Accepted
- **Date**: 2026-05-08
- **Deciders**: Greg Zapantis
- **Related**: ADR-0012 (Vault PKI hierarchy), ADR-0018 (nftables flush + Docker iptables-nft conflict)

## Context

Two latent bugs from Phase 0.E.4 surfaced when `grezap/nexus-cli` v0.1.0 ran `cluster-status` from the build host (10.0.70.101) against the live cluster for the first time:

### Bug 1: leaf-only cert on the wire

The Vault Agent templates rendered by `role-overlay-{consul,nomad,portainer}-tls.tf` (Phase 0.E.2.2 / 0.E.3.1 / 0.E.4b) emit a bundle file containing three PEM blocks via `pkiCert`:

```
{{ .Cert }}    -- leaf cert
{{ .Key }}     -- private key
{{ .CA }}      -- issuing CA (= NexusPlatform Intermediate CA, per ADR-0012)
```

The post-render split script writes the **first** CERTIFICATE block to `server.crt` and the **second** to `ca.pem`. Daemons (Consul, Nomad, Portainer) point their `cert_file` config at `server.crt` — which contains **only the leaf**. On TLS handshake, the server presents the leaf and nothing else.

This works for any client that has the intermediate already in its trust store. It silently fails for clients that have only the root, because the chain `leaf → intermediate (??) → root` cannot be built without the intermediate available somewhere.

The build host's canonical CA bundle (`$HOME\.nexus\vault-ca-bundle.crt`, distributed by Phase 0.D.2) contains only the **NexusPlatform Root CA**. Off-cluster TLS validation against this bundle hits `X509ChainStatus.PartialChain`. Diagnosed in `nexus-cli` v0.1.0/v0.1.1 runs against Consul:8501.

The 0.E.4d smoke gate (`smoke-0.E.4.ps1`) didn't catch this because it probed Portainer:9443 from inside `swarm-manager-1` via `curl --cacert /etc/portainer/tls/ca.pem` — using the manager's own intermediate-CA file, not the build host's root-only bundle.

### Bug 2: empty `inet filter forward` chain

The swarm-node Packer template (`packer/swarm-node/files/nftables.conf`) declared:

```nftables
chain forward {
    type filter hook forward priority 0; policy drop;
}
```

…with **zero rules** inside. Linux nftables runs **all FORWARD chains for every forwarded packet** — both Docker's `ip filter FORWARD` (which Docker autopopulates to `policy=accept` + `DOCKER-FORWARD`/`DOCKER-USER`) AND the operator's `inet filter forward`. Either chain dropping is sufficient to drop the packet.

For services with host-listener-only sockets (Consul:8501, Nomad:4646), traffic traverses the INPUT hook and never sees FORWARD — so they worked. For services routed via Docker Swarm's ingress mesh (Portainer:9443, where the host listener DNATs to a `docker_gwbridge` IP at `172.18.0.0/16`), the post-DNAT packet is **forwarded** from `nic0` to `docker_gwbridge`. That hits the FORWARD hook, the inet chain has no accept rule, the policy drops it.

Symptom: `:9443` reachable from manager-localhost (no FORWARD traversal — see ADR-0018), unreachable from the build host's bridged adapter. Same symptom shape as ADR-0018, different root cause: ADR-0018 was Docker's `ip filter FORWARD` getting wiped by `nft -f`; this is the operator's `inet filter forward` having no rules at all.

The 0.E.1 smoke gate (`smoke-0.E.1.ps1`) didn't catch this because it probed only INPUT-chain reachability (Consul/Nomad/SSH).

## Decision

### Decision 1: server.crt carries leaf + intermediate; ca.pem stays as intermediate-only

Modify the three split scripts to:

```bash
# After the awk-split identifies SERVER_CRT (leaf), CA_PEM (intermediate), SERVER_KEY:
cat "$SERVER_CRT" "$CA_PEM" > "$TMP/server-fullchain.crt"
install -m 0644 "$TMP/server-fullchain.crt" "$DEST/server.crt"
install -m 0640 "$SERVER_KEY"               "$DEST/server.key"
install -m 0644 "$CA_PEM"                   "$DEST/ca.pem"   # unchanged
```

**Why server.crt holds two PEMs:** standard practice for TLS servers — the server SHOULD present its full chain except the root, so clients with only the root in their trust store can validate.

**Why ca.pem stays as the intermediate alone:** internal mTLS verification (Consul agent ↔ Consul agent, Nomad agent ↔ Nomad agent) anchors trust at `ca.pem`. Both Go's `crypto/tls` and Consul/Nomad's TLS code accept any cert in the trust pool as a valid anchor — they don't require self-signed roots. Keeping ca.pem as the intermediate avoids requiring Vault Agent's `.CAChain` template helper (variant cross-version behaviour) and keeps the per-overlay diff minimal.

**Why not put the root in ca.pem instead?** That would require Vault Agent to emit the root, which `pkiCert` doesn't do directly (it emits leaf + key + issuing-CA). We could fetch via `pki/cert/ca` separately and concatenate, but that's a larger change for no functional benefit at the daemon layer — internal mTLS already works.

Version triggers bump:
- `consul_tls_v` → `7`
- `nomad_tls_v`  → `5`
- `portainer_tls_v` → `2`

### Decision 2: `inet filter forward` allows traffic on `docker_gwbridge` (and `docker0`)

Add to the swarm-node Packer template's forward chain:

```nftables
chain forward {
    type filter hook forward priority 0; policy drop;

    ct state { established, related } accept
    iifname "docker_gwbridge" accept comment "Docker swarm ingress mesh (in)"
    oifname "docker_gwbridge" accept comment "Docker swarm ingress mesh (out)"
    iifname "docker0"         accept comment "Docker default bridge (in)"
    oifname "docker0"         accept comment "Docker default bridge (out)"
}
```

For already-deployed clones (the current lab), a new overlay `role-overlay-nftables-forward.tf` SSHes to each node, idempotently patches `/etc/nftables.conf` in place, runs `nft -f` to atomically reload, then `systemctl restart docker` to rebuild Docker's iptables-nft rules per ADR-0018.

**Why scope to `docker_gwbridge` and `docker0` (and not blanket-accept FORWARD):** preserves the operator's deny-by-default posture. Only Docker-managed bridge traffic gets the accept; everything else still hits `policy drop`. Future swarm services that publish ports via the routing mesh land their containers on `docker_gwbridge` and inherit the rule; no per-service overlay needed.

### Decision 3: smoke gate extension

`scripts/smoke-0.E.4e.ps1` is a chained child of `smoke-0.E.4.ps1` and adds:

- **Block A**: assert `server.crt` on each node has 2 PEM blocks (file-on-disk check) AND the TLS handshake at the daemon's listener port returns ≥ 2 wire-chain elements (network check via .NET `SslStream`).
- **Block B**: assert `inet filter forward` chain has the docker_gwbridge / docker0 accept rules and the `ct state established/related accept` rule (running ruleset check via `nft list chain`).
- **Block C**: assert HTTPS GET against each manager's services returns 200 (or 403 for Nomad anon-deny) **from the build host** with the **stock root-only CA bundle**. This is the gate that 0.E.4 lacked.
- **Block D** (optional, `-RunCli`): drive `nexus-cli cluster-status` end-to-end with the stock bundle and assert overall=green.

Block C's "stock root-only CA bundle" assertion explicitly checks that the bundle has exactly 1 cert; if the operator augmented it as a workaround, the gate warns and the human-reviewable output makes the spurious-pass obvious.

## Consequences

### Positive

- **Off-cluster clients work without manual operator state.** No bundle augmentation. No `--insecure` flag. The build host's stock `vault-ca-bundle.crt` validates every TLS handshake the cluster offers.
- **Future services inherit the fix.** Any new Docker Swarm service that publishes a port via the ingress mesh gets routing-mesh reachability for free; any new Vault-Agent-rendered TLS daemon gets full-chain serving for free (as long as it follows the same template + split-script pattern).
- **Smoke gate now exercises the wire.** Wire-chain depth + off-cluster reachability are gated, not hoped-for.
- **Phase boundary is sealed.** A clean redeploy from `terraform destroy` + `apply` produces a cluster that passes 0.E.4e without operator intervention.

### Negative

- **Apply window churn.** Bumping the three TLS version triggers cascades downstream replacements (consul_acl, nomad_acl, nomad_vault_integration, portainer_admin_render, portainer_stack) via the existing trigger chain. The 0.E.4e apply uses `-target` flags to limit blast radius to just the TLS overlays + `nftables_forward`, leaving downstream "soft-drift" (terraform plan reports drifted triggers but doesn't apply them). A future force-redeploy will re-run the downstream chain in one go.
- **Manual recovery path on swarm fragility.** During 0.E.4e iteration, a too-aggressive sequential docker restart cycle (5s sleeps between managers) cascade-killed Portainer tasks faster than swarm could reschedule. Mitigation: longer settle windows (≥30s between manager restarts), and an explicit precondition in the apply-pattern handbook that swarm be 6/6 healthy + Portainer 1/1 stable before kicking off.
- **`docker_gwbridge` accept is permissive.** Anything that lands on docker_gwbridge gets forwarded freely. Acceptable in a lab; production should constrain via container labels + dedicated overlay networks per service tier. Not in scope for 0.E.

### Neutral

- **`.CAChain` Vault Agent helper unused.** A future enhancement could render `cert_chain.pem` via `.CAChain` for daemons that prefer a separate chain file. Not adopted now: the catenation approach is uniform across Consul/Nomad/Portainer and matches HashiCorp's own documentation examples.
- **No change to internal mTLS behaviour.** ca.pem still anchors at the intermediate. Cluster-internal handshakes between agents work exactly as before.

## Verification

The 0.E.4e smoke gate is the canonical verification:

```pwsh
pwsh -File scripts\smoke-0.E.4e.ps1 -RunCli `
     -NexusCliPath "F:\..\nexus-cli\artifacts\win-x64\nexus.exe"
```

Expected: ALL GREEN. The Block C "build host has stock root-only bundle" check explicitly asserts the bundle hasn't been augmented, so a passing run with `bundleCount = 1` is the rebuild-from-scratch-friendly state.

Cold rebuild test (closes the loop):

```pwsh
pwsh -File scripts\swarm.ps1 destroy
pwsh -File scripts\swarm.ps1 apply
pwsh -File scripts\smoke-0.E.4e.ps1
# All ALL GREEN, no operator intervention between destroy and smoke.
```
