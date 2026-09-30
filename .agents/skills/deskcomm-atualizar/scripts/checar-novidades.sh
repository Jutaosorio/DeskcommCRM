#!/usr/bin/env bash
# ==============================================================================
# checar-novidades.sh — Inspeciona upstream e resume as novidades e migrações
# ==============================================================================
set -e

# Garante que estamos na raiz do repositório
RAIZ="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$RAIZ"

# Cores para saída amigável
c_cyn() { printf "\033[0;36m%s\033[0m\n" "$*"; }
c_grn() { printf "\033[0;32m%s\033[0m\n" "$*"; }
c_ylw() { printf "\033[0;33m%s\033[0m\n" "$*"; }
c_red() { printf "\033[0;31m%s\033[0m\n" "$*"; }
c_bld() { printf "\033[1m%s\033[0m\n" "$*"; }

# 1. Garante que o remote upstream existe
UPSTREAM_URL="https://github.com/melgarafael/DeskcommCRM.git"
if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream "$UPSTREAM_URL" 2>/dev/null || true
fi

printf "\n"
c_cyn "==> Consultando novidades do repositório oficial (upstream)..."
git fetch upstream main --tags --quiet 2>/dev/null || {
  c_red "Erro ao conectar com o upstream. Verifique sua conexão à internet."
  exit 1
}

# 2. Informações de versão
HEAD_COMMIT="$(git rev-parse --short HEAD)"
UPSTREAM_COMMIT="$(git rev-parse --short upstream/main)"
LATEST_TAG="$(git describe --tags --abbrev=0 upstream/main 2>/dev/null || echo "sem-tag")"
CURRENT_TAG="$(git describe --tags --exact-match HEAD 2>/dev/null || git describe --tags --abbrev=0 2>/dev/null || echo "custom ($HEAD_COMMIT)")"

# 3. Contagem de commits
COMMITS_BEHIND="$(git rev-list --count HEAD..upstream/main 2>/dev/null || echo 0)"
COMMITS_AHEAD="$(git rev-list --count upstream/main..HEAD 2>/dev/null || echo 0)"

printf "\n"
c_bld "=========================================================="
c_bld "        RESUMO DE STATUS DE VERSÃO — DESKCOMM CRM        "
c_bld "=========================================================="
printf "  • Versão Atual Local:      %s (%s)\n" "$CURRENT_TAG" "$HEAD_COMMIT"
printf "  • Versão Mais Recente:     %s (%s)\n" "$LATEST_TAG" "$UPSTREAM_COMMIT"
printf "  • Commits do Upstream pendentes: %s\n" "$COMMITS_BEHIND"
printf "  • Commits Customizados locais:   %s\n" "$COMMITS_AHEAD"
c_bld "----------------------------------------------------------"

if [ "$COMMITS_BEHIND" -eq 0 ]; then
  c_grn "✓ Seu repositório já está sincronizado com a versão mais recente do upstream!"
  printf "\n"
  exit 0
fi

# 4. Checagem de Migrations de Banco de Dados
MIGRATIONS_CHANGED="$(git diff --name-only HEAD..upstream/main -- supabase/migrations/ supabase/baseline.sql 2>/dev/null | wc -l)"
printf "\n"
if [ "$MIGRATIONS_CHANGED" -gt 0 ]; then
  c_ylw "⚠ ATENÇÃO AO BANCO DE DADOS: Há novas migrações SQL ou alterações no baseline.sql!"
  printf "   Arquivos de banco afetados:\n"
  git diff --name-only HEAD..upstream/main -- supabase/migrations/ supabase/baseline.sql | sed 's/^/    - /'
  printf "   (O script update.sh cuidará de aplicar com backup automático no deploy.)\n"
else
  c_grn "✓ Banco de Dados: Nenhuma alteração de schema/migration detectada nesta versão."
fi

# 5. Lista de Mudanças / Commits Principais
printf "\n"
c_cyn "Principais commits incluídos no upstream:"
git log --oneline --no-merges -n 12 HEAD..upstream/main | sed 's/^/  • /'

printf "\n"
c_bld "=========================================================="
c_grn "Pronto para o Checkpoint 1: Avalie as novidades acima."
c_bld "=========================================================="
printf "\n"
