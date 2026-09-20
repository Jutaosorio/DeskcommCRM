# Runbook — staging local em Docker

Este ambiente é para testar o produto sem ler `.env`, `.env.local`, Supabase
Cloud ou a sessão WhatsApp de produção. Ele não altera a VPS nem a Astra Cloud.

## Pre-requisitos

- Node 22 e pnpm 9.15.9;
- Docker Desktop em execucao, com `docker compose` funcional;
- Supabase CLI no `PATH`.
- Bash utilizável (no Windows, use o terminal Ubuntu/WSL).

O pre-flight recusa qualquer versao ou ferramenta diferente. Ele tambem recusa
uma URL do Supabase que nao seja loopback; nao contorne essa recusa com uma URL
da nuvem.

## Subir

```bash
pnpm stack:local:up
```

O comando inicia o Supabase CLI local, gera `.env.docker.local` com segredos
descartáveis, aplica `supabase/baseline.sql` uma vez no banco local e sobe o
profile `local`: proxy, app, worker, scheduler, WAHA NOWEB sem sessão pareada,
Redis e serverless-redis-http. O Compose espera os healthchecks e os webhooks
locais exigem HMAC, mesmo sem haver número pareado.

- App: http://localhost:3000
- Painel WAHA local: http://localhost:3030
- Supabase Studio: a URL mostrada por `supabase status`

O navegador usa `supabase.localhost`; dentro dos conteineres esse mesmo nome
resolve para o host Docker. Assim, nenhum bundle local recebe URL remota.

## Verificar e parar

```bash
pnpm stack:local:status
pnpm stack:local:down
```

`status` confirma a saúde de app, worker, scheduler, WAHA e Redis; também
confirma funcionalmente Supabase, Redis HTTP e WAHA pela rota de saúde da app.
`down` para os contêineres locais e o Supabase local, preservando os volumes.
Ele nunca chama o compose de produção.

## Resetar dados locais

```bash
pnpm stack:local:reset --confirm-local-data-loss
```

Esse é o único comando destrutivo. Ele exige a confirmação literal, valida o
Supabase como loopback, remove somente o projeto Compose `deskcomm-local` e os
volumes do Supabase CLI local, e recria tudo a partir do `baseline.sql`.

## Limite do aceite

WAHA sobe deliberadamente sem QR ou pareamento. Webhooks e envio nesta etapa
são simulados no limite da aplicação; o webhook de teste precisa ser assinado.
WhatsApp real, QR, ACK e recuperação de sessão só podem ser provados depois,
com uma conta exclusiva de teste — nunca com a sessão Astra de produção.
