# ADR-0012 — Vault PKI hierarchy (root + intermediate) for lab-internal TLS

- **Status**: Accepted
- **Date**: 2026-05-01 (Phase 0.D.2 close-out)
- **Deciders**: Greg Zapantis
- **Supersedes**: per-clone self-signed bootstrap TLS from ADR-0011
- **Superseded by**: —
- **Related**: ADR-0011 (Vault cluster), ADR-0013 (LDAPS uses pki_int leaves), ADR-0014 (foundation env vault provider's `ca_cert_file` reads the distributed root CA bundle)

## Context

Phase 0.D.1 brought up a 3-node Vault cluster with per-clone self-signed listener TLS. Operators set `VAULT_SKIP_VERIFY=true` for every CLI call, every smoke probe, every Terraform local-exec. Cross-node Raft join needed each follower to install the leader's cert in `/usr/local/share/ca-certificates/` then run `update-ca-certificates`. This works for bring-up but doesn't scale: any Vault node restart, replacement, or .NET TLS handshake from build host needs the same cert-shuffle. We need a single trust anchor that covers every Vault listener AND that downstream services (LDAPS to dc-nexus, future SQL Server endpoints, microservice mTLS) can chain through.

Three options:

1. **Stay on per-clone self-signed.** Rejected — `VAULT_SKIP_VERIFY=true` everywhere is a bad portfolio look and breaks the lab's narrative on TLS hygiene.
2. **External CA (Let's Encrypt / commercial).** Rejected — lab uses non-routable VMnet11 hosts (`*.nexus.lab`); ACME challenges don't reach. Manual cert ordering breaks the "all reproducible from terraform apply" rule.
3. **Vault PKI: root + intermediate hierarchy with leaf rotation.** Selected. Vault's `pki/` and `pki_int/` engines were already running on the cluster; turning on the hierarchy adds 7 small overlays and earns operator-grade TLS.

## Decision

1. **Two-tier hierarchy.**
   - `pki/` mount → root CA (`CN=NexusPlatform Root CA`, TTL 87600 h = 10 y). Issues exactly one cert: the `pki_int/` intermediate. Otherwise unused — long-lived, root-of-trust only.
   - `pki_int/` mount → intermediate CA (`CN=NexusPlatform Intermediate CA`, TTL 43800 h = 5 y, signed by root). All leaf certs chain through this.
2. **PKI role `vault-server`** at `pki_int/roles/vault-server`. `allow_ip_sans=true`, `allow_localhost=true`, `allowed_domains = nexus.lab + lab + localhost`, `allow_subdomains=true`, `key_type=rsa`, `key_bits=2048`, `ttl=8760h` (1 y leaf TTL). Used to issue:
   - Vault listener certs (per-node leaf SAN: `vault-N.nexus.lab` + `vault-N` + `localhost` + 192.168.70.N + 192.168.10.N + 127.0.0.1).
   - dc-nexus LDAPS cert (Phase 0.D.3, see ADR-0013) — same role, different SAN (`dc-nexus.nexus.lab` + 192.168.70.240 + ...).
3. **Leaf rotation idempotent.** Per-node listener cert reissue checks (a) issuer = `NexusPlatform Intermediate CA`, (b) days-remaining > 30. Skips if both true; otherwise issues fresh + atomic-swap into `/etc/vault.d/tls/` + `systemctl reload vault.service` (SIGHUP, zero-downtime).
4. **Root CA distribution.**
   - Build host: `$HOME\.nexus\vault-ca-bundle.crt` (mode 0600 via icacls).
   - Each Vault node: `/usr/local/share/ca-certificates/nexus-vault-pki-root.crt` + `update-ca-certificates`.
   - Operator drops `VAULT_SKIP_VERIFY` and sets `VAULT_CACERT=$HOME\.nexus\vault-ca-bundle.crt`. Hash-compare idempotent on every apply.
5. **Legacy 0.D.1 trust shuffle retired.** The per-clone `vault-leader.crt` residue in followers' `/usr/local/share/ca-certificates/` is removed once the shared root CA replaces it (`role-overlay-vault-pki-cleanup-hack.tf`).
6. **TTL strategy.** Root 10 y / intermediate 5 y / leaf 1 y today. Phase 0.D.5 drops leaf TTL to 90 d once Vault Agent automates renewal cadence.

## Consequences

### Positive

- Single trust anchor: `vault-ca-bundle.crt` covers all Vault listeners + LDAPS to dc-nexus + future TLS endpoints.
- `VAULT_SKIP_VERIFY` removed from operator workflow.
- Future services (microservice mTLS, SQL Server endpoint TLS, MinIO) chain through `pki_int/` without a second CA hierarchy.
- Vault PKI is the only CA in the lab. ADR-0144's `Autounattend.xml` cert work + ADR-0013's LDAPS cert + future MinIO TLS all share the trust anchor.

### Negative / accepted

- 1 y leaf TTL means manual re-apply within 11 months for cert renewal. Acceptable for 0.D.4 since the smoke gate's `>300 days remaining` probe catches drift. ADR-0014's `vault_kv_secret_v2` data sources reuse the same bundle.
- Root CA's private key sits in `pki/`. Compromising the root rebuilds the entire trust chain. Mitigated by: root is sealed inside Vault (which is sealed when not running); root signs nothing except the intermediate (rotation cadence: never, by design).

## Lessons captured (now memory canon)

- `feedback_smoke_gate_probe_robustness.md` rule #2: .NET `SslStream` custom-root TLS validation requires intermediates relayed from `$chain.ChainElements` into `ExtraStore` before `Build()` — discovered while writing the build-host TLS validation probe.
- `feedback_diagnose_before_rewriting.md` — when a TLS handshake fails, dump cert chain (`X509Chain.Build`) + Schannel events / OpenSSL errors before rewriting code. Saved 2 wasted iterations during 0.D.3 LDAPS rollout.

## Operational rules

- Smoke: `pwsh -File scripts\security.ps1 smoke -Phase 0.D.2`. Verifies CA hierarchy, role definition, per-node cert SAN + days-remaining, build-host bundle hash match, legacy trust cleanup.
- Manual cert renewal: `terraform apply -target=null_resource.vault_pki_rotate_listener` (per-node leaf reissue alone, no other side effects).
- Adding a new role-overlay-issued cert: define a new PKI role under `pki_int/roles/<name>`, then issue via `vault write pki_int/issue/<name> common_name=... ttl=... ip_sans=... alt_names=...`.
