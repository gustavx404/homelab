<p align="center">
  <b>homelab</b> &nbsp;·&nbsp; self-hosted infrastructure &nbsp;·&nbsp; docker compose &nbsp;·&nbsp; 11 services
  <br><br>
  <a href="https://github.com/gustavx404/homelab/actions"><img src="https://img.shields.io/github/actions/workflow/status/gustavx404/homelab/ci.yaml?style=flat-square&label=ci&color=10b981" alt="ci"></a>
  <a href="#"><img src="https://img.shields.io/badge/Suricata_8-IDS-10b981?style=flat-square" alt="suricata"></a>
  <a href="#"><img src="https://img.shields.io/badge/CrowdSec-IPS-10b981?style=flat-square" alt="crowdsec"></a>
  <a href="#"><img src="https://img.shields.io/badge/Traefik-v3-10b981?style=flat-square" alt="traefik"></a>
  <a href="#"><img src="https://img.shields.io/badge/secrets-SOPS_+_age-10b981?style=flat-square" alt="sops"></a>
</p>

---

```
                           INTERNET
                              │
                         ┌────┴────┐
                         │ OpenWrt │  edge · CrowdSec bouncer
                         └────┬────┘
                              │  :80 :443
                         ┌────┴──────────────┐
                         │     TRAEFIK v3     │  reverse proxy · TLS
                         │  /       → HA      │
                         │  /grafana → Grafana│
                         │  /git    → Forgejo │
                         └────────┬───────────┘
                                  │  backend (br-homelab)
               ┌────────┬─────────┼────────┬─────────┐
               ▼        ▼         ▼        ▼         ▼
          ┌────────┐┌────────┐┌────────┐┌────────┐┌────────┐
          │mariadb ││grafana ││prometh ││forgejo ││ mumble │
          │ :3306  ││ :3000  ││ :9090  ││ :2222  ││ :64738 │
          └────────┘└────────┘└────────┘└────────┘└────────┘
                                             │
               ┌─────────────┬───────────────┤
               ▼             ▼               ▼
          ┌────────┐   ┌──────────┐   ┌──────────┐
          │suricata│   │ esphome  │   │ crowdsec │
          │ host   │   │ :6052    │   │ :8080    │
          └────────┘   └──────────┘   └──────────┘
```

---

### Quick Start

```bash
# 1. dependencies
sudo apt install -y docker.io docker-compose-v2 age yamllint
curl -LO https://github.com/getsops/sops/releases/download/v3.13.3/sops-v3.13.3.linux.amd64
sudo mv sops-v3.13.3.linux.amd64 /usr/local/bin/sops && sudo chmod +x /usr/local/bin/sops

# 2. age key
age-keygen -o ~/.config/sops/age/keys.txt       # copy public key → .sops.yaml

# 3. secrets
sops compose/sops-secrets.yaml                   # edit with real values

# 4. env
bash scripts/decrypt-secrets.sh                  # generate compose/.env

# 5. deploy
docker compose -f compose/compose.yaml up -d
```

**Access:** `https://<host>/` → HA · `https://<host>/grafana/` → Grafana · `https://<host>/git/` → Forgejo *(self-signed TLS – accept once)*

---

### Services

| stack | service | image | access |
|-------|---------|-------|--------|
| core | **traefik** | `v3.3` | `:80` `:443` — single http/s gateway |
| core | **homeassistant** | `stable` | `/` via traefik — home automation |
| core | **mariadb** | `lts` | internal — HA recorder database |
| core | **esphome** | `stable` | `:6052` host — esp32 firmware · mDNS |
| security | **suricata** | `latest` _(8.0)_ | host — 12 rules · `eno1` + `br-homelab` |
| security | **crowdsec** | `latest` | `:8080` lapi — IPS · openwrt bouncer |
| apps | **forgejo** | `16.0.2` | `/git` (web) `:2222` (ssh) — git server |
| apps | **mumble** | `latest` | `:64738` tcp/udp — ducks voip server |
| apps | **kali** | `rolling` | `docker exec -it kali bash` — pentest |
| monitoring | **prometheus** | `v3.4.0` | `127.0.0.1:9090` — metrics |
| monitoring | **grafana** | `11.6.0` | `/grafana` via traefik — dashboards |

---

### Sources

```
compose/
├── compose.yaml         # master (includes all stacks)
├── network.yaml         # bridge br-homelab + secrets
├── home.yaml            # mariadb · homeassistant · esphome
├── security.yaml        # suricata · crowdsec
├── monitoring.yaml      # prometheus · grafana
├── services.yaml        # traefik · forgejo · mumble · kali
├── .env.example         # template (fake values)
└── sops-secrets.yaml    # encrypted (SOPS + age)

traefik/     dynamic.yml + traefik.yml
suricata/    12 custom IDS signatures
crowdsec/    acquis · profiles · scenarios · whitelist
scripts/     decrypt-secrets · update-suricata-rules
```

```bash
# individual stacks
docker compose -f compose/network.yaml -f compose/security.yaml up -d    # security only
docker compose -f compose/network.yaml -f compose/home.yaml up -d        # home only
docker compose -f compose/network.yaml -f compose/services.yaml up -d    # apps only
```

---

### IDS/IPS

**Suricata** 12 signatures — 2 alerts in 60s = **CrowdSec** auto-ban → **OpenWrt** blocks at edge.

| sid | signature | threshold |
|-----|-----------|-----------|
| `1000010` | syn scan | 5/3s |
| `1000011` | connect scan | 5/3s |
| `1000012` | null scan | 3/10s |
| `1000013` | fin scan | 3/10s |
| `1000014` | xmas scan | 3/10s |
| `1000020` | port scan | 10/5s |
| `1000030` | udp scan | 5/3s |
| `1000040` | ssh brute force | 8/30s |
| `1000050` | path traversal | — |
| `1000051` | sql injection | — |

```bash
docker exec crowdsec cscli decisions list      # active bans
docker exec kali nmap -sS -p 1-100 <host>     # test trigger
```

---

### Exposed ports

| port | service | rationale |
|------|---------|-----------|
| `22` | ssh | admin |
| `80,443` | traefik | http/s gateway |
| `2222` | forgejo ssh | git |
| `6052` | esphome | host network · mDNS |
| `64738` | mumble | voip protocol |
| `8080` | crowdsec lapi | openwrt bouncer |

> Zero web apps exposed directly. All http/s through Traefik.

---

### Security

▸ grafana & prometheus bind `127.0.0.1` only  
▸ mariadb isolated on `backend` network  
▸ SOPS + age encryption · `.env` gitignored  
▸ `network_mode: host` only where necessary  
▸ `no-new-privileges:true` on host-network containers  
▸ healthchecks + resource limits on all containers  
▸ CI: yamllint · compose-validate · trivy config · trivy cve (7 images)

---

### Backup

```bash
tar -czf backup-$(date +%Y%m%d).tar.gz data/
cp ~/.config/sops/age/keys.txt backup-age-key.txt
```

---

<div align="center">

[robgt978/Easun-SMG-II-11Kw-esphome](https://github.com/robgt978/Easun-SMG-II-11Kw-esphome-) ·
[OISF/Suricata](https://suricata.io) ·
[crowdsec](https://github.com/crowdsecurity/crowdsec) ·
[mumble](https://github.com/mumble-voip/mumble)

</div>
