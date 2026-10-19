---
name: deskcomm-atualizar
description: 'Guia de atualização e sincronização do fork da Astra (Jutaosorio/DeskcommCRM) com o repositório oficial (upstream), preservando as customizações da Astra, em 3 checkpoints com aprovação. Use SEMPRE que a pessoa pedir para atualizar o CRM, verificar o que há de novo no upstream, sincronizar versão, ou perguntar "tem versão nova?", "como atualizo sem perder meu código?", "roda a deskcomm-atualizar". Conduz a comparação (com os avisos "Requer atenção" do CHANGELOG), o merge em branch isolada, a custódia + gates, o build das imagens no GitHub Actions e o deploy na VPS single-server com backup, foto das imagens, conferência de saúde e rollback por foto.'
metadata:
  publico: mantenedor do fork, operador de VPS
  alvo: sync/upstream com preservacao de customizacoes; VPS com Supabase self-hosted (SINGLE_SERVER=1)
---

# Atualizar o DeskcommCRM (fork da Astra) com segurança

Sincroniza o fork com o upstream (`melgarafael/DeskcommCRM`) **sem perder o que é da Astra** e leva a versão nova à VPS.

**Onde cada coisa roda**
- **Máquina de trabalho** (clone `codigo-deskcomm`, `gh` logado): Checkpoints 1 e 2 e o push.
- **VPS** (`ssh vps-crm`, pasta `/root/deskcommcrm`): Checkpoint 3.
- Scripts desta skill: `.agents/skills/deskcomm-atualizar/scripts/` (espelho em `.claude/skills/`). **Edite a fonte em `.agents/`** e copie para o espelho.

## Regras de ouro (cada uma já derrubaria ou escondeu um problema)

1. **Nunca `docker compose -f docker-compose.prod.yml …` direto na VPS.** Desde 19/10/2026 ela roda `SINGLE_SERVER=1`: o `up -d` precisa do `docker-compose.single-server.yml` (rede do Supabase + Caddyfile do modo). Sem ele, app e worker voltam sem enxergar o banco e reiniciam em loop. Use **`dc`**, o helper do kit (`source hostgator-setup-kit/_common.sh && enter_project`), que monta os arquivos certos.
2. **`APP_PULL_POLICY=missing` + imagem `:latest` = `up -d` não puxa nada.** Imagem nova só chega com `dc pull` explícito.
3. **Sem "foto" não há volta.** A VPS segue a tag móvel `:latest`; depois do `pull` a imagem antiga perde o nome. Sempre `vps-antes-depois.sh antes` primeiro.
4. **Nada vai para a `main` antes da custódia e dos gates.** A `main` dispara o build das imagens de produção.
5. **`SUPABASE_REF` mudou? Pare.** O deploy manual desta skill **não** atualiza o Supabase da VPS (só o `update.sh` faz isso). Decida com o Juta antes.
6. **Nunca imprima `.env` nem chaves.** Os scripts já não imprimem; ao diagnosticar, filtre as linhas.

## Por que esta skill não usa o `update.sh` (e quando passar a usar)

O `update.sh` faz `git checkout <tag>` e fixa as imagens em `ghcr.io/<dono-do-origin>/…:<versão>`, e descobre a "última versão" pela *release* do `origin`. O `origin` do fork **não tem releases nem tags novas** (as tags do fork param na v1.32). Rodá-lo aqui puxaria o código do upstream (sem as customizações da Astra) e imagens que não existem. Para adotá-lo no futuro: publicar no fork uma tag por sincronização (ex.: `v1.85.0-astra.1`) + release, e rodar `update.sh --to <tag>`. Até lá, o caminho é o do Checkpoint 3.

## Modos

1. **Avaliação** (`--diff`, "o que mudou?", "tem versão nova?"): só o Checkpoint 1. **Não altera branch nem VPS.**
2. **Atualização:** um "sim" no Checkpoint 1 libera o Checkpoint 2; o Checkpoint 3 pede **outro** "sim" (é ele que mexe na produção). Qualquer falha **pausa** e traz o diagnóstico.

```
Checkpoint 1: checar-novidades ─► autoriza? ─ não ─► encerra
        │ sim
Checkpoint 2: branch sync + merge da TAG ─► custodia.sh --testes ─► PR + CI verde ─► autoriza o merge? ─► main ─► build das imagens
        │
Checkpoint 3 (autorização própria): antes ─► código ─► caddy-sites ─► banco ─► pull + up ─► depois ─ falhou ─► rollback
```

---

## Checkpoint 1 — O que há de novo (só leitura)

```bash
bash .agents/skills/deskcomm-atualizar/scripts/checar-novidades.sh
```

Ele lê a **versão que roda de verdade** (commit da imagem do app na VPS) e a **última release estável** do upstream, e imprime o CHANGELOG das versões no meio com a seção **⚠️ Requer atenção** na íntegra, mais: migrations novas, mudança do `SUPABASE_REF`, arquivos de Caddy/compose/kit que o upstream mexeu e a lista do que o fork customiza.

**Apresente ao Juta, em português curto:**
1. Versão instalada → versão alvo.
2. Cada item **⚠️ Requer atenção**, *traduzido para a Alug Já*: "isso se aplica a nós?" (ex.: "cobrança ligada?", "provedor de IA personalizado com teto em modo bloqueio?"). Confira no banco/tela antes de afirmar; não adivinhe.
3. Banco: há migration/baseline? (vira o passo 4 do Checkpoint 3).
4. `SUPABASE_REF` mudou? (regra de ouro 5) e arquivos de infra mexidos (conflito provável).
5. Pergunta: *"Prepara a atualização para vX.Y.Z na branch de sincronização?"* Se não, encerre.

---

## Checkpoint 2 — Branch de sincronização, merge e custódia

1. **Branch isolada, mesclando a TAG da release (não o topo da `main` do upstream):**
   ```bash
   git checkout main && git pull --ff-only origin main
   git checkout -b sync/upstream-vX.Y.Z
   git merge vX.Y.Z          # a tag que o Checkpoint 1 mostrou
   ```
2. **Conflitos:** preserve o que é da Astra. A lista do que é da Astra **não está aqui**: ela sai do git (`checar-novidades.sh`, seção "Customizações da Astra"). Casos conhecidos:
   - `Dockerfile`: manter `NODE_OPTIONS=--max-old-space-size=4096`.
   - `Caddyfile` / `Caddyfile.single-server`: a Astra acrescentou o bloco `mcp.juta-os.com`. **A partir da v1.85 o upstream tem o ponto de extensão `caddy-sites/*.caddy`**: nos conflitos, **fique com a versão do upstream** e leve o bloco para `caddy-sites/` no passo 3 do Checkpoint 3 (arquivo que o git ignora, não trava o `update.sh`).
   - marca (`public/branding/astra-*`), componentes de inbox/kanban, stack local: ver a lista.
3. **Custódia + gates** (pede `pnpm install --frozen-lockfile` antes):
   ```bash
   bash .agents/skills/deskcomm-atualizar/scripts/custodia.sh --testes --alvo vX.Y.Z
   ```
   Camada A (derivada do git): todo arquivo em que o fork difere do upstream sobreviveu ao merge? Camada B: assinaturas conhecidas (heap do Dockerfile, marca, bloco do Caddy). Com `--testes`: `typecheck`, `lint`, `test:unit` (e `test:shell` se kit/compose/Caddy/Dockerfile mudaram); **o código de saída é a autoridade**. Falhou → pare na branch de sync e traga o diagnóstico.
4. **PR e CI antes da `main`:** `git push -u origin sync/upstream-vX.Y.Z`, `gh pr create --base main`, `gh pr checks --watch`. Verde = pode pedir autorização. (Se o CI do fork não rodar, vale o `--testes` local, dito explicitamente.)
5. **Pergunta de autorização do merge:** *"Custódia OK e CI verde. Autoriza mesclar na `main`? Isso dispara o build das imagens de produção."* Ao receber: `gh pr merge --merge` (ou merge local + push).
6. **Build das imagens:** `gh run list --workflow=publish-image.yml --limit 1` até `completed success` (conferir também o job `imagens-ok`). Reporte ao Juta.

---

## Checkpoint 3 — Deploy na VPS (autorização própria)

Pergunta: *"As imagens foram publicadas (ghcr.io/jutaosorio/…). Autoriza atualizar a VPS agora? Haverá uma parada curta do CRM."*

Em cada passo, `ssh vps-crm` e `cd /root/deskcommcrm`. Use o `vps-antes-depois.sh` do repositório; se a VPS ainda não tem a versão nova dele, a cópia estável está em `/root/migracao/vps-antes-depois.sh`.

1. **Backup + foto** (se o backup do Drive falhar, **não siga**):
   ```bash
   bash /root/migracao/vps-antes-depois.sh antes
   ```
   Backup cifrado no Drive (banco completo, Storage, sessões do WhatsApp) + arquivo `pre-update-<ts>.txt` com o id das 3 imagens e o `.env` copiado (600).
2. **Código novo:** `git fetch origin && git merge --ff-only origin/main`. Se abortar por "mudanças locais" nos Caddyfiles, faça o passo 3 primeiro.
3. **Caddy (primeira vez com v1.85 ou mais):** crie `caddy-sites/mcp-juta-os.caddy` com o bloco `mcp.juta-os.com` (copie do `Caddyfile.single-server` antigo), valide com `docker run --rm -e ACME_EMAIL=x@y.z -e DOMAIN=crm.astramarketing.io -v $PWD/Caddyfile.single-server:/etc/caddy/Caddyfile:ro -v $PWD/caddy-sites:/etc/caddy/sites:ro caddy:2 caddy validate --config /etc/caddy/Caddyfile`, e então `git checkout -- Caddyfile Caddyfile.single-server` se estiverem alterados.
4. **Banco, só se o Checkpoint 1 acusou migration/baseline** — com o app parado, para ninguém falar com o banco enquanto ele muda:
   ```bash
   bash -c 'source hostgator-setup-kit/_common.sh && enter_project && dc stop app worker scheduler \
     && reaplicar_baseline "$PROJECT_DIR/supabase/baseline.sql" "$PROJECT_DIR/.deskcomm-banco.log"'
   tail -20 .deskcomm-banco.log     # erros aqui? pare e rollback/restore
   ```
5. **Imagens novas (com `dc`, nunca o compose cru):**
   ```bash
   bash -c 'source hostgator-setup-kit/_common.sh && enter_project && dc pull app worker scheduler && dc up -d'
   ```
6. **Conferência** (espere ~60 s):
   ```bash
   bash /root/migracao/vps-antes-depois.sh depois
   ```
   Confere: `/api/v1/health` 200, `/app` 307, gateway do Supabase, serviços de pé, `SINGLE_SERVER=1`, bloco `mcp.juta-os.com` no Caddy em uso, regra do `/mcp` no Envoy, `shared_buffers`/`max_connections`, poda de vídeos (filtra a Alug Já, 2 horas), crons do backup e do alerta, swap, disco e erros de banco nos logs. **Tudo verde** = concluído.
7. **Se algo reprovar:** `bash /root/migracao/vps-antes-depois.sh rollback /root/migracao/pre-update-<ts>.txt` (aponta as 3 imagens para a foto e recria os serviços). Mostre `docker logs --tail=50 deskcommcrm-app-1`. **O rollback não desfaz o banco**: se o schema mudou e importa, restaure o backup do Drive (ver `alugja.md`, seção Backup).
8. **Depois de 24 h estável:** `docker image prune -f` (as imagens antigas são a rede de segurança do rollback: não limpe antes). A retenção dos backups é do `backup-drive.sh` (14 locais, 30 no Drive); esta skill **não** apaga backup.
9. **Registrar:** versão nova em `DECISOES.md` (seção Supabase na VPS / histórico) e no `alugja.md`, e o que o Juta precisa fazer na tela por causa dos "Requer atenção".

## O que NÃO fazer
- Não rode `update.sh` nem o botão "Atualizar" da tela neste fork (ver acima).
- Não faça push na `main` com custódia reprovada ou sem CI verde.
- Não pule o `antes`; não rode `docker image prune` antes de 24 h.
- Não aceite "a imagem subiu" como prova: a prova é o `depois` todo verde.
