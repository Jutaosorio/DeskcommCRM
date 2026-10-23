# Contrato com o upstream: o que esta skill assume, e como ela não envelhece

A skill roda sobre um projeto que muda toda semana. Para continuar valendo, ela segue três princípios, e `checar-contrato.sh` vigia o resultado.

## Os princípios

1. **Nada de número de versão no raciocínio.** Em vez de "a partir da v1.85 há `caddy-sites/`", pergunta-se pela **capacidade**: `test -d caddy-sites`, `git grep "import /etc/caddy/sites"`. A mesma pergunta serve à 1.85 e à 9.0.
2. **Nada de lista de "o que é do fork" escrita à mão.** Sai do git a cada rodada: arquivos (`git diff` da base comum até o fork) e linhas acrescentadas. A parte que só a instância sabe fica em `custodia.d/`, fora do git.
3. **"Sem mudança" só vale se o instrumento ainda enxerga.** Se o upstream renomear `SUPABASE_REF`, o aviso mais importante não pode sumir em verde: `checar-novidades.sh` diz "não consegui verificar" e manda rodar o contrato.

## O que a skill assume (e quem usa)

| Suposição | Usada por | Se quebrar |
|---|---|---|
| `hostgator-setup-kit/_common.sh` declara `dc`, `enter_project`, `reaplicar_baseline` | `deploy-vps.md` (passos 4 e 5), `vps-antes-depois.sh rollback` | Ache a função nova com `git log -S"reaplicar_baseline" -- hostgator-setup-kit/` e troque o nome nos dois lugares |
| `SUPABASE_REF=` em `_common.sh` | `checar-novidades.sh` seção 4 | Aponte a seção para onde a versão pinada passou a morar |
| `docker-compose.prod.yml` com `app`, `worker`, `scheduler` | `vps-antes-depois.sh`, `VPS_SERVICOS` | Ajuste `VPS_SERVICOS` na config |
| `supabase/baseline.sql` é o que o deploy reaplica | `deploy-vps.md` passo 4 | Veja como o `update.sh` do kit aplica o schema hoje e copie o gesto |
| CHANGELOG em `## [x.y.z]` com seção "Requer atenção" | `checar-novidades.sh` seção 3 | Ajuste os `awk` da seção 3; sem isso os avisos importantes não aparecem |
| Imagem carimbada com `org.opencontainers.image.revision` | `checar-novidades.sh` (versão instalada) | Use `--instalada vX.Y.Z` à mão até corrigir |
| `publish-image.yml` publica as imagens | Checkpoint 2, passo 6 | Troque o `gh run list --workflow=…` pelo workflow novo |
| Rota `/api/v1/health` (200) e `/app` (307) | `vps-antes-depois.sh depois` | Ajuste os códigos esperados |
| Tags `vX.Y.Z` e releases no upstream | `checar-novidades.sh` | `git fetch upstream --tags`; sem releases, passe `--alvo` |

## Quando `checar-contrato.sh` reprova

1. Leia **qual** suposição quebrou (cada linha diz em que arquivo da skill corrigir).
2. Descubra o que o upstream fez: `git log upstream/main -S"<nome antigo>" --oneline -- <arquivo>`.
3. Corrija **o script ou o roteiro**, não o contrato: o contrato descreve o upstream.
4. Rode `bash .agents/skills/atualizar-crm-custom/scripts/testar-skill.sh` (prova os scripts num upstream e num fork sintéticos, sem tocar em produção) e `checar-contrato.sh` de novo.
5. Atualize a tabela acima se a suposição mudou de forma.

## Vigia automático

`.github/workflows/contrato-upstream.yml` roda `checar-contrato.sh` toda semana contra o `main` do upstream, **só em fork**. Quando o upstream muda algo de que a skill depende, o job fica vermelho e o GitHub avisa por e-mail — antes do dia de atualizar.

## Por que a skill não usa o `update.sh` do kit (e quando passar a usar)

O `update.sh` descobre a última versão pela *release* do `origin`, faz `git checkout <tag>` e fixa as imagens em `ghcr.io/<dono-do-origin>/…:<versão>`. Num fork que não publica releases nem imagens com esse esquema, rodá-lo puxaria o código do upstream **sem as customizações do fork**, e imagens que não existem. Para adotá-lo no futuro: publicar no fork uma tag por sincronização (por exemplo `vX.Y.Z-<fork>.1`) com release e imagens, e rodar `update.sh --to <tag>`. Até lá, o caminho é o do Checkpoint 3.
