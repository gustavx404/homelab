# homelab

> Infraestrutura Dockerizada com SOPS, CI/CD e 10 servicos.

[![CI](https://github.com/gustavx404/homelab/actions/workflows/ci.yaml/badge.svg)](https://github.com/gustavx404/homelab/actions/workflows/ci.yaml)

---

## Arquitetura

```
Internet
   │
   ▼
┌──────────────────────────────────────┐
│  Caddy :80/:443 (reverse proxy)      │
│  / → Home Assistant                  │
│  /grafana → Grafana                  │
│  /git → Forgejo                      │
└──────────────────────────────────────┘
   │
   ▼  backend (bridge network)
┌──────────┬──────────┬──────────┬──────────┬──────────┐
│ mariadb  │ grafana  │prometheus│ forgejo  │  mumble  │
│ (HA DB)  │ :3000    │ :9090    │ :3001/22 │ :64738   │
└──────────┴──────────┴──────────┴──────────┴──────────┘
   │
   ▼  host network (dispositivos/mDNS)
┌──────────┬──────────┬──────────────────┐
│ suricata │ esphome  │ homeassistant    │
│ IDS/IPS  │ :6052    │ :8123            │
└──────────┴──────────┴──────────────────┘
```

---

## Stack

| Servico | Imagem | Porta | Funcao |
|---------|--------|-------|--------|
| **Home Assistant** | `ghcr.io/.../home-assistant:stable` | `8123` | Automacao residencial |
| **MariaDB** | `mariadb:lts` | interno | Recorder HA (substitui SQLite) |
| **ESPHome** | `ghcr.io/.../esphome:stable` | `6052` | Firmware ESP32/ESP8266 |
| **Mumble** | `mumblevoip/mumble-server` | `64738` | VoIP (Ducks Server) |
| **Kali Linux** | `kalilinux/kali-rolling` | CLI | Pentest, CTF, nmap |
| **Caddy** | `caddy:2-alpine` | `80/443` | Reverse proxy + TLS |
| **Forgejo** | `forgejo:16.0.2` | `3001/2222` | Git self-hosted |
| **Prometheus** | `prom/prometheus:v3.4.0` | `9090` | Metricas |
| **Grafana** | `grafana/grafana:11.6.0` | `3000` | Dashboards |
| **Suricata** | `jasonish/suricata:7.0` | host | IDS/IPS (11 regras anti-scan) |

---

## Quick Start

```bash
# 1. Instalar dependencias
sudo apt install -y docker.io docker-compose-v2 age yamllint

# 2. SOPS (binario direto)
curl -LO https://github.com/getsops/sops/releases/download/v3.13.3/sops-v3.13.3.linux.amd64
sudo mv sops-v3.13.3.linux.amd64 /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops

# 3. Gerar chave age
age-keygen -o ~/.config/sops/age/keys.txt

# 4. Copiar public key para .sops.yaml (substitua pela sua)
#    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# 5. Editar secrets com valores reais
sops compose/sops-secrets.yaml

# 6. Gerar .env
bash scripts/decrypt-secrets.sh

# 7. Subir tudo
docker compose -f compose/compose.yaml up -d
```

---

## Estrutura

```
├── compose/
│   ├── compose.yaml          # Stack principal (10 servicos)
│   ├── .env.example          # Template de variaveis (valores fake)
│   └── sops-secrets.yaml     # Secrets encriptados (SOPS + age)
├── homeassistant/
│   ├── configuration.yaml    # Config do Home Assistant
│   ├── secrets.yaml          # !env_var bridge pras env vars
│   ├── ha-entrypoint.sh      # Wrapper que previne vazamento de secrets no docker inspect
│   └── esphome/
│       └── easun-4kw.yaml    # Inversor EASUN SMG II 11Kw
├── caddy/
│   └── Caddyfile             # Reverse proxy rules
├── suricata/
│   ├── suricata.yaml         # IDS/IPS config
│   └── rules/suricata.rules  # Regras de deteccao (SYN, XMAS, etc)
├── monitoring/
│   ├── prometheus/prometheus.yml
│   └── grafana/datasources.yml
├── scripts/
│   ├── decrypt-secrets.sh    # SOPS → .env
│   └── update-suricata-rules.sh  # Baixar ET Open ruleset
└── .github/workflows/
    └── ci.yaml               # yamllint + compose validate + trivy scan
```

---

## Secrets (SOPS + age)

Dois arquivos, propositos diferentes:

| Arquivo | Conteudo | Git |
|---------|----------|-----|
| `.env.example` | Template documentando todas as variaveis | ✅ commitado |
| `sops-secrets.yaml` | Valores reais encriptados | ✅ commitado |
| `.env` | Gerado pelo script, valores em plaintext | 🚫 gitignored |

```bash
sops compose/sops-secrets.yaml  # editar
bash scripts/decrypt-secrets.sh # gerar .env
```

---

## Servicos em detalhe

### Home Assistant + MariaDB

Recorder usa MariaDB em vez de SQLite — mais rapido, confiavel, suporta historico longo sem corromper. O container HA espera o healthcheck do MariaDB (`condition: service_healthy`).

### Suricata — IDS/IPS

11 regras de deteccao ativas:

| SID | Tipo | Detecta |
|-----|------|---------|
| 1000010 | SYN scan | `nmap -sS` |
| 1000011 | connect() scan | `nmap -sT` |
| 1000012 | NULL scan | `nmap -sN` |
| 1000013 | FIN scan | `nmap -sF` |
| 1000014 | XMAS scan | `nmap -sX` |
| 1000020 | Port scan | 50+ portas em 10s |
| 1000030 | UDP scan | `nmap -sU` |
| 1000040 | SSH brute force | 8+ novas conexoes em 30s |
| 1000050 | Path traversal | `../` em URL |
| 1000051 | SQL injection | `union select` em URL |

Para baixar o ruleset completo ET Open (30.000+ regras):

```bash
bash scripts/update-suricata-rules.sh
```

### Mumble — Ducks Server

Servidor VoIP com canais: Home, Study, Gaming, AFK. ACL maxima — apenas usuarios registrados conectam, anonimos barrados.

### Kali Linux

Container CLI com `NET_RAW` + `NET_ADMIN`. Acesso:

```bash
docker exec -it kali bash
apt update && apt install -y kali-tools-top10
```

### Seguranca

- Prometheus, Grafana bindam apenas em `127.0.0.1`
- MariaDB acessivel somente na rede interna `backend`
- Secrets encriptados com SOPS + age
- `.env` nunca commitado
- `network_mode: host` apenas onde necessario (Suricata, ESPHome)
- Healthchecks em todos os 10 containers
- Resource limits (memoria) em todos os containers
- `no-new-privileges:true` em containers com `host` network
- CI scan de vulnerabilidades com Trivy em todas as imagens

### Backup

```bash
# Volumes
tar -czf backup-$(date +%Y%m%d).tar.gz data/

# Chave age (CRITICO — sem ela, perde acesso aos secrets)
cp ~/.config/sops/age/keys.txt backup-age-key.txt
```

---

## Creditos

- **EASUN SMG II 11Kw ESPHome** — Configuracao do inversor baseada no projeto de [robgt978/easun-smg-ii-11kw-esphome](https://github.com/robgt978/Easun-SMG-II-11Kw-esphome-)
- **Suricata rules** — Emerging Threats Open ruleset
- **Mumble** — [mumblevoip/mumble-server](https://github.com/mumble-voip/mumble)

---

## CI/CD

GitHub Actions executa em todo push/PR:

| Job | Funcao |
|-----|--------|
| `yamllint` | Valida sintaxe YAML em compose/, homeassistant/, suricata/, monitoring/ |
| `compose-validate` | `docker compose config --quiet` |
| `config-scan` | Trivy misconfiguration scan no compose/ |
| `image-scan` | Trivy CVE scan em todas as 6 imagens (matrix job) |
