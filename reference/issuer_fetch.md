# Fetch a CVM open-data table for an issuer dataset (deprecated)

`issuer_fetch()` was superseded by
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md),
the single public fetcher, and is deprecated: every call warns once per
session and the function will be removed in a later release. Migrate by
selecting issuers with `cnpj` (CNPJ only) or `ticker` (B3 code) instead
of `issuer`, and the statement basis with `basis` instead of
`report_type`.
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
does not take CVM codes or company names; look them up in
`cvm_fetch("cad", "companhias")`.

Until removal the function keeps its original behaviour: it selects the
right URL, downloads (or serves from cache), parses, applies
schema-declared transformations, and returns a tibble carrying
provenance attributes. Column names, categorical values and free-text
fields are preserved in Portuguese exactly as published by CVM
(snake_case minúsculo).

## Usage

``` r
issuer_fetch(
  dataset,
  table,
  issuer = NULL,
  year = NULL,
  source = NULL,
  report_type = NULL,
  on_error = "abort",
  validate = "strict",
  ...
)
```

## Arguments

- dataset:

  Short dataset id (e.g. `"cad"`, `"dfp"`).

- table:

  Snake-case table name (e.g. `"companhias"`, `"bpa"`). For datasets
  with conceptually paired tables (individual / consolidated), `table`
  is the concept name and `report_type` selects the variant.

- issuer:

  Optional character vector identifying issuers to include. Accepts CNPJ
  (with or without punctuation), CD_CVM (with or without zero-padding),
  a B3 trading ticker (e.g. `"PETR4"`, `"BBDC11"`), or free-text matched
  against `denom_cia`. Detection is automatic per element; a ticker is
  resolved to its issuer CNPJ via `fca/valor_mobiliario`. `NULL`
  (default) returns every issuer. Singular naming follows tidyverse
  conventions; the argument still accepts vectors of any length. When
  the target table does not carry a `cd_cvm` column (e.g.
  `composicao_capital`, `parecer`), CD_CVM tokens are resolved to CNPJ
  via the dataset's `submissao` table for the same year — the
  user-facing interface is identical regardless of which table holds
  CD_CVM natively.

- year:

  Integer vector of years to fetch. `NULL` (default) fetches the latest
  available year. Ignored for datasets with
  `temporal_partitioning: none` (e.g. CAD). Singular naming follows
  tidyverse conventions; the argument still accepts vectors of any
  length.

- source:

  One of `"mirror"` (parquet via DuckDB) or `"cvm"` (CVM Open Data
  Portal). `NULL` (default) resolves to the active backend via
  [`cvm_source_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_get.md)
  — `"mirror"` from v0.1.0 onward unless the user has flipped it via
  `cvm_source_set("cvm")`.

- report_type:

  One of `"ind"`, `"con"`, or `NULL`. Required for tables that publish
  individual and consolidated variants (`bpa`, `bpp`, `dre`, `dra`,
  `dfc_md`, `dfc_mi`, `dmpl`, `dva`). Must be `NULL` for tables without
  that distinction (`composicao_capital`, `submissao`, `parecer`,
  `companhias`).

- on_error:

  One of `"abort"` (default), `"warn"` or `"silent"`. Controls behaviour
  on HTTP failures for batches of yearly tables (`year = c(...)` with
  more than one element). With `"warn"`, the failed years are skipped
  and a `cvmdata_warn_partial_failure` warning lists them; with
  `"silent"`, the failed years are skipped silently; with `"abort"`, the
  first failure aborts the call. Total batch failure (every year fails)
  always aborts regardless of the setting — there is no partial result
  to return. Parse/validation failures are governed by `validate`, not
  `on_error`. Single-year calls, non-yearly tables, and the implicit
  fallback when `year = NULL` always abort on HTTP failure.

- validate:

  One of `"strict"` (default), `"warn"` or `"skip"`. Controls schema
  validation strictness at parse time.

- ...:

  Reserved for forward compatibility. Currently no extra arguments are
  accepted; passing any aborts with `cvmdata_error_input`.

## Value

A tibble of class `cvm_tbl` carrying the five provenance attributes
`source`, `fetched_at`, `dataset`, `table` and `package_version`.

## Filing versions

When a detail table carries several filings for the same issuer and
reference date, only the last one delivered is kept, ranked by receipt
date, then CVM document id, then `versao`. The version number alone is
not a filing key: the CVM index can list two filings under the same
version, or a later filing under a lower one.

The `submissao` table of each dataset is the filing index and is not
collapsed: it returns one row per delivery, re-filings included, with
the receipt date (`dt_receb` or `data_entrega`), the document id
(`id_doc`, `id_documento` or `protocolo_entrega`) and `versao`. The
current filing of an issuer and reference date is the last row by that
order; joining `submissao` to a detail table on the issuer and reference
date alone matches every delivery.

Tables of datasets with a `submissao` index are checked against it
before returning. In DFP and ITR tables, rows the CVM file holds twice
are dropped (`cvmdata_warn_duplicate_filing`); copies that differ in
`vl_conta` are kept (`cvmdata_warn_conflicting_filing`). A table holding
an earlier filing than the last delivery keeps the CVM numbers and warns
(`cvmdata_warn_stale_filing`). Set
`options(cvmdata.check_filings = FALSE)` to skip these checks.

## See also

[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)

## Examples

``` r
if (FALSE) { # interactive()
# CAD: single snapshot, no temporal partitioning, no report_type
issuers <- issuer_fetch("cad", "companhias")

# DFP BPA individual, latest year, single issuer
bb <- issuer_fetch("dfp", "bpa",
                   report_type = "ind",
                   issuer = "BCO BRASIL",
                   year = 2024)
}
```
