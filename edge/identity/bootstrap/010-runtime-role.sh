#!/usr/bin/env bash
set -e

runtime_password="$(cat /run/secrets/identity_runtime_password)"
psql -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --set=runtime_password="$runtime_password" <<'SQL'
CREATE ROLE omisha_identity_runtime LOGIN PASSWORD :'runtime_password';
GRANT CONNECT ON DATABASE omisha_identity TO omisha_identity_runtime;
SQL
unset runtime_password
