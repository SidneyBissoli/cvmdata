# cvmdata

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
cvm_tables("dfp")
#>  [1] "bpa"                "bpp"                "composicao_capital"
#>  [4] "dfc_md"             "dfc_mi"             "dmpl"              
#>  [7] "dra"                "dre"                "dva"               
#> [10] "parecer"            "submissao"
```

Fetch quarterly individual balance sheets (“BPA individual”) for two
companies across recent years. Companies can be identified by CNPJ,
CD_CVM, or free text — the latter with abbreviation expansion (`BANCO`
matches `BCO`, `COMPANHIA` matches `CIA`, and so on):

``` r

bpa <- cvm_fetch(
  "dfp", "bpa",
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
- **Utilities** —
  [`cnpj_clean()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_clean.md),
  [`cnpj_format()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_format.md).

## Data provenance

Data is fetched from the official CVM Open Data Portal
(<https://dados.cvm.gov.br/>). A package-managed mirror on GitHub
Releases serves as automatic fallback when an upstream file becomes
unavailable. Every returned tibble carries provenance attributes
(`source`, `fetched_at`, `dataset`, `table`, `package_version`).

## Related work

Two other R packages address overlapping problems:

- [`GetDFPData2`](https://github.com/msperlin/GetDFPData2) by Marcelo
  Perlin downloads DFP/ITR filings via the per-document RAD/ENET
  interface. Comprehensive coverage but typically ~30 s per document.
- [`GetITRData`](https://github.com/msperlin/GetITRData) is the earlier
  ITR-only sibling.

`cvmdata` differs by pulling the bulk yearly ZIPs from
`dados.cvm.gov.br` (~1 s per dataset-year for any number of companies),
shipping the official dictionary and code lists as embedded snapshots
(so column types and categorical values are canonical without a runtime
fetch), and unifying CAD / DFP / ITR / FRE behind a single
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
entry point with consistent filtering semantics for companies (`CNPJ` /
`CD_CVM` / free text).

## Getting help

Bug reports and feature requests:
<https://github.com/SidneyBissoli/cvmdata/issues>.

## License

MIT © Sidney Bissoli.
