#!/usr/bin/env bash
# Instala o watcher de IP -> rewrite *.home do AdGuard Home:
#   1. systemd timer (verifica a cada 30s, ajustavel com --interval)
#   2. hook dhcpcd (dispara na hora da renovacao do lease DHCP)
#   3. diretorio de estado /var/lib/adguard-rewrites
#
# Uso: sudo bash scripts/install-adguard-rewrites-watch.sh [--interval 30s]
# Remove: sudo systemctl disable --now adguard-rewrites.timer
#         sudo rm /usr/lib/dhcpcd/dhcpcd-hooks/90-adguard-rewrites
#
# Requisito: credenciais em compose/.env (ADGUARD_USER/ADGUARD_PASSWORD) —
# ver scripts/adguard-rewrites.sh. Idempotente: pode rodar de novo.

set -euo pipefail

INTERVAL="30s"
[ "${1:-}" = "--interval" ] && INTERVAL="${2:-30s}"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERRO: rode com sudo (instala units em /etc/systemd/system e hook em /usr/lib/dhcpcd)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/adguard-rewrites.sh"

if [ ! -x "$SCRIPT" ]; then
  echo "ERRO: $SCRIPT nao encontrado (rode a partir do repo)." >&2
  exit 1
fi

IFACE=$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.*dev \([^ ]*\).*/\1/p' | head -1)

# --- diretorios -----------------------------------------------------------
mkdir -p /var/lib/adguard-rewrites /etc/adguard-rewrites
printf '%s\n' "$IFACE" > /etc/adguard-rewrites/iface

# --- units systemd ---------------------------------------------------------
sed "s|__SCRIPT__|$SCRIPT|g" "$SCRIPT_DIR/systemd/adguard-rewrites.service" \
  > /etc/systemd/system/adguard-rewrites.service
sed -e "s|__SCRIPT__|$SCRIPT|g" \
    -e "s|__INTERVAL__|$INTERVAL|g" \
  "$SCRIPT_DIR/systemd/adguard-rewrites.timer" \
  > /etc/systemd/system/adguard-rewrites.timer

# --- hook dhcpcd ------------------------------------------------------------
sed "s|__SCRIPT__|$SCRIPT|g" "$SCRIPT_DIR/dhcpcd-hook/90-adguard-rewrites" \
  > /usr/lib/dhcpcd/dhcpcd-hooks/90-adguard-rewrites
chmod 755 /usr/lib/dhcpcd/dhcpcd-hooks/90-adguard-rewrites

systemctl daemon-reload
systemctl enable --now adguard-rewrites.timer

echo "OK: watcher instalado (timer ${INTERVAL}, iface ${IFACE})."
echo "    Estado em /var/lib/adguard-rewrites/last-ip."
echo "    Timer: systemctl status adguard-rewrites.timer"
echo "    Rodar agora: $SCRIPT --apply"
