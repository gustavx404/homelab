<p align="center">
  <h1 align="center">homelab</h1>
  <p align="center">
    <b>Infraestrutura auto-hospedada</b><br>
    Docker Compose &middot; 14 servicos &middot; Zero-confianca
  </p>
</p>

<p align="center">
  <a href="https://github.com/gustavx404/homelab/actions"><img src="https://github.com/gustavx404/homelab/actions/workflows/ci.yaml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/servicos-14-3b82f6?style=flat-square" alt="14 servicos">
  <img src="https://img.shields.io/badge/suricata-12_asssinaturas-6b7280?style=flat-square" alt="Suricata 12 assinaturas">
  <img src="https://img.shields.io/badge/secrets-sops%2Bage-6b7280?style=flat-square" alt="SOPS + age">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white" alt="Docker">
  <img src="https://img.shields.io/badge/Traefik-24A1C1?style=flat-square&logo=traefikproxy&logoColor=white" alt="Traefik">
  <img src="https://img.shields.io/badge/Tailscale-242424?style=flat-square&logo=tailscale&logoColor=white" alt="Tailscale">
  <img src="https://img.shields.io/badge/HomeKit-F5A200?style=flat-square&logo=apple&logoColor=white" alt="HomeKit">
  <img src="https://img.shields.io/badge/Suricata-EF7E2B?style=flat-square&logo=suricata&logoColor=white" alt="Suricata">
  <img src="https://img.shields.io/badge/Prometheus-E6522C?style=flat-square&logo=prometheus&logoColor=white" alt="Prometheus">
  <img src="https://img.shields.io/badge/Grafana-F46800?style=flat-square&logo=grafana&logoColor=white" alt="Grafana">
  <img src="https://img.shields.io/badge/MariaDB-003545?style=flat-square&logo=mariadb&logoColor=white" alt="MariaDB">
</p>

---

### Indice

- [Arquitetura](#arquitetura) — diagrama da infraestrutura
- [Acesso Remoto](#acesso-remoto-tailscale) — Tailscale (WireGuard mesh)
- [Apple](#apple) — HomeKit, Siri, Companion App
- [Instalacao](#instalacao) — do zero ao ar em 5 minutos
- [Servicos](#servicos) — catalogo completo com 14 containers
- [Estrutura](#estrutura) — arvore de diretorios
- [Seguranca](#seguranca) — IDS/IPS, CrowdSec, hardenings
- [Backup](#backup) — rotina de backup
- [Template](#usar-como-template) — fork e personalize

---

## Arquitetura

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {
  'primaryColor': '#1e3a5f', 'primaryTextColor': '#e2e8f0',
  'primaryBorderColor': '#3b82f6', 'lineColor': '#64748b',
  'secondaryColor': '#0f172a', 'tertiaryColor': '#1e293b',
  'background': '#0f172a', 'mainBkg': '#1e293b',
  'textColor': '#e2e8f0', 'edgeLabelBackground': '#1e293b'
}}}%%
flowchart TB
    subgraph Internet["Internet"]
        iPhone["iPhone<br/>(Tailscale)"]
    end

    subgraph Edge["Borda — OpenWrt"]
        DNS["dnsmasq · DNS"]
        Bouncer["CrowdSec bouncer"]
    end

    subgraph Host["Host — 192.168.20.189"]
        Tailscale["Tailscale<br/>subnet router"]
        direction TB
        Traefik["Traefik v3<br/>:80 :443"]

        subgraph Backend["backend network (br-homelab)"]
            direction LR
            HA["Home Assistant"]
            Grafana["Grafana"]
            Forgejo["Forgejo"]
            Frigate["Frigate NVR"]
            Prometheus["Prometheus"]
            MariaDB["MariaDB"]
            CrowdSec["CrowdSec"]
            Stats["suricata-stats"]
            Mumble["Mumble VoIP"]
            Kali["Kali"]
        end

        subgraph HostNet["host network"]
            Suricata["Suricata IDS"]
            ESPHome["ESPHome"]
        end
    end

    iPhone -->|"WireGuard mesh"| Tailscale
    Tailscale -->|"subnet routes<br/>192.168.20.0/24 + 172.19.0.0/16"| Backend
    Internet -->|":80 :443"| Traefik
    Traefik -->|"hostname routing"| HA
    Traefik --> Grafana
    Traefik --> Forgejo
    Traefik --> Frigate
    CrowdSec -->|"LAPI :8080"| Bouncer
    HA -->|"recorder"| MariaDB
    Forgejo -->|"repo data"| MariaDB
    Grafana -->|"dashboards"| MariaDB
    CrowdSec -->|"decisions"| MariaDB
    Prometheus -->|"scrape"| HA
    Prometheus -->|"scrape"| Grafana
    Prometheus -->|"scrape"| Forgejo
    Prometheus -->|"scrape"| Frigate
```

| componente | funcao |
|---|---|
| Traefik | Unico ponto de entrada HTTP/S — roteia `*.home` por hostname |
| Tailscale | Mesh WireGuard — iPhone acessa tudo de qualquer lugar, sem portas abertas |
| MariaDB | Banco central — HA (recorder), Forgejo, Grafana, CrowdSec |
| Suricata + CrowdSec | IDS/IPS — detecta scans, aplica bans, notifica via HA webhook |
| Prometheus + Grafana | Metricas e dashboards de todos os servicos |

---

## Acesso Remoto (Tailscale)

O container `tailscale` atua como **subnet router**, expondo a LAN
(`192.168.20.0/24`) e a rede Docker (`172.19.0.0/16`) via WireGuard.

<details open>
<summary><b>Setup (4 passos)</b></summary>

1. **Crie uma auth key** em [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys)
   - Reusable, ephemeral=false, pre-approved=true
   - Tags: `tag:homelab`

2. **Adicione ao sops**:
   ```bash
   sops compose/sops-secrets.yaml        # TAILSCALE_AUTHKEY: tskey-auth-xxx...
   bash scripts/decrypt-secrets.sh
   ```

3. **Subir**:
   ```bash
   docker compose -f compose/compose.yaml up -d tailscale
   ```

4. **Aprovar subnet routes** no [admin console](https://login.tailscale.com/admin/machines):
   Machines > homelab > Edit route settings > aprovar `192.168.20.0/24` e `172.19.0.0/16`

</details>

> **iPhone**: instale o app Tailscale, faca login na mesma conta — `https://ha.home`,
> `https://grafana.home`, etc. funcionam como se estivesse em casa.

---

## Apple

### HomeKit Bridge

Expoe dispositivos do HA como acessorios HomeKit — controle pelo app **Casa**
ou **Siri** no iPhone/iPad/Apple TV/HomePod.

**Pre-requisito**: avahi-daemon no host com reflector (mDNS entre Docker bridge e LAN):

```bash
sudo apt install avahi-daemon
sudo sed -i 's/#enable-reflector=no/enable-reflector=yes/' /etc/avahi/avahi-daemon.conf
sudo systemctl restart avahi-daemon
```

A config `homekit:` ja esta no `homeassistant/configuration.yaml`. Apos subir
o HA, abra o app **Casa** > **+** > Adicionar Acessorio > escaneie o QR code em
HA > Configuracoes > Dispositivos e servicos > HomeKit Bridge.

### Companion App

O `default_config:` do HA ja inclui `mobile_app:` — zero config no servidor.

1. App Store: **Home Assistant Companion** > login em `https://ha.home`
2. Sensores automaticos: bateria, GPS, passos, SSID Wi-Fi, modo Foco, direcao

As automacoes usam `notify.notify` (envia p/ todos os destinos). Para
direcionar so ao iPhone, troque por `notify.mobile_app_iphone` nos
arquivos `automations.yaml` e `scripts.yaml`.

---

## Instalacao

```bash
# dependencias
curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh ./get-docker.sh
sudo apt install -y docker-compose-v2 age yamllint avahi-daemon
curl -LO https://github.com/getsops/sops/releases/download/v3.13.3/sops-v3.13.3.linux.amd64
sudo install -m 755 sops-v3.13.3.linux.amd64 /usr/local/bin/sops

# avahi-reflector (HomeKit — mDNS entre Docker e LAN)
sudo sed -i 's/#enable-reflector=no/enable-reflector=yes/' /etc/avahi/avahi-daemon.conf
sudo systemctl enable --now avahi-daemon

# secrets
age-keygen -o ~/.config/sops/age/keys.txt     # gera chave age
sops compose/sops-secrets.yaml                 # edita valores reais
bash scripts/decrypt-secrets.sh                # gera compose/.env

# subir tudo
docker compose -f compose/compose.yaml up -d
```

**DNS**: hostnames `.home` resolvem via dnsmasq do OpenWrt (LuCI > `/etc/hosts`
apontando `192.168.20.189`). Devem bater com `traefik/dynamic.yml`.

| hostname | servico |
|---|---|
| `ha.home` | Home Assistant |
| `grafana.home` | Grafana |
| `git.home` | Forgejo |
| `frigate.home` | Frigate (NVR) |

---

## Servicos

| stack | servico | imagem | acesso | rede |
|---|---|---|---|---|
| services | traefik | `v3.3` | `:80,443` | backend |
| home | homeassistant | `stable` | interno | backend |
| database | mariadb | `lts` | interno | backend |
| home | esphome | `stable` | `:6052` | host |
| security | suricata | `latest` | — | host |
| security | crowdsec | `latest` | `:8080` lapi | backend |
| security | suricata-stats | `python:3.13-alpine` | `:8899` interno | backend |
| services | forgejo | `16.0.2` | `:2222` ssh | backend |
| services | mumble | `latest` | `:64738` tcp/udp | backend |
| services | kali | `rolling` | cli | backend |
| monitoring | prometheus | `v3.4.0` | `127.0.0.1:9090` | backend |
| monitoring | grafana | `11.6.0` | `127.0.0.1:3000` | backend |
| media | frigate | `stable` | `:8554,8555` | backend |
| network | tailscale | `latest` | subnet router | host |

### MariaDB (banco central)

| app | banco | usuario |
|---|---|---|
| Home Assistant (recorder) | homeassistant | ha_user |
| Forgejo | forgejo | forgejo |
| Grafana | grafana | grafana |
| CrowdSec | crowdsec | crowdsec |

Bancos criados no primeiro boot por `database-init/01-create-app-databases.sh`.
Senhas no SOPS: `FORGEJO_DB_PASSWORD`, `GRAFANA_DB_PASSWORD`, `CROWDSEC_DB_PASSWORD`.

Mumble usa SQLite (volume baixo, evita dependencia no banco central).

---

## Estrutura

```
compose/
├── compose.yaml           principal (include)
├── network.yaml           rede + secrets
├── tailscale.yaml         acesso remoto (subnet router WireGuard)
├── database.yaml          mariadb
├── database-init/         01-create-app-databases.sh
├── home.yaml              homeassistant · esphome
├── security.yaml          suricata · crowdsec · suricata-stats
├── monitoring.yaml        prometheus · grafana
├── media.yaml             frigate (NVR)
├── services.yaml          traefik · forgejo · mumble · kali
├── .env.example           template
├── sops-secrets.yaml      encriptado (SOPS + age)
└── sops-secrets.template.yaml

traefik/     proxy reverso (rotas, TLS, middlewares)
frigate/     NVR (detector CPU, cameras)
suricata/    IDS + 12 assinaturas
crowdsec/    acquis · profiles · scenarios · whitelist · notifications
homeassistant/  HA + ESPHome
monitoring/  prometheus + grafana dashboards
scripts/     init-sops · decrypt-secrets · update-suricata-rules · suricata-stats
```

Stacks podem subir individualmente com `compose/network.yaml` (obrigatorio) +
`database.yaml` (se usar o banco central):

```bash
docker compose -f compose/network.yaml -f compose/database.yaml -f compose/security.yaml up -d
docker compose -f compose/network.yaml -f compose/database.yaml -f compose/home.yaml up -d
```

---

## Seguranca

### IDS/IPS

Suricata em `eno1` + `br-homelab`. CrowdSec processa `eve.json` — 3 alertas
em 60s disparam ban (duracao pelo perfil).

<details>
<summary><b>12 assinaturas</b></summary>

| assinatura | limite |
|---|---|
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

</details>

<details>
<summary><b>Perfis CrowdSec (ordem importa, on_success: break)</b></summary>

| gatilho | duracao |
|---|---|
| reincidente (>=3 eventos) | 48 h |
| padrao de scan | 24 h |
| primeira deteccao | 6 h |

</details>

**Notificacoes**: ban dispara webhook p/ HA
(`crowdsec/notifications/ha-webhook.yaml`, perfil `ha_alerts`), que repassa
via `notify.notify`. Webhook ID no SOPS (`HA_WEBHOOK_ID`).
Teste: `docker exec crowdsec cscli notifications test ha_alerts`

**Whitelist RFC1918**: `127.0.0.1`, `192.168.20.0/24` e redes Docker
(`172.16.0.0/12`, `10.0.0.0/8`) nunca geram ban.

**CAPI**: `docker exec crowdsec cscli console enable console_management` ativa
a blocklist da comunidade — os bans aparecem em `cscli decisions list` com
origem `CAPI` e o OpenWrt os aplica na borda.

```bash
docker exec crowdsec cscli decisions list    # bans ativos
docker exec crowdsec cscli console status    # estado CAPI
```

### Hardenings

- Apps web acessiveis apenas via Traefik (hostname routing + TLS)
- Prometheus bind `127.0.0.1`; MariaDB isolado na rede `backend`
- `network_mode: host` so onde necessario (suricata, esphome, tailscale)
- `no-new-privileges:true`, healthchecks e resource limits em todos os containers
- Secrets: SOPS + age (`.env` gitignored, `.sops.yaml` com chave publica commitavel)
- Tailscale: auth key ephemeral, subnet routes aprovadas manualmente

### Portas expostas

| porta | servico | motivo |
|---|---|---|
| `22` | ssh | admin |
| `80,443` | traefik | entrada HTTP/S |
| `2222` | forgejo | git ssh |
| `6052` | esphome | host (mDNS) |
| `64738` | mumble | VoIP |
| `8080` | crowdsec | LAPI (bouncer OpenWrt) |
| `8554` | frigate | RTSP |
| `8555` | frigate | WebRTC |

Tailscale nao expoe porta (WireGuard outbound com NAT traversal).

---

## Backup

```bash
tar -czf backup-$(date +%Y%m%d).tar.gz data/
cp ~/.config/sops/age/keys.txt backup-age-key.txt
```

---

## Usar como template

1. Clique em **Use this template** (ou fork) no GitHub
2. Clone e gere seus secrets:

```bash
bash scripts/init-sops.sh          # chave age + encripta template
sops compose/sops-secrets.yaml     # preencha valores reais
bash scripts/decrypt-secrets.sh    # gera compose/.env
docker compose -f compose/compose.yaml up -d
```

3. Ajuste os hostnames em `traefik/dynamic.yml` e o DNS do roteador
4. Veja [SECURITY.md](SECURITY.md) para rotacao de chaves e hardening do GitHub

> O `sops-secrets.yaml` versionado so decripta com a chave age do autor.
> `scripts/init-sops.sh` encripta o template com a **sua** chave, do zero.

---

## Creditos

| projeto | autor |
|---|---|
| [EASUN SMG II ESPHome](https://github.com/robgt978/Easun-SMG-II-11Kw-esphome-) | robgt978 |
| [Tailscale](https://tailscale.com/) | Tailscale Inc. |
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

<p align="center">Feito por <a href="https://github.com/gustavx404">gustavx404</a></p>
