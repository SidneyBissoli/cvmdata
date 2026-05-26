# Fetch a CVM open-data table for a regulatory-event dataset

Single entry point for retrieving any table from any CVM event-class
dataset covered by the package. Covers sanctioning proceedings
(`atividade-sancionadora`) and declaratory acts issued by the CVM
directors (`atos-declaratorios`).

## Usage

``` r
event_fetch(
  dataset,
  table,
  event = NULL,
  date_range = NULL,
  source = NULL,
  on_error = "abort",
  validate = "strict",
  ...
)
```

## Arguments

- dataset:

  Short dataset id (e.g. `"sancionadora"`, `"atos-declaratorios"`).

- table:

  Snake-case table name within the dataset.

- event:

  Optional character vector of event identifiers (`nr_processo` for
  sanctioning proceedings, `nr_ato` for declaratory acts). `NULL`
  (default) returns every event in the date range. Singular naming
  follows tidyverse conventions; the argument still accepts vectors of
  any length.

- date_range:

  Optional `Date` vector of length 2 specifying the event date window:
  `c(from, to)`. `NULL` (default) returns every event ever published.
  Vectors of length other than 2 abort with `cvmdata_error_input`.

- source:

  One of `"mirror"` (parquet via DuckDB) or `"cvm"` (CVM Open Data
  Portal). `NULL` (default) resolves to the active backend via
  [`cvm_source_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_get.md).

- on_error:

  One of `"abort"` (default), `"warn"` or `"silent"`. Controls behaviour
  on HTTP failures, analogously to
  [`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md).

- validate:

  One of `"strict"` (default), `"warn"` or `"skip"`. Controls schema
  validation strictness at parse time.

- ...:

  Reserved for forward compatibility. Currently no extra arguments are
  accepted; passing any aborts with `cvmdata_error_input`.

## Value

A tibble of class `cvm_tbl` carrying the five provenance attributes
`source`, `fetched_at`, `dataset`, `table` and `package_version`.

## Details

Column names, categorical values and free-text fields are preserved in
Portuguese exactly as published by CVM (snake_case minúsculo).

In v0.1.0.9000 the function is exported as a skeleton documenting the
planned contract; calling it aborts with `cvmdata_error_input_group`
pointing to ROADMAP.md. Full implementation arrives in v0.8.

## See also

Other fetchers:
[`agent_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/agent_fetch.md),
[`fund_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/fund_fetch.md),
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md),
[`offering_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/offering_fetch.md)

## Examples

``` r
if (FALSE) {
# Available from v0.8 onwards (atividade-sancionadora):
procs <- event_fetch("sancionadora", "processos",
                     date_range = as.Date(
                       c("2024-01-01", "2024-12-31")
                     ))

# Declaratory acts:
atos <- event_fetch("atos-declaratorios", "atos")
}
```
