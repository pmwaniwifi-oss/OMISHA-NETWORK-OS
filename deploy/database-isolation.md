# Database isolation and container topology

## Binding design decision

Each application persists data in its own database service/container and private
volume. A database never runs inside the Go gateway, Rust worker, ERP application,
NMS PHP process, or mobile API container. Do not point unrelated applications at
one shared application database. Per-client ERP data gets a separate Frappe
Compose project and MariaDB container/volume, credentials and backup set. NMS
Prime data is on its own PostgreSQL service/volume and NMS-compatible database
accounts. Production Zabbix and n8n databases are separately deployed services.

The existing Frappe Compose configuration already defines the database as the
separate `db` service and the app as backend/frontend/queues. The Compose wrapper
uses a unique project and therefore isolates its volumes and service network for
each client. The VM pilot publishes ERP only on loopback. Do not combine Frappe
and NMS tables in the ERP database, and do not put database ports on the public
internet.

## Logical data stores

| Workload | Own container/service | Data boundary | Notes |
|---|---|---|---|
| One client ERPNext/Frappe site | MariaDB container per client stack | Frappe site plus dedicated MariaDB volume/password/backup | Frappe app containers are separate. Frappe uses its documented MariaDB/Redis topology. |
| One client NMS Prime Community | PostgreSQL service per client NMS boundary | NMS PostgreSQL database and volume | The pinned NMS source defaults Laravel to `DB_CONNECTION=pgsql`, `DB_HOST`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`; RPM installer and migration compatibility still need a clean test. |
| NMS MariaDB feature dependencies | Separate MariaDB container only where enabled | Its own database/user/volume | NMS config declares MariaDB connections (including config/import/VoIP/Icinga features) and RPM dependencies. Do not assume every feature is unused; inventory the installed NMS modules before sizing or omitting it. |
| Zabbix | Its own database container | Zabbix server/schema/volume | Select the supported backend for the pinned Zabbix version. Never use the NMS or ERP schema. |
| n8n | Its own PostgreSQL service for durable production data | n8n database/volume | Do not run production workflows on SQLite or share ERP credentials. |
| OMISHA report/operations control | Separate service-owned database when promoted from pilot | Per-client report/job/audit data | The current report pilot uses local SQLite and is not production multi-user software. Move to a supported service DB before concurrent use. |
| Go, Rust, Flutter API | No embedded authoritative business database | Use authenticated service APIs and a transactional outbox owned by a database service | Valkey is a disposable cache only; no bills, subscriber authority, signed logs or entitlements live only in Valkey. |
| Raw ISP logs | Append/archive object/filesystem service | Tenant/date partitions, protected immutable backup | Not a relational write to every database; preserve mandated original records. |

The NMS repository declares PostgreSQL 16 and MariaDB server RPM dependencies and
multiple Laravel connections. Its main PostgreSQL configuration accepts
`DB_HOST`, and the package pins PostgreSQL major 16. An opt-in PostgreSQL 16
Compose service is supplied for a same-host Rocky/RHEL install. It uses a
dedicated bridge, with the host port loopback-bound so the native NMS service can
reach PostgreSQL at `127.0.0.1:5432`. The RPM dependencies may install
local PostgreSQL binaries too; disable the local PostgreSQL service only as part
of a documented, backed-up migration. The Compose file is a configuration starting
point; RPM setup, roles, schema creation, extensions, TLS and backup/restore have
not been validated. Do not start it in production before that staging drill.
NMS optional MariaDB connections remain separate database services where the
installed NMS features require them.

## Scale and performance

Containers provide process and volume boundaries. Containers on one laptop still
compete for the same CPU, memory, storage and IOPS; splitting containers does not
create extra capacity or prove a speed increase. At the laptop pilot, start only
ERP and a small synthetic NMS test if the operator's VM resources allow it. Do not
start Zabbix, n8n, PM-WANI services, or multiple DBs by default. Keep each Compose
stack opt-in and stop unused pilots. Record resource limits from actual load tests
before setting production limits; a database starvation limit can corrupt latency.

For hosted production, schedule each DB on its own storage/CPU/memory class. Small
clients can use separate databases/schemas on a managed database cluster only if
that becomes an explicit, benchmarked cost decision and the security isolation
model is approved; it is not the current per-client dedicated-container design.
Large clients can move DB containers to separate Linux VMs or dedicated database
hosts without changing application API contracts. Use connection pools, indexes,
batched events, a durable outbox and separate read projections. Scale read-only
replicas only when the selected engine and application support them. Never scale
by dual-writing one record to several independent databases without reconciliation.

Measure before tuning: per-container CPU/memory/OOM, DB connections and lock wait,
query p95/p99, storage growth, fsync latency/IOPS, queue age, API p95/p99, and
report generation time. Load tests must include peak log ingestion, invoice
posting, backups and recovery together. A separate database container cannot by
itself guarantee “no lag.”

## Network, secrets and recovery rules

- Use private Compose networks; app containers reach only required DB services.
  Do not publish database ports. For the NMS VM to reach a Docker database, use a
  private host/overlay network with TLS and host firewall rules, then validate
  vendor installation support. Avoid an unrestricted Docker bridge exposed to LAN.
- Give each app one least-privilege database account, separate from DB admin.
  Mount credentials from private files/secrets; do not put values in Git, images,
  Compose labels or routine logs. Rotate by tested procedure.
- Make a consistent DB backup plus file/object backup for each client. Encrypt and
  copy to a separate failure domain. Retain immutable manifests and regularly
  restore into an isolated staging stack; measure RPO/RTO. A running volume is
  not a backup. Never remove real volumes as routine rollback.
- Upgrade one client staging copy first. Database migration rollback is a restore
  plan, not just a prior container tag. Version schemas, images and backup sets.
- Tenant separation is not an authentication substitute. The API must bind user
  identity to a client, site and record before forwarding an upstream lookup.

## Git implementation status

- Per-client ERP MariaDB is present in the official Frappe Docker Compose service;
  the OMISHA wrapper keeps it separate, uses a file secret and private localhost
  frontend. Config-only CI validates these boundaries and does not start ERP.
- NMS source is pinned separately and its main database connection/env contract
  is documented. NMS host deployment and Docker PostgreSQL integration are not
  run or certified here.
- Valkey remains a separate volatile cache. The local reporting SQLite pilot and
  all network/API adapters are explicitly not production database deployments.

Before production, verify actual NMS modules and secondary DB uses, decide how many
clients justify one DB container per client, allocate durable VM disks, restore
NMS/ERP/Zabbix/n8n independently, then load-test concurrent client workloads.
