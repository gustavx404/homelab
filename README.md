# homelab

Infraestrutura auto-hospedada — Docker Compose, 11 servicos, rede zero-confianca.

[![CI](https://img.shields.io/github/actions/workflow/status/gustavx404/homelab/ci.yaml?style=flat-square&label=ci&color=10b981)](https://github.com/gustavx404/homelab/actions)
[![servicos](https://img.shields.io/badge/servicos-11-3b82f6?style=flat-square)]()
[![suricata](https://img.shields.io/badge/suricata-8-6b7280?style=flat-square)]()
[![secrets](https://img.shields.io/badge/secrets-sops%2Bage-6b7280?style=flat-square)]()

---

## Arquitetura

```
Internet → OpenWrt (borda + CrowdSec bouncer)
                │
                ▼  :80 :443
           ┌─────────────┐
           │  Traefik v3  │  proxy reverso · roteamento por path
           │  /         HA│
           │  /grafana    │
           │  /git        │
           └──────┬───────┘
                  │  rede backend (br-homelab)
     ┌────────┬───┴───┬────────┬────────┬────────┐
     ▼        ▼       ▼        ▼        ▼        ▼
  mariadb  grafana prometheus forgejo  mumble  crowdsec
     └────────┴───────┴───┬────┴────────┴────│───┘
                     rede host               ▼
               suricata · esphome       LAPI :8080
               (eno1)     (:6052)       (→ OpenWrt)
```

- Traefik e o unico ponto de entrada HTTP/S. Todos os apps web passam por ele.
- Suricata e ESPHome usam `network_mode: host` por necessidade (captura de pacotes / mDNS).
- CrowdSec envia decisoes de ban para o OpenWrt na borda da rede.

---

## Instalacao

```bash
# dependencias
curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh ./get-docker.sh
sudo apt install -y docker-compose-v2 age yamllint
curl -LO https://github.com/getsops/sops/releases/download/v3.13.3/sops-v3.13.3.linux.amd64
sudo install -m 755 sops-v3.13.3.linux.amd64 /usr/local/bin/sops

# gerar chave age e copiar a chave publica para .sops.yaml
age-keygen -o ~/.config/sops/age/keys.txt

# editar secrets com valores reais
sops compose/sops-secrets.yaml

# decriptar secrets e gerar .env
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

---

## Servicos

| stack | servico | imagem | acesso |
|-------|---------|--------|--------|
| nucleo | traefik | `v3.3` | `80,443` |
| nucleo | homeassistant | `stable` | interno |
| nucleo | mariadb | `lts` | interno |
| nucleo | esphome | `stable` | `6052` host |
| seguranca | suricata | `latest` | host |
| seguranca | crowdsec | `latest` | `8080` lapi |
| apps | forgejo | `16.0.2` | `2222` ssh |
| apps | mumble | `latest` | `64738` tcp/udp |
| apps | kali | `rolling` | cli |
| monitoria | prometheus | `v3.4.0` | `127.0.0.1:9090` |
| monitoria | grafana | `11.6.0` | interno |

---

## Estrutura

```
compose/
├── compose.yaml        principal (include)
├── network.yaml        rede + secrets
├── home.yaml           mariadb · homeassistant · esphome
├── security.yaml       suricata · crowdsec
├── monitoring.yaml     prometheus · grafana
├── services.yaml       traefik · forgejo · mumble · kali
├── .env.example        template
└── sops-secrets.yaml   encriptado (SOPS + age)

traefik/                config do proxy reverso
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
```

---

## IDS/IPS

Suricata monitora `eno1` e `br-homelab`. CrowdSec processa `eve.json` em tempo real. Dois alertas em 60 segundos disparam um ban de 6 horas, propagado para o OpenWrt na borda.

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
| `6052` | esphome | rede host (mDNS) |
| `64738` | mumble | protocolo VoIP |
| `8080` | crowdsec lapi | bouncer OpenWrt |

Prometheus vinculado apenas a `127.0.0.1`. Nenhum app web exposto diretamente — tudo passa pelo Traefik.

---

## Seguranca

- todos os apps web acessiveis apenas via Traefik (HA, Grafana, Forgejo)
- prometheus vinculado apenas a `127.0.0.1` (metricas internas)
- mariadb isolado na rede `backend`
- secrets encriptados com SOPS + age (`.env` gitignored)
- `network_mode: host` apenas onde necessario
- `no-new-privileges:true` nos containers host
- healthchecks e resource limits em todos os containers
- CI: yamllint, compose-validate, trivy config, trivy cve (7 imagens)

---

## Backup

```bash
tar -czf backup-$(date +%Y%m%d).tar.gz data/
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
| [SOPS](https://github.com/getsops/sops) | Mozilla |
| [age](https://github.com/FiloSottile/age) | Filippo Valsorda |

Feito por [gustavx404](https://github.com/gustavx404).
