#!/bin/bash
# Cria bancos e usuarios das apps que compartilham o MariaDB central.
# Executado pelo entrypoint do container mariadb apenas no primeiro boot
# (diretorio de dados vazio). Idempotente.
# Senhas vem de compose/.env (sops) repassadas ao container via environment.
set -euo pipefail

: "${FORGEJO_DB_PASSWORD:?FORGEJO_DB_PASSWORD nao definida no .env}"
: "${CROWDSEC_DB_PASSWORD:?CROWDSEC_DB_PASSWORD nao definida no .env}"
: "${GRAFANA_DB_PASSWORD:?GRAFANA_DB_PASSWORD nao definida no .env}"

# Senha root: secret file (compose/database.yaml) ou env (uso manual/testes)
if [ -r /run/secrets/MARIADB_ROOT_PASSWORD ]; then
  MYSQL_PWD="$(cat /run/secrets/MARIADB_ROOT_PASSWORD)"
elif [ -n "${MARIADB_ROOT_PASSWORD:-}" ]; then
  MYSQL_PWD="${MARIADB_ROOT_PASSWORD}"
else
  echo "ERROR: MARIADB_ROOT_PASSWORD nao encontrada (secret file ou env)" >&2
  exit 1
fi
export MYSQL_PWD

mariadb --protocol=socket -uroot <<SQL
CREATE DATABASE IF NOT EXISTS forgejo CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'forgejo'@'%' IDENTIFIED BY '${FORGEJO_DB_PASSWORD//\'/\'\'}';
GRANT ALL PRIVILEGES ON forgejo.* TO 'forgejo'@'%';


CREATE DATABASE IF NOT EXISTS crowdsec CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'crowdsec'@'%' IDENTIFIED BY '${CROWDSEC_DB_PASSWORD//\'/\'\'}';
GRANT ALL PRIVILEGES ON crowdsec.* TO 'crowdsec'@'%';

CREATE DATABASE IF NOT EXISTS grafana CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'grafana'@'%' IDENTIFIED BY '${GRAFANA_DB_PASSWORD//\'/\'\'}';
GRANT ALL PRIVILEGES ON grafana.* TO 'grafana'@'%';

FLUSH PRIVILEGES;
SQL
