#!/usr/bin/env bash
# ==============================================================================
# custodia.sh — Depois do merge do upstream na branch de sync: o que é da Astra
# sobreviveu? E o código ainda passa nos gates?
#
# Uso (na raiz do clone, JÁ na branch sync/upstream-vX.Y.Z com o merge feito):
#   bash .agents/skills/deskcomm-atualizar/scripts/custodia.sh [--testes] [--alvo vX.Y.Z]
#
# --testes   roda também typecheck + lint + test:unit (e test:shell se kit/compose
#            mudou). O CÓDIGO DE SAÍDA é a autoridade, não o rodapé nem o grep.
# --alvo     ref do upstream que foi mesclada (padrão: upstream/main)
# CUSTODIA_BASE   ref do fork ANTES do merge (padrão: main)
#
# Duas camadas, e a primeira não é uma lista escrita à mão:
#   A. DERIVADA dos dados: todo arquivo em que o fork difere do upstream (git diff
#      do ponto de encontro até a `main` do fork) precisa ter sobrevivido ao merge.
#      Arquivo que o fork CRIOU e sumiu = falha. Arquivo que o fork ALTEROU e hoje é
#      idêntico ao do upstream = aviso (ou foi perdido, ou o upstream adotou).
#   B. ASSINATURAS conhecidas (abaixo): coisas que um merge pode derrubar sem dar
#      conflito e que já morderam. Quando a Astra criar customização nova que um
#      merge possa levar embora, acrescente aqui.
# ==============================================================================
set -u

RAIZ="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$RAIZ" || exit 1

TESTES=0; ALVO="upstream/main"; BASE="${CUSTODIA_BASE:-main}"
while [ $# -gt 0 ]; do
  case "$1" in
    --testes) TESTES=1 ;;
    --alvo) shift; ALVO="${1:-upstream/main}" ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "opção desconhecida: $1" >&2; exit 2 ;;
  esac
  shift
done

c_grn() { printf "\033[0;32m%s\033[0m\n" "$*"; }
c_ylw() { printf "\033[0;33m%s\033[0m\n" "$*"; }
c_red() { printf "\033[0;31m%s\033[0m\n" "$*"; }
c_bld() { printf "\033[1m%s\033[0m\n" "$*"; }
FALHAS=0; AVISOS=0
falha() { c_red "  ✗ $*"; FALHAS=$((FALHAS + 1)); }
aviso() { c_ylw "  ⚠ $*"; AVISOS=$((AVISOS + 1)); }
ok()    { c_grn "  ✓ $*"; }

printf "\n"; c_bld "==> Custódia das customizações da Astra (base do fork: $BASE; upstream: $ALVO)"

git rev-parse --verify --quiet "${ALVO}^{commit}" >/dev/null || { c_red "ref $ALVO não existe (rode checar-novidades.sh antes)"; exit 2; }
git rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null || { c_red "ref $BASE não existe"; exit 2; }

# ── 1. Marcadores de conflito ───────────────────────────────────────────────────
c_bld "1. Marcadores de conflito do Git"
CONFLITOS="$(git grep -En '^(<<<<<<<|=======$|>>>>>>>)' -- ':!*.test.ts' ':!*.spec.ts' ':!*.json' ':!*.md' ':!*.snap' 2>/dev/null || true)"
if [ -n "$CONFLITOS" ]; then falha "conflito de merge sem resolver:"; printf '%s\n' "$CONFLITOS" | head -10 | sed 's/^/      /'; else ok "nenhum marcador de conflito"; fi

# ── 2. Camada A: o que o fork mudou em relação ao upstream sobreviveu? ─────────
c_bld "2. Arquivos do fork vs. resultado do merge (derivado do git, sem lista fixa)"
MB="$(git merge-base "$ALVO" "$BASE" 2>/dev/null || true)"
if [ -z "$MB" ]; then aviso "sem ponto de encontro entre $ALVO e $BASE: camada A pulada"; else
  PERDIDOS=0; TOTAL=0
  while IFS=$'\t' read -r st arq; do
    [ -z "$arq" ] && continue
    TOTAL=$((TOTAL + 1))
    case "$st" in
      A) [ -e "$arq" ] || { falha "arquivo CRIADO pela Astra sumiu: $arq"; PERDIDOS=$((PERDIDOS + 1)); } ;;
      M)
        a="$(git rev-parse -q --verify "HEAD:$arq" 2>/dev/null || true)"
        b="$(git rev-parse -q --verify "${ALVO}:$arq" 2>/dev/null || true)"
        if [ -z "$a" ]; then falha "arquivo ALTERADO pela Astra não existe mais: $arq"; PERDIDOS=$((PERDIDOS + 1))
        elif [ -n "$b" ] && [ "$a" = "$b" ]; then aviso "idêntico ao upstream (customização perdida, ou adotada por eles?): $arq"; fi ;;
    esac
  done < <(git diff --name-status --no-renames "$MB" "$BASE")
  [ "$PERDIDOS" -eq 0 ] && ok "$TOTAL arquivo(s) do fork conferido(s); nenhum sumiu"
fi

# ── 3. Camada B: assinaturas conhecidas ────────────────────────────────────────
c_bld "3. Assinaturas conhecidas da Astra"
grep -q "max-old-space-size=4096" Dockerfile 2>/dev/null \
  && ok "Dockerfile: NODE_OPTIONS=--max-old-space-size=4096" \
  || falha "Dockerfile sem max-old-space-size=4096 (risco de falta de memória no build)"
[ -f docker-compose.prod.yml ] && ok "docker-compose.prod.yml presente" || falha "docker-compose.prod.yml ausente"
[ -f public/branding/astra-logo.png ] && ok "marca: public/branding/astra-logo.png" || falha "marca da Astra ausente (public/branding/astra-logo.png)"

# O Caddy da VPS também serve mcp.juta-os.com (MCPs de WhatsApp do Juta, projeto separado).
# Antes da v1.85 o bloco morava dentro dos DOIS Caddyfiles; a partir dela o lugar certo é
# caddy-sites/*.caddy (ponto de extensão oficial, fora do git: não trava o update.sh).
if git grep -q "mcp.juta-os.com" HEAD -- Caddyfile Caddyfile.single-server 2>/dev/null; then
  if [ -d caddy-sites ] || git grep -q "import /etc/caddy/sites" HEAD -- Caddyfile.single-server 2>/dev/null; then
    aviso "bloco mcp.juta-os.com ainda está dentro do Caddyfile, mas esta versão já tem caddy-sites/: MOVA para caddy-sites/mcp-juta-os.caddy na VPS e tire dos Caddyfiles (senão o update.sh trava por 'mudanças locais')"
  else
    ok "bloco mcp.juta-os.com presente nos Caddyfiles"
  fi
else
  if git grep -q "import /etc/caddy/sites" HEAD -- Caddyfile.single-server 2>/dev/null; then
    aviso "bloco mcp.juta-os.com não está nos Caddyfiles (esperado a partir da v1.85): confirme que a VPS tem caddy-sites/mcp-juta-os.caddy — o 'vps-antes-depois.sh depois' confere"
  else
    falha "bloco mcp.juta-os.com sumiu dos Caddyfiles e esta versão não tem caddy-sites/: os MCPs de WhatsApp sairiam do ar"
  fi
fi

# ── 4. Gates (opcional, mas é o que a skill chama de "teste") ──────────────────
if [ "$TESTES" -eq 1 ]; then
  c_bld "4. Gates do código (o exit code decide)"
  if [ ! -d node_modules ]; then
    falha "node_modules ausente: rode 'pnpm install --frozen-lockfile' antes de --testes"
  else
    rodar() {  # rodar <rótulo> <comando...>
      local rot="$1"; shift
      "$@" > "/tmp/custodia-$rot.log" 2>&1; local rc=$?
      if [ $rc -eq 0 ]; then ok "$rot (exit 0)"; else falha "$rot falhou (exit $rc) — ver /tmp/custodia-$rot.log"; grep -aE "^ *(Test Files|Tests|Errors) " "/tmp/custodia-$rot.log" | tail -3 | sed 's/^/      /'; fi
    }
    rodar typecheck pnpm typecheck
    rodar lint pnpm lint
    rodar test-unit pnpm test:unit
    if git diff --name-only "$BASE" HEAD -- hostgator-setup-kit/ 'docker-compose*.yml' 'Caddyfile*' Dockerfile | grep -q .; then
      rodar test-shell pnpm test:shell
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
