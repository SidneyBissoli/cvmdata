# cvmdata

[English](https://github.com/SidneyBissoli/cvmdata/blob/main/README.md)
\| **Português**

[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/SidneyBissoli/cvmdata/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/SidneyBissoli/cvmdata/actions/workflows/R-CMD-check.yaml)
[![Codecov test
coverage](https://codecov.io/gh/SidneyBissoli/cvmdata/graph/badge.svg)](https://app.codecov.io/gh/SidneyBissoli/cvmdata)
[![pkgdown](https://github.com/SidneyBissoli/cvmdata/actions/workflows/pkgdown.yaml/badge.svg)](https://github.com/SidneyBissoli/cvmdata/actions/workflows/pkgdown.yaml)
[![CRAN
status](https://www.r-pkg.org/badges/version/cvmdata)](https://CRAN.R-project.org/package=cvmdata)

API tidy para os dados abertos da CVM. A primeira versão cobre os
principais conjuntos de companhias abertas: cadastro (`cad`), ITR, DFP e
o Formulário de Referência (`fre`), incluindo as tabelas ESG/governança
sobre composição de conselho, remuneração e estrutura acionária.

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

Dois pacotes já existentes do Marcelo Perlin endereçam fatias adjacentes
do problema:

- [`GetITRData`](https://github.com/msperlin/GetITRData) cobria o ITR,
  mas foi arquivado pelo autor em março de 2020 e não recebe mais
  manutenção.
- [`GetDFPData2`](https://github.com/msperlin/GetDFPData2) é mantido
  ativamente e é a escolha certa quando se precisa só do DFP. O
  `get_dfp_data()` cobre os formulários *anuais*; ITR, FRE e o cadastro
  (CAD) estão fora do escopo.

O `cvmdata` unifica CAD, ITR, DFP e FRE atrás de uma única
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md),
com filtros consistentes para companhias (CNPJ ou ticker da B3) e
períodos (anos inteiros ou janela de datas pela data de referência),
cache HTTP com revalidação por ETag/Last-Modified e janela TTL
configurável, e o dicionário e as codelists da CVM embarcados como
snapshots (tipos de coluna e valores categóricos canônicos, sem consulta
em tempo de execução).

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
  [`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md),
  o entry point das versões anteriores, está depreciada e será removida
  em uma release futura.
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
  publica o CSV daquele ano sem linhas de dados.
- `"cvm"` — HTTP direto ao Portal de Dados Abertos da CVM. Use quando
  precisar de frescor byte a byte contra o regulador, ou quando preferir
  não depender de um espelho de terceiro.

Todo tibble retornado carrega atributos de proveniência (`source`,
`fetched_at`, `group`, `dataset`, `table`, `package_version`),
permitindo a qualquer consumidor auditar qual backend serviu os dados.

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
