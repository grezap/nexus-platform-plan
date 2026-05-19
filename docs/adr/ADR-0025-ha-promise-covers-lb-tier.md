# ADR-0025 — HA promise covers the load-balancer tier; LB SPOFs are first-class regressions

- **Status**: Accepted
- **Date**: 2026-05-19
- **Deciders**: Greg Zapantis
- **Related**: `feedback_ha_promise_covers_lb_tier.md`, ADR-0011 (Vault HA Raft pattern), [0.G.3 ProxySQL HA pair + VRRP VIP `.50`](../../../nexus-infra-oltp/docs/handbook.md), [0.G.4 HAProxy HA pair + VRRP VIP `.60`](../../../nexus-infra-oltp/docs/handbook.md), `feedback_per_cluster_state_per_engine_template.md`

## Context

Phase 0.G.4's initial scaffold landed a **single HAProxy** in front of a 3-node Patroni Postgres HA cluster. The cluster nodes themselves were HA (3-node Raft DCS in etcd + 3-node Patroni-supervised PG with automatic Leader election + streaming replication), but the LB tier was a single VM — one failed LB and the whole "HA" promise collapses to a hard outage on the client connection string.

Greg flagged this mid-scaffold (before any commit): *"why is HA proxy single. Isn't this a point of failure? can't it be clustered too?"* The flag was correct — the cluster's HA promise was being undermined by an LB-tier SPOF, and the inconsistency was specifically visible against 0.G.3 (the same repo, four sub-phases earlier), which had already established the **2-node LB + VRRP VIP** pattern for ProxySQL fronting the Percona XtraDB Cluster:

| Phase | Cluster | LB tier (as initially scaffolded) | Inconsistency |
|---|---|---|---|
| 0.G.3 | Percona XtraDB Cluster (3 nodes HA) | `proxysql-1` + `proxysql-2` with VRRP VIP `192.168.70.50` | — (HA all the way through) |
| 0.G.4 v1 | Patroni Postgres HA (3 PG + 3 etcd HA) | **`haproxy-pg` (single VM)** | LB-tier SPOF undermines the cluster HA promise |

The fix was simple — convert to a 2-node HAProxy HA pair with VRRP VIP `.60` mirroring the proxysql-1/2 + VIP `.50` pattern — but the failure mode was an architectural blind spot, not a tactical mistake: the scaffold author (me) read "Patroni HA" as describing the cluster's HA topology without reflexively asking "and what about the thing the clients actually connect to?"

The lesson generalizes well beyond 0.G.4. Every multi-node cluster the lab has built or will build sits behind some sort of LB or VIP-anchored front door:

- Kafka clusters → bootstrap servers list (multi-host, client-side LB, OK)
- Vault HA Raft → active-standby with HTTP 307 redirect to active (built-in, OK)
- Consul → multi-host gossip, no LB (OK)
- MongoDB RS → replica-set URI lists all members (client-side LB, OK)
- Redis Cluster → CRC16 slot map, client knows all nodes (OK)
- **Percona XtraDB Cluster → ProxySQL → fixed client connection string** ⇐ needs LB-tier HA
- **Patroni PG HA → HAProxy → fixed client connection string** ⇐ needs LB-tier HA
- **(Planned) SQL Server AG → Listener** ⇐ Listener IS the LB-tier HA primitive; Windows clusters get it for free
- **(Planned) StarRocks FE coordinators → ??? front door** ⇐ open question — investigate before 0.G.5 lands
- **(Planned) ClickHouse Distributed → ??? front door** ⇐ open question — investigate before 0.G.6 lands

The pattern: **whenever a fixed-endpoint LB sits between clients and a multi-node cluster, the LB tier itself must be HA**, or the cluster's HA promise is a lie at the client's view. This applies whether the LB is a dedicated middleware (HAProxy, ProxySQL) or a connection-pool router (PgBouncer).

## Decision

**Adopt as a hard project rule:** every "X HA" phase in the NexusPlatform lab must sanity-check the LB tier against the phase name **before** scaffolding starts. If a fixed-endpoint LB sits between clients and the cluster, the LB tier must be HA too — typically a 2-node HA pair fronted by a VRRP-floated VIP (the canonical pattern, established by 0.G.3 ProxySQL and confirmed by 0.G.4 HAProxy).

### What counts as "HA at the LB tier"

- **2-node HA pair + VRRP VIP** (canonical: 0.G.3 ProxySQL `.50`, 0.G.4 HAProxy `.60`). Unicast VRRP so the VIP works on isolated VMnets; priorities differ (MASTER=110, BACKUP=100); the BACKUP node continuously consumes the same backend state so failover is sub-second.
- **Client-side multi-endpoint** (Kafka bootstrap servers, MongoDB replica-set URI, Redis Cluster slot map). The client itself is the LB and tries the next endpoint on connection failure.
- **Built-in cluster redirect** (Vault Raft HTTP 307, Consul gossip). The cluster's wire protocol relays the request to the right node.

### What does NOT count

- A single LB VM (even if "the cluster behind it is HA"). Defeats the purpose.
- A 2-node LB pair with NO VIP (two endpoints with no float). Forces the client to do retry+failover, which most app stacks do badly or not at all under load.
- A reverse proxy that itself depends on a single upstream resolver (e.g., HAProxy resolving a single DNS name that points to a single VM). Failure of the resolver = failure of the LB.

### Acceptance gate

Every cluster-tier phase exit gate now includes an LB-tier HA verification step. For VIP-fronted clusters:

```
# 1. Confirm both LB nodes are responding on backend probes
ssh haproxy-pg-1 'sudo haproxy -c -f /etc/nexus-haproxy/haproxy.cfg'
ssh haproxy-pg-2 'sudo haproxy -c -f /etc/nexus-haproxy/haproxy.cfg'

# 2. Confirm the VIP is owned by exactly one node (the MASTER)
ssh haproxy-pg-1 'ip -br addr | grep <vip>'   # expect: <vip> on this node
ssh haproxy-pg-2 'ip -br addr | grep <vip>'   # expect: empty (BACKUP)

# 3. Trigger a failover (stop MASTER's keepalived) and re-check
ssh haproxy-pg-1 'sudo systemctl stop nexus-keepalived'
sleep 5
ssh haproxy-pg-2 'ip -br addr | grep <vip>'   # expect: <vip> moved here

# 4. Connect via VIP through the failover and confirm the cluster behind still serves
psql "host=<vip> sslmode=verify-ca user=... dbname=postgres" -c 'SELECT pg_is_in_recovery();'
# expect: 'f' (we hit the Leader through the BACKUP-now-MASTER LB)

# 5. Restore the original MASTER + confirm the VIP returns
ssh haproxy-pg-1 'sudo systemctl start nexus-keepalived'
sleep 5
ssh haproxy-pg-1 'ip -br addr | grep <vip>'   # expect: <vip> back on prio-110 owner
```

The smoke gate for every VIP-fronted cluster phase must include the above sequence verbatim (with cluster-specific service names).

### Backward application

The 0.G.3 ProxySQL HA pair already conformed; this ADR formalizes the rule and back-applies the **acceptance-gate sequence** to 0.G.3's smoke (was: VIP ownership probe only; now: full 5-step sequence). The 0.G.4 HAProxy HA pair was the first phase to land under the rule mid-scaffold.

## Consequences

**Positive:**

- LB SPOFs become first-class regressions, caught at gate time rather than in production-class failure scenarios.
- The 2-node + VRRP VIP pattern is now the canonical answer for any future cluster needing a fixed-endpoint LB (StarRocks FE, ClickHouse Distributed, future PgBouncer fronts, etc.).
- Client connection strings stay simple — a single VIP or DNS name — without burdening the client with retry+failover logic.

**Negative:**

- Adds 1 VM per LB tier (the 2nd LB) + keepalived config overhead.
- VRRP VIP requires the LB pair to share an L2 segment (true on VMnet11 today; requires routing planning if the lab ever spans L3 boundaries).
- Patroni unicast VRRP only — multicast not viable on VMware Workstation Host-Only networks.

**Operational:**

- `nexus-cli` `cluster-status` for VIP-fronted clusters must report the VIP owner ("MASTER node") alongside the cluster Leader; the two are independent and either can fail over independently.
- The handbook for any cluster with a VIP front door must document the failover acceptance-gate sequence in §1.4 (verify) AND §3.x (operator runbooks).

## Lessons captured

This ADR codifies `feedback_ha_promise_covers_lb_tier.md` — the memory entry that surfaced the rule from the 0.G.4 scaffold pivot. The memory is the project-facing version (read by future sessions); the ADR is the canon-facing version (read by reviewers and future contributors).
