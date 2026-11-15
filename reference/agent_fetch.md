# Fetch a CVM open-data table for a registered-agent dataset

Single entry point for retrieving any table from any CVM agent-class
dataset covered by the package. Covers natural and legal persons
registered with CVM across eight CKAN groups: `administradores`,
`agentes-autonomos`, `agentes-fiduciarios`, `auditores`,
`consultores-de-valores-mobiliarios`, `coordenadores-de-ofertas`,
`participantes-intermediarios` and `investidores-nao-residentes`.

## Usage

``` r
agent_fetch(
  dataset,
  table,
  agent = NULL,
  as_of = NULL,
  source = NULL,
  on_error = "abort",
  validate = "strict",
  ...
)
```

## Arguments

- dataset:

  Short dataset id (e.g. `"administradores"`, `"agentes-autonomos"`).

- table:

  Snake-case table name within the dataset.

- agent:

  Optional character vector identifying registered agents to include.
  Accepts CPF, CNPJ, or free-text — the accepted token types vary by
  dataset:

  - `agentes-autonomos` accepts CPF only;

  - `coordenadores-de-ofertas` accepts CNPJ only;

  - `administradores`, `auditores`, `consultores-de-valores-mobiliarios`
    accept CPF, CNPJ and free-text against the registered name.
    Validation is performed against the target dataset at fetch time.
    `NULL` (default) returns every registered agent. Singular naming
    follows tidyverse conventions; the argument still accepts vectors of
    any length.

- as_of:

  Optional `Date` scalar specifying a registry snapshot date. `NULL`
  (default) returns the most recent registry snapshot. For historical
  snapshots, pass a specific date; the function returns the registry as
  published at the closest available snapshot on or before that date.

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
[`event_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/event_fetch.md),
[`fund_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/fund_fetch.md),
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md),
[`offering_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/offering_fetch.md)

## Examples

``` r
if (FALSE) {
# Available from v0.7 onwards:
admins <- agent_fetch("administradores", "cadastro")

# Snapshot at a historical date:
aa <- agent_fetch("agentes-autonomos", "cadastro",
                  as_of = as.Date("2023-12-31"))
}
```
