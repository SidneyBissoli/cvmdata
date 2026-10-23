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
```

Live chunks below use the default mirror backend (GitHub Releases +
DuckDB): the docs build must not depend on the CVM portal being up — a
portal timeout took the site down on 2026-06-03. The mirror releases
follow the current `mirror-<group>-<dataset>-latest` naming since
2026-06-09, so the old live-portal pin is gone.

## Inventory

| \# | Defect | Upstream behaviour | `cvmdata` treatment |
|----|----|----|----|
| 1 | Embedded control characters in free-text FRE fields (e.g. BEL ) | `Experiencia_Profissional` and similar carry raw control bytes | Preserved verbatim — “stays as in CVM”. A `cvm_strip_control_chars()` helper is on the v0.2 list. |
| 2 | CEP loses leading zeros in CAD | META declares `tipo_dados: numeric`; “01310-100” arrives as `1310100` | Preserved; a `cep_pad()` helper is on the v0.2 list. The column is forced to `character`. |
| 3 | Empty `Descrição` / `Domínio` in some META FRE entries | Reader sees partial metadata blocks | Tolerated. The dictionary snapshot keeps the row with `NA` for the empty fields. |
| 4 | `VL_CONTA` declared `decimal(29,10)` | Up to 29 digits of precision; R `double` resolves ~15–17 significant figures | Documented limitation. No silent truncation; values above the safe range have not been observed in the public companies feed. |
| 5 | CD_CVM zero-padding inconsistent between datasets | CAD ships `1023`; ITR/DFP ship `001023` | **See example below.** Preserved as published; [`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md) filters by CNPJ, so the padding never enters a call. |
| 6 | CNPJ comes with punctuation (`00.000.000/0001-91`) | Per-row formatting; not stripped upstream | Preserved in `cnpj_cia`. `cnpj` accepts both punctuated and clean forms. [`cnpj_clean()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_clean.md) / [`cnpj_format()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_format.md) round-trip. |
| 7 | `VL_CONTA × ESCALA_MOEDA` (UNIDADE / MIL / MILHÃO / BILHÃO) | Two columns; user must multiply | **See example below.** Applied via the canonical `multiply_by_scale` transformation; `escala_moeda` dropped. |
| 8 | Eight FRE tables ship without published META | Dictionary `.txt` never released for `empregado_PCD` and seven kin | **See example below.** YAML declares `meta_status: missing`; `validate = "warn"` or `"skip"` opt-in required. |
| 9 | `ORDEM_EXERC ∈ {ÚLTIMO, PENÚLTIMO}` per yearly CSV | Each year’s CSV covers only the declared year and N − 1, and the N − 1 column is the issuer’s comparative, often restated | Returned as-is by default. `reading = c("original", "restated")` reads an exercise by its own year and labels the figures originally filed and the comparative of the following year’s file. To assemble three or more consecutive years, pass an explicit `year` vector spanning the range. |
| 10 | FRE 2024 META URL anomalies | Archive name is `meta_fre_cia_aberta.zip` (no `_txt.zip` suffix); `empregado_local_faixa_etaria` entry lives without the `meta_` prefix | Schema-level fixups: `cvm_dictionary_url` lists the archive plus entry; reader looks for both prefixed and bare entry names. |
| 11 | `VERSAO` per `(cnpj_cia, dt_refer)` enables re-filings | Multiple rows for the same filing key when re-filed | **See example below.** Applied via the canonical `keep_latest_version` transformation, which orders filings by delivery (see \#14). |
| 12 | Dates as `YYYY-MM-DD` strings | Plain strings in the CSV | Converted to R `Date` for every column the dictionary declares `tipo_dados: "date"`. |
| 13 | FRE-detail and some ITR/DFP tables lack a `cd_cvm` column | Filter must run on CNPJ | **See example below.** [`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md) identifies issuers by CNPJ (or ticker) only, matching `cnpj_cia` or `cnpj_companhia` as the table carries. |
| 14 | Repeated filings and repeated rows | Two filings under the same version; DFP/ITR statement CSVs repeat rows, often the whole statement | **See below.** Detail tables keep the last delivery; `submissao` lists every one; identical rows dropped from DFP/ITR tables with `cvmdata_warn_duplicate_filing`. |
| 15 | A later filing delivered under a lower `VERSAO` | The statement CSVs keep the highest version, not the last delivery | **See below.** `cvmdata_warn_stale_filing` names the issuers; the table keeps the CVM numbers. |
| 16 | Comparative column filled with zeros | When an issuer presents no comparative, the `PENÚLTIMO` rows carry `0`, not `NA`: 21 banks did so for 2024 on the individual basis in the DFP 2025, after adopting CMN Resolution 4,966 without restating | Returned as-is, including through `reading = "restated"`. A zero in a comparative column of a bank’s individual statements for 2024 means “not presented”, not a zero balance. |

## Mini-examples for the structural cases

### \#5 — CD_CVM padding preserved per dataset

CAD ships CD_CVM unpadded, ITR/DFP pad to six digits. The same issuer,
selected by CNPJ in both, shows the two forms:

``` r

a <- cvm_fetch("dfp", "bpa", cnpj = "00.000.000/0001-91",
               year = 2024, basis = "ind")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpkV1wSQ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpkV1wSQ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
b <- cvm_fetch("cad", "companhias", cnpj = "00.000.000/0001-91")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpkV1wSQ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
unique(a$cd_cvm)
#> [1] "001023"
unique(b$cd_cvm)
#> [1] "1023"
```

The returned `cd_cvm` column is whatever the dataset publishes —
six-digit padded for DFP, two- to five-digit unpadded for CAD.
Identifier columns are forced to `character` (CLAUDE.md §2.4) so neither
form is corrupted. Because
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
selects issuers by CNPJ, the padding never has to be normalised at the
call; the registry is where a CVM code is translated to its CNPJ.

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

bpa <- cvm_fetch("dfp", "bpa", cnpj = "00.000.000/0001-91",
                 year = 2024, basis = "ind")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpkV1wSQ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpkV1wSQ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.

# Total assets reported by BCO BRASIL in 2024 (reais):
bpa[bpa$cd_conta == "1" & bpa$ordem_exerc == "ÚLTIMO", "vl_conta"]
#> ℹ source: "mirror" | fetched_at: 2026-10-23 15:16:14.374542
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

cvm_fetch("fre", "empregado_PCD",
          cnpj = "00.000.000/0001-91", year = 2024)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpkV1wSQ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> ℹ source: "mirror" | fetched_at: 2026-10-23 15:16:15.357523
#> ℹ group: "companhias" | dataset: "fre" | table: "empregado_PCD"
#> # A tibble: 0 × 11
#> # ℹ 11 variables: cnpj_companhia <chr>, data_referencia <date>, versao <chr>,
#> #   id_documento <chr>, nome_companhia <chr>, codigo_posicao <chr>,
#> #   posicao <chr>, quantidade_pcd <dbl>, quantidade_nao_pcd <dbl>,
#> #   quantidade_sem_resposta <dbl>, year <int>
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
each detail table where re-filings happen, the schema declares a
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

Result: at most one row per filing key in the returned tibble. The
`submissao` table of each dataset is the exception: it is the filing
index and returns every delivery, with its receipt date and document id
(see \#14 and \#15 below for how to read the current one).

``` r

auditor <- cvm_fetch("fre", "auditor",
                     cnpj = "00.000.000/0001-91", year = 2024)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpkV1wSQ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpkV1wSQ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
# One row per (cnpj_companhia, data_referencia):
nrow(unique(auditor[, c("cnpj_companhia", "data_referencia")])) ==
  nrow(auditor)
#> [1] FALSE
```

### \#13 — Tables without `cd_cvm`

`fre/auditor`, `dfp/composicao_capital`, `dfp/parecer`, and several
FRE-detail tables index by `cnpj_companhia` (or `cnpj_cia`) without
carrying `cd_cvm`.
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
identifies issuers by CNPJ (or by a B3 ticker, resolved to CNPJ), and
matches whichever CNPJ column the table carries:

``` r

auditor <- cvm_fetch("fre", "auditor",
                     cnpj = "00.000.000/0001-91", year = 2024)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpkV1wSQ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpkV1wSQ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
"cd_cvm" %in% names(auditor)
#> [1] FALSE
unique(auditor$cnpj_companhia)
#> [1] "00.000.000/0001-91"
unique(auditor$nome_companhia)
#> [1] "BCO BRASIL S.A."
```

The interface is identical regardless of which table holds CD_CVM
natively. A CVM code known only by itself is translated to its CNPJ
through the registry (`cvm_fetch("cad", "companhias")`) or the dataset’s
`submissao`; the deprecated
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)
still does that lookup on the caller’s behalf until it is removed.

### \#14 and \#15 — `VERSAO` is not a filing key

`keep_latest_version` ranks filings by delivery, not by version number:
receipt date (`dt_receb`, `data_entrega`), then the CVM document id,
then `versao`. Tables without delivery columns fall back to the highest
`versao`. Two cases measured on 2026-10-18 show why the version number
alone fails:

- **TRV XLIII Securitizadora, DFP 2023.** The filing index lists two
  deliveries as version 1 (document ids 135158 and 135670). The DFP
  statement CSVs carry both, every account twice, with no column to tell
  them apart, so a sum over the issuer counts double. Dibens Leasing
  (ITR, 2023-09-30) is the same case.

  Repeated rows are more common than repeated filings. Across every DFP
  and ITR file from 2010 to 2026, 884 issuer-period-table cases have the
  whole statement doubled and 110 more a few accounts repeated, most of
  them with a single filing in the index (AXIA Energia Norte, DFP 2023,
  is one). A statement has one row per account, order and period, so the
  package drops the identical copies and warns with
  `cvmdata_warn_duplicate_filing`. Copies that differ in `vl_conta` are
  kept, with `cvmdata_warn_conflicting_filing`, since nothing says which
  is right.

- **Travessia Securitizadora VI, DFP 2024.** Versions 1, 2 and again 1,
  the last one delivered on 2025-08-14. That filing has other numbers
  (total assets R\$ 14.4 million against R\$ 31.2 million in version 2),
  and it is the one the issuer reports as the 2024 comparative in its
  DFP 2025. The DFP 2024 statement CSVs still hold version 2. The
  package returns the CVM numbers and warns with
  `cvmdata_warn_stale_filing`.

Both checks read the dataset’s `submissao` of the same year, take the
last delivery of each filing key from it, and run for either backend.
`options(cvmdata.check_filings = FALSE)` turns them off.

The `submissao` itself is not collapsed since 0.2.0.9000: it lists every
delivery of a filing, so the history behind both cases above is one call
away, and the current filing is the last row by receipt date, then
document id, then `versao`:

``` r

history <- cvm_fetch("dfp", "submissao",
                     cnpj = "43.335.774/0001-86", year = 2024)
history[, c("dt_refer", "versao", "id_doc", "dt_receb")]
# Three deliveries for 2024-12-31: versions 1, 2 and again 1.

current <- history |>
  dplyr::arrange(dt_receb, as.integer(id_doc), as.integer(versao)) |>
  dplyr::slice_tail(n = 1, by = c(cnpj_cia, dt_refer))
# id_doc and versao are character (identifiers); as.integer() orders
# them numerically.
```

Before this release the index returned only that last row, so a join of
`submissao` to a statement table on `(cnpj_cia, dt_refer)` matched one
delivery; it now matches all of them, and the recipe above restores the
one-row-per-filing view.

## Reading the other defects directly

For defects 1, 2, 3, 4, 6, 9, 10, and 12 the package’s behaviour is
either purely preservational (1, 2, 3, 4, 6) or structurally declared in
the schema (9, 10, 12). The inventory table above points at each YAML
and at the relevant CLAUDE.md section; the package’s source under
`R/transform-schema.R`, `R/util-csv-cvm.R`, `R/api-cvm-fetch.R` and
`R/api-issuer-fetch.R` is the canonical reference.

## Where to read next

- **issuer-fetch** — argument reference; `validate` and `on_error`
  semantics in full.
- **itr-dfp** — workflow with `multiply_by_scale` and
  `keep_latest_version` in action.
- **fre** — workflow with the eight `meta_status: missing` tables.
