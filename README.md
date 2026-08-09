# homelab

> Infraestrutura Dockerizada com Suricata 8 + CrowdSec, SOPS e 11 servicos em stacks modulares.

[![CI](https://github.com/gustavx404/homelab/actions/workflows/ci.yaml/badge.svg)](https://github.com/gustavx404/homelab/actions/workflows/ci.yaml)

---

## Arquitetura

```
Internet
   │
   ▼
┌─────────────────────────────────────────────────────────┐
│  Caddy :80/:443 (reverse proxy + TLS)                   │
│  / → Home Assistant   /grafana → Grafana   /git → Forgejo│
└─────────────────────────────────────────────────────────┘
   │
   ▼  backend (bridge network)
┌──────────┬──────────┬──────────┬──────────┬──────────────┐
│ mariadb  │ grafana  │prometheus│ forgejo  │  mumble      │
│ (HA DB)  │ :3000    │ :9090    │ :3001/22 │  :64738      │
└──────────┴──────────┴──────────┴──────────┴──────────────┘
   │
   ▼  host network (seguranca/dispositivos)
┌──────────────┬──────────┬──────────────────┐
│  suricata 8  │ esphome  │  homeassistant   │
│  + crowdsec  │ :6052    │  :8123           │
│  IDS/IPS     │          │                  │
└──────────────┴──────────┴──────────────────┘
```

---

## Stack

| Servico | Imagem | Porta | Funcao |
|---------|--------|-------|--------|
| **Home Assistant** | `home-assistant:stable` | `8123` | Automacao residencial |
| **MariaDB** | `mariadb:lts` | interno | Recorder HA |
| **ESPHome** | `esphome:stable` | `6052` | Firmware ESP32 |
| **Suricata 8** | `jasonish/suricata:latest` | host | IDS/IPS (12 regras) |
| **CrowdSec** | `crowdsecurity/crowdsec:latest` | host | IPS — bloqueia IPs maliciosos |
| **Mumble** | `mumblevoip/mumble-server` | `64738` | VoIP (Ducks Server) |
| **Kali Linux** | `kalilinux/kali-rolling` | CLI | Pentest, CTF |
| **Caddy** | `caddy:2-alpine` | `80/443` | Reverse proxy + TLS |
| **Forgejo** | `forgejo:16.0.2` | `3001/2222` | Git self-hosted |
| **Prometheus** | `prom/prometheus:v3.4.0` | `9090` | Metricas |
| **Grafana** | `grafana/grafana:11.6.0` | `3000` | Dashboards |

---

## Estrutura (stacks modulares)

```
compose/
├── compose.yaml        # Master (include todos os stacks)
├── network.yaml        # Redes + secrets compartilhados
├── home.yaml           # mariadb, homeassistant, esphome
├── security.yaml       # suricata, crowdsec
├── monitoring.yaml     # prometheus, grafana
├── services.yaml       # caddy, forgejo, mumble, kali
├── .env.example        # Template de variaveis
└── sops-secrets.yaml   # Secrets encriptados (SOPS + age)

suricata/               # Config IDS/IPS + regras
crowdsec/               # Config CrowdSec (acquis, profiles)
homeassistant/          # HA config + ESPHome
caddy/                  # Caddyfile
monitoring/             # Prometheus + Grafana configs
scripts/                # decrypt-secrets, update-suricata-rules
```

### Gerenciar stacks individualmente

```bash
# Stack completo
docker compose -f compose/compose.yaml up -d

# Apenas home
docker compose -f compose/network.yaml -f compose/home.yaml up -d

# Apenas seguranca
docker compose -f compose/network.yaml -f compose/security.yaml up -d

# Apenas servicos
docker compose -f compose/network.yaml -f compose/services.yaml up -d
```

---

## Quick Start

```bash
# 1. Dependencias
sudo apt install -y docker.io docker-compose-v2 age yamllint
curl -LO https://github.com/getsops/sops/releases/download/v3.13.3/sops-v3.13.3.linux.amd64
sudo mv sops-v3.13.3.linux.amd64 /usr/local/bin/sops && sudo chmod +x /usr/local/bin/sops

# 2. Gerar chave age
age-keygen -o ~/.config/sops/age/keys.txt
# Copie a public key para .sops.yaml

# 3. Editar secrets
sops compose/sops-secrets.yaml

# 4. Gerar .env
bash scripts/decrypt-secrets.sh

# 5. Subir tudo
docker compose -f compose/compose.yaml up -d
```

---

## Suricata 8 + CrowdSec

### Suricata (deteccao)

12 regras ativas monitorando `eno1` + Docker bridge:

| SID | Tipo | Detecta |
|-----|------|---------|
| 1000010 | SYN scan | `nmap -sS` (5 pacotes em 3s) |
| 1000011 | connect() scan | `nmap -sT` |
| 1000012 | NULL scan | `nmap -sN` |
| 1000013 | FIN scan | `nmap -sF` |
| 1000014 | XMAS scan | `nmap -sX` |
| 1000020 | Port scan | 10+ portas em 5s |
| 1000030 | UDP scan | `nmap -sU` |
| 1000040 | SSH brute force | 8+ conexoes em 30s |
| 1000050 | Path traversal | `../` em URL |
| 1000051 | SQL injection | `union select` em URL |

### CrowdSec (prevencao)

CrowdSec le os alerts do Suricata via `eve.json` e bloqueia IPs maliciosos automaticamente:

- **Bans padrao**: 4 horas
- **Scans agressivos**: 24 horas
- Colecao: `crowdsecurity/suricata`

```bash
# Ver decisoes ativas
docker exec crowdsec cscli decisions list

# Ver metricas
docker exec crowdsec cscli metrics
```

### Testar

```bash
# Gerar scan de teste (Kali)
docker exec kali nmap -sS -p 1-20 192.168.20.189

# Ver alerts Suricata
docker exec suricata cat /var/log/suricata/fast.log | tail -5

# Ver bans CrowdSec
docker exec crowdsec cscli decisions list
```

---

## Seguranca

- Prometheus, Grafana bindam apenas em `127.0.0.1`
- MariaDB acessivel somente na rede `backend`
- Secrets encriptados com SOPS + age
- `.env` gitignored
- `network_mode: host` so onde necessario (Suricata, CrowdSec, ESPHome)
- Healthchecks em todos os containers
- Resource limits (memoria) definidos
- `no-new-privileges:true` em containers com host network
- CI Trivy scan em 7 imagens

---

## Backup

```bash
tar -czf backup-$(date +%Y%m%d).tar.gz data/
cp ~/.config/sops/age/keys.txt backup-age-key.txt  # CRITICO
```

---

## Creditos

- **EASUN SMG II 11Kw ESPHome** — [robgt978/easun-smg-ii-11kw-esphome](https://github.com/robgt978/Easun-SMG-II-11Kw-esphome-)
- **Suricata** — [OISF/Suricata](https://suricata.io/)
- **CrowdSec** — [crowdsecurity/crowdsec](https://github.com/crowdsecurity/crowdsec)
- **Mumble** — [mumblevoip/mumble-server](https://github.com/mumble-voip/mumble)

---

## CI/CD

| Job | Funcao |
|-----|--------|
| `yamllint` | Valida YAML em compose/ homeassistant/ suricata/ monitoring/ crowdsec/ |
| `compose-validate` | `docker compose config --quiet` (todos os stacks) |
| `config-scan` | Trivy misconfiguration scan |
| `image-scan` | Trivy CVE scan em 7 imagens (matrix) |
