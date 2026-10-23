# O que é só da Astra neste fork

Pasta do fork `Jutaosorio/DeskcommCRM`. O upstream (`melgarafael/DeskcommCRM`)
não tem `.astra/`, então nada aqui conflita numa sincronização.

- A skill de sincronização + deploy deste fork é `atualizar-crm-custom`, em
  `.agents/skills/atualizar-crm-custom/` (fonte) com espelho em
  `.claude/skills/atualizar-crm-custom/` (`pnpm skills:sync`). Antes morava em
  `.astra/skills/`, onde nenhum CLI a achava. O nome **não** começa com
  `deskcomm-` de propósito: o teste `skills-embutidas` exige que toda skill
  `deskcomm-*` seja citada em `AGENTS.md`, `CLAUDE.md` e nas duas rules — arquivos
  do upstream que dariam conflito a cada sincronização.
- `.astra/local/` — **ignorada pelo git** (`.gitignore`). Config da instância (ssh, pasta e
  domínio da VPS), checagens próprias e lista de termos proibidos. O fork é público: nada que
  identifique cliente ou servidor entra no git. Como preencher:
  `.agents/skills/atualizar-crm-custom/references/instancia.md`.
- `.github/workflows/contrato-upstream.yml` — vigia semanal: o que a skill assume do upstream
  ainda é verdade? Só roda em fork. Agendamentos em fork nascem desligados: habilite uma vez
  em Actions › contrato-upstream › Enable workflow.
- Prova dos scripts da skill, sem tocar em produção:
  `bash .agents/skills/atualizar-crm-custom/scripts/testar-skill.sh`.

## Divergências intencionais que pedem ajuste de teste do upstream

Ao sincronizar, se um destes testes falhar, **reaplique o ajuste no teste**;
não desfaça a customização.

| Customização | Arquivo | Teste ajustado no fork |
|---|---|---|
| Tema escuro "Linear Dark" (superfícies mais escuras: contraste MAIOR que o upstream) | `app/globals.css` | `tests/unit/branding-pares-pintados.test.ts` (linhas com `ASTRA`) |
| E2E desligado no fork (minutos do Actions vão para o build das imagens) | `.github/workflows/e2e.yml` (`FORK_DA_ASTRA` vem do `env:` do passo, que o teste não carrega: ele segue exercitando a regra do upstream) | nenhum |
| Stack local de staging com as imagens da Astra | `docker-compose.local-vps.yml` | nenhum (o namespace do upstream não pode aparecer escrito à mão) |
| Skill `atualizar-crm-custom` no orçamento de descrições do Codex (upstream já usa ~5.970 de 6.000) | `tests/unit/skills-embutidas.test.ts` (`ORCAMENTO_DESCRICOES` 6000 → 6500) e `.gitignore` (`!.claude/skills/atualizar-crm-custom/`) | o próprio `skills-embutidas` |
| Vigia semanal do contrato da skill com o upstream (job só de fork) | `.github/workflows/contrato-upstream.yml` | `tests/unit/gatilho-dos-jobs-de-entrega.test.ts` (uma entrada em `GATILHO_ESPERADO`, marcada `ASTRA`) |
| Heap do build | `Dockerfile` (`NODE_OPTIONS=--max-old-space-size=4096`) | nenhum |

## Pendente

- **Job `invariants` reprova no fork**: `scripts/conferir-isolamento-do-kit.sh`
  precisa de uma release publicada no `origin` e da tag `v1.63.0`. Conserto:
  publicar uma release por sincronização (ex.: `v1.86.0-astra.1`) e levar as
  tags do upstream ao fork — empurrando no máximo 3 por vez, porque cada push
  de tag `v*` dispara `publish-image.yml`.
