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
through `basis`.

\
[`library`](https://rdrr.io/r/base/library.html)`(`[`cvmdata`](https://github.com/SidneyBissoli/cvmdata)`)`

## Reference: tables available

| Table | What it carries | `basis` required? | Notes |
|----|----|----|----|
| `bpa` | Asset side of the balance sheet | Yes (`ind` / `con` / both) | `VL_CONTA × ESCALA_MOEDA` applied (`multiply_by_scale`). |
| `bpp` | Liabilities + equity side | Yes | Idem. |
| `dre` | Income statement | Yes | Idem. |
| `dra` | Statement of comprehensive income | Yes | Idem. |
| `dfc_md` | Cash-flow statement, direct method | Yes | Idem. |
| `dfc_mi` | Cash-flow statement, indirect method | Yes | Idem. |
| `dmpl` | Statement of changes in equity | Yes | Idem; wider table (multiple equity columns). |
| `dva` | Statement of value added (Brazilian-specific) | Yes | Idem. |
| `composicao_capital` | Capital composition (share counts by class) | No (leave unset) | No `cd_cvm` column; indexed by `cnpj_cia`. |
| `parecer` | Auditor opinion (free-text) | No | One row per filing, with full opinion text in `texto`. |
| `submissao` | Filing header — `id_doc`, `dt_receb`, `link_doc`, etc. | No | The dataset’s index: one row per delivery, re-filings included; the current one is the last by `dt_receb`, `id_doc`. |

The eight tables that take `basis` always carry a `basis` column in the
result, whether you asked for one variant or for `c("ind", "con")`
(which stacks both).

Use `cvm_dictionary("dfp", "<table>")` to see the column-level metadata
(descriptions, domain, data type, size) for any of the eleven tables;
`cvm_codelist("dfp", "<table>", "<column>")` returns enumerated
categorical values.

## Workflow 1 — Side-by-side total assets across two issuers

Goal: compare 2024 total assets for **BCO BRASIL S.A.** (CNPJ
`00.000.000/0001-91`) and **MAGAZINE LUIZA S.A.** (CNPJ
`47.960.950/0001-21`) using the individual balance sheet (`dfp/bpa`).

\
`bpa`` ``<-`` `[`cvm_fetch`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)`(`\
`  ``"dfp"``, ``"bpa"``,`\
`  cnpj ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``"00.000.000/0001-91"``, ``"47.960.950/0001-21"``)``,`\
`  year ``=`` ``2024``,`\
`  basis ``=`` ``"ind"`\
`)`\
`#> duckdb keeps downloaded extensions and secrets in a temporary directory:`\
`#> ``ℹ`` /tmp/RtmpQbEVm6/duckdb`\
`#> This is removed when the R session ends.`\
`#> ``•`` Extensions are re-downloaded each session.`\
`#> ``•`` Secrets are lost.`\
`#> ``ℹ`` Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).`\
`#> ``ℹ`` Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).`\
`#> ``ℹ`` See ?duckdb_storage for details and alternatives.`\
`#> duckdb keeps downloaded extensions and secrets in a temporary directory:`\
`#> ``ℹ`` /tmp/RtmpQbEVm6/duckdb`\
`#> This is removed when the R session ends.`\
`#> ``•`` Extensions are re-downloaded each session.`\
`#> ``•`` Secrets are lost.`\
`#> ``ℹ`` Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).`\
`#> ``ℹ`` Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).`\
`#> ``ℹ`` See ?duckdb_storage for details and alternatives.`\
`bpa`\
`#> ``ℹ`` ``source``: ``"mirror"`` | ``release``: ``"mirror-companhias-dfp-latest"`` | ``fetched_at``:`\
`#>   ``2026-10-27 19:55:40.058973`\
`#> ``ℹ`` ``group``: ``"companhias"`` | ``dataset``: ``"dfp"`` | ``table``: ``"bpa"`\
`#> ``# A tibble: 226 × 15`\
`#>    cnpj_cia       dt_refer   versao denom_cia cd_cvm grupo_dfp moeda ordem_exerc`\
`#>    ``<chr>``          ``<date>``     ``<chr>``  ``<chr>``     ``<chr>``  ``<chr>``     ``<chr>`` ``<chr>``      `\
`#> `` 1`` 00.000.000/00… 2024-12-31 1      BCO BRAS… 001023 DF Indiv… REAL  PENÚLTIMO  `\
`#> `` 2`` 00.000.000/00… 2024-12-31 1      BCO BRAS… 001023 DF Indiv… REAL  ÚLTIMO     `\
`#> `` 3`` 00.000.000/00… 2024-12-31 1      BCO BRAS… 001023 DF Indiv… REAL  PENÚLTIMO  `\
`#> `` 4`` 00.000.000/00… 2024-12-31 1      BCO BRAS… 001023 DF Indiv… REAL  ÚLTIMO     `\
`#> `` 5`` 00.000.000/00… 2024-12-31 1      BCO BRAS… 001023 DF Indiv… REAL  PENÚLTIMO  `\
`#> `` 6`` 00.000.000/00… 2024-12-31 1      BCO BRAS… 001023 DF Indiv… REAL  ÚLTIMO     `\
`#> `` 7`` 00.000.000/00… 2024-12-31 1      BCO BRAS… 001023 DF Indiv… REAL  PENÚLTIMO  `\
`#> `` 8`` 00.000.000/00… 2024-12-31 1      BCO BRAS… 001023 DF Indiv… REAL  ÚLTIMO     `\
`#> `` 9`` 00.000.000/00… 2024-12-31 1      BCO BRAS… 001023 DF Indiv… REAL  PENÚLTIMO  `\
`#> ``10`` 00.000.000/00… 2024-12-31 1      BCO BRAS… 001023 DF Indiv… REAL  ÚLTIMO     `\
`#> ``# ℹ 216 more rows`\
`#> ``# ℹ 7 more variables: dt_fim_exerc <date>, cd_conta <chr>, ds_conta <chr>,`\
`#> ``#   vl_conta <dbl>, st_conta_fixa <chr>, year <int>, basis <chr>`

The tibble carries provenance attributes and the package has already:

- multiplied `VL_CONTA` by `ESCALA_MOEDA` and dropped the scale column
  (values are in absolute reais);
- converted `DT_REFER`, `DT_FIM_EXERC` to R `Date`;
- kept only the filing delivered last per `(cnpj_cia, dt_refer)` — so
  re-filings do not produce duplicated rows. The `submissao` index is
  the exception: it lists every delivery, with its receipt date.

Total assets is the top of the asset hierarchy (`cd_conta == "1"`):

\
`ativo_total`` ``<-`` ``bpa``[`\
`  ``bpa``$``cd_conta`` ``==`` ``"1"`` ``&`` ``bpa``$``ordem_exerc`` ``==`` ``"ÚLTIMO"``,`\
`  `[`c`](https://rdrr.io/r/base/c.html)`(``"cnpj_cia"``, ``"denom_cia"``, ``"dt_fim_exerc"``, ``"vl_conta"``)`\
`]`\
`ativo_total`\
`#> ``ℹ`` ``source``: ``"mirror"`` | ``release``: ``"mirror-companhias-dfp-latest"`` | ``fetched_at``:`\
`#>   ``2026-10-27 19:55:40.058973`\
`#> ``ℹ`` ``group``: ``"companhias"`` | ``dataset``: ``"dfp"`` | ``table``: ``"bpa"`\
`#> ``# A tibble: 2 × 4`\
`#>   cnpj_cia           denom_cia           dt_fim_exerc      vl_conta`\
`#>   ``<chr>``              ``<chr>``               ``<date>``               ``<dbl>`\
`#> ``1`` 00.000.000/0001-91 BCO BRASIL S.A.     2024-12-31   2``395``432``208``000`\
`#> ``2`` 47.960.950/0001-21 MAGAZINE LUIZA S.A. 2024-12-31     ``32``482``619``000`

CVM publishes each fiscal year’s CSV with two reference columns —
`ÚLTIMO` (the declared year, here 2024) and `PENÚLTIMO` (the comparative
previous year). To pick up an older comparative, request the matching
upstream year explicitly:

\
`bpa_history`` ``<-`` `[`cvm_fetch`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)`(`\
`  ``"dfp"``, ``"bpa"``,`\
`  cnpj ``=`` ``"00.000.000/0001-91"``,`\
`  year ``=`` ``2022``:``2024``,`\
`  basis ``=`` ``"ind"`\
`)`\
`#> duckdb keeps downloaded extensions and secrets in a temporary directory:`\
`#> ``ℹ`` /tmp/RtmpQbEVm6/duckdb`\
`#> This is removed when the R session ends.`\
`#> ``•`` Extensions are re-downloaded each session.`\
`#> ``•`` Secrets are lost.`\
`#> ``ℹ`` Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).`\
`#> ``ℹ`` Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).`\
`#> ``ℹ`` See ?duckdb_storage for details and alternatives.`\
`#> duckdb keeps downloaded extensions and secrets in a temporary directory:`\
`#> ``ℹ`` /tmp/RtmpQbEVm6/duckdb`\
`#> This is removed when the R session ends.`\
`#> ``•`` Extensions are re-downloaded each session.`\
`#> ``•`` Secrets are lost.`\
`#> ``ℹ`` Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).`\
`#> ``ℹ`` Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).`\
`#> ``ℹ`` See ?duckdb_storage for details and alternatives.`\
`ativo_history`` ``<-`` ``bpa_history``[`\
`  ``bpa_history``$``cd_conta`` ``==`` ``"1"`` ``&`` ``bpa_history``$``ordem_exerc`` ``==`` ``"ÚLTIMO"``,`\
`  `[`c`](https://rdrr.io/r/base/c.html)`(``"dt_fim_exerc"``, ``"vl_conta"``)`\
`]`\
`ativo_history``[`[`order`](https://rdrr.io/r/base/order.html)`(``ativo_history``$``dt_fim_exerc``)``, ``]`\
`#> ``ℹ`` ``source``: ``"mirror"`` | ``release``: ``"mirror-companhias-dfp-latest"`` | ``fetched_at``:`\
`#>   ``2026-10-27 19:55:41.328744`\
`#> ``ℹ`` ``group``: ``"companhias"`` | ``dataset``: ``"dfp"`` | ``table``: ``"bpa"`\
`#> ``# A tibble: 3 × 2`\
`#>   dt_fim_exerc      vl_conta`\
`#>   ``<date>``               ``<dbl>`\
`#> ``1`` 2022-12-31   2``062``674``549``000`\
`#> ``2`` 2023-12-31   2``208``053``634``000`\
`#> ``3`` 2024-12-31   2``395``432``208``000`

The `PENÚLTIMO` column is the comparative the issuer presented a year
later, and issuers restate it. `reading` reads an exercise by its own
year and labels the two readings — the figures originally filed
(`ÚLTIMO` of that year’s file) and the comparative of the following
year’s file (`PENÚLTIMO` there):

\
`bpa_2023`` ``<-`` `[`cvm_fetch`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)`(`\
`  ``"dfp"``, ``"bpa"``,`\
`  cnpj ``=`` ``"00.000.000/0001-91"``,`\
`  year ``=`` ``2023``,`\
`  basis ``=`` ``"con"``,`\
`  reading ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``"original"``, ``"restated"``)`\
`)`\
`#> duckdb keeps downloaded extensions and secrets in a temporary directory:`\
`#> ``ℹ`` /tmp/RtmpQbEVm6/duckdb`\
`#> This is removed when the R session ends.`\
`#> ``•`` Extensions are re-downloaded each session.`\
`#> ``•`` Secrets are lost.`\
`#> ``ℹ`` Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).`\
`#> ``ℹ`` Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).`\
`#> ``ℹ`` See ?duckdb_storage for details and alternatives.`\
`#> duckdb keeps downloaded extensions and secrets in a temporary directory:`\
`#> ``ℹ`` /tmp/RtmpQbEVm6/duckdb`\
`#> This is removed when the R session ends.`\
`#> ``•`` Extensions are re-downloaded each session.`\
`#> ``•`` Secrets are lost.`\
`#> ``ℹ`` Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).`\
`#> ``ℹ`` Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).`\
`#> ``ℹ`` See ?duckdb_storage for details and alternatives.`\
`#> duckdb keeps downloaded extensions and secrets in a temporary directory:`\
`#> ``ℹ`` /tmp/RtmpQbEVm6/duckdb`\
`#> This is removed when the R session ends.`\
`#> ``•`` Extensions are re-downloaded each session.`\
`#> ``•`` Secrets are lost.`\
`#> ``ℹ`` Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).`\
`#> ``ℹ`` Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).`\
`#> ``ℹ`` See ?duckdb_storage for details and alternatives.`\
`#> duckdb keeps downloaded extensions and secrets in a temporary directory:`\
`#> ``ℹ`` /tmp/RtmpQbEVm6/duckdb`\
`#> This is removed when the R session ends.`\
`#> ``•`` Extensions are re-downloaded each session.`\
`#> ``•`` Secrets are lost.`\
`#> ``ℹ`` Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).`\
`#> ``ℹ`` Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).`\
`#> ``ℹ`` See ?duckdb_storage for details and alternatives.`\
`bpa_2023``[`\
`  ``bpa_2023``$``cd_conta`` `[`%in%`](https://rdrr.io/r/base/match.html)` `[`c`](https://rdrr.io/r/base/c.html)`(``"1"``, ``"1.02"``)``,`\
`  `[`c`](https://rdrr.io/r/base/c.html)`(``"dt_refer"``, ``"ordem_exerc"``, ``"dt_fim_exerc"``, ``"cd_conta"``, ``"vl_conta"``,`\
`    ``"reading"``)`\
`]`\
`#> ``ℹ`` ``source``: ``"mirror"`` | ``release``: ``"mirror-companhias-dfp-latest"`` | ``fetched_at``:`\
`#>   ``2026-10-27 19:55:42.497016`\
`#> ``ℹ`` ``group``: ``"companhias"`` | ``dataset``: ``"dfp"`` | ``table``: ``"bpa"`\
`#> ``# A tibble: 4 × 6`\
`#>   dt_refer   ordem_exerc dt_fim_exerc cd_conta      vl_conta reading `\
`#>   ``<date>``     ``<chr>``       ``<date>``       ``<chr>``            ``<dbl>`` ``<chr>``   `\
`#> ``1`` 2023-12-31 ÚLTIMO      2023-12-31   1        2``153``878``452``000 original`\
`#> ``2`` 2023-12-31 ÚLTIMO      2023-12-31   1.02     1``937``460``342``000 original`\
`#> ``3`` 2024-12-31 PENÚLTIMO   2023-12-31   1        2``153``878``452``000 restated`\
`#> ``4`` 2024-12-31 PENÚLTIMO   2023-12-31   1.02     1``935``460``343``000 restated`

## Workflow 2 — Capital composition and the filing header

`composicao_capital` does not carry `cd_cvm` — it indexes by `cnpj_cia`,
which is exactly what `cnpj` matches, so the call is the same as for any
other table:

\
`cap`` ``<-`` `[`cvm_fetch`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)`(`\
`  ``"dfp"``, ``"composicao_capital"``,`\
`  cnpj ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``"00.000.000/0001-91"``, ``"47.960.950/0001-21"``)``,`\
`  year ``=`` ``2024`\
`)`\
`#> duckdb keeps downloaded extensions and secrets in a temporary directory:`\
`#> ``ℹ`` /tmp/RtmpQbEVm6/duckdb`\
`#> This is removed when the R session ends.`\
`#> ``•`` Extensions are re-downloaded each session.`\
`#> ``•`` Secrets are lost.`\
`#> ``ℹ`` Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).`\
`#> ``ℹ`` Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).`\
`#> ``ℹ`` See ?duckdb_storage for details and alternatives.`\
`#> duckdb keeps downloaded extensions and secrets in a temporary directory:`\
`#> ``ℹ`` /tmp/RtmpQbEVm6/duckdb`\
`#> This is removed when the R session ends.`\
`#> ``•`` Extensions are re-downloaded each session.`\
`#> ``•`` Secrets are lost.`\
`#> ``ℹ`` Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).`\
`#> ``ℹ`` Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).`\
`#> ``ℹ`` See ?duckdb_storage for details and alternatives.`\
`cap`\
`#> ``ℹ`` ``source``: ``"mirror"`` | ``release``: ``"mirror-companhias-dfp-latest"`` | ``fetched_at``:`\
`#>   ``2026-10-27 19:55:43.004552`\
`#> ``ℹ`` ``group``: ``"companhias"`` | ``dataset``: ``"dfp"`` | ``table``: ``"composicao_capital"`\
`#> ``# A tibble: 2 × 11`\
`#>   cnpj_cia           dt_refer   versao denom_cia          qt_acao_ordin_cap_in…¹`\
`#>   ``<chr>``              ``<date>``     ``<chr>``  ``<chr>``                               ``<dbl>`\
`#> ``1`` 00.000.000/0001-91 2024-12-31 1      BCO BRASIL S.A.                ``5``730``834``040`\
`#> ``2`` 47.960.950/0001-21 2024-12-31 1      MAGAZINE LUIZA S.…              738``995``248`\
`#> ``# ℹ abbreviated name: ¹​qt_acao_ordin_cap_integr`\
`#> ``# ℹ 6 more variables: qt_acao_pref_cap_integr <dbl>,`\
`#> ``#   qt_acao_total_cap_integr <dbl>, qt_acao_ordin_tesouro <dbl>,`\
`#> ``#   qt_acao_pref_tesouro <dbl>, qt_acao_total_tesouro <dbl>, year <int>`

Note: no `basis` argument — `composicao_capital` is a single concept,
not split into individual / consolidated, and passing `basis` to it
aborts.

Cross-check against the underlying submissao header, which is also where
a CVM code (`cd_cvm`) meets its CNPJ:

\
`sub`` ``<-`` `[`cvm_fetch`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)`(`\
`  ``"dfp"``, ``"submissao"``,`\
`  cnpj ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``"00.000.000/0001-91"``, ``"47.960.950/0001-21"``)``,`\
`  year ``=`` ``2024`\
`)`\
`#> duckdb keeps downloaded extensions and secrets in a temporary directory:`\
`#> ``ℹ`` /tmp/RtmpQbEVm6/duckdb`\
`#> This is removed when the R session ends.`\
`#> ``•`` Extensions are re-downloaded each session.`\
`#> ``•`` Secrets are lost.`\
`#> ``ℹ`` Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).`\
`#> ``ℹ`` Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).`\
`#> ``ℹ`` See ?duckdb_storage for details and alternatives.`\
`sub``[``, `[`c`](https://rdrr.io/r/base/c.html)`(``"cd_cvm"``, ``"denom_cia"``, ``"dt_refer"``, ``"id_doc"``)``]`\
`#> ``ℹ`` ``source``: ``"mirror"`` | ``release``: ``"mirror-companhias-dfp-latest"`` | ``fetched_at``:`\
`#>   ``2026-10-27 19:55:43.261773`\
`#> ``ℹ`` ``group``: ``"companhias"`` | ``dataset``: ``"dfp"`` | ``table``: ``"submissao"`\
`#> ``# A tibble: 2 × 4`\
`#>   cd_cvm denom_cia           dt_refer   id_doc`\
`#>   ``<chr>``  ``<chr>``               ``<date>``     ``<chr>`` `\
`#> ``1`` 001023 BCO BRASIL S.A.     2024-12-31 144874`\
`#> ``2`` 022470 MAGAZINE LUIZA S.A. 2024-12-31 145377`

ITR works the same way — replace `"dfp"` with `"itr"`. The trimester
breakdown then shows up in `dt_refer`, `dt_fim_exerc` and in the
`ds_conta` / `grupo_dfp` columns; the underlying mechanics
(`multiply_by_scale`, `keep_latest_version`, date conversion via the
dictionary) are shared. To pick quarters rather than whole years, pass a
`from`/`to` window on the reference date:

\
`h1`` ``<-`` `[`cvm_fetch`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)`(`\
`  ``"itr"``, ``"bpa"``,`\
`  cnpj ``=`` ``"00.000.000/0001-91"``,`\
`  from ``=`` ``"2024-01-01"``, to ``=`` ``"2024-06-30"``,`\
`  basis ``=`` ``"con"`\
`)`\
`#> duckdb keeps downloaded extensions and secrets in a temporary directory:`\
`#> ``ℹ`` /tmp/RtmpQbEVm6/duckdb`\
`#> This is removed when the R session ends.`\
`#> ``•`` Extensions are re-downloaded each session.`\
`#> ``•`` Secrets are lost.`\
`#> ``ℹ`` Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).`\
`#> ``ℹ`` Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).`\
`#> ``ℹ`` See ?duckdb_storage for details and alternatives.`\
`#> duckdb keeps downloaded extensions and secrets in a temporary directory:`\
`#> ``ℹ`` /tmp/RtmpQbEVm6/duckdb`\
`#> This is removed when the R session ends.`\
`#> ``•`` Extensions are re-downloaded each session.`\
`#> ``•`` Secrets are lost.`\
`#> ``ℹ`` Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).`\
`#> ``ℹ`` Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).`\
`#> ``ℹ`` See ?duckdb_storage for details and alternatives.`\
[`unique`](https://rdrr.io/r/base/unique.html)`(``h1``$``dt_refer``)`\
`#> [1] "2024-03-31" "2024-06-30"`

## Where to read next

- **issuer-fetch** — argument reference and the full `cnpj` / `ticker` /
  `year` / `from` / `to` / `basis` / `validate` / `on_error` semantics.
- **fre** — reference form. Same package, different table semantics.
- **cvm-defects** — known publication quirks behind the transformations
  applied here.
