#!/usr/bin/env bash
# ==============================================================================
# vps-antes-depois.sh — roda NA VPS (ssh vps-crm), em volta do deploy.
#
#   antes     backup (Drive, cifrado) + FOTO do que roda agora: imagens, .env, digests.
#             Sem esta foto não existe "voltar à versão anterior": a VPS segue a tag
#             móvel :latest, e depois do pull a imagem velha perde o nome.
#   depois    confere o que a atualização NÃO sabe que é nosso (fora do git) e a saúde.
#   rollback <foto>   volta as 3 imagens da foto e recria os serviços (não desfaz banco:
#             banco volta só por restauração de backup).
#   rollback <foto> --dry-run   só mostra o que faria.
#
# De fora (máquina de trabalho):  ssh vps-crm 'bash -s -- antes' < vps-antes-depois.sh
# Nenhum segredo é impresso. Saída ≠ 0 se algo reprovar.
# ==============================================================================
set -u
PROJ="${PROJETO:-/root/deskcommcrm}"
MIG="${MIGRACAO:-/root/migracao}"
DBC="${DBC:-deskcommcrm-supabase-db-1}"
ORG="1793d20a-cd29-41bf-994f-a27c18ec7698"
SERVICOS="app worker scheduler"

c_grn() { printf "\033[0;32m%s\033[0m\n" "$*"; }
c_ylw() { printf "\033[0;33m%s\033[0m\n" "$*"; }
c_red() { printf "\033[0;31m%s\033[0m\n" "$*"; }
c_bld() { printf "\033[1m%s\033[0m\n" "$*"; }
FALHAS=0; AVISOS=0
ok()    { c_grn "  ✓ $*"; }
falha() { c_red "  ✗ $*"; FALHAS=$((FALHAS + 1)); }
aviso() { c_ylw "  ⚠ $*"; AVISOS=$((AVISOS + 1)); }

cd "$PROJ" || { echo "pasta $PROJ não existe"; exit 2; }
MODO="${1:-}"

# ── antes ───────────────────────────────────────────────────────────────────────
if [ "$MODO" = "antes" ]; then
  c_bld "==> ANTES do deploy"
  TS="$(date -u +%Y%m%d-%H%M%S)"; FOTO="$MIG/pre-update-$TS.txt"
  if [ "${2:-}" != "--sem-drive" ]; then
    echo "  backup cifrado no Drive (banco completo + Storage + WhatsApp)…"
    bash "$MIG/backup-drive.sh" >> "/var/log/alugja-backup.log" 2>&1 && ok "backup no Drive concluído" || { falha "backup falhou — NÃO atualize (ver /var/log/alugja-backup.log)"; exit 1; }
  else aviso "backup pulado (--sem-drive)"; fi
  (umask 077; : > "$FOTO")
  {
    echo "# foto $TS (UTC) — usada por: vps-antes-depois.sh rollback $FOTO"
    echo "commit_codigo=$(git rev-parse HEAD)"
    for s in $SERVICOS; do
      cid="$(docker ps -q -f "name=deskcommcrm-$s-1")"
      [ -n "$cid" ] || { echo "# serviço $s não está rodando" >&2; continue; }
      echo "$s.image_id=$(docker inspect "$cid" --format '{{.Image}}')"
      echo "$s.image_ref=$(docker inspect "$cid" --format '{{.Config.Image}}')"
    done
    echo "# linhas de imagem do .env (sem segredos):"
    grep -E '^(APP_IMAGE|WORKER_IMAGE|SCHEDULER_IMAGE|VOICE_AGENT_IMAGE|APP_PULL_POLICY|SINGLE_SERVER)=' .env | sed 's/^/env./'
  } >> "$FOTO"
  cp -p .env "$MIG/.env.pre-update-$TS" && chmod 600 "$MIG/.env.pre-update-$TS"
  ok "foto salva em $FOTO (e cópia do .env, modo 600)"
  echo "  Para voltar: bash $MIG/vps-antes-depois.sh rollback $FOTO"
  exit 0
fi

# ── rollback ────────────────────────────────────────────────────────────────────
if [ "$MODO" = "rollback" ]; then
  FOTO="${2:-}"; DRY=0; [ "${3:-}" = "--dry-run" ] && DRY=1
  [ -f "$FOTO" ] || { c_red "uso: $0 rollback <arquivo-da-foto> [--dry-run]"; exit 2; }
  c_bld "==> ROLLBACK das imagens para a foto $FOTO $([ $DRY = 1 ] && echo '(dry-run)')"
  for s in $SERVICOS; do
    id="$(grep -E "^$s.image_id=" "$FOTO" | cut -d= -f2-)"; ref="$(grep -E "^$s.image_ref=" "$FOTO" | cut -d= -f2-)"
    [ -n "$id" ] && [ -n "$ref" ] || { aviso "$s sem dados na foto, pulado"; continue; }
    if docker image inspect "$id" >/dev/null 2>&1; then
      echo "  $s: reaponta $ref -> ${id:0:19}…"
      [ $DRY = 1 ] || docker tag "$id" "$ref"
    else falha "$s: a imagem antiga ${id:0:19}… não existe mais neste disco (foi removida?) — só restaurando versão por pull"; fi
  done
  [ "$FALHAS" -gt 0 ] && exit 1
  if [ $DRY = 0 ]; then
    # shellcheck disable=SC1091
    source "$PROJ/hostgator-setup-kit/_common.sh"; enter_project >/dev/null
    dc up -d --pull never --force-recreate $SERVICOS && ok "serviços recriados com as imagens da foto" || exit 1
    echo "  Banco NÃO foi desfeito. Se a atualização mexeu no schema e isso importa: restaurar o backup do Drive."
  fi
  exit 0
fi

# ── depois ──────────────────────────────────────────────────────────────────────
if [ "$MODO" = "depois" ]; then
  c_bld "==> DEPOIS do deploy: saúde e customizações da Astra que ficam FORA do git"
  DOM="$(grep -E '^DOMAIN=' .env | cut -d= -f2- | tr -d '"')"; DOM="${DOM:-crm.astramarketing.io}"

  c_bld "1. O app respondeu como app?"
  h="$(curl -s -o /dev/null -w '%{http_code}' "https://$DOM/api/v1/health")"; [ "$h" = 200 ] && ok "/api/v1/health 200" || falha "/api/v1/health = $h"
  a="$(curl -s -o /dev/null -w '%{http_code}' "https://$DOM/app")"; [ "$a" = 307 ] && ok "/app 307 (manda para o login)" || falha "/app = $a (esperado 307)"
  g="$(curl -s -o /dev/null -w '%{http_code}' "https://$DOM/auth/v1/health")"; [ "$g" = 401 ] && ok "gateway do Supabase vivo (401 sem chave)" || falha "/auth/v1/health = $g (esperado 401)"
  for s in $SERVICOS caddy waha; do
    st="$(docker ps --format '{{.Status}}' -f "name=deskcommcrm-$s-1")"; case "$st" in Up*) ok "$s: $st";; *) falha "$s: ${st:-não está rodando}";; esac
  done
  grep -qE '^SINGLE_SERVER="?1' .env && ok ".env: SINGLE_SERVER=1" || falha ".env perdeu SINGLE_SERVER=1 (o app não acharia o banco)"

  c_bld "2. Caddy: o domínio dos MCPs de WhatsApp (mcp.juta-os.com)"
  if grep -q "mcp.juta-os.com" Caddyfile.single-server 2>/dev/null || grep -qs "mcp.juta-os.com" caddy-sites/*.caddy 2>/dev/null; then
    docker exec deskcommcrm-caddy-1 sh -c 'grep -rqs "mcp.juta-os.com" /etc/caddy/' && ok "bloco mcp.juta-os.com está no Caddy em uso" \
      || falha "o bloco existe no disco mas o Caddy em uso não o lê (recriar o caddy)"
  else falha "bloco mcp.juta-os.com não está em Caddyfile.single-server nem em caddy-sites/*.caddy"; fi
  m="$(curl -s -o /dev/null -w '%{http_code}' https://mcp.juta-os.com/)"; [ "$m" = 404 ] && ok "mcp.juta-os.com responde (404 na raiz é o esperado)" || falha "mcp.juta-os.com = $m (esperado 404)"
  if [ -d caddy-sites ] && git status --short Caddyfile Caddyfile.single-server | grep -q .; then aviso "Caddyfile alterado localmente com caddy-sites/ disponível: o update.sh vai parar por 'mudanças locais'"; fi

  c_bld "3. Regra do MCP do Supabase (Envoy) e afinação do Postgres"
  if grep -q "allow_host_only" .runtime/supabase/volumes/api/envoy/lds.template.yaml 2>/dev/null; then ok "Envoy: /mcp liberado só para o host (regra presente)"
  else aviso "Envoy perdeu a regra do /mcp (a atualização do Supabase sobrescreve): o MCP supabase-vps volta bloqueado; reaplicar com $MIG/lds.template.yaml.orig como base"; fi
  sb="$(docker exec "$DBC" psql -U postgres -d postgres -Atc 'show shared_buffers')"; [ "$sb" = "2GB" ] && ok "shared_buffers = 2GB" || falha "shared_buffers = $sb (esperado 2GB)"
  mc="$(docker exec "$DBC" psql -U postgres -d postgres -Atc 'show max_connections')"; [ "$mc" = 200 ] && ok "max_connections = 200" || falha "max_connections = $mc (esperado 200)"

  c_bld "4. Poda de vídeos (só da Alug Já) e cron do Postgres"
  docker exec "$DBC" psql -U postgres -d postgres -Atc "select position('$ORG' in pg_get_functiondef('public.fn_aj_podar_videos_enviados(integer)'::regprocedure))>0 and position('2 hours' in pg_get_functiondef('public.fn_aj_podar_videos_enviados(integer)'::regprocedure))>0" 2>/dev/null | grep -q '^t$' \
    && ok "fn_aj_podar_videos_enviados filtra a Alug Já e usa 2 horas" || falha "fn_aj_podar_videos_enviados mudou (sem filtro de org ou sem 2 horas): reaplicar scripts/migracao/08-podar-videos-2h.sql"
  docker exec "$DBC" psql -U postgres -d postgres -Atc "select count(*) from cron.job where jobname='aj-podar-videos-enviados' and schedule='15 * * * *' and active" 2>/dev/null | grep -q '^1$' \
    && ok "pg_cron: aj-podar-videos-enviados (15 * * * *)" || falha "pg_cron perdeu o job aj-podar-videos-enviados"

  c_bld "5. Backup, disco e swap (crontab e memória da VPS)"
  crontab -l 2>/dev/null | grep -q "alugja:backup-diario" && ok "cron do backup diário presente" || falha "cron do backup diário sumiu"
  crontab -l 2>/dev/null | grep -q "alugja:alerta-disco" && ok "cron do alerta de disco presente" || falha "cron do alerta de disco sumiu"
  swapon --show | grep -q swapfile && ok "swap ativo" || aviso "swap não está ativo"
  uso="$(df --output=pcent / | tail -1 | tr -dc 0-9)"; [ "$uso" -lt 80 ] && ok "disco em ${uso}%" || aviso "disco em ${uso}% (o deploy deixa imagens velhas: docker image prune)"

  c_bld "6. Erros desde o deploy (5 min)"
  for s in app worker scheduler; do
    n="$(docker logs "deskcommcrm-$s-1" --since 5m 2>&1 | grep -ciE 'PGRST002|57014|ECHECKOUTTIMEOUT|ECONNREFUSED|permission denied|invalid api key')"
    [ "$n" -eq 0 ] && ok "$s: 0 erros de banco/chave" || falha "$s: $n linha(s) de erro de banco/chave"
  done
  printf "\n"
  if [ "$FALHAS" -eq 0 ]; then c_grn "✓ Tudo certo ($AVISOS aviso(s))."; exit 0; else c_red "✗ $FALHAS falha(s), $AVISOS aviso(s). Considere o rollback."; exit 1; fi
fi

echo "uso: $0 antes [--sem-drive] | depois | rollback <foto> [--dry-run]"; exit 2
