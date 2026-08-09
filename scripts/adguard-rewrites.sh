#!/usr/bin/env bash
# AdGuard Home: garante a DNS rewrite "*.home -> <IP atual do host>" via API.
#
# O IP e detectado automaticamente (variavel do sistema), entao a rewrite
# continua correta mesmo se o lease DHCP mudar ou o AdGuard mudar de endereco.
#
# Modos:
#   --ip     Imprime o IP IPv4 do host (HOMELAB_IP tem prioridade).
#   --apply  Login na API do AdGuard e garante a rewrite (idempotente).
#   --check  Fast path p/ watcher: so aplica se o IP mudou desde a ultima vez.
#   --help   Este texto.
#
# Variaveis:
#   HOMELAB_IP         Override do IP (opcional).
#   ADGUARD_URL        URL da API (default: http://127.0.0.1:3003).
#   ADGUARD_DNS         DNS p/ probe de drift (default: 127.0.0.1).
#   ADGUARD_DRIFT_INTERVAL  Min. segundos entre probes (default: 300).
#   ADGUARD_DOMAIN     Dominio da rewrite (default: "*.home").
#   ADGUARD_STATE_DIR  Onde fica last-ip (default: /var/lib/adguard-rewrites
#                      se gravavel, senao ~/.local/state/adguard-rewrites).
#
# Credenciais: ADGUARD_USER/ADGUARD_PASSWORD vem de compose/.env (gerado por
# scripts/decrypt-secrets.sh a partir do compose/sops-secrets.yaml).
#
# Dependencias: bash, curl, sed, grep, tr, awk, ip, hostname, dig, python3, mktemp.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${ADGUARD_ENV_FILE:-${ROOT_DIR}/compose/.env}"

ADGUARD_URL="${ADGUARD_URL:-http://127.0.0.1:3003}"
ADGUARD_DOMAIN="${ADGUARD_DOMAIN:-*.home}"

# --- Estado (last-ip) -----------------------------------------------------
init_state_dir() {
  local dir="${ADGUARD_STATE_DIR:-}"
  if [ -z "$dir" ]; then
    if mkdir -p /var/lib/adguard-rewrites 2>/dev/null && [ -w /var/lib/adguard-rewrites ]; then
      dir=/var/lib/adguard-rewrites
    else
      dir="${XDG_STATE_HOME:-$HOME/.local/state}/adguard-rewrites"
      mkdir -p "$dir"
    fi
  else
    mkdir -p "$dir"
  fi
  STATE_DIR="$dir"
}

# --- IP do host ------------------------------------------------------------
detect_ip() {
  local ip=""
  if [ -n "${HOMELAB_IP:-}" ]; then
    echo "$HOMELAB_IP"
    return 0
  fi
  ip=$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.*src \([0-9.]*\).*/\1/p' | head -1)
  if [ -z "$ip" ]; then
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  fi
  if [ -z "$ip" ]; then
    echo "ERRO: nao foi possivel detectar o IP do host (use HOMELAB_IP como override)." >&2
    return 1
  fi
  echo "$ip"
}

# --- Credenciais ------------------------------------------------------------
load_credentials() {
  if [ ! -f "$ENV_FILE" ]; then
    echo "ERRO: $ENV_FILE nao encontrado." >&2
    echo "  Rode: bash scripts/decrypt-secrets.sh (apos adicionar os segredos no sops)." >&2
    return 1
  fi
  # Extrai so as chaves que precisamos (valores podem ter aspas de escape do sops).
  ADGUARD_USER=$(sed -n 's/^ADGUARD_USER=//p' "$ENV_FILE" | tail -1)
  ADGUARD_PASSWORD=$(sed -n 's/^ADGUARD_PASSWORD=//p' "$ENV_FILE" | tail -1)
  ADGUARD_USER="${ADGUARD_USER%\"}"; ADGUARD_USER="${ADGUARD_USER#\"}"
  ADGUARD_PASSWORD="${ADGUARD_PASSWORD%\"}"; ADGUARD_PASSWORD="${ADGUARD_PASSWORD#\"}"
  if [ -z "$ADGUARD_USER" ] || [ -z "$ADGUARD_PASSWORD" ]; then
    echo "ERRO: ADGUARD_USER/ADGUARD_PASSWORD ausentes em $ENV_FILE." >&2
    echo "  1) sops compose/sops-secrets.yaml   (adicionar as 2 chaves)" >&2
    echo "  2) bash scripts/decrypt-secrets.sh  (regenerar o .env)" >&2
    return 1
  fi
}

# --- API AdGuard ------------------------------------------------------------
# Escapa valor para JSON (aspas e backslashes).
esc_json() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

adguard_login() {
  COOKIE_DIR="$(mktemp -d)"
  COOKIE_JAR="${COOKIE_DIR}/cookies.txt"
  chmod 700 "$COOKIE_DIR"
  trap 'rm -rf "$COOKIE_DIR"' EXIT
  local body
  body=$(printf '{"name":"%s","password":"%s"}' "$(esc_json "$ADGUARD_USER")" "$(esc_json "$ADGUARD_PASSWORD")")
  if ! curl -fsS -m 10 -c "$COOKIE_JAR" \
       -H 'Content-Type: application/json' -d "$body" \
       "$ADGUARD_URL/control/login" >/dev/null 2>&1; then
    echo "ERRO: login no AdGuard ($ADGUARD_URL) falhou." >&2
    echo "  Causas provaveis: credencial invalida, 2FA ativo, ou AdGuard fora do ar." >&2
    return 1
  fi
  [ -s "$COOKIE_JAR" ]
}

# Retorna o "answer" atual da entrada ADGUARD_DOMAIN (vazio se nao existir).
rewrite_current_answer() {
  local list code
  list=$(curl -fsS -m 10 -b "$COOKIE_JAR" "$ADGUARD_URL/control/rewrite/list" 2>/dev/null)
  # Python via -c: heredoc roubaria o stdin do pipe com a lista.
  code='import json, sys
entries = sys.stdin.read()
try:
    data = json.loads(entries)
except Exception:
    sys.exit(0)
target = sys.argv[1]
for entry in data if isinstance(data, list) else []:
    if entry.get("domain") == target:
        print(entry.get("answer", ""))
        break'
  printf '%s' "$list" | python3 -c "$code" "$ADGUARD_DOMAIN"
}

rewrite_apply() {
  local ip="$1"
  local current
  current=$(rewrite_current_answer || true)

  if [ "$current" = "$ip" ]; then
    echo "OK: rewrite ${ADGUARD_DOMAIN} -> ${ip} (ja atualizada)"
    return 0
  fi

  if [ -n "$current" ]; then
    if ! curl -fsS -m 10 -b "$COOKIE_JAR" -H 'Content-Type: application/json' \
         -d "{\"domain\":\"$(esc_json "$ADGUARD_DOMAIN")\",\"answer\":\"$(esc_json "$current")\"}" \
         "$ADGUARD_URL/control/rewrite/delete" >/dev/null 2>&1; then
      echo "ERRO: falha ao remover rewrite antiga (${ADGUARD_DOMAIN} -> ${current})." >&2
      return 1
    fi
    echo "  removida: ${ADGUARD_DOMAIN} -> ${current}"
  fi

  if ! curl -fsS -m 10 -b "$COOKIE_JAR" -H 'Content-Type: application/json' \
       -d "{\"domain\":\"$(esc_json "$ADGUARD_DOMAIN")\",\"answer\":\"$(esc_json "$ip")\"}" \
       "$ADGUARD_URL/control/rewrite/add" >/dev/null 2>&1; then
    echo "ERRO: falha ao adicionar rewrite ${ADGUARD_DOMAIN} -> ${ip}." >&2
    return 1
  fi

  echo "OK: rewrite ${ADGUARD_DOMAIN} -> ${ip}"
}

# --- Acoes ---------------------------------------------------------------
cmd_ip() { detect_ip; }

cmd_apply() {
  local ip
  ip=$(detect_ip) || return 1
  load_credentials || return 1
  adguard_login || return 1
  if rewrite_apply "$ip"; then
    printf '%s\n' "$ip" > "$STATE_DIR/last-ip"
  fi
}

cmd_check() {
  init_state_dir
  local ip prev=""
  ip=$(detect_ip) || return 1
  [ -f "$STATE_DIR/last-ip" ] && prev=$(cat "$STATE_DIR/last-ip" 2>/dev/null || true)
  if [ "$prev" != "$ip" ]; then
    echo "IP_CHANGED: ${prev:-(sem estado)} -> ${ip}"
    cmd_apply
    return $?
  fi
  # Auto-cura de drift (rewrite apagada/reset): probe DNS, no max. 1x por
  # intervalo (default 5min). Nome unico por probe (RANDOM) evita cache.
  if command -v dig >/dev/null 2>&1; then
    local last=0 now probe ans
    [ -f "$STATE_DIR/last-check" ] && last=$(cat "$STATE_DIR/last-check" 2>/dev/null || true)
    case "$last" in *[!0-9]*) last=0;; esac
    now=$(date +%s)
    if [ $((now - last)) -ge "${ADGUARD_DRIFT_INTERVAL:-300}" ]; then
      probe="rewrite-check-${RANDOM}.${ADGUARD_DOMAIN#\*.}"
      ans=$(dig +short +time=1 +tries=1 "@${ADGUARD_DNS:-127.0.0.1}" "$probe" 2>/dev/null | tail -1)
      printf '%s\n' "$now" > "$STATE_DIR/last-check"
      if [ "$ans" != "$ip" ]; then
        echo "DRIFT: rewrite ausente ou incorreta (probe ${probe} -> ${ans:-vazio}); reaplicando"
        cmd_apply
        return $?
      fi
    fi
  fi
  echo "OK: IP inalterado (${ip})"
}

cmd_help() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# --- Main ------------------------------------------------------------------
case "${1:-}" in
  --ip)    cmd_ip ;;
  --apply) init_state_dir; cmd_apply ;;
  --check) cmd_check ;;
  --help|-h|*) cmd_help ;;
esac
