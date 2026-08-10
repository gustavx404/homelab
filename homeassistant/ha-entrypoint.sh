#!/bin/sh
# Wrapper: constroi RECORDER_DB_URL a partir dos env vars MARIADB_* antes de iniciar o HA.
# Prevents credentials from leaking via `docker inspect`.

if [ -n "${MARIADB_USER:-}" ] && [ -n "${MARIADB_PASSWORD:-}" ] && [ -n "${MARIADB_DATABASE:-}" ]; then
  export RECORDER_DB_URL="mysql://${MARIADB_USER}:${MARIADB_PASSWORD}@mariadb/${MARIADB_DATABASE}?charset=utf8mb4"
fi

exec /init
