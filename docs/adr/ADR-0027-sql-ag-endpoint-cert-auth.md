# ADR-0027 — SQL Server AG endpoint authentication: certificate-based

- **Status**: Accepted
- **Date**: 2026-05-20
- **Deciders**: Greg Zapantis
- **Related**: Phase 0.G.7 (SQL FCI+AG), ADR-0024 (cluster-adapter framework), ADR-0025 (HA promise covers LB tier), ADR-0026 (iSCSI shared storage), `memory/project_nexus_infra_oltp_0g7_phase.md`

## Context

SQL Server Always On AG requires every replica to host a database mirroring "HADR endpoint" (TCP listener on port 5022 by default). Inbound HADR endpoint connections must be authenticated. SQL Server supports two authentication modes for AG endpoints:

1. **Windows authentication** (`AUTHENTICATION = WINDOWS`). The SQL service account on the *connecting* node (the secondary trying to seed from the primary) must be a SQL Server login on the *listening* node, with `CONNECT ON ENDPOINT::Hadr_endpoint` permission. With our GMSA pattern (`nexus.lab\gmsa-sql-engine$` on every node — per the security env's GMSA overlay), this means creating a SQL login from the GMSA on every node + granting endpoint connect to it.

2. **Certificate-based authentication** (`AUTHENTICATION = CERTIFICATE Hadr_endpoint_cert`). Each node creates a local X509 certificate in `master`, exports the public part, ships it to every other node, and imports each peer's public-cert into its own `master`. Endpoint TLS handshakes prove identity via the cert pair.

Phase 0.G.7's hybrid topology (FCI virtual server + 2 standalone AG replicas) has a subtle wrinkle: the FCI's SQL service identity, the FCI virtual server name (`sql-fci-cluster`), and the per-node Windows identities are not 1:1. SQL Server doesn't allow the same SQL login to be the connect-endpoint-as on multiple replicas (it'd ambiguate the auth chain). With Windows auth, that means the GMSA login on each node needs an endpoint-connect grant for every OTHER node's identity — a 4×3 = 12 GRANT statements ripening into per-server login sprawl.

Two alternatives considered:

1. **Windows authentication** as above. Requires per-node `CREATE LOGIN [NEXUS\gmsa-sql-engine$]` + `GRANT CONNECT ON ENDPOINT::Hadr_endpoint` × all 4 nodes. Simple in concept; verbose in practice. Most online tutorials show this for AGs in fully domain-joined topologies (which we are).

2. **Certificate-based authentication.** Each of the 4 nodes generates its own `Hadr_endpoint_cert` via `CREATE CERTIFICATE` in `master`, exports `.cer` (public) + `.pvk` (private, encrypted by a password from Vault KV at `nexus/oltp/sqlserver/ag-endpoint-cert-password`), distributes `.cer` to the other 3 nodes via scp, and on receipt each node imports the peer's `.cer` as a database-level cert. The endpoint's `AUTHENTICATION = CERTIFICATE` clause specifies the LOCAL cert; peer auth is wire-side TLS handshake against the imported peer certs.

## Decision

**Adopt alternative 2 (certificate-based AG endpoint auth).** Four reasons:

1. **No login sprawl.** Avoids 12+ SQL Server LOGIN + GRANT statements that ripen into a per-server identity surface. Cert pair management is symmetric (each node has 1 local cert + 3 peer certs imported).
2. **Mirrors the patroni pattern.** The 0.G.4 Patroni cluster uses cert-based mutual TLS for streaming replication endpoints (via Vault PKI-issued certs). The AG endpoint cert pattern is the SQL Server equivalent — same conceptual shape (cert pair proves identity at TCP layer), different language layer (T-SQL `CREATE CERTIFICATE` vs `pg_hba.conf hostssl`). Architectural symmetry across clusters.
3. **Secret custody fits canon.** The cert PFX encryption password is a single KV entry (`nexus/oltp/sqlserver/ag-endpoint-cert-password`), 32-char hex, sticky-seeded by the security env. Sidecar-via-Vault-Agent renders it to `C:\ProgramData\nexus\sql\creds\` on each node. Standard pattern; no per-node SQL login passwords to manage.
4. **Replica add/remove is a 1-cert dance.** Adding a future replica = generate 1 cert on new node + distribute to 3 peers + import. No N×N grant matrix.

### Implementation details

Per the role-overlay `terraform/envs/oltp-sqlserver/role-overlay-ag-bootstrap.tf`:

#### Step 1 — on every node: create local cert
```sql
DECLARE @pwd nvarchar(400) = (
  SELECT TOP 1 password_text FROM OPENROWSET(
    BULK 'C:\ProgramData\nexus\sql\creds\ag-endpoint-cert-password.txt',
    SINGLE_CLOB
  ) AS T(password_text)
);
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
  EXEC('CREATE MASTER KEY ENCRYPTION BY PASSWORD = ''' + @pwd + ''';');
IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'Hadr_endpoint_cert')
  EXEC('CREATE CERTIFICATE Hadr_endpoint_cert
        WITH SUBJECT = ''AG endpoint cert for ' + @@SERVERNAME + ''';');
EXEC('BACKUP CERTIFICATE Hadr_endpoint_cert
        TO FILE = ''C:\ProgramData\nexus\sql\tls\' + @@SERVERNAME + '.endpoint.cer''
        WITH PRIVATE KEY (
          FILE = ''C:\ProgramData\nexus\sql\tls\' + @@SERVERNAME + '.endpoint.pvk'',
          ENCRYPTION BY PASSWORD = ''' + @pwd + '''
        );');
```

#### Step 2 — distribute each `.cer` to the other 3 nodes
Via scp from the build host (the terraform overlay orchestrates). The CSV path on the FCI nodes (`S:\AG_Certs\`) is shareable; AG-replica nodes use local `C:\ProgramData\nexus\sql\tls\peers\`.

#### Step 3 — on every node: CREATE ENDPOINT bound to local cert
```sql
CREATE ENDPOINT Hadr_endpoint
  STATE = STARTED
  AS TCP (LISTENER_PORT = 5022, LISTENER_IP = ALL)
  FOR DATABASE_MIRRORING (
    ROLE = ALL,
    AUTHENTICATION = CERTIFICATE Hadr_endpoint_cert,
    ENCRYPTION = REQUIRED ALGORITHM AES
  );
```

#### Step 4 — on every node: import peer `.cer` files
```sql
CREATE LOGIN [hadr_<peer>_login] WITH PASSWORD = '<random>';
CREATE USER [hadr_<peer>_user] FOR LOGIN [hadr_<peer>_login];
CREATE CERTIFICATE [hadr_<peer>_cert]
  AUTHORIZATION [hadr_<peer>_user]
  FROM FILE = 'C:\ProgramData\nexus\sql\tls\peers\<peer>.endpoint.cer';
GRANT CONNECT ON ENDPOINT::Hadr_endpoint TO [hadr_<peer>_login];
```

(The "logins" here are PURE auth scaffolding for the endpoint cert; they have no DB permissions and no Windows mapping. Their passwords are random + never logged in interactively. The cert is the actual auth artifact.)

#### Step 5 — CREATE AVAILABILITY GROUP
```sql
CREATE AVAILABILITY GROUP nexus-ag
  FOR REPLICA ON
    N'sql-fci-cluster'   WITH (ENDPOINT_URL = N'TCP://sql-fci-cluster.nexus.lab:5022',  AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, FAILOVER_MODE = AUTOMATIC, SEEDING_MODE = AUTOMATIC),
    N'sql-ag-rep-1'      WITH (ENDPOINT_URL = N'TCP://sql-ag-rep-1.nexus.lab:5022',    AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT, FAILOVER_MODE = MANUAL,   SEEDING_MODE = AUTOMATIC),
    N'sql-ag-rep-2'      WITH (ENDPOINT_URL = N'TCP://sql-ag-rep-2.nexus.lab:5022',    AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT, FAILOVER_MODE = MANUAL,   SEEDING_MODE = AUTOMATIC);
```

SEEDING_MODE = AUTOMATIC means the secondary fetches its baseline copy via the AG endpoint (TLS-encrypted using the endpoint cert) — no separate manual `RESTORE WITH NORECOVERY` step. Faster + idempotent.

## Consequences

### Positive

- **No SQL login sprawl.** 4 endpoint scaffolding logins instead of 12+ Windows-auth GRANT statements.
- **Architectural symmetry** with Patroni (cert-based replication auth).
- **Single KV cred** for the entire AG endpoint trust circle (the PFX password).
- **Replica add/remove is simple**: 1 new cert + 3 distribute + 3 import.
- **Future cert rotation** (90-day Vault PKI cycle) can apply uniformly — the AG endpoint cert is independent of the per-node mTLS leaf cert (the latter handles client TLS to the SQL :1433 listener).

### Negative

- **AG endpoint cert auth is OFFLINE — local cert, not Vault-issued.** Unlike the per-node mTLS leaf certs (issued by `pki_int/issue/sqlserver-server` with 90-day TTL + auto-rotation via Vault Agent), the endpoint certs are SQL-server-generated, password-protected, and rotated by operator-driven `BACKUP CERTIFICATE` + `DROP/CREATE CERTIFICATE` cycle. The rotation cadence is operator-controlled, not Vault-driven. Mitigation: SQL endpoint certs are wire-side only — they don't carry an identity claim that traverses the lab; rotation can be infrequent (annual is fine for a portfolio lab).
- **Initial cert distribution is brittle**: 12-file scp (`4 nodes × 3 peers each`) requires the destination paths to exist, ACLs to allow read, and the destination's `CREATE CERTIFICATE FROM FILE` to find the right file. The 0.G.7 ratification (separate session) will surface any path/permission issues here.
- **`CREATE LOGIN` requires SQL auth mode** (Windows auth alone can't host SQL-only logins). Phase 0.G.7's `setup.exe /SECURITYMODE=SQL` arg at FCI install time enables mixed mode for exactly this reason. The `sa` login is left disabled (default) — only the cert auth logins exist in SQL auth mode.

### Neutral

- **Choice of cert subject** (`'AG endpoint cert for ' + @@SERVERNAME`) is informational only — SQL Server doesn't validate the subject against the connecting peer's identity. The trust is "do I have this cert imported?" not "does this cert's subject match?". A future hardening pass could match subject ↔ source IP via a trigger but that's overkill for a portfolio lab.

## Verification

- **smoke-0.G.7 Section 9** (AG sync state) confirms `synchronization_state_desc = SYNCHRONIZED` (FCI) + `SYNCHRONIZING` (async replicas). If endpoint auth fails, `synchronization_state_desc` shows `NOT SYNCHRONIZING` + sys.dm_hadr_database_replica_states reports last_connect_error_number = 35206 (endpoint connect failed).
- **Manual probe** during ratification: `SELECT @@SERVERNAME, type, type_desc, state_desc FROM sys.endpoints WHERE name = 'Hadr_endpoint'` returns `STARTED` on all 4 nodes.
- **Cert visibility**: `SELECT name, thumbprint, start_date, expiry_date FROM sys.certificates WHERE name LIKE 'Hadr_%' OR name LIKE 'hadr_%_cert'` returns 4 rows per node (1 local + 3 peer).

## References

- Phase 0.G.7 in MASTER-PLAN.md
- ADR-0024 — cluster-adapter framework
- ADR-0025 — HA promise covers LB tier (the AG Listener IS the LB-tier HA primitive for SQL AG)
- ADR-0026 — SQL FCI iSCSI shared storage
- Microsoft docs: <https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/use-the-availability-group-wizard-sql-server-management-studio#using-certificate-authentication> (for the standalone canonical reference)
- `memory/project_nexus_infra_oltp_0g7_phase.md`
