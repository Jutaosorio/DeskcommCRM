#!/usr/bin/env bash
# ==============================================================================
# testar-skill.sh — prova que os scripts da skill funcionam, SEM tocar em produção
# nem depender da versão atual do upstream.
#
# Monta no /tmp um "upstream" e um "fork" sintéticos (git de verdade, arquivos de
# mentira) e exercita: checar-novidades, custódia (o caso bom e três maus),
# checar-contrato (o bom e um com a suposição quebrada) e guardar-vazamento.
# Os checkpoints 2 e 3 de verdade mexem na main e na VPS: esses não se testam aqui.
#
# Uso:  bash .agents/skills/atualizar-crm-custom/scripts/testar-skill.sh
# Exit 0 = tudo passou. Nada fora do diretório temporário é alterado.
# ==============================================================================
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null    # nada do ambiente do dono interfere
unset ATUALIZAR_CRM_CONFIG ASTRA_LOCAL UPSTREAM_SLUG UPSTREAM_URL FORK_BASE CUSTODIA_BASE

PASSOU=0; FALHOU=0
confere() {  # confere "descrição" <comando…> — o comando precisa sair com 0
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then PASSOU=$((PASSOU + 1)); printf "  \033[0;32m✓\033[0m %s\n" "$d"
  else FALHOU=$((FALHOU + 1)); printf "  \033[0;31m✗\033[0m %s\n" "$d"; fi
}
sai_com() { local esperado="$1"; shift; "$@" >/dev/null 2>&1; [ "$?" -eq "$esperado" ]; }
git_() { git -c core.autocrlf=false -c commit.gpgsign=false "$@"; }
commit() { git_ add -A && git_ commit -q -m "$1"; }
# Saída de um script guardada em $SAIDA para as asserções de texto (sem cores).
rodar() { "$@" > "$T/saida.raw" 2>&1; RC=$?; SAIDA="$(sed 's/\x1b\[[0-9;]*m//g' "$T/saida.raw")"; }
tem() { printf '%s\n' "$SAIDA" | grep -qF -- "$1"; }

# ── o mundo sintético ───────────────────────────────────────────────────────────
U="$T/upstream"; F="$T/fork"
mkdir -p "$U" && cd "$U" || exit 1
git_ init -q -b main
mkdir -p hostgator-setup-kit app/api/v1/health supabase/migrations .github/workflows
printf 'FROM node:22\nRUN echo base\nCMD ["start"]\n' > Dockerfile
printf 'services:\n  app:\n    image: x\n  worker:\n    image: x\n  scheduler:\n    image: x\n' > docker-compose.prod.yml
printf 'select 1;\n' > supabase/baseline.sql
printf 'SUPABASE_REF=aaaa\ndc() { :; }\nenter_project() { :; }\nreaplicar_baseline() { :; }\n' > hostgator-setup-kit/_common.sh
printf '#!/bin/sh\n' > hostgator-setup-kit/backup.sh
printf 'export const GET = 1;\n' > app/api/v1/health/route.ts
printf 'labels: org.opencontainers.image.revision\n' > .github/workflows/publish-image.yml
printf '# Changelog\n\n## [1.0.0] - 2026-01-01\n\n### Adicionado\n\n- **Começo**\n' > CHANGELOG.md
commit "v1.0.0" && git_ tag v1.0.0

git_ clone -q "$U" "$F" && cd "$F" || exit 1
git_ remote rename origin upstream
printf 'linha um do fork\nlinha dois do fork\n' > custom.txt
printf 'ENV NODE_OPTIONS=--max-old-space-size=4096\nENV FLAG_DO_FORK=ligado\n' >> Dockerfile
commit "customização do fork"

cd "$U"
printf 'FROM node:22-slim\nRUN echo base\nCMD ["start"]\n' > Dockerfile
printf 'select 2;\n' > supabase/migrations/0001_nova.sql
printf '# Changelog\n\n## [1.1.0] - 2026-02-01\n\n### ⚠️ Requer atenção\n\n- **Troque a chave X** Antes de atualizar, confira Y.\n\n### Adicionado\n\n- **Coisa nova**\n\n## [1.0.0] - 2026-01-01\n\n### Adicionado\n\n- **Começo**\n' > CHANGELOG.md
commit "v1.1.0" && git_ tag v1.1.0

# ── checar-novidades ────────────────────────────────────────────────────────────
echo "checar-novidades"
cd "$F"
rodar bash "$DIR/checar-novidades.sh" --sem-vps --instalada v1.0.0
confere "acha a release nova (v1.1.0)" tem "Última release estável:    v1.1.0"
confere "mostra o aviso 'Requer atenção' na íntegra" tem "Troque a chave X"
confere "conta a migration nova" tem "1 migration(ns) nova(s)"
confere "sai com 0" test "$RC" -eq 0
rodar bash "$DIR/checar-novidades.sh" --sem-vps --instalada v1.1.0
confere "já na última: diz que está em dia" tem "Já está na versão mais recente"

# ── custódia ────────────────────────────────────────────────────────────────────
echo "custódia"
git_ checkout -q -b sync/upstream-v1.1.0 && git_ merge -q v1.1.0 -m "merge v1.1.0"
export CUSTODIA_BASE=main
rodar bash "$DIR/custodia.sh" --alvo v1.1.0
confere "merge fiel: custódia passa (exit 0)" test "$RC" -eq 0
confere "merge fiel: diz que as linhas do fork estão presentes" tem "todas as linhas acrescentadas pelo fork estão presentes"

git_ rm -q custom.txt && commit "perde arquivo"
rodar bash "$DIR/custodia.sh" --alvo v1.1.0
confere "arquivo do fork sumiu: reprova (exit 1)" test "$RC" -eq 1
confere "arquivo do fork sumiu: nomeia o arquivo" tem "custom.txt"
git_ reset -q --hard HEAD~1

git_ checkout -q v1.1.0 -- Dockerfile && commit "perde a customização inteira do Dockerfile"
rodar bash "$DIR/custodia.sh" --alvo v1.1.0
confere "customização inteira sumiu do arquivo: reprova (exit 1)" test "$RC" -eq 1
confere "customização inteira sumiu: diz INTEIRA" tem "INTEIRA"
git_ reset -q --hard HEAD~1

grep -v 'FLAG_DO_FORK' Dockerfile > Dockerfile.novo && mv Dockerfile.novo Dockerfile && commit "perde uma linha"
rodar bash "$DIR/custodia.sh" --alvo v1.1.0
confere "perdeu 1 de 2 linhas: só avisa (exit 0)" test "$RC" -eq 0
confere "perdeu 1 de 2 linhas: conta 1 de 2" tem "1 de 2 linha(s)"
git_ reset -q --hard HEAD~1
unset CUSTODIA_BASE

# ── checar-contrato ─────────────────────────────────────────────────────────────
echo "checar-contrato"
cd "$U"
rodar bash "$DIR/checar-contrato.sh" --ref HEAD
confere "upstream que cumpre o contrato: passa (exit 0)" test "$RC" -eq 0
grep -v 'reaplicar_baseline' hostgator-setup-kit/_common.sh > x && mv x hostgator-setup-kit/_common.sh && commit "renomeia função"
rodar bash "$DIR/checar-contrato.sh" --ref HEAD
confere "função sumiu do kit: reprova (exit 1)" test "$RC" -eq 1
confere "função sumiu: diz qual" tem "reaplicar_baseline"
confere "função sumiu: diz onde corrigir" tem "references/deploy-vps.md"

# ── guardar-vazamento ───────────────────────────────────────────────────────────
echo "guardar-vazamento"
cd "$F"
mkdir -p .astra/local && printf 'clienteteste\n' > .astra/local/proibidos.txt
printf '.astra/local/\n' > .gitignore
commit "base limpa"
rodar bash "$DIR/guardar-vazamento.sh" --arvore
confere "árvore limpa: passa (exit 0)" test "$RC" -eq 0
printf 'contato: ClienteTeste Ltda\n' > nota.txt && commit "cita o cliente"
rodar bash "$DIR/guardar-vazamento.sh" --arvore
confere "termo proibido na árvore: bloqueia (exit 1)" test "$RC" -eq 1
confere "mostra o arquivo, não o conteúdo" tem "nota.txt"
confere "não imprime o conteúdo da linha" bash -c '! printf "%s" "$0" | grep -q "Ltda"' "$SAIDA"
git_ rm -q nota.txt && commit "tira"
printf 'token=ghp_%s\n' "$(printf 'a%.0s' $(seq 1 36))" > segredo.txt && commit "põe um token"
rodar bash "$DIR/guardar-vazamento.sh" --arvore
confere "token do GitHub na árvore: bloqueia (exit 1)" test "$RC" -eq 1
git_ rm -q segredo.txt && commit "tira"

# pre-push: o que está para sair, não a árvore
git_ init -q --bare "$T/remoto.git" && git_ remote add origin "$T/remoto.git"
git_ push -q origin main:main 2>/dev/null
printf 'cliente: clienteteste\n' > vaza.txt && commit "vaza"
NOVO="$(git_ rev-parse HEAD)"; VELHO="$(git_ rev-parse HEAD~1)"
rodar bash -c "printf 'refs/heads/main %s refs/heads/main %s\n' '$NOVO' '$VELHO' | bash '$DIR/guardar-vazamento.sh' --pre-push origin"
confere "pre-push de commit com termo: bloqueia (exit 1)" test "$RC" -eq 1
rodar bash -c "printf 'refs/heads/main %s refs/heads/main %s\n' '$VELHO' '$VELHO' | bash '$DIR/guardar-vazamento.sh' --pre-push origin"
confere "pre-push sem nada novo: passa (exit 0)" test "$RC" -eq 0

# ── na-vps (com um ssh de mentira que executa o comando aqui mesmo) ─────────────
echo "na-vps"
P="$T/projeto-vps"; mkdir -p "$P" "$T/bin" "$T/cfg/ast/verificacoes.d"
( cd "$P" && git_ init -q -b main && printf 'SINGLE_SERVER=1\nSEGREDO_X=valor-super-secreto\nCOMPOSE_PROJECT_NAME=meuprojeto\nDOMAIN=exemplo.invalid\n' > .env && commit "projeto" )
printf '#!/usr/bin/env bash\ncmd="${@: -1}"\nexec bash -c "$cmd"\n' > "$T/bin/ssh"; chmod +x "$T/bin/ssh"
printf 'VPS_SSH=vps-de-mentira\nVPS_PROJETO=%s\nVPS_MIGRACAO=%s/fotos\nVPS_PREFIXO=meuprojeto\n' "$P" "$T" > "$T/cfg/instancia.env"
printf 'c_bld "X1. verificação da instância"\nok "extra rodou na VPS"\n' > "$T/cfg/ast/verificacoes.d/10-minha.sh"
cd "$F"
rodar env PATH="$T/bin:$PATH" ATUALIZAR_CRM_CONFIG="$T/cfg/instancia.env" ASTRA_LOCAL="$T/cfg/ast" bash "$DIR/na-vps.sh" antes --sem-backup
confere "antes: o motor roda na 'VPS' e grava a foto" tem "foto salva em"
confere "antes: a foto tem o commit do código" bash -c 'grep -q "^commit_codigo=" "$0"/fotos/pre-update-*.txt' "$T"
confere "antes: devolve o caminho da foto (FOTO=…)" tem "FOTO="
confere "antes: não imprime segredo do .env" bash -c '! printf "%s" "$0" | grep -q "valor-super-secreto"' "$SAIDA"
confere "antes: a foto não carrega segredo do .env" bash -c '! grep -q "valor-super-secreto" "$0"/fotos/pre-update-*.txt' "$T"
FOTO_T="$(ls "$T"/fotos/pre-update-*.txt | head -1)"
rodar env PATH="$T/bin:$PATH" ATUALIZAR_CRM_CONFIG="$T/cfg/instancia.env" ASTRA_LOCAL="$T/cfg/ast" bash "$DIR/na-vps.sh" depois "$FOTO_T"
confere "depois: roda as verificações da instância levadas pelo ssh" tem "extra rodou na VPS"
confere "depois: reprova o que não responde (domínio inexistente)" test "$RC" -eq 1
confere "depois: compara o modo com o da foto" tem "modo SINGLE_SERVER igual ao da foto"
rodar env PATH="$T/bin:$PATH" ATUALIZAR_CRM_CONFIG="$T/cfg/instancia.env" ASTRA_LOCAL="$T/cfg/ast" bash "$DIR/na-vps.sh" rollback "$T/nao-existe.txt"
confere "rollback com foto inexistente: recusa (exit 2)" test "$RC" -eq 2

# ── resultado ───────────────────────────────────────────────────────────────────
printf "\n"
if [ "$FALHOU" -eq 0 ]; then printf "\033[0;32m✓ %d verificações passaram.\033[0m\n" "$PASSOU"; exit 0; fi
printf "\033[0;31m✗ %d falharam, %d passaram.\033[0m\n" "$FALHOU" "$PASSOU"; exit 1
