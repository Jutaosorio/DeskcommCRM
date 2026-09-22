---
impacto: capacidade_nova
secao: corrigido
titulo: O modelo enviado fora da janela de 24 horas agora pede os valores que ele exige
---

Quando a janela de 24 horas fechava e você escolhia um modelo aprovado com imagem no
cabeçalho, ou com campos como {{1}} no texto, o envio saía sem esses valores. O WhatsApp
recusava a mensagem, mas a tela mostrava "Modelo enviado", e o cliente nunca recebia nada.

Agora o painel mostra um campo para cada valor que o modelo exige, como o link da imagem
do cabeçalho, e só libera o botão com todos preenchidos. Se o envio falhar mesmo assim, o
aviso passa a ser de erro e diz o motivo.

O link da mídia também pode ficar salvo no modelo: marque "Salvar este link no modelo" e
ele vem preenchido nos próximos envios. Crédito: @rafaelbatistazz.
