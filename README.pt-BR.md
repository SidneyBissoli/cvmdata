# cvmdata

[English](https://github.com/SidneyBissoli/cvmdata/blob/main/README.md)
\| **Português**

[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/SidneyBissoli/cvmdata/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/SidneyBissoli/cvmdata/actions/workflows/R-CMD-check.yaml)
[![Codecov test
coverage](https://codecov.io/gh/SidneyBissoli/cvmdata/graph/badge.svg)](https://app.codecov.io/gh/SidneyBissoli/cvmdata)
[![pkgdown](https://github.com/SidneyBissoli/cvmdata/actions/workflows/pkgdown.yaml/badge.svg)](https://github.com/SidneyBissoli/cvmdata/actions/workflows/pkgdown.yaml)

API tidy para os dados abertos da CVM sobre companhias abertas. Lê nove
conjuntos e 104 tabelas por uma única função: o cadastro (`cad`), as
demonstrações anuais e trimestrais (`dfp`, `itr`), o Formulário de
Referência (`fre`), o Formulário Cadastral (`fca`, que liga os tickers
da B3 às companhias), o informe do código de governança (`cgvn`), os
valores mobiliários negociados e detidos (`vlmo`), os programas de
recompra de ações (`recompra_acoes`) e o índice de documentos periódicos
e eventuais (`ipe`).

Nomes de tabelas, colunas, valores categóricos e texto livre são
preservados em português, exatamente como a CVM publica. Nomes de
função, argumentos e atributos de metadado seguem o padrão
inglês-tidyverse esperado pelo rOpenSci e CRAN.

**De onde vêm os dados.** Por padrão, o `cvmdata` *não* lê o portal da
CVM a cada chamada: lê um **espelho** do portal — snapshots em Parquet
dos arquivos da CVM, mantidos pelo autor do pacote nos [GitHub
Releases](https://github.com/SidneyBissoli/cvmdata/releases) deste
repositório e atualizados toda semana por um pipeline automatizado.
Passe `source = "cvm"` (ou chame `cvm_source_set("cvm")`) para ler o
portal oficial diretamente. A CVM publica esses conjuntos sob a licença
Open Database License (ODbL) e o espelho é redistribuído sob a mesma
licença; veja [Proveniência e licença dos
dados](#proveni%C3%AAncia-e-licen%C3%A7a-dos-dados) abaixo.

## Por que cvmdata

A CVM publica os formulários em ZIPs anuais de CSVs com codificação
ISO-8859-1, schema específico por tabela e sem dicionário de dados
unificado. Workflows comuns — “me dá o DFP da empresa X de 2018 a 2024”
— exigem download manual, tratamento de encoding, conversão de
`VL_CONTA` por `ESCALA_MOEDA` e join contra uma `submissao` separada
para traduzir CD_CVM em CNPJ. O `cvmdata` consolida tudo isso atrás de
uma chamada `cvm_fetch(dataset, table, cnpj, year, basis, reading, ...)`
e embarca o dicionário oficial como snapshot, então os tipos de coluna
vêm prontos.

Dois pacotes de R no CRAN, ambos de Marcelo Perlin e colegas, leem o
mesmo portal (conferido no CRAN em 15/11/2026):

- [`GetDFPData2`](https://cran.r-project.org/package=GetDFPData2)
  (0.6.5) lê as demonstrações anuais (DFP), o cadastro das companhias e
  os tickers da B3.
- [`GetFREData`](https://cran.r-project.org/package=GetFREData) (1.1.0)
  lê as tabelas do Formulário de Referência (FRE).

Os antecessores `GetDFPData` e `GetITRData` estão arquivados no CRAN.
Para o DFP de uma lista de companhias, ou uma tabela do FRE em alguns
anos, esses pacotes atendem bem.

O `cvmdata` difere no que faz entre o arquivo e a análise. Mantém a
entrega vigente quando a companhia reapresenta (e devolve todas as
versões substituídas com
[`cvm_versions()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_versions.md)),
traz lado a lado o valor original e o reexpresso de um exercício
(`reading`), aplica a escala da moeda, guarda identificadores como
texto, confere cada arquivo contra o dicionário da CVM e seleciona
companhias por CNPJ ou ticker da B3 e períodos por ano ou por janela de
datas de referência, nos nove conjuntos. O dicionário e as listas de
códigos vêm no pacote, e a fonte padrão é um espelho datado, com soma de
verificação.

## Instalação

`cvmdata` exige R ≥ 4.1 (pipe nativo) e ainda não está no CRAN. A versão
de desenvolvimento pode ser instalada do GitHub:

\
`# install.packages("pak")`\
`pak``::`[`pak`](https://pak.r-lib.org/reference/pak.html)`(``"SidneyBissoli/cvmdata"``)`

## Início rápido

Descubra o que está coberto (offline — a descoberta lê de snapshots
embarcados):

\
[`library`](https://rdrr.io/r/base/library.html)`(`[`cvmdata`](https://github.com/SidneyBissoli/cvmdata)`)`\
\
[`cvm_datasets`](https://sidneybissoli.github.io/cvmdata/reference/cvm_datasets.md)`(``)`\
`#> [1] "cad"  "cgvn" "dfp"  "fca"  "fre"  "ipe"  "itr"  "vlmo"`

O dicionário embarcado expõe os tipos e descrições que a CVM publica
para cada coluna:

\
`dict`` ``<-`` `[`cvm_dictionary`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md)`(``"dfp"``, ``"bpa"``)`\
`tbl`` ``<-`` ``knitr``::`[`kable`](https://rdrr.io/pkg/knitr/man/kable.html)`(`\
`  ``dict``[``1``:``8``, `[`c`](https://rdrr.io/r/base/c.html)`(``"campo"``, ``"descricao"``, ``"tipo_dados"``, ``"tamanho"``)``]``,`\
`  format ``=`` ``"html"`\
`)`\
[`cat`](https://rdrr.io/r/base/cat.html)`(``'<div align="center">'``, ``tbl``, ``'</div>'``, sep ``=`` ``"\n"``)`

| campo        | descricao                       | tipo_dados | tamanho |
|:-------------|:--------------------------------|:-----------|--------:|
| cd_conta     | Código da conta                 | varchar    |      18 |
| cd_cvm       | Código CVM                      | char       |       6 |
| cnpj_cia     | CNPJ da companhia               | varchar    |      20 |
| denom_cia    | Nome empresarial da companhia   | varchar    |     100 |
| ds_conta     | Descrição da conta              | varchar    |     100 |
| dt_fim_exerc | Data fim do exercício social    | date       |      10 |
| dt_refer     | Data de referência do documento | date       |      10 |
| escala_moeda | Escala monetária                | varchar    |     100 |

Baixe os balanços patrimoniais ativos individuais (“BPA individual”)
para duas companhias em anos recentes. Companhias são identificadas por
CNPJ (com ou sem pontuação) ou por ticker da B3; `basis` escolhe as
demonstrações individuais, consolidadas ou ambas:

\
`bpa`` ``<-`` `[`cvm_fetch`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)`(`\
`  dataset ``=`` ``"dfp"``,`\
`  table   ``=`` ``"bpa"``,`\
`  cnpj    ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``"00.000.000/0001-91"``, ``"47.960.950/0001-21"``)``,`\
`  year    ``=`` ``2022``:``2024``,`\
`  basis   ``=`` ``"ind"`\
`)`

Cada arquivo anual traz também o comparativo que a companhia apresentou
para o exercício anterior, muitas vezes reexpresso. `reading` coloca as
duas leituras de um exercício lado a lado, rotuladas: os números
entregues originalmente e o comparativo do arquivo do ano seguinte:

\
`bpa_2022`` ``<-`` `[`cvm_fetch`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)`(`\
`  dataset ``=`` ``"dfp"``,`\
`  table   ``=`` ``"bpa"``,`\
`  ticker  ``=`` ``"PSSA3"``,`\
`  year    ``=`` ``2022``,`\
`  basis   ``=`` ``"con"``,`\
`  reading ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``"original"``, ``"restated"``)`\
`)`

Um documento pode ser reapresentado, e
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
devolve a versão vigente.
[`cvm_versions()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_versions.md)
devolve todas as versões conhecidas, a vigente incluída, cada versão
substituída datada e apontando para a que a substituiu (a Braskem
entregou a DRE de 2023 três vezes; a versão 1 estava em R\$ unidades por
engano):

\
`brkm`` ``<-`` `[`cvm_versions`](https://sidneybissoli.github.io/cvmdata/reference/cvm_versions.md)`(`\
`  dataset ``=`` ``"dfp"``,`\
`  table   ``=`` ``"dre"``,`\
`  cnpj    ``=`` ``"42.150.391/0001-70"``,`\
`  year    ``=`` ``2023``,`\
`  basis   ``=`` ``"con"`\
`)`

Limpe e formate CNPJs:

\
[`cnpj_clean`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_clean.md)`(``"00.000.000/0001-91"``)`\
`#> [1] "00000000000191"`\
[`cnpj_format`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_format.md)`(``"00000000000191"``)`\
`#> [1] "00.000.000/0001-91"`

## Documentação

Referência e artigos em <https://sidneybissoli.github.io/cvmdata/>. A
API exportada está agrupada em cinco famílias:

- **Fetcher** —
  [`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
  é a função única para qualquer dataset e tabela; os grupos ainda no
  roadmap (fundos, agentes, ofertas, eventos) vão estendê-la pelos seus
  schemas.
  [`cvm_versions()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_versions.md)
  devolve todas as versões conhecidas de um documento.
- **Discovery** —
  [`cvm_groups()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_groups.md),
  [`cvm_datasets()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_datasets.md),
  [`cvm_tables()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_tables.md),
  [`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md),
  [`cvm_codelist()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_codelist.md),
  [`cvm_dataset_years()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dataset_years.md).
- **Cache** —
  [`cvm_cache_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_path.md),
  [`cvm_cache_set_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_set_path.md),
  [`cvm_cache_info()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_info.md),
  [`cvm_cache_clear()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_clear.md).
  A janela de TTL para revalidação HTTP é configurável via
  `options(cvmdata.cache_ttl_seconds)` (default 30 dias).
- **Source backend** —
  [`cvm_source_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_get.md),
  [`cvm_source_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_set.md).
- **Utilidades** —
  [`cnpj_lookup()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_lookup.md)
  (acha o CNPJ pelo nome da companhia),
  [`cnpj_clean()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_clean.md),
  [`cnpj_format()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_format.md).

## Proveniência e licença dos dados

Todos os dados têm origem no Portal de Dados Abertos da CVM
(<https://dados.cvm.gov.br/>). O pacote chega a eles por um de dois
backends, selecionáveis via
[`cvm_source_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_set.md)
ou pelo argumento `source` de
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md):

- `"mirror"` (**o padrão** desde a v0.1.0) — snapshots em Parquet dos
  arquivos da CVM publicados nos GitHub Releases deste repositório
  (`mirror-<group>-<dataset>-latest`) e consultados via DuckDB com
  filter pushdown por ano. O espelho é produzido e atualizado toda
  semana pelo ETL em `inst/etl/`, mantido pelo autor do pacote, não pela
  CVM. Costuma ser ~30× mais rápido que o portal; sua defasagem é
  limitada pela atualização semanal. O espelho omite um ano quando a CVM
  publica o CSV daquele ano sem linhas de dados. Cada rodada semanal
  também guarda um retrato datado
  (`mirror-<group>-<dataset>-snapshot-<AAAA-MM-DD>`), de modo que
  `cvm_release_set("2026-11-01")` fixa a sessão no espelho como ele
  estava naquele dia; o padrão `"latest"` acompanha a atualização
  semanal.
- `"cvm"` — HTTP direto ao Portal de Dados Abertos da CVM. Use quando
  precisar de frescor byte a byte contra o regulador, ou quando preferir
  não depender de um espelho de terceiro.

Todo tibble retornado carrega atributos de proveniência (`source`,
`fetched_at`, `group`, `dataset`, `table`, `package_version`,
`release`), permitindo a qualquer consumidor auditar qual backend, e
qual release do espelho, serviu os dados.

**Licença dos dados.** A CVM publica todos os conjuntos cobertos pelo
`cvmdata` sob a [Open Data Commons Open Database License (ODbL)
v1.0](https://opendatacommons.org/licenses/odbl/1-0/). O espelho é um
banco de dados derivado nos termos dessa licença e é redistribuído
também sob a ODbL. Atribuição dos dados: *“Contém dados do Portal de
Dados Abertos da Comissão de Valores Mobiliários (CVM),
<https://dados.cvm.gov.br/>, sob a ODbL v1.0.”* Os detalhes, inclusive o
que a licença pede de quem redistribui os dados, estão em
[`DATA-LICENSE.md`](https://sidneybissoli.github.io/cvmdata/DATA-LICENSE.md).
O **código** do pacote é MIT.

O espelho guarda dados sobre companhias, não sobre pessoas; as tabelas
que descrevem pessoas são lidas direto da CVM. O que o espelho deixa de
fora, quem responde por ele e como uma pessoa citada em um texto pode
pedir que o nome saia estão no aviso de privacidade,
[`PRIVACY.pt-BR.md`](https://sidneybissoli.github.io/cvmdata/PRIVACY.pt-BR.md)
([in English](https://sidneybissoli.github.io/cvmdata/PRIVACY.md)).

### Como citar os dados

O espelho é depositado no Zenodo em edições com DOI (o plano é quatro
por ano), para que um estudo possa citar exatamente o dado que usou e
para que o dado sobreviva às releases do GitHub. Cite a edição que você
usou; o DOI
[10.5281/zenodo.24260440](https://doi.org/10.5281/zenodo.24260440)
aponta sempre para a mais recente. A primeira edição é de 15/11/2026
([10.5281/zenodo.24260441](https://doi.org/10.5281/zenodo.24260441)).
`citation("cvmdata")` traz o pacote e os dados.

## Trabalhos relacionados

Para dados de mercado do lado da bolsa (preços, volumes, tickers,
índices, calendários de pregão), o companheiro natural é o
[`rb3`](https://github.com/wilsonfreitas/rb3) do Wilson Freitas (com
Marcelo Perlin como co-autor), que baixa e parseia os arquivos públicos
da B3. `rb3` e `cvmdata` são complementares: `cvmdata` cobre os
formulários do emissor publicados pelo regulador (CVM); `rb3` cobre os
dados de negociação publicados pelo operador de mercado (B3). Análises
que juntam microestrutura de mercado com demonstrações financeiras usam
os dois lado a lado.

## Suporte

Reporte bugs e peça features em
<https://github.com/SidneyBissoli/cvmdata/issues>.

## Como contribuir

Pull requests são bem-vindas. Veja
[CONTRIBUTING.md](https://github.com/SidneyBissoli/cvmdata/blob/main/CONTRIBUTING.md)
(em inglês, por convenção rOpenSci) para o setup de desenvolvimento, o
gate de qualidade rodado a cada commit, e o formato dos schemas YAML
usados ao adicionar um novo dataset.

O projeto adota o [Código de Conduta do
Contribuidor](https://github.com/SidneyBissoli/cvmdata/blob/main/CODE_OF_CONDUCT.md)
(em inglês). Ao contribuir, você concorda em respeitar seus termos.

## Licença

MIT © Sidney Bissoli.
