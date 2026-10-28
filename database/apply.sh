#!/usr/bin/env sh
set -eu

if [ -z "${DATABASE_URL:-}" ]; then
  echo "Set DATABASE_URL to the PostgreSQL connection string first." >&2
  exit 1
fi

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$(dirname "$0")/schema.sql"
