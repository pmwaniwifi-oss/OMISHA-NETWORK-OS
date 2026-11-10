#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
: "${OMISHA_ENV_FILE:?Set absolute path to private environment file}"
: "${OMISHA_STACK:?Set a unique Compose project for this client}"
if [[ ! "$OMISHA_STACK" =~ ^[a-z0-9][a-z0-9_-]{0,40}$ ]]; then
  echo "Invalid stack identifier" >&2
  exit 2
fi
if [[ "$OMISHA_ENV_FILE" != /* ]]; then
  echo "Environment file path must be absolute" >&2
  exit 2
fi
if [[ $# -eq 0 ]]; then set -- config --quiet; fi
exec docker compose --env-file "$OMISHA_ENV_FILE" -p "$OMISHA_STACK" \
  -f "$root/upstream/compose.yaml" \
  -f "$root/upstream/overrides/compose.mariadb.yaml" \
  -f "$root/upstream/overrides/compose.mariadb-secrets.yaml" \
  -f "$root/upstream/overrides/compose.redis.yaml" \
  -f "$root/compose.omisha.yaml" "$@"
