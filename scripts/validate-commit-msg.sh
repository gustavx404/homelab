#!/usr/bin/env bash
# validate-commit-msg.sh — Valida formato de commit pt-BR "Tipo:Texto"
# Uso: validate-commit-msg.sh <arquivo-mensagem>
# Called by pre-commit hook at commit-msg stage

set -uo pipefail

MSG_FILE="${1:-}"
if [[ -z "$MSG_FILE" || ! -f "$MSG_FILE" ]]; then
  echo "ERRO: Arquivo de mensagem não fornecido ou inexistente" >&2
  exit 1
fi

MSG="$(cat "$MSG_FILE" | head -1)"

# Padrão: Tipo:Texto (primeira linha)
# Tipos válidos: Fix, Docs, Feat, Refactor, Chore, Test, Build, CI, Perf, Style
REGEX='^(Fix|Docs|Feat|Refactor|Chore|Test|Build|CI|Perf|Style):.+'

if [[ ! "$MSG" =~ $REGEX ]]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "❌  FORMATO DE COMMIT INVÁLIDO"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Mensagem recebida: \"$MSG\""
  echo ""
  echo "Padrão obrigatório (pt-BR):"
  echo "  Tipo:Descrição curta do que foi feito"
  echo ""
  echo "Tipos válidos:"
  echo "  Fix       Correção de bug"
  echo "  Docs      Documentação (README, comentários, etc.)"
  echo "  Feat      Nova funcionalidade"
  echo "  Refactor  Refatoração (sem mudança de comportamento)"
  echo "  Chore     Tarefas de manutenção (deps, configs, etc.)"
  echo "  Test      Testes (adição/alteração)"
  echo "  Build     Sistema de build (Dockerfile, CI, etc.)"
  echo "  CI        Pipeline CI/CD"
  echo "  Perf      Melhoria de performance"
  echo "  Style     Formatação, lint, sem mudança lógica"
  echo ""
  echo "Exemplos válidos:"
  echo "  Fix:Corrigir healthcheck do suricata-stats"
  echo "  Docs:Atualizar README com serviços"
  echo "  Feat:Adicionar OmniRoute secrets ao template"
  echo "  Refactor:Remover referências Authentik obsoletas"
  echo "  Chore:Atualizar dependências do pre-commit"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 1
fi

exit 0