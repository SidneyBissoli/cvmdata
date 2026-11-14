# Aviso de privacidade do espelho de dados do cvmdata

Este aviso é para as pessoas cujos nomes aparecem nos dados que o pacote
`cvmdata` espelha: administradores, conselheiros fiscais, membros de
comitês, diretores de relações com investidores, auditores, acionistas e
outras pessoas citadas nos formulários que as companhias abertas entregam
à Comissão de Valores Mobiliários (CVM). Ele diz o que o espelho guarda
sobre você, por quê, por quanto tempo e como pedir que isso mude.

Versão de 14 de novembro de 2026. Em caso de divergência com a versão em
inglês ([`PRIVACY.md`](PRIVACY.md)), vale esta.

## Quem responde pelo espelho

O espelho é mantido por uma pessoa física, sem fim econômico:

- **Responsável pelo espelho** (controlador, no sentido do art. 5º, VI, da
  Lei 13.709/2018, a LGPD, e também encarregado, art. 41): Sidney da Silva
  Pereira Bissoli.
- **Contato:** <sbissoli76@gmail.com>.

O espelho não é da CVM nem fala por ela. A CVM continua sendo a
responsável pelo Portal de Dados Abertos, <https://dados.cvm.gov.br/>.

## O que é o espelho e de onde vêm os dados

A CVM publica em dados abertos os formulários que as companhias abertas
são obrigadas a entregar. O `cvmdata` é um pacote de R que lê esses dados.
Para a leitura ser rápida e reproduzível, o pacote mantém uma cópia
convertida para o formato Parquet: o espelho. Nenhum dado é coletado de
você nem de outra fonte: tudo vem do portal da CVM.

O espelho existe em dois lugares, ambos abertos a qualquer pessoa:

- **GitHub Releases** do repositório <https://github.com/SidneyBissoli/cvmdata>,
  atualizado toda semana, com fotos datadas que permitem ler o espelho
  como estava em uma data passada.
- **Zenodo**, <https://zenodo.org/>, onde edições trimestrais serão
  depositadas com um identificador permanente (DOI), para que um estudo
  possa citar exatamente o dado que usou.

Os dois serviços guardam arquivos fora do Brasil. O Zenodo informa que
os arquivos ficam nos centros de dados do CERN, "primarily Geneva, with
replicas in Budapest". O GitHub informa que armazena e processa dados
"in a variety of locations, including your local region, the United
States". Lido nas políticas dos dois serviços em 14/11/2026.

## Quais dados pessoais o espelho guarda

- **Nome**, como a CVM publica.
- **CPF mascarado**, no formato `***.456.789-**`. O número completo não é
  guardado.
- **Ano de nascimento.** A data completa não é guardada.
- **Cargo, órgão, datas de eleição, posse e mandato, profissão** e os
  demais campos do formulário sobre a função exercida.
- **Experiência profissional e declarações** que o formulário exige, no
  texto que a companhia entregou.
- **Participação acionária e relações** (familiares, de subordinação, com
  partes relacionadas) declaradas nos formulários.
- **Cidade, estado e país** de quem é indicado como responsável ou
  contato.

## O que o espelho não guarda

O espelho retira, do que a CVM publica, o que não é necessário para a
finalidade abaixo:

- o CPF completo e qualquer outro documento de identificação;
- a data de nascimento completa;
- e-mail, telefone e fax, de pessoas e de empresas;
- o endereço de rua de pessoas;
- as contagens de declarações de raça, gênero e deficiência dos membros de
  cada órgão de administração (três tabelas inteiras);
- nas contagens de raça, gênero e deficiência de empregados, as companhias
  em que um grupo tem menos de 10 pessoas ou em que todos declararam a
  mesma categoria.

Quem lê os dados diretamente do portal da CVM, com ou sem o pacote,
recebe o que a CVM publica. Este aviso trata só do espelho.

## Para que os dados são usados

Para pesquisa, ensino e acompanhamento público da governança das
companhias abertas brasileiras: quem as administra e fiscaliza, por
quanto tempo, com que formação e com quais vínculos.

Essa não é a finalidade original da divulgação. A norma da CVM manda as
companhias divulgarem informações "úteis à avaliação dos valores
mobiliários" que emitem, "para todo o mercado" (Resolução CVM 80, arts.
17 e 18), e pede, no formulário de referência, o nome, a data de
nascimento, a profissão, o CPF, o cargo, os mandatos, a experiência
profissional e as condenações de cada administrador e conselheiro fiscal
(Anexo C, item 7.3). O estudo da governança é uma finalidade nova, que o
responsável entende compatível com a original, nos termos do art. 7º,
§ 7º, da LGPD.

O espelho não é usado para decisões sobre pessoas, publicidade, formação
de perfis nem venda de dados.

## Com que fundamento

O responsável entende que o tratamento se apoia no legítimo interesse
(LGPD, art. 7º, IX), dele e dos pesquisadores que usam os dados, sobre
dados de acesso público, cujo uso deve considerar "a finalidade, a boa-fé
e o interesse público que justificaram sua disponibilização" (art. 7º,
§ 3º), limitado ao estritamente necessário (art. 10, § 1º). O teste que
sustenta essa escolha está registrado em
[`data-raw/decisions/cvmdata_lgpd_legitimo_interesse.md`](data-raw/decisions/cvmdata_lgpd_legitimo_interesse.md).

## Por quanto tempo

- **Cópia corrente:** é refeita toda semana a partir do portal da CVM.
  O que a CVM corrige ou retira muda na cópia corrente na atualização
  semanal seguinte.
- **Fotos datadas:** guardam o espelho como estava em cada data, para
  que resultados publicados possam ser refeitos. Não têm prazo de
  expiração.
- **Edições no Zenodo:** o Zenodo guarda os itens "for the lifetime of
  the repository". Passados 30 dias da publicação, só aceita apagar um
  registro "in duly justified cases, such as copyright infringement or
  exposure of personal data", por pedido ao suporte; no lugar fica uma
  página com a citação (lido na ajuda e nas políticas do Zenodo em
  14/11/2026). O responsável se compromete a fazer esse pedido quando um
  pedido de titular proceder.

## Seus direitos e como exercê-los

A LGPD (art. 18) dá a você o direito de pedir ao responsável, a qualquer
momento e sem custo:

- a confirmação de que o espelho trata dados seus;
- o acesso a esses dados;
- a correção de dados incompletos, inexatos ou desatualizados;
- a anonimização, o bloqueio ou a eliminação de dados desnecessários,
  excessivos ou tratados em desconformidade com a lei;
- a informação sobre com quem os dados são compartilhados;
- a oposição ao tratamento, se entender que ele descumpre a lei
  (art. 18, § 2º).

**Como pedir:** escreva para <sbissoli76@gmail.com> dizendo o seu nome
como aparece nos formulários, a companhia e o que está pedindo. Não envie
o número do seu CPF nem cópia de documento na primeira mensagem; se for
preciso confirmar que o pedido é seu, a forma será combinada na resposta.

**Prazos:** a confirmação em formato simplificado sai o quanto antes; a
declaração completa, em até 15 dias do pedido (art. 19).

**Limites que você deve conhecer:**

- A origem do dado é o formulário entregue à CVM. Um erro no formulário
  se corrige na origem, pela companhia; o espelho acompanha a correção.
- Arquivos já baixados por terceiros estão fora do alcance do
  responsável.
- O atendimento segue o procedimento registrado em
  [`data-raw/decisions/cvmdata_lgpd_pedidos_de_titular.md`](data-raw/decisions/cvmdata_lgpd_pedidos_de_titular.md).

Você também pode peticionar à Autoridade Nacional de Proteção de Dados
(art. 18, § 1º): <https://www.gov.br/anpd/>.

## Mudanças neste aviso

Mudanças são publicadas neste arquivo, com a data no topo, e registradas
no histórico do repositório.
