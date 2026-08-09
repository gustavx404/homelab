# homelab

> Infraestrutura Dockerizada — 11 servicos, Suricata 8 + CrowdSec IPS, Traefik reverse proxy.

[![CI](https://github.com/gustavx404/homelab/actions/workflows/ci.yaml/badge.svg)](https://github.com/gustavx404/homelab/actions/workflows/ci.yaml)

---

## Arquitetura

```
Internet
   │
   ▼ OpenWrt (borda — CrowdSec bouncer)
   │
   ▼
┌──────────────────────────────────────────────────────────────────┐
│  Traefik :80/:443 (reverse proxy + TLS, path-based routing)      │
│  / → Home Assistant   /grafana → Grafana   /git → Forgejo        │
└──────────────────────────────────────────────────────────────────┘
   │
   ▼  backend (bridge br-homelab)
┌──────────┬──────────┬──────────┬──────────┬──────────┐
│ mariadb  │ grafana  │prometheus│ forgejo  │  mumble  │
│ (HA DB)  │ (int)    │ (int)    │ (int)    │ :64738   │
└──────────┴──────────┴──────────┴──────────┴──────────┘
   │
   ▼  host network (seguranca / dispositivos)
┌──────────────┬──────────┬──────────────┐
│  suricata 8  │ esphome  │  crowdsec    │
│  + crowdsec  │ :6052    │  LAPI :8080  │
└──────────────┴──────────┴──────────────┘
```

---

## Stack

| Servico | Imagem | Exposicao | Motivo |
|---------|--------|-----------|--------|
| **Traefik** | `traefik:v3.3` | `:80`, `:443` | Reverse proxy (unica entrada HTTP/S) |
| **Home Assistant** | `home-assistant:stable` | interno | So via Traefik |
| **MariaDB** | `mariadb:lts` | interno | Rede backend |
| **ESPHome** | `esphome:stable` | `:6052` host | mDNS/device discovery |
| **Suricata 8** | `jasonish/suricata:latest` | host | Captura de pacotes (eno1 + br-homelab) |
| **CrowdSec** | `crowdsecurity/crowdsec:latest` | `:8080` LAN | LAPI para OpenWrt bouncer |
| **Mumble** | `mumblevoip/mumble-server` | `:64738` TCP/UDP | Protocolo proprio (VoIP) |
| **Forgejo** | `forgejo:16.0.2` | `:2222` (SSH) | Git SSH (web via Traefik) |
| **Kali Linux** | `kalilinux/kali-rolling` | CLI | `docker exec -it kali bash` |
| **Prometheus** | `prom/prometheus:v3.4.0` | `127.0.0.1:9090` | Metricas internas |
| **Grafana** | `grafana/grafana:11.6.0` | `127.0.0.1:3000` | Via Traefik |

---

## Auditoria de portas expostas

| Porta | Servico | Justificativa |
|-------|---------|---------------|
| `80, 443` | Traefik | Unico proxy de entrada |
| `22` | Host SSH | Acesso administrativo |
| `2222` | Forgejo SSH | Git push/pull |
| `6052` | ESPHome | `network_mode: host` (mDNS) — dashboard com auth |
| `64738` | Mumble | Protocolo VoIP proprio (TCP+UDP) |
| `8080` | CrowdSec LAPI | API autenticada para OpenWrt bouncer |

**Nenhum app web exposto diretamente.** Tudo passa pelo Traefik.

---

## Acesso

Path-based routing — funciona com qualquer IP ou hostname, sem dependencia de DNS:

| URL | Servico |
|-----|---------|
| `https://<host-ip>/` | Home Assistant |
| `https://<host-ip>/grafana/` | Grafana |
| `https://<host-ip>/git/` | Forgejo |

Exemplo: `https://192.168.20.189/`, `https://192.168.20.189/grafana/`

Certificado auto-assinado — aceitar no primeiro acesso.

---

## Estrutura

```
compose/
├── compose.yaml        # Master (include todos os stacks)
├── network.yaml        # Redes + secrets compartilhados
├── home.yaml           # mariadb, homeassistant, esphome
├── security.yaml       # suricata, crowdsec
├── monitoring.yaml     # prometheus, grafana
├── services.yaml       # traefik, forgejo, mumble, kali
├── .env.example        # Template de variaveis (fake)
└── sops-secrets.yaml   # Secrets encriptados (SOPS + age)

traefik/                # Reverse proxy (dynamic.yml + traefik.yml)
suricata/               # IDS/IPS (yaml + regras custom)
crowdsec/               # IPS (acquis, profiles, scenarios, whitelist)
homeassistant/          # HA config template + ESPHome
monitoring/             # Prometheus + Grafana
scripts/                # decrypt-secrets, update-suricata-rules
```

### Stacks individuais

```bash
# Tudo
docker compose -f compose/compose.yaml up -d

# So home
docker compose -f compose/network.yaml -f compose/home.yaml up -d

# So seguranca
docker compose -f compose/network.yaml -f compose/security.yaml up -d
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
# Copiar public key para .sops.yaml

# 3. Editar secrets com valores reais
sops compose/sops-secrets.yaml

# 4. Gerar .env
bash scripts/decrypt-secrets.sh

# 5. Subir
docker compose -f compose/compose.yaml up -d
```

---

## Suricata 8 + CrowdSec IPS

### Suricata (deteccao)

12 regras ativas em `eno1` + `br-homelab`:

| SID | Tipo | Detecta |
|-----|------|---------|
| 1000010 | SYN scan | `nmap -sS` (5 pacotes em 3s) |
| 1000011 | connect() scan | `nmap -sT` |
| 1000012 | NULL scan | `nmap -sN` |
| 1000013 | FIN scan | `nmap -sF` |
| 1000014 | XMAS scan | `nmap -sX` |
| 1000020 | Port scan | 10+ portas em 5s |
| 1000030 | UDP scan | `nmap -sU` (exclui DNS) |
| 1000040 | SSH brute force | 8+ novas conexoes em 30s |
| 1000050 | Path traversal | `../` em HTTP |
| 1000051 | SQL injection | `union select` em HTTP |

### CrowdSec (prevencao)

- Le `eve.json` do Suricata em tempo real
- Scenario custom: 2 alerts em 60s = ban
- OpenWrt bouncer aplica bloqueio na borda via nftables
- Whitelist: localhost + gateway (192.168.20.1)

```bash
docker exec crowdsec cscli decisions list   # IPs banidos
docker exec crowdsec cscli alerts list      # alertas recentes
```

### Testar

```bash
docker exec kali nmap -sS -p 1-100 192.168.20.189
docker exec suricata cat /var/log/suricata/fast.log | tail -5
docker exec crowdsec cscli decisions list
```

---

## Seguranca

- **Zero portas web expostas** — tudo via Traefik
- Grafana, Prometheus bind `127.0.0.1` (internos)
- MariaDB so na rede `backend`
- Secrets encriptados com SOPS + age (`.env` gitignored)
- `network_mode: host` so onde necessario (Suricata, ESPHome)
- `no-new-privileges:true` em containers com host network
- Healthchecks + resource limits em todos os containers
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
| `yamllint` | Valida YAML (compose/, homeassistant/, suricata/, monitoring/, crowdsec/, traefik/) |
| `compose-validate` | `docker compose config --quiet` |
| `config-scan` | Trivy misconfiguration scan |
| `image-scan` | Trivy CVE scan em 7 imagens (matrix) |
