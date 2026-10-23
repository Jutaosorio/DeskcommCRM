#!/usr/bin/env bash
# ==============================================================================
# custodia.sh — Depois do merge do upstream na branch de sync: o que é do fork
# sobreviveu? E o código ainda passa nos gates?
#
# Uso (na raiz do clone, JÁ na branch sync/upstream-vX.Y.Z com o merge feito):
#   bash .agents/skills/atualizar-crm-custom/scripts/custodia.sh [--testes] [--alvo vX.Y.Z]
#
# --testes   roda também typecheck + lint + test:unit (e test:shell se kit/compose
#            mudou). O CÓDIGO DE SAÍDA é a autoridade, não o rodapé nem o grep.
# --alvo     ref do upstream que foi mesclada (padrão: upstream/main)
# CUSTODIA_BASE   ref do fork ANTES do merge (padrão: FORK_BASE da config, ou main)
#
# Nenhuma lista escrita à mão do que "é do fork": tudo sai do git.
#   A. ARQUIVOS: todo arquivo em que o fork difere do upstream (git diff do ponto de
#      encontro até a base do fork) precisa ter sobrevivido ao merge. Criado pelo fork
#      e sumiu = falha. Alterado pelo fork e hoje idêntico ao upstream = aviso.
#   B. LINHAS: dentro dos arquivos que sobreviveram, as linhas que o fork acrescentou
#      continuam lá? Um merge pode manter o arquivo e levar embora a customização.
#      TODAS sumidas = falha; algumas = aviso (o upstream pode ter reescrito a linha).
#   C. INSTÂNCIA (opcional): cada .astra/local/custodia.d/*.sh é lido aqui, para o
#      que só esta instalação sabe (um bloco de proxy, por exemplo). Fora do git.
# ==============================================================================
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$DIR/_lib.sh"
carregar_instancia
cd "$RAIZ" || exit 1

TESTES=0; ALVO="upstream/$UPSTREAM_BRANCH"; BASE="${CUSTODIA_BASE:-$FORK_BASE}"
while [ $# -gt 0 ]; do
  case "$1" in
    --testes) TESTES=1 ;;
    --alvo) shift; ALVO="${1:-upstream/$UPSTREAM_BRANCH}" ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "opção desconhecida: $1" >&2; exit 2 ;;
  esac
  shift
done
TMPD="${TMPDIR:-/tmp}"
WORK="$(mktemp)"; trap 'rm -f "$WORK" "$WORK.2"' EXIT

printf "\n"; c_bld "==> Custódia das customizações do fork (base: $BASE; upstream: $ALVO)"

git rev-parse --verify --quiet "${ALVO}^{commit}" >/dev/null || { c_red "ref $ALVO não existe (rode checar-novidades.sh antes)"; exit 2; }
git rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null || { c_red "ref $BASE não existe"; exit 2; }

# ── 1. Marcadores de conflito ───────────────────────────────────────────────────
c_bld "1. Marcadores de conflito do Git"
CONFLITOS="$(git grep -En '^(<<<<<<<|=======$|>>>>>>>)' -- ':!*.test.ts' ':!*.spec.ts' ':!*.json' ':!*.md' ':!*.snap' 2>/dev/null || true)"
if [ -n "$CONFLITOS" ]; then falha "conflito de merge sem resolver:"; printf '%s\n' "$CONFLITOS" | head -10 | sed 's/^/      /'; else ok "nenhum marcador de conflito"; fi

MB="$(git merge-base "$ALVO" "$BASE" 2>/dev/null || true)"

# ── 2. Camada A: o que o fork mudou em relação ao upstream sobreviveu? ─────────
c_bld "2. Arquivos do fork vs. resultado do merge (derivado do git)"
if [ -z "$MB" ]; then aviso "sem ponto de encontro entre $ALVO e $BASE: camadas A e B puladas"; else
  PERDIDOS=0; TOTAL=0
  while IFS=$'\t' read -r st arq; do
    [ -z "$arq" ] && continue
    TOTAL=$((TOTAL + 1))
    case "$st" in
      A) [ -e "$arq" ] || { falha "arquivo CRIADO pelo fork sumiu: $arq"; PERDIDOS=$((PERDIDOS + 1)); } ;;
      M)
        a="$(git rev-parse -q --verify "HEAD:$arq" 2>/dev/null || true)"
        b="$(git rev-parse -q --verify "${ALVO}:$arq" 2>/dev/null || true)"
        if [ -z "$a" ]; then falha "arquivo ALTERADO pelo fork não existe mais: $arq"; PERDIDOS=$((PERDIDOS + 1))
        elif [ -n "$b" ] && [ "$a" = "$b" ]; then aviso "idêntico ao upstream (customização perdida, ou adotada por eles?): $arq"; fi ;;
    esac
  done < <(git diff --name-status --no-renames "$MB" "$BASE")
  [ "$PERDIDOS" -eq 0 ] && ok "$TOTAL arquivo(s) do fork conferido(s); nenhum sumiu"

  # ── 3. Camada B: as linhas do fork dentro dos arquivos que ficaram ───────────
  c_bld "3. Linhas acrescentadas pelo fork continuam nos arquivos"
  LINHAS_PERDIDAS=0; ARQ_COM_PERDA=0
  while IFS= read -r arq; do
    [ -n "$arq" ] || continue
    case "$arq" in *.lock|pnpm-lock.yaml|package-lock.json|CHANGELOG.md|*.png|*.jpg|*.ico|*.svg|*.woff*|*.snap) continue ;; esac
    git cat-file -e "HEAD:$arq" 2>/dev/null || continue            # sumiu: a camada A já falou
    # Linhas que o fork acrescentou: sem CR, sem as curtas ou só de pontuação (`}`, `)`…).
    git diff -U0 --no-renames "$MB" "$BASE" -- "$arq" | grep -E '^\+[^+]' | sed 's/^+//; s/\r$//' \
      | awk 'length($0) >= 6 && $0 ~ /[[:alnum:]]/' > "$WORK"
    N="$(wc -l < "$WORK" | tr -d ' ')"; [ "$N" -gt 0 ] || continue
    git show "HEAD:$arq" 2>/dev/null | sed 's/\r$//' > "$WORK.2"
    FALTAM="$(awk 'NR==FNR{a[$0]=1;next} !($0 in a)' "$WORK.2" "$WORK" | wc -l | tr -d ' ')"
    [ "$FALTAM" -gt 0 ] || continue
    ARQ_COM_PERDA=$((ARQ_COM_PERDA + 1)); LINHAS_PERDIDAS=$((LINHAS_PERDIDAS + FALTAM))
    if [ "$FALTAM" -eq "$N" ] && [ "$N" -ge 2 ]; then falha "a customização INTEIRA do fork sumiu de $arq ($N linha(s))"
    elif [ "$ARQ_COM_PERDA" -le 12 ]; then aviso "$FALTAM de $N linha(s) do fork não estão mais em $arq (reescritas pelo upstream? confira)"; fi
  done < <(git diff --name-only --diff-filter=M --no-renames "$MB" "$BASE")
  [ "$ARQ_COM_PERDA" -eq 0 ] && ok "todas as linhas acrescentadas pelo fork estão presentes"
  [ "$ARQ_COM_PERDA" -gt 12 ] && aviso "…e mais $((ARQ_COM_PERDA - 12)) arquivo(s) com linhas ausentes ($LINHAS_PERDIDAS no total)"
fi

# ── 4. Camada C: o que só esta instância sabe (opcional, fora do git) ──────────
if ls "$ASTRA_LOCAL"/custodia.d/*.sh >/dev/null 2>&1; then
  c_bld "4. Verificações da instância ($ASTRA_LOCAL/custodia.d)"
  for f in "$ASTRA_LOCAL"/custodia.d/*.sh; do
    # shellcheck disable=SC1090
    . "$f"
  done
fi

# ── 5. Gates (opcional, mas é o que a skill chama de "teste") ──────────────────
if [ "$TESTES" -eq 1 ]; then
  c_bld "5. Gates do código (o exit code decide)"
  if [ ! -d node_modules ]; then
    falha "node_modules ausente: rode 'pnpm install --frozen-lockfile' antes de --testes"
  elif [ -f .env ] || [ -f .env.local ]; then
    # Os testes carregam .env/.env.local: com o .env da produção eles leem chaves
    # e serviços reais. O lugar dos testes é o clone da máquina de trabalho, sem
    # .env — e a prova é o CI.
    falha "há .env/.env.local nesta pasta: não rodo testes aqui (é a VPS?). Use o clone da máquina de trabalho, sem .env, ou deixe o CI da PR decidir"
  else
    rodar() {  # rodar <rótulo> <comando...>
      local rot="$1"; shift
      "$@" < /dev/null > "$TMPD/custodia-$rot.log" 2>&1; local rc=$?   # </dev/null: nenhum teste espera teclado
      if [ $rc -eq 0 ]; then ok "$rot (exit 0)"; else falha "$rot falhou (exit $rc) — ver $TMPD/custodia-$rot.log"; grep -aE "^ *(Test Files|Tests|Errors) " "$TMPD/custodia-$rot.log" | tail -3 | sed 's/^/      /'; fi
    }
    gate() {  # gate <rótulo> <script do package.json> <comando...> — script ausente é aviso, não verde falso
      local rot="$1" script="$2"; shift 2
      if tem_script_npm "$script"; then rodar "$rot" "$@"; else aviso "sem script '$script' no package.json: $rot não rodou"; fi
    }
    gate typecheck typecheck env NODE_OPTIONS=--max-old-space-size=6144 pnpm typecheck
    gate lint lint pnpm lint
    gate test-unit test:unit pnpm test:unit
    if git diff --name-only "$BASE" HEAD -- hostgator-setup-kit/ 'docker-compose*.yml' 'Caddyfile*' Dockerfile | grep -q .; then
      gate test-shell test:shell pnpm test:shell
    else ok "kit/compose/Caddy/Dockerfile sem mudança: test:shell dispensado"; fi
  fi
else
  printf "\n"; aviso "gates (typecheck/lint/test:unit) NÃO rodados. Use --testes, ou deixe o CI da PR decidir (ver SKILL.md, Checkpoint 2)."
fi

printf "\n"
if [ "$FALHAS" -eq 0 ]; then
  c_bld "=========================================================="
  c_grn "✓ Custódia OK ($AVISOS aviso(s)). Pode ir para a aprovação do merge."
  c_bld "=========================================================="; printf "\n"; exit 0
else
  c_bld "=========================================================="
  c_red "✗ Custódia reprovou: $FALHAS falha(s), $AVISOS aviso(s). Pare na branch de sync."
  c_bld "=========================================================="; printf "\n"; exit 1
fi
