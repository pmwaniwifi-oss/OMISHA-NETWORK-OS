#!/usr/bin/env bash
set -euo pipefail

compose=(docker compose -f edge/docker-compose.yml -f edge/identity/docker-compose.yml)
for migration in edge/identity/migrations/*.sql; do
  printf 'Applying %s\n' "$migration"
  "${compose[@]}" exec -T identity-db \
    psql -v ON_ERROR_STOP=1 \
      --username omisha_identity_admin \
      --dbname omisha_identity < "$migration"
done
"${compose[@]}" exec -T identity-db \
  psql -v ON_ERROR_STOP=1 \
    --username omisha_identity_admin \
    --dbname omisha_identity < edge/identity/grant-runtime.sql
