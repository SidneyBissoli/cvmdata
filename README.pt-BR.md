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

## Por que cvmdata

A CVM publica os formulários em ZIPs anuais de CSVs com codificação
ISO-8859-1, schema específico por tabela e sem dicionário de dados
unificado. Workflows comuns — “me dá o DFP da empresa X de 2018 a 2024”
— exigem download manual, tratamento de encoding, conversão de
`VL_CONTA` por `ESCALA_MOEDA` e join contra uma `submissao` separada
para traduzir CD_CVM em CNPJ. O `cvmdata` consolida tudo isso atrás de
uma chamada `issuer_fetch(dataset, table, issuer, year, ...)` e embarca
o dicionário oficial como snapshot, então os tipos de coluna vêm
prontos.

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
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md),
com filtros consistentes para companhias (CNPJ / CD_CVM / texto livre
com expansão de abreviações), cache HTTP com revalidação por
ETag/Last-Modified e janela TTL configurável, e o dicionário e as
codelists da CVM embarcados como snapshots (tipos de coluna e valores
categóricos canônicos, sem consulta em tempo de execução).

## Instalação

`cvmdata` exige R ≥ 4.1 (pipe nativo) e ainda não está no CRAN. A versão
de desenvolvimento pode ser instalada do GitHub:

``` r

# install.packages("pak")
pak::pak("SidneyBissoli/cvmdata")
```

## Início rápido

Descubra o que está coberto (offline — a descoberta lê de snapshots
embarcados):

``` r

library(cvmdata)

cvm_datasets()
#> [1] "cad" "dfp" "fre" "itr"
```

O dicionário embarcado expõe os tipos e descrições que a CVM publica
para cada coluna:

``` r

dict <- cvm_dictionary("dfp", "bpa")
tbl <- knitr::kable(
  dict[1:8, c("campo", "descricao", "tipo_dados", "tamanho")],
  format = "html"
)
cat('<div align="center">', tbl, '</div>', sep = "\n")
```

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
para duas companhias em anos recentes. Companhias podem ser
identificadas por CNPJ, CD_CVM ou texto livre — neste último caso com
expansão de abreviações (`BANCO` casa `BCO`, `COMPANHIA` casa `CIA`, e
assim por diante):

``` r

bpa <- issuer_fetch(
  dataset     = "dfp",
  table       = "bpa",
  report_type = "ind",
  issuer = c("BCO BRASIL", "MAGAZINE LUIZA"),
  year = 2022:2024
)
```

Limpe e formate CNPJs:

``` r

cnpj_clean("00.000.000/0001-91")
#> [1] "00000000000191"
cnpj_format("00000000000191")
#> [1] "00.000.000/0001-91"
```

## Documentação

Referência e artigos em <https://sidneybissoli.github.io/cvmdata/>. A
API exportada está agrupada em cinco famílias:

- **Fetchers** —
  [`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)
  é o entry point único para todos os datasets de emissor. Quatro
  fetchers irmãos por contrato —
  [`fund_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/fund_fetch.md),
  [`agent_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/agent_fetch.md),
  [`offering_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/offering_fetch.md)
  e
  [`event_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/event_fetch.md)
  — já estão exportados como skeletons na v0.1.0.9000; chamá-los aborta
  com `cvmdata_error_input_group`. Implementação plena chega a partir da
  v0.4.
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

## Proveniência dos dados

Os dados vêm do Portal de Dados Abertos da CVM
(<https://dados.cvm.gov.br/>). O backend ativo é selecionável via
[`cvm_source_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_set.md)
(ou pelo argumento `source` de
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)):

- `"mirror"` (default a partir da v0.1.0) — snapshots em parquet
  publicados em GitHub Releases e consultados via DuckDB com filter
  pushdown por ano, atualizados semanalmente por um workflow de ETL
  neste repositório.
- `"cvm"` — HTTP direto ao Portal de Dados Abertos da CVM. Selecionável
  por chamada quando se precisa de frescor byte a byte contra o
  regulador.

Todo tibble retornado carrega atributos de proveniência (`source`,
`fetched_at`, `group`, `dataset`, `table`, `package_version`),
permitindo a qualquer consumidor auditar qual backend serviu os dados.

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
