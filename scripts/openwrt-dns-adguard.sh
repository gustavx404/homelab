#!/usr/bin/env sh
# OpenWrt: aponta o DNS da LAN para o AdGuard Home (homelab 192.168.20.189)
# Rodar NO roteador (ssh root@192.168.20.1). Idempotente — pode rodar de novo.
#
# O que faz:
#   1. dnsmasq encaminha TODAS as queries para o AdGuard (upstream unico)
#   2. DHCP option 6: clientes recebem 192.168.20.189 como DNS (query log por cliente)
#   3. (opcional, comentado) redirect DNAT: forca TODO o DNS da LAN para o AdGuard

ADGUARD="192.168.20.189"

# --- 1. dnsmasq usa o AdGuard como unico upstream -------------------------
# Obs: com noresolv=1, se o AdGuard cair a LAN fica sem DNS (ver README).
uci -q delete dhcp.@dnsmasq[0].server || true
uci add_list dhcp.@dnsmasq[0].server="${ADGUARD}#53"
uci set dhcp.@dnsmasq[0].noresolv='1'

# --- 2. DHCP option 6: clientes recebem o AdGuard como DNS -----------------
uci -q delete dhcp.lan.dhcp_option || true
uci add_list dhcp.lan.dhcp_option="6,${ADGUARD}"

uci commit dhcp
/etc/init.d/dnsmasq restart

# --- 3. (opcional) redirect DNAT: forca todo o DNS da LAN para o AdGuard ----
# Descomente se quiser capturar ate clientes com DNS fixo (ex.: 8.8.8.8).
# uci -q delete firewall.dns_int || true
# uci set firewall.dns_int='redirect'
# uci set firewall.dns_int.name='Redirect-DNS-V4'
# uci set firewall.dns_int.src='lan'
# uci set firewall.dns_int.src_dport='53'
# uci set firewall.dns_int.proto='tcp udp'
# uci set firewall.dns_int.family='ipv4'
# uci set firewall.dns_int.target='DNAT'
# uci set firewall.dns_int.dest_ip="${ADGUARD}"
# uci set firewall.dns_int.src_ip="!${ADGUARD}"   # evita loop (o proprio AdGuard)
# uci commit firewall
# /etc/init.d/firewall restart

echo "OK: dnsmasq upstream -> ${ADGUARD}#53 | DHCP option 6 -> ${ADGUARD}"
echo "Clientes so recebem o novo DNS ao renovar o lease."
echo "Para forcar renovacao imediata (derruba o SSH/roteador): /etc/init.d/network restart"
echo "Verificar: uci show dhcp | grep -E 'server|dhcp_option'; dig @${ADGUARD} example.com"
