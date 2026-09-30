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

O processo é dividido em **3 checkpoints obrigatórios** com validação humana.

---

## Os 3 Checkpoints

```
[Início]
   │
   ▼
[1. Checagem Upstream] ──► CHECKPOINT 1: Resumo das Novidades (Autoriza preparar?)
                                │ (Sim)
                                ▼
[2. Branch sync & Merge] ──► Testes de Custódia Astra & Integridade
                                │
                                ▼
                             CHECKPOINT 2: Pós-Merge Validado (Autoriza push na main?)
                                │ (Sim)
                                ▼
[3. GitHub Actions Build] ──► 4 Imagens publicadas no GHCR
                                │
                                ▼
                             CHECKPOINT 3: Imagens Prontas (Autoriza deploy na VPS?)
                                │ (Sim)
                                ▼
[4. Backup + Deploy VPS] ──► Healthcheck 200 OK?
                                ├── Sim ──► ✓ Atualização Concluída!
                                └── Não ──► ⚠ Rollback Automático e Exibição de Logs
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
   bash hostgator-setup-kit/backup-db.sh 2>/dev/null || true
   ```
   
   b. **Atualização do Banco (se houver migrations)**:
   Se foram detectadas alterações no `baseline.sql` no Checkpoint 1:
   ```bash
   bash hostgator-setup-kit/update.sh
   ```
   Caso contrário (somente código/telas):
   ```bash
   docker compose -f docker-compose.prod.yml pull
   docker compose -f docker-compose.prod.yml up -d
   ```

4. **Validação de Saúde (Healthcheck)**:
   Verifique se o app respondeu HTTP 200:
   ```bash
   curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3000/api/v1/health
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
