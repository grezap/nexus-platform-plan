# ADR-0021 — Phase 0.H.2-0.H.5: Kafka-tier mTLS — Vault PKI PEM keystores, PKCS#1→PKCS#8, and the Confluent PEM/PKCS#12 listener split

- **Status**: Accepted
- **Date**: 2026-05-15
- **Deciders**: Greg Zapantis
- **Related**: ADR-0012 (Vault PKI hierarchy), ADR-0015 (Vault Agent on member servers), ADR-0019 (TLS full-chain on the wire)

## Context

Every service in the lab gets a TLS identity from the Vault PKI hierarchy (ADR-0012), rendered locally by a per-node Vault Agent (ADR-0015 pattern). The Kafka tier has to apply that pattern across three different kinds of TLS surface:

1. **Broker ↔ broker / client ↔ broker (the data plane).** Kafka 3.8 supports `ssl.keystore.type=PEM` natively — a concatenated `key + leaf + chain` PEM file, no JKS, no `keytool`, no keystore password. This is the clean path and the obvious default.
2. **The JVM key-format gap.** Vault PKI issues RSA private keys in **PKCS#1** (`-----BEGIN RSA PRIVATE KEY-----`). Java's PEM keystore parser only accepts **PKCS#8** (`-----BEGIN PRIVATE KEY-----`). A broker handed a PKCS#1 key crash-loops at startup with `java.security.InvalidKeyException: algid parse error, not a sequence`. (Go's `crypto/tls` — Consul/Nomad — reads both, so this gap never surfaced before Phase 0.H.)
3. **The Confluent REST-listener split.** The ecosystem services each serve their own HTTPS listener, and they do **not** agree on keystore formats:
   - **Schema Registry + REST Proxy** use Confluent `rest-utils`, which has a PEM→keystore helper — they accept `ssl.keystore.type=PEM`.
   - **Kafka Connect's `RestServer` (Apache Kafka's own) + ksqlDB's `KsqlRestConfig`** pass the keystore type straight through to Jetty / validate it against `{JKS, PKCS12, BCFKS}` — they **reject `PEM`** (`NoSuchAlgorithmException: PEM KeyStore not available` / `Invalid value PEM ...`).

The decision has to produce one coherent per-node cert-rendering pipeline that satisfies all three.

## Decision

**Per-node Vault Agent issues one leaf; a post-render split script produces both a PEM pair and a PKCS#12 pair; each consumer picks the format it accepts.**

### The cert pipeline (every kafka-tier node)

1. The node's `nexus-vault-agent.service` authenticates with a narrow per-host AppRole and renders a bundle from `pki_int/issue/kafka-broker` (the role carries **server + client EKU** — every node is both a TLS server and a Kafka client — and a **90-day leaf TTL**, matching the ADR-0015 cadence).
2. A post-render split script (`kafka-tls-split.sh`):
   - **converts the key PKCS#1 → PKCS#8** via `openssl pkcs8 -topk8 -nocrypt` (idempotent);
   - writes `keystore.pem` (PKCS#8 key + leaf + intermediate) + `truststore.pem` (intermediate);
   - **also** writes `keystore.p12` (via `openssl pkcs12 -export`) + `truststore.p12` (via **`keytool -importcert`** — the `openssl pkcs12 -export -nokeys` form produces a cert bag Java loads as empty, `trustAnchors must be non-empty`).

### Who uses which format

| Surface | Keystore format | Why |
|---|---|---|
| Brokers (client + controller listeners), all Kafka **clients**, the CLI tools | **PEM** | Kafka 3.8 native; no password, no `keytool` |
| Schema Registry + REST Proxy HTTPS listeners | **PEM** | Confluent `rest-utils` accepts it |
| Kafka Connect + ksqlDB HTTPS listeners | **PKCS#12** | their REST servers reject PEM |
| MirrorMaker 2 (producer/consumer/admin) | **PEM** | all Kafka clients; `connect-mirror-maker` runs no REST server in this topology |

`ssl.client.auth=required` on the broker listeners → every Kafka client presents a cert, so the per-node leaf doubles as the node's client identity. There is one fixed lab-convenience keystore password for the `.p12` files (`var.kafka_keystore_password`); production would source it from Vault KV.

## Consequences

### Positive

- **One leaf, one Vault Agent, one render path per node** — the format fan-out is a post-render concern, not a per-service Vault Agent template.
- **The PEM path stays password-free** for everything that can take it (brokers, clients, SR, REST Proxy) — no keystore-password secret to manage on the majority of surfaces.
- **The PKCS#1→PKCS#8 conversion is sealed once**, in the shared split script — every JVM consumer in the tier (now and in later sub-phases) inherits the fix.

### Negative

- **Dual artefacts on the ecosystem nodes.** Connect/ksqlDB nodes carry both a PEM pair (their Kafka-client identity) and a PKCS#12 pair (their REST listener). The split script must keep them in sync; a partial render is a latent failure.
- **`keytool` is on the critical path** for `truststore.p12`. It ships with the Temurin JDK the template already installs, so there is no new dependency — but the truststore build can't be pure-`openssl`.
- **The fixed keystore password is a lab convenience.** It lives in a plaintext Terraform variable default; the `.p12` + config files are `0640 root:kafka`. Logged as a deferred item (Vault-KV-sourced password) — not a Phase 0.H deliverable.

### Neutral

- **No change to the Vault PKI hierarchy.** `kafka-broker` is one more role under `pki_int/`, exactly the shape of `consul-server` / `nomad-server` / `portainer-server`. Its `allowed_domains` lists all 15 tier hostnames.
- **The mTLS flip is a wire-format change.** Brokers come up PLAINTEXT in 0.H.1 and flip to mTLS in 0.H.2 via a per-cluster **parallel big-bang restart** — a TLS wire-format flip cannot be a sequential rolling restart (the consul-tls / nomad-tls lesson; KRaft's controller quorum is a Raft group and a sequential flip splits it).

## Verification

- `smoke-0.H.2.ps1` (92 checks) — every broker listener requires a client cert; KRaft quorum + RF=3 round-trip verified over mTLS.
- `smoke-0.H.3.ps1` (37) / `smoke-0.H.4.ps1` (48) / `smoke-0.H.5.ps1` (38) — each ecosystem node holds a leaf with the expected CN, talks to the brokers over mTLS, and serves its HTTPS listener in the format above.
- Verification docs: `nexus-infra-kafka/docs/verification/0.H.{2,3,4,5}-*.md`.
