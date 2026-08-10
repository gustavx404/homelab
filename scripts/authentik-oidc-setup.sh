#!/usr/bin/env bash
# =============================================================================
# Cria providers OAuth2/OIDC + applications no Authentik para os servicos
# que usam SSO (Immich, Vaultwarden). Idempotente — pula providers existentes.
#
# Uso:   bash scripts/authentik-oidc-setup.sh
# Depois: copie os Client ID/Secret impressos para o sops:
#   sops compose/sops-secrets.yaml   (IMMICH_OIDC_*, VAULTWARDEN_OIDC_*)
#   bash scripts/decrypt-secrets.sh  (gera compose/.env)
#   docker compose -f compose/compose.yaml up -d immich vaultwarden
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! docker ps --format '{{.Names}}' | grep -q '^authentik-server$'; then
  echo "ERROR: container authentik-server nao esta rodando. Suba o stack auth antes." >&2
  exit 1
fi

docker cp "$SCRIPT_DIR/authentik-oidc-setup.py" authentik-server:/tmp/authentik-oidc-setup.py
docker exec authentik-server ak shell -c "exec(open('/tmp/authentik-oidc-setup.py').read())"
