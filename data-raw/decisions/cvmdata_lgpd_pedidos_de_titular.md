# Procedimento para pedidos de titular — espelho do cvmdata

Registro de 2026-11-14. Diz o que o responsável pelo espelho faz quando
uma pessoa citada nos dados escreve. Não é parecer jurídico. Os artigos
citados foram lidos no texto da Lei 13.709/2018 (LGPD) em 2026-11-14.

O canal é o e-mail publicado em [`PRIVACY.pt-BR.md`](../../PRIVACY.pt-BR.md).
Um pedido que chegue por issue do GitHub é tratado do mesmo jeito, e a
primeira resposta pede para continuar por e-mail, porque a issue é
pública.

## Prazos

| O quê | Prazo | Fonte |
|---|---|---|
| Acusar o recebimento | no mesmo dia útil, se possível | prática do responsável |
| Confirmação ou acesso em formato simplificado | "imediatamente" | art. 19, I |
| Declaração clara e completa | até 15 dias do pedido | art. 19, II |
| Resposta quando a providência não é possível de imediato | na primeira resposta, com as razões | art. 18, § 4º |

O atendimento é sem custo para o titular (art. 18, § 5º). O prazo em
dobro que a ANPD dá ao agente de pequeno porte não é usado: ver o ponto
aberto 1 do teste de legítimo interesse.

## Passo a passo

1. **Registrar.** Anotar a data do pedido, o que foi pedido e o prazo,
   numa nota privada, fora do repositório. O pedido traz dado pessoal e
   não vai para lugar público.
2. **Entender quem pede.** O pedido vale se vier do titular ou de
   representante legalmente constituído (art. 18, § 3º). Para confirmar,
   usar o que o próprio espelho já tem: pedir resposta a partir de um
   endereço da companhia, ou um dado do formulário que só a pessoa
   saberia situar (a companhia e o ano). Não pedir cópia de documento nem
   o CPF completo como rotina.
3. **Localizar.** Procurar o nome nas tabelas com pessoas, na cópia
   corrente e nas fotos datadas. Anotar em que tabelas, companhias e anos
   aparece. Só contagens e nomes de tabela na nota.
4. **Responder conforme o pedido**, pela tabela abaixo.
5. **Fechar.** Dizer ao titular o que foi feito, o que não foi e por quê,
   e que ele pode peticionar à ANPD (art. 18, § 1º). Guardar a nota.
6. **Rever o teste de legítimo interesse** se o pedido mostrou um risco
   que ele não previa.

## O que fazer em cada tipo de pedido

| Pedido | O que fazer |
|---|---|
| Confirmação de tratamento (art. 18, I) | responder sim ou não, com as tabelas e os anos |
| Acesso (art. 18, II) | enviar as linhas do espelho sobre a pessoa, a origem (o formulário e a companhia), a finalidade e os critérios; dizer o que o espelho não guarda |
| Correção (art. 18, III) | o dado é cópia do formulário. Explicar que a correção se faz na origem, por reapresentação da companhia à CVM, e que a cópia corrente acompanha em até cerca de nove dias. Se o erro for do espelho (a conversão), corrigir no ETL e republicar |
| Eliminação, anonimização ou bloqueio de dado desnecessário, excessivo ou irregular (art. 18, IV) | avaliar se o dado é necessário à finalidade. Se não for, retirar para todos (regra nova no ETL), não só para quem pediu |
| Oposição (art. 18, § 2º) | avaliar o motivo contra o teste de legítimo interesse. Se proceder, retirar a pessoa conforme a seção seguinte |
| Com quem os dados são compartilhados (art. 18, VII) | o espelho é aberto: qualquer pessoa pode tê-lo baixado. Informar os dois lugares em que é publicado |

## Retirar uma pessoa do espelho

O ETL não tem hoje uma lista de pessoas a suprimir. Enquanto ela não
existir, um pedido que proceda é atendido assim, e cada passo é dito ao
titular com a sua data:

1. **Cópia corrente:** criar no ETL a supressão das linhas da pessoa
   (regra nova em `util-privacy.R`, com teste) e publicar. A lista de
   suprimidos não pode ir para o repositório público com o nome: fica
   como hash do nome, ou fora do repositório.
2. **Fotos datadas:** passar a mesma regra por `repair-personal-data.R`
   e `repair-snapshot-digests.R`. É reescrita de arquivo público, sem
   volta.
3. **Edições no Zenodo:** pedir ao suporte do Zenodo a retirada do
   registro por exposição de dado pessoal e depositar uma edição
   corrigida. Registrado pelo responsável em 2026-11-08, a partir da
   ajuda do Zenodo: o dono apaga o próprio registro em até 30 dias da
   publicação; depois disso, só por pedido justificado ao suporte, e a
   página de citação permanece.
4. **O que não se alcança:** cópias já baixadas por terceiros e a origem,
   que é o portal da CVM. Dizer isso ao titular e indicar que o pedido
   sobre a origem se faz à companhia ou à CVM.

Se o pedido não proceder, responder com as razões de fato e de direito
(art. 18, § 4º, II).
