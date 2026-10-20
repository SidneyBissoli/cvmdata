# Getting started with cvmdata

This article is a guided tour of every public feature in `cvmdata`. It
is meant to be read top-to-bottom in one sitting: by the end you will
know what the package covers, the single fetcher it exports, how to
filter and discover data, what the two backends do, how the cache
behaves, and which error classes are worth catching in your own code.
Live chunks use the default mirror backend (GitHub Releases + DuckDB);
the CVM Open Data Portal backend is documented alongside the mirror in
its own article.

``` r

library(cvmdata)
```

## The 30-second pitch

`cvmdata` consolidates the messy parts of working with CVM open data
(yearly ZIPs of CSVs, mixed `ISO-8859-1` encoding, per-table schemas, no
unified dictionary, `VL_CONTA × ESCALA_MOEDA` arithmetic, one issuer id
per table convention) behind one function:

``` r

cvm_fetch(dataset, table,
          cnpj = NULL, ticker = NULL,
          year = NULL, from = NULL, to = NULL,
          basis = NULL, ...)
```

Column names, table names and categorical values arrive in Portuguese
exactly as CVM publishes them. Function names, arguments and metadata
attributes are in English (rOpenSci / tidyverse conventions).

## The discovery layer — explore before you fetch

Discovery functions read from snapshots bundled with the package, so
they do not touch the network and work offline.

### Groups

CVM publishes data in **18 thematic groups** on its CKAN portal.
`cvmdata` serves every group through the same
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md);
each dataset’s schema declares which columns identify the entity (issuer
/ fund / agent / offering / event):

``` r

cvm_groups()
#> # A tibble: 18 × 3
#>    group                               n_datasets contract
#>    <chr>                                    <int> <chr>   
#>  1 administradores                              2 agent   
#>  2 agentes-autonomos                            1 agent   
#>  3 agentes-fiduciarios                          1 agent   
#>  4 atividade-sancionadora                       1 event   
#>  5 atos-declaratorios                           1 event   
#>  6 auditores                                    1 agent   
#>  7 companhias                                  12 issuer  
#>  8 consultores-de-valores-mobiliarios           1 agent   
#>  9 coordenadores-de-ofertas                     1 agent   
#> 10 emissores-de-cepac                           1 issuer  
#> 11 fundos-de-investimento                      22 fund    
#> 12 fundos-de-investimento-imobiliarios          4 fund    
#> 13 fundos-estruturados                         10 fund    
#> 14 investidores-nao-residentes                  1 agent   
#> 15 ofertas-publicas                             2 offering
#> 16 participantes-intermediarios                 1 agent   
#> 17 plataformas-de-crowdfunding                  1 offering
#> 18 securitizadoras                              4 issuer
```

The `contract` column is a planning map naming the kind of entity each
group is keyed on; the `groups-overview` article expands on the
rationale and on which groups are implemented today.

### Datasets, tables, and years

``` r

cvm_datasets()
#> [1] "cad"  "cgvn" "dfp"  "fca"  "fre"  "ipe"  "itr"  "vlmo"
cvm_datasets(group = "companhias")
#> [1] "cad"  "cgvn" "dfp"  "fca"  "fre"  "ipe"  "itr"  "vlmo"
cvm_tables("dfp")
#>  [1] "bpa"                "bpp"                "composicao_capital"
#>  [4] "dfc_md"             "dfc_mi"             "dmpl"              
#>  [7] "dra"                "dre"                "dva"               
#> [10] "parecer"            "submissao"
```

For yearly-partitioned datasets,
[`cvm_dataset_years()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dataset_years.md)
discovers the years currently published upstream (a tiny HTTP probe of
the CVM directory listing, cached for the session):

``` r

cvm_dataset_years("dfp")
#> [1] 2010 2011 2012 ... 2024 2025
```

### Dictionary and codelists

`cvm_dictionary(dataset, table)` returns the field descriptions, types
and domains as published in the CVM META files:

``` r

head(cvm_dictionary("dfp", "bpa"), 5)
#> # A tibble: 5 × 8
#>   campo     campo_original descricao   dominio tipo_dados tamanho precisao scale
#>   <chr>     <chr>          <chr>       <chr>   <chr>        <int>    <int> <int>
#> 1 cd_conta  CD_CONTA       Código da … Numéri… varchar         18       NA    NA
#> 2 cd_cvm    CD_CVM         Código CVM  Numéri… char             6       NA    NA
#> 3 cnpj_cia  CNPJ_CIA       CNPJ da co… Alfanu… varchar         20       NA    NA
#> 4 denom_cia DENOM_CIA      Nome empre… Alfanu… varchar        100       NA    NA
#> 5 ds_conta  DS_CONTA       Descrição … Alfanu… varchar        100       NA    NA
```

`cvm_codelist(dataset, table, column)` returns the enumerated values for
categorical columns. Inclusion is automatic: either the META declares an
enumerated domain (e.g. `S/N`), or the column is a `varchar` with
`tamanho < 200` and at most 50 distinct values observed in the latest
year.

``` r

cvm_codelist("cgvn", "praticas", "pratica_adotada")
#> # A tibble: 4 × 1
#>   value
#>   <chr>
#> 1 Não
#> 2 Não se Aplica
#> 3 Parcialmente
#> 4 Sim
```

## One fetcher

[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
is the only fetcher: one function for any dataset and any table, with
the entity filter (`cnpj`, `ticker`), the period (`year` or `from`/`to`)
and the statement `basis` interpreted through each dataset’s schema.
Groups not yet implemented (funds, registered agents, public offerings,
regulatory events) will arrive as new schemas behind the same function,
not as new fetchers.

[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md),
the entry point of v0.1 and v0.2, is deprecated. It still works and
emits a lifecycle warning pointing to
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md);
it will be removed in a later release.

## Fetching data — a tour of the 8 issuer datasets

The package implements eight datasets in the `companhias` group: `cad`,
`dfp`, `itr`, `fre` (v0.1) and `cgvn`, `vlmo`, `fca`, `ipe` (v0.2). The
examples below are marked `eval = FALSE` to keep the article fast; copy
any of them into your R session as-is.

### `cad` — company registry

A single, time-less snapshot. No `year`, no `basis`. It is also where a
CVM code or a company name resolves to a CNPJ: `cd_cvm`, `denom_social`
and `cnpj_cia` sit side by side.

``` r

companies <- cvm_fetch("cad", "companhias")
companies
```

### `dfp` and `itr` — financial statements

Annual (DFP) and quarterly (ITR) financial statements share an identical
table set (11 tables: balance sheet, income statement, cash flow, etc.).
Accounting tables that publish individual and consolidated variants —
`bpa`, `bpp`, `dre`, `dra`, `dfc_md`, `dfc_mi`, `dmpl`, `dva` — require
`basis`: `"ind"`, `"con"` or `c("ind", "con")` to stack both. Those
tables always carry a `basis` column in the result.

``` r

# BCO BRASIL individual balance sheet, 2024
bb <- cvm_fetch(
  "dfp", "bpa",
  cnpj = "00.000.000/0001-91",
  year = 2024,
  basis = "ind"
)

# Two companies across three years, both bases stacked
two <- cvm_fetch(
  "dfp", "dre",
  cnpj = c("00.000.000/0001-91", "47.960.950/0001-21"),
  year = 2022:2024,
  basis = c("ind", "con")
)

# ITR balance sheets referenced in the first half of 2024
h1 <- cvm_fetch(
  "itr", "bpa",
  ticker = "PETR4",
  from = "2024-01-01", to = "2024-06-30",
  basis = "con"
)
```

`vl_conta` is already in absolute reais: `cvmdata` multiplies by
`ESCALA_MOEDA` (`UNIDADE`=1, `MIL`=1e3, etc.) and drops the scale
column. Dates arrive as `Date`, driven by the bundled dictionary.

### `fre` — reference form (36 tables)

FRE is the annual Reference Form, with header (`submissao`) and 35
detail tables covering board composition, compensation, auditor,
shareholder distribution and ESG/governance disclosures (gender, race,
age-bracket, persons with disabilities). Eight of those detail tables
ship without a CVM-published META (`meta_status: missing`); their
parsing uses the `expected_field_names` declared in the schema YAML as a
defense-in-depth check.

``` r

auditor <- cvm_fetch(
  "fre", "auditor",
  cnpj = "00.000.000/0001-91",
  year = 2024
)

# Genuine empty table is fine — FRE/empregado_PCD has meta_status: missing
pcd <- cvm_fetch(
  "fre", "empregado_PCD",
  year = 2024,
  validate = "warn"  # or "strict" / "skip"
)
```

FRE detail tables use a different naming convention: `cnpj_companhia`,
`data_referencia`, `nome_companhia`, `versao`, `id_documento`. There is
**no `cd_cvm`** column in the detail tables; `cnpj` filters on
`cnpj_companhia` there and on `cnpj_cia` elsewhere, so the call is the
same for every table.

### `cgvn` — Brazilian Corporate Governance Code informe

Added in v0.1.0.9000 toward v0.2. Two tables: `submissao` (one row per
delivery of the ICBGC informe, re-filings included) and `praticas`
(“comply or explain” detail with 54 recommended practices per filing,
last delivery only).

``` r

praticas <- cvm_fetch(
  "cgvn", "praticas",
  cnpj = "00.000.000/0001-91",
  year = 2024
)
# Columns include: cnpj_companhia, data_referencia, versao,
# id_item ("N.N.N"), capitulo, principio, pratica_recomendada,
# pratica_adotada ∈ {Sim, Não, Parcialmente, Não se Aplica},
# explicacao.
```

CGVN follows a third naming convention (`codigo_cvm` instead of `cd_cvm`
in the submissao table). The CNPJ column is what `cnpj` matches, so the
three conventions are invisible at the call.

### `vlmo` — securities traded and held by insiders

Added in v0.1.0.9000 toward v0.2. Two tables: `submissao` (one row per
delivery, re-filings included) and `consolidado` (one row per security
movement). The package table is named `consolidado` — the CVM file token
is `con`, a reserved device name on Windows.

``` r

movements <- cvm_fetch(
  "vlmo", "consolidado",
  cnpj = "00.000.000/0001-91",
  year = 2024
)
# Columns include: cnpj_companhia, data_referencia, versao,
# tipo_empresa, empresa, tipo_cargo, tipo_movimentacao,
# tipo_operacao, tipo_ativo, data_movimentacao, quantidade,
# preco_unitario, volume.
```

Two things set `vlmo/consolidado` apart. First, it is **event-per-row**:
unlike every other detail table, it declares no `keep_latest_version`,
so each `versao` is kept verbatim (collapsing by version would merge
distinct movements). Second, insider identity is **opaque by design of
the CVM** — there is no CPF in the detail, only the category
`tipo_cargo` and, for corporate insiders, a name in `empresa`. The
`cnpj` argument filters the issuing company; to slice by insider
category, filter `tipo_cargo` on the returned tibble with `dplyr`.

### `fca` — registration form (10 tables)

Added in v0.1.0.9000 toward v0.2 — the largest v0.2 surface. The `fca`
(Formulário Cadastral) is the company’s standing registration record:
ten tables headed by `submissao` (the classic 9-field header, identical
to ITR/DFP/FRE) plus nine FRE-detail tables — `auditor`,
`canal_divulgacao`, `departamento_acionistas`, `dri`, `endereco`,
`escriturador`, `geral`, `pais_estrangeiro_negociacao` and
`valor_mobiliario`.

``` r

# Current registration state, latest year
geral <- cvm_fetch("fca", "geral", cnpj = "00.000.000/0001-91")

# Securities and their B3 trading tickers
vm <- cvm_fetch("fca", "valor_mobiliario", year = 2024)

# A ticker selects the issuer (see "Selecting issuers" below)
petr <- cvm_fetch("fca", "geral", ticker = "PETR4")
```

`submissao` is classic (`cnpj_cia` + `cd_cvm`) while the nine detail
tables are FRE-detail (`cnpj_companhia`, no `cd_cvm`); `cnpj` matches
whichever CNPJ column the table carries.

Two FCA specifics worth knowing. First, `fca/valor_mobiliario` is the
source of the **B3 ticker lookup** — its `codigo_negociacao` column is
what lets you pass `ticker = "PETR4"` (or `"BBDC11"`) to *any* dataset.
Second, `fca/departamento_acionistas` is published with a valid 23-field
header but **no data rows from 2024 onward** (it carried data through
2023, then zeroed after a regulatory change); the call returns an empty
tibble without error — use `fca/endereco` or `fca/dri` for
shareholder-department contact details instead.

#### `fca` vs `cad`

Both describe the company itself, but they are different artifacts and
should not be confused. `cad` is a single, time-less, unversioned
snapshot of the *current* registry state. `fca` is a **versioned,
yearly-partitioned history** of the registration form: one filing per
company per year. Its detail tables keep the filing delivered last; its
`submissao` lists every delivery, re-filings included. There is no
automatic dedup or join between the two. To relate them, join manually
on the issuer CNPJ — `cad$cnpj_cia` against `fca`’s `cnpj_cia`
(submissao) or `cnpj_companhia` (detail) — after normalising both with
[`cnpj_clean()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_clean.md).

### `ipe` — manifest of periodic and eventual documents

Added in v0.1.0.9000 toward v0.2. `ipe` (Informações Periódicas e
Eventuais) is a **single-table manifest**: one row per document a
company filed with the CVM — roughly 50,000 documents a year, across
every category (Fato Relevante, Comunicado ao Mercado, Assembleia, …).

``` r

# Everything Banco do Brasil filed in 2024
docs <- cvm_fetch("ipe", "ipe", ticker = "BBAS3", year = 2024)

# Slice the manifest by document class — a plain dplyr step
library(dplyr)
fatos <- docs |> filter(categoria == "Fato Relevante")
```

The manifest is **event-per-row**: it declares no `keep_latest_version`,
so re-submissions and every `versao` of a document survive verbatim
(filter on `categoria`/`versao` yourself if you want a subset). The
`link_download` column is the URL of the original document on the CVM
portal; cvmdata returns it as plain text and **does not download or OCR
the PDF** — that is out of scope.

`ipe` overlaps `vlmo` on one category: “Valores Mobiliários negociados e
detidos (art. 11 …)” is the same event `vlmo` structures. Use `vlmo` for
the **structured** insider movements and `ipe` to **discover and
locate** the filed documents (and their PDFs) in any category. The
`ipe-vlmo` article works the overlap through end to end.

## Selecting issuers

[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
identifies issuers by two keys, which combine in one call:

| Argument | Accepts |
|----|----|
| `cnpj` | CNPJ, with or without punctuation, vector of any length |
| `ticker` | B3 trading code (`PETR4`, `BBDC11`), resolved to the issuer’s CNPJ via `fca/valor_mobiliario` |

A CVM code or a company name passed as `cnpj` aborts with
`cvmdata_error_input` — there is no free-text search. To find a CNPJ you
know only by name or by CVM code, read the registry:
`cvm_fetch("cad", "companhias")` carries `cd_cvm`, `denom_social` and
`cnpj_cia` side by side. (The deprecated
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)
still accepts CD_CVM and free text through its `issuer` argument until
it is removed.)

An unknown ticker aborts with `cvmdata_error_input` (tickers cover only
exchange-listed securities — debentures and private placements have
none). A CNPJ absent from the table yields zero rows, silently.

``` r

cvm_fetch("dfp", "bpa",
          cnpj = c("00.000.000/0001-91", "47.960.950/0001-21"),
          ticker = "PETR4",
          year = 2024, basis = "ind")
```

## Period semantics

`year` accepts an integer vector or `NULL`. When `NULL`, the package
fetches the **latest year published upstream**. If the latest year has
no rows for the requested issuer (a common case in agribusiness, where
the civil-year ZIP is created before any civil-calendar filing arrives),
the fetcher walks down up to three years and emits a
`cvmdata_warn_year_fallback` warning naming the year actually returned.

An explicit vector fetches each year and binds the result. For
historical reach, just pass a longer vector:

``` r

hist <- cvm_fetch("dfp", "dre",
                  cnpj = "00.000.000/0001-91",
                  year = 2012:2024,
                  basis = "ind")
```

CVM publishes only `ORDEM_EXERC ∈ {ÚLTIMO, PENÚLTIMO}` per yearly CSV
(i.e. the declared year and its N-1).
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
returns the literal CSV content for each year you ask for; users build
longer histories by passing a longer vector and deduplicating
downstream.

For slices smaller than a year, pass `from` and `to` together as
complete dates (`"YYYY-MM-DD"`). Rows are kept by the document’s
reference date (`dt_refer` / `data_referencia`), and the yearly files
read are the years the window spans. `year` and `from`/`to` are mutually
exclusive, and neither applies to the `cad` snapshot.

## Provenance — what every tibble carries

Every tibble returned by
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
is of class `cvm_tbl` and carries six provenance attributes:

``` r

attr(out, "source")           #  "mirror" or "cvm"
attr(out, "fetched_at")       #  POSIXct, set at download time
attr(out, "group")            #  CKAN group slug, e.g. "companhias"
attr(out, "dataset")          #  "dfp"
attr(out, "table")            #  "bpa"
attr(out, "package_version")  #  packageVersion("cvmdata")
```

`print.cvm_tbl()` renders the five header attributes before delegating
to the standard tibble print, so a snapshot taken at the REPL is
self-describing.

## Cache and source backend

The cache lives under `tools::R_user_dir("cvmdata", "cache")` by
default. Two functions inspect and reset it:

``` r

cvm_cache_path()
cvm_cache_info()                # current size + unit breakdown
cvm_cache_clear()               # interactive prompt by default
```

Knobs:

- `options(cvmdata.cache_ttl_seconds = ...)` — HTTP revalidation window
  (default 30 days; `0` = always HEAD; `Inf` = never).
- `options(cvmdata.cache_max_size_mb = ...)` — LRU eviction threshold
  (default 100 MiB).
- `cvm_cache_set_path(path)` — relocate the cache directory.
- `cvm_cache_clear(what = c("all", "raw", "parquet"), group = ..., dataset = ..., year = ...)`
  — scoped resets.

`source` selects the backend. From v0.1.0 the default is `"mirror"`
(parquet snapshots in GitHub Releases queried via DuckDB with
year-partition filter pushdown, refreshed weekly). The `"cvm"` backend
hits the CVM Open Data Portal directly. Select per call or persist with
`cvm_source_set("cvm")`. The `cache-and-mirror` article walks through
the layout, refresh cadence and equivalence guarantees in detail.

## Utilities

Two CNPJ helpers, deliberately small:

``` r

cnpj_clean("00.000.000/0001-91")
#> [1] "00000000000191"
cnpj_format("00000000000191")
#> [1] "00.000.000/0001-91"
```

[`cnpj_clean()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_clean.md)
strips everything that is not a digit and zero-pads to 14;
[`cnpj_format()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_format.md)
is the inverse. Both vectorise over their input and return
`NA_character_` for invalid elements rather than aborting.

## Error model — condition classes worth catching

Every error or warning emitted by `cvmdata` inherits from
`cvmdata_error` or `cvmdata_warn`. The subclasses below are the ones
most likely to appear in user code:

| Class | Meaning |
|----|----|
| `cvmdata_error_input` | User-supplied argument failed validation. |
| `cvmdata_error_input_ambiguous` | A `(dataset, table)` slug exists in more than one group; pass `group =`. |
| `cvmdata_error_http` | HTTP fetch failed. |
| `cvmdata_error_parse` | Field-count or field-name validation failed under `validate = "strict"`. |
| `cvmdata_error_meta_unavailable` | `meta_status: missing` table called under `validate = "strict"`. |
| `cvmdata_warn_year_fallback` | `year = NULL` fell back to an earlier year (issuer absent in the latest). |
| `cvmdata_warn_partial_failure` | Multi-year batch under `on_error = "warn"` had some years fail. |
| `cvmdata_warn_validation` | Validation divergence under `validate = "warn"`. |
| `cvmdata_warn_meta_unavailable` | `meta_status: missing` table under `validate = "warn"`. |
| `cvmdata_warn_eviction` | LRU eviction removed cache units to honour the size limit. |

Catch them with [`tryCatch()`](https://rdrr.io/r/base/conditions.html)
or [`withCallingHandlers()`](https://rdrr.io/r/base/conditions.html)
keyed on the class string, e.g.:

``` r

out <- tryCatch(
  cvm_fetch("dfp", "bpa", cnpj = "00.000.000/0001-91",
            year = 2024, basis = "ind", source = "cvm"),
  cvmdata_error_http = function(e) {
    message("Portal indisponivel, tentando mirror.")
    cvm_fetch("dfp", "bpa", cnpj = "00.000.000/0001-91",
              year = 2024, basis = "ind", source = "mirror")
  }
)
```

## Where to read next

Topic-specific articles on the pkgdown site:

- **issuer-fetch** — every
  [`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
  argument in depth.
- **itr-dfp** — quarterly + annual statements, end-to-end workflows.
- **fre** — reference form, including the 8 ESG/governance tables
  without CVM META.
- **groups-overview** — the 18 CKAN groups and the single fetcher.
- **cache-and-mirror** — backend dual contract, cache layout, ETL
  refresh cadence.
- **data-defects** — known quirks of the CVM publication and how
  `cvmdata` handles each one.
