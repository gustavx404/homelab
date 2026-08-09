# homelab

Infraestrutura auto-hospedada — Docker Compose, 11 services, rede zero-confianca.

[![CI](https://img.shields.io/github/actions/workflow/status/gustavx404/homelab/ci.yaml?style=flat-square&label=ci&color=10b981)](https://github.com/gustavx404/homelab/actions)
[![services](https://img.shields.io/badge/services-11-3b82f6?style=flat-square)]()
[![suricata](https://img.shields.io/badge/suricata-8-6b7280?style=flat-square)]()
[![secrets](https://img.shields.io/badge/secrets-sops%2Bage-6b7280?style=flat-square)]()

---

## Architecture

```
Internet → OpenWrt (borda + CrowdSec bouncer)
                │
                ▼  :80 :443
           ┌─────────────┐
           │  Traefik v3  │  reverse proxy · path-based routing
           │  /         HA│
           │  /grafana    │
           │  /git        │
           └──────┬───────┘
                  │  backend network (br-homelab)
     ┌────────┬───┴───┬────────┬────────┬────────┐
     ▼        ▼       ▼        ▼        ▼        ▼
  mariadb  grafana prometheus forgejo  mumble  crowdsec
     └────────┴───────┴───┬────┴────────┴────│───┘
                     host network             ▼
               suricata · esphome       LAPI :8080
               (eno1)     (:6052)       (→ OpenWrt)
```

- Traefik e o unico ponto de entrada HTTP/S. Todos os apps web passam por ele.
- Suricata e ESPHome usam `network_mode: host` por necessidade (packet capture / mDNS).
- CrowdSec envia decisoes de ban para o OpenWrt na borda da rede.

---

## Quick Start

```bash
# dependencies
curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh ./get-docker.sh
sudo apt install -y docker-compose-v2 age yamllint
curl -LO https://github.com/getsops/sops/releases/download/v3.13.3/sops-v3.13.3.linux.amd64
sudo install -m 755 sops-v3.13.3.linux.amd64 /usr/local/bin/sops

# generate age key and copy public key to .sops.yaml
age-keygen -o ~/.config/sops/age/keys.txt

# edit secrets with real values
sops compose/sops-secrets.yaml

# decrypt and generate .env
bash scripts/decrypt-secrets.sh

# deploy all stacks
docker compose -f compose/compose.yaml up -d
```

**Access** — path-based routing, zero DNS dependency. Self-signed TLS.

| path | service |
|------|---------|
| `/` | Home Assistant |
| `/grafana/` | Grafana |
| `/git/` | Forgejo |

---

## Services

| stack | service | image | access |
|-------|---------|-------|--------|
| home | traefik | `v3.3` | `80,443` |
| home | homeassistant | `stable` | internal |
| home | mariadb | `lts` | internal |
| home | esphome | `stable` | `6052` host |
| security | suricata | `latest` | host |
| security | crowdsec | `latest` | `8080` lapi |
| services | forgejo | `16.0.2` | `2222` ssh |
| services | mumble | `latest` | `64738` tcp/udp |
| services | kali | `rolling` | cli |
| monitoring | prometheus | `v3.4.0` | `127.0.0.1:9090` |
| monitoring | grafana | `11.6.0` | internal |

---

## Structure

```
compose/
├── compose.yaml        master (include)
├── network.yaml        network + secrets
├── home.yaml           mariadb · homeassistant · esphome
├── security.yaml       suricata · crowdsec
├── monitoring.yaml     prometheus · grafana
├── services.yaml       traefik · forgejo · mumble · kali
├── .env.example        template
└── sops-secrets.yaml   encrypted (SOPS + age)

traefik/                reverse proxy config
suricata/               IDS config + 12 signatures
crowdsec/               acquis · profiles · scenarios · whitelist
homeassistant/          HA config + ESPHome devices
monitoring/             prometheus + grafana configs
scripts/                decrypt-secrets · update-suricata-rules
```

Individual stacks:

```bash
docker compose -f compose/network.yaml -f compose/security.yaml up -d
docker compose -f compose/network.yaml -f compose/home.yaml up -d
```

---

## IDS/IPS

Suricata monitors `eno1` and `br-homelab`. CrowdSec reads `eve.json` in real time. Two alerts within 60 seconds trigger a 6-hour ban, propagated to OpenWrt at the network edge.

| signature | threshold |
|-----------|-----------|
| icmp echo | info only |
| icmp sweep | 10 / 30s |
| syn scan | 5 / 3s |
| connect scan | 5 / 3s |
| null scan | 3 / 10s |
| fin scan | 3 / 10s |
| xmas scan | 3 / 10s |
| port scan | 10 / 5s |
| udp scan | 5 / 3s |
| ssh brute force | 8 / 30s |
| path traversal | — |
| sql injection | — |

CrowdSec profiles — scenario `homelab/scan-detection`:

| trigger | duration |
|---------|----------|
| first detection | 6 h |
| scan pattern | 24 h |
| repeat (>=3) | 48 h |

```bash
docker exec crowdsec cscli decisions list      # active bans
docker exec kali nmap -sS -p 1-100 <host>     # test
```

---

## Exposed Ports

| port | service | reason |
|------|---------|--------|
| `22` | ssh | admin access |
| `80,443` | traefik | single entry point |
| `2222` | forgejo ssh | git push/pull |
| `6052` | esphome | host network (mDNS) |
| `64738` | mumble | VoIP protocol |
| `8080` | crowdsec lapi | OpenWrt bouncer |

Prometheus bound to `127.0.0.1` only. Zero web apps exposed directly — everything through Traefik.

---

## Security

- all web apps accessible only via Traefik (HA, Grafana, Forgejo)
- prometheus bound to `127.0.0.1` only (internal metrics)
- mariadb isolated on `backend` network
- secrets encrypted with SOPS + age (`.env` gitignored)
- `network_mode: host` only where necessary
- `no-new-privileges:true` on host containers
- healthchecks and resource limits on all containers
- CI: yamllint, compose-validate, trivy config, trivy cve (7 images)

---

## Backup

```bash
tar -czf backup-$(date +%Y%m%d).tar.gz data/
cp ~/.config/sops/age/keys.txt backup-age-key.txt
```

---

## Credits

| project | author |
|---------|--------|
| [EASUN SMG II 11Kw ESPHome](https://github.com/robgt978/Easun-SMG-II-11Kw-esphome-) | robgt978 |
| [Suricata](https://suricata.io/) | OISF |
| [CrowdSec](https://github.com/crowdsecurity/crowdsec) | CrowdSec |
| [Mumble](https://github.com/mumble-voip/mumble) | Mumble VoIP |
| [Traefik](https://github.com/traefik/traefik) | Traefik Labs |
| [Forgejo](https://forgejo.org/) | Forgejo |
| [ESPHome](https://esphome.io/) | ESPHome |
| [Home Assistant](https://www.home-assistant.io/) | Home Assistant |
| [Grafana](https://grafana.com/) | Grafana Labs |
| [Prometheus](https://prometheus.io/) | Prometheus |
| [SOPS](https://github.com/getsops/sops) | Mozilla |
| [age](https://github.com/FiloSottile/age) | Filippo Valsorda |

Feito por [gustavx404](https://github.com/gustavx404).
