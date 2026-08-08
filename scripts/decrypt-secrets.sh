#!/usr/bin/env bash
set -euo pipefail

# Decrypt SOPS secrets and write them to compose/.env
# Requires: sops in PATH, age key at ~/.config/sops/age/keys.txt

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SECRETS_FILE="$ROOT_DIR/compose/sops-secrets.yaml"
ENV_FILE="$ROOT_DIR/compose/.env"

if ! command -v sops &>/dev/null; then
  echo "ERROR: sops is not installed. https://github.com/getsops/sops"
  exit 1
fi

if ! command -v age-keygen &>/dev/null; then
  echo "ERROR: age is not installed. https://github.com/FiloSottile/age"
  exit 1
fi

if [ ! -f "$HOME/.config/sops/age/keys.txt" ]; then
  echo "ERROR: age key not found at ~/.config/sops/age/keys.txt"
  echo "Generate one with: age-keygen -o ~/.config/sops/age/keys.txt"
  exit 1
fi

if [ ! -f "$SECRETS_FILE" ]; then
  echo "ERROR: $SECRETS_FILE not found"
  exit 1
fi

echo "Decrypting $SECRETS_FILE -> $ENV_FILE"
sops -d --output-type dotenv "$SECRETS_FILE" > "$ENV_FILE"

# Derive RECORDER_DB_URL from MARIADB_* variables
# shellcheck disable=SC1090
source "$ENV_FILE"
if [ -n "${MARIADB_USER:-}" ] && [ -n "${MARIADB_PASSWORD:-}" ] && [ -n "${MARIADB_DATABASE:-}" ]; then
  RECORDER_DB_URL="mysql://${MARIADB_USER}:${MARIADB_PASSWORD}@mariadb/${MARIADB_DATABASE}?charset=utf8mb4"
  echo "RECORDER_DB_URL=${RECORDER_DB_URL}" >> "$ENV_FILE"
fi

chmod 600 "$ENV_FILE"
echo "Done. $ENV_FILE created with restricted permissions."
