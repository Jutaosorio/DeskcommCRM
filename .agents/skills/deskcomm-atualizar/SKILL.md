---
name: deskcomm-atualizar
description: 'Guia de atualização e sincronização do DeskcommCRM com o repositório oficial (upstream), preservando customizações da Astra, assets de marca e alocações de Docker em 3 checkpoints com rollback automático. Use SEMPRE que a pessoa pedir para atualizar o CRM, verificar o que há de novo no upstream, sincronizar versão, ou perguntar "tem versão nova?", "como atualizo sem perder meu código?", "roda a deskcomm-atualizar". Conduz a comparação, o merge em branch isolada de sync, os testes rigorosos, o acompanhamento do build no GitHub Actions e o deploy seguro com healthcheck 200.'
metadata:
  publico: mantenedor do fork, operador de VPS
  alvo: sync/upstream com preservacao de customizacoes
---

# Atualizar o DeskcommCRM com Segurança e Preservação de Customizações

Este guia conduz a sincronização do fork com o repositório oficial (`upstream`), garantindo
que nenhuma customização da Astra (logos, alocação de memória no Dockerfile, configurações locais)
seja perdida ou sobrescrita.

## Modos de Operação

1. **Modo Avaliação (`--diff`, "o que mudou?", "só ver novidades"):**
   - Executa a comparação entre a versão instalada e a mais recente do upstream;
   - Exibe o resumo detalhado das novidades e alerta de migrações no banco;
   - **Encerra sem tocar em nenhuma branch nem alterar nada na VPS.**

2. **Modo Atualização Inteligente (Aprovação Única no Início):**
   - Uma vez autorizada a atualização no Checkpoint 1, o agente executa o fluxo completo de ponta a ponta;
   - **Pausa Automática em caso de falha:** Se o teste de custódia (`custodia.sh`) encontrar qualquer conflito ou falha nos testes de marca e código, o processo **pausa imediatamente na branch sync**, sem tocar na `main` e sem fazer push no GitHub, trazendo o diagnóstico para resolução humana.

---

## Os Checkpoints do Fluxo

```
[Início / --diff] ──► Exibe Resumo de Novidades & Alerta de Banco
                             │
                             ▼
                    Autoriza Atualizar?
                             ├── Não ──► Encerra sem alterar nada
                             └── Sim ──► Executa Fluxo Inteligente
                                          │
                                          ▼
                             [Branch sync & Merge Upstream]
                                          │
                                          ▼
                             [Trava de Custódia Astra & Testes]
                                          ├── Falha ──► ⏸ PAUSA OBRIGATÓRIA (Reporta ao usuário)
                                          └── Sucesso
                                               │
                                               ▼
                             [Merge na main & Push GitHub]
                                          │
                                          ▼
                             [Monitoramento Silencioso do Build GHCR]
                                          │
                                          ▼
                             [Backup Preventivo (3 versões)]
                                          │
                                          ▼
                             [Migrações no Banco Supabase]
                                          │
                                          ▼
                             [Deploy na VPS Hostinger & Healthcheck 200]
                                          │
                                          ▼
                             ✓ Atualização Concluída com Sucesso!
```

---

## Checkpoint 1 — Identificação das Novidades e Autorização

Execute o script de checagem:

```bash
bash .agents/skills/deskcomm-atualizar/scripts/checar-novidades.sh
```

### O que apresentar ao usuário:
1. **Versão atual** instalada vs. **versão mais recente** do upstream.
2. **Resumo executivo em português**: principais novidades, correções de bugs e melhorias.
3. **Alerta de banco de dados**: indicar claramente se há alterações em `supabase/migrations/` ou `supabase/baseline.sql`.
4. **Pergunta de autorização**:
   > *"Deseja iniciar a preparação da atualização para a versão vX.Y.Z na branch de sincronização?"*

Se o usuário responder que **não**, encerre sem alterar nenhuma branch.

---

## Checkpoint 2 — Branch de Sincronização, Merge e Custódia

Uma vez aprovado o Checkpoint 1:

1. **Criar a branch isolada de sincronização**:
   ```bash
   git checkout main
   git checkout -b sync/upstream-v<VERSAO>
   ```

2. **Mesclar as alterações do upstream**:
   ```bash
   git merge upstream/main
   ```

3. **Resolução de Conflitos e Custódia da Astra**:
   Se houver conflitos de merge, resolva mantendo as customizações locais:
   - Preservar arquivos de marca própria e logotipos da Astra (pasta de branding).
   - Preservar no `Dockerfile`: `NODE_OPTIONS=--max-old-space-size=4096`.
   - Preservar variáveis customizadas de `.env` e compose.

4. **Validar a custódia**:
   ```bash
   bash .agents/skills/deskcomm-atualizar/scripts/custodia.sh
   ```

5. **Pergunta de autorização do Push**:
   Apresente o resultado dos testes e pergunte:
   > *"O merge foi concluído e todas as customizações da Astra estão 100% protegidas. Autoriza fazer o merge na main e o push para disparar o build das imagens no GitHub?"*

Ao receber a autorização:
```bash
git checkout main
git merge sync/upstream-v<VERSAO>
git push origin main
```

---

## Checkpoint 3 — Build das Imagens e Deploy Seguro na VPS

1. **Acompanhar o Build no GitHub Actions**:
   Monitore a execução da Action:
   ```bash
   gh run list --workflow=publish-image.yml --limit 1
   ```
   Aguarde a conclusão com sucesso (`conclusion: "success"`).

2. **Pergunta de autorização do Deploy**:
   Apresente ao usuário:
   > *"As 4 imagens Docker foram compiladas e publicadas com sucesso no GHCR (ghcr.io/jutaosorio/...). Autoriza realizar o backup e atualizar os contêineres na VPS agora?"*

3. **Execução do Deploy na VPS**:
   Ao receber a autorização final:
   
   a. **Backup preventivo**:
   ```bash
   bash hostgator-setup-kit/backup.sh
   ```
   
   b. **Atualização do Banco (se houver migrations)**:
   Se foram detectadas alterações no `baseline.sql` no Checkpoint 1:
   ```bash
   bash -c 'source hostgator-setup-kit/_common.sh && enter_project && reaplicar_baseline "$PROJECT_DIR/supabase/baseline.sql" "$PROJECT_DIR/.deskcomm-banco.log"'
   ```
   Em seguida:
   ```bash
   docker compose -f docker-compose.prod.yml pull
   docker compose -f docker-compose.prod.yml up -d
   ```

4. **Validação de Saúde (Healthcheck)**:
   Verifique se o app respondeu HTTP 200:
   ```bash
   curl -s -o /dev/null -w "%{http_code}" https://${DOMAIN:-127.0.0.1}/api/v1/health
   ```
   E confira os contêineres:
   ```bash
   docker compose -f docker-compose.prod.yml ps
   ```

5. **Tratamento de Falha e Rollback Automático**:
   Se o healthcheck não responder `200` em até 60 segundos ou algum contêiner cair:
   - Reative imediatamente a imagem ou commit anterior.
   - Restaure os contêineres funcionais com `docker compose -f docker-compose.prod.yml up -d`.
   - Exiba os logs de erro (`docker compose logs --tail=50 app`) para diagnóstico conjunto.

6. **Higienização de Backups (Política de 3 Versões)**:
   Após validação com sucesso do healthcheck 200, mantenha apenas as **3 versões mais recentes** de backups em `backups/` para garantir pontos de recuperação seguros sem consumir espaço em disco desnecessariamente:
   ```bash
   # Mantém os 3 backups mais recentes de banco e waha
   ls -t backups/db-*.sql.gz 2>/dev/null | tail -n +4 | xargs -r rm -f
   ls -t backups/waha-*.tgz 2>/dev/null | tail -n +4 | xargs -r rm -f
   ```
