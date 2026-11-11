# Identity control-plane deployment

This Compose file is an explicit overlay for `edge/docker-compose.yml`. Use both files together to add PostgreSQL and attach only the gateway to the identity network. The normal edge Compose command remains unchanged and does not start PostgreSQL.

## Operator preparation

Before the first start, create these local secret files under `edge/identity/secrets/`; this directory is ignored by Git:

- `identity_db_password`: random bootstrap/admin password for the Postgres superuser.
- `identity_runtime_password`: a separate random password for the gateway's restricted PostgreSQL role.
- `identity_database_url`: PostgreSQL DSN for `omisha_identity_runtime`, host `identity-db`, port `5432`, database `omisha_identity`; URL-encode any special characters in the password.
- `identity_hmac_key`: at least 32 random bytes for nonce, provider-subject and opaque-session HMACs.

Restrict file permissions to the deployment owner (for example, `chmod 600` on Linux). Do not put credentials in Compose YAML, app source, shell history or public Git. Set `OMISHA_GOOGLE_SERVER_CLIENT_ID` only to the public server/web OAuth client ID. No client secret belongs in the Android app or repository.

Verify the Docker volume is on encrypted host storage and has a tested backup policy. Docker named volumes provide persistence, not encryption or backup.

## Explicit deployment commands

From the repository root, after preparing secrets:

```sh
docker compose -f edge/docker-compose.yml -f edge/identity/docker-compose.yml config --quiet
docker compose -f edge/docker-compose.yml -f edge/identity/docker-compose.yml up -d
bash edge/identity/apply-migrations.sh
```

These commands are instructions only; the repository change does not execute them. The database has no published host port. It is on an internal-only network shared only with the gateway. The runtime role is created at first database initialization from `identity_runtime_password`. The migration helper applies ordered SQL files once using the migration ledger, then grants the gateway role only the table operations needed for identity sign-in. It does not grant DDL or DELETE.

The Postgres entrypoint runs the runtime-role bootstrap only when initializing an empty data volume. Secret changes after first initialization do not rotate an existing database role; password rotation needs a coordinated database role update and DSN secret change.

## Authentication boundaries

The Go gateway returns 503 from Google identity endpoints until database URL, HMAC key and Google server client ID are configured. The Google challenge route returns a short-lived random nonce; exchange validates Google's ID token signature, issuer, audience and expiry, checks the exact nonce claim, and consumes the DB challenge once in the same transaction that maps the provider subject and creates an opaque identity session. It stores only keyed HMAC digests for the provider subject, nonce and session token.

Google public signing keys may need to be fetched or refreshed, so Google social login requires outbound connectivity to Google's key service. Local ISP/NMS operations and the separate offline-license verification design do not rely on this login route.

The gateway has only a small in-process IP rate limiter. Before internet-facing deployment, add a trusted reverse-proxy rate limit or shared Valkey-backed limiter; do not trust arbitrary `X-Forwarded-For` headers. OTP, membership listing, context activation, session revocation, tenant credential routing and business APIs remain unimplemented. Thus successful Google identity exchange alone does not enable a usable customer or staff workspace.

## Migration and recovery

Back up the volume before migrations and test restore. Keep migration files append-only after application. The helper records completed migration names so rerunning it skips applied SQL. Restore testing must use an isolated non-production database. Never treat a volume snapshot as the only backup.
