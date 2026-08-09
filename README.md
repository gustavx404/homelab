<p align="center">
  <br>
  <samp>homelab</samp>
  <br><br>
  Self-hosted infrastructure. Docker Compose. 11 services. Zero-trust networking.
  <br><br>
  <a href="https://github.com/gustavx404/homelab/actions"><img src="https://img.shields.io/badge/build-passing-10b981?style=flat-square" alt="build"></a>
  <a href="#"><img src="https://img.shields.io/badge/suricata-8-6b7280?style=flat-square" alt="suricata"></a>
  <a href="#"><img src="https://img.shields.io/badge/crowdsec-ips-6b7280?style=flat-square" alt="crowdsec"></a>
  <a href="#"><img src="https://img.shields.io/badge/secrets-sops-6b7280?style=flat-square" alt="sops"></a>
  <br><br>
</p>

---

```
                          Internet
                             │
                        ┌────┴────┐
                        │ OpenWrt │  edge router + CrowdSec bouncer
                        └────┬────┘
                             │  80 · 443
                        ┌────┴──────────────┐
                        │     Traefik v3     │  reverse proxy
                        │                    │
                        │  /          HA     │
                        │  /grafana   Grafana│
                        │  /git       Forgejo│
                        └────────┬───────────┘
                                 │  backend network
              ┌────────┬─────────┼────────┬─────────┐
              ▼        ▼         ▼        ▼         ▼
          ┌───────┐┌───────┐┌────────┐┌───────┐┌───────┐
          │mariadb││grafana││prometh.││forgejo││mumble │
          └───────┘└───────┘└────────┘└───────┘└───────┘
                                            │
              ┌─────────────┬───────────────┤
              ▼             ▼               ▼
         ┌────────┐   ┌──────────┐   ┌──────────┐
         │suricata│   │ esphome  │   │ crowdsec │
         │  host  │   │  host    │   │  lapi    │
         └────────┘   └──────────┘   └──────────┘
```

---

### Quick Start

```bash
# dependencies
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh ./get-docker.sh
sudo apt install -y docker-compose-v2 age yamllint
curl -LO https://github.com/getsops/sops/releases/download/v3.13.3/sops-v3.13.3.linux.amd64
sudo mv sops-v3.13.3.linux.amd64 /usr/local/bin/sops && sudo chmod +x /usr/local/bin/sops

# age key → copy public key into .sops.yaml
age-keygen -o ~/.config/sops/age/keys.txt

# edit secrets with real values
sops compose/sops-secrets.yaml

# generate .env from encrypted secrets
bash scripts/decrypt-secrets.sh

# deploy everything
docker compose -f compose/compose.yaml up -d
```

Access via any IP — path-based routing, no DNS needed.

| path | service |
|------|---------|
| `/` | Home Assistant |
| `/grafana/` | Grafana |
| `/git/` | Forgejo |

---

### Services

| stack | service | image | port |
|-------|---------|-------|------|
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
├── compose.yaml        master (include all)
├── network.yaml        bridge + secrets
├── home.yaml           mariadb · ha · esphome
├── security.yaml       suricata · crowdsec
├── monitoring.yaml     prometheus · grafana
├── services.yaml       traefik · forgejo · mumble · kali
├── .env.example        template
└── sops-secrets.yaml   encrypted

traefik/                dynamic.yml
suricata/               12 IDS signatures
crowdsec/               acquis · profiles · scenarios
scripts/                decrypt · update-rules
```

```bash
docker compose -f compose/network.yaml -f compose/security.yaml up -d
docker compose -f compose/network.yaml -f compose/home.yaml up -d
```

---

### IDS / IPS

Suricata monitors `eno1` + `br-homelab`. CrowdSec reads `eve.json` in real time. 2 alerts in 60 seconds triggers a 6-hour ban propagated to OpenWrt at the network edge.

| signature | threshold |
|-----------|-----------|
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

```bash
docker exec crowdsec cscli decisions list
docker exec kali nmap -sS -p 1-100 <host>
```

---

### Exposed Ports

| port | service | reason |
|------|---------|--------|
| `22` | ssh | admin access |
| `80,443` | traefik | single http/s entry point |
| `2222` | forgejo ssh | git push/pull |
| `6052` | esphome | host network · mDNS |
| `64738` | mumble | voip protocol |
| `8080` | crowdsec lapi | openwrt bouncer api |

Zero web apps exposed directly. Everything through Traefik.

---

### Security

grafana & prometheus bind `127.0.0.1` only · mariadb isolated on `backend` network · SOPS + age encryption · `.env` gitignored · `network_mode: host` only where necessary · `no-new-privileges:true` on host containers · healthchecks + resource limits on all 11 containers · CI yamllint + compose-validate + trivy config + trivy cve

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
