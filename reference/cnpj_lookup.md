# Look up a company's CNPJ by name

Searches the CVM company registers for a name, or part of one, and
returns the matching registrations with their CNPJ. Use it to find the
`cnpj` that
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
takes. The function never picks a company for you: it lists every match,
and you choose.

## Usage

``` r
cnpj_lookup(name, source = NULL)
```

## Arguments

- name:

  A single string: the company name, or part of it.

- source:

  One of `"mirror"` or `"cvm"`, as in
  [`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md).
  `NULL` (default) resolves to the active backend via
  [`cvm_source_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_get.md).

## Value

A tibble with one row per registration: `cnpj_cia`, `denom_social`,
`denom_comerc`, `cd_cvm`, `sit`, `dt_reg`, `dt_cancel` and `table` (the
register the row comes from). Rows the CVM repeats per market
(`tp_merc`) appear once. Active registrations (no `dt_cancel`) come
first, then by `denom_social`. No match returns zero rows and a message.

## Details

The search reads the three registers of the `cad` dataset (`companhias`,
`estrangeiras` and `incentivadas`, see
[`cvm_tables()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_tables.md))
from `source` and looks for `name` in `denom_social` and `denom_comerc`.
Every word of `name` must appear, in any order, ignoring case and
accents: `"banco brasil"` finds `"BANCO DO BRASIL S.A."` and `"tiete"`
finds `"AES TIETÊ ENERGIA S.A"`. Words are matched as plain text, not as
regular expressions.

Cancelled registrations are included, after the active ones: a delisted
company has no ticker, which is when a CNPJ is most needed. The
registers hold today's names only; a company that changed its name is
found by the current one.

## See also

[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md),
whose `cnpj` argument takes the result; its `ticker` argument is the
shortcut for exchange-listed companies.

Other utilities:
[`cnpj_clean()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_clean.md),
[`cnpj_format()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_format.md),
[`cvm_tbl`](https://sidneybissoli.github.io/cvmdata/reference/cvm_tbl.md)

## Examples

``` r
# \donttest{
hits <- cnpj_lookup("magazine luiza")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp8htSTF/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp8htSTF/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp8htSTF/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
hits
#> # A tibble: 1 × 8
#>   cnpj_cia    denom_social denom_comerc cd_cvm sit   dt_reg     dt_cancel table 
#>   <chr>       <chr>        <chr>        <chr>  <chr> <date>     <date>    <chr> 
#> 1 47.960.950… MAGAZINE LU… MAGAZINE LU… 22470  ATIVO 2011-04-28 NA        compa…
cvm_fetch("dfp", "dre", cnpj = hits$cnpj_cia[1], basis = "con")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp8htSTF/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp8htSTF/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> Warning: `year = NULL`: no rows for the requested issuer in 2026; returning 2025
#> instead.
#> ℹ The CVM portal publishes the current civil year as soon as the first
#>   non-civil-calendar filing arrives (e.g. agribusiness).
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp8htSTF/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> ℹ source: "mirror" | release: "mirror-companhias-dfp-snapshot-2026-11-15" |
#>   fetched_at: 2026-11-18 13:52:13.726864
#> ℹ group: "companhias" | dataset: "dfp" | table: "dre"
#> # A tibble: 64 × 15
#>    cnpj_cia       dt_refer   versao denom_cia cd_cvm grupo_dfp moeda ordem_exerc
#>    <chr>          <date>     <chr>  <chr>     <chr>  <chr>     <chr> <chr>      
#>  1 47.960.950/00… 2025-12-31 1      MAGAZINE… 022470 DF Conso… REAL  PENÚLTIMO  
#>  2 47.960.950/00… 2025-12-31 1      MAGAZINE… 022470 DF Conso… REAL  ÚLTIMO     
#>  3 47.960.950/00… 2025-12-31 1      MAGAZINE… 022470 DF Conso… REAL  PENÚLTIMO  
#>  4 47.960.950/00… 2025-12-31 1      MAGAZINE… 022470 DF Conso… REAL  ÚLTIMO     
#>  5 47.960.950/00… 2025-12-31 1      MAGAZINE… 022470 DF Conso… REAL  PENÚLTIMO  
#>  6 47.960.950/00… 2025-12-31 1      MAGAZINE… 022470 DF Conso… REAL  ÚLTIMO     
#>  7 47.960.950/00… 2025-12-31 1      MAGAZINE… 022470 DF Conso… REAL  PENÚLTIMO  
#>  8 47.960.950/00… 2025-12-31 1      MAGAZINE… 022470 DF Conso… REAL  ÚLTIMO     
#>  9 47.960.950/00… 2025-12-31 1      MAGAZINE… 022470 DF Conso… REAL  PENÚLTIMO  
#> 10 47.960.950/00… 2025-12-31 1      MAGAZINE… 022470 DF Conso… REAL  ÚLTIMO     
#> # ℹ 54 more rows
#> # ℹ 7 more variables: dt_ini_exerc <date>, dt_fim_exerc <date>, cd_conta <chr>,
#> #   ds_conta <chr>, vl_conta <dbl>, st_conta_fixa <chr>, basis <chr>
# }
```
