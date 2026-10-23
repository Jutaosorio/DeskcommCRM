# Resolver conflitos do merge sem perder o fork

Regra de ouro: **conflito não se resolve escolhendo um lado no automático.** O fork e o upstream mudaram a mesma região por razões diferentes; entenda as duas antes de escrever o resultado.

## Descobrir o que é do fork

A lista não está escrita aqui porque envelhece. Ela sai do git:

```bash
bash .agents/skills/atualizar-crm-custom/scripts/checar-novidades.sh   # seção "Customizações do fork"
git diff --name-status "$(git merge-base upstream/main main)" main      # a lista inteira
```

Depois de resolver, `custodia.sh` confere arquivo por arquivo e linha por linha se a customização sobreviveu.

## Por tipo de arquivo

| Arquivo | Como resolver |
|---|---|
| Configuração do build (`Dockerfile`, limites de memória) | Mantenha a linha do fork **e** as mudanças do upstream. Conferir: a linha do fork continua no resultado (a custódia avisa se sumiu). |
| Proxy (`Caddyfile*`) | Se o upstream tem o ponto de extensão `caddy-sites/` (`git grep -l "import /etc/caddy/sites"`), **fique com a versão do upstream** e leve o bloco do fork para `caddy-sites/*.caddy` na VPS (arquivo que o git ignora). Sem o ponto de extensão, mantenha o bloco do fork no `Caddyfile`. |
| Marca, tema, componentes do fork | Mantenha a versão do fork, a menos que o upstream tenha adotado a mesma ideia: aí prefira a dele e apague o desvio. A custódia avisa "idêntico ao upstream" quando isso acontece. |
| Teste do upstream que vigia uma customização do fork | **Ajuste o teste, não a customização**, com um comentário curto, e registre a linha na tabela de `.astra/README.md` para a próxima sincronização reaplicar. |
| `pnpm-lock.yaml` | Fique com o do upstream e rode `pnpm install` para reaplicar as dependências do fork. Não edite o lockfile à mão. |
| `CHANGELOG.md`, `package.json` (versão) | Fique com o do upstream: é a história dele. |
| Migrations e `supabase/baseline.sql` | Nunca renumere nem apague migration do upstream. Se o fork tem migration própria, confira que o número dela não colide com o das novas (a doutrina de migrations do projeto está no `CLAUDE.md`). |

## Quando um conflito não é seu de resolver

Se o conflito está num arquivo que o fork nunca tocou, algo está errado com a base do merge (branch `main` do fork desatualizada, tag errada). Pare, confira `git merge-base` e a tag do Checkpoint 1.
