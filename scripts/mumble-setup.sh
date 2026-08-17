#!/bin/bash
# mumble-setup.sh — cria canais e regras ACL no Mumble (Murmur)
# Roda no host. Idempotente.
# Requer: container mariadb rodando.
set -euo pipefail

# Resolve senha root do MariaDB (Docker secret montado no container)
echo "==> Lendo senha root do MariaDB..."
MYSQL_PWD=$(docker exec mariadb cat /run/secrets/MARIADB_ROOT_PASSWORD 2>/dev/null) || {
  echo "ERROR: nao foi possivel ler a senha root. O container mariadb esta rodando?" >&2
  exit 1
}

mysql_cmd() {
  docker exec -i -e MYSQL_PWD="$MYSQL_PWD" mariadb mariadb -uroot "$@"
}

echo "==> Criando canais padrao..."

mysql_cmd mumble <<'SQL'
INSERT IGNORE INTO channels (server_id, channel_id, parent_id, name, inheritacl)
VALUES
  (1, 1, 0, 'Home',   1),
  (1, 2, 0, 'Study',  1),
  (1, 3, 0, 'Gaming', 1),
  (1, 4, 0, 'AFK',    1);
SQL

echo "==> Canais criados (ou ja existiam)."

echo "==> Aplicando regras ACL no canal Root..."
mysql_cmd mumble <<'SQL'
DELETE FROM acl WHERE server_id=1 AND channel_id=0;

-- ACL no canal Root (channel_id=0), user_id=0 (SuperUser como placeholder p/ groups)
-- grantpriv: 1=Enter 2=Speak 4=Whisper 8=MuteDeafen 16=Move 32=MakeChannel 64=Link 128=TextMessage

-- @all: Enter + Speak (aplica aqui e nos sub-canais)
INSERT INTO acl (server_id, channel_id, priority, user_id, group_name, apply_here, apply_sub, grantpriv)
VALUES (1, 0, 5, 0, 'all', 1, 1, 3);

-- @auth: Enter + Speak + Whisper + MakeTempChannel (aplica aqui e nos sub-canais)
INSERT INTO acl (server_id, channel_id, priority, user_id, group_name, apply_here, apply_sub, grantpriv)
VALUES (1, 0, 10, 0, 'auth', 1, 1, 39);
SQL

echo "==> ACL aplicada."
echo
echo "Setup completo. Conecte no Mumble como SuperUser:"
echo "  Name:     SuperUser"
echo "  Password: (MUMBLE_CONFIG_supw do sops)"
echo "  Server:   ${MUMBLE_PUBLIC_HOST:-<defina MUMBLE_PUBLIC_HOST no .env>}"
echo
echo "Depois registre seu usuario normal e de promote via cliente."
echo "https://wiki.mumble.info/wiki/ACL_and_Groups"
