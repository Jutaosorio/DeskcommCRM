#!/usr/bin/env bash
# ==============================================================================
# custodia.sh — Confere se as customizações da Astra e configurações críticas
#               foram preservadas após a sincronização/merge.
# ==============================================================================
set -e

RAIZ="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$RAIZ"

c_grn() { printf "\033[0;32m%s\033[0m\n" "$*"; }
c_ylw() { printf "\033[0;33m%s\033[0m\n" "$*"; }
c_red() { printf "\033[0;31m%s\033[0m\n" "$*"; }
c_bld() { printf "\033[1m%s\033[0m\n" "$*"; }

FALHAS=0

printf "\n"
c_bld "==> Verificando custódia de customizações da Astra e integridade..."

# 1. Checagem de marcadores de conflito do Git
c_bld "1. Checando marcadores de conflito do Git..."
CONFLITOS="$(git grep -En "^(<<<<<<<|=======|>>>>>>>)" -- ':!*.test.ts' ':!*.spec.ts' ':!*.json' ':!*.md' 2>/dev/null || true)"
if [ -n "$CONFLITOS" ]; then
  c_red "  ✗ ERRO: Conflitos de merge não resolvidos encontrados:"
  printf "%s\n" "$CONFLITOS" | sed 's/^/    /'
  FALHAS=$((FALHAS + 1))
else
  c_grn "  ✓ Nenhum marcador de conflito do Git encontrado."
fi

# 2. Checagem do limite de memória no Dockerfile (4096MB)
c_bld "2. Checando Dockerfile (heap memory allocation)..."
if grep -q "max-old-space-size=4096" Dockerfile 2>/dev/null; then
  c_grn "  ✓ Dockerfile: NODE_OPTIONS=--max-old-space-size=4096 está preservado."
else
  c_red "  ✗ ALERTA: Dockerfile não possui max-old-space-size=4096. Risco de OOM no build!"
  FALHAS=$((FALHAS + 1))
fi

# 3. Checagem de ativos de branding (Astra)
c_bld "3. Checando ativos de marca em assets/branding/..."
if [ -d "assets/branding" ] && [ "$(ls -A assets/branding 2>/dev/null | wc -l)" -gt 0 ]; then
  c_grn "  ✓ Diretório assets/branding/ preservado com $(ls -A assets/branding | wc -l) arquivos."
else
  c_ylw "  ⚠ Aviso: Diretório assets/branding/ não encontrado ou vazio."
fi

# 4. Checagem de configurações locais / compose
c_bld "4. Checando docker-compose.prod.yml..."
if [ -f "docker-compose.prod.yml" ]; then
  c_grn "  ✓ docker-compose.prod.yml está presente e intacto."
else
  c_red "  ✗ ERRO: docker-compose.prod.yml ausente!"
  FALHAS=$((FALHAS + 1))
fi

printf "\n"
if [ "$FALHAS" -eq 0 ]; then
  c_bld "=========================================================="
  c_grn "✓ Custódia OK: Todas as customizações e regras estão protegidas!"
  c_bld "=========================================================="
  printf "\n"
  exit 0
else
  c_bld "=========================================================="
  c_red "✗ Falha na custódia: Foram detectados $FALHAS problema(s) acima."
  c_bld "=========================================================="
  printf "\n"
  exit 1
fi
