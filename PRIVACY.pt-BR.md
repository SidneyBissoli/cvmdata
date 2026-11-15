# Aviso de privacidade do espelho de dados do cvmdata

O espelho do `cvmdata` guarda dados sobre companhias abertas, não sobre
pessoas. Este aviso é para quem, mesmo assim, encontrar o próprio nome
citado em um texto do espelho, e diz como pedir que ele saia.

Versão de 15 de novembro de 2026. Em caso de divergência com a versão em
inglês ([`PRIVACY.md`](PRIVACY.md)), vale esta.

## Quem responde pelo espelho

O espelho é mantido por uma pessoa física, sem fim econômico:

- **Responsável pelo espelho:** Sidney da Silva Pereira Bissoli.
- **Contato:** <sbissoli76@gmail.com>.

O espelho não é da CVM nem fala por ela. A CVM continua sendo a
responsável pelo Portal de Dados Abertos, <https://dados.cvm.gov.br/>.

## O que é o espelho

A Comissão de Valores Mobiliários (CVM) publica em dados abertos os
formulários que as companhias abertas são obrigadas a entregar. O
`cvmdata` é um pacote de R que lê esses dados. Para a leitura ser rápida
e reproduzível, o pacote mantém uma cópia convertida para o formato
Parquet: o espelho. Tudo vem do portal da CVM; nada é coletado de você
nem de outra fonte.

O espelho existe em dois lugares, ambos abertos a qualquer pessoa:

- **GitHub Releases** do repositório
  <https://github.com/SidneyBissoli/cvmdata>, atualizado toda semana, com
  fotos datadas que permitem ler o espelho como estava em uma data
  passada.
- **Zenodo**, <https://zenodo.org/>, onde edições trimestrais serão
  depositadas com um identificador permanente (DOI).

Os dois serviços guardam arquivos fora do Brasil. O Zenodo informa que os
arquivos ficam nos centros de dados do CERN, "primarily Geneva, with
replicas in Budapest". O GitHub informa que armazena e processa dados "in
a variety of locations, including your local region, the United States".
Lido nas políticas dos dois serviços em 14/11/2026.

## O que o espelho não guarda

Desde 15 de novembro de 2026 o espelho não leva as tabelas em que a CVM
descreve pessoas:

- administradores, conselheiros fiscais e membros de comitês;
- relações familiares e de subordinação dos administradores;
- acionistas e partes relacionadas;
- quem assina o formulário, o diretor de relações com investidores e o
  responsável técnico da auditoria;
- as contagens de declarações de raça, gênero e deficiência dos membros
  de cada órgão de administração.

Nas tabelas sobre a companhia, saem as colunas que nomeiam uma pessoa (o
responsável no cadastro, a pessoa de contato, o responsável técnico), os
e-mails, telefones e faxes, e a linha de um auditor que seja pessoa
física. Nas contagens de raça, gênero e deficiência de empregados, saem as
companhias em que um grupo tem menos de 10 pessoas ou em que todos
declararam a mesma categoria.

Quem lê essas informações com o pacote as recebe diretamente do portal
da CVM, no próprio computador. Essa leitura não passa pelo espelho, e
este aviso não trata dela.

## O que pode restar sobre você

Um texto sobre a companhia pode citar uma pessoa pelo nome: o relatório
do auditor, uma declaração dos diretores, o assunto de um comunicado, uma
observação. O espelho copia esses textos como a CVM os publica, com uma
diferença: um número de CPF que apareça no texto é mascarado
(`***.456.789-**`).

O espelho não reúne o que é dito sobre uma pessoa, não é usado para
decisões sobre pessoas, publicidade, formação de perfis nem venda de
dados.

## Com que fundamento

Os textos servem à pesquisa, ao ensino e ao acompanhamento público das
companhias abertas. O responsável entende que a menção de um nome dentro
deles se apoia no legítimo interesse (Lei 13.709/2018, a LGPD, art. 7º,
IX), sobre dados de acesso público, cujo uso deve considerar "a
finalidade, a boa-fé e o interesse público que justificaram sua
disponibilização" (art. 7º, § 3º). Artigos lidos em 14/11/2026.

## Como pedir que o seu nome saia

Escreva para <sbissoli76@gmail.com> dizendo o seu nome como aparece nos
textos e a companhia. Não envie o número do seu CPF nem cópia de
documento na primeira mensagem; se for preciso confirmar que o pedido é
seu, a forma será combinada na resposta.

Todo pedido de quem comprovar ser a pessoa, ou seu representante, é
atendido, sem necessidade de explicar o motivo. O nome passa a aparecer
como `[omitido a pedido do titular]` nos textos da cópia corrente do
espelho, na atualização semanal que se seguir ao atendimento.

Você também pode pedir a confirmação de que o espelho cita o seu nome e
o acesso a esses trechos (LGPD, art. 18). A confirmação sai o quanto
antes; a resposta completa, em até 15 dias do pedido (art. 19).

**Limites que você deve conhecer:**

- O texto de origem continua no portal da CVM. Um pedido sobre a origem
  se faz à companhia ou à CVM.
- **Fotos datadas e edições no Zenodo já publicadas podem continuar
  citando o nome.** O espelho é mantido por uma pessoa só, e este aviso
  não promete o que ela pode não conseguir cumprir. As fotos datadas
  podem ser refeitas, mas isso não é automático. No Zenodo, depois de 30
  dias da publicação, a retirada de um registro não depende do
  responsável: depende de pedido ao suporte do serviço, que só a aceita
  "in duly justified cases, such as copyright infringement or exposure
  of personal data" (lido na ajuda do Zenodo em 14/11/2026). A resposta
  ao seu pedido dirá o que foi feito e o que não foi possível.
- Arquivos já baixados por terceiros estão fora do alcance do
  responsável.
- O atendimento segue o procedimento registrado em
  [`data-raw/decisions/cvmdata_lgpd_pedidos_de_titular.md`](https://github.com/SidneyBissoli/cvmdata/blob/main/data-raw/decisions/cvmdata_lgpd_pedidos_de_titular.md).

Você também pode peticionar à Autoridade Nacional de Proteção de Dados
(art. 18, § 1º): <https://www.gov.br/anpd/>.

## Mudanças neste aviso

Mudanças são publicadas neste arquivo, com a data no topo, e registradas
no histórico do repositório.
