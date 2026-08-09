<div align="center">

```
   ▄█    █▀▀▀▀   █▀▄▀█   ▄▀▀▀▀▄   █     ▄▀▀▀▀▄   ██▄
   ██    ██▄▄▄   █ █ █   ██        █     ██        █▀██
   ██    ██      █ ▀ █   ██▀▀▀▀   █     ██▀▀▀▀   █  ██
   ▐██▄  ▀▀▀▀▀   ▀   ▀   ▀▀▀▀▀   ▀▀▀▀  ▀▀▀▀▀   ▀▀▀▀
```

**self-hosted infrastructure · docker compose · modular stacks · zero-trust**

[![CI](https://img.shields.io/github/actions/workflow/status/gustavx404/homelab/ci.yaml?style=flat-square&label=build&color=10b981)](https://github.com/gustavx404/homelab/actions)
[![services](https://img.shields.io/badge/11_services-10b981?style=flat-square)](.)
[![suricata](https://img.shields.io/badge/Suricata_8-CrowdSec_IPS-10b981?style=flat-square)](.)
[![proxy](https://img.shields.io/badge/proxy-Traefik_v3-10b981?style=flat-square)](.)
[![secrets](https://img.shields.io/badge/secrets-SOPS_+_age-10b981?style=flat-square)](.)

</div>

---

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          NETWORK MAP                                    │
│                                                                         │
│   INTERNET                                                              │
│      │                                                                  │
│      ▼                                                                  │
│   ┌──────────┐                                                          │
│   │ OpenWrt  │ ← edge router + CrowdSec bouncer                         │
│   └────┬─────┘                                                          │
│        │                                                                │
│        ▼  :80 :443                                                      │
│   ┌─────────────────────────────────────────┐                           │
│   │              TRAEFIK v3                 │                           │
│   │         reverse proxy + TLS             │                           │
│   │                                         │                           │
│   │  /          → Home Assistant            │                           │
│   │  /grafana   → Grafana                   │                           │
│   │  /git       → Forgejo                   │                           │
│   └─────────────────┬───────────────────────┘                           │
│                     │                                                   │
│      ┌──────────────┼──────────────┬──────────────┐                     │
│      ▼              ▼              ▼              ▼                     │
│   ┌──────┐    ┌──────────┐  ┌──────────┐  ┌──────────┐                 │
│   │mariad│    │ grafana  │  │prometheus│  │ forgejo  │                 │
│   │b     │    │  :3000   │  │  :9090   │  │ :2222    │                 │
│   └──────┘    └──────────┘  └──────────┘  └──────────┘                 │
│                                                                         │
│      ┌──────────────┬──────────────┬──────────────┐                     │
│      ▼              ▼              ▼              ▼                     │
│   ┌──────┐    ┌──────────┐  ┌──────────┐  ┌──────────┐                 │
│   │mumble│    │  kali    │  │ suricata │  │ crowsec  │                 │
│   │:64738│    │  (cli)   │  │  IDS/IPS │  │  :8080   │                 │
│   └──────┘    └──────────┘  └──────────┘  └──────────┘                 │
│                                                                         │
│   ▸ backend network: br-homelab                                         │
│   ▸ host network: suricata, esphome, crowdsec                           │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## `$ docker compose up -d`

```bash
# 1 · dependencies
sudo apt install -y docker.io docker-compose-v2 age yamllint
curl -LO https://github.com/getsops/sops/releases/download/v3.13.3/sops-v3.13.3.linux.amd64
sudo mv sops-v3.13.3.linux.amd64 /usr/local/bin/sops && sudo chmod +x /usr/local/bin/sops

# 2 · generate age key
age-keygen -o ~/.config/sops/age/keys.txt
# → copy public key into .sops.yaml

# 3 · edit secrets
sops compose/sops-secrets.yaml

# 4 · decrypt → .env
bash scripts/decrypt-secrets.sh

# 5 · deploy all stacks
docker compose -f compose/compose.yaml up -d
```

---

## `~$ cat /etc/services`

### `▸ core`

| service | image | port | notes |
|----------|-------|------|-------|
| **traefik** | `v3.3` | `80,443` | reverse proxy — single entry point for all HTTP/S |
| **homeassistant** | `stable` | `8123` (internal) | home automation — accessed via `/` |
| **mariadb** | `lts` | `3306` (internal) | recorder database for Home Assistant |
| **esphome** | `stable` | `6052` (host) | ESP32 firmware builder — mDNS discovery |

### `▸ security`

| service | image | port | notes |
|----------|-------|------|-------|
| **suricata** | `latest` _(8.0.6)_ | host | IDS — 12 rules, monitors `eno1` + `br-homelab` |
| **crowdsec** | `latest` | `8080` | IPS — reads `eve.json`, bans via OpenWrt bouncer |

### `▸ apps`

| service | image | port | notes |
|----------|-------|------|-------|
| **forgejo** | `16.0.2` | `2222` (SSH) | git server — web at `/git` via Traefik |
| **mumble** | `latest` | `64738` tcp/udp | voip — ducks server |
| **kali** | `rolling` | cli | pentest — `docker exec -it kali bash` |

### `▸ monitoring`

| service | image | port | notes |
|----------|-------|------|-------|
| **prometheus** | `v3.4.0` | `9090` (localhost) | metrics collection |
| **grafana** | `11.6.0` | `3000` | dashboards — `/grafana` via Traefik |

---

## `$ curl -k https://<host>/`

```
/          → Home Assistant
/grafana/  → Grafana
/git/      → Forgejo
```

> self-signed tls · accept on first visit · path-based routing works with any ip

---

## `$ tree compose/`

```
compose/
├── compose.yaml         # master (includes all)
├── network.yaml         # bridge + secrets
├── home.yaml            # mariadb · homeassistant · esphome
├── security.yaml        # suricata · crowdsec
├── monitoring.yaml      # prometheus · grafana
├── services.yaml        # traefik · forgejo · mumble · kali
├── .env.example         # template
└── sops-secrets.yaml    # encrypted (SOPS + age)

traefik/     reverse proxy rules (dynamic.yml)
suricata/    IDS/IPS config + 12 custom signatures
crowdsec/    IPS config (acquis · profiles · scenarios · whitelist)
scripts/     decrypt-secrets · update-suricata-rules
```

---

## `$ suricata --detect`

| sid | signature | threshold |
|-----|-----------|-----------|
| `1000010` | syn scan | 5 pkts / 3s |
| `1000011` | connect() scan | 5 conns / 3s |
| `1000012` | null scan | 3 pkts / 10s |
| `1000013` | fin scan | 3 pkts / 10s |
| `1000014` | xmas scan | 3 pkts / 10s |
| `1000020` | port scan | 10 ports / 5s |
| `1000030` | udp scan | 5 pkts / 3s · excl dns |
| `1000040` | ssh brute force | 8 conns / 30s |
| `1000050` | path traversal | `../` in url |
| `1000051` | sql injection | `union select` |

**crowdsec** reads `eve.json` in real-time · 2 alerts in 60s → 6h ban → OpenWrt blocks at edge

```bash
docker exec crowdsec cscli decisions list     # active bans
docker exec kali nmap -sS -p 1-100 <host>    # test trigger
```

---

## `$ ss -tlnp | grep -v 127.`

| port | service | why exposed |
|------|---------|-------------|
| `22` | ssh | admin access |
| `80,443` | traefik | single http/s gateway |
| `2222` | forgejo ssh | git push/pull |
| `6052` | esphome | host network (mdns) · auth required |
| `64738` | mumble | native voip protocol |
| `8080` | crowdsec lapi | authenticated api for openwrt bouncer |

> **zero web apps exposed directly** · all http/s through traefik

---

## `$ security --audit`

```
▸ grafana & prometheus bind 127.0.0.1 only
▸ mariadb isolated on backend network
▸ secrets encrypted with SOPS + age (.env gitignored)
▸ network_mode: host only where necessary
▸ no-new-privileges:true on host-network containers
▸ healthchecks + resource limits on all 11 containers
▸ ci: yamllint + compose-validate + trivy config + trivy cve (7 images)
```

---

## `$ backup --all`

```bash
tar -czf backup-$(date +%Y%m%d).tar.gz data/
cp ~/.config/sops/age/keys.txt backup-age-key.txt   # ⚠ critical
```

---

## `# ./stack --manager`

```bash
docker compose -f compose/compose.yaml up -d                                    # all
docker compose -f compose/network.yaml -f compose/security.yaml up -d           # security only
docker compose -f compose/network.yaml -f compose/home.yaml up -d               # home only
```

---

<div align="center">

**[robgt978/Easun-SMG-II-11Kw-esphome](https://github.com/robgt978/Easun-SMG-II-11Kw-esphome-)** · **[OISF/Suricata](https://suricata.io)** · **[crowdsec](https://github.com/crowdsecurity/crowdsec)** · **[mumble](https://github.com/mumble-voip/mumble)**

</div>
