# Checkpoint 3: deploy na VPS

Só depois da autorização própria do dono. Tudo parte da **máquina de trabalho**: `na-vps.sh` entra na VPS pelo ssh da config, envia o motor deste repositório (nunca uma cópia velha esquecida lá) e leva junto as suas `verificacoes.d/`. Atalho: `NAVPS="bash .agents/skills/atualizar-crm-custom/scripts/na-vps.sh"`.

Os comandos `sh` rodam na pasta do projeto da VPS. Onde aparece `app worker scheduler`, use a sua `VPS_SERVICOS` se for diferente.

## 1. Backup + foto (se o backup falhar, **não siga**)

```bash
$NAVPS antes
```

Roda o backup (`VPS_BACKUP_CMD`, padrão o `backup.sh` do kit) e grava a foto `pre-update-<ts>.txt`: id e referência das imagens, commit do código, linhas de imagem/modo do `.env` (sem segredos), mais uma cópia do `.env` em modo 600. **Anote a linha `FOTO=…`**: o `depois` e o `rollback` precisam dela.

## 2. Código novo

```bash
$NAVPS sh 'git fetch origin && git merge --ff-only origin/main'
```

Se abortar por "mudanças locais" nos arquivos do proxy, faça o passo 3 primeiro.

## 3. Proxy (só se a instância tem blocos próprios)

Se o upstream tem o ponto de extensão `caddy-sites/` (`git grep -l "import /etc/caddy/sites"`), os blocos próprios vão para `caddy-sites/*.caddy` na VPS (o git ignora) e os Caddyfiles voltam ao do upstream. Valide antes de aplicar:

```bash
$NAVPS sh 'docker run --rm -e ACME_EMAIL=x@y.z -e DOMAIN=<seu-dominio> -v $PWD/Caddyfile.single-server:/etc/caddy/Caddyfile:ro -v $PWD/caddy-sites:/etc/caddy/sites:ro caddy:2 caddy validate --config /etc/caddy/Caddyfile'
$NAVPS sh 'git checkout -- Caddyfile Caddyfile.single-server'    # se estiverem alterados à mão
```

Use o arquivo de proxy que a **sua** instalação usa (`Caddyfile` ou `Caddyfile.single-server`). Sem o ponto de extensão, o bloco próprio continua dentro do Caddyfile do fork.

## 4. Banco, só se o Checkpoint 1 acusou migration ou baseline

Com o app parado, para ninguém falar com o banco enquanto ele muda:

```bash
$NAVPS sh 'bash -c "source hostgator-setup-kit/_common.sh && enter_project && dc stop app worker scheduler && reaplicar_baseline \"\$PROJECT_DIR/supabase/baseline.sql\" \"\$PROJECT_DIR/.deskcomm-banco.log\""'
$NAVPS sh 'tail -20 .deskcomm-banco.log'      # erro aqui? pare e vá ao rollback/restauração
```

## 5. Imagens novas (com `dc`, nunca o compose cru)

```bash
$NAVPS sh 'bash -c "source hostgator-setup-kit/_common.sh && enter_project && dc pull app worker scheduler && dc up -d"'
```

## 6. Conferência (espere cerca de 60 s)

```bash
$NAVPS depois <foto>
```

O script imprime o que conferiu, então esta lista não precisa ser copiada: app respondendo como app (`/api/v1/health` 200, `/app` 307; no modo single-server também o gateway do Supabase), serviços de pé, modo igual ao da foto, disco e swap, erros de banco nos logs dos últimos 5 minutos, mais **as suas** `verificacoes.d/`. **Tudo verde = concluído.**

## 7. Se algo reprovar

```bash
$NAVPS rollback <foto>            # ou --dry-run para só ver o que faria
$NAVPS sh 'docker logs --tail=50 <prefixo>-app-1'
```

Aponta as imagens para a foto e recria os serviços. **O rollback não desfaz o banco**: se o schema mudou e isso importa, restaure o backup do passo 1.

## 8. Depois de 24 h estável

`docker image prune -f`: as imagens antigas são a rede de segurança do rollback, não limpe antes. A retenção dos backups é do script de backup; esta skill **não** apaga backup.

## 9. Registrar

Anote a versão nova e o que o dono precisa fazer na tela por causa dos itens "Requer atenção", onde a sua equipe guarda decisões (fora do repositório, se tiver nome de cliente).
