#!/usr/bin/env bash
# validate-env.sh — Validate required environment variables before deploy
# Usage: ./scripts/validate-env.sh [--env-file compose/.env]

set -uo pipefail

ENV_FILE="${1:-compose/.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found. Run 'bash scripts/decrypt-secrets.sh' first."
  exit 1
fi

# Required variables (from sops-secrets.template.yaml + compose files)
required_vars=(
  # General
  "TZ"

  # MariaDB
  "MARIADB_ROOT_PASSWORD"
  "MARIADB_DATABASE"
  "MARIADB_USER"
  "MARIADB_PASSWORD"
  "FORGEJO_DB_PASSWORD"
  "CROWDSEC_DB_PASSWORD"
  "GRAFANA_DB_PASSWORD"
  "MUMBLE_DB_PASSWORD"
  "VAULTWARDEN_DB_PASSWORD"

  # Home Assistant
  "HOMEASSISTANT_LATITUDE"
  "HOMEASSISTANT_LONGITUDE"
  "HOMEASSISTANT_ELEVATION"
  "HA_WEBHOOK_ID"

  # ESPHome
  "ESPHOME_USERNAME"
  "ESPHOME_PASSWORD"

  # Grafana
  "GRAFANA_ADMIN_USER"
  "GRAFANA_ADMIN_PASSWORD"
  "GRAFANA_OIDC_CLIENT_ID"
  "GRAFANA_OIDC_CLIENT_SECRET"

  # Mumble
  "MUMBLE_CONFIG_supw"

  # Frigate
  "FRIGATE_RTSP_PASSWORD"

  # Forgejo
  "FORGEJO_OIDC_CLIENT_ID"
  "FORGEJO_OIDC_CLIENT_SECRET"

  # Vaultwarden
  "VAULTWARDEN_ADMIN_TOKEN"
  "VAULTWARDEN_DATABASE_URL"
  "VAULTWARDEN_OIDC_CLIENT_ID"
  "VAULTWARDEN_OIDC_CLIENT_SECRET"

  # Authentik
  "AUTHENTIK_SECRET_KEY"
  "AUTHENTIK_POSTGRES_PASSWORD"
  "AUTHENTIK_BOOTSTRAP_PASSWORD"
  "AUTHENTIK_BOOTSTRAP_EMAIL"

  # Tailscale
  "TAILSCALE_AUTHKEY"

  # OmniRoute
  "OMNIROUTE_INITIAL_PASSWORD"
  "JWT_SECRET"
  "STORAGE_ENCRYPTION_KEY"
  "API_KEY_SECRET"
)

missing=0
for var in "${required_vars[@]}"; do
  if ! grep -q "^${var}=" "$ENV_FILE" 2>/dev/null; then
    echo "MISSING: $var"
    missing=$((missing + 1))
  fi
done

# Check for empty values
empty=0
for var in "${required_vars[@]}"; do
  if grep -q "^${var}=$" "$ENV_FILE" 2>/dev/null; then
    echo "EMPTY: $var"
    empty=$((empty + 1))
  fi
done

echo ""
if [[ $missing -gt 0 || $empty -gt 0 ]]; then
  echo "VALIDATION FAILED: $missing missing, $empty empty"
  exit 1
else
  echo "VALIDATION OK: all ${#required_vars[@]} required variables are set"
  exit 0
fi