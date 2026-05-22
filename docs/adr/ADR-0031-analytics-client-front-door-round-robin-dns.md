# ADR-0031 — Phase 0.G.5/0.G.6: Analytics client front door — round-robin DNS, no VRRP VIP

- **Status**: Accepted
- **Date**: 2026-05-22
- **Deciders**: Greg Zapantis
- **Related**: **ADR-0025 (HA promise covers the LB tier — this ADR resolves the two open questions ADR-0025 §Context left for the analytics tier)**, ADR-0029 (ClickHouse topology), ADR-0030 (StarRocks topology), 0.E.4c Portainer multi-A round-robin DNS precedent (`feedback` on dnsmasq `host-record`)

## Context

ADR-0025 made it a hard rule that **whenever a fixed-endpoint LB sits between clients and a multi-node cluster, the LB tier itself must be HA** (2-node + VRRP VIP), and explicitly left two open questions to resolve before the analytics phases:

> - **(Planned) StarRocks FE coordinators → ??? front door** ⇐ open question — investigate before this phase lands
> - **(Planned) ClickHouse Distributed → ??? front door** ⇐ open question — investigate before this phase lands

This ADR is that investigation's conclusion. The ADR-0025 decision tree turns on one question: **does a *fixed-endpoint* LB sit between clients and the cluster?** ADR-0025 itself enumerates the cases where the answer is "no, and that's fine":

> - Kafka clusters → bootstrap servers list (multi-host, client-side LB, OK)
> - MongoDB RS → replica-set URI lists all members (client-side LB, OK)
> - Redis Cluster → CRC16 slot map, client knows all nodes (OK)

The analytics engines fall squarely into that "client-side multi-endpoint / no single mandatory endpoint" category:

- **ClickHouse**: a client connects to **any** data node and reads/writes the `Distributed` table; that node fans the query out to all shards. There is no single "primary" node a client *must* reach — all 6 shard-replica nodes are equivalent entry points. (ClickHouse's own HTTP/native clients accept a comma-separated host list and round-robin/failover natively.)
- **StarRocks**: a client connects to **any** FE on the MySQL protocol (`:9030`); Followers transparently forward DDL to the Leader and serve queries themselves. There is no single FE a client *must* reach — all 3 FE are equivalent entry points. (The MySQL JDBC/driver ecosystem supports multi-host failover URLs natively.)

Contrast with the OLTP cases that *did* need a VIP (ADR-0025): Percona XtraDB Cluster (clients hit ProxySQL → a fixed connection string) and Patroni PG (clients hit HAProxy → a fixed connection string routed to the single writable Leader). Those have **exactly one writable endpoint** that a router must steer to, so the router is a fixed endpoint that must itself be HA. The analytics engines have **no single mandatory endpoint** — every node is a valid front door — so there is no fixed-endpoint LB to make HA, and therefore **no SPOF a VIP would remove**.

## Decision

**Provide a stable client endpoint via round-robin DNS (dnsmasq multi-A `host-record`), with NO dedicated LB VMs and NO VRRP VIP, for both analytics clusters.**

- `clickhouse.nexus.lab` → multi-A record resolving to all 6 ClickHouse data nodes (`.44`–`.49`).
- `starrocks-fe.nexus.lab` → multi-A record resolving to all 3 FE (`.31`–`.33`).
- Both `host-record` entries live on `nexus-gateway`'s dnsmasq, exactly the mechanism already proven for `portainer.nexus.lab` (0.E.4c) — round-robin across multiple A records, with the resolver rotating order per query.
- Clients get a single stable name; failure of any one node means subsequent resolutions/connections land on a survivor (and the native multi-host client behavior of both engines retries the next address). The stable endpoint **is** part of the HA promise; it is delivered without a VIP because the data plane is intrinsically multi-endpoint.
- **No `keepalived`, no VRRP, no LB VMs** are added to the `04-analytics` tier. `vms.yaml`'s analytics tier carries no `virtual_ips:` block — and that absence is now intentional + documented, not an oversight.

### Why round-robin DNS is sufficient here (and why it is NOT for Percona/Patroni)

| | Writable endpoints | Client behavior | Front door | LB-tier HA needed? |
|---|---|---|---|---|
| Percona PXC (0.G.3) | effectively 1 (single-writer via ProxySQL) | fixed connection string | **ProxySQL (fixed endpoint)** | **Yes — VIP `.50`** |
| Patroni PG (0.G.4) | exactly 1 (Leader) | fixed connection string | **HAProxy routes to Leader** | **Yes — VIP `.60`** |
| SQL AG (0.G.7) | 1 (AG primary) | fixed Listener name | WSFC-migrated Listener | Yes — Listener (free w/ WSFC) |
| **ClickHouse (0.G.5)** | **all 6 nodes** | **any-node + native multi-host** | **round-robin DNS** | **No — no fixed endpoint exists** |
| **StarRocks (0.G.6)** | **all 3 FE** | **any-FE + native multi-host** | **round-robin DNS** | **No — no fixed endpoint exists** |

## Consequences

### Positive

- **No SPOF, no added VMs.** The analytics tier stays at its canon 15 VMs; no LB pair, no keepalived, no VRRP unicast config to maintain. The HA promise is satisfied by the data plane itself.
- **Stable client endpoint** (`clickhouse.nexus.lab` / `starrocks-fe.nexus.lab`) — app connection strings use one name, not a hand-maintained host list.
- **Consistent with ADR-0025**, not an exception to it: ADR-0025's decision tree explicitly classes "client-side multi-endpoint" as a valid HA front door; this ADR documents that the analytics engines are that case and records *why no VIP is needed*, which is exactly what ADR-0025 / `feedback_ha_promise_covers_lb_tier.md` require for the no-VIP branch.

### Negative

- **Round-robin DNS has no health awareness.** A resolution can hand a client a just-failed node's address; the client must retry the next. Both engines' native clients do this, but a naive single-host client (e.g., a `clickhouse-client --host clickhouse.nexus.lab` that resolves once and pins) could land on a dead node for that session. Mitigation: the smoke gate + handbook document using the engines' multi-host client forms; DNS TTL is kept low. For a *health-aware* stable endpoint the future option is a 2-node + VIP LB pair (chproxy for ClickHouse, an FE-aware proxy for StarRocks) — explicitly deferred as a possible enhancement, NOT required for the HA promise.
- **No connection-level load balancing.** Round-robin DNS balances at resolution granularity, not connection granularity. Acceptable for lab/demo traffic; a production high-QPS deployment might add chproxy/ProxySQL-class routing.

### Neutral

- **The acceptance gate from ADR-0025 still applies in spirit** — but its VIP-ownership steps are replaced by an endpoint-resilience check: resolve the round-robin name, confirm it returns all member addresses, kill one member, confirm a fresh resolution + connection still succeeds against a survivor. The smoke gate encodes this analytics-specific variant.

## Verification

`smoke-0.G.5.ps1` / `smoke-0.G.6.ps1` assert: the round-robin name resolves to the full member set (`Resolve-DnsName clickhouse.nexus.lab` / `starrocks-fe.nexus.lab` returns all member A records); a query succeeds against the name; and an endpoint-resilience check (stop one member → a fresh connection via the name still succeeds against a surviving member). No VIP-ownership probe exists for the analytics tier — by design, and this ADR is the record of why.
