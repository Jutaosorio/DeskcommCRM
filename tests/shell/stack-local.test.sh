#!/usr/bin/env bash
# Guarda estática do perfil local: não chama Docker, Supabase nem lê .env.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/stack-local.sh"
COMPOSE="$ROOT/docker-compose.local.yml"

falhar() { printf 'stack-local: %s\n' "$*" >&2; exit 1; }
exigir() { grep -Fq -- "$1" "$2" || falhar "nao achei '$1' em $2"; }

exigir 'name: deskcomm-local' "$COMPOSE"
exigir '--confirm-local-data-loss' "$SCRIPT"
exigir 'WAHA_WEBHOOK_REQUIRE_SIGNATURE=true' "$SCRIPT"
exigir 'new URL(value)' "$SCRIPT"
exigir 'reescrever_db_para_docker' "$SCRIPT"
exigir 'for servico in app worker scheduler waha redis' "$SCRIPT"
exigir 'estado_do_servico srh running' "$SCRIPT"

if grep -Fq 'http://127.*' "$SCRIPT"; then
  falhar 'glob de loopback voltou ao script'
fi
if grep -Eq '(^|[^[:alnum:]_])(source|\.)[[:space:]]+\.env' "$SCRIPT"; then
  falhar 'script local leu .env de producao'
fi

printf 'stack-local: guardas estaticos ok\n'
