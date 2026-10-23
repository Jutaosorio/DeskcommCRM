#!/usr/bin/env bash
# ==============================================================================
# na-vps.sh — roda vps-antes-depois.sh NA VPS, levando junto a config da instância.
#
# Uso (máquina de trabalho, na raiz do clone):
#   bash .agents/skills/atualizar-crm-custom/scripts/na-vps.sh antes [--sem-backup]
#   bash .agents/skills/atualizar-crm-custom/scripts/na-vps.sh depois [<foto na VPS>]
#   bash .agents/skills/atualizar-crm-custom/scripts/na-vps.sh rollback <foto na VPS> [--dry-run]
#   bash .agents/skills/atualizar-crm-custom/scripts/na-vps.sh sh '<comando>'     # comando solto, na pasta do projeto
#
# O motor é SEMPRE o deste repositório, enviado a cada chamada: não há cópia velha
# esquecida na VPS. A config vem de .astra/local/instancia.env (VPS_SSH, VPS_PROJETO…);
# cada .astra/local/verificacoes.d/*.sh vai junto e roda no fim de `depois`.
# VPS_SSH vazio ou "local": executa aqui mesmo (para quando você JÁ está na VPS).
# ==============================================================================
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$DIR/_lib.sh"
carregar_instancia
MOTOR="$DIR/vps-antes-depois.sh"

case "${1:-}" in
  antes|depois|rollback|sh) ;;
  -h|--help|"") sed -n '2,15p' "$0"; exit 0 ;;
  *) echo "modo desconhecido: $1" >&2; exit 2 ;;
esac

EXTRAS=""
if ls "$ASTRA_LOCAL"/verificacoes.d/*.sh >/dev/null 2>&1; then
  EXTRAS="$(cat "$ASTRA_LOCAL"/verificacoes.d/*.sh | base64 | tr -d '\n')"
fi

if [ "$1" = sh ]; then
  [ -n "${2:-}" ] || { echo "uso: sh '<comando>'" >&2; exit 2; }
  if [ -z "${VPS_SSH:-}" ] || [ "$VPS_SSH" = local ]; then ( cd "${VPS_PROJETO:-.}" && bash -c "$2" )
  else ssh -o BatchMode=yes "$VPS_SSH" "cd $(printf %q "${VPS_PROJETO:-.}") && $2"; fi
  exit $?
fi

# Variáveis para o motor (as que a config não define ficam vazias → o motor usa o padrão).
VARS=(
  "PROJETO=${VPS_PROJETO:-}" "MIGRACAO=${VPS_MIGRACAO:-}" "PREFIXO=${VPS_PREFIXO:-}"
  "SERVICOS=${VPS_SERVICOS:-}" "BACKUP_CMD=${VPS_BACKUP_CMD:-}" "BACKUP_LOG=${VPS_BACKUP_LOG:-}"
  "DOMINIO=${VPS_DOMINIO:-}" "EXTRAS_B64=$EXTRAS"
)
# Motor vazio nas variáveis em branco: `env X=` cria variável vazia; o motor usa ${X:-padrão}.

if [ -z "${VPS_SSH:-}" ] || [ "$VPS_SSH" = local ]; then
  env "${VARS[@]}" bash "$MOTOR" "$@"
else
  # O motor é gravado num arquivo temporário da VPS ANTES de rodar: com `bash -s`,
  # um comando filho que lesse a entrada padrão engoliria o resto do script.
  CMD='t=$(mktemp) && cat > "$t"'
  CMD="$CMD && env"
  for v in "${VARS[@]}"; do CMD="$CMD $(printf %q "$v")"; done
  CMD="$CMD bash \"\$t\""
  for a in "$@"; do CMD="$CMD $(printf %q "$a")"; done
  CMD="$CMD; rc=\$?; rm -f \"\$t\"; exit \$rc"
  ssh -o BatchMode=yes "$VPS_SSH" "$CMD" < "$MOTOR"
fi
