# homelab

Infraestrutura auto-hospedada — Docker Compose, 20 servicos, rede zero-confianca.

[![CI](https://github.com/gustavx404/homelab/actions/workflows/ci.yaml/badge.svg)](https://github.com/gustavx404/homelab/actions)
[![servicos](https://img.shields.io/badge/servicos-20-3b82f6?style=flat-square)]()
[![suricata](https://img.shields.io/badge/suricata-8-6b7280?style=flat-square)]()
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
           │  photos.home  → Immich (fotos)
           │  vault.home   → Vaultwarden (senhas)
           └──────┬───────┘
                  │  backend network (br-homelab)
     ┌────────┬───┴───┬────────┬────────┬────────┬────────┬────────┐
     ▼        ▼       ▼        ▼        ▼        ▼        ▼        ▼
  mariadb  grafana prometheus forgejo  mumble  crowdsec  immich  frigate
     └────────┴───────┴───┬────┴────────┴────│───┘
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

**DNS** — adicionar ao OpenWrt (LuCI → DHCP and DNS → Hosts) ou `/etc/hosts`:

```
192.168.20.189 home.home ha.home grafana.home git.home frigate.home photos.home vault.home ntfy.home
```

**Acesso** — hostname-based routing, TLS auto-assinado.

| hostname | servico |
|----------|---------|
| `home.home` | Homepage (dashboard) |
| `ha.home` | Home Assistant |
| `grafana.home` | Grafana |
| `git.home` | Forgejo |
| `frigate.home` | Frigate (NVR) |
| `photos.home` | Immich (fotos) |
| `vault.home` | Vaultwarden (senhas) |
| `ntfy.home` | ntfy (notificacoes push) |

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
| services | homepage | `latest` | interno |
| services | forgejo | `16.0.2` | `2222` ssh |
| services | mumble | `latest` | `64738` tcp/udp |
| services | kali | `rolling` | cli |
| services | vaultwarden | `docker.io/vaultwarden/server:latest` | interno |
| notify | ntfy | `binwiederhier/ntfy:latest` | interno |
| monitoring | prometheus | `v3.4.0` | `127.0.0.1:9090` |
| monitoring | grafana | `11.6.0` | interno |
| media | frigate | `stable` | interno |
| media | immich-server | `v3.1.0` | interno |
| media | immich-machine-learning | `v3.1.0` | interno |
| media | immich-redis (valkey) | `9` | interno |
| media | immich-postgres | `14-vectorchord0.4.3-pgvectors0.2.0` | interno |

### Banco de dados (MariaDB)

MariaDB e o banco central (`compose/database.yaml`, rede `backend`), compartilhado por:

| app | banco | usuario |
|-----|-------|---------|
| Home Assistant (recorder) | homeassistant | ha_user |
| Forgejo | forgejo | forgejo |
| Vaultwarden | vaultwarden | vaultwarden |
| CrowdSec | crowdsec | crowdsec |

Bancos e usuarios das apps sao criados no primeiro boot por
`compose/database-init/01-create-app-databases.sh` (montado em
`/docker-entrypoint-initdb.d`). Senhas centralizadas no SOPS
(`FORGEJO_DB_PASSWORD`, `VAULTWARDEN_DB_PASSWORD`, `CROWDSEC_DB_PASSWORD`).

Nao usam MariaDB de proposito: Immich (PostgreSQL + pgvector, exigido pelo ML
de embeddings), Grafana/Mumble/ntfy (SQLite — volume baixo ou sem suporte a
MySQL, evitam dependencia no banco central).

---

## Estrutura

```
compose/
├── compose.yaml        principal (include)
├── network.yaml        rede + secrets
├── database.yaml       mariadb (banco central: HA · forgejo · vaultwarden · crowdsec)
├── database-init/      01-create-app-databases.sh (bancos/usuarios no primeiro boot)
├── home.yaml           homeassistant · esphome
├── security.yaml       suricata · crowdsec · suricata-stats
├── monitoring.yaml     prometheus · grafana
├── media.yaml          frigate · immich (server/ml/redis/postgres)
├── services.yaml       traefik · forgejo · mumble · kali
├── vaultwarden.yaml    vaultwarden (senhas)
├── notify.yaml         ntfy (notificacoes push)
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

Stacks que usam o banco central (home, security, services, vaultwarden) exigem compose/database.yaml na lista.

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

O dashboard (Homepage) mostra stats em tempo real do Suricata via `suricata-stats` (endpoint interno `:8899` que le o `eve.json`): uptime, pacotes, drops e total de alertas. Apos editar `suricata/suricata.yaml`, recrie o container:

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
- painel `/admin` do Vaultwarden protegido por `ADMIN_TOKEN` (SOPS); signups desabilitados
- ntfy com auth `deny-all`; topico de alerts protegido por access token
- `network_mode: host` apenas onde necessario
- `suricata-stats` le o `eve.json` somente-leitura (rede `backend`, porta interna, sem bind)
- `no-new-privileges:true` nos containers host
- healthchecks e resource limits em todos os containers
- CI: yamllint, compose-validate, trivy config, trivy cve (15 imagens)

---

## Notificacoes (ntfy)

ntfy e o canal de push self-hosted: app no celular, Home Assistant e CrowdSec
publicam nos topicos `alerts` (seguranca) e `home` (cotidiano).

**Primeiro boot:**

```bash
docker compose -f compose/compose.yaml up -d ntfy

# criar usuarios (auth deny-all)
# senha admin: NTFY_ADMIN_PASSWORD no sops (sops compose/sops-secrets.yaml)
docker exec -it ntfy ntfy user add --role=admin admin   # login web + HA
docker exec ntfy ntfy user add crowdsec                 # service user p/ CrowdSec
docker exec ntfy ntfy access crowdsec alerts rw         # ACL do topico alerts
docker exec ntfy ntfy token add crowdsec alerts         # token tk_... -> NTFY_TOKEN_CROWDSEC (sops)

# testar publish (com o token do topico)
curl -u admin:SUA_SENHA -H "Title: teste" -H "Priority: high" \
     -d "Homelab funcionando" https://ntfy.home/alerts
```

**Celular:** instale o app ntfy, use o servidor `https://ntfy.home` e faca login.

**Home Assistant** (Settings > Devices & services > Add Integration > ntfy):
URL `http://ntfy:80`, usuario/senha admin; adicione os topicos `alerts` e `home`
(entidades `notify.alerts` / `notify.home` usadas em `homeassistant/automations.yaml`).

**CrowdSec** publica automaticamente no topico de alerts (plugin http, config em
`crowdsec/notifications/ntfy.yaml`). Teste: `docker exec crowdsec cscli notifications test ntfy_alerts`.

---

## Dashboard (Homepage)

Cards de status em `homepage/services.yaml` (rede `backend`, sem expor portas).

Widgets ativos: Home Assistant, CrowdSec, Suricata (customapi), ntfy, Gitea
(API do Forgejo), Frigate (`frigate:5000` — porta interna da API), Immich,
Grafana (admin) e Prometheus. O card Traefik usa apenas status Docker
(dashboard nao exposto).

**Pendencias — chaves que ainda nao existem** (widgets aparecem com erro de
auth ate serem criadas):

```bash
# 1. Immich (widget mostra fotos/usuarios):
#    photos.home > Perfil > API Keys > New API Key (permissao: server.statistics)
# 2. Forgejo (widget gitea mostra repos/issues/pulls):
#    git.home > Settings > Applications > Generate New Token
#    (permissao: read:notification, read:repository, read:issue)

# 3. Guardar as chaves no SOPS e regenerar o .env:
sops compose/sops-secrets.yaml          # preencher IMMICH_API_KEY e FORGEJO_TOKEN
bash scripts/decrypt-secrets.sh
docker compose -f compose/compose.yaml up -d homepage
```

> Segredos (HOMEPAGE_HA_KEY, CrowdSec, ntfy e Grafana admin) chegam ao
> container via `HOMEPAGE_VAR_*` (ver `compose/services.yaml`) — mesmo padrao
> usado pelos demais widgets; dashboard protegido por basicAuth no Traefik.

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
| [Vaultwarden](https://github.com/dani-garcia/vaultwarden) | dani-garcia |
| [ESPHome](https://esphome.io/) | ESPHome |
| [Home Assistant](https://www.home-assistant.io/) | Home Assistant |
| [Grafana](https://grafana.com/) | Grafana Labs |
| [Prometheus](https://prometheus.io/) | Prometheus |
| [Frigate](https://frigate.video/) | Blake Blackshear |
| [Immich](https://immich.app/) | Immich (FUTO) |
| [SOPS](https://github.com/getsops/sops) | Mozilla |
| [ntfy](https://ntfy.sh/) | Philipp C. Heckel |
| [age](https://github.com/FiloSottile/age) | Filippo Valsorda |

Feito por [gustavx404](https://github.com/gustavx404).
