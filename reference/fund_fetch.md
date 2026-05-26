# Fetch a CVM open-data table for a fund dataset

Single entry point for retrieving any table from any CVM fund-class
dataset covered by the package. Covers investment funds across three
CKAN groups: `fundos-de-investimento` (ICVM 555 funds),
`fundos-de-investimento-imobiliarios` (FII) and `fundos-estruturados`
(FIP, FIDC, FAPI, etc.).

## Usage

``` r
fund_fetch(
  dataset,
  table,
  fund = NULL,
  date = NULL,
  source = NULL,
  on_error = "abort",
  validate = "strict",
  ...
)
```

## Arguments

- dataset:

  Short dataset id (e.g. `"fi-cad"`, `"informe-diario"`, `"cda"`).

- table:

  Snake-case table name within the dataset.

- fund:

  Optional character vector of fund CNPJs to include. `NULL` (default)
  returns every fund. Free-text matching against fund denomination is
  **not** supported in the current API because CVM Resolution 175 (2023)
  restructured fund nomenclature into Classe / Subclasse / Razão Social
  columns that change between issues; CNPJ remains the stable
  identifier. Free-text matching may be added in v0.5+ if a stable
  column emerges. Singular naming follows tidyverse conventions; the
  argument still accepts vectors of any length.

- date:

  Optional `Date` vector of reference dates. `NULL` (default) fetches
  the latest available month or quarter. Reference dates are
  point-in-time (end-of-month for monthly reports, last business day of
  quarter for quarterly). Singular naming; the argument accepts vectors
  of any length. Pass
  [`seq.Date()`](https://rdrr.io/r/base/seq.Date.html) for ranges or
  specific historical points.

- source:

  One of `"mirror"` (parquet via DuckDB) or `"cvm"` (CVM Open Data
  Portal). `NULL` (default) resolves to the active backend via
  [`cvm_source_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_get.md).

- on_error:

  One of `"abort"` (default), `"warn"` or `"silent"`. Controls behaviour
  on HTTP failures for batches of dated tables, analogously to
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
pointing to ROADMAP.md. Full implementation arrives in v0.4
(`fundos-de-investimento`), v0.5 (`fundos-de-investimento-imobiliarios`)
and v0.6 (`fundos-estruturados`).

## See also

Other fetchers:
[`agent_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/agent_fetch.md),
[`event_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/event_fetch.md),
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md),
[`offering_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/offering_fetch.md)

## Examples

``` r
if (FALSE) {
# Available from v0.4 onwards (fundos-de-investimento):
funds <- fund_fetch("fi-cad", "cad",
                    fund = "12.345.678/0001-90")

# Available from v0.5 onwards (fundos-de-investimento-imobiliarios):
fii <- fund_fetch("fii", "informe-mensal",
                  date = as.Date("2024-03-31"))
}
```
