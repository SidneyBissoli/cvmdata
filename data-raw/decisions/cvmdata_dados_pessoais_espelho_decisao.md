# Dados pessoais no espelho e nas edições do Zenodo

Decisão do dono em 2026-11-08, depois de duas pesquisas (CPF e nome).
Não é parecer jurídico; a pergunta aberta a advogado, se o dono quiser
fazê-la, é a da seção "O que continua em aberto".

## O que se decidiu

Igual no espelho (GitHub Releases) e nas edições do Zenodo:

| Dado | Tratamento | Por quê |
|---|---|---|
| CPF, onde estiver | Máscara da Receita: `***.456.789-**` | Sobra para a finalidade: a máscara com o nome identifica a pessoa entre tabelas |
| Documento estrangeiro em coluna de CPF | `***` | Mesmo motivo, sem máscara parcial possível |
| `data_nascimento` | Só o ano, na coluna `ano_nascimento` (inteiro) | Nome + CPF + nascimento é o trio de confirmação de identidade; a pesquisa usa idade |
| Nomes | Como a CVM publica | O nome é o conteúdo da divulgação (Res. CVM 80, itens 7.5 e 7.6) |
| Biografias e declarações | Como a CVM publica, salvo o número de CPF citado nelas | Divulgação exigida; editar o texto falsificaria o que ele afirma |
| Contagens de raça, gênero e deficiência | Como a CVM publica | Por órgão, ninguém identificado |

`source = "cvm"` continua lendo tudo da CVM sem tocar em nada. O
tratamento mora só no ETL (`inst/etl/util-privacy.R`).

É a única exceção à regra "se vem da CVM, fica como na CVM", e vale para
o que o pacote **redistribui**: quem lê da CVM recebe da CVM.

## Por quê

O depósito do Zenodo é público e permanente, e o depositante responde
sozinho por ele (Termos do Zenodo). A CVM publica por dever legal, e o
art. 7º, §§ 3º, 4º e 7º da LGPD permite tratar dado tornado público
respeitando a finalidade da publicação; o art. 10, § 1º limita o legítimo
interesse aos dados estritamente necessários. O teste do necessário dá
resultados opostos para o nome e para o CPF:

- **Nome:** tirá-lo desfaz a finalidade (dizer ao mercado quem governa a
  companhia). O padrão federal é nome completo com CPF descaracterizado
  (Parecer 001/2021 e Despacho 093/2022 da CONJUR-CGU/AGU; dados abertos
  do CNPJ da Receita). O STF apoia a publicação de nomes de quem presta
  contas (Tema 483) e rejeita um direito geral ao esquecimento (Tema 786).
- **CPF:** a máscara faz o mesmo serviço. Medido no FRE 2021–2025: 10.687
  CPFs distintos dão 10.561 máscaras; 123 máscaras são compartilhadas, e
  máscara + nome não junta nenhuma pessoa diferente.

## O que a medição acrescentou (2026-11-08)

A varredura de todos os parquets, valor a valor, achou mais do que as "14
colunas" da conta anterior. Valores alterados no `-latest`, histórico incluído:

| Onde | Valores |
|---|---|
| Colunas `cpf*` (13, em 9 tabelas do FCA e do FRE) | 556.858 |
| `documento_pessoa_relacionada`, `documento_parte_relacionada` (nome não diz CPF) | 2.406 |
| Biografias (`experiencia_profissional`) | 2.364 |
| Outros textos livres (21 colunas) | 201 |
| `data_nascimento` (2 tabelas) | 131.129 |

Nas colunas `cpf*` há também passaportes (`AA999999`), e em colunas de
CNPJ, CPFs preenchidos com zeros. Por isso a regra olha o valor, não só o
nome da coluna, e usa o dígito verificador quando o formato não basta:
`999.999.999-99` é CPF mesmo com dígito errado, e 11 dígitos soltos em
texto só contam se o dígito fechar (os do `motivo_reapresentacao` do ITR
não fecham nenhum: não são CPF e ficam).

## Como funciona

- `mirror_apply_privacy()` é idempotente. O estágio 02 aplica antes de
  gravar; o 03 aplica também ao parquet da release anterior **antes de
  comparar**, então a mudança de regra não parece reapresentação e nenhuma
  linha sem máscara chega ao histórico. Prova em dado real: 871 partições
  comparadas, 0 linha falsa de histórico.
- `privacy_rule` no `__source_hash.json`: a primeira publicação sob a
  regra reescreve os ativos de histórico do `-latest`.
- Guardas que param a publicação: `mirror_privacy_counts()` no 02b e no 06
  ("a regra ainda mudaria algo?"). Só nomes de coluna e contagens vão ao
  log.
- `repair-personal-data.R`: as fotos datadas antigas são reescritas no
  lugar (os ponteiros das fotos seguintes dependem delas, então não se
  apagam), seguidas de `repair-snapshot-digests.R`.

## O que continua em aberto

- **Dados de contato:** decididos em 2026-11-14, na seção "Complemento de
  2026-11-14" abaixo.
- **O que não se limpa daqui:** o histórico do git (fixture
  `fca_cia_aberta_2024.zip`, até esta mudança, com 4 CPFs reais), os
  depósitos do sandbox do Zenodo e as cópias que terceiros já baixaram.
- **Documento que não seja CPF em texto livre** (RG, por exemplo): não há
  formato confiável para achar.
- Se o dono consultar advogado, a pergunta é se este desenho basta para o
  depósito permanente, e como responder a um pedido do art. 18 da LGPD
  sobre um registro do Zenodo que não se apaga.

## Complemento de 2026-11-14: dados de contato

Decisão do dono, depois de uma avaliação da decisão de 08/11 no papel de
advogado (análise, não parecer). Princípio que ele fixou: a regra vale por
si, sem depender do que a medição do dia mostrar, porque o dado de amanhã
pode ser outro e o depósito é para sempre.

**Regra:** o espelho e as edições não levam e-mail, telefone nem fax de
ninguém, pessoa ou empresa, nem o endereço de rua de uma pessoa. As colunas
saem (não ficam vazias). O endereço da companhia fica; cidade, estado e
país de uma pessoa ficam; nomes ficam. `source = "cvm"` segue intacto.

| Onde | Sai | Fica |
|---|---|---|
| `cad` (3 tabelas) | `email`, `tel`, `fax`, `ddd_*`, `cd_pais_*` e todos os `*_resp` de contato e de rua | endereço da companhia, `resp`, `mun_resp`, `uf_resp`, `pais_resp` |
| `fca/endereco`, `fca/escriturador` | e-mail, telefone, fax | endereço |
| `fca/dri`, `fca/departamento_acionistas`, `fre/auditor_responsavel` | e-mail, telefone, fax, `logradouro`, `complemento`, `bairro`, `cep` | nome, cidade, estado, país |

**Por que o campo da empresa também sai.** Os campos são distintos, e uma
regra só para os campos de pessoa era possível sem adivinhação. Mas o campo
da empresa traz e-mail de pessoa: a companhia pequena declara como contato
institucional o endereço de alguém. Medido em 2026-11-14 (webmail = gmail,
hotmail, yahoo, outlook, uol e semelhantes; preenchidos / webmail):
`cad/companhias` empresa 1.787 / 48 e responsável 1.791 / 51;
`cad/incentivadas` empresa 696 / 296 e responsável 369 / 153;
`cad/estrangeiras` 26 / 0 e 25 / 0; `fca/endereco` 2025 1.435 / 10;
`fca/dri` 2025 1.007 / 11. Limpar só esses exigiria adivinhar pelo domínio.
A pesquisa não usa telefone nem e-mail, e o contato atual está no portal da
CVM.

**Como funciona.** `mirror_contact_columns()` em `util-privacy.R` escolhe
pelas palavras do nome da coluna (`email`, `tel`, `telefone`, `celular`,
`fax`), para pegar coluna que a CVM criar depois; o endereço de rua sai
pelos sufixos `_resp` e, sem sufixo, quando a tabela tem coluna de pessoa
de contato (`responsavel`, `contato`, `responsavel_tecnico`). Um teste
prende o resultado ao dicionário. `mirror_privacy_rule` passa a "2": a
primeira publicação reescreve o histórico do `-latest`, as guardas do 02b e
do 06 recusam coluna de contato presente, e as fotos datadas pedem
`repair-personal-data.R` de novo, com registro no NEWS.

## Complemento de 2026-11-14: contagens de administradores por órgão

Decisão do dono, depois de ler a fonte: três tabelas do FRE saem do espelho
e das edições, `administrador_declaracao_genero`,
`administrador_declaracao_raca` e `administrador_PCD`. `source = "cvm"`
continua lendo as três. As cinco tabelas de empregados (`empregado_*`)
ficam, em decisão separada, ainda aberta.

**O que a lei diz** (Lei 13.709/2018, texto lido no Planalto em
2026-11-14):

- art. 5º, II: dado sensível inclui "origem racial ou étnica" e "dado
  referente à saúde". Gênero não está na lista.
- art. 11: dado sensível só com consentimento específico ou nas hipóteses
  do inciso II. Legítimo interesse não é uma delas, e não há a dispensa do
  art. 7º, § 4º, para dado tornado público.
- art. 11, II, c, com o art. 5º, XVIII: a hipótese de pesquisa é de "órgão
  de pesquisa", que é órgão público ou pessoa jurídica sem fins
  lucrativos. Pessoa física não se enquadra.
- art. 12: dado anonimizado não é dado pessoal, salvo quando a
  anonimização "com esforços razoáveis, puder ser revertida".

Interpretação, não texto: tratar deficiência como "dado referente à
saúde". Disputado: identidade de gênero. Fico e Nobrega (Revista Direito e
Práxis, 13(2), 2022, doi 10.1590/2179-8966/2022/66817; lido o resumo)
sustentam que é dado sensível mesmo sem estar na lista. Posição da ANPD
procurada e não encontrada.

**O que a medição mostrou** (FRE 2025, só contagens; linha unânime = todos
declararam a mesma categoria e ninguém deixou de responder): 694
companhias, 5 órgãos cada, 1.913 linhas com pessoas. Raça: 1.297 linhas
unânimes (67,8%), 5.472 pessoas. Deficiência: 1.608 (84%), 7.371 pessoas,
todas "sem deficiência"; 33 pessoas com deficiência declarada, 8 em órgãos
de até 3 membros. Gênero: 969 (50,7%); a tabela tem as colunas "não
binário" e "outros" (2 pessoas em 2025; 20 em 2024, com 4 órgãos inteiros
em "outros"). Tamanho dos órgãos: 58 de 1 pessoa, 178 de 2, 1.187 de 3 a
5. Os membros de cada órgão estão nomeados em
`administrador_membro_conselho_fiscal`; os rótulos de órgão diferem entre
as tabelas, mas, juntando à mão só a diretoria, 351 das 469 linhas unânimes
de raça têm o mesmo número de diretores nomeados (1.300 pessoas), e 430 das
de deficiência (1.715 pessoas). É reversão com esforço pequeno.

**Por que não esconder só as linhas de órgão pequeno ou unânime.** A regra
dependeria do dado de cada ano, e a tabela de deficiência ficaria com 16%
das linhas.

**Como funciona.** `mirror: false` e `mirror_reason` no YAML da tabela.
`mirror_tables()` do ETL deixa de listá-la, então os estágios 01, 02 e 02b
não a tocam; o 03 apaga do `-latest` as partições, como sobra, e os ativos
de histórico (`mirror_drop_excluded_history()`), o único caso em que
histórico é apagado. `cvm_fetch()` e `cvm_versions()` recusam a tabela no
espelho com `cvmdata_error_input` e apontam `source = "cvm"`. A guarda da
edição (`edition_check_privacy()`) recusa qualquer arquivo dessas tabelas.
As fotos datadas ainda as têm até o reparo.
