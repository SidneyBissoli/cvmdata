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

## Complemento de 2026-11-14: contagens de empregados

Decisão do dono: as cinco tabelas de empregados com raça, gênero e
deficiência (`empregado_PCD`, `empregado_local_declaracao_genero`,
`empregado_local_declaracao_raca`, `empregado_posicao_declaracao_genero`,
`empregado_posicao_declaracao_raca`) ficam no espelho, sem a companhia que,
no ano, tem algum grupo com menos de 10 pessoas ou algum grupo unânime
(todos responderam e todos declararam a mesma categoria). A regra é igual
para as cinco. As tabelas de faixa etária e a de cargo por região não
entram: não trazem dado sensível.

**Por que ficam.** São agregados: uma linha é uma companhia, num ano, num
de dois cargos ou numa de seis regiões, com a contagem por categoria.
Nenhuma tabela do conjunto nomeia empregados. Pelo art. 12 da LGPD (lido
em 2026-11-14), dado anonimizado não é dado pessoal, salvo quando a
anonimização puder ser revertida "utilizando exclusivamente meios
próprios" ou "com esforços razoáveis". Para a grande maioria das linhas a
lei não se aplica. A primeira recomendação do assistente, de tirar as cinco
tabelas, ia além do que a lei pede e foi retirada.

**Por que a regra.** Num grupo de 1 pessoa, quem conhece a empresa sabe de
quem é a declaração; num grupo unânime, quem sabe que a pessoa está nele
sabe a categoria dela. O que os órgãos de estatística publicam, lido em
2026-11-14:

| Órgão | Regra | Fonte |
|---|---|---|
| IBGE, Censo Agropecuário | menos de 3 informantes por célula até município; menos de 10 em níveis menores | Guia do usuário da sala de acesso a dados restritos, 2022, Anexo 4 |
| IBGE, pesquisas por empresa | três ou mais informantes na célula; outra linha é omitida para o usuário não obter a informação "por diferença" | mesmo guia |
| Governo britânico, Analysis Function | contagens de 1 ou 2 potencialmente reveladoras; limiar 3; linhas "dominated by zeros" são divulgação de atributo; população em risco abaixo de 1.000 pede proteção mesmo com variável de baixo impacto | Statistical Disclosure Control for tables produced from administrative data |
| ONS | suprime contagens abaixo de 10 no Integrated Data Service | Comparison of post-tabular statistical disclosure control methods |
| CMS (EUA) | célula de 1 a 10 não se publica, nem célula que permita derivá-la | CMS Cell Size Suppression Policy |
| ANPD | nenhum número: processo "baseado em riscos", "não é possível estabelecer uma metodologia padronizada a todos os casos", e em base pública "o risco deve ser majorado" | Estudo técnico sobre anonimização de dados na LGPD (orientativo) |

Não lidos, por virem truncados: o manual europeu de controle de divulgação
e o do UK Data Service.

**Por que 10 e os unânimes.** 10 é o que os órgãos usam em dado sensível
ou recorte pequeno; com os unânimes na regra, custa quase o mesmo que 3.
Os unânimes entram pelo mesmo motivo que tirou as tabelas de
administradores. Não há exceção para "sem deficiência": seria escolha por
categoria sem fonte. A companhia inteira sai da tabela no ano, e não só a
linha, para a linha não ser recalculada por subtração entre as tabelas por
cargo e por região.

**Custo medido** (FRE 2025; companhias que saem, e pessoas contadas que
saem com elas): raça por cargo 49 de 465 (10,5%; 0,1%); gênero por cargo 51
(11,0%; 0,1%); raça por região 147 (31,6%; 15,0%); gênero por região 134
(28,8%; 7,5%); deficiência 173 de 459 (37,7%; 5,0%). Na de deficiência, 185
das 244 linhas unânimes são de grupos com 10 pessoas ou mais, todas "sem
deficiência".

**Como o usuário fica sabendo** (desenho aprovado pelo dono): (1) aviso
`cvmdata_warn_privacy_omitted` a cada leitura, com as companhias e a
parcela de pessoas que não vieram, por ano; (2) atributo `omitted` no
resultado, que o cabeçalho impresso anuncia e que sobrevive aos verbos do
dplyr; (3) companhia pedida por `cnpj` ou `ticker` que foi omitida é
nomeada, em vez de zero linhas caladas, e nesse caso o aviso geral não sai.
Os números vêm de `privacy_omitted` no `__source_hash.json`, gravado pelo
robô por tabela e ano, com a lista de CNPJs omitidos (não revela nada de
pessoas e já seria dedutível comparando com a CVM). A edição do Zenodo leva
`privacy_omitted.csv`, só com contagens.

**Como funciona.** `mirror_group_unsafe()` em `util-privacy.R` reconhece a
tabela pelas colunas (`quantidade_sem_resposta` mais `posicao` ou `local`;
um teste prende isso aos esquemas) e marca todas as linhas da entrega
(companhia, data de referência, versão, documento) em que algum grupo com
pessoas é pequeno ou unânime. `mirror_apply_privacy()` as retira, então a
regra vale no estágio 02, no histórico, na comparação com a release
anterior e nas guardas do 02b e do 06. `mirror_privacy_rule` passa a "3".
