#!/usr/bin/env bash
# _lib.sh — carregado (source) pelos scripts que rodam na máquina de trabalho.
# Não roda sozinho. Dá: cores, contadores ok/falha/aviso e a config da instância.
#
# A config da instância (ssh, pasta, domínio…) NUNCA mora no git: fica em
# `.astra/local/instancia.env` (ignorado). Modelo sem dados reais:
# assets/instancia.exemplo.env. Para apontar outro arquivo: ATUALIZAR_CRM_CONFIG=...

# Git Bash (Windows) reescreve argumentos que parecem caminho: `git show ref:.github/x.yml`
# vira lixo e o git responde "Not a valid object name" — o script concluiria "arquivo não
# existe". Medido ao testar checar-contrato.sh contra o upstream real.
export MSYS2_ARG_CONV_EXCL='*'

c_grn() { printf "\033[0;32m%s\033[0m\n" "$*"; }
c_ylw() { printf "\033[0;33m%s\033[0m\n" "$*"; }
c_red() { printf "\033[0;31m%s\033[0m\n" "$*"; }
c_cyn() { printf "\033[0;36m%s\033[0m\n" "$*"; }
c_bld() { printf "\033[1m%s\033[0m\n" "$*"; }

FALHAS=0; AVISOS=0
ok()    { c_grn "  ✓ $*"; }
falha() { c_red "  ✗ $*"; FALHAS=$((FALHAS + 1)); }
aviso() { c_ylw "  ⚠ $*"; AVISOS=$((AVISOS + 1)); }

carregar_instancia() {
  RAIZ="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  ASTRA_LOCAL="${ASTRA_LOCAL:-$RAIZ/.astra/local}"
  CONFIG="${ATUALIZAR_CRM_CONFIG:-$ASTRA_LOCAL/instancia.env}"
  if [ -f "$CONFIG" ]; then
    set -a; . "$CONFIG"; set +a   # arquivo do próprio dono, local
  fi
  UPSTREAM_SLUG="${UPSTREAM_SLUG:-melgarafael/DeskcommCRM}"
  UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/$UPSTREAM_SLUG.git}"
  UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
  FORK_BASE="${FORK_BASE:-main}"
}

# O slug "dono/repo" do remote `upstream` — vazio se ele não for do GitHub (o `gh`
# só serve para GitHub; um upstream em outro lugar usa só as tags).
slug_do_upstream() {
  git remote get-url upstream 2>/dev/null | sed -nE 's#.*github\.com[:/]([^/]+/[^/]+)$#\1#p' | sed 's#\.git$##'
}

# Existe script `$1` no package.json? (sem jq: o repo não garante jq na máquina)
tem_script_npm() { grep -qE "\"$1\"[[:space:]]*:" package.json 2>/dev/null; }
