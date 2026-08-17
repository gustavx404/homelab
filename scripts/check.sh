#!/usr/bin/env bash
# check.sh -- CI local do homelab
# QUANDO: Antes de QUALQUER commit/push (mandatorio via AGENTS.md hooks)
# O QUE: Valida YAML, Docker Compose, secrets, configuracoes
# EXIT: 0 = tudo verde, 1 = lista falhas
set -uo pipefail

cd "$(dirname "$0")/.."

fails=0
ok()   { printf '  [OK]   %s\n' "$1"; }
fail() { printf '  [FAIL] %s\n' "$1"; fails=$((fails + 1)); }

# ---------------------------------------------------------------------------
echo "==> 1/5 YAML lint (compose/, homeassistant/, suricata/, monitoring/, crowdsec/, traefik/, frigate/)"
# ---------------------------------------------------------------------------
if command -v yamllint >/dev/null 2>&1; then
  if yamllint -c .yamllint.yaml compose/ homeassistant/ suricata/ monitoring/ crowdsec/ traefik/ frigate/ 2>/dev/null; then
    ok "yamllint"
  else
    fail "yamllint -- erros de lint YAML"
  fi
else
  echo "  [SKIP] yamllint nao instalado"
fi

# ---------------------------------------------------------------------------
echo "==> 2/5 Docker Compose validate"
# ---------------------------------------------------------------------------
if [[ -f compose/.env.example ]]; then
  # Valida o compose com o template, mas PRESERVA o .env real (segredos SOPS)
  # e o restaura ao final — nunca sobrescrever o .env em producao.
  if [[ -f compose/.env ]]; then
    cp compose/.env /tmp/compose.env.backup.$$
    trap 'rm -f /tmp/compose.env.backup.$$' EXIT
  fi
  cp compose/.env.example compose/.env
  if docker compose -f compose/compose.yaml config --quiet 2>/dev/null; then
    ok "docker compose config"
  else
    fail "docker compose config -- configuracao invalida"
  fi
  if [[ -f /tmp/compose.env.backup.$$ ]]; then
    cp /tmp/compose.env.backup.$$ compose/.env
    rm -f /tmp/compose.env.backup.$$
    trap - EXIT
  fi
else
  fail "compose/.env.example ausente"
fi

# ---------------------------------------------------------------------------
echo "==> 3/5 Trivy config scan (compose/)"
# ---------------------------------------------------------------------------
if command -v trivy >/dev/null 2>&1; then
  if trivy config --severity CRITICAL,HIGH --exit-code 1 compose/ 2>/dev/null; then
    ok "trivy config scan"
  else
    fail "trivy config scan -- vulnerabilidades CRITICAL/HIGH encontradas"
  fi
else
  echo "  [SKIP] trivy nao instalado"
fi

# ---------------------------------------------------------------------------
echo "==> 4/5 Secrets check (arquivos tracked)"
# ---------------------------------------------------------------------------
# Verifica por padroes comuns de secrets em arquivos versionados
# Ignora referencias a variaveis de ambiente ${VAR} e arquivos .example
secret_found=false

# Check for hardcoded private keys
if git grep -iE "BEGIN.*PRIVATE KEY|-----BEGIN OPENSSH PRIVATE KEY-----" -- '*.yaml' '*.yml' '*.json' '*.sh' '*.py' '*.env*' 2>/dev/null | grep -v ".example" | grep -v "sops" | grep -v "age" | head -5; then
  secret_found=true
fi

# Check for hardcoded api keys, secrets, passwords, tokens (not env var refs)
# Use patterns that match actual assignments like key = "value" or key: "value"
# Not code references like function calls
# Ignore ESPHome fallback AP passwords (config123 is a known default)
patterns=(
  "api[_-]?key\s*[:=]\s*[\"'][^\"']+[\"']"
  "secret[_-]?key\s*[:=]\s*[\"'][^\"']+[\"']"
  "password\s*[:=]\s*[\"'][^\"']+[\"']"
  "token\s*[:=]\s*[\"'][^\"']+[\"']"
)
for pattern in "${patterns[@]}"; do
  if git grep -iE "$pattern" -- '*.yaml' '*.yml' '*.json' '*.sh' '*.py' '*.env*' 2>/dev/null | grep -v ".example" | grep -v "sops" | grep -v "age" | grep -v '\${' | grep -v 'config123' | grep -v 'fallback' | head -5; then
    secret_found=true
  fi
done

if [[ "$secret_found" == "false" ]]; then
  ok "nenhum secret obvio em arquivos tracked"
else
  fail "possiveis secrets encontrados em arquivos tracked"
fi

# ---------------------------------------------------------------------------
echo "==> 5/5 SOPS/AGE secrets validos"
# ---------------------------------------------------------------------------
if command -v sops >/dev/null 2>&1; then
  # Find files that are actually encrypted (contain sops metadata)
  sops_files=$(find . -name "*.sops.yaml" -o -name "*.sops.yml" -o -name "secrets.yaml" -o -name "secrets.yml" 2>/dev/null | head -10)
  if [[ -n "$sops_files" ]]; then
    # Only test decrypt on files that have sops metadata
    sops_ok=true
    tested=0
    while IFS= read -r f; do
      if head -20 "$f" 2>/dev/null | grep -q "sops:"; then
        if [[ -n "${SOPS_AGE_KEY_FILE:-}" ]] || [[ -f "$HOME/.config/sops/age/keys.txt" ]]; then
          if ! sops -d "$f" >/dev/null 2>&1; then
            fail "SOPS decrypt falhou: $f"
            sops_ok=false
          fi
          tested=1
        else
          echo "  [SKIP] age key nao disponivel para testar decrypt"
        fi
      else
        echo "  [SKIP] $f nao eh arquivo encriptado SOPS (sem metadata sops:)"
      fi
    done <<< "$sops_files"
    if [[ $tested -eq 0 ]]; then
      echo "  [SKIP] nenhum arquivo SOPS encriptado encontrado para testar"
    elif [[ "$sops_ok" == "true" ]]; then
      ok "SOPS secrets descriptografam corretamente"
    fi
  else
    echo "  [SKIP] nenhum arquivo SOPS encontrado"
  fi
else
  echo "  [SKIP] sops nao instalado"
fi

# ---------------------------------------------------------------------------
echo ""
if [[ $fails -eq 0 ]]; then
  echo "==> CHECK PASSOU -- pronto pra commit"
  exit 0
else
  echo "==> CHECK FALHOU -- $fails falha(s)"
  exit 1
fi