<p align="center">
  <br>
  <samp>homelab</samp>
  <br><br>
  Infraestrutura auto-hospedada com Docker Compose. 11 servicos. Rede zero-confianca. IDS/IPS na borda.
  <br><br>
  <img src="https://img.shields.io/badge/CI-verde-10b981?style=flat-square" alt="ci">
  <img src="https://img.shields.io/badge/servicos-11-3b82f6?style=flat-square" alt="servicos">
  <img src="https://img.shields.io/badge/suricata-8-6b7280?style=flat-square" alt="suricata">
  <img src="https://img.shields.io/badge/secrets-sops-6b7280?style=flat-square" alt="secrets">
  <br><br>
</p>

---

```
                         Internet
                            │
                   ┌────────┴────────┐
                   │     OpenWrt      │  roteador de borda + CrowdSec bouncer
                   └────────┬────────┘
                            │  80 · 443
                   ┌────────┴────────┐
                   │    Traefik v3   │  proxy reverso · roteamento por path
                   │  /         HA   │
                   │  /grafana  Grafana
                   │  /git      Forgejo
                   └────────┬────────┘
                            │  rede backend · br-homelab
   ┌─────────┬────────┬─────┴─────┬────────┬─────────┐
   ▼         ▼        ▼           ▼        ▼         ▼
 mariadb   grafana  prometheus  forgejo  mumble   crowdsec
   └────────┴────────┴─────┬─────┴────────┴────│─────┘
                     rede host                  ▼
               suricata (eno1)   esphome    LAPI :8080
               + br-homelab      :6052      (→ OpenWrt)
```

---

### Instalacao rapida

```bash
# dependencias
curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh ./get-docker.sh
sudo apt install -y docker-compose-v2 age yamllint
curl -LO https://github.com/getsops/sops/releases/download/v3.13.3/sops-v3.13.3.linux.amd64
sudo install -m 755 sops-v3.13.3.linux.amd64 /usr/local/bin/sops

# gerar chave age → copiar chave publica para .sops.yaml
age-keygen -o ~/.config/sops/age/keys.txt

# editar secrets com valores reais
sops compose/sops-secrets.yaml

# decriptar → compose/.env
bash scripts/decrypt-secrets.sh

# subir tudo
docker compose -f compose/compose.yaml up -d
```

**Acesso** — roteamento por path, funciona com qualquer IP. Sem dependencia de DNS.

| path | servico |
|------|---------|
| `/` | Home Assistant |
| `/grafana/` | Grafana |
| `/git/` | Forgejo |

> TLS auto-assinado — aceitar no primeiro acesso.

---

### Servicos

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

### Estrutura do repositorio

```
compose/
├── compose.yaml        principal (inclui todos os stacks)
├── network.yaml        rede br-homelab + secrets
├── home.yaml           mariadb · homeassistant · esphome
├── security.yaml       suricata · crowdsec
├── monitoring.yaml     prometheus · grafana
├── services.yaml       traefik · forgejo · mumble · kali
├── .env.example        template
└── sops-secrets.yaml   secrets encriptados (SOPS + age)

traefik/                traefik.yml + dynamic.yml
suricata/               config + 12 assinaturas IDS
crowdsec/               acquis · profiles · scenarios · whitelist
homeassistant/          config HA + dispositivos ESPHome
monitoring/             configs prometheus + grafana
scripts/                decrypt-secrets · update-suricata-rules
data/                   volumes persistentes (gitignored)
```

Stacks individuais:

```bash
docker compose -f compose/network.yaml -f compose/security.yaml up -d
docker compose -f compose/network.yaml -f compose/home.yaml up -d
```

---

### IDS / IPS

Suricata monitora `eno1` + `br-homelab`. CrowdSec le `eve.json` em tempo real. 2 alertas em 60s disparam um ban de 6h propagado para o OpenWrt na borda da rede.

| assinatura | limite |
|-----------|--------|
| icmp echo | — (info) |
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

**Perfis CrowdSec** — cenario `homelab/scan-detection`:

| gatilho | duracao do ban |
|---------|---------------|
| primeira deteccao | 6 h |
| padrao de scan | 24 h |
| reincidente (≥3 eventos) | 48 h |

```bash
docker exec crowdsec cscli decisions list      # bans ativos
docker exec kali nmap -sS -p 1-100 <host>     # teste de deteccao
```

---

### Portas expostas

| porta | servico | motivo |
|-------|---------|--------|
| `22` | ssh | acesso administrativo |
| `80,443` | traefik | unico ponto de entrada http/s |
| `2222` | forgejo ssh | git push/pull |
| `6052` | esphome | rede host · mDNS |
| `64738` | mumble | protocolo voip |
| `8080` | crowdsec lapi | api do bouncer openwrt |

Prometheus e Grafana vinculados apenas em `127.0.0.1`. Nenhum app web exposto diretamente.

---

### Seguranca

grafana e prometheus em `127.0.0.1` · mariadb isolado na rede `backend` · secrets encriptados com SOPS + age · `.env` gitignored · `network_mode: host` apenas onde necessario · `no-new-privileges:true` nos containers host · healthchecks e resource limits em todos os 11 containers · CI yamllint + compose-validate + trivy config + trivy cve

---

### Backup

```bash
tar -czf backup-$(date +%Y%m%d).tar.gz data/
cp ~/.config/sops/age/keys.txt backup-age-key.txt
```

---

## Creditos

Este projeto utiliza e adapta trabalhos dos seguintes autores e projetos open-source:

| projeto | autor / organizacao | uso no homelab |
|---------|-------------------|----------------|
| [EASUN SMG II 11Kw ESPHome](https://github.com/robgt978/Easun-SMG-II-11Kw-esphome-) | **robgt978** | configuracao do inversor easun-4kw.yaml |
| [Suricata](https://suricata.io/) | **OISF** | motor de IDS/IPS com 12 regras customizadas |
| [CrowdSec](https://github.com/crowdsecurity/crowdsec) | **CrowdSec** | IPS comportamental integrado ao Suricata |
| [Mumble](https://github.com/mumble-voip/mumble) | **Mumble VoIP** | servidor de voz Ducks Server |
| [Traefik](https://github.com/traefik/traefik) | **Traefik Labs** | proxy reverso com TLS |
| [Forgejo](https://forgejo.org/) | **Forgejo** | git self-hosted |
| [ESPHome](https://esphome.io/) | **ESPHome** | firmware para dispositivos ESP32 |
| [Home Assistant](https://www.home-assistant.io/) | **Home Assistant** | automacao residencial |
| [Grafana](https://grafana.com/) | **Grafana Labs** | dashboards de monitoria |
| [Prometheus](https://prometheus.io/) | **Prometheus** | coleta de metricas |
| [MariaDB](https://mariadb.org/) | **MariaDB Foundation** | banco de dados do recorder |
| [SOPS](https://github.com/getsops/sops) | **Mozilla** | encriptacao de secrets |
| [age](https://github.com/FiloSottile/age) | **FiloSottile** | backend de encriptacao do SOPS |

---

<p align="center">
  <sub>feito com &lt;3 por <a href="https://github.com/gustavx404">gustavx404</a></sub>
</p>
