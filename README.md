# homelab

Infraestrutura do homelab gerenciada via Docker Compose com SOPS para secrets.

## Stack

| Servico | Descricao | Porta |
| --- | --- | --- |
| **Home Assistant** | Automacao residencial | `8123` |
| **MariaDB** | Banco de dados (recorder do HA) | interno |
| **ESPHome** | Firmware para dispositivos ESP | host |
| **Mumble** | Servidor VoIP | `64738` TCP+UDP |
| **Kali Linux** | Pentest/CTF (CLI) | interno |
| **Caddy** | Reverse proxy (TLS automatico) | `80`, `443` |
| **Forgejo** | Git self-hosted | `3001`, `2222` (SSH) |
| **Prometheus** | Metricas | `9090` (localhost) |
| **Grafana** | Dashboards | `3000` (localhost) |
| **Suricata** | IDS/IPS | host |

## Estrutura

```
compose/          Docker Compose + env + secrets
homeassistant/    Configuracoes do Home Assistant + ESPHome
caddy/            Reverse proxy (Caddyfile)
forgejo/          Git self-hosted
monitoring/       Prometheus + Grafana
suricata/         IDS/IPS (regras + config)
scripts/          Scripts utilitarios
data/             Volumes persistentes (gitignored)
```

## Pre-requisitos

```bash
# Docker + Compose
sudo apt install -y docker.io docker-compose-v2
sudo usermod -aG docker $USER

# SOPS (secrets encryption)
curl -LO https://github.com/getsops/sops/releases/download/v3.13.3/sops-v3.13.3.linux.amd64
sudo mv sops-v3.13.3.linux.amd64 /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops

# age (SOPS backend)
sudo apt install -y age

# yamllint (CI opcional)
sudo apt install -y yamllint
```

## Secrets: os 2 arquivos

| Arquivo | Funcao | Dados |
| --- | --- | --- |
| `compose/.env.example` | Template documentando todas as variaveis | **Fakes** (exemplo: `senha=changeme`) |
| `compose/sops-secrets.yaml` | Secrets reais encriptados com SOPS | **Reais** (senhas, localizacao) |

O fluxo: voce edita `sops-secrets.yaml` com seus valores reais, e o script `decrypt-secrets.sh` gera o `.env` (que nunca e commitado).

## Setup rapido

```bash
# 1. Instalar pre-requisitos (veja secao acima)

# 2. Gerar chave age e configurar SOPS
age-keygen -o ~/.config/sops/age/keys.txt
# Copie a public key para .sops.yaml

# 3. Editar secrets com valores reais
sops compose/sops-secrets.yaml

# 4. Decriptar secrets para .env
bash scripts/decrypt-secrets.sh

# 5. Subir os servicos
docker compose -f compose/compose.yaml up -d
```

## Secrets (SOPS)

Secrets sensiveis (senhas, tokens) sao armazenados encriptados com SOPS + age em `compose/sops-secrets.yaml`.

```bash
# Editar secrets
sops compose/sops-secrets.yaml

# Decriptar para .env
bash scripts/decrypt-secrets.sh

# Recriar .env apos edicao
sops compose/sops-secrets.yaml    # editar valores
bash scripts/decrypt-secrets.sh   # gerar .env
```

## Servicos

### Home Assistant + MariaDB

O recorder do Home Assistant usa MariaDB para persistencia mais rapida e confiavel que o SQLite padrao. O container do HA espera o healthcheck do MariaDB antes de iniciar.

### Mumble (Murmur)

Servidor VoIP open-source. Conecte com qualquer client Mumble em `<IP>:64738`.

```yaml
# compose/sops-secrets.yaml
MUMBLE_SUPERUSER_PASSWORD: "sua-senha-aqui"
```

Apos subir, logue como `SuperUser` com a senha definida para administrar o servidor.

### Kali Linux (CLI)

Container Kali oficial para pentest e CTF. Ferramentas como nmap, metasploit, hydra, etc. Acesso via `docker exec`:

```bash
# Entrar no container
docker exec -it kali bash

# Instalar ferramentas adicionais
apt update && apt install -y kali-tools-top10
```

O container ja tem `NET_RAW` e `NET_ADMIN` para scans de rede.

### Reverse Proxy (Caddy)

Caddy expoe os servicos web com TLS automatico (Let's Encrypt). Defina `DOMAIN` no `.env`:

```bash
DOMAIN=meuhomelab.duckdns.org
```

Rotas:
- `/` -> Home Assistant
- `/grafana/*` -> Grafana
- `/git/*` -> Forgejo

### Seguranca

- Servicos internos (Prometheus, Grafana) bindam apenas em `127.0.0.1`
- MariaDB acessivel apenas na rede interna `backend`
- Secrets encriptados com SOPS + age (nunca commitados em plaintext)
- `.env` no `.gitignore` (gerado via `decrypt-secrets.sh`)
- Suricata e ESPHome usam `network_mode: host` apenas quando necessario

### Backup

Volumes persistentes estao em `data/`. Recomendacao:

```bash
# Backup dos volumes
tar -czf backup-$(date +%Y%m%d).tar.gz data/

# Backup da chave age (CRITICO - sem ela nao decripta os secrets)
cp ~/.config/sops/age/keys.txt backup-age-key.txt
```

## CI/CD

GitHub Actions valida sintaxe YAML, compose, e faz scan de vulnerabilidades com Trivy em todo push e PR.
