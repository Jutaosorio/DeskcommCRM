#!/usr/bin/env bash
# Staging local: usa SOMENTE Supabase CLI + Docker locais. Nao le .env/.env.local.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ACAO="${1:-}"
ARQUIVO_ENV=".env.docker.local"
MARCADOR=".stack-local/baseline-applied"
# --env-file e obrigatorio: sem ele o Compose leria automaticamente .env, que
# numa maquina de trabalho pode conter segredos e URLs de producao.
COMPOSE=(docker compose --env-file "$ARQUIVO_ENV" --project-name deskcomm-local --profile local -f docker-compose.staging-local.yml)

erro() { printf '==> %s\n' "$*" >&2; exit 1; }

precisa() { command -v "$1" >/dev/null 2>&1 || erro "Falta '$1' no PATH."; }

preflight() {
  precisa node
  precisa pnpm
  precisa docker
  precisa supabase
  [[ "$(node --version)" =~ ^v22\. ]] || erro "Node 22 e obrigatorio (encontrado: $(node --version))."
  [[ "$(pnpm --version)" == "9.15.9" ]] || erro "pnpm 9.15.9 e obrigatorio (encontrado: $(pnpm --version))."
  docker compose version >/dev/null || erro "Docker Compose v2 nao esta acessivel."
  docker info >/dev/null 2>&1 || erro "Docker nao esta em execucao ou nao esta acessivel."
  supabase --version >/dev/null || erro "Supabase CLI nao esta acessivel."
}

preflight_minimo() {
  precisa docker
  precisa supabase
  docker compose version >/dev/null || erro "Docker Compose v2 nao esta acessivel."
}

ler_status() {
  supabase status -o env 2>/dev/null || erro "O Supabase local nao respondeu. Rode 'pnpm stack:local:up'."
}

valor_status() {
  local nome="$1" status="$2"
  printf '%s\n' "$status" | grep "^${nome}=" | head -1 | cut -d= -f2- | tr -d '"' || true
}

eh_url_local() {
  # Nao use glob aqui: `127.exemplo.com` tambem casa com `127.*`.
  # O parser da plataforma decide o host antes de qualquer container receber a URL.
  node -e '
    const [value, kind] = process.argv.slice(1);
    try {
      const url = new URL(value);
      const host = url.hostname.toLowerCase();
      const ipv4Loopback = /^127(?:\.\d{1,3}){3}$/.test(host) && host.split(".").every((part) => Number(part) <= 255);
      const hostLocal = host === "localhost" || host === "supabase.localhost" || host === "[::1]" || ipv4Loopback;
      const protocolOk = kind === "api" ? url.protocol === "http:" : ["postgres:", "postgresql:"].includes(url.protocol);
      process.exit(hostLocal && protocolOk ? 0 : 1);
    } catch {
      process.exit(1);
    }
  ' "$1" "$2"
}

reescrever_db_para_docker() {
  node -e '
    const value = process.argv[1];
    try {
      const url = new URL(value);
      if (!["postgres:", "postgresql:"].includes(url.protocol)) process.exit(1);
      url.hostname = "supabase.localhost";
      process.stdout.write(url.toString());
    } catch {
      process.exit(1);
    }
  ' "$1" || erro "RECUSADO: nao foi possivel reescrever a DB_URL local."
}

validar_status_local() {
  local status="$1" api db
  api="$(valor_status API_URL "$status")"
  db="$(valor_status DB_URL "$status")"
  [[ -n "$api" && -n "$db" ]] || erro "O status local nao trouxe API_URL e DB_URL."
  eh_url_local "$api" api || erro "RECUSADO: API_URL nao e loopback local."
  eh_url_local "$db" db || erro "RECUSADO: DB_URL nao e loopback local."
}

segredo_hex() { node -e 'process.stdout.write(require("node:crypto").randomBytes(Number(process.argv[1])).toString("hex"))' "$1"; }
segredo_base64() { node -e 'process.stdout.write(require("node:crypto").randomBytes(Number(process.argv[1])).toString("base64"))' "$1"; }

sha512() { node -e 'let x="";process.stdin.on("data",d=>x+=d).on("end",()=>process.stdout.write(require("node:crypto").createHash("sha512").update(x).digest("hex")))'; }

valor_env_local() {
  local nome="$1"
  [[ -f "$ARQUIVO_ENV" ]] || return 0
  grep "^${nome}=" "$ARQUIVO_ENV" | head -1 | cut -d= -f2- || true
}

gerar_env() {
  local status api anon service db porta_api db_docker chave_waha hash_waha
  status="$(ler_status)"
  validar_status_local "$status"
  api="$(valor_status API_URL "$status")"
  anon="$(valor_status ANON_KEY "$status")"
  service="$(valor_status SERVICE_ROLE_KEY "$status")"
  db="$(valor_status DB_URL "$status")"
  [[ -n "$anon" && -n "$service" ]] || erro "O Supabase local nao trouxe as chaves anon/service."
  porta_api="${api##*:}"
  db_docker="$(reescrever_db_para_docker "$db")"

  if [[ -f "$ARQUIVO_ENV" ]] && ! grep -q '^# Gerado por scripts/stack-local.sh' "$ARQUIVO_ENV"; then
    erro "$ARQUIVO_ENV ja existe e nao foi gerado por esta stack; recuso sobrescrever."
  fi

  chave_waha="$(valor_env_local WAHA_API_KEY)"; [[ -n "$chave_waha" ]] || chave_waha="$(segredo_hex 32)"
  hash_waha="sha512:$(printf '%s' "$chave_waha" | sha512)"
  umask 077
  cat > "${ARQUIVO_ENV}.tmp" <<EOF
# Gerado por scripts/stack-local.sh. Segredos descartaveis, somente local.
NEXT_PUBLIC_LOCAL_STACK=1
NEXT_PUBLIC_SUPABASE_URL=http://supabase.localhost:${porta_api}
NEXT_PUBLIC_SUPABASE_ANON_KEY=${anon}
SUPABASE_SERVICE_ROLE_KEY=${service}
SUPABASE_DB_URL=${db_docker}
NEXT_PUBLIC_APP_URL=http://localhost:3000
INTERNAL_SECRET=$(valor_env_local INTERNAL_SECRET)
CPF_ENCRYPTION_KEY=$(valor_env_local CPF_ENCRYPTION_KEY)
WAHA_BYO_ENCRYPTION_KEY=$(valor_env_local WAHA_BYO_ENCRYPTION_KEY)
AI_CRED_AES_KEY=$(valor_env_local AI_CRED_AES_KEY)
WAHA_API_BASE_URL=http://waha:3000
WAHA_API_KEY=${chave_waha}
WAHA_API_KEY_SHA512=${hash_waha}
WAHA_HMAC_SECRET=$(valor_env_local WAHA_HMAC_SECRET)
WAHA_WEBHOOK_BASE_URL=http://app:3000
WAHA_WEBHOOK_REQUIRE_SIGNATURE=true
UPSTASH_REDIS_REST_URL=http://srh:80
UPSTASH_REDIS_REST_TOKEN=$(valor_env_local UPSTASH_REDIS_REST_TOKEN)
SENTRY_DSN=off
NEXT_TELEMETRY_DISABLED=1
EOF
  # Chaves de cifra e segredos persistem entre "up" para os dados locais seguirem legiveis.
  for nome in INTERNAL_SECRET CPF_ENCRYPTION_KEY WAHA_BYO_ENCRYPTION_KEY AI_CRED_AES_KEY WAHA_HMAC_SECRET UPSTASH_REDIS_REST_TOKEN; do
    atual="$(valor_env_local "$nome")"
    [[ -n "$atual" ]] && continue
    if [[ "$nome" == *KEY ]]; then atual="$(segredo_base64 32)"; else atual="$(segredo_hex 32)"; fi
    sed -i.bak "s|^${nome}=.*|${nome}=${atual}|" "${ARQUIVO_ENV}.tmp"
  done
  rm -f "${ARQUIVO_ENV}.tmp.bak"
  mv "${ARQUIVO_ENV}.tmp" "$ARQUIVO_ENV"
}

aplicar_baseline_uma_vez() {
  [[ -f "$MARCADOR" ]] && return 0
  local db
  db="$(valor_env_local SUPABASE_DB_URL)"
  [[ "$db" == *'@supabase.localhost:'* ]] || erro "RECUSADO: DSN Docker local invalido."
  mkdir -p "$(dirname "$MARCADOR")"
  printf '==> Aplicando supabase/baseline.sql no Supabase LOCAL...\n'
  docker run --rm --add-host host.docker.internal:host-gateway -i postgres:15-alpine \
    psql "${db/supabase.localhost/host.docker.internal}" --set ON_ERROR_STOP=1 < supabase/baseline.sql
  touch "$MARCADOR"
}

estado_do_servico() {
  local servico="$1" esperado="$2" id estado
  id="$("${COMPOSE[@]}" ps --all -q "$servico")"
  [[ -n "$id" ]] || erro "Servico local ausente: $servico."
  estado="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id")"
  [[ "$estado" == "$esperado" ]] || erro "Servico local $servico esta '$estado'; esperado '$esperado'."
  printf 'servico %s: %s\n' "$servico" "$estado"
}

verificar_servicos() {
  local servico
  for servico in app worker scheduler waha redis; do
    estado_do_servico "$servico" healthy
  done
  # O Redis HTTP e provado funcionalmente pelo /health da app abaixo; a imagem
  # upstream nao declara HEALTHCHECK proprio, portanto aqui exigimos que esteja de pe.
  estado_do_servico srh running
}

subir() {
  preflight
  supabase start
  gerar_env
  aplicar_baseline_uma_vez
  "${COMPOSE[@]}" config >/dev/null
  "${COMPOSE[@]}" up --build --detach --wait
  status
}

descer() {
  preflight_minimo
  [[ -f "$ARQUIVO_ENV" ]] || erro "Falta $ARQUIVO_ENV; nao ha stack local para parar."
  "${COMPOSE[@]}" down --remove-orphans
  supabase stop
}

status() {
  preflight
  local resultado
  resultado="$(ler_status)"
  validar_status_local "$resultado"
  [[ -f "$ARQUIVO_ENV" ]] || erro "Falta $ARQUIVO_ENV; rode 'pnpm stack:local:up'."
  grep -q '^NEXT_PUBLIC_LOCAL_STACK=1$' "$ARQUIVO_ENV" || erro "$ARQUIVO_ENV nao e o ambiente local gerado."
  grep -q '^NEXT_PUBLIC_SUPABASE_URL=http://supabase\.localhost:' "$ARQUIVO_ENV" || erro "RECUSADO: URL publica local invalida."
  "${COMPOSE[@]}" ps
  verificar_servicos
  node -e 'fetch("http://127.0.0.1:3000/api/v1/health").then(r=>{if(!r.ok)throw new Error(String(r.status));process.stdout.write("app health: ok\n")}).catch(e=>{process.stderr.write("app health: "+e.message+"\n");process.exit(1)})'
  node -e 'fetch("http://127.0.0.1:3030/ping").then(r=>{if(!r.ok)throw new Error(String(r.status));process.stdout.write("waha health: ok\n")}).catch(e=>{process.stderr.write("waha health: "+e.message+"\n");process.exit(1)})'
}

resetar() {
  [[ "${2:-}" == "--confirm-local-data-loss" && "$#" == 2 ]] || erro "Uso: pnpm stack:local:reset --confirm-local-data-loss"
  preflight
  supabase start
  validar_status_local "$(ler_status)"
  "${COMPOSE[@]}" down --volumes --remove-orphans
  supabase stop --no-backup
  rm -rf .stack-local
  rm -f "$ARQUIVO_ENV"
  subir
}

case "$ACAO" in
  up) subir ;;
  down) descer ;;
  status) status ;;
  reset) resetar "$@" ;;
  *) erro "Uso: stack-local.sh {up|down|status|reset --confirm-local-data-loss}" ;;
esac
