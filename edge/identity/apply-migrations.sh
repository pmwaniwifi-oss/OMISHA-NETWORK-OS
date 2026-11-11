#!/usr/bin/env bash
set -euo pipefail

compose=(docker compose -f edge/docker-compose.yml -f edge/identity/docker-compose.yml)
"${compose[@]}" exec -T identity-db \
  psql -v ON_ERROR_STOP=1 \
    --username omisha_identity_admin \
    --dbname omisha_identity \
    -c "CREATE TABLE IF NOT EXISTS omisha_schema_migrations (version TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())"

for migration in edge/identity/migrations/*.sql; do
  version="$(basename "$migration" .sql)"
  if "${compose[@]}" exec -T identity-db \
      psql -At -v ON_ERROR_STOP=1 \
        --username omisha_identity_admin \
        --dbname omisha_identity \
        -c "SELECT 1 FROM omisha_schema_migrations WHERE version = '$version'" | grep -qx 1; then
    printf 'Already applied: %s\n' "$version"
    continue
  fi
  printf 'Applying %s\n' "$version"
  "${compose[@]}" exec -T identity-db \
    psql -v ON_ERROR_STOP=1 \
      --username omisha_identity_admin \
      --dbname omisha_identity < "$migration"
done
"${compose[@]}" exec -T identity-db \
  psql -v ON_ERROR_STOP=1 \
    --username omisha_identity_admin \
    --dbname omisha_identity < edge/identity/grant-runtime.sql
