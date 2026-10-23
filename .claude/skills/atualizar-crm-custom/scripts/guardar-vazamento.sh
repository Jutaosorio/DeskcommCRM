#!/usr/bin/env bash
# ==============================================================================
# guardar-vazamento.sh — dado de cliente e segredo não vão para um fork público.
#
# Um fork de repositório público é público. A skill de atualização vive nele, e é
# fácil um nome de cliente, um domínio ou uma chave entrar num commit "de passagem".
# Este guarda confere o que está para SAIR, e nunca imprime o conteúdo da linha —
# só o arquivo e o motivo.
#
# Duas listas:
#   • TERMOS PROIBIDOS, seus: .astra/local/proibidos.txt (um por linha, ignora
#     maiúsculas; o arquivo é local, fora do git). Nomes de clientes, domínios, IDs.
#   • PADRÕES DE SEGREDO, fixos aqui: chaves de API, tokens do GitHub/Slack/Google,
#     JWT, chave privada, credencial AWS.
#
# Uso:
#   guardar-vazamento.sh --arvore       confere os arquivos rastreados agora
#   guardar-vazamento.sh --instalar     arma o hook pre-push (confere cada push)
#   guardar-vazamento.sh --pre-push …   (chamado pelo hook, não à mão)
# Exit 1 se achar algo.
# ==============================================================================
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$DIR/_lib.sh"
carregar_instancia
cd "$RAIZ" || exit 1

PADROES='sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\.|BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}|xox[abp]-[0-9A-Za-z-]{10,}|AIza[0-9A-Za-z_-]{30,}'
TERMOS="$(mktemp)"; FLUXO="$(mktemp)"; FLUXO_MIN="$(mktemp)"; trap 'rm -f "$TERMOS" "$FLUXO" "$FLUXO_MIN"' EXIT
# Sem linhas vazias: um padrão vazio casaria com TUDO. Os termos vão em minúsculas porque o
# `grep -iF` do Git for Windows (grep 3.0) devolve ZERO acertos mesmo havendo — e um guarda
# que não acha nada é pior que nenhum. A comparação é `grep -F` sobre o conteúdo também em
# minúsculas (o nome do arquivo fica intacto, para o relatório).
[ -f "$ASTRA_LOCAL/proibidos.txt" ] && grep -vE '^[[:space:]]*(#|$)' "$ASTRA_LOCAL/proibidos.txt" | tr -d '\r' | tr '[:upper:]' '[:lower:]' > "$TERMOS"
TEM_TERMOS=0; [ -s "$TERMOS" ] && TEM_TERMOS=1
ACHOU=0

relatar_fluxo() {  # lê $FLUXO ("arquivo<TAB>linha") e relata sem mostrar o conteúdo
  awk '{i=index($0,"\t"); printf "%s\t%s\n", substr($0,1,i-1), tolower(substr($0,i+1))}' "$FLUXO" > "$FLUXO_MIN"
  if [ "$TEM_TERMOS" = 1 ]; then
    while IFS= read -r termo; do
      lista="$(grep -F -- "$termo" "$FLUXO_MIN" | cut -f1 | sort -u)"
      [ -n "$lista" ] || continue
      ACHOU=1; c_red "  ✗ termo proibido '$termo' em:"; printf '%s\n' "$lista" | head -8 | sed 's/^/      /'
    done < "$TERMOS"
  fi
  lista="$(grep -E -- "$PADROES" "$FLUXO" | cut -f1 | sort -u)"
  if [ -n "$lista" ]; then ACHOU=1; c_red "  ✗ padrão de segredo (chave/token/JWT/chave privada) em:"; printf '%s\n' "$lista" | head -8 | sed 's/^/      /'; fi
}

fim() {
  if [ "$ACHOU" -eq 0 ]; then
    [ "$TEM_TERMOS" = 1 ] && c_grn "✓ nada de cliente nem segredo" || c_ylw "✓ sem segredo; sem termos proibidos (crie $ASTRA_LOCAL/proibidos.txt para vigiar nomes de clientes)"
    exit 0
  fi
  c_red "✗ Bloqueado. Tire isso do commit (e do histórico, se já foi): o fork é público."
  exit 1
}

case "${1:-}" in
  --arvore)
    c_bld "==> Conferindo os arquivos rastreados"
    if [ "$TEM_TERMOS" = 1 ]; then
      # Um termo por vez, com -e: passar o arquivo com -f ao git nativo do Windows não
      # funciona (ele não entende o caminho /tmp do Git Bash).
      while IFS= read -r termo; do
        l="$(git grep -I -i -l -F -e "$termo" 2>/dev/null || true)"
        [ -n "$l" ] && { ACHOU=1; c_red "  ✗ termo proibido '$termo' em:"; printf '%s\n' "$l" | head -8 | sed 's/^/      /'; }
      done < "$TERMOS"
    fi
    # Segredo: só nos arquivos que o FORK acrescentou ou alterou. A árvore inteira inclui as
    # fixtures de teste do upstream (chaves de mentira), que o dono do fork não escreveu e
    # que fariam esta checagem gritar em toda rodada até ninguém mais ler o aviso.
    MB="$(git merge-base "upstream/$UPSTREAM_BRANCH" HEAD 2>/dev/null || true)"
    if [ -n "$MB" ]; then
      l="$(git diff --name-only -z --diff-filter=AM "$MB" HEAD | xargs -0 -r git grep -I -l -E -e "$PADROES" -- 2>/dev/null || true)"
    else
      c_ylw "  (sem remote upstream: procurando segredo na árvore inteira; fixtures de teste podem aparecer)"
      l="$(git grep -I -l -E -e "$PADROES" 2>/dev/null || true)"
    fi
    [ -n "$l" ] && { ACHOU=1; c_red "  ✗ padrão de segredo em:"; printf '%s\n' "$l" | head -8 | sed 's/^/      /'; }
    fim ;;

  --pre-push)
    shift; REMOTO="${1:-origin}"
    c_bld "==> Conferindo o que vai para $REMOTO"
    while read -r _lref lsha _rref rsha; do
      [ -n "${lsha:-}" ] || continue
      case "$lsha" in 0000000*) continue ;; esac                      # apagando branch
      case "${rsha:-0}" in 0000000*) intervalo=("$lsha" --not "--remotes=$REMOTO") ;; *) intervalo=("$rsha..$lsha") ;; esac
      # O que já está no upstream é público e não é do dono do fork: numa sincronização o push
      # leva centenas de commits dele (fixtures de teste com "chaves" de mentira incluídas).
      git remote | grep -qx upstream && intervalo+=(--not --remotes=upstream)
      # `+++ b/caminho` → caminho (a partir do 7º caractere); `+++ /dev/null` vira "ev/null" e é ignorado.
      git log -p -U0 --no-color --format='@@@%h' "${intervalo[@]}" \
        | awk '/^\+\+\+ /{f=substr($0,7); next} /^\+[^+]|^\+$/{ if (f!="" && f!="ev/null") print f "\t" substr($0,2)}' > "$FLUXO"
      [ "${PIPESTATUS[0]}" -eq 0 ] || { c_red "  ✗ não consegui ler o intervalo ${intervalo[*]} — por segurança, bloqueando"; ACHOU=1; continue; }
      relatar_fluxo
    done
    fim ;;

  --instalar)
    HOOK="$(git rev-parse --git-path hooks/pre-push)"
    MARCA="# atualizar-crm-custom: guardar-vazamento"
    if [ -f "$HOOK" ] && ! grep -q "$MARCA" "$HOOK"; then
      c_ylw "Já existe um pre-push em $HOOK que não é este. Acrescente a ele a linha:"
      echo "  bash \"$DIR/guardar-vazamento.sh\" --pre-push \"\$@\" || exit 1   # (repassando a entrada do git)"
      exit 1
    fi
    mkdir -p "$(dirname "$HOOK")"
    printf '#!/bin/sh\n%s\nexec bash "%s/guardar-vazamento.sh" --pre-push "$@"\n' "$MARCA" "$DIR" > "$HOOK"
    chmod +x "$HOOK"; c_grn "✓ hook pre-push armado em $HOOK"
    exit 0 ;;

  *) sed -n '2,24p' "$0"; exit 2 ;;
esac
