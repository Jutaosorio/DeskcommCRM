#!/usr/bin/env bash
# ==============================================================================
# checar-contrato.sh — O que esta skill ASSUME do upstream ainda é verdade?
#
# A skill depende de nomes que o upstream pode mudar sem aviso: funções do kit
# (`dc`, `enter_project`, `reaplicar_baseline`), arquivos de compose, o formato do
# CHANGELOG, o rótulo da imagem que diz qual commit roda. Sem esta checagem, uma
# mudança dessas aparece no MEIO do deploy. Com ela, aparece antes — dizendo qual
# suposição quebrou e em que arquivo da skill corrigir.
#
# Uso (na raiz do clone):
#   bash .agents/skills/atualizar-crm-custom/scripts/checar-contrato.sh [--ref <ref>]
#
# --ref   o que conferir (padrão: upstream/main se existir, senão HEAD). Pode ser uma tag.
# Falha (exit 1) só nas suposições que o deploy não sobrevive sem; as demais são aviso.
# Só LÊ o git: não troca de branch, não fala com a VPS.
# ==============================================================================
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$DIR/_lib.sh"
carregar_instancia
cd "$RAIZ" || exit 1

REF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ref) shift; REF="${1:-}" ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "opção desconhecida: $1" >&2; exit 2 ;;
  esac
  shift
done
if [ -z "$REF" ]; then
  git rev-parse --verify --quiet "upstream/$UPSTREAM_BRANCH^{commit}" >/dev/null && REF="upstream/$UPSTREAM_BRANCH" || REF="HEAD"
fi
git rev-parse --verify --quiet "${REF}^{commit}" >/dev/null || { c_red "ref $REF não existe"; exit 2; }

existe()   { git cat-file -e "$REF:$1" 2>/dev/null; }
conteudo() { git show "$REF:$1" 2>/dev/null || true; }
# `nome() {`, `nome () {`, `function nome {` — as três formas de declarar função em bash.
declara_funcao() { conteudo "$1" | grep -qE "^[[:space:]]*$2[[:space:]]*\(\)|^[[:space:]]*function[[:space:]]+$2([[:space:]{]|$)"; }

c_bld "==> Contrato da skill com o upstream (ref: $REF)"

c_bld "1. Kit de instalação (usado por references/deploy-vps.md)"
KIT=hostgator-setup-kit/_common.sh
if existe "$KIT"; then
  ok "$KIT existe"
  for f in dc enter_project reaplicar_baseline; do
    declara_funcao "$KIT" "$f" && ok "função $f declarada" \
      || falha "função $f NÃO está em $KIT — o deploy usa 'source $KIT && $f'. Corrigir: references/deploy-vps.md (passos 4 e 5) e vps-antes-depois.sh (rollback)"
  done
  conteudo "$KIT" | grep -qE '^[[:space:]]*SUPABASE_REF=' && ok "SUPABASE_REF declarado (checar-novidades.sh avisa quando muda)" \
    || aviso "SUPABASE_REF não está mais em $KIT: checar-novidades.sh não consegue avisar de troca do Supabase. Corrigir a seção 4 dele"
else
  falha "$KIT não existe: toda a parte de deploy da skill perdeu o chão"
fi
existe hostgator-setup-kit/backup.sh && ok "backup.sh do kit existe (backup padrão da skill)" \
  || aviso "hostgator-setup-kit/backup.sh sumiu: defina VPS_BACKUP_CMD na config da instância"

c_bld "2. Compose, imagem e banco"
existe docker-compose.prod.yml && ok "docker-compose.prod.yml existe" || falha "docker-compose.prod.yml não existe"
for s in app worker scheduler; do
  conteudo docker-compose.prod.yml | grep -qE "^  $s:" && ok "serviço $s no compose" \
    || aviso "serviço $s não está em docker-compose.prod.yml: ajuste VPS_SERVICOS na config da instância"
done
existe Dockerfile && ok "Dockerfile existe" || falha "Dockerfile não existe"
existe supabase/baseline.sql && ok "supabase/baseline.sql existe (é o que o deploy reaplica)" || falha "supabase/baseline.sql não existe"
# O rótulo vem do docker/metadata-action (que o põe por padrão) e o próprio kit do
# upstream o lê em diagnostico.sh — é o mesmo sinal que checar-novidades.sh usa.
{ conteudo Dockerfile; conteudo .github/workflows/publish-image.yml; conteudo hostgator-setup-kit/diagnostico.sh; } \
  | grep -qE "org.opencontainers.image.revision|docker/metadata-action" \
  && ok "imagem carimba o commit (org.opencontainers.image.revision): dá para saber a versão que roda na VPS" \
  || aviso "nada carimba 'org.opencontainers.image.revision' na imagem: checar-novidades.sh perde a versão instalada da VPS (use --instalada)"
existe .github/workflows/publish-image.yml && ok "publish-image.yml existe (a skill espera o build por ele)" \
  || aviso "publish-image.yml sumiu: o Checkpoint 2, passo 6, precisa de outro jeito de saber que as imagens foram publicadas"

c_bld "3. CHANGELOG (usado por checar-novidades.sh)"
if existe CHANGELOG.md; then
  CHG="$(conteudo CHANGELOG.md)"
  N="$(printf '%s\n' "$CHG" | grep -cE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]')"
  [ "$N" -gt 0 ] && ok "$N versão(ões) no formato '## [x.y.z]'" || falha "CHANGELOG sem '## [x.y.z]': checar-novidades.sh não separa versões. Corrigir a seção 3 dele"
  printf '%s\n' "$CHG" | awk '/^## \[[0-9]/{n++} n<=6' | grep -qiE '^### .*requer aten' \
    && ok "seção 'Requer atenção' presente nas versões recentes" \
    || aviso "nenhuma seção 'Requer atenção' nas 6 versões mais recentes (normal se não houve; suspeito se sempre)"
else falha "CHANGELOG.md não existe"; fi

c_bld "4. Saúde do app (usado por vps-antes-depois.sh depois)"
existe app/api/v1/health/route.ts && ok "rota /api/v1/health existe" || aviso "app/api/v1/health/route.ts sumiu: 'depois' confere essa rota"

c_bld "5. Versões e releases"
TAGS="$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' | grep -cE '^v[0-9]+\.[0-9]+\.[0-9]+$')"
[ "$TAGS" -gt 0 ] && ok "$TAGS tag(s) vX.Y.Z" || aviso "nenhuma tag vX.Y.Z (rode 'git fetch upstream --tags'); checar-novidades.sh depende delas"

printf "\n"
if [ "$FALHAS" -eq 0 ]; then
  c_bld "=========================================================="
  c_grn "✓ Contrato OK ($AVISOS aviso(s)). A skill pode seguir."
  c_bld "=========================================================="; exit 0
fi
c_bld "=========================================================="
c_red "✗ $FALHAS suposição(ões) da skill quebrou/quebraram ($AVISOS aviso(s))."
c_red "  NÃO atualize ainda: corrija a skill (references/contrato-com-upstream.md) e rode de novo."
c_bld "=========================================================="; exit 1
