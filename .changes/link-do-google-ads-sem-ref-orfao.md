---
impacto: nada_mudou
secao: corrigido
titulo: O link de captura do Google Ads deixa de pôr um "[ref:]" vazio na mensagem do lead
---

Quando alguém abria o endereço de captura do Google Ads sem o identificador do
clique (um teste, um link compartilhado, uma visita que não veio do anúncio), o
WhatsApp abria com o texto configurado terminando em `[ref:]`, um colchete vazio
que o lead enviava junto e que aparecia na conversa sem significar nada.

Agora esse caminho tira o marcador inteiro do texto: a pessoa envia só a
mensagem, e a conversa entra normalmente, sem origem de anúncio, como já
acontecia. O caminho com o identificador do clique não muda.

Contribuição de @rafaelbatistazz (#1405).
