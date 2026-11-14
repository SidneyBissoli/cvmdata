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
  as_of = NULL,
  basis = NULL,
  reading = NULL,
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

  Integer vector of years to fetch, as the CVM publishes them (one file
  per year). `NULL` (default) fetches the latest available year. Must be
  `NULL` for datasets with `temporal_partitioning: none` (e.g. CAD), and
  cannot be combined with `from`/`to`. Years the table is not published
  for are refused before any download: years before the table's first
  year, and years from which the CVM publishes its CSV with the header
  only (`fca/departamento_acionistas` from 2024, after Resolução CVM
  59/2021 revoked the block). For such a table, `year = NULL` warns
  (`cvmdata_warn_empty_upstream`): the mirror returns the last year with
  content, the portal returns the latest file, which has zero rows.

- from, to:

  Optional period bounds, both required together, as complete dates
  (`"YYYY-MM-DD"` strings or `Date` scalars). Rows are kept when the
  document's reference date (`dt_refer` or `data_referencia`) falls
  inside `[from, to]`; the yearly files read are the years spanned by
  the interval. Incomplete dates (`"2024"`, `"2024-06"`) are rejected.
  Cannot be combined with `year`, and do not apply to snapshot tables
  such as CAD.

- as_of:

  Optional complete date (`"YYYY-MM-DD"` or `Date`) for registry tables
  only (the three `cad` tables): keeps the registrations in force on
  that date, i.e. registered on or before it and not cancelled by it.
  The rows are the register as the CVM publishes it today, not a
  reconstruction of the past. See the section *Company register*.
  Passing it for any other table aborts.

- basis:

  Individual (`"ind"`), consolidated (`"con"`) or both
  (`c("ind", "con")`) financial statements. Required for tables that
  publish the two variants (`bpa`, `bpp`, `dre`, `dra`, `dfc_md`,
  `dfc_mi`, `dmpl`, `dva`): there is no default, because many issuers
  file only individual statements. Those tables always carry a `basis`
  column in the result, even when a single value was requested. Must be
  `NULL` for every other table; passing it aborts.

- reading:

  Which reading of each fiscal exercise to return, for the DFP and ITR
  statement tables (the ones with `ordem_exerc`): `"original"` (the
  figures the issuer filed for the exercise, the `ÚLTIMO` rows of that
  year's file), `"restated"` (the comparative figures for the same
  exercise in the following year's file, the `PENÚLTIMO` rows there) or
  `c("original", "restated")`, which stacks both. `NULL` (default)
  returns each year's file as the CVM publishes it, `ÚLTIMO` and
  `PENÚLTIMO` rows together, without a `reading` column. When set,
  `year` names the exercises and the following year's files are read as
  needed; the result carries a `reading` column. See the section
  *Readings of an exercise*. Must be `NULL` for tables without
  `ordem_exerc`; passing it aborts.

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

  Reserved for forward compatibility. Currently no extra arguments are
  accepted; passing any aborts with `cvmdata_error_input`.

## Value

A tibble of class `cvm_tbl` carrying the provenance attributes `source`,
`fetched_at`, `group`, `dataset`, `table` and `package_version`.

## Details

Column names, categorical values and free-text fields are preserved in
Portuguese exactly as published by CVM (snake_case minúsculo). Changes
to the published rows are declared per table in its schema (latest
filing, currency scale), with one deliberate exception: in DFP and ITR
tables, rows the CVM file holds twice, identical in every column, are
dropped with a warning, since a statement has one row per account and a
sum over the copies counts twice. See the section *Filing versions*;
`options(cvmdata.check_filings = FALSE)` turns the check off.

## Personal data

The CVM publishes, by legal duty, data of the natural persons who run
and control listed companies. The mirror keeps what research needs and
no more: every CPF, in the columns that hold it and in free text, is
masked the way the Federal Revenue masks its open CNPJ data
(`***.456.789-**`), a foreign document in those columns becomes `***`,
and `data_nascimento` becomes the integer `ano_nascimento`. Contact data
is not carried at all: the columns of e-mail, telephone and fax, of
people and of companies alike, and the street address of a person
(`*_resp` in `cad`; `fca` `dri` and `departamento_acionistas`; `fre`
`auditor_responsavel`) are absent from the mirror. The address of the
company stays. Names, CNPJs and biographies stay as published; the
masked CPF plus the name still follow a person across tables.
`source = "cvm"` reads everything from the CVM untouched, under the same
duty to respect the purpose of the disclosure (Lei 13.709/2018, art. 7,
paragraphs 3 and 4).

## Filing versions

When a detail table carries several filings for the same issuer and
reference date, only the last one delivered is kept, ranked by receipt
date, then CVM document id, then `versao`. The version number alone is
not a filing key: the CVM index can list two filings under the same
version, or a later filing under a lower one.

The `submissao` table of each dataset is the filing index and is not
collapsed: it returns one row per delivery, re-filings included, with
the receipt date (`dt_receb` or `data_entrega`), the document id
(`id_doc`, `id_documento` or `protocolo_entrega`) and `versao`. The
current filing of an issuer and reference date is the last row by that
order; joining `submissao` to a detail table on the issuer and reference
date alone matches every delivery.

Tables of datasets with a `submissao` index are checked against it
before returning. In DFP and ITR tables, rows the CVM file holds twice
are dropped (`cvmdata_warn_duplicate_filing`); copies that differ in
`vl_conta` are kept (`cvmdata_warn_conflicting_filing`). A table holding
an earlier filing than the last delivery keeps the CVM numbers and warns
(`cvmdata_warn_stale_filing`). Set
`options(cvmdata.check_filings = FALSE)` to skip these checks.

## Readings of an exercise

Every yearly DFP and ITR statement file carries two columns of figures
per account: `ordem_exerc = "ÚLTIMO"`, the exercise the file is about,
and `ordem_exerc = "PENÚLTIMO"`, the comparative the issuer presented
for the previous exercise. The comparative is often not the figure
originally filed: issuers restate it after a change of accounting
policy, an error or a reorganisation (about a third of the issuers in
the DFP, measured on the 2023 file against the 2022 one), and the
restated figure is the one later statements build on. With `reading`,
`cvm_fetch()` reads the exercise by its own year and labels each row:

- `"original"`: the `ÚLTIMO` rows of the file of `year`.

- `"restated"`: the `PENÚLTIMO` rows of the file of `year + 1`, read in
  addition to (or instead of) the file of `year`. Rows are returned as
  the CVM publishes them, so `dt_refer` and `versao` are those of the
  following year's document and `dt_fim_exerc` (and `dt_ini_exerc`)
  identify the exercise the figure belongs to. An exercise whose
  following year's file is not published yet has no restated reading;
  the call says so and returns what exists. When the file exists but the
  issuer has not filed in it yet, its restated rows are simply absent.

The two readings of an exercise pair on the issuer, the exercise dates,
`cd_conta` and, in `dmpl`, `coluna_df`. Either reading can be absent for
an issuer (it stopped filing, or started filing in the following year),
and a restated figure can be `0` where the issuer presented no
comparative at all, as the banks did for 2024 on the individual basis
after adopting CMN Resolution 4,966 in 2025. In the ITR, the comparative
of the balance sheet (`bpa`, `bpp`) is the previous year end, not the
previous year's quarter, so the restated reading of an ITR balance sheet
is the year-end balance as the following year's quarterly filings
present it.

With `from`/`to`, the window applies to the exercise end
(`dt_fim_exerc`) rather than to the document date, so an exercise's two
readings stay together.

## Company register

`cad/companhias` is a single file holding today's state of every
registration the CVM ever granted: companies that cancelled their
registration stay in it, with `sit = "CANCELADA"`, `dt_cancel` and
`motivo_cancel` (cancellations go back to 1984 and are three quarters of
the rows). Its key is `(cnpj_cia, cd_cvm, tp_merc)`, which has two
consequences for joins:

- A few dozen CNPJs hold **two registrations** (a company that cancelled
  and registered again years later under a new CVM code). These are
  distinct registrations and the package keeps them apart.

- About a hundred registrations are **repeated in two or three rows that
  differ only in `tp_merc`** (the markets the company is admitted to:
  exchange, organised OTC, non-organised OTC). Every other column is
  identical. A join on `cnpj_cia` alone duplicates those companies. The
  package returns the file as published; for one row per registration,
  drop the market before joining, e.g.
  `dplyr::distinct(reg, cnpj_cia, cd_cvm, .keep_all = TRUE)`. `tp_merc`
  is empty for almost every cancelled company, so filtering on it
  discards delisted companies.

`as_of` answers "which companies were registered on date X" from the
registration and cancellation dates of each registration, which is what
a survivorship-free universe needs. The rows it returns are still
today's: a company registered in 2012 and cancelled in 2017 is part of
the 2015 universe, but its row says `"CANCELADA"`, because the CVM does
not publish past states of the register (the file only records when the
current value of each field started). The yearly `fca/geral` file is the
CVM's own picture of a company in a given year (name, registration
situation, category, issuer situation).

`as_of` is a filter on dates that are already in the file, so it could
be written by hand; it is an argument because the obvious ways of
writing it are wrong. Filtering on `sit = "ATIVO"` returns today's
survivors, which is the bias a historical universe has to avoid. A
condition on `dt_cancel` alone drops every active registration, whose
cancellation date is empty. And a CNPJ that cancelled and registered
again has two rows, each in force over its own period, so the test has
to run on each registration rather than on the company. The argument
applies the one rule (registered on or before the date, cancellation
empty or after it) to each row, and refuses tables that do not declare
registration and cancellation dates.

The CVM keeps two more registers in the same shape, also in `cad`:
`cad/estrangeiras` (foreign companies) and `cad/incentivadas` (companies
registered under the tax-incentive regime). Their issuer column is
`cnpj`, not `cnpj_cia`, and they have no `tp_merc`; `cnpj` and `as_of`
work as in `cad/companhias`. In `cad/incentivadas` most companies never
got a CVM code (`cd_cvm` is `NA` in about 40% of the rows), several
CNPJs were cancelled and registered again, and a few rows carry a
cancellation date with a situation other than `"CANCELADA"`; `as_of`
reads the dates as the CVM published them.

## Arguments by table

Which arguments apply depends on the table. The rules below are
generated from the package's table schemas, the same ones the argument
checks read, for the 104 tables in 9 datasets. An argument passed to a
table it does not apply to aborts with `cvmdata_error_input` before
anything is downloaded; nothing is silently ignored.

- `year` and `from`/`to`: every table published one file per year. Not
  for `cad`: `companhias`, `estrangeiras`, `incentivadas`;
  `recompra_acoes`: `intermediarios`, `quantidades`, `recompra_acoes`, a
  single snapshot. A `year` before the table's first year is refused (a
  `from`/`to` window is cut to it instead). Most tables start with their
  dataset; these start later: `dfp/composicao_capital` (2020),
  `fre/acao_entregue` (2023), `fre/administrador_PCD` (2023),
  `fre/administrador_declaracao_genero` (2023),
  `fre/administrador_declaracao_raca` (2023), `fre/empregado_PCD`
  (2023), `fre/empregado_local_declaracao_genero` (2023),
  `fre/empregado_local_declaracao_raca` (2023),
  `fre/empregado_local_faixa_etaria` (2023),
  `fre/empregado_posicao_declaracao_genero` (2023),
  `fre/empregado_posicao_declaracao_raca` (2023),
  `fre/empregado_posicao_faixa_etaria` (2023),
  `fre/empregado_posicao_local` (2023), `fre/mercado_estrangeiro`
  (2019), `fre/remuneracao_acao` (2023), `fre/remuneracao_variavel`
  (2023), `fre/titular_valor_mobiliario` (2018), `fre/titulo_exterior`
  (2016), `itr/composicao_capital` (2020).

- Years from which the CVM publishes the file with its header only are
  refused too: `fca/departamento_acionistas` (2024).

- Tables the CVM stopped publishing (last year in parentheses) refuse
  later years and require an explicit `year`, since `year = NULL` would
  mean the dataset's latest year: `fre/ativo_imobilizado` (2023),
  `fre/ativo_intangivel` (2023), `fre/auditor_responsavel` (2023),
  `fre/capital_social_aumento` (2023),
  `fre/capital_social_aumento_classe_acao` (2022),
  `fre/capital_social_desdobramento` (2023),
  `fre/capital_social_desdobramento_classe_acao` (2022),
  `fre/capital_social_reducao` (2023),
  `fre/capital_social_reducao_classe_acao` (2022), `fre/direito_acao`
  (2023), `fre/distribuicao_dividendos` (2023),
  `fre/distribuicao_dividendos_classe_acao` (2023), `fre/endividamento`
  (2023), `fre/grupo_economico_reestruturacao` (2016),
  `fre/historico_emissor` (2023), `fre/informacao_financeira` (2023),
  `fre/obrigacao` (2023), `fre/participacao_sociedade_valorizacao_acao`
  (2023), `fre/plano_recompra` (2023), `fre/plano_recompra_classe_acao`
  (2023), `fre/politica_negociacao` (2023),
  `fre/politica_negociacao_cargo` (2023),
  `fre/valor_mobiliario_tesouraria_movimentacao` (2023),
  `fre/valor_mobiliario_tesouraria_ultimo_exercicio` (2016),
  `fre/volume_valor_mobiliario` (2023).

- `basis`: required, with no default, in `dfp` and `itr`: `bpa`, `bpp`,
  `dfc_md`, `dfc_mi`, `dmpl`, `dra`, `dre`, `dva`. Refused in every
  other table.

- `reading`: only in `dfp` and `itr`: `bpa`, `bpp`, `dfc_md`, `dfc_mi`,
  `dmpl`, `dra`, `dre`, `dva` (the tables with `ordem_exerc`).

- `as_of`: only in `cad`: `companhias`, `estrangeiras`, `incentivadas`.

- `cnpj`/`ticker` in a table without an issuer column: `recompra_acoes`:
  `intermediarios`, `quantidades` keep the rows linked to the issuer's
  rows in `recompra_acoes/recompra_acoes`.

- [`cvm_versions()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_versions.md):
  every table except `cad`: `companhias`, `estrangeiras`,
  `incentivadas`; `cgvn`, `dfp`, `fca`, `fre` and `itr`: `submissao`;
  `ipe`: `ipe`; `recompra_acoes`: `intermediarios`, `quantidades`,
  `recompra_acoes`; `vlmo`: `consolidado`, `submissao`, which already
  return every row the CVM publishes.

## See also

Other fetchers:
[`cvm_versions()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_versions.md)

## Examples

``` r
if (FALSE) { # interactive()
# CAD: single snapshot, no year, no basis
issuers <- cvm_fetch("cad", "companhias")

# Registrations in force at the end of 2015 (survivorship-free
# universe), one row per registration
u2015 <- cvm_fetch("cad", "companhias", as_of = "2015-12-31")
u2015 <- dplyr::distinct(u2015, cnpj_cia, cd_cvm, .keep_all = TRUE)

# The registers of foreign and of tax-incentive companies
foreign <- cvm_fetch("cad", "estrangeiras")
incentive <- cvm_fetch("cad", "incentivadas", as_of = "2015-12-31")

# A delisted company by its former ticker
gol <- cvm_fetch("dfp", "dre", ticker = "GOLL4", year = 2019, basis = "con")

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

# Exercise 2022 as originally filed and as restated in the 2023
# file, side by side in a `reading` column
pssa <- cvm_fetch(
  "dfp", "bpa",
  ticker = "PSSA3",
  year = 2022,
  basis = "con",
  reading = c("original", "restated")
)
}
```
