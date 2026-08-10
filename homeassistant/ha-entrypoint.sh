#!/bin/sh
# Wrapper: le credenciais do MariaDB via Docker secrets e exporta RECORDER_DB_URL.
# Evita que senhas aparecam em `docker inspect` ou `docker compose config`.

if [ -f /run/secrets/MARIADB_USER ] && [ -f /run/secrets/MARIADB_PASSWORD ] && [ -f /run/secrets/MARIADB_DATABASE ]; then
  export RECORDER_DB_URL="mysql://$(cat /run/secrets/MARIADB_USER):$(cat /run/secrets/MARIADB_PASSWORD)@mariadb/$(cat /run/secrets/MARIADB_DATABASE)?charset=utf8mb4"
fi

exec /init
