# homelab

Infraestrutura auto-hospedada — Docker Compose, 13 servicos, rede zero-confianca.

[![CI](https://github.com/gustavx404/homelab/actions/workflows/ci.yaml/badge.svg)](https://github.com/gustavx404/homelab/actions)
[![servicos](https://img.shields.io/badge/servicos-13-3b82f6?style=flat-square)]()
[![suricata](https://img.shields.io/badge/suricata-12-6b7280?style=flat-square)]()
[![secrets](https://img.shields.io/badge/secrets-sops%2Bage-6b7280?style=flat-square)]()

---

## Arquitetura

```
Internet → OpenWrt (borda + CrowdSec bouncer)
                │
                ▼  :80 :443
           ┌─────────────┐
           │  Traefik v3  │  proxy reverso · hostname-based routing
           │              │
           │  ha.home      → Home Assistant
           │  grafana.home → Grafana
           │  git.home     → Forgejo
           │  frigate.home → Frigate (NVR)
           └──────┬───────┘
                  │  backend network (br-homelab)
     ┌────────┬───┴───┬────────┬────────┬────────┬────────┐
     ▼        ▼       ▼        ▼        ▼        ▼        ▼
  mariadb  grafana prometheus forgejo  mumble  crowdsec  frigate
     └────────┴───────┴───┬────┴────────┴────┬───┘
                     host network             ▼
               suricata · esphome       LAPI :8080
               (eno1)     (:6052)       (→ OpenWrt)
               suricata-stats (backend, :8899 interno)
```

- Traefik e o unico ponto de entrada HTTP/S. Todos os apps web passam por ele.
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

**DNS** — hostnames `.home` (ha, grafana, git, frigate) resolvem via
dnsmasq do roteador OpenWrt (`/etc/hosts` no LuCI) para `192.168.20.189`.
A lista de hostnames precisa bater com as rotas em `traefik/dynamic.yml`.

**Acesso** — hostname-based routing, TLS auto-assinado.

| hostname | servico |
|----------|---------|
| `ha.home` | Home Assistant |
| `grafana.home` | Grafana |
| `git.home` | Forgejo |
| `frigate.home` | Frigate (NVR) |

---

## Servicos

| stack | servico | imagem | acesso |
|-------|---------|--------|--------|
| services | traefik | `v3.3` | `80,443` |
| home | homeassistant | `stable` | interno |
| database | mariadb | `lts` | interno |
| home | esphome | `stable` | `6052` host |
| security | suricata | `latest` | host |
| security | suricata-stats | `python:3.13-alpine` | interno `8899` |
| security | crowdsec | `latest` | `8080` lapi |
| services | forgejo | `16.0.2` | `2222` ssh |
| services | mumble | `latest` | `64738` tcp/udp |
| services | kali | `rolling` | cli |
| monitoring | prometheus | `v3.4.0` | `127.0.0.1:9090` |
| monitoring | grafana | `11.6.0` | interno |
| media | frigate | `stable` | interno |

### Banco de dados (MariaDB)

MariaDB e o banco central (`compose/database.yaml`, rede `backend`), compartilhado por:

| app | banco | usuario |
|-----|-------|---------|
| Home Assistant (recorder) | homeassistant | ha_user |
| Forgejo | forgejo | forgejo |
| Grafana | grafana | grafana |
| CrowdSec | crowdsec | crowdsec |

Bancos e usuarios das apps sao criados no primeiro boot por
`compose/database-init/01-create-app-databases.sh` (montado em
`/docker-entrypoint-initdb.d`). Senhas centralizadas no SOPS
(`FORGEJO_DB_PASSWORD`, `GRAFANA_DB_PASSWORD`, `CROWDSEC_DB_PASSWORD`).

Nao usam MariaDB de proposito: Mumble (SQLite — volume baixo ou sem
suporte a MySQL, evita dependencia no banco central).

---

## Estrutura

```
compose/
├── compose.yaml        principal (include)
├── network.yaml        rede + secrets
├── database.yaml       mariadb (banco central: HA · forgejo · grafana · crowdsec)
├── database-init/      01-create-app-databases.sh (bancos/usuarios no primeiro boot)
├── home.yaml           homeassistant · esphome
├── security.yaml       suricata · crowdsec · suricata-stats
├── monitoring.yaml     prometheus · grafana
├── media.yaml          frigate (NVR)
├── services.yaml       traefik · forgejo · mumble · kali
├── .env.example        template
├── sops-secrets.yaml   encriptado (SOPS + age)
└── sops-secrets.template.yaml  template SOPS (init-sops)

traefik/                config do proxy reverso
frigate/                config NVR (detector CPU, cameras)
suricata/               config IDS + 12 assinaturas
crowdsec/               acquis · profiles · scenarios · whitelist · notifications
homeassistant/          config HA + dispositivos ESPHome
monitoring/             configs prometheus + grafana
scripts/                init-sops · decrypt-secrets · update-suricata-rules · suricata-stats
```

Stacks individuais:

```bash
docker compose -f compose/network.yaml -f compose/database.yaml -f compose/security.yaml up -d
docker compose -f compose/network.yaml -f compose/database.yaml -f compose/home.yaml up -d
docker compose -f compose/network.yaml -f compose/media.yaml up -d
```

Stacks que usam o banco central (home, security, services, monitoring) exigem compose/database.yaml na lista.

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

`suricata-stats` expoe stats em tempo real do Suricata (endpoint interno `:8899` que le o `eve.json`): uptime, pacotes, drops e total de alertas. Apos editar `suricata/suricata.yaml`, recrie o container:

```bash
docker compose -f compose/network.yaml -f compose/security.yaml up -d --force-recreate suricata
```

Perfis CrowdSec — cenario `homelab/scan-detection` (ordem importa: o mais
especifico vem primeiro, `on_success: break`):

| gatilho | duracao |
|---------|---------|
| reincidente (>=3 eventos) | 48 h |
| padrao de scan | 24 h |
| primeira deteccao | 6 h |

**Notificacoes**: cada ban dispara um webhook para o Home Assistant
(`crowdsec/notifications/ha-webhook.yaml`, perfil `ha_alerts` no
`crowdsec/profiles.yaml`), que repassa o alerta para os apps via
`notify.notify`. O ID do webhook vem do SOPS (`HA_WEBHOOK_ID`, default
`crowdsec_alerts`) e a automacao correspondente esta em
`homeassistant/automations.yaml`. Teste:
`docker exec crowdsec cscli notifications test ha_alerts`.

**Whitelist RFC1918**: `crowdsec/whitelists.yaml` branqueia `127.0.0.1`, a LAN
(`192.168.20.0/24`) e as redes Docker (`172.16.0.0/12`, `10.0.0.0/8`) — trafego
interno nunca gera ban (so protecao da borda via OpenWrt). Apos editar
`crowdsec/whitelists.yaml`, `profiles.yaml` ou `scenarios/`, recrie o container:

```bash
docker compose -f compose/compose.yaml up -d --force-recreate crowdsec
```

**Community blocklist (CAPI)**: habilitado com
`docker exec crowdsec cscli console enable console_management` — as decisoes da
comunidade (`ssh:bruteforce` etc.) aparecem em `cscli decisions list` com origem
`CAPI` e o OpenWrt as aplica na borda. Para o bouncer do OpenWrt puxar a
blocklist, ele precisa pedir `community_pull=true` no stream (config do bouncer
no roteador; hoje esta `false`).

```bash
docker exec crowdsec cscli decisions list      # bans ativos (origem CAPI/local)
docker exec crowdsec cscli console status      # estado do console (blocklist)
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
| `8554` | frigate | RTSP restream |
| `8555` | frigate | WebRTC tcp/udp |

Nenhum app web exposto diretamente — tudo passa pelo Traefik.

---

## Seguranca

- todos os apps web acessiveis apenas via Traefik
- prometheus vinculado apenas a `127.0.0.1` (metricas internas)
- mariadb isolado na rede `backend`
- secrets encriptados com SOPS + age (`.env` gitignored)
- `network_mode: host` apenas onde necessario
- `suricata-stats` le o `eve.json` somente-leitura (rede `backend`, porta interna, sem bind)
- `no-new-privileges:true` nos containers host
- healthchecks e resource limits em todos os containers
- CI: yamllint, compose-validate, trivy config, trivy cve (9 imagens)

---

## Backup

```bash
tar -czf backup-$(date +%Y%m%d).tar.gz data/
cp ~/.config/sops/age/keys.txt backup-age-key.txt
```

---

## Usar como template

Este repositorio e um ponto de partida para montar o proprio lab.

1. Clique em **Use this template** (ou fork) no GitHub
2. Clone e gere seus secrets:

```bash
bash scripts/init-sops.sh          # chave age + encripta sops-secrets.template.yaml
sops compose/sops-secrets.yaml     # preencha valores reais
bash scripts/decrypt-secrets.sh    # gera compose/.env
docker compose -f compose/compose.yaml up -d
```

3. Ajuste os hostnames em `traefik/dynamic.yml` e o DNS do roteador.
4. Veja `SECURITY.md` para rotacao de chaves e hardening do GitHub.

> O `compose/sops-secrets.yaml` versionado so decripta com a chave age do autor.
> O script `init-sops.sh` encripta o template com a **sua** chave, do zero.

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
| [SOPS](https://github.com/getsops/sops) | Mozilla |
| [age](https://github.com/FiloSottile/age) | Filippo Valsorda |

Feito por [gustavx404](https://github.com/gustavx404).
