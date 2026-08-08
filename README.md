# homelab

Infraestrutura do homelab gerenciada via Docker Compose.

## Estrutura

```
compose/         Compose principal
homeassistant/   Configuracoes do Home Assistant
suricata/        IDS/IPS
monitoring/      Prometheus + Grafana
caddy/           Reverse proxy
forgejo/         Git self-hosted
scripts/         Scripts utilitarios
```

## Uso

```bash
cp compose/.env.example compose/.env
docker compose -f compose/compose.yaml up -d
```
