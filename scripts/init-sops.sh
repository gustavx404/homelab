#!/usr/bin/env bash
# =============================================================================
# Onboarding SOPS para quem clonou o template (fork / "Use this template").
# Gera a chave age, registra o recipient no .sops.yaml e encripta o template
# compose/sops-secrets.template.yaml -> compose/sops-secrets.yaml (seus valores).
#
# Uso:   bash scripts/init-sops.sh [--force]
# Depois: sops compose/sops-secrets.yaml   # preencher valores reais
#         bash scripts/decrypt-secrets.sh  # gerar compose/.env
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SOPS_YAML="$ROOT_DIR/.sops.yaml"
TEMPLATE="$ROOT_DIR/compose/sops-secrets.template.yaml"
SECRETS="$ROOT_DIR/compose/sops-secrets.yaml"
FORCE="${1:-}"

# --- 1. dependencia ---------------------------------------------------------
if ! command -v sops >/dev/null 2>&1; then
  echo "ERROR: sops nao instalado. https://github.com/getsops/sops"
  exit 1
fi

# --- 2. chave age ------------------------------------------------------------
KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
if [ ! -f "$KEY_FILE" ]; then
  if ! command -v age-keygen >/dev/null 2>&1; then
    echo "ERROR: chave age ausente em $KEY_FILE e age-keygen nao encontrado."
    echo "       Linux: sudo apt install age   macOS: brew install age"
    exit 1
  fi
  mkdir -p "$(dirname "$KEY_FILE")"
  age-keygen -o "$KEY_FILE"
  chmod 600 "$KEY_FILE"
  echo "Chave age gerada: $KEY_FILE"
else
  echo "Chave age existente: $KEY_FILE"
fi

PUBLIC_KEY="$(grep 'public key:' "$KEY_FILE" | awk '{print $NF}' | head -1)"
if [ -z "$PUBLIC_KEY" ]; then
  echo "ERROR: public key nao encontrada em $KEY_FILE (procure a linha '# public key: age1...')"
  exit 1
fi
echo "Public key: $PUBLIC_KEY"

# --- 3. registrar recipient no .sops.yaml (idempotente) ----------------------
if grep -q "$PUBLIC_KEY" "$SOPS_YAML"; then
  echo ".sops.yaml: recipient ja registrado."
elif grep -qE '^[[:space:]]+age:' "$SOPS_YAML"; then
  # adiciona ao final da lista existente (formato: age: age1..., age1...)
  awk -v key="$PUBLIC_KEY" '/^[[:space:]]+age:/ { print $0 ", " key; next } { print }' "$SOPS_YAML" > "$SOPS_YAML.tmp"
  mv "$SOPS_YAML.tmp" "$SOPS_YAML"
  echo ".sops.yaml: recipient adicionado a lista age existente."
else
  # cria a chave age na primeira creation_rule
  awk -v key="$PUBLIC_KEY" '
    /^[[:space:]]+- path_regex:/ { print; print "    age: " key; found=1; next }
    { print }
  ' "$SOPS_YAML" > "$SOPS_YAML.tmp"
  mv "$SOPS_YAML.tmp" "$SOPS_YAML"
  echo ".sops.yaml: recipient adicionado (nova entrada age)."
fi

# --- 4. encriptar o template --------------------------------------------------
if [ -f "$SECRETS" ] && [ "$FORCE" != "--force" ]; then
  echo "ERROR: $SECRETS ja existe. Use --force para sobrescrever (perde secrets atuais)."
  exit 1
fi
sops -e "$TEMPLATE" > "$SECRETS"
chmod 600 "$SECRETS"
echo "Secrets encriptados: $SECRETS"

echo
echo "Proximos passos:"
echo "  sops $SECRETS                    # preencher valores reais"
echo "  bash scripts/decrypt-secrets.sh  # gerar compose/.env"
