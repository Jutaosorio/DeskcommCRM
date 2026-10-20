# O que é só da Astra neste fork

Pasta do fork `Jutaosorio/DeskcommCRM`. O upstream (`melgarafael/DeskcommCRM`)
não tem `.astra/`, então nada aqui conflita numa sincronização.

- `skills/deskcomm-atualizar/` — a skill de sincronização + deploy deste fork.
  Fica fora de `.agents/skills/` porque o teste `skills-embutidas` limita a soma
  das descrições a 6.000 caracteres e as skills do upstream já usam ~5.970.

## Divergências intencionais que pedem ajuste de teste do upstream

Ao sincronizar, se um destes testes falhar, **reaplique o ajuste no teste**;
não desfaça a customização.

| Customização | Arquivo | Teste ajustado no fork |
|---|---|---|
| Tema escuro "Linear Dark" (superfícies mais escuras: contraste MAIOR que o upstream) | `app/globals.css` | `tests/unit/branding-pares-pintados.test.ts` (linhas com `ASTRA`) |
| E2E desligado no fork (minutos do Actions vão para o build das imagens) | `.github/workflows/e2e.yml` (`FORK_DA_ASTRA` vem do `env:` do passo, que o teste não carrega: ele segue exercitando a regra do upstream) | nenhum |
| Stack local de staging com as imagens da Astra | `docker-compose.local-vps.yml` | nenhum (o namespace do upstream não pode aparecer escrito à mão) |
| Heap do build | `Dockerfile` (`NODE_OPTIONS=--max-old-space-size=4096`) | nenhum |

## Pendente

- **Job `invariants` reprova no fork**: `scripts/conferir-isolamento-do-kit.sh`
  precisa de uma release publicada no `origin` e da tag `v1.63.0`. Conserto:
  publicar uma release por sincronização (ex.: `v1.86.0-astra.1`) e levar as
  tags do upstream ao fork — empurrando no máximo 3 por vez, porque cada push
  de tag `v*` dispara `publish-image.yml`.
