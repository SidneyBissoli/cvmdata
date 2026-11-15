# Procedimento para pedidos de titular — espelho do cvmdata

Registro de 2026-11-15 (substitui o de 2026-11-14). Diz o que o
responsável pelo espelho faz quando uma pessoa escreve. Não é parecer
jurídico. Os artigos citados foram lidos no texto da Lei 13.709/2018
(LGPD) em 2026-11-14.

Desde 2026-11-15 o espelho só leva dado de companhia. O que pode restar
sobre uma pessoa é o nome citado em um texto sobre a companhia (parecer,
declaração, assunto de comunicado, observação).

O canal é o e-mail publicado em [`PRIVACY.pt-BR.md`](../../PRIVACY.pt-BR.md).
Um pedido que chegue por issue do GitHub é tratado do mesmo jeito, e a
primeira resposta pede para continuar por e-mail, porque a issue é
pública.

## Prazos

| O quê | Prazo | Fonte |
|---|---|---|
| Acusar o recebimento | no mesmo dia útil, se possível | prática do responsável |
| Confirmação em formato simplificado | "imediatamente" | art. 19, I |
| Declaração clara e completa | até 15 dias do pedido | art. 19, II |
| Resposta quando a providência não é possível de imediato | na primeira resposta, com as razões | art. 18, § 4º |

O atendimento é sem custo para o titular (art. 18, § 5º).

## Passo a passo

1. **Registrar.** Anotar a data do pedido, o que foi pedido e o prazo,
   numa nota privada, fora do repositório. O pedido traz dado pessoal e
   não vai para lugar público.
2. **Entender quem pede.** O pedido vale se vier do titular ou de
   representante legalmente constituído (art. 18, § 3º). Para confirmar,
   pedir resposta a partir de um endereço da companhia, ou um dado que só
   a pessoa saberia situar (a companhia e o ano do texto). Não pedir cópia
   de documento nem o CPF completo como rotina.
3. **Responder conforme o pedido**, pela tabela abaixo.
4. **Fechar.** Dizer ao titular o que foi feito, o que não foi e por quê,
   e que ele pode peticionar à ANPD (art. 18, § 1º). Guardar a nota.

## O que fazer em cada tipo de pedido

| Pedido | O que fazer |
|---|---|
| Confirmação e acesso (art. 18, I e II) | procurar o nome nos textos da cópia corrente; responder sim ou não, com as tabelas e os anos, e enviar os trechos |
| Retirada do nome | atender sempre que quem pede comprovar ser a pessoa (decisão do responsável de 2026-11-14); ver a seção seguinte |
| Correção (art. 18, III) | o texto é cópia do formulário. Explicar que a correção se faz na origem, por reapresentação da companhia à CVM, e que a cópia corrente acompanha na atualização semanal seguinte |
| Pedido sobre tabela de pessoas (administradores, acionistas e outras) | explicar que o espelho não as leva desde 2026-11-15 e que a origem é o portal da CVM |

## Retirar um nome do espelho

1. **Lista.** Acrescentar uma linha ao segredo `CVMDATA_MIRROR_SUPPRESSED`
   do repositório, pelo site do GitHub: `nome completo;CPF`, o CPF
   opcional. O GitHub não mostra o conteúdo de um segredo depois de
   gravado: a lista inteira fica na nota privada e é regravada inteira a
   cada acréscimo. A lista nunca entra no repositório.
2. **Cópia corrente.** A rodada semanal seguinte (ou um disparo manual
   de `etl-mirror.yaml`) troca o nome por `[omitido a pedido do titular]`
   em todo texto do espelho e passa o histórico pela mesma regra. Se a
   lista vier menor que a da rodada anterior, a publicação para: é a
   defesa contra um segredo apagado por engano.
3. **Fotos datadas.** Rodar `repair-personal-data.R` e depois
   `repair-snapshot-digests.R`, com a lista no ambiente. É reescrita de
   arquivo público.
4. **Edições no Zenodo.** Lido na ajuda do Zenodo ("Manage records",
   seção "Delete records") e nas políticas gerais em 2026-11-14: o dono
   apaga o próprio registro "within 30 days after publication"; fora
   desse prazo, "we only allow deletion in duly justified cases, such as
   copyright infringement or exposure of personal data", por pedido ao
   suporte, e "requests without a valid justification will be
   automatically declined"; o registro retirado dá lugar a uma página com
   a citação, e "the DOI and the URL of the original object are
   retained". Pedir a retirada e depositar uma edição corrigida.
5. **O que não se alcança.** Cópias já baixadas por terceiros e a origem,
   que é o portal da CVM. Dizer isso ao titular.

O mecanismo foi provado só com nomes inventados (testes do pacote). O
primeiro pedido real é também a primeira prova contra o espelho real:
conferir, depois da rodada, que o nome não aparece mais.
