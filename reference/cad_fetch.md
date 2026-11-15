# Fetch the CVM company registry (CAD)

Thin alias for `cvm_fetch(dataset = "cad", table = "companhias", ...)`,
kept for ergonomics of the Session 01 release. Returns the current
snapshot of the *Cadastro de Companhias Abertas* published by CVM at
<https://dados.cvm.gov.br/>.

## Usage

``` r
cad_fetch(
  companies = NULL,
  source = NULL,
  on_error = "abort",
  validate = "strict",
  ...
)
```

## Arguments

- companies:

  Optional character vector identifying companies to include. Accepts
  CNPJ (with or without punctuation), CD_CVM (with or without
  zero-padding), or free-text matched against `denom_cia`. Detection is
  automatic per element. `NULL` (default) returns every company. When
  the target table does not carry a `cd_cvm` column (e.g.
  `composicao_capital`, `parecer`), CD_CVM tokens are resolved to CNPJ
  via the dataset's `submissao` table for the same year — the
  user-facing interface is identical regardless of which table holds
  CD_CVM natively.

- source:

  One of `"mirror"` (parquet via DuckDB) or `"cvm"` (CVM Open Data
  Portal). `NULL` (default) resolves to the active backend via
  [`cvm_source_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_get.md)
  — `"mirror"` from v0.1.0 onward unless the user has flipped it via
  `cvm_source_set("cvm")`.

- on_error:

  One of `"abort"` (default), `"warn"` or `"silent"`. Controls behaviour
  on HTTP failures for batches of yearly tables (`years = c(...)` with
  more than one element). With `"warn"`, the failed years are skipped
  and a `cvmdata_warn_partial_failure` warning lists them; with
  `"silent"`, the failed years are skipped silently; with `"abort"`, the
  first failure aborts the call. Total batch failure (every year fails)
  always aborts regardless of the setting — there is no partial result
  to return. Parse/validation failures are governed by `validate`, not
  `on_error`. Single-year calls, non-yearly tables, and the implicit
  fallback when `years = NULL` always abort on HTTP failure.

- validate:

  One of `"strict"` (default), `"warn"` or `"skip"`. Controls schema
  validation strictness at parse time.

- ...:

  Reserved for forward compatibility.

## Value

A tibble of class `cvm_tbl` carrying provenance attributes.

## See also

[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
for the generic API.

Other fetchers:
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)

## Examples

``` r
if (FALSE) { # interactive()
companies <- cad_fetch()
}
```
