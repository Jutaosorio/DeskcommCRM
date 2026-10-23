#!/usr/bin/env bash
# ==============================================================================
# checar-novidades.sh — Modo avaliação: SÓ LÊ. Não troca branch, não mexe na VPS.
#
# Responde, com dado e não com opinião:
#   1. qual versão roda de verdade na VPS (pelo rótulo `revision` da imagem) e qual
#      é a última release estável do upstream;
#   2. o que mudou entre as duas — do CHANGELOG, com a seção "Requer atenção" na
#      íntegra (é onde estão os avisos que o `update.sh` do upstream manda ler);
#   3. se há migração/baseline, mudança na versão pinada do Supabase (SUPABASE_REF)
#      e mudança em Caddyfile/compose/kit (onde moram as customizações de infra);
#   4. quanto o fork diverge do upstream.
#
# Uso (na raiz do clone do fork, na máquina de trabalho):
#   bash .agents/skills/atualizar-crm-custom/scripts/checar-novidades.sh [--alvo vX.Y.Z] [--instalada vX.Y.Z] [--sem-vps]
#
# --alvo        compara contra essa tag do upstream (padrão: última release estável)
# --instalada   diz a versão instalada à mão (padrão: lê a imagem do app na VPS)
# --sem-vps     não tenta o ssh (usa o HEAD local como "instalado")
# Config da instância (VPS_SSH, VPS_PREFIXO, UPSTREAM_SLUG…): .astra/local/instancia.env
# ==============================================================================
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$DIR/_lib.sh"
carregar_instancia
cd "$RAIZ" || exit 1

ALVO=""; INSTALADA=""; USAR_VPS=1
while [ $# -gt 0 ]; do
  case "$1" in
    --alvo) shift; ALVO="${1:-}" ;;
    --instalada) shift; INSTALADA="${1:-}" ;;
    --sem-vps) USAR_VPS=0 ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "opção desconhecida: $1" >&2; exit 2 ;;
  esac
  shift
done

VPS_SSH="${VPS_SSH:-}"
VPS_APP="${VPS_APP:-${VPS_PREFIXO:-deskcommcrm}-app-1}"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT

git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL" 2>/dev/null || true
printf "\n"; c_cyn "==> Consultando o repositório oficial (upstream)..."
git fetch upstream "$UPSTREAM_BRANCH" --tags --quiet 2>/dev/null || { c_red "Erro ao falar com o upstream. Confira a internet."; exit 1; }
SLUG="$(slug_do_upstream)"

# ── 1. Versão alvo: a ÚLTIMA RELEASE publicada, não a maior tag nem o topo da main ──
if [ -z "$ALVO" ] && [ -n "$SLUG" ] && command -v gh >/dev/null 2>&1; then
  ALVO="$(gh release list -R "$SLUG" --exclude-pre-releases --limit 1 --json tagName -q '.[0].tagName' 2>/dev/null || true)"
fi
[ -n "$ALVO" ] || ALVO="$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)"
[ -n "$ALVO" ] || { c_red "Não achei nenhuma release (tag vX.Y.Z) no upstream."; exit 1; }
git rev-parse --verify --quiet "${ALVO}^{commit}" >/dev/null || { c_red "Não achei a tag $ALVO."; exit 1; }

# ── 2. Versão instalada: pelo commit da imagem que ROda na VPS ──────────────────
REV=""; ORIGEM_INST=""
LABEL='{{index .Config.Labels "org.opencontainers.image.revision"}}'
if [ -z "$INSTALADA" ] && [ "$USAR_VPS" = 1 ]; then
  # Rodando na própria VPS o contêiner é local: o ssh para si mesma falharia.
  command -v docker >/dev/null 2>&1 && REV="$(docker inspect "$VPS_APP" --format "$LABEL" 2>/dev/null || true)"
  if [ -z "$REV" ] && [ -n "$VPS_SSH" ]; then
    REV="$(ssh -o BatchMode=yes -o ConnectTimeout=8 "$VPS_SSH" "docker inspect $VPS_APP --format '$LABEL'" 2>/dev/null || true)"
  fi
  if [ -n "$REV" ] && git cat-file -e "${REV}^{commit}" 2>/dev/null; then ORIGEM_INST="imagem do app na VPS (commit ${REV:0:9})"; else REV=""; fi
fi
if [ -n "$INSTALADA" ]; then
  REV="$(git rev-parse --verify --quiet "${INSTALADA}^{commit}" || true)"; ORIGEM_INST="informada à mão"
  [ -n "$REV" ] || { c_red "Não achei a versão informada: $INSTALADA."; exit 1; }
elif [ -z "$REV" ]; then
  REV="$(git rev-parse HEAD)"; ORIGEM_INST="HEAD local (a VPS não respondeu ou VPS_SSH não está na config; pode estar defasado)"
fi
# Versão do upstream que o commit instalado já contém (a maior tag alcançável a partir dele).
INST_TAG="$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --merged "$REV" --sort=-v:refname 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)"
[ -n "$INST_TAG" ] || INST_TAG="(nenhuma)"

PENDENTES="$(git rev-list --count "$REV..$ALVO" 2>/dev/null || echo "?")"
PROPRIOS="$(git rev-list --count "$ALVO..$REV" 2>/dev/null || echo "?")"

c_bld "=========================================================="
c_bld "     STATUS DE VERSÃO — DESKCOMM CRM (fork)"
c_bld "=========================================================="
printf "  • Instalada (base upstream): %s   [%s]\n" "$INST_TAG" "$ORIGEM_INST"
printf "  • Última release estável:    %s\n" "$ALVO"
printf "  • Commits do upstream pendentes: %s | commits só do fork: %s\n" "$PENDENTES" "$PROPRIOS"
c_bld "----------------------------------------------------------"

if [ "$INST_TAG" = "$ALVO" ] || [ "$PENDENTES" = "0" ]; then
  c_grn "✓ Já está na versão mais recente do upstream."; printf "\n"; exit 0
fi

# ── 3. CHANGELOG das versões no meio ─────────────────────────────────────────────
# O formato esperado (`## [x.y.z]`, `### …Requer atenção`, `### Adicionado/Corrigido`)
# é conferido por checar-contrato.sh. Se ele mudar, cai no aviso abaixo, não em silêncio.
printf "\n"; c_cyn "==> O que mudou (CHANGELOG, de $INST_TAG até $ALVO):"
CHG="$(git show "$ALVO:CHANGELOG.md" 2>/dev/null || true)"
if [ -z "$CHG" ]; then c_ylw "  (CHANGELOG.md não encontrado nessa tag)"; else
  VERS="$(printf '%s\n' "$CHG" | grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' | tr -d '#[] ')"
  [ -n "$VERS" ] || c_ylw "  ⚠ não reconheci nenhuma versão no CHANGELOG (formato mudou?). Leia-o à mão e rode checar-contrato.sh."
  BASE="${INST_TAG#v}"; [ "$INST_TAG" = "(nenhuma)" ] && BASE="0.0.0"; TOPO="${ALVO#v}"
  for v in $(printf '%s\n' "$VERS" | sort -V); do
    # versão > instalada e <= alvo
    [ "$(printf '%s\n%s\n' "$BASE" "$v" | sort -V | head -1)" = "$v" ] && continue
    [ "$(printf '%s\n%s\n' "$v" "$TOPO" | sort -V | head -1)" = "$v" ] || continue
    printf "\n"; c_bld "── v$v"
    printf '%s\n' "$CHG" | awk -v ver="$v" '
      $0 ~ "^## \\[" ver "\\]" {dentro=1; next}
      dentro && /^## \[/ {exit}
      dentro {print}' > "$TMP"
    ATENCAO="$(awk 'tolower($0) ~ /^### .*requer aten/{f=1;next} /^### /{f=0} f' "$TMP" | sed '/^[[:space:]]*$/d')"
    if [ -n "$ATENCAO" ]; then c_ylw "  ⚠️ REQUER ATENÇÃO:"; printf '%s\n' "$ATENCAO" | cut -c1-400 | sed 's/^/    /'; fi
    ADIC="$(awk '/^### Adicionado/{f=1;next} /^### /{f=0} f && /^- \*\*/' "$TMP" | sed -E 's/^- \*\*([^*]*)\*\*.*/\1/' | cut -c1-150)"
    CORR="$(awk '/^### Corrigido/{f=1;next} /^### /{f=0} f && /^- \*\*/' "$TMP" | wc -l | tr -d ' ')"
    [ -n "$ADIC" ] && { printf "  Adicionado:\n"; printf '%s\n' "$ADIC" | head -8 | sed 's/^/    • /'; }
    printf "  Corrigido: %s item(ns)\n" "$CORR"
  done
fi

# ── 4. Banco, Supabase pinado e arquivos de infraestrutura ────────────────────────
printf "\n"; c_cyn "==> Banco de dados e infraestrutura:"
MIG="$(git diff --name-only "$REV..$ALVO" -- supabase/migrations/ supabase/baseline.sql 2>/dev/null | wc -l | tr -d ' ')"
NOVAS="$(git diff --name-only --diff-filter=A "$REV..$ALVO" -- supabase/migrations/ 2>/dev/null | wc -l | tr -d ' ')"
if [ "$MIG" -gt 0 ]; then c_ylw "  ⚠ Banco: $NOVAS migration(ns) nova(s); $MIG arquivo(s) de schema mudaram (baseline.sql inclusive)."
else c_grn "  ✓ Banco: nenhuma mudança de schema."; fi

# Um "sem mudança" só vale se o instrumento ainda enxerga a variável: sem esta
# guarda, se o upstream renomear SUPABASE_REF o aviso mais importante some em verde.
KIT=hostgator-setup-kit/_common.sh
if git show "$ALVO:$KIT" 2>/dev/null | grep -qE '^[[:space:]]*SUPABASE_REF='; then
  REF_MUDOU="$(git diff "$REV..$ALVO" -- "$KIT" 2>/dev/null | grep -E '^[+-][[:space:]]*SUPABASE_REF=' || true)"
  if [ -n "$REF_MUDOU" ]; then
    c_red "  ⚠ SUPABASE_REF mudou — esta versão pede atualizar o Supabase self-hosted da VPS:"
    printf '%s\n' "$REF_MUDOU" | sed 's/^/      /'
    printf "      (o update.sh do kit faz isso sozinho; o deploy manual da skill NÃO: pare e decida com o dono.)\n"
  else c_grn "  ✓ Versão pinada do Supabase self-hosted: sem mudança."; fi
else
  c_ylw "  ⚠ Não consegui verificar a versão do Supabase: SUPABASE_REF não está em $KIT. Rode checar-contrato.sh."
fi

TOCADOS="$(git diff --name-only "$REV..$ALVO" -- 'Caddyfile*' 'docker-compose*.yml' hostgator-setup-kit/ Dockerfile 2>/dev/null)"
if [ -n "$TOCADOS" ]; then
  c_ylw "  ⚠ Arquivos de infraestrutura/kit alterados no upstream (conferir contra as customizações do fork):"
  printf '%s\n' "$TOCADOS" | head -15 | sed 's/^/      - /'
  [ "$(printf '%s\n' "$TOCADOS" | wc -l)" -gt 15 ] && printf "      … e mais.\n"
else c_grn "  ✓ Caddyfile/compose/kit/Dockerfile: sem mudança no upstream."; fi

# ── 5. Divergência do fork ──────────────────────────────────────────────────────
printf "\n"; c_cyn "==> Customizações do fork (o que o merge precisa preservar):"
MB="$(git merge-base "$ALVO" "$FORK_BASE" 2>/dev/null || true)"
if [ -n "$MB" ]; then
  printf "  %s arquivo(s) do fork diferem do upstream:\n" "$(git diff --name-only "$MB" "$FORK_BASE" | wc -l | tr -d ' ')"
  git diff --name-status --no-renames "$MB" "$FORK_BASE" | head -12 | sed 's/^/    /'
else c_ylw "  (sem ponto de encontro entre $ALVO e $FORK_BASE)"; fi

printf "\n"; c_bld "=========================================================="
c_grn "Pronto para o Checkpoint 1: avalie acima (principalmente ⚠️)."
c_bld "=========================================================="; printf "\n"
