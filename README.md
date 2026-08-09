# homelab

Infraestrutura auto-hospedada — Docker Compose, 16 servicos, rede zero-confianca.

[![CI](https://img.shields.io/github/actions/workflow/status/gustavx404/homelab/ci.yaml?style=flat-square&label=ci&color=10b981)](https://github.com/gustavx404/homelab/actions)
[![servicos](https://img.shields.io/badge/servicos-16-3b82f6?style=flat-square)]()
[![suricata](https://img.shields.io/badge/suricata-8-6b7280?style=flat-square)]()
[![secrets](https://img.shields.io/badge/secrets-sops%2Bage-6b7280?style=flat-square)]()

---

## Arquitetura

```
Internet → OpenWrt (borda + CrowdSec bouncer)
                │
                ▼  :80 :443
           ┌─────────────┐
           │  Traefik v3  │  reverse proxy · path-based routing
           │  /         HA│
           │  /grafana    │
           │  /git        │
           │  /frigate    │
           └──────┬───────┘
                  │  backend network (br-homelab)
     ┌────────┬───┴───┬────────┬────────┬────────┬────────┬────────┐
     ▼        ▼       ▼        ▼        ▼        ▼        ▼        ▼
  mariadb  grafana prometheus forgejo  mumble  crowdsec  immich  frigate
     └────────┴───────┴───┬────┴────────┴────│───┘       │        │
                     host network             ▼     :2283  :8554/55
               suricata · esphome       LAPI :8080
               (eno1)     (:6052)       (→ OpenWrt)
```

- Traefik e o unico ponto de entrada HTTP/S. Todos os apps web passam por ele.
- Frigate acessivel em `/frigate` (header `X-Ingress-Path` + WebSocket).
- Immich nao suporta subpath — exposto na porta `2283` (LAN).
- Suricata e ESPHome usam `network_mode: host` por necessidade (packet capture / mDNS).
- CrowdSec envia decisoes de ban para o OpenWrt na borda da rede.

---

## Instalacao

```bash
# dependencias
curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh ./get-docker.sh
sudo apt install -y docker-compose-v2 age yamllint
curl -LO https://github.com/getsops/sops/releases/download/v3.13.3/sops-v3.13.3.linux.amd64
sudo install -m 755 sops-v3.13.3.linux.amd64 /usr/local/bin/sops

# gerar chave age e copiar chave publica para .sops.yaml
age-keygen -o ~/.config/sops/age/keys.txt

# editar secrets com valores reais
sops compose/sops-secrets.yaml

# decriptar e gerar .env
bash scripts/decrypt-secrets.sh

# subir todos os stacks
docker compose -f compose/compose.yaml up -d
```

**Acesso** — roteamento por path, sem dependencia de DNS. TLS auto-assinado.

| path | servico |
|------|---------|
| `/` | Home Assistant |
| `/grafana/` | Grafana |
| `/git/` | Forgejo |
| `/frigate/` | Frigate (NVR cameras) |

> Immich (fotos) nao suporta subpath — acessar em `http://192.168.20.189:2283`.

---

## Servicos

| stack | servico | imagem | acesso |
|-------|---------|--------|--------|
| home | traefik | `v3.3` | `80,443` |
| home | homeassistant | `stable` | interno |
| home | mariadb | `lts` | interno |
| home | esphome | `stable` | `6052` host |
| security | suricata | `latest` | host |
| security | crowdsec | `latest` | `8080` lapi |
| services | forgejo | `16.0.2` | `2222` ssh |
| services | mumble | `latest` | `64738` tcp/udp |
| services | kali | `rolling` | cli |
| monitoring | prometheus | `v3.4.0` | `127.0.0.1:9090` |
| monitoring | grafana | `11.6.0` | interno |
| media | frigate | `stable` | `/frigate` |
| media | immich-server | `v3.1.0` | `2283` |
| media | immich-machine-learning | `v3.1.0` | interno |
| media | immich-redis (valkey) | `9` | interno |
| media | immich-postgres | `14-vectorchord` | interno |

---

## Estrutura

```
compose/
├── compose.yaml        principal (include)
├── network.yaml        rede + secrets
├── home.yaml           mariadb · homeassistant · esphome
├── security.yaml       suricata · crowdsec
├── monitoring.yaml     prometheus · grafana
├── media.yaml          frigate · immich (server/ml/redis/postgres)
├── services.yaml       traefik · forgejo · mumble · kali
├── .env.example        template
└── sops-secrets.yaml   encriptado (SOPS + age)

traefik/                config do proxy reverso
frigate/                config NVR (detector CPU, cameras)
suricata/               config IDS + 12 assinaturas
crowdsec/               acquis · profiles · scenarios · whitelist
homeassistant/          config HA + dispositivos ESPHome
monitoring/             configs prometheus + grafana
scripts/                decrypt-secrets · update-suricata-rules
```

Stacks individuais:

```bash
docker compose -f compose/network.yaml -f compose/security.yaml up -d
docker compose -f compose/network.yaml -f compose/home.yaml up -d
docker compose -f compose/network.yaml -f compose/media.yaml up -d
```

---

## IDS/IPS

Suricata monitora `eno1` e `br-homelab`. CrowdSec processa `eve.json` em tempo real. Dois alertas em 60 segundos disparam ban de 6 horas, propagado para o OpenWrt na borda.

| assinatura | limite |
|-----------|--------|
| icmp echo | informativo |
| varredura icmp | 10 / 30s |
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

Perfis CrowdSec — cenario `homelab/scan-detection`:

| gatilho | duracao |
|---------|---------|
| primeira deteccao | 6 h |
| padrao de scan | 24 h |
| reincidente (>=3) | 48 h |

```bash
docker exec crowdsec cscli decisions list      # bans ativos
docker exec kali nmap -sS -p 1-100 <host>     # teste
```

---

## Portas expostas

| porta | servico | motivo |
|-------|---------|--------|
| `22` | ssh | acesso administrativo |
| `80,443` | traefik | unico ponto de entrada |
| `2222` | forgejo ssh | git push/pull |
| `6052` | esphome | host network (mDNS) |
| `64738` | mumble | protocolo VoIP |
| `8080` | crowdsec lapi | bouncer OpenWrt |
| `2283` | immich | fotos/videos (subpath nao suportado) |
| `8554` | frigate | RTSP restream |
| `8555` | frigate | WebRTC tcp/udp |

Frigate UI/API (8971) nao exposta — somente via Traefik em `/frigate` com autenticacao.

---

## Seguranca

- todos os apps web acessiveis via Traefik (HA, Grafana, Forgejo, Frigate)
- Immich na porta 2283 (excecao documentada — subpath nao suportado)
- prometheus vinculado apenas a `127.0.0.1` (metricas internas)
- mariadb isolado na rede `backend`
- secrets encriptados com SOPS + age (`.env` gitignored)
- `network_mode: host` apenas onde necessario
- `no-new-privileges:true` nos containers host
- healthchecks e resource limits em todos os containers
- CI: yamllint, compose-validate, trivy config, trivy cve (12 imagens)

---

## Backup

```bash
tar -czf backup-$(date +%Y%m%d).tar.gz data/  # inclui immich/ (library+postgres) e frigate/
cp ~/.config/sops/age/keys.txt backup-age-key.txt
```

---

## Creditos

| projeto | autor |
|---------|-------|
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
| [Frigate](https://frigate.video/) | Blake Blackshear |
| [Immich](https://immich.app/) | Immich (FUTO) |
| [SOPS](https://github.com/getsops/sops) | Mozilla |
| [age](https://github.com/FiloSottile/age) | Filippo Valsorda |

Feito por [gustavx404](https://github.com/gustavx404).
