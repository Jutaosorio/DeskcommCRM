# Config da instância (fora do git)

O fork é público. Tudo que identifica **a sua instalação ou um cliente** (alias do ssh, pasta e domínio da VPS, nome de cliente, checagens próprias) mora em `.astra/local/`, que o `.gitignore` ignora. Os scripts da skill são genéricos e leem de lá.

```
.astra/local/                      ← ignorado pelo git
├── instancia.env                  ← obrigatório para falar com a VPS
├── verificacoes.d/*.sh            ← opcional: checagens SUAS, rodadas na VPS no fim de `depois`
├── custodia.d/*.sh                ← opcional: checagens SUAS na custódia do merge
└── proibidos.txt                  ← opcional: termos que nunca podem ir ao git
```

## Primeira vez (2 minutos)

```bash
mkdir -p .astra/local/verificacoes.d .astra/local/custodia.d
cp .agents/skills/atualizar-crm-custom/assets/instancia.exemplo.env .astra/local/instancia.env
cp .agents/skills/atualizar-crm-custom/assets/proibidos.exemplo.txt .astra/local/proibidos.txt
# edite os dois; depois arme o guarda de push:
bash .agents/skills/atualizar-crm-custom/scripts/guardar-vazamento.sh --instalar
```

## `instancia.env`

Cada chave é opcional; a que faltar tem padrão. `assets/instancia.exemplo.env` traz o modelo comentado.

| Chave | Para quê | Padrão |
|---|---|---|
| `VPS_SSH` | alias do ssh da VPS (vazio ou `local` = você já está nela) | sem VPS |
| `VPS_PROJETO` | pasta do projeto na VPS | a pasta atual, se tiver `.env` e compose |
| `VPS_PREFIXO` | prefixo dos contêineres (`<prefixo>-app-1`) | `COMPOSE_PROJECT_NAME` do `.env`, ou o nome da pasta |
| `VPS_SERVICOS` | serviços que o deploy atualiza | `app worker scheduler` |
| `VPS_MIGRACAO` | onde ficam as fotos (`pre-update-*.txt`) e as cópias do `.env` | `<projeto>/.atualizacoes` (modo 700) |
| `VPS_BACKUP_CMD` | comando do backup, rodado na pasta do projeto | `bash hostgator-setup-kit/backup.sh` |
| `VPS_BACKUP_LOG` | onde guardar a saída do backup | `<VPS_MIGRACAO>/backup.log` |
| `VPS_DOMINIO` | domínio público | `DOMAIN` do `.env` da VPS |
| `UPSTREAM_SLUG` | repositório oficial | `melgarafael/DeskcommCRM` |
| `FORK_BASE` | branch do fork que recebe a atualização | `main` |

## `verificacoes.d/*.sh`: o que só a sua instalação sabe

Cada arquivo é um trecho de bash que `na-vps.sh depois` executa **na VPS**, depois das checagens genéricas (app responde, serviços de pé, disco, erros nos logs). Helpers: `c_bld "título"`, `ok "msg"`, `falha "msg"`, `aviso "msg"`. Variáveis: `PROJ`, `MIG`, `PREFIXO`, `DBC` (contêiner do banco), `DOM`.

```bash
# .astra/local/verificacoes.d/10-meu-proxy.sh
c_bld "X1. Bloco do proxy do meu outro domínio"
docker exec "$PREFIXO-caddy-1" sh -c 'grep -rqs "meu-outro-dominio.exemplo" /etc/caddy/' \
  && ok "bloco presente no proxy em uso" || falha "o proxy em uso perdeu o bloco"
```

Boa candidata a checagem sua: tudo que uma atualização **não sabe que é seu e fica fora do git**: ajustes de memória do Postgres, regras de proxy, crons do `crontab`, funções de banco feitas à mão.

## `custodia.d/*.sh`: o mesmo, para o merge

Lidos por `custodia.sh` (mesmos helpers `ok`/`falha`/`aviso`/`c_bld`). Úteis para o que um merge pode derrubar **sem dar conflito** e que a comparação de arquivos e linhas do git não enxerga.

## `proibidos.txt`: o guarda de vazamento

Um termo por linha (maiúsculas não importam; linhas com `#` são comentário). Use termos **específicos**: o nome do cliente com a grafia dele, o domínio, o id da organização. Um termo curto demais ("alug") casa com palavras comuns ("aluguel") e vira ruído que ninguém mais lê. O hook `pre-push` bloqueia o push se um commit novo contiver um termo daqui, ou um padrão de segredo (chaves de API, tokens, JWT, chave privada). Ele diz **qual arquivo**, nunca mostra o conteúdo da linha.

Conferir agora, na árvore inteira: `bash .agents/skills/atualizar-crm-custom/scripts/guardar-vazamento.sh --arvore`.

## Por que fora do git, e o que fazer se algo já vazou

Um fork de repositório público é público, e o histórico guarda para sempre o que entrou, mesmo depois de apagado. Por isso o guarda existe: o custo de barrar um push é segundos; o de tirar algo do histórico é reescrevê-lo e dar force-push em todas as branches. Se um **segredo** vazou, a primeira ação é trocá-lo no serviço de origem; limpar o histórico vem depois. Se vazou só um **nome ou identificador**, avalie se vale reescrever.
