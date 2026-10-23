#!/usr/bin/env bash
# ==============================================================================
# vps-antes-depois.sh — roda NA VPS, em volta do deploy. Quem chama é na-vps.sh
# (que leva a config da instância pelo ssh); direto na VPS: PROJETO=… bash este-arquivo …
#
#   antes [--sem-backup]   backup + FOTO do que roda agora: imagens, .env, digests.
#                          Sem esta foto não existe "voltar à versão anterior": a VPS segue
#                          uma tag móvel e, depois do pull, a imagem velha perde o nome.
#   depois [foto]          saúde do app + o que a atualização não sabe que é seu.
#                          Com a foto, confere também que o modo (SINGLE_SERVER) não mudou.
#   rollback <foto> [--dry-run]   volta as imagens da foto e recria os serviços (o banco
#                          NÃO volta: só por restauração de backup).
#
# Variáveis (todas vêm da config da instância, via na-vps.sh):
#   PROJETO      pasta do projeto na VPS (padrão: a pasta atual, se tiver .env + compose)
#   MIGRACAO     onde ficam fotos e cópias do .env (padrão: $PROJETO/.atualizacoes, modo 700)
#   PREFIXO      prefixo dos contêineres (padrão: COMPOSE_PROJECT_NAME do .env, ou o nome da pasta)
#   SERVICOS     serviços do deploy (padrão: "app worker scheduler")
#   BACKUP_CMD   comando do backup, rodado em $PROJETO (padrão: bash hostgator-setup-kit/backup.sh)
#   BACKUP_LOG   onde guardar a saída do backup (padrão: $MIGRACAO/backup.log)
#   DOMINIO      domínio público (padrão: DOMAIN do .env)
#   EXTRAS_B64   verificações extras da instância (base64), rodadas no fim de `depois`
#
# Nenhum segredo é impresso. Saída ≠ 0 se algo reprovar.
# ==============================================================================
set -u

c_grn() { printf "\033[0;32m%s\033[0m\n" "$*"; }
c_ylw() { printf "\033[0;33m%s\033[0m\n" "$*"; }
c_red() { printf "\033[0;31m%s\033[0m\n" "$*"; }
c_bld() { printf "\033[1m%s\033[0m\n" "$*"; }
FALHAS=0; AVISOS=0
ok()    { c_grn "  ✓ $*"; }
falha() { c_red "  ✗ $*"; FALHAS=$((FALHAS + 1)); }
aviso() { c_ylw "  ⚠ $*"; AVISOS=$((AVISOS + 1)); }

PROJ="${PROJETO:-}"
if [ -z "$PROJ" ] && [ -f .env ] && ls docker-compose*.yml >/dev/null 2>&1; then PROJ="$(pwd)"; fi
[ -n "$PROJ" ] && [ -d "$PROJ" ] || { echo "defina PROJETO (pasta do projeto na VPS) — VPS_PROJETO na config da instância"; exit 2; }
cd "$PROJ" || exit 2
MIG="${MIGRACAO:-$PROJ/.atualizacoes}"
SERVICOS="${SERVICOS:-app worker scheduler}"
PREFIXO="${PREFIXO:-$(sed -n 's/^[[:space:]]*COMPOSE_PROJECT_NAME=//p' .env 2>/dev/null | tr -d '"' | head -1)}"
[ -n "$PREFIXO" ] || PREFIXO="$(basename "$PROJ" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9')"
DBC="${DBC:-$PREFIXO-supabase-db-1}"
DOM="${DOMINIO:-$(grep -E '^DOMAIN=' .env 2>/dev/null | cut -d= -f2- | tr -d '"')}"
MODO="${1:-}"
env_valor() { grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'; }

# ── antes ───────────────────────────────────────────────────────────────────────
if [ "$MODO" = "antes" ]; then
  c_bld "==> ANTES do deploy"
  (umask 077; mkdir -p "$MIG")
  TS="$(date -u +%Y%m%d-%H%M%S)"; FOTO="$MIG/pre-update-$TS.txt"
  if [ "${2:-}" != "--sem-backup" ]; then
    BACKUP_CMD="${BACKUP_CMD:-bash hostgator-setup-kit/backup.sh}"; BACKUP_LOG="${BACKUP_LOG:-$MIG/backup.log}"
    echo "  backup antes de mexer em qualquer coisa…"
    bash -c "$BACKUP_CMD" >> "$BACKUP_LOG" 2>&1 && ok "backup concluído (log: $BACKUP_LOG)" || { falha "backup falhou — NÃO atualize (ver $BACKUP_LOG)"; exit 1; }
  else aviso "backup pulado (--sem-backup)"; fi
  (umask 077; : > "$FOTO")
  {
    echo "# foto $TS (UTC) — usada por: rollback $FOTO"
    echo "commit_codigo=$(git rev-parse HEAD)"
    for s in $SERVICOS; do
      cid="$(docker ps -q -f "name=$PREFIXO-$s-1")"
      [ -n "$cid" ] || { echo "# serviço $s não está rodando" >&2; continue; }
      echo "$s.image_id=$(docker inspect "$cid" --format '{{.Image}}')"
      echo "$s.image_ref=$(docker inspect "$cid" --format '{{.Config.Image}}')"
    done
    echo "# linhas de imagem/modo do .env (sem segredos):"
    grep -E '^(APP_IMAGE|WORKER_IMAGE|SCHEDULER_IMAGE|VOICE_AGENT_IMAGE|APP_PULL_POLICY|SINGLE_SERVER)=' .env | sed 's/^/env./'
  } >> "$FOTO"
  cp -p .env "$MIG/.env.pre-update-$TS" && chmod 600 "$MIG/.env.pre-update-$TS"
  ok "foto salva em $FOTO (e cópia do .env, modo 600)"
  echo "FOTO=$FOTO"
  exit 0
fi

# ── rollback ────────────────────────────────────────────────────────────────────
if [ "$MODO" = "rollback" ]; then
  FOTO="${2:-}"; DRY=0; [ "${3:-}" = "--dry-run" ] && DRY=1
  [ -f "$FOTO" ] || { c_red "uso: rollback <arquivo-da-foto> [--dry-run]"; exit 2; }
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
    # shellcheck disable=SC2086
    dc up -d --pull never --force-recreate $SERVICOS && ok "serviços recriados com as imagens da foto" || exit 1
    echo "  Banco NÃO foi desfeito. Se a atualização mexeu no schema e isso importa: restaurar o backup."
  fi
  exit 0
fi

# ── depois ──────────────────────────────────────────────────────────────────────
if [ "$MODO" = "depois" ]; then
  FOTO="${2:-}"
  c_bld "==> DEPOIS do deploy: saúde e o que fica FORA do git"
  [ -n "$DOM" ] || { falha "sem domínio: defina VPS_DOMINIO ou DOMAIN no .env"; exit 1; }
  SINGLE="$(env_valor SINGLE_SERVER)"

  c_bld "1. O app respondeu como app?"
  h="$(curl -s -o /dev/null -w '%{http_code}' "https://$DOM/api/v1/health")"; [ "$h" = 200 ] && ok "/api/v1/health 200" || falha "/api/v1/health = $h"
  a="$(curl -s -o /dev/null -w '%{http_code}' "https://$DOM/app")"; [ "$a" = 307 ] && ok "/app 307 (manda para o login)" || falha "/app = $a (esperado 307)"
  if [ "$SINGLE" = 1 ]; then
    g="$(curl -s -o /dev/null -w '%{http_code}' "https://$DOM/auth/v1/health")"; [ "$g" = 401 ] && ok "gateway do Supabase vivo (401 sem chave)" || falha "/auth/v1/health = $g (esperado 401)"
  fi
  for s in $SERVICOS caddy waha; do
    # caddy/waha são opcionais conforme o modo: só cobra o que EXISTE neste projeto.
    if [ -z "$(docker ps -aq -f "name=$PREFIXO-$s-1")" ]; then
      case " $SERVICOS " in *" $s "*) falha "$s: contêiner não existe";; esac; continue
    fi
    st="$(docker ps --format '{{.Status}}' -f "name=$PREFIXO-$s-1")"; case "$st" in Up*) ok "$s: $st";; *) falha "$s: ${st:-não está rodando}";; esac
  done
  if [ -n "$FOTO" ] && [ -f "$FOTO" ]; then
    antes="$(grep -E '^env.SINGLE_SERVER=' "$FOTO" | cut -d= -f2- | tr -d '"')"
    [ "$antes" = "$SINGLE" ] && ok "modo SINGLE_SERVER igual ao da foto (${SINGLE:-vazio})" \
      || falha "SINGLE_SERVER mudou: foto='${antes:-vazio}', agora='${SINGLE:-vazio}' (o app pode não achar o banco)"
  else aviso "sem foto informada: não comparei o modo (SINGLE_SERVER=${SINGLE:-vazio}) com o de antes"; fi

  c_bld "2. Proxy e disco"
  if [ -d caddy-sites ] && git status --short Caddyfile Caddyfile.single-server 2>/dev/null | grep -q .; then
    aviso "Caddyfile alterado localmente com caddy-sites/ disponível: o update.sh vai parar por 'mudanças locais'"
  fi
  swapon --show 2>/dev/null | grep -q . && ok "swap ativo" || aviso "swap não está ativo"
  uso="$(df --output=pcent / | tail -1 | tr -dc 0-9)"; [ "${uso:-0}" -lt 80 ] && ok "disco em ${uso}%" || aviso "disco em ${uso}% (o deploy deixa imagens velhas: docker image prune, depois de 24 h estável)"

  c_bld "3. Erros desde o deploy (5 min)"
  for s in $SERVICOS; do
    [ -n "$(docker ps -aq -f "name=$PREFIXO-$s-1")" ] || continue
    n="$(docker logs "$PREFIXO-$s-1" --since 5m 2>&1 | grep -ciE 'PGRST002|57014|ECHECKOUTTIMEOUT|ECONNREFUSED|permission denied|invalid api key')"
    [ "$n" -eq 0 ] && ok "$s: 0 erros de banco/chave" || falha "$s: $n linha(s) de erro de banco/chave"
  done

  if [ -n "${EXTRAS_B64:-}" ]; then
    c_bld "4. Verificações da instância"
    # shellcheck disable=SC1090
    eval "$(printf '%s' "$EXTRAS_B64" | base64 -d)"
  fi

  printf "\n"
  if [ "$FALHAS" -eq 0 ]; then c_grn "✓ Tudo certo ($AVISOS aviso(s))."; exit 0; else c_red "✗ $FALHAS falha(s), $AVISOS aviso(s). Considere o rollback."; exit 1; fi
fi

echo "uso: antes [--sem-backup] | depois [foto] | rollback <foto> [--dry-run]"; exit 2
