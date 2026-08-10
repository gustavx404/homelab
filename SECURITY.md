# Seguranca

## Modelo de secrets

Todos os valores sensiveis vivem em `compose/sops-secrets.yaml`, **encriptado com
SOPS + age**. Nenhuma senha/token em texto plano e commitado.

- Fonte de verdade: `compose/sops-secrets.yaml` (encriptado)
- Template legivel para novos labs: `compose/sops-secrets.template.yaml`
- `.env` real e gerado localmente por `scripts/decrypt-secrets.sh` e nunca versionado
- Onboarding para forks: `bash scripts/init-sops.sh`

## Regras da chave age

A chave privada **nunca** deve existir fora da maquina que roda o lab:

- Local: `~/.config/sops/age/keys.txt` (gitignored — `keys.txt`, `*.agekey`)
- Faca backup dela **offline** (nao no repo): tar do README inclui `keys.txt` — guarde em cofre/senha-manager
- Se a chave vazar: gere uma nova, re-encripte `sops-secrets.yaml` e rotacione todos os tokens/senhas
- A chave publica (`age1...`) e commitada em `.sops.yaml` — isso e intencional e seguro

## O que pode / nao pode ir para o repo

| Permiti do | Proibido |
|---|---|
| `compose/sops-secrets.yaml` (encriptado) | `.env`, `compose/.env` |
| Configs, compose, scripts | `keys.txt`, `*.agekey`, `secrets.plain.*` |
| `.sops.yaml` (chave publica) | tokens/API keys em texto plano (mesmo em comentarios) |

## Cadeia de confianca

- Unico ponto de entrada HTTP: Traefik (TLS auto-assinado). Nenhum app web exposto direto.
- `no-new-privileges:true` nos containers; resource limits; healthchecks.
- Prometheus bound a `127.0.0.1`. MariaDB isolado na rede backend.
- CI (GitHub Actions) e **read-only**: yamllint, compose validate, trivy config/image.
  Nunca adicione job que decripte SOPS ou envie secrets para o runner.

## Hardening recomendado no GitHub

1. **Secret scanning** + **push protection**: Settings > Code security and analysis
2. **Branch protection** na `master` (requer review para push direto)
3. 2FA obrigatorio na conta; access tokens do GitHub com escopo minimo
4. Se quiser 100% de privacidade do inventario: torne o repo privado — mas os
   secrets **ja** estao protegidos por SOPS independentemente da visibilidade

## Reportando vulnerabilidades

Abra uma issue privada (Security > Report a vulnerability) ou contate o mantenedor
diretamente. Nao exponha detalhes em issues publicas antes do fix.

## Boas praticas de rotacao

| Item | Frequencia sugerida |
|---|---|
| Senha do admin do HA | semestral |
| `HA_WEBHOOK_ID` | anual ou ao suspeitar de vazamento |
| Chave age | imediatamente se qualquer copia for perdida/vazada |

## Prevencao de leaks em commits

Nunca coloque senhas, tokens ou API keys em mensagens de commit — o SOPS
protege o conteudo dos arquivos, mas mensagens de commit sao texto plano
permanente no historico.

Instale o hook pre-commit p/ bloquear secrets acidentalmente:

```bash
cat > .git/hooks/commit-msg << 'HOOK'
#!/bin/sh
if grep -iE '(password|passwd|token|secret|apikey)[=: ]+[^ ]{6,}' "$1" | grep -viE 'exemplo|example|template|changeme'; then
  echo "ERROR: possible secret in commit message" >&2
  exit 1
fi
HOOK
chmod +x .git/hooks/commit-msg
```
