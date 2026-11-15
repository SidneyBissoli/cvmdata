# Every known version of a filing

An issuer may file the same document more than once: a DFP or ITR
re-filed to fix a figure, a scale, a note.
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
returns the current version of each document, as the CVM's yearly files
do. `cvm_versions()` returns every version the package knows of, the
current one included, so the figures of a filing can be followed from
one version to the next. The signature mirrors the part of
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
that identifies the documents (`dataset`, `table`, `cnpj`, `ticker`,
`year`, `basis`) and takes none of its row filters: `reading`,
`from`/`to` and `as_of` select rows of the current reading and are
refused here.

Only the tables that keep a single filing per document (those whose
schema declares `keep_latest_version`: the DFP, ITR and FRE detail
tables, among others) have a version history. Asking for another table,
such as a dataset's `submissao` index or the CAD register, aborts: those
already return every row the CVM publishes. The list of tables is in the
section *Arguments by table* of
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md).

## Usage

``` r
cvm_versions(
  dataset,
  table,
  cnpj = NULL,
  ticker = NULL,
  year = NULL,
  basis = NULL,
  source = NULL,
  on_error = "abort",
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
  like `cnpj`; the two arguments combine. The lookup reads every yearly
  FCA file that carries trading codes (2018 onwards), so the code of a
  company that has since left the exchange still resolves, for any
  `year`. A ticker absent from every file aborts with
  `cvmdata_error_input`; so does a ticker that maps to more than one
  issuer (pass `cnpj` instead).

- year:

  Integer vector of years whose documents to return, as the CVM
  publishes them (one file per year). `NULL` (default) uses the latest
  available year.

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

  `"abort"` (default) or `"warn"`: what to do when a CVM file departs
  from the table's schema (field count or names) or one of several
  yearly files fails to download. `"abort"` stops with a classed error
  (`cvmdata_error_parse` or `cvmdata_error_http`) for
  [`tryCatch()`](https://rdrr.io/r/base/conditions.html). `"warn"` reads
  the file anyway, skips the failed years and returns the rest, with a
  `cvmdata_warn_validation` or `cvmdata_warn_partial_failure` warning;
  wrap the call in
  [`suppressWarnings()`](https://rdrr.io/r/base/warning.html) to silence
  them. A call where nothing could be read always aborts.

- ...:

  Reserved; any extra argument aborts. `reading`, `from`/`to` and
  `as_of` are refused by name.

## Value

A `cvm_tbl` (a tibble subclass) with the columns of the table, `basis`
for the tables published in individual and consolidated variants, and
the five version columns described above. Empty when the issuers have no
filing in the period.

## Where the versions come from

The two backends know different parts of the history.

- `source = "mirror"` (the default) reads, for every partition of the
  table, the current asset
  [`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
  reads plus the `history` asset the ETL keeps next to it with the
  superseded filings, dated. The history holds the filings the mirror
  saw being replaced from 2026-10 on and, for the DFP and ITR
  statements, the ones recovered from the CVM's filing system (RAD) back
  to 2010; `history_source` says which (`"mirror"` or `"rad"`). A change
  of the company's name in the CVM register is not a version: the CVM
  rewrites the name in every row of every year under the same filing,
  and the history does not record it. The name a filing carried on a
  given date is in the dated snapshot of the mirror
  ([`cvm_release_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_release_set.md)).

- `source = "cvm"` reads the CVM's yearly CSV without collapsing it to
  the current filing. That file keeps only the versions the CVM still
  publishes, usually the current one alone, and carries no supersession
  date, so `superseded_at`, `id_doc` and `motivo_reapresentacao` are
  `NA` there; the call says so once. The complete history is on the
  mirror.

## Columns

The columns of the table, `year` and `basis` as
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
returns them, then six version columns:

- `superseded_at`: `Date` the version stopped being the current one (the
  receipt date of the version that replaced it); `NA` for the current
  version.

- `superseded_by_versao`: the `versao` of the filing that replaced it;
  `NA` for the current version.

- `history_source`: `"current"` for the rows of the current version,
  `"mirror"` or `"rad"` for a superseded version on the mirror, `"cvm"`
  for a superseded version still in the CVM's yearly file.

- `id_doc`: the CVM document id of the superseded filing, when the
  history knows it.

- `motivo_reapresentacao`: the reason the issuer gave for the re-filing,
  as the CVM publishes it, when known.

- `scale_error`: whether the superseded version was a scale error (see
  below); `"sem erro de escala"` for the current version.

Rows are ordered by issuer, reference date and `versao`. `versao` is not
a key on its own: the CVM index carries two filings under the same
`VERSAO` for some documents.

## Scale errors

About one superseded DFP or ITR version in twenty is not a restatement
but a filing in the wrong unit (R\$ units where the form asks for R\$
thousand, or the reverse), replaced within days by the same figures a
thousand times larger or smaller; measured on the mirror in 2026-11,
every year from 2010 on has such documents. Their rows stay in the
history (the wrong figures were public) and `scale_error` says what the
replacement changed, judged by the ETL over the whole document (the
eight statements, individual and consolidated) with one verdict per
version:

- `"apenas erro de escala"`: every account the two versions share
  differs by the same factor of 1000, and neither has an account the
  other lacks. The version carries no information of its own.

- `"erro de escala e outras mudanças"`: more than half of the shared
  accounts differ by one factor of 1000, but some differ otherwise or
  exist in one version only. The replacement fixed the unit and changed
  figures.

- `"sem erro de escala"`: everything else, the current version included:
  an ordinary restatement, or a version identical to its replacement.

The judgement reads the `ÚLTIMO` rows, leaves out the per-share accounts
(`3.99*`), and takes accounts with a zero on both sides as saying
nothing. `NA` marks a superseded version the ETL has not judged yet (it
runs after every update of the history). When the result holds a version
with a scale error the call says so once, with a message (not a warning:
a whole year always has one);
[`suppressMessages()`](https://rdrr.io/r/base/message.html) silences it.

## See also

Other fetchers:
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)

## Examples

``` r
if (FALSE) { # interactive()
# Petrobras filed its consolidated 2023 income statement twice;
# version 1 was superseded on 2024-03-25 and net income (account
# 3.11, exercise row) is the same in both.
petr <- cvm_versions(
  "dfp",
  "dre",
  ticker = "PETR4",
  year = 2023,
  basis = "con"
)
petr[
  petr$cd_conta == "3.11" & petr$ordem_exerc == "ÚLTIMO",
  c("versao", "superseded_at", "superseded_by_versao", "vl_conta")
]

# Braskem filed it three times: version 1 in R$ units (a loss of
# R$ 4.5 million) AND with other figures, version 2 "to reflect the
# R$ thousand scale" (a loss of R$ 4.89 billion: other operating
# expenses grew by R$ 360 million too) and version 3, identical to
# version 2 in this statement. `scale_error` tells the two apart.
brkm <- cvm_versions(
  "dfp",
  "dre",
  cnpj = "42.150.391/0001-70",
  year = 2023,
  basis = "con"
)
unique(brkm[, c("versao", "superseded_at", "scale_error")])
}
```
