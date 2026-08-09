<p align="center">
  <img src="https://img.shields.io/github/actions/workflow/status/gustavx404/homelab/ci.yaml?branch=master&label=CI&style=flat-square" alt="CI">
  <img src="https://img.shields.io/badge/services-11-blue?style=flat-square" alt="Services">
  <img src="https://img.shields.io/badge/security-Suricata%208%20%2B%20CrowdSec-green?style=flat-square" alt="Security">
  <img src="https://img.shields.io/badge/proxy-Traefik%20v3-blueviolet?style=flat-square" alt="Proxy">
  <img src="https://img.shields.io/badge/secrets-SOPS%20%2B%20age-black?style=flat-square" alt="Secrets">
</p>

<h1 align="center">homelab</h1>

<p align="center">Self-hosted infrastructure — Docker Compose, modular stacks, zero-trust networking.</p>

---

### Architecture

```
  Internet ──► OpenWrt (borda + CrowdSec bouncer)
                   │
                   ▼  :80 :443
              ┌─────────────┐
              │   Traefik    │  reverse proxy + TLS
              │  /           │  ──► Home Assistant
              │  /grafana    │  ──► Grafana
              │  /git        │  ──► Forgejo
              └──────┬───────┘
                     │  backend (br-homelab)
       ┌─────────────┼─────────────┬──────────────┐
       ▼             ▼             ▼              ▼
   ┌───────┐   ┌──────────┐  ┌──────────┐  ┌─────────┐
   │mariadb│   │ grafana  │  │prometheus│  │ forgejo │
   │  :3306│   │  :3000   │  │  :9090   │  │ :2222   │
   └───────┘   └──────────┘  └──────────┘  └─────────┘
       │
       ▼  host network
   ┌──────────┬──────────┬──────────┐
   │ suricata │ esphome  │ crowdsec │
   │  IDS/IPS │  :6052   │  :8080   │
   └──────────┴──────────┴──────────┘
```

### Services

<table>
<tr>
<td width="50%">

#### Core
| Service | Image | Access |
|---------|-------|--------|
| **Traefik** | `v3.3` | `:80` `:443` |
| **Home Assistant** | `stable` | `/` (proxy) |
| **MariaDB** | `lts` | `:3306` (internal) |
| **ESPHome** | `stable` | `:6052` (host) |

#### Security
| Service | Image | Access |
|---------|-------|--------|
| **Suricata 8** | `latest` | host (eno1 + br-homelab) |
| **CrowdSec** | `latest` | `:8080` (LAPI) |

</td>
<td width="50%">

#### Apps
| Service | Image | Access |
|---------|-------|--------|
| **Forgejo** | `16.0.2` | `/git` (web) `:2222` (SSH) |
| **Mumble** | `latest` | `:64738` TCP+UDP |
| **Kali** | `rolling` | `docker exec` CLI |

#### Monitoring
| Service | Image | Access |
|---------|-------|--------|
| **Prometheus** | `v3.4.0` | `127.0.0.1:9090` |
| **Grafana** | `11.6.0` | `/grafana` (proxy) |

</td>
</tr>
</table>

### Quick Start

```bash
# 1. Dependencies
sudo apt install -y docker.io docker-compose-v2 age yamllint
curl -LO https://github.com/getsops/sops/releases/download/v3.13.3/sops-v3.13.3.linux.amd64
sudo mv sops-v3.13.3.linux.amd64 /usr/local/bin/sops && sudo chmod +x /usr/local/bin/sops

# 2. Generate age key
age-keygen -o ~/.config/sops/age/keys.txt
# Copy public key into .sops.yaml

# 3. Edit secrets
sops compose/sops-secrets.yaml

# 4. Generate .env
bash scripts/decrypt-secrets.sh

# 5. Deploy
docker compose -f compose/compose.yaml up -d
```

### Access

Path-based routing — works with any IP, zero DNS dependency:

| URL | Destination |
|-----|-------------|
| `https://<host>/` | Home Assistant |
| `https://<host>/grafana/` | Grafana |
| `https://<host>/git/` | Forgejo |

> Self-signed certificate — accept on first visit.

### Stack Layout

```
compose/
├── compose.yaml          # master (includes all stacks)
├── network.yaml          # shared network + secrets
├── home.yaml             # mariadb, homeassistant, esphome
├── security.yaml         # suricata, crowdsec
├── monitoring.yaml       # prometheus, grafana
├── services.yaml         # traefik, forgejo, mumble, kali
├── .env.example          # template (fake values)
└── sops-secrets.yaml     # encrypted secrets (SOPS + age)

traefik/                  # dynamic.yml + traefik.yml
suricata/                 # IDS/IPS config + 12 custom rules
crowdsec/                 # IPS config (acquis, profiles, scenarios)
homeassistant/            # HA config + ESPHome devices
monitoring/               # Prometheus + Grafana configs
scripts/                  # decrypt-secrets, update-suricata-rules
```

Run individual stacks:

```bash
docker compose -f compose/network.yaml -f compose/security.yaml up -d   # security only
docker compose -f compose/network.yaml -f compose/home.yaml up -d       # home only
```

### IDS/IPS — Suricata 8 + CrowdSec

**12 active rules** monitoring `eno1` + `br-homelab`:

| Rule | Detects | Threshold |
|------|---------|-----------|
| `SYN scan` | `nmap -sS` | 5 pkts / 3s |
| `connect() scan` | `nmap -sT` | 5 conns / 3s |
| `NULL scan` | `nmap -sN` | 3 pkts / 10s |
| `FIN scan` | `nmap -sF` | 3 pkts / 10s |
| `XMAS scan` | `nmap -sX` | 3 pkts / 10s |
| `Port scan` | aggressive probing | 10 ports / 5s |
| `UDP scan` | `nmap -sU` (excl. DNS) | 5 pkts / 3s |
| `SSH brute force` | repeated auth | 8 conns / 30s |
| `Path traversal` | `../` in URL | — |
| `SQL injection` | `union select` | — |

**CrowdSec IPS** reads `eve.json` in real time — 2 alerts in 60s triggers a 6h ban propagated to OpenWrt at the edge.

```bash
docker exec crowdsec cscli decisions list     # active bans
docker exec crowdsec cscli alerts list        # recent alerts
docker exec kali nmap -sS -p 1-100 <host>    # test a scan
```

### Port Audit

| Port | Service | Rationale |
|------|---------|-----------|
| `80,443` | Traefik | single HTTP/S entry point |
| `22` | SSH | admin access |
| `2222` | Forgejo SSH | git push/pull |
| `6052` | ESPHome | host network (mDNS) — auth required |
| `64738` | Mumble | native VoIP protocol |
| `8080` | CrowdSec LAPI | authenticated API for OpenWrt bouncer |

### Security

- **Zero web ports exposed** — everything through Traefik
- Grafana & Prometheus bind `127.0.0.1` only
- MariaDB isolated on `backend` network
- Secrets encrypted with SOPS + age (`.env` gitignored)
- `network_mode: host` only where necessary (Suricata, ESPHome)
- `no-new-privileges:true` on host-network containers
- Healthchecks + resource limits on all 11 containers
- CI Trivy vulnerability scan across all images

### Backup

```bash
tar -czf backup-$(date +%Y%m%d).tar.gz data/
cp ~/.config/sops/age/keys.txt backup-age-key.txt   # critical — lose this, lose access to secrets
```

### Credits

- [robgt978/Easun-SMG-II-11Kw-esphome](https://github.com/robgt978/Easun-SMG-II-11Kw-esphome-) — inverter integration
- [OISF/Suricata](https://suricata.io/) — network IDS/IPS engine
- [crowdsecurity/crowdsec](https://github.com/crowdsecurity/crowdsec) — behavior-based IPS
- [mumblevoip/mumble-server](https://github.com/mumble-voip/mumble) — VoIP server

### CI/CD

| Job | Purpose |
|-----|---------|
| `yamllint` | YAML syntax validation (compose, suricata, crowdsec, traefik) |
| `compose-validate` | `docker compose config --quiet` |
| `config-scan` | Trivy misconfiguration check |
| `image-scan` | Trivy CVE scan — 7 images (matrix) |
