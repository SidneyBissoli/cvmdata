# Quarterly and annual statements (ITR & DFP)

CVM publishes two financial-statement datasets with the **same eleven
tables** and the same schema, differing only in cadence:

- **ITR** — *Informações Trimestrais*. One CSV per table per year, with
  one row per `(company, quarter, account)`.
- **DFP** — *Demonstrações Financeiras Padronizadas*. One CSV per table
  per year, with one row per `(company, fiscal year, account)`.

The package’s tooling is identical for both: pass `"itr"` or `"dfp"` as
`dataset`, the same `table` name, and the same arguments. Eight tables
out of eleven publish individual / consolidated variants selected
through `report_type`.

``` r

library(cvmdata)

# Pin the source to the live CVM portal for the article's live chunks.
# The default mirror backend (`cvm_source_get()`) depends on GitHub
# Releases named `mirror-<group>-<dataset>-latest`; until those are
# renamed in place from the pre-Sessao-08 format, the fallback to the
# CVM HTTP portal is the path that always works.
cvm_source_set("cvm")
#> ✔ Source backend set to "cvm".
```

## Reference: tables available

| Table | What it carries | `report_type` required? | Notes |
|----|----|----|----|
| `bpa` | Asset side of the balance sheet | Yes (`ind` / `con`) | `VL_CONTA × ESCALA_MOEDA` applied (`multiply_by_scale`). |
| `bpp` | Liabilities + equity side | Yes | Idem. |
| `dre` | Income statement | Yes | Idem. |
| `dra` | Statement of comprehensive income | Yes | Idem. |
| `dfc_md` | Cash-flow statement, direct method | Yes | Idem. |
| `dfc_mi` | Cash-flow statement, indirect method | Yes | Idem. |
| `dmpl` | Statement of changes in equity | Yes | Idem; wider table (multiple equity columns). |
| `dva` | Statement of value added (Brazilian-specific) | Yes | Idem. |
| `composicao_capital` | Capital composition (share counts by class) | No (`NULL`) | No `cd_cvm` column — CD_CVM filters resolve via `submissao`. |
| `parecer` | Auditor opinion (free-text) | No | One row per filing, with full opinion text in `texto`. |
| `submissao` | Filing header — `id_doc`, `dt_receb`, `link_doc`, etc. | No | The dataset’s index. Every filing has exactly one row here. |

Use `cvm_dictionary("dfp", "<table>")` to see the column-level metadata
(descriptions, domain, data type, size) for any of the eleven tables;
`cvm_codelist("dfp", "<table>", "<column>")` returns enumerated
categorical values.

## Workflow 1 — Side-by-side total assets across two issuers

Goal: compare 2024 total assets for **BCO BRASIL S.A.** (CD_CVM `1023`)
and **MAGAZINE LUIZA S.A.** (CD_CVM `22470`) using the individual
balance sheet (`dfp/bpa`).

``` r

bpa <- issuer_fetch(
  "dfp", "bpa",
  report_type = "ind",
  issuer = c("1023", "22470"),
  year = 2024
)
bpa
#> ℹ source: "cvm" | fetched_at: 2026-05-29 00:46:07.025076
#> ℹ group: "companhias" | dataset: "dfp" | table: "bpa"
#> # A tibble: 226 × 13
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
#> # ℹ 216 more rows
#> # ℹ 5 more variables: dt_fim_exerc <date>, cd_conta <chr>, ds_conta <chr>,
#> #   vl_conta <dbl>, st_conta_fixa <chr>
```

The tibble carries provenance attributes and the package has already:

- multiplied `VL_CONTA` by `ESCALA_MOEDA` and dropped the scale column
  (values are in absolute reais);
- converted `DT_REFER`, `DT_FIM_EXERC` to R `Date`;
- kept only the latest `VERSAO` per `(cnpj_cia, dt_refer)` — so
  re-filings do not produce duplicated rows.

Total assets is the top of the asset hierarchy (`cd_conta == "1"`):

``` r

ativo_total <- bpa[
  bpa$cd_conta == "1" & bpa$ordem_exerc == "ÚLTIMO",
  c("cnpj_cia", "denom_cia", "dt_fim_exerc", "vl_conta")
]
ativo_total
#> ℹ source: "cvm" | fetched_at: 2026-05-29 00:46:07.025076
#> ℹ group: "companhias" | dataset: "dfp" | table: "bpa"
#> # A tibble: 2 × 4
#>   cnpj_cia           denom_cia           dt_fim_exerc      vl_conta
#>   <chr>              <chr>               <date>               <dbl>
#> 1 00.000.000/0001-91 BCO BRASIL S.A.     2024-12-31   2395432208000
#> 2 47.960.950/0001-21 MAGAZINE LUIZA S.A. 2024-12-31     32482619000
```

CVM publishes each fiscal year’s CSV with two reference columns —
`ÚLTIMO` (the declared year, here 2024) and `PENÚLTIMO` (the comparative
previous year). To pick up an older comparative, request the matching
upstream year explicitly:

``` r

bpa_history <- issuer_fetch(
  "dfp", "bpa",
  report_type = "ind",
  issuer = "1023",
  year = 2022:2024
)
ativo_history <- bpa_history[
  bpa_history$cd_conta == "1" & bpa_history$ordem_exerc == "ÚLTIMO",
  c("dt_fim_exerc", "vl_conta")
]
ativo_history[order(ativo_history$dt_fim_exerc), ]
#> ℹ source: "cvm" | fetched_at: 2026-05-29 00:46:08.410302
#> ℹ group: "companhias" | dataset: "dfp" | table: "bpa"
#> # A tibble: 3 × 2
#>   dt_fim_exerc      vl_conta
#>   <date>               <dbl>
#> 1 2022-12-31   2062674549000
#> 2 2023-12-31   2208053634000
#> 3 2024-12-31   2395432208000
```

## Workflow 2 — Capital composition through `submissao` lookup

`composicao_capital` does not carry `cd_cvm` — it indexes by `cnpj_cia`.
The package reads the dataset’s `submissao` table for the same year,
looks up CNPJ for each CD_CVM passed in `companies`, and applies the
filter on CNPJ. The user-facing interface is identical:

``` r

cap <- issuer_fetch(
  "dfp", "composicao_capital",
  issuer = c("1023", "22470"),
  year = 2024
)
#> ℹ Resolving CD_CVM 1023, 22470 via "dfp"/submissao for 2024 (table
#>   "composicao_capital" does not carry `cd_cvm`).
cap
#> ℹ source: "cvm" | fetched_at: 2026-05-29 00:46:08.568992
#> ℹ group: "companhias" | dataset: "dfp" | table: "composicao_capital"
#> # A tibble: 2 × 10
#>   cnpj_cia           dt_refer   versao denom_cia          qt_acao_ordin_cap_in…¹
#>   <chr>              <date>     <chr>  <chr>                               <dbl>
#> 1 00.000.000/0001-91 2024-12-31 1      BCO BRASIL S.A.                5730834040
#> 2 47.960.950/0001-21 2024-12-31 1      MAGAZINE LUIZA S.…              738995248
#> # ℹ abbreviated name: ¹​qt_acao_ordin_cap_integr
#> # ℹ 5 more variables: qt_acao_pref_cap_integr <dbl>,
#> #   qt_acao_total_cap_integr <dbl>, qt_acao_ordin_tesouro <dbl>,
#> #   qt_acao_pref_tesouro <dbl>, qt_acao_total_tesouro <dbl>
```

Note: no `report_type` argument — `composicao_capital` is a single
concept, not split into individual / consolidated.

Cross-check against the underlying submissao header:

``` r

sub <- issuer_fetch(
  "dfp", "submissao",
  issuer = c("1023", "22470"),
  year = 2024
)
sub[, c("cd_cvm", "denom_cia", "dt_refer", "id_doc")]
#> ℹ source: "cvm" | fetched_at: 2026-05-29 00:46:08.701167
#> ℹ group: "companhias" | dataset: "dfp" | table: "submissao"
#> # A tibble: 2 × 4
#>   cd_cvm denom_cia           dt_refer   id_doc
#>   <chr>  <chr>               <date>     <chr> 
#> 1 001023 BCO BRASIL S.A.     2024-12-31 144874
#> 2 022470 MAGAZINE LUIZA S.A. 2024-12-31 145377
```

ITR works the same way — replace `"dfp"` with `"itr"`. The trimester
breakdown then shows up in `dt_fim_exerc` and in the `ds_conta` /
`grupo_dfp` columns; the underlying mechanics (`multiply_by_scale`,
`keep_latest_version`, date conversion via the dictionary) are shared.

## Where to read next

- **issuer-fetch** — argument reference and the full `companies` /
  `years` / `report_type` / `validate` / `on_error` semantics.
- **fre** — reference form. Same package, different table semantics.
- **cvm-defects** — known publication quirks behind the transformations
  applied here.
