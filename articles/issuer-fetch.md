# cvm_fetch(): the generic API

`cvm_fetch(dataset, table, ...)` is the single entry point for every CVM
dataset and every table covered by the package.

This article walks through each argument: how issuers are selected
(`cnpj`, `ticker`), how the period is selected (`year` or `from`/`to`),
the `basis` rule for financial statements, the `validate` and `on_error`
modes, and the cache/source plumbing.

[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md),
the entry point of v0.1 and v0.2, is deprecated: it still works, with a
lifecycle warning, and will be removed in a later release. Its `issuer`
argument (CNPJ, CD_CVM, free text or ticker) and `report_type` map onto
the arguments described here.

``` r

library(cvmdata)
```

## Anatomy

``` r

cvm_fetch(
  dataset,
  table,
  cnpj     = NULL,
  ticker   = NULL,
  year     = NULL,
  from     = NULL,
  to       = NULL,
  basis    = NULL,
  source   = NULL,
  on_error = "abort",
  validate = "strict",
  ...
)
```

Returns a tibble of subclass `cvm_tbl` carrying six provenance
attributes (`source`, `fetched_at`, `group`, `dataset`, `table`,
`package_version`). Column names, table names and categorical values are
preserved in Portuguese as published by CVM; the API surface is in
English.

``` r

bb_bpa <- cvm_fetch(
  "dfp", "bpa",
  cnpj = "00.000.000/0001-91",
  year = 2024,
  basis = "ind"
)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp3XseBV/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp3XseBV/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
bb_bpa
#> ℹ source: "mirror" | fetched_at: 2026-10-20 01:09:03.750886
#> ℹ group: "companhias" | dataset: "dfp" | table: "bpa"
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
#> #   vl_conta <dbl>, st_conta_fixa <chr>, year <int>, basis <chr>

# Provenance:
attr(bb_bpa, "source")
#> [1] "mirror"
attr(bb_bpa, "dataset")
#> [1] "dfp"
attr(bb_bpa, "table")
#> [1] "bpa"
```

## Identifying issuers

[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
identifies issuers by two keys only, and the two combine in a single
call:

| Argument | Accepts | Match against |
|----|----|----|
| `cnpj` | CNPJ, with or without punctuation, vector of any length | `cnpj_cia` / `cnpj_companhia`, punctuation stripped |
| `ticker` | B3 trading code (`PETR4`, `BBAS3`, `BBDC11`) | `codigo_negociacao` in `fca/valor_mobiliario`, resolved to the issuer’s CNPJ |

A CVM code (`"1023"`) or a company name (`"BCO BRASIL"`) passed as
`cnpj` aborts with `cvmdata_error_input`: there is no free-text search
and no CD_CVM lookup in
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md).
To find the CNPJ of a company you know by name or by CVM code, read the
registry, which carries `cd_cvm`, `denom_social` and `cnpj_cia` side by
side:

``` r

registry <- cvm_fetch("cad", "companhias")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp3XseBV/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
registry[grepl("MAGAZINE LUIZA", registry$denom_social),
         c("cd_cvm", "denom_social", "cnpj_cia")]
#> ℹ source: "mirror" | fetched_at: 2026-10-20 01:09:04.245322
#> ℹ group: "companhias" | dataset: "cad" | table: "companhias"
#> # A tibble: 1 × 3
#>   cd_cvm denom_social      cnpj_cia          
#>   <chr>  <chr>             <chr>             
#> 1 22470  MAGAZINE LUIZA SA 47.960.950/0001-21
```

### CNPJ: punctuated or clean, same rows

``` r

# Each call returns identical rows.
a <- cvm_fetch("dfp", "bpa", cnpj = "00.000.000/0001-91",
               year = 2024, basis = "ind")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp3XseBV/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp3XseBV/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
b <- cvm_fetch("dfp", "bpa", cnpj = "00000000000191",
               year = 2024, basis = "ind")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp3XseBV/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp3XseBV/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.

identical(nrow(a), nrow(b))
#> [1] TRUE
```

A CNPJ absent from the table yields zero rows for it, silently — a miss
on a taxpayer id is not a typo the package can second-guess.

### Ticker: resolved through the registration form

A B3 trading code is looked up in `fca/valor_mobiliario` (read from the
same `source` as the data), keeping only securities still traded, and
the issuer’s CNPJ is then filtered exactly as `cnpj` would be. Tickers
cover only exchange-listed securities; an unknown ticker aborts with
`cvmdata_error_input` rather than returning an empty tibble.

``` r

petr <- cvm_fetch("dfp", "bpa", ticker = "PETR4",
                  year = 2024, basis = "con")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp3XseBV/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp3XseBV/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp3XseBV/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
unique(petr$denom_cia)
#> [1] "PETROLEO BRASILEIRO S.A. PETROBRAS"
```

`cnpj` and `ticker` combine; the result is the union of both sets:

``` r

two <- cvm_fetch("dfp", "bpa",
                 cnpj = "00.000.000/0001-91",
                 ticker = "MGLU3",
                 year = 2024, basis = "ind")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp3XseBV/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp3XseBV/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
unique(two$denom_cia)
#> [1] "BCO BRASIL S.A."     "MAGAZINE LUIZA S.A."
```

## Selecting the period

Two mutually exclusive forms; passing both aborts.

### Whole years with `year`

`year` is an integer vector of any length (singular naming follows
tidyverse conventions), matching the yearly files the CVM publishes.
`NULL` (default) fetches the **latest available year**, discovered by
HEAD-probing CVM’s listing (or from the mirror’s inventory). Must be
`NULL` for snapshot tables such as `cad/companhias`.

``` r

# What's published upstream?
cvm_dataset_years("dfp")
#>  [1] 2010 2011 2012 2013 2014 2015 2016 2017 2018 2019 2020 2021 2022 2023 2024
#> [16] 2025 2026

# Pass an explicit vector to back-fill history:
history <- cvm_fetch("dfp", "bpa", cnpj = "00.000.000/0001-91",
                     year = 2022:2024, basis = "ind")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp3XseBV/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp3XseBV/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
sort(unique(format(history$dt_refer, "%Y")))
#> [1] "2022" "2023" "2024"
```

Each CSV publishes `ORDEM_EXERC ∈ {ÚLTIMO, PENÚLTIMO}` — the declared
year and N − 1. The antepenultimate of year N is the last of year N − 2.
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
does not synthesize the antepenultimate; ask for `year = (N - 2):N` if
you need it.

``` r

table(history$ordem_exerc)
#> 
#> PENÚLTIMO    ÚLTIMO 
#>       144       144
```

### A date window with `from` and `to`

For slices smaller than a year, pass `from` and `to` together as
complete dates (`"YYYY-MM-DD"` strings or `Date` scalars). Rows are kept
when the document’s **reference date** (`dt_refer` in CAD/ITR/DFP-style
tables, `data_referencia` in FRE-style tables) falls inside the window;
the yearly files actually read are the years the window spans. The
reference date is the period the filing describes, not the day it was
delivered.

``` r

# ITR balance sheets referenced in the first half of 2024
h1 <- cvm_fetch("itr", "bpa", cnpj = "00.000.000/0001-91",
                from = "2024-01-01", to = "2024-06-30",
                basis = "con")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp3XseBV/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp3XseBV/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
unique(h1$dt_refer)
#> [1] "2024-03-31" "2024-06-30"
```

Incomplete dates (`"2024"`, `"2024-06"`) are rejected, as is a window on
a snapshot table. One bound without the other aborts; for whole years
use `year`.

### Partial failure with `on_error`

When several yearly files are read (more than one element in `year`, or
a window spanning several years), `on_error = "warn"` keeps surviving
years and emits `cvmdata_warn_partial_failure` listing failures.
`on_error = "silent"` does the same without the warning.
`on_error = "abort"` (default) aborts at the first HTTP failure. Total
failure (every year fails) always aborts regardless. Single-year calls,
non-yearly tables (CAD) and the implicit `year = NULL` fallback always
abort on HTTP failure.

Parse and schema-validation failures are governed by `validate`, not by
`on_error` — schema drift is treated as a separate signal.

## `basis`

Eight tables in ITR/DFP publish both **individual** and **consolidated**
variants of the same concept (`bpa`, `bpp`, `dre`, `dra`, `dfc_md`,
`dfc_mi`, `dmpl`, `dva`). `basis` is **required** for those, with no
default: many issuers file only individual statements, so defaulting to
`"con"` would silently drop them.

``` r

cvm_fetch("dfp", "bpa", cnpj = "00.000.000/0001-91", year = 2024)
#> Error in `check_basis()`:
#> ! Table "dfp"/"bpa" requires `basis`.
#> ℹ Pass `basis = "ind"` for individual statements, `basis = "con"` for
#>   consolidated, or `basis = c("ind", "con")` for both.
```

`basis` takes `"ind"`, `"con"` or `c("ind", "con")`. With both, the two
variants are read and stacked. Whatever you ask for, those eight tables
**always carry a `basis` column** in the result, so a single value and a
stacked pair have the same shape:

``` r

both <- cvm_fetch("dfp", "bpa", cnpj = "00.000.000/0001-91",
                  year = 2024, basis = c("ind", "con"))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp3XseBV/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp3XseBV/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp3XseBV/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp3XseBV/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
table(both$basis)
#> 
#> con ind 
#>  82  96
"basis" %in% names(bb_bpa)
#> [1] TRUE
```

On every other table (`companhias`, `submissao`, `parecer`,
`composicao_capital`, every FRE/FCA detail table) `basis` must be left
unset; passing it aborts rather than being ignored:

``` r

cvm_fetch("dfp", "composicao_capital",
          cnpj = "00.000.000/0001-91", year = 2024,
          basis = "ind")
#> Error in `check_basis()`:
#> ! Table "dfp"/"composicao_capital" has no individual/consolidated split;
#>   leave `basis` unset.
#> ✖ Got "ind".
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
#> # A tibble: 0 × 8
#> # ℹ 8 variables: group <chr>, dataset <chr>, file <chr>, path <chr>,
#> #   size_bytes <int>, mtime <dttm>, etag <chr>, last_modified <chr>
attr(info, "total_size_bytes")
#> [1] 0
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
