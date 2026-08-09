<p align="center">
  <br>
  <samp>homelab</samp>
  <br><br>
  Self-hosted infrastructure on Docker Compose. 11 services. Zero-trust networking. Edge IDS/IPS.
  <br><br>
  <img src="https://img.shields.io/badge/CI-passing-10b981?style=flat-square" alt="ci">
  <img src="https://img.shields.io/badge/services-11-3b82f6?style=flat-square" alt="services">
  <img src="https://img.shields.io/badge/suricata-8-6b7280?style=flat-square" alt="suricata">
  <img src="https://img.shields.io/badge/secrets-sops-6b7280?style=flat-square" alt="secrets">
  <br><br>
</p>

---

```
                         Internet
                            │
                   ┌────────┴────────┐
                   │     OpenWrt      │  edge router + CrowdSec bouncer
                   └────────┬────────┘
                            │  80 · 443
                   ┌────────┴────────┐
                   │    Traefik v3   │  reverse proxy · path-based routing
                   │  /         HA   │
                   │  /grafana  Grafana
                   │  /git      Forgejo
                   └────────┬────────┘
                            │  backend · br-homelab
   ┌─────────┬────────┬─────┴─────┬────────┬─────────┐
   ▼         ▼        ▼           ▼        ▼         ▼
 mariadb   grafana  prometheus  forgejo  mumble   crowdsec
   └────────┴────────┴─────┬─────┴────────┴────│─────┘
                     host network              ▼
               suricata (eno1)   esphome    LAPI :8080
               + br-homelab      :6052      (→ OpenWrt)
```

---

### Quick Start

```bash
# dependencies
curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh ./get-docker.sh
sudo apt install -y docker-compose-v2 age yamllint
curl -LO https://github.com/getsops/sops/releases/download/v3.13.3/sops-v3.13.3.linux.amd64
sudo install -m 755 sops-v3.13.3.linux.amd64 /usr/local/bin/sops

# generate age key → copy public key into .sops.yaml
age-keygen -o ~/.config/sops/age/keys.txt

# edit secrets with real values
sops compose/sops-secrets.yaml

# decrypt → compose/.env
bash scripts/decrypt-secrets.sh

# deploy all stacks
docker compose -f compose/compose.yaml up -d
```

**Access** — path-based routing, works with any IP. No DNS needed.

| path | service |
|------|---------|
| `/` | Home Assistant |
| `/grafana/` | Grafana |
| `/git/` | Forgejo |

---

### Services

| stack | service | image | access |
|-------|---------|-------|--------|
| core | traefik | `v3.3` | `80,443` |
| core | homeassistant | `stable` | internal |
| core | mariadb | `lts` | internal |
| core | esphome | `stable` | `6052` host |
| security | suricata | `latest` | host |
| security | crowdsec | `latest` | `8080` lapi |
| apps | forgejo | `16.0.2` | `2222` ssh |
| apps | mumble | `latest` | `64738` tcp/udp |
| apps | kali | `rolling` | cli |
| monitoring | prometheus | `v3.4.0` | `127.0.0.1:9090` |
| monitoring | grafana | `11.6.0` | internal |

---

### Sources

```
compose/
├── compose.yaml        master (includes all stacks)
├── network.yaml        bridge br-homelab + secrets
├── home.yaml           mariadb · homeassistant · esphome
├── security.yaml       suricata · crowdsec
├── monitoring.yaml     prometheus · grafana
├── services.yaml       traefik · forgejo · mumble · kali
├── .env.example        template
└── sops-secrets.yaml   encrypted (SOPS + age)

traefik/                traefik.yml + dynamic.yml
suricata/               config + 12 IDS signatures
crowdsec/               acquis · profiles · scenarios · whitelist
homeassistant/          HA config + ESPHome devices
monitoring/             prometheus + grafana configs
scripts/                decrypt-secrets · update-suricata-rules
data/                   persisted volumes (gitignored)
```

Individual stacks:

```bash
docker compose -f compose/network.yaml -f compose/security.yaml up -d
docker compose -f compose/network.yaml -f compose/home.yaml up -d
```

---

### IDS / IPS

Suricata monitors `eno1` + `br-homelab`. CrowdSec reads `eve.json` in real time. 2 alerts in 60s triggers a ban propagated to OpenWrt at the network edge.

| signature | threshold |
|-----------|-----------|
| icmp echo | — (info) |
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

**CrowdSec profiles** — scenario `homelab/scan-detection`:

| trigger | ban duration |
|---------|-------------|
| first detection | 6 h |
| scan pattern | 24 h |
| repeat (≥3 events) | 48 h |

```bash
docker exec crowdsec cscli decisions list      # active bans
docker exec kali nmap -sS -p 1-100 <host>     # test trigger
```

---

### Exposed Ports

| port | service | reason |
|------|---------|--------|
| `22` | ssh | admin access |
| `80,443` | traefik | http/s gateway |
| `2222` | forgejo ssh | git push/pull |
| `6052` | esphome | host network · mDNS |
| `64738` | mumble | voip protocol |
| `8080` | crowdsec lapi | openwrt bouncer |

Prometheus and Grafana bind `127.0.0.1` only. Zero web apps exposed directly.

---

### Security

grafana & prometheus bind `127.0.0.1` · mariadb isolated on `backend` network · SOPS + age encryption · `.env` gitignored · `network_mode: host` only where necessary · `no-new-privileges:true` on host containers · healthchecks + resource limits on all 11 containers · CI yamllint + compose-validate + trivy config + trivy cve

---

### Backup

```bash
tar -czf backup-$(date +%Y%m%d).tar.gz data/
cp ~/.config/sops/age/keys.txt backup-age-key.txt
```

---

<p align="center">
  <sub>
    <a href="https://github.com/robgt978/Easun-SMG-II-11Kw-esphome-">EASUN ESPHome</a> ·
    <a href="https://suricata.io">Suricata</a> ·
    <a href="https://github.com/crowdsecurity/crowdsec">CrowdSec</a> ·
    <a href="https://github.com/mumble-voip/mumble">Mumble</a>
  </sub>
</p>
