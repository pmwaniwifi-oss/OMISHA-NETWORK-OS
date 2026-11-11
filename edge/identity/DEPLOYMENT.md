# Identity control-plane deployment

This Compose file is intentionally separate from `edge/docker-compose.yml`. It deploys only the identity-control-plane PostgreSQL service on a private Docker network. It publishes no host port and the existing gateway is not attached to this network yet.

## Operator preparation

1. On the Linux host, create `edge/identity/secrets/identity_db_password` outside source control with a long, randomly generated database bootstrap password. Restrict it to the deployment owner (`chmod 600` on Linux). Never paste it into a tracked file or commit it.
2. Verify the host data volume is on encrypted storage and has a backup policy before first use. Docker named volumes are persistent storage, not encryption or backup.
3. Review the pinned image version and update it through a reviewed change after compatibility checks.
4. Start only when intentionally preparing the IAM database with `docker compose -f edge/identity/docker-compose.yml up -d`. This repository change does not run that command.
5. Before applying migrations, create a least-privilege runtime database role; the configured bootstrap user is an initialization administrator, not the future Go application's account. Use a separate migration role and runtime role, and keep their credentials in deployment secrets.
6. Apply the ordered SQL migrations using a controlled migration job, then verify a backup restore. Do not mount the migrations into the Postgres image's one-time initialization directory: that mechanism only runs for a new empty data directory and is not an upgrade system.

## Isolation and known gap

The database uses an internal-only network and has no `ports:` mapping. The gateway is not connected, and no application database client exists yet. A later change must intentionally connect only the gateway/migration job to this internal network, provide a separate least-privilege runtime credential, and define secret rotation and backup/restore procedures.

For PostgreSQL 18 the official image uses `/var/lib/postgresql` as the volume root; the data directory is version-specific beneath it. Do not change this mount path without reviewing the selected image major version and its persistence requirements.
