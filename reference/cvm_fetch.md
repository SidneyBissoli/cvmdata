# Fetch a CVM open-data table

Single public entry point for any table of any dataset covered by the
package. Selects the right file, downloads (or serves from the cache or
the parquet mirror), parses, applies the schema-declared
transformations, filters by issuer and period, and returns a tibble
carrying provenance attributes.

## Usage

``` r
cvm_fetch(
  dataset,
  table,
  cnpj = NULL,
  ticker = NULL,
  year = NULL,
  from = NULL,
  to = NULL,
  basis = NULL,
  source = NULL,
  on_error = "abort",
  validate = "strict",
  ...
)
```

## Arguments

- dataset:

  Short dataset id (e.g. `"cad"`, `"dfp"`).

- table:

  Snake-case table name (e.g. `"companhias"`, `"bpa"`). For tables
  published in individual and consolidated variants, `table` is the
  concept name and `basis` selects the variant(s).

- cnpj:

  Optional character vector of issuer CNPJs, with or without punctuation
  (`"00.000.000/0001-91"` or `"00000000000191"`). Only CNPJs are
  accepted: a CVM code or a company name aborts with
  `cvmdata_error_input`. `NULL` (default) keeps every issuer. A CNPJ
  absent from the table yields zero rows for it, silently.

- ticker:

  Optional character vector of B3 trading codes (`"PETR4"`, `"BBAS3"`).
  Each ticker is resolved to its issuer CNPJ through
  `fca/valor_mobiliario` (read from the same `source`) and then filtered
  like `cnpj`; the two arguments combine. A ticker absent from the
  lookup aborts with `cvmdata_error_input`.

- year:

  Integer vector of years to fetch, as the CVM publishes them (one file
  per year). `NULL` (default) fetches the latest available year. Must be
  `NULL` for datasets with `temporal_partitioning: none` (e.g. CAD), and
  cannot be combined with `from`/`to`.

- from, to:

  Optional period bounds, both required together, as complete dates
  (`"YYYY-MM-DD"` strings or `Date` scalars). Rows are kept when the
  document's reference date (`dt_refer` or `data_referencia`) falls
  inside `[from, to]`; the yearly files read are the years spanned by
  the interval. Incomplete dates (`"2024"`, `"2024-06"`) are rejected.
  Cannot be combined with `year`, and do not apply to snapshot tables
  such as CAD.

- basis:

  Individual (`"ind"`), consolidated (`"con"`) or both
  (`c("ind", "con")`) financial statements. Required for tables that
  publish the two variants (`bpa`, `bpp`, `dre`, `dra`, `dfc_md`,
  `dfc_mi`, `dmpl`, `dva`): there is no default, because many issuers
  file only individual statements. Those tables always carry a `basis`
  column in the result, even when a single value was requested. Must be
  `NULL` for every other table; passing it aborts.

- source:

  One of `"mirror"` (parquet via DuckDB) or `"cvm"` (CVM Open Data
  Portal). `NULL` (default) resolves to the active backend via
  [`cvm_source_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_get.md).

- on_error:

  One of `"abort"` (default), `"warn"` or `"silent"`. Controls behaviour
  on HTTP failures when several yearly files are read (`year` with more
  than one element, or a `from`/`to` window spanning several years).
  With `"warn"`, the failed years are skipped and a
  `cvmdata_warn_partial_failure` warning lists them; with `"silent"`,
  they are skipped silently; with `"abort"`, the first failure aborts
  the call. Total failure always aborts.

- validate:

  One of `"strict"` (default), `"warn"` or `"skip"`. Controls schema
  validation strictness at parse time.

- ...:

  Reserved for forward compatibility. Currently no extra arguments are
  accepted; passing any aborts with `cvmdata_error_input`.

## Value

A tibble of class `cvm_tbl` carrying the provenance attributes `source`,
`fetched_at`, `group`, `dataset`, `table` and `package_version`.

## Details

Column names, categorical values and free-text fields are preserved in
Portuguese exactly as published by CVM (snake_case minúsculo).

## Filing versions

When a table carries several filings for the same issuer and reference
date, only the last one delivered is kept, ranked by receipt date, then
CVM document id, then `versao`. The version number alone is not a filing
key: the CVM index can list two filings under the same version, or a
later filing under a lower one.

Tables of datasets with a `submissao` index are checked against it
before returning. In DFP and ITR tables, rows the CVM file holds twice
are dropped (`cvmdata_warn_duplicate_filing`); copies that differ in
`vl_conta` are kept (`cvmdata_warn_conflicting_filing`). A table holding
an earlier filing than the last delivery keeps the CVM numbers and warns
(`cvmdata_warn_stale_filing`). Set
`options(cvmdata.check_filings = FALSE)` to skip these checks.

## Examples

``` r
if (FALSE) { # interactive()
# CAD: single snapshot, no year, no basis
issuers <- cvm_fetch("cad", "companhias")

# DFP balance sheet (assets), individual statements, latest year,
# one issuer by CNPJ
bb <- cvm_fetch("dfp", "bpa", cnpj = "00.000.000/0001-91", basis = "ind")

# Both bases, 2022 to 2024, issuer by B3 ticker
petr <- cvm_fetch(
  "dfp", "dre",
  ticker = "PETR4",
  year = 2022:2024,
  basis = c("ind", "con")
)

# ITR by reference date: the quarters of the first half of 2024
h1 <- cvm_fetch(
  "itr", "bpa",
  from = "2024-01-01", to = "2024-06-30",
  basis = "con"
)
}
```
