#!/usr/bin/env bash
# ==============================================================================
# checar-novidades.sh — Modo avaliação: SÓ LÊ. Não troca branch, não mexe na VPS.
#
# Responde, com dado e não com opinião:
#   1. qual versão roda de verdade na VPS (pelo `revision` da imagem) e qual é a
#      última release estável do upstream;
#   2. o que mudou entre as duas — do CHANGELOG, com a seção "⚠️ Requer atenção"
#      na íntegra (é onde estão os avisos que o `update.sh` manda ler);
#   3. se há migração/baseline, mudança na versão pinada do Supabase
#      (SUPABASE_REF — na VPS single-server isso é um Supabase a atualizar) e
#      mudança em Caddyfile/compose/kit (onde moram as customizações da Astra);
#   4. quanto o fork diverge do upstream.
#
# Uso (na raiz do clone do fork, na máquina de trabalho):
#   bash .agents/skills/deskcomm-atualizar/scripts/checar-novidades.sh [--alvo vX.Y.Z] [--instalada vX.Y.Z] [--sem-vps]
#
# --alvo        compara contra essa tag do upstream (padrão: última release estável)
# --instalada   diz a versão instalada à mão (padrão: lê a imagem do app na VPS)
# --sem-vps     não tenta o ssh (usa o HEAD local como "instalado")
# VPS_SSH       destino ssh (padrão: vps-crm); VPS_APP (padrão: deskcommcrm-app-1)
# ==============================================================================
set -u

RAIZ="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$RAIZ" || exit 1

ALVO=""; INSTALADA=""; USAR_VPS=1
while [ $# -gt 0 ]; do
  case "$1" in
    --alvo) shift; ALVO="${1:-}" ;;
    --instalada) shift; INSTALADA="${1:-}" ;;
    --sem-vps) USAR_VPS=0 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "opção desconhecida: $1" >&2; exit 2 ;;
  esac
  shift
done

c_cyn() { printf "\033[0;36m%s\033[0m\n" "$*"; }
c_grn() { printf "\033[0;32m%s\033[0m\n" "$*"; }
c_ylw() { printf "\033[0;33m%s\033[0m\n" "$*"; }
c_red() { printf "\033[0;31m%s\033[0m\n" "$*"; }
c_bld() { printf "\033[1m%s\033[0m\n" "$*"; }

UPSTREAM_URL="https://github.com/melgarafael/DeskcommCRM.git"
UPSTREAM_SLUG="melgarafael/DeskcommCRM"
VPS_SSH="${VPS_SSH:-vps-crm}"
VPS_APP="${VPS_APP:-deskcommcrm-app-1}"

git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL" 2>/dev/null || true
printf "\n"; c_cyn "==> Consultando o repositório oficial (upstream)..."
git fetch upstream main --tags --quiet 2>/dev/null || { c_red "Erro ao falar com o upstream. Confira a internet."; exit 1; }

# ── 1. Versão alvo: a ÚLTIMA RELEASE publicada, não a maior tag nem o topo da main ──
if [ -z "$ALVO" ] && command -v gh >/dev/null 2>&1; then
  ALVO="$(gh release list -R "$UPSTREAM_SLUG" --exclude-pre-releases --limit 1 --json tagName -q '.[0].tagName' 2>/dev/null || true)"
fi
[ -n "$ALVO" ] || ALVO="$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)"
git rev-parse --verify --quiet "${ALVO}^{commit}" >/dev/null || { c_red "Não achei a tag $ALVO."; exit 1; }

# ── 2. Versão instalada: pelo commit da imagem que ROda na VPS ──────────────────
REV=""; ORIGEM_INST=""
if [ -z "$INSTALADA" ] && [ "$USAR_VPS" = 1 ]; then
  REV="$(ssh -o BatchMode=yes -o ConnectTimeout=8 "$VPS_SSH" \
    "docker inspect $VPS_APP --format '{{index .Config.Labels \"org.opencontainers.image.revision\"}}'" 2>/dev/null || true)"
  [ -n "$REV" ] && git cat-file -e "${REV}^{commit}" 2>/dev/null && ORIGEM_INST="imagem do app na VPS (commit ${REV:0:9})"
fi
if [ -n "$INSTALADA" ]; then
  REV="$(git rev-parse --verify --quiet "${INSTALADA}^{commit}" || true)"; ORIGEM_INST="informada à mão"
elif [ -z "$REV" ] || [ -z "$ORIGEM_INST" ]; then
  REV="$(git rev-parse HEAD)"; ORIGEM_INST="HEAD local (a VPS não respondeu; pode estar defasado)"
fi
# Versão do upstream que o commit instalado já contém (a maior tag alcançável a partir dele).
INST_TAG="$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --merged "$REV" --sort=-v:refname 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)"
[ -n "$INST_TAG" ] || INST_TAG="(nenhuma)"

PENDENTES="$(git rev-list --count "$REV..$ALVO" 2>/dev/null || echo "?")"
PROPRIOS="$(git rev-list --count "$ALVO..$REV" 2>/dev/null || echo "?")"

c_bld "=========================================================="
c_bld "     STATUS DE VERSÃO — DESKCOMM CRM (fork da Astra)"
c_bld "=========================================================="
printf "  • Instalada (base upstream): %s   [%s]\n" "$INST_TAG" "$ORIGEM_INST"
printf "  • Última release estável:    %s\n" "$ALVO"
printf "  • Commits do upstream pendentes: %s | commits só do fork: %s\n" "$PENDENTES" "$PROPRIOS"
c_bld "----------------------------------------------------------"

if [ "$INST_TAG" = "$ALVO" ] || [ "$PENDENTES" = "0" ]; then
  c_grn "✓ Já está na versão mais recente do upstream."; printf "\n"; exit 0
fi

# ── 3. CHANGELOG das versões no meio ─────────────────────────────────────────────
printf "\n"; c_cyn "==> O que mudou (CHANGELOG, de $INST_TAG até $ALVO):"
CHG="$(git show "$ALVO:CHANGELOG.md" 2>/dev/null || true)"
if [ -z "$CHG" ]; then c_ylw "  (CHANGELOG.md não encontrado nessa tag)"; else
  VERS="$(printf '%s\n' "$CHG" | grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' | tr -d '#[] ')"
  BASE="${INST_TAG#v}"; TOPO="${ALVO#v}"
  for v in $(printf '%s\n' "$VERS" | sort -V); do
    # versão > instalada e <= alvo
    [ "$(printf '%s\n%s\n' "$BASE" "$v" | sort -V | head -1)" = "$v" ] && continue
    [ "$(printf '%s\n%s\n' "$v" "$TOPO" | sort -V | head -1)" = "$v" ] || continue
    printf "\n"; c_bld "── v$v"
    printf '%s\n' "$CHG" | awk -v ver="$v" '
      $0 ~ "^## \\[" ver "\\]" {dentro=1; next}
      dentro && /^## \[/ {exit}
      dentro {print}' > /tmp/.chg_sec.$$
    ATENCAO="$(awk '/^### ⚠️ Requer atenção/{f=1;next} /^### /{f=0} f' /tmp/.chg_sec.$$ | sed '/^[[:space:]]*$/d')"
    if [ -n "$ATENCAO" ]; then c_ylw "  ⚠️ REQUER ATENÇÃO:"; printf '%s\n' "$ATENCAO" | cut -c1-400 | sed 's/^/    /'; fi
    ADIC="$(awk '/^### Adicionado/{f=1;next} /^### /{f=0} f && /^- \*\*/' /tmp/.chg_sec.$$ | sed -E 's/^- \*\*([^*]*)\*\*.*/\1/' | cut -c1-150)"
    CORR="$(awk '/^### Corrigido/{f=1;next} /^### /{f=0} f && /^- \*\*/' /tmp/.chg_sec.$$ | wc -l | tr -d ' ')"
    [ -n "$ADIC" ] && { printf "  Adicionado:\n"; printf '%s\n' "$ADIC" | head -8 | sed 's/^/    • /'; }
    printf "  Corrigido: %s item(ns)\n" "$CORR"
    rm -f /tmp/.chg_sec.$$
  done
fi

# ── 4. Banco, Supabase pinado e arquivos onde moram as customizações ───────────
printf "\n"; c_cyn "==> Banco de dados e infraestrutura:"
MIG="$(git diff --name-only "$REV..$ALVO" -- supabase/migrations/ supabase/baseline.sql 2>/dev/null | wc -l | tr -d ' ')"
NOVAS="$(git diff --name-only --diff-filter=A "$REV..$ALVO" -- supabase/migrations/ 2>/dev/null | wc -l | tr -d ' ')"
if [ "$MIG" -gt 0 ]; then c_ylw "  ⚠ Banco: $NOVAS migration(ns) nova(s); $MIG arquivo(s) de schema mudaram (baseline.sql inclusive)."
else c_grn "  ✓ Banco: nenhuma mudança de schema."; fi

REF_MUDOU="$(git diff "$REV..$ALVO" -- hostgator-setup-kit/_common.sh 2>/dev/null | grep -E '^[+-]SUPABASE_REF=' || true)"
if [ -n "$REF_MUDOU" ]; then
  c_red "  ⚠ SUPABASE_REF mudou — esta versão pede atualizar o Supabase self-hosted da VPS:"
  printf '%s\n' "$REF_MUDOU" | sed 's/^/      /'
  printf "      (o update.sh faz isso sozinho; o deploy manual da skill NÃO: pare e decida com o Juta.)\n"
else c_grn "  ✓ Versão pinada do Supabase self-hosted: sem mudança."; fi

TOCADOS="$(git diff --name-only "$REV..$ALVO" -- 'Caddyfile*' 'docker-compose*.yml' hostgator-setup-kit/ Dockerfile 2>/dev/null)"
if [ -n "$TOCADOS" ]; then
  c_ylw "  ⚠ Arquivos de infraestrutura/kit alterados no upstream (conferir contra as customizações da Astra):"
  printf '%s\n' "$TOCADOS" | head -15 | sed 's/^/      - /'
  [ "$(printf '%s\n' "$TOCADOS" | wc -l)" -gt 15 ] && printf "      … e mais.\n"
else c_grn "  ✓ Caddyfile/compose/kit/Dockerfile: sem mudança no upstream."; fi

# ── 5. Divergência do fork ──────────────────────────────────────────────────────
printf "\n"; c_cyn "==> Customizações da Astra (o que o merge precisa preservar):"
MB="$(git merge-base "$ALVO" main 2>/dev/null || true)"
if [ -n "$MB" ]; then
  printf "  %s arquivo(s) do fork diferem do upstream:\n" "$(git diff --name-only "$MB" main | wc -l | tr -d ' ')"
  git diff --name-status --no-renames "$MB" main | head -12 | sed 's/^/    /'
fi

printf "\n"; c_bld "=========================================================="
c_grn "Pronto para o Checkpoint 1: avalie acima (principalmente ⚠️)."
c_bld "=========================================================="; printf "\n"
