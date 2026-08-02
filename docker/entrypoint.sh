#!/bin/sh
# Bring the demo database up to a usable state, then hand off to CMD (the Rails server).
# Idempotent: safe to restart the container without duplicating data.
set -e

# compose already gates on the db healthcheck, but a restarted container can still outrun it.
attempts=0
until pg_isready -q -d "${DATABASE_URL}"; do
  attempts=$((attempts + 1))
  if [ "${attempts}" -ge 60 ]; then
    echo "==> postgres did not become ready in 60s; giving up" >&2
    exit 1
  fi
  echo "==> waiting for postgres (${attempts}/60)"
  sleep 1
done

echo "==> running engine migrations"
bin/rails db:migrate

echo "==> loading seed programs"
bin/rails runner docker/seed.rb

exec "$@"
