# cvmdata

**English** \|
[Português](https://sidneybissoli.github.io/cvmdata/README.pt-BR.md)

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

`cvmdata` unifies CAD, ITR, DFP and FRE behind a single
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
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

- **Fetchers** —
  [`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md),
  [`cad_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cad_fetch.md)
  (alias kept for ergonomics).
- **Discovery** —
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
  The TTL window for HTTP revalidation is configurable via
  `options(cvmdata.cache_ttl_seconds)` (default 30 days).
- **Source backend** —
  [`cvm_source_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_get.md),
  [`cvm_source_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_set.md).
  The cache/mirror integration is documented in detail in the
  [cache-and-mirror](https://sidneybissoli.github.io/cvmdata/articles/cache-and-mirror.html)
  article.
- **Utilities** —
  [`cnpj_clean()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_clean.md),
  [`cnpj_format()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_format.md).

## Data provenance

Data is fetched from the official CVM Open Data Portal
(<https://dados.cvm.gov.br/>). The active backend is selectable via
[`cvm_source_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_set.md)
(or the `source` argument of
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)):

- `"cvm"` (default in v0.1) — HTTP directly to the CVM Open Data Portal.
- `"mirror"` (default from the release that ships Phase F) — parquet
  snapshots in GitHub Releases queried via DuckDB with year-partition
  filter pushdown, refreshed weekly by an ETL workflow in this repo.

Every returned tibble carries provenance attributes (`source`,
`fetched_at`, `dataset`, `table`, `package_version`) so a downstream
caller can audit which backend served the data.

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

## Contributing

Pull requests are welcome. See
[CONTRIBUTING.md](https://sidneybissoli.github.io/cvmdata/CONTRIBUTING.md)
for the development setup, the quality gate run on every commit, and the
schema-YAML format used when adding a new dataset.

Please note that the cvmdata project is released with a [Contributor
Code of
Conduct](https://sidneybissoli.github.io/cvmdata/CODE_OF_CONDUCT.md). By
contributing to this project, you agree to abide by its terms.

## License

MIT © Sidney Bissoli.
