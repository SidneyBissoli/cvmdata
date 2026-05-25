# cvm_fetch(): the generic API

`cvm_fetch(dataset, table, ...)` is the single entry point for every CVM
dataset and every table covered by the package.
[`cad_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cad_fetch.md)
and any future dataset-specific helpers are thin wrappers around it.

This article walks through each argument, the company-detection logic,
the years semantics, the `report_type` rule, the `validate` and
`on_error` modes, and the cache/source plumbing.

``` r

library(cvmdata)
```

## Anatomy

``` r

cvm_fetch(
  dataset,
  table,
  companies   = NULL,
  years       = NULL,
  source      = NULL,
  report_type = NULL,
  on_error    = "abort",
  validate    = "strict",
  ...
)
```

Returns a tibble of subclass `cvm_tbl` carrying five provenance
attributes (`source`, `fetched_at`, `dataset`, `table`,
`package_version`). Column names, table names and categorical values are
preserved in Portuguese as published by CVM; the API surface is in
English.

``` r

bb_bpa <- cvm_fetch(
  "dfp", "bpa",
  report_type = "ind",
  companies   = "1023",
  years       = 2024
)
bb_bpa
#> ℹ source: "mirror" | fetched_at: 2026-05-25 02:03:27.158161
#> ℹ dataset: "dfp" | table: "bpa"
#> # A tibble: 96 × 15
#>    cnpj_cia       dt_refer   versao denom_cia cd_cvm grupo_dfp moeda ordem_exerc
#>    <chr>          <date>     <chr>  <chr>     <chr>  <chr>     <chr> <chr>      
#>  1 00.000.000/00… 2024-12-31 1      BCO BRAS… 001023 DF Indiv… REAL  PENÚLTIMO  
#>  2 00.000.000/00… 2024-12-31 1      BCO BRAS… 001023 DF Indiv… REAL  ÚLTIMO     
#>  3 00.000.000/00… 2024-12-31 1      BCO BRAS… 001023 DF Indiv… REAL  PENÚLTIMO  
#>  4 00.000.000/00… 2024-12-31 1      BCO BRAS… 001023 DF Indiv… REAL  ÚLTIMO     
#>  5 00.000.000/00… 2024-12-31 1      BCO BRAS… 001023 DF Indiv… REAL  PENÚLTIMO  
#>  6 00.000.000/00… 2024-12-31 1      BCO BRAS… 001023 DF Indiv… REAL  ÚLTIMO     
#>  7 00.000.000/00… 2024-12-31 1      BCO BRAS… 001023 DF Indiv… REAL  PENÚLTIMO  
#>  8 00.000.000/00… 2024-12-31 1      BCO BRAS… 001023 DF Indiv… REAL  ÚLTIMO     
#>  9 00.000.000/00… 2024-12-31 1      BCO BRAS… 001023 DF Indiv… REAL  PENÚLTIMO  
#> 10 00.000.000/00… 2024-12-31 1      BCO BRAS… 001023 DF Indiv… REAL  ÚLTIMO     
#> # ℹ 86 more rows
#> # ℹ 7 more variables: dt_fim_exerc <date>, cd_conta <chr>, ds_conta <chr>,
#> #   vl_conta <dbl>, st_conta_fixa <chr>, report_type <chr>, year <int>

# Provenance:
attr(bb_bpa, "source")
#> [1] "mirror"
attr(bb_bpa, "dataset")
#> [1] "dfp"
attr(bb_bpa, "table")
#> [1] "bpa"
```

## Identifying companies

`companies` accepts a character vector. Each element is classified **per
element** by the pattern it matches:

| Pattern | Interpretation | Match against |
|----|----|----|
| 14 digits, no punctuation | CNPJ (clean) | `cnpj_clean(cnpj_cia)` |
| 14 digits with `.` / `/` / `-` | CNPJ (formatted) | `cnpj_cia` (literal) |
| 1–6 digits | CD_CVM | `cd_cvm` (with / without zero-padding) |
| Anything else (≥ 1 alphabetic token) | Free-text search | `denom_cia` (normalized) |

### CNPJ, CD_CVM, free text — same issuer, three calls

``` r

# Each call returns identical rows.
a <- cvm_fetch("dfp", "bpa", report_type = "ind",
               companies = "1023",                years = 2024)
b <- cvm_fetch("dfp", "bpa", report_type = "ind",
               companies = "001023",              years = 2024)
c <- cvm_fetch("dfp", "bpa", report_type = "ind",
               companies = "00.000.000/0001-91",  years = 2024)

identical(nrow(a), nrow(b))
#> [1] TRUE
identical(nrow(a), nrow(c))
#> [1] TRUE
```

### Free-text matching with abbreviations

Text search tokenizes the input by whitespace, normalizes (uppercase, no
accents, no punctuation), applies a built-in abbreviation map
(`BANCO ↔︎ BCO`, `COMPANHIA ↔︎ CIA`, etc.) and requires every token to
match `denom_cia` with a word boundary.

``` r

# A distinctive stem resolves cleanly to one issuer:
magalu <- cvm_fetch("dfp", "bpa", report_type = "ind",
                    companies = "MAGAZINE LUIZA", years = 2024)
unique(magalu$denom_cia)
#> [1] "MAGAZINE LUIZA S.A."
```

A non-unique stem aborts (in batch) with the list of candidates so
scripts never silently grab the wrong issuer:

``` r

cvm_fetch("dfp", "bpa", report_type = "ind",
          companies = "BCO BRASIL", years = 2024)
#> Error in `abort_on_multiple_matches()`:
#> ! Multiple companies match "BCO BRASIL".
#> ℹ Pass `companies` as CD_CVM or CNPJ to disambiguate, or run interactively to
#>   pick from a menu.
#> • 021466 : BANCO RCI BRASIL S.A.
#> • 020958 : BCO ABC BRASIL S.A.
#> • 001023 : BCO BRASIL S.A.
#> • 001325 : BCO MERCANTIL DO BRASIL S.A.
#> • 001228 : BCO NORDESTE DO BRASIL S.A.
#> • 020532 : BCO SANTANDER (BRASIL) S.A.
```

In [`interactive()`](https://rdrr.io/r/base/interactive.html) sessions
an [`utils::menu()`](https://rdrr.io/r/utils/menu.html) prompt appears
instead. Zero matches abort with the same error class.

### CD_CVM lookup for tables without `cd_cvm`

Some tables (e.g. `composicao_capital`, `parecer` in ITR/DFP) do not
carry a `cd_cvm` column. When the user passes CD_CVM tokens against such
a table,
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
reads the dataset’s `submissao` for the same year, looks up CNPJ for
each CD_CVM and applies the filter on CNPJ. The interface is identical
to the user:

``` r

cap <- cvm_fetch("dfp", "composicao_capital",
                 companies = "1023", years = 2024)
#> ℹ Resolving CD_CVM 1023 via "dfp"/submissao for 2024 (table
#>   "composicao_capital" does not carry `cd_cvm`).
cap
#> ℹ source: "mirror" | fetched_at: 2026-05-25 02:03:32.33073
#> ℹ dataset: "dfp" | table: "composicao_capital"
#> # A tibble: 1 × 11
#>   cnpj_cia           dt_refer   versao denom_cia       qt_acao_ordin_cap_integr
#>   <chr>              <date>     <chr>  <chr>                              <dbl>
#> 1 00.000.000/0001-91 2024-12-31 1      BCO BRASIL S.A.               5730834040
#> # ℹ 6 more variables: qt_acao_pref_cap_integr <dbl>,
#> #   qt_acao_total_cap_integr <dbl>, qt_acao_ordin_tesouro <dbl>,
#> #   qt_acao_pref_tesouro <dbl>, qt_acao_total_tesouro <dbl>, year <int>
```

## Selecting years

`years` is an integer vector. `NULL` (default) fetches the **latest
available year**, discovered by HEAD-probing CVM’s listing.

``` r

# What's published upstream?
cvm_dataset_years("dfp")
#>  [1] 2010 2011 2012 2013 2014 2015 2016 2017 2018 2019 2020 2021 2022 2023 2024
#> [16] 2025 2026

# Pass an explicit vector to back-fill history:
history <- cvm_fetch("dfp", "bpa", report_type = "ind",
                     companies = "1023", years = 2022:2024)
sort(unique(format(history$dt_refer, "%Y")))
#> [1] "2022" "2023" "2024"
```

Each CSV publishes `ORDEM_EXERC ∈ {ÚLTIMO, PENÚLTIMO}` — the declared
year and N − 1. The antepenultimate of year N is the last of year N − 2.
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
does not synthesize the antepenultimate; ask for `years = (N - 2):N` if
you need it.

``` r

table(history$ordem_exerc)
#> 
#> PENÚLTIMO    ÚLTIMO 
#>       144       144
```

### Partial failure with `on_error`

For multi-year calls (more than one element in `years`),
`on_error = "warn"` keeps surviving years and emits
`cvmdata_warn_partial_failure` listing failures. `on_error = "silent"`
does the same without the warning. `on_error = "abort"` (default) aborts
at the first HTTP failure. Total failure (every year fails) always
aborts regardless. Single-year calls, non-yearly tables (CAD) and the
implicit `years = NULL` fallback always abort on HTTP failure.

Parse and schema-validation failures are governed by `validate`, not by
`on_error` — schema drift is treated as a separate signal.

## `report_type`

Eight tables in ITR/DFP publish both **individual** and **consolidated**
variants of the same concept (`bpa`, `bpp`, `dre`, `dra`, `dfc_md`,
`dfc_mi`, `dmpl`, `dva`). `report_type` is **required** for those:

``` r

cvm_fetch("dfp", "bpa", companies = "1023", years = 2024)
#> Error in `validate_mirror_args()`:
#> ! Table "dfp"/"bpa" requires `report_type` ("ind" or "con").
```

And **must be `NULL`** for tables without the distinction (`companhias`,
`submissao`, `parecer`, `composicao_capital`):

``` r

cvm_fetch("dfp", "composicao_capital",
          companies = "1023", years = 2024,
          report_type = "ind")
#> Error in `validate_mirror_args()`:
#> ! Table "dfp"/"composicao_capital" does not support `report_type`; pass
#>   `NULL`.
```

## `validate`

Controls the strictness of schema validation at parse time. Three modes:

| Mode | Table with META published | Table with `meta_status: missing` |
|----|----|----|
| `"strict"` | Validates; mismatch aborts. | Aborts with `cvmdata_error_meta_unavailable`. |
| `"warn"` | Validates; mismatch warns. | Warns with `cvmdata_warn_meta_unavailable`; data returned. |
| `"skip"` | Skips validation silently. | Skips silently. |

The eight FRE tables without published META (`empregado_PCD`,
`empregado_local_declaracao_genero`, etc.) need `validate = "warn"` or
`"skip"` to be readable. See the **fre** article for a worked example.

## Cache, TTL and source backend

Downloaded artefacts are cached under
`tools::R_user_dir("cvmdata", "cache")`. Each ZIP / CSV stores an
ETag/Last-Modified sidecar; HTTP revalidation is throttled by a 30-day
TTL (configurable via `options(cvmdata.cache_ttl_seconds)`). Cached
units are LRU-evicted once total size exceeds the limit set by
`options(cvmdata.cache_max_size_mb)` (default 100 MiB).

``` r

info <- cvm_cache_info()
info
#> # A tibble: 4 × 7
#>   dataset file          path  size_bytes mtime               etag  last_modified
#>   <chr>   <chr>         <chr>      <int> <dttm>              <chr> <chr>        
#> 1 dfp     dfp_cia_aber… /hom…     182978 2026-05-25 02:03:32  NA   NA           
#> 2 dfp     dfp_cia_aber… /hom…   13395083 2026-05-25 02:03:32 "\"6… Sun, 24 May …
#> 3 fre     fre_cia_aber… /hom…    1085173 2026-05-25 02:03:22  NA   NA           
#> 4 fre     fre_cia_aber… /hom…    8408826 2026-05-25 02:03:22 "\"6… Sun, 24 May …
attr(info, "total_size_bytes")
#> [1] 23072432
```

`source` selects the backend: from v0.1.0 the default is `"mirror"`,
which reads parquet snapshots from GitHub Releases via DuckDB with
year-partition filter pushdown; `"cvm"` reads the open-data portal over
HTTP and remains fully supported. The current backend is read by
[`cvm_source_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_get.md)
and changed at session scope by
[`cvm_source_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_set.md):

``` r

cvm_source_get()
#> [1] "mirror"
```

## Where to read next

- **itr-dfp** — quarterly and annual financial statements; two
  end-to-end workflows.
- **fre** — reference form, including the eight ESG/governance tables
  without published META.
- **cvm-defects** — known publication quirks and how `cvmdata` handles
  each one.
