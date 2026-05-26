# Fetch a CVM open-data table for a public-offering dataset

Single entry point for retrieving any table from any CVM offering-class
dataset covered by the package. Covers both registered public offerings
(`ofertas-publicas`) and crowdfunding-platform offerings under CVM
Resolution 88 (`plataformas-de-crowdfunding`).

## Usage

``` r
offering_fetch(
  dataset,
  table,
  offering = NULL,
  date_range = NULL,
  source = NULL,
  on_error = "abort",
  validate = "strict",
  ...
)
```

## Arguments

- dataset:

  Short dataset id (e.g. `"ofertas-publicas"`, `"crowdfunding"`).

- table:

  Snake-case table name within the dataset.

- offering:

  Optional character vector of offering identifiers (`numero_oferta`).
  `NULL` (default) returns every offering in the date range. Covers both
  registered public offerings (`ofertas-publicas`) and
  crowdfunding-platform offerings (`plataformas-de-crowdfunding`, CVM
  Resolution 88). Singular naming follows tidyverse conventions; the
  argument still accepts vectors of any length.

- date_range:

  Optional `Date` vector of length 2 specifying the offering date
  window: `c(from, to)`. `NULL` (default) returns every offering ever
  published. Vectors of length other than 2 abort with
  `cvmdata_error_input`.

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
pointing to ROADMAP.md. Full implementation arrives in v0.7.

## See also

Other fetchers:
[`agent_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/agent_fetch.md),
[`event_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/event_fetch.md),
[`fund_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/fund_fetch.md),
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)

## Examples

``` r
if (FALSE) {
# Available from v0.7 onwards (ofertas-publicas):
ipos <- offering_fetch("ofertas-publicas", "registradas",
                       date_range = as.Date(
                         c("2024-01-01", "2024-12-31")
                       ))

# Crowdfunding under CVM Resolution 88:
cf <- offering_fetch("crowdfunding", "ofertas")
}
```
