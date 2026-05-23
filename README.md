
<!-- README.md is generated from README.Rmd. Please edit that file. -->

# cvmdata

<!-- badges: start -->

[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/SidneyBissoli/cvmdata/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/SidneyBissoli/cvmdata/actions/workflows/R-CMD-check.yaml)
[![Codecov test
coverage](https://codecov.io/gh/SidneyBissoli/cvmdata/graph/badge.svg)](https://app.codecov.io/gh/SidneyBissoli/cvmdata)
[![pkgdown](https://github.com/SidneyBissoli/cvmdata/actions/workflows/pkgdown.yaml/badge.svg)](https://github.com/SidneyBissoli/cvmdata/actions/workflows/pkgdown.yaml)
[![CRAN
status](https://www.r-pkg.org/badges/version/cvmdata)](https://CRAN.R-project.org/package=cvmdata)
<!-- badges: end -->

`cvmdata` provides a tidy API to the open data published by the
Brazilian Securities and Exchange Commission (CVM — Comissão de Valores
Mobiliários). The first release covers the core publicly-traded-company
datasets: company registry (`cad`), quarterly financial statements
(`itr`), annual financial statements (`dfp`) and the reference form
(`fre`), the latter including ESG/governance tables on board diversity,
compensation and shareholder structure.

The package preserves table names, column names, categorical values and
free text in Portuguese exactly as CVM publishes them. Function names,
arguments and metadata attributes follow English-language rOpenSci and
tidyverse conventions.

## Why cvmdata

CVM publishes filings as yearly ZIPs of CSVs with mixed encodings,
table-specific schemas, and no unified data dictionary. Common workflows
— “give me DFP for company X across 2018-2024” — typically require
manual ZIP downloads, ISO-8859-1 handling, scale-by-`ESCALA_MOEDA`
conversion, and joins against a separate `submissao` header to translate
CD_CVM to CNPJ. `cvmdata` consolidates these steps behind a single
`cvm_fetch(dataset, table, companies, years, ...)` call and ships the
official dictionary as an embedded snapshot, so column types are picked
up automatically.

Two existing R packages by Marcelo Perlin address adjacent slices of
this problem:

- [`GetITRData`](https://github.com/msperlin/GetITRData) covered the
  quarterly statements (ITR), but was archived by its author in March
  2020 and is no longer maintained.
- [`GetDFPData2`](https://github.com/msperlin/GetDFPData2) is actively
  maintained and is the right choice if you need DFP only. Its exported
  API (`get_dfp_data()`) covers the *annual* statements; ITR, FRE and
  the company registry (CAD) are out of scope.

`cvmdata` unifies CAD, ITR, DFP and FRE behind a single `cvm_fetch()`
entry point, with consistent filtering semantics for companies (CNPJ /
CD_CVM / free text with abbreviation expansion),
ETag/Last-Modified-aware HTTP caching with a configurable TTL window,
and the CVM dictionary and code lists shipped as embedded snapshots (so
column types and categorical values are canonical without a runtime
fetch).

## Installation

`cvmdata` requires R ≥ 4.1 (native pipe) and is not yet on CRAN. The
development version can be installed from GitHub:

``` r
# install.packages("pak")
pak::pak("SidneyBissoli/cvmdata")
```

## Quick start

Browse what’s covered (offline — discovery reads from embedded
snapshots):

``` r
library(cvmdata)

cvm_datasets()
#> [1] "cad" "dfp" "fre" "itr"
```

The bundled dictionary surfaces the types and descriptions CVM publishes
for every column:

``` r
dict <- cvm_dictionary("dfp", "bpa")
knitr::kable(
  dict[1:8, c("column", "descricao", "tipo_dados", "tamanho")]
)
```

| column       | descricao                       | tipo_dados | tamanho |
|:-------------|:--------------------------------|:-----------|--------:|
| cd_conta     | Código da conta                 | varchar    |      18 |
| cd_cvm       | Código CVM                      | char       |       6 |
| cnpj_cia     | CNPJ da companhia               | varchar    |      20 |
| denom_cia    | Nome empresarial da companhia   | varchar    |     100 |
| ds_conta     | Descrição da conta              | varchar    |     100 |
| dt_fim_exerc | Data fim do exercício social    | date       |      10 |
| dt_refer     | Data de referência do documento | date       |      10 |
| escala_moeda | Escala monetária                | varchar    |     100 |

Fetch quarterly individual balance sheets (“BPA individual”) for two
companies across recent years. Companies can be identified by CNPJ,
CD_CVM, or free text — the latter with abbreviation expansion (`BANCO`
matches `BCO`, `COMPANHIA` matches `CIA`, and so on):

``` r
bpa <- cvm_fetch(
  dataset     = "dfp",
  table       = "bpa",
  report_type = "ind",
  companies   = c("BCO BRASIL", "MAGAZINE LUIZA"),
  years       = 2022:2024
)
```

Parse and format Brazilian corporate taxpayer IDs (CNPJ):

``` r
cnpj_clean("00.000.000/0001-91")
#> [1] "00000000000191"
cnpj_format("00000000000191")
#> [1] "00.000.000/0001-91"
```

## Documentation

Reference and articles at <https://sidneybissoli.github.io/cvmdata/>.
The exported API is grouped into five families:

- **Fetchers** — `cvm_fetch()`, `cad_fetch()` (alias kept for
  ergonomics).
- **Discovery** — `cvm_datasets()`, `cvm_tables()`, `cvm_dictionary()`,
  `cvm_codelist()`, `cvm_dataset_years()`.
- **Cache** — `cvm_cache_path()`, `cvm_cache_set_path()`,
  `cvm_cache_info()`, `cvm_cache_clear()`. The TTL window for HTTP
  revalidation is configurable via `options(cvmdata.cache_ttl_seconds)`
  (default 30 days).
- **Source backend** — `cvm_source_get()`, `cvm_source_set()`.
- **Utilities** — `cnpj_clean()`, `cnpj_format()`.

## Data provenance

Data is fetched from the official CVM Open Data Portal
(<https://dados.cvm.gov.br/>). A package-managed mirror on GitHub
Releases serves as automatic fallback when an upstream file becomes
unavailable. Every returned tibble carries provenance attributes
(`source`, `fetched_at`, `dataset`, `table`, `package_version`).

## Related work

For exchange-side market data (prices, volumes, tickers, indices,
trading calendars), the natural companion is
[`rb3`](https://github.com/wilsonfreitas/rb3) by Wilson Freitas (with
Marcelo Perlin as co-author), which downloads and parses public files
released by B3. `rb3` and `cvmdata` are complements: `cvmdata` covers
issuer-side filings released by the regulator (CVM); `rb3` covers
exchange-side trading data released by the market operator (B3).
Analyses that join market microstructure with financial statements use
the two side by side.

## Getting help

Bug reports and feature requests:
<https://github.com/SidneyBissoli/cvmdata/issues>.

## License

MIT © Sidney Bissoli.
