# Known defects of the CVM publication

This article is a referential inventory of known publication quirks of
the CVM open-data feeds — heterogeneous identifier formats,
declared-but-implicit unit scales, columns CVM ships under one name but
indexes under another, tables published without a dictionary, and so on.
`cvmdata` adopts a deliberate stance:

> **If it comes from CVM, it stays as in CVM**, with only typographic
> normalization to snake_case lowercase. The package never invents
> content that CVM did not publish. Transformations exist only when
> CVM’s own metadata declares them (e.g. the `ESCALA_MOEDA` multiplier).

The result is a tibble that round-trips cleanly to the published source
while still being analysis-ready. The table below catalogs the thirteen
defects we have seen so far. The five structurally representative cases
get a mini-example below; the others are single-paragraph references.

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

## Inventory

| \# | Defect | Upstream behaviour | `cvmdata` treatment |
|----|----|----|----|
| 1 | Embedded control characters in free-text FRE fields (e.g. BEL ) | `Experiencia_Profissional` and similar carry raw control bytes | Preserved verbatim — “stays as in CVM”. A `cvm_strip_control_chars()` helper is on the v0.2 list. |
| 2 | CEP loses leading zeros in CAD | META declares `tipo_dados: numeric`; “01310-100” arrives as `1310100` | Preserved; a `cep_pad()` helper is on the v0.2 list. The column is forced to `character`. |
| 3 | Empty `Descrição` / `Domínio` in some META FRE entries | Reader sees partial metadata blocks | Tolerated. The dictionary snapshot keeps the row with `NA` for the empty fields. |
| 4 | `VL_CONTA` declared `decimal(29,10)` | Up to 29 digits of precision; R `double` resolves ~15–17 significant figures | Documented limitation. No silent truncation; values above the safe range have not been observed in the public companies feed. |
| 5 | CD_CVM zero-padding inconsistent between datasets | CAD ships `1023`; ITR/DFP ship `001023` | **See example below.** `companies` accepts either form; internal match strips/restores padding. |
| 6 | CNPJ comes with punctuation (`00.000.000/0001-91`) | Per-row formatting; not stripped upstream | Preserved in `cnpj_cia`. `companies` accepts both punctuated and clean forms. [`cnpj_clean()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_clean.md) / [`cnpj_format()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_format.md) round-trip. |
| 7 | `VL_CONTA × ESCALA_MOEDA` (UNIDADE / MIL / MILHÃO / BILHÃO) | Two columns; user must multiply | **See example below.** Applied via the canonical `multiply_by_scale` transformation; `escala_moeda` dropped. |
| 8 | Eight FRE tables ship without published META | Dictionary `.txt` never released for `empregado_PCD` and seven kin | **See example below.** YAML declares `meta_status: missing`; `validate = "warn"` or `"skip"` opt-in required. |
| 9 | `ORDEM_EXERC ∈ {ÚLTIMO, PENÚLTIMO}` per yearly CSV | Each year’s CSV covers only the declared year and N − 1 | Returned as-is. To assemble three or more consecutive years, pass an explicit `years` vector spanning the range. |
| 10 | FRE 2024 META URL anomalies | Archive name is `meta_fre_cia_aberta.zip` (no `_txt.zip` suffix); `empregado_local_faixa_etaria` entry lives without the `meta_` prefix | Schema-level fixups: `cvm_dictionary_url` lists the archive plus entry; reader looks for both prefixed and bare entry names. |
| 11 | `VERSAO` per `(cnpj_cia, dt_refer)` enables re-filings | Multiple rows for the same filing key when re-filed | **See example below.** Applied via the canonical `keep_latest_version` transformation. |
| 12 | Dates as `YYYY-MM-DD` strings | Plain strings in the CSV | Converted to R `Date` for every column the dictionary declares `tipo_dados: "date"`. |
| 13 | FRE-detail and some ITR/DFP tables lack a `cd_cvm` column | Filter must run on CNPJ | **See example below.** CD_CVM tokens resolve to CNPJ via the dataset’s `submissao` of the same year. |

## Mini-examples for the structural cases

### \#5 — CD_CVM padding accepted in either form

CAD ships CD_CVM unpadded, ITR/DFP pad to six digits.
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)
normalizes both:

``` r

a <- issuer_fetch("dfp", "bpa", report_type = "ind",
               issuer = "1023",   year = 2024)
b <- issuer_fetch("dfp", "bpa", report_type = "ind",
               issuer = "001023", year = 2024)
identical(a[, !(names(a) %in% character(0))],
          b[, !(names(b) %in% character(0))])
#> [1] FALSE
unique(a$cd_cvm)
#> [1] "001023"
```

The returned `cd_cvm` column is whatever the dataset publishes —
six-digit padded for DFP, two- to five-digit unpadded for CAD.
Identifier columns are forced to `character` (CLAUDE.md §2.4) so neither
form is corrupted.

### \#7 — `VL_CONTA × ESCALA_MOEDA` applied as published

The published CSV has two columns: `VL_CONTA` (the raw figure) and
`ESCALA_MOEDA` (one of `UNIDADE`, `MIL`, `MILHÃO`, `BILHÃO`). The schema
declares the transformation, and the package returns absolute reais with
`escala_moeda` dropped:

``` r

yaml::read_yaml(system.file(
  "extdata", "schemas", "dfp", "bpa.yaml", package = "cvmdata"
))$transformations
#> Warning in file(file, "rt", encoding = fileEncoding): file("") only supports
#> open = "w+" and open = "w+b": using the former
#> NULL
```

``` r

bpa <- issuer_fetch("dfp", "bpa", report_type = "ind",
                 issuer = "1023", year = 2024)

# Total assets reported by BCO BRASIL in 2024 (reais):
bpa[bpa$cd_conta == "1" & bpa$ordem_exerc == "ÚLTIMO", "vl_conta"]
#> ℹ source: "cvm" | fetched_at: 2026-05-29 21:05:07.219816
#> ℹ group: "companhias" | dataset: "dfp" | table: "bpa"
#> # A tibble: 1 × 1
#>        vl_conta
#>           <dbl>
#> 1 2395432208000
"escala_moeda" %in% names(bpa)
#> [1] FALSE
```

### \#8 — META missing in 8 FRE tables, opt-in via `validate`

The eight workforce-diversity tables in FRE (`empregado_PCD`,
`empregado_local_declaracao_genero`, etc.) ship without a CVM
dictionary. The default `validate = "strict"` refuses to read them:

``` r

issuer_fetch("fre", "empregado_PCD",
          issuer = "1023", year = 2024)
#> ℹ Resolving CD_CVM 1023 via "fre"/submissao for 2024 (table "empregado_PCD"
#>   does not carry `cd_cvm`).
#> ℹ source: "cvm" | fetched_at: 2026-05-29 21:05:08.469026
#> ℹ group: "companhias" | dataset: "fre" | table: "empregado_PCD"
#> # A tibble: 0 × 10
#> # ℹ 10 variables: cnpj_companhia <chr>, data_referencia <date>, versao <chr>,
#> #   id_documento <chr>, nome_companhia <chr>, codigo_posicao <chr>,
#> #   posicao <chr>, quantidade_pcd <dbl>, quantidade_nao_pcd <dbl>,
#> #   quantidade_sem_resposta <dbl>
```

`validate = "warn"` returns the data and emits
`cvmdata_warn_meta_unavailable`; `"skip"` silences the warning.
[`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md)
for these tables returns `NA` in every metadata column except `campo` /
`campo_original` — the package never invents content CVM did not
publish.

See the **fre** article for the worked example.

### \#11 — `keep_latest_version` collapses re-filings

A filing can be re-submitted; CVM keeps every version in the CSV. For
each table where re-filings happen, the schema declares a
`keep_latest_version` transformation which the package applies before
returning:

``` r

yaml::read_yaml(system.file(
  "extdata", "schemas", "fre", "auditor.yaml", package = "cvmdata"
))$transformations
#> Warning in file(file, "rt", encoding = fileEncoding): file("") only supports
#> open = "w+" and open = "w+b": using the former
#> NULL
```

Result: at most one row per filing key in the returned tibble.

``` r

auditor <- issuer_fetch("fre", "auditor",
                     issuer = "1023", year = 2024)
#> ℹ Resolving CD_CVM 1023 via "fre"/submissao for 2024 (table "auditor" does not
#>   carry `cd_cvm`).
# One row per (cnpj_companhia, data_referencia):
nrow(unique(auditor[, c("cnpj_companhia", "data_referencia")])) ==
  nrow(auditor)
#> [1] FALSE
```

### \#13 — CD_CVM filter against tables without `cd_cvm`

`fre/auditor`, `dfp/composicao_capital`, `dfp/parecer`, and several
FRE-detail tables index by `cnpj_companhia` (or `cnpj_cia`) without
carrying `cd_cvm`. The package reads the dataset’s `submissao` for the
same year, looks up CNPJ for each CD_CVM token in `companies`, and
applies the filter on CNPJ:

``` r

auditor <- issuer_fetch("fre", "auditor",
                     issuer = "1023", year = 2024)
#> ℹ Resolving CD_CVM 1023 via "fre"/submissao for 2024 (table "auditor" does not
#>   carry `cd_cvm`).
"cd_cvm" %in% names(auditor)
#> [1] FALSE
unique(auditor$cnpj_companhia)
#> [1] "00.000.000/0001-91"
unique(auditor$nome_companhia)
#> [1] "BCO BRASIL S.A."
```

The interface is identical regardless of which table holds CD_CVM
natively. If a CD_CVM token is not present in the year’s `submissao`,
the call aborts with `cvmdata_error_input` rather than silently
returning an empty tibble.

## Reading the other defects directly

For defects 1, 2, 3, 4, 6, 9, 10, and 12 the package’s behaviour is
either purely preservational (1, 2, 3, 4, 6) or structurally declared in
the schema (9, 10, 12). The inventory table above points at each YAML
and at the relevant CLAUDE.md section; the package’s source under
`R/transform-schema.R`, `R/util-csv-cvm.R` and `R/api-issuer-fetch.R` is
the canonical reference.

## Where to read next

- **issuer-fetch** — argument reference; `validate` and `on_error`
  semantics in full.
- **itr-dfp** — workflow with `multiply_by_scale` and
  `keep_latest_version` in action.
- **fre** — workflow with the eight `meta_status: missing` tables.
