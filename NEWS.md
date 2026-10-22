# cvmdata 0.2.0.9000 (in development)

## ⚠️ Breaking changes

* The four skeleton fetchers `fund_fetch()`, `agent_fetch()`,
  `offering_fetch()` and `event_fetch()`, exported since v0.1.0.9000 as
  placeholders that only aborted, are gone, and so is their condition
  class `cvmdata_error_input_group`. The 2026-05-25 architecture of five
  fetchers by data contract is superseded: a single function serves
  every dataset, and the groups planned for v0.4-v0.8 (funds, agents,
  offerings, events) will extend `cvm_fetch()` through their schemas
  instead of shipping new functions. `cvm_groups()` keeps its `contract`
  column as a planning map.

* `issuer_fetch()` is deprecated in favour of `cvm_fetch()` and warns
  once per session (`lifecycle`). It keeps its behaviour, including the
  `issuer` argument's CVM-code and free-text forms, until it is removed
  in a later release.

* The `submissao` table of every dataset (`dfp`, `itr`, `fre`, `fca`,
  `cgvn`, `vlmo`) now returns the complete filing history: one row per
  delivery, re-filings included, each with its receipt date
  (`dt_receb` / `data_entrega`), document id (`id_doc` / `id_documento`
  / `protocolo_entrega`) and `versao`, as the CVM publishes it. The
  schemas no longer declare `keep_latest_version` for it; the detail
  tables still keep the last delivery. The CVM statement CSVs carry a
  single version per filing, so `submissao` was the only place the
  history could be read from, and the index is where the Travessia and
  TRV cases of the 0.2.0.9000 fixes below are visible. Code that joins
  `submissao` to a detail table on the issuer and reference date now
  matches every delivery; to get the current filing, keep the last row
  per key:

  ```r
  sub |>
    dplyr::arrange(dt_receb, as.integer(id_doc), as.integer(versao)) |>
    dplyr::slice_tail(n = 1, by = c(cnpj_cia, dt_refer))
  ```

  The fetch-time check that warns about a stale filing
  (`cvmdata_warn_stale_filing`) computes that row itself before
  comparing. The parquet mirror (`source = "mirror"`, the default)
  carries the history once the weekly ETL republishes the six datasets
  with this version of the package; until then it serves the
  collapsed index.

## New features

* `cvm_fetch()` is the single public fetcher, built on the same pipeline
  as `issuer_fetch()`:
  `cvm_fetch(dataset, table, cnpj, ticker, year, from, to, basis, ...)`.
  - Issuers are selected by `cnpj` (CNPJ only, with or without
    punctuation; a CVM code or a company name aborts) and/or `ticker`
    (B3 trading code, resolved through `fca/valor_mobiliario` from the
    same `source`). The free-text and CVM-code lookups of `issuer` were
    not carried over: the registry `cvm_fetch("cad", "companhias")` is
    the place to resolve a name or a code to a CNPJ.
  - The period is `year` (whole published years, as before) or a
    `from`/`to` window of complete dates: the yearly files spanned by
    the window are read and rows are kept by the document's reference
    date (`dt_refer` / `data_referencia`). Giving both aborts, as does
    an incomplete date or a window on a snapshot table such as CAD.
  - `basis` replaces `report_type` for the tables published in
    individual and consolidated variants: `"ind"`, `"con"` or
    `c("ind", "con")`, which stacks both. There is no default, because
    many issuers file only individual statements. Those tables always
    carry a `basis` column in the result, on both backends; the mirror's
    `report_type` partition column no longer leaks through
    `cvm_fetch()`.

* `cvm_fetch()` gains `reading`, for the DFP and ITR statement tables
  (the ones with `ordem_exerc`): the two readings of a fiscal exercise,
  side by side. Every yearly file carries the exercise it is about
  (`ÚLTIMO`) and the comparative the issuer presented for the previous
  one (`PENÚLTIMO`), and the comparative is often restated: about a
  third of the DFP issuers in 2023 restated 2022 (Porto Seguro's
  consolidated total assets of 2022 are R$ 50.5 bn in the 2022 file
  and R$ 39.9 bn in the 2023 one). With `reading = "original"` the call
  returns the `ÚLTIMO` rows of the file of `year`; with
  `reading = "restated"`, the `PENÚLTIMO` rows of the file of
  `year + 1`, which the call reads on its own; with both, the two
  stacked. Rows come as published, with a `reading` column appended:
  `dt_refer` and `versao` are those of the document each row came
  from, and `dt_fim_exerc` (plus `dt_ini_exerc`) identify the
  exercise. An exercise whose following file is not published yet has
  no restated reading, and the call says so. `from`/`to` then apply to
  the exercise end. The default, `reading = NULL`, returns each file as
  before, `ÚLTIMO` and `PENÚLTIMO` together and no `reading` column.
  Two things the data showed while measuring: in the ITR, the
  comparative of a balance sheet is the previous year end, not the
  previous year's quarter; and the banks, which adopted CMN Resolution
  4,966 in 2025 without restating, carry the 2024 comparative of their
  individual statements as zeros, which the restated reading returns as
  the CVM publishes them.

* Delisted companies (decisions of 2026-10-21, after a quant reader's
  questions):
  - `cvm_fetch("cad", "companhias", as_of = "2015-12-31")` keeps the
    registrations in force on a date: registered on or before it and
    not cancelled by it. The register is today's state of every
    registration ever granted (cancellations back to 1984 are three
    quarters of the file), so this is the survivorship-free universe a
    backtest needs; the rows are still today's (a company cancelled in
    2017 is in the 2015 universe with `sit = "CANCELADA"`), because the
    CVM does not publish past states of the register. Registry tables
    declare the date columns in their schema (`as_of:`); every other
    table rejects the argument. Measured against the 2015 DFP index:
    599 of the 633 filers fall inside the 640-company universe, the 34
    outside being 11 companies absent from the register and 23 that
    registered in 2016 and filed the 2015 statements on registration.
  - `ticker` now resolves against every yearly `fca/valor_mobiliario`
    file that carries trading codes (2018 onwards; the column is empty
    before), not only the file of the latest requested year. A code
    that left the exchange (`GOLL4`, `BPAN4`) resolves for any `year`,
    and `PETR4` resolves for years before 2018, which used to abort.
    A code that maps to more than one issuer now aborts asking for
    `cnpj` instead of picking one; none does today.
  - The register's key, `(cnpj_cia, cd_cvm, tp_merc)`, is documented in
    `?cvm_fetch` (section *Company register*): 107 registrations repeat
    in rows that differ only in `tp_merc`, and 34 CNPJs hold two
    registrations under distinct CVM codes. The file is returned as
    published; the recipe for one row per registration is in the help.

* A year the table is not published for is refused before any
  download. A table can start later than its dataset: the CVM's yearly
  ZIP simply lacks its CSV before then. The schemas now declare the
  measured first year of 19 tables that used to claim 2010 or 2011
  (`composicao_capital` of the DFP and ITR from 2020; fourteen FRE
  tables such as `acao_entregue`, `remuneracao_variavel` and the
  diversity tables from 2023; `mercado_estrangeiro` from 2019,
  `titular_valor_mobiliario` from 2018, `titulo_exterior` from 2016;
  measured on the mirror's inventory and confirmed in the ZIP members).
  `cvm_fetch()` aborts with `cvmdata_error_input` ("not published for")
  when `year` names an earlier year, and a `from`/`to` window drops the
  years the table does not exist for, saying so. The backend errors
  for a CSV missing from a ZIP, or a partition missing from the mirror,
  now say the table is not published for that year instead of blaming
  the schema.

## Data coverage

* Corrected the declared `first_year` for the v0.2 datasets, which had
  been set to 2021 — the year they were first verified — rather than the
  earliest year the CVM directory listing actually serves. `first_year`
  now equals `min(cvm_dataset_years())` for every yearly table: `fca`
  reaches back to 2010, `ipe` to 2003, and `cgvn` and `vlmo` to 2018. The
  CSV headers in those earlier years already match the current schema, so
  the data reads cleanly under strict validation. This invariant matters
  because `first_year` is now load-bearing: both the year-clamp (below)
  and the ETL's expected-year enumeration key off it, so a value above
  the listing minimum makes the clamp reject — and the mirror ETL hard-
  fail on — years the portal genuinely publishes. The new
  `data-raw/audit-first-year.R` checks the invariant against the live
  portal.

## Bug fixes

* The parquet mirror (`source = "mirror"`, the default) had stopped
  updating in June 2026. The weekly ETL skipped a publish whenever the
  CVM dictionary files were unchanged, and they rarely change, so new
  filings, restatements and package fixes never reached the mirror. The
  publish hash now covers the content of every parquet as well. The
  `vlmo` mirror release had also been left as a draft since June, which
  made `source = "mirror"` fail for `vlmo` with a 404; the ETL now
  publishes the release explicitly and checks it without credentials.
  Releases are now updated in place instead of deleted and recreated,
  so the mirror no longer goes empty while a new snapshot uploads,
  and a failed asset upload is retried before the run gives up.

* `keep_latest_version` now keeps the last filing delivered, ranked by
  receipt date, then CVM document id, then `versao`, instead of the
  highest `versao`. The version number is not a filing key: the DFP 2023
  index lists two "version 1" filings for TRV XLIII Securitizadora, and
  the DFP 2024 index lists versions 1, 2 and again 1 for Travessia
  Securitizadora VI, the last one being the filing the issuer carries
  forward. `submissao` used to return both TRV rows and the superseded
  Travessia row. Tables with no delivery columns still keep the highest
  `versao`.

* `issuer_fetch()` checks each table against its dataset's filing
  index (`submissao`). The CVM statement CSVs repeat rows: a sweep of every DFP and ITR file
  from 2010 to 2026 found 884 issuer-period-table cases with the whole
  statement doubled and 110 with a few accounts repeated, some from two
  filings under the same version (TRV XLIII, DFP 2023), most with a
  single filing in the index. Sums over those issuers counted double.
  Identical rows are now dropped and `cvmdata_warn_duplicate_filing`
  names the issuers; copies that differ in `vl_conta` are kept and flagged
  with `cvmdata_warn_conflicting_filing`. When the table holds an
  earlier filing than the last delivery (the Travessia case, whose
  statement CSVs stayed on version 2), `cvmdata_warn_stale_filing` names
  the issuers. Both checks run for either backend and can be turned off
  with `options(cvmdata.check_filings = FALSE)`. See defects #14 and #15
  in the data-defects article.

* The mirror ETL no longer burns a whole runner on a portal that is not
  answering it. Of the 14 scheduled mirror runs between 2026-06-09 and
  2026-09-08, 8 went red, every one of them in stage 01 and on a
  different `(group, dataset)` each week, while the sibling jobs on
  other runners downloaded normally; the 2026-09-08 `fre` job logged
  `0 ok / 612 failed`, all of them 10 s TCP connect timeouts, after
  5 h 51 min — minutes short of GitHub's 6 h job ceiling. Probing the
  portal from eight runners in parallel on 2026-09-11 showed it
  answering in ~0,15 s over IPv4 from every one, each on a different
  Azure egress IP, so these episodes are the portal dropping some
  egress addresses for a while rather than anything wrong with the URLs
  the ETL builds. Three changes follow from that: a transport failure
  (DNS, TCP connect, TLS, read timeout) now carries the
  `cvmdata_error_http_transport` subclass, which an HTTP status such as
  404 does not, so "the portal did not answer" is distinguishable from
  "this file is not published"; stage 01 trips a circuit breaker after
  8 consecutive transport failures with nothing yet fetched, exiting 3
  in about 5 min instead of walking hundreds of pairs that cannot
  succeed; and the job carries a 120 min ceiling for the partial
  outage, where interleaved successes would keep resetting the breaker.
  A new `ETL mirror retry` workflow then re-runs only the failed jobs,
  each landing on a fresh egress IP, up to 3 attempts.

* CVM portal requests now retry transient failures. `cvm_dataset_years()`
  (directory listing) and the `source = "cvm"` HEAD/GET downloads wrap
  their `httr2` calls in `req_retry(max_tries = 3, retry_on_failure =
  TRUE)`, so an intermittent portal timeout — which the open-data portal
  produces sporadically — no longer aborts the call (or the mirror ETL)
  on the first attempt. Matches the retry already used on the GitHub
  Releases mirror path.

* `cvm_dataset_years()` no longer hard-fails when the CVM directory index
  is unreachable. After the retries above are exhausted it falls back to
  the declared coverage range — `first_year` (now verified to equal the
  listing minimum) through the current year — and warns with class
  `cvmdata_warn_year_listing_fallback`, instead of aborting. This removes
  the directory listing as a single point of failure for the mirror ETL,
  which from foreign CI IPs occasionally cannot reach the index even
  though the per-year archives download fine. A reachable index that
  genuinely lists no archives still aborts.

* `issuer_fetch()` with a free-text `issuer` and `year = NULL` no longer
  aborts with "No issuers match ..." when the company is simply absent
  from the latest probed year (e.g. a header-only current year, or an
  issuer that has not yet filed). Text matching now participates in the
  descending year fallback like CNPJ and CD_CVM matching do, walking
  down to an earlier year that holds the filer; a genuine typo still
  aborts with the spelling hint on the last candidate year. The same
  applies to an explicit multi-year request (e.g. `year = 2012:2024`): a
  text issuer absent from some of the requested years now contributes no
  rows for those years instead of aborting the whole span, and the
  spelling error is raised once only if no requested year matched.

* `issuer_fetch()` with explicit years that precede a dataset's first
  published year (e.g. `year = 2005:2024` for `dfp`, which starts in
  2010) no longer fails with a raw HTTP 404. The years before
  `first_year` are dropped before any request, with an informational
  message listing them, and the remaining years are fetched normally.
  When every requested year is too early the call aborts with a clear
  `cvmdata_error_input` instead of a network error. This applies to both
  the `"mirror"` and `"cvm"` backends; genuine 404s on years that do
  exist remain governed by `on_error`.

* `issuer_fetch()` on the current, not-yet-filed year of an annual
  financial table (e.g. `dfp/dfc_md` for fiscal 2026 early in 2026)
  no longer aborts with "non-numeric argument to binary operator". The
  CVM publishes a header-only CSV for such years; the
  `multiply_by_scale` transform now no-ops on a 0-row table and returns
  a clean empty tibble.

* ETL parquet mirror: the pipeline tolerates `(table, year)` pairs that
  legitimately produce no parquet, so a single absent year no longer
  fails the whole dataset publish. Stage 02 records each skipped tuple
  with a reason — `empty` (0 rows upstream) or `absent` (the detail
  table's CSV is not in that year's ZIP because CVM only began
  publishing it later, e.g. `dfp`/`itr` `composicao_capital` before
  2020, or several `fre` tables in early years) — and stage 02b treats
  a missing parquet for such a tuple as a soft pass instead of a hard
  failure. A parquet that is missing without a recorded reason still
  hard-fails. Fixes the red `dfp`/`itr`/`fre` mirror jobs.

## Internal

* The two ETL workflows that append to the history assets
  (`etl-mirror.yaml`, weekly, and `etl-rad.yaml`, daily) share the
  GitHub Actions concurrency group `etl-history`, so a run of one waits
  for the other to finish. The schedules alone did not keep them apart:
  the RAD run reads `dfp` and `itr` in series and can last until
  08:40 UTC, past the Tuesday 07:00 UTC run of the mirror.

* The mirror ETL keeps the filings it supersedes. Every CVM annual file
  carries only the filing delivered last for each company and reference
  date, so when a company restated a statement the previous rows
  vanished from the mirror on the next weekly publish. Now, for every
  partition whose content hash moved, `inst/etl/03-publish.R` downloads
  the parquet of the previous release and compares it filing by filing
  (`inst/etl/util-history.R`): the rows of the filings the new file
  replaces or drops are appended, with `superseded_at` and
  `superseded_by_versao`, to a cumulative history asset of the same
  partition (`<table>__report_type=R__year=Y__history.parquet`). A
  filing counts as changed by the content of its rows, never by a new
  `versao` or document id alone, and a column the CVM adds upstream is
  not a change of every filing. The `-latest` parquets and the client
  are untouched (`parse_mirror_asset_name()` rejects the history names);
  `__source_hash.json` gains a `history` map. Only tables that keep the
  last delivery (`keep_latest_version`) have a history; `submissao`
  already lists every delivery. Reading the history from `cvm_fetch()`
  is a separate item.

* The filings superseded BEFORE the mirror kept a history are recovered
  from the CVM document archive (RAD) by a daily robot
  (`.github/workflows/etl-rad.yaml`, `inst/etl/04-rad-fetch.R`): every
  DFP/ITR delivery the `submissao` index lists that is not the current
  one is downloaded, read from its XML (`inst/etl/util-rad.R`, both
  layouts the RAD has used since 2010) into the eight statement tables
  with exactly the columns and conventions of the CSV, and appended to
  the same history assets with `history_source = "rad"`, the receipt date
  of the delivery that replaced it (`superseded_at`), its `id_doc` and the
  reason for restatement the document declares (`motivo_reapresentacao`).
  Rows written by the mirror path carry `history_source = "mirror"`. The
  reader was calibrated against 60 current filings of 2010-2025 read back
  from the mirror, account by account: values, accounts, periods and
  descriptions identical; `st_conta_fixa` differs in 30 rows of three
  2019 documents, because the CSV takes that flag from the chart of
  accounts in force when the file is generated; the history keeps the
  document's own flag, the one that held when the filing was delivered.
  Documents the
  robot cannot read are listed in the public asset `__rad_unread.csv` of
  each release. The first real run (2026-10-20, DFP 2025) set aside 8 of
  73 documents and stopped, as designed, over two defects of the reader,
  both fixed: the XML is parsed without libxml2's 10 MB text-node limit
  (the embedded PDF of five documents exceeded it, and libxml2 2.9
  refused the whole file as "Extra content at the end of the document"),
  and the DMPL columns of the flat variant follow the document's own
  order of elements rather than a fixed map (the converter only
  reorders the three-way split of consolidated equity: controlling,
  non-controlling, consolidated), so the equity columns of financial
  institutions, which differ between two filing templates
  (`AjustesAvaliacaoPatrimonial` before or after
  `LucroPrejuizoAcumulado`, `ReservasReavaliacao`, nine consolidated
  columns with the ninth unlabelled), come out as the CSV writes them:
  Banestes, Banco Pine, Daycoval, BTG Pactual and Itaú, DFP 2025,
  account by account, zero differences. The state now records which
  reader set a document aside, and attempts made by an earlier reader
  no longer spend the document.

* New contract test `test-schema-snapshot-consistency.R` pins the
  invariants between the hand-written schema YAMLs and the derived
  `cvm_dictionary_snapshot.csv`: every installed `(group, dataset,
  table)` has snapshot rows and vice versa, `expected_field_count`
  equals the snapshot's row count, `meta_status` agrees row by row,
  and the 8 META-less FRE tables declare exactly the field names the
  snapshot carries. Measured on 2026-09-17: 74 YAMLs, 74 tables in the
  snapshot, zero divergences. This retires the pre-v0.1 roadmap item
  "generate the remaining YAMLs from the dictionary snapshot": the
  dependency runs the other way (`data-raw/build-dictionary-snapshot.R`
  reads each YAML's `cvm_dictionary_url` to build the snapshot), so a
  generator would be circular, and there are no remaining YAMLs to
  generate. `data-raw/README.md` no longer lists the schema YAMLs as a
  built artefact.

# cvmdata 0.2.0 (2026-05-29)

## ⚠️ Breaking changes

* `cvm_fetch()` has been renamed `issuer_fetch()` to reflect the
  contract of CVM's company-issuer datasets (the v0.1 scope). The
  rename is mechanical:

      cvm_fetch(dataset, table, companies = ..., years = ..., ...)
      ↓
      issuer_fetch(dataset, table, issuer = ..., year = ..., ...)

  The arguments `companies` and `years` have been renamed to the
  singular `issuer` and `year` for tidyverse-canonical naming. The
  semantics are unchanged: `issuer` accepts a character vector of
  CNPJs / CD_CVMs / free-text identifiers; `year` accepts an integer
  vector of years and defaults to the latest available year when
  `NULL`. The renamed arguments still accept vectors of any length.

  `cvm_fetch()` is **removed without a deprecation wrapper**. Calls
  using the old name will fail with `could not find function "cvm_fetch"`.
  Likewise, passing the old argument names will abort with
  `cvmdata_error_input` and a hint suggesting the new names.

  Rationale: cvmdata has zero CRAN distribution and zero external
  users at v0.1.0; the breaking change is contained to a few
  collaborators who can update their scripts in one pass. The
  alternative (a soft-deprecated wrapper kept until v1.0) would
  carry the maintenance cost of a redundant code path through the
  entire v0.x cycle, with no external users to protect.

* `cad_fetch()` has been removed without replacement. Use
  `issuer_fetch("cad", "companhias")` instead — the call site is one
  character longer and removes a thin alias that was only retained
  for ergonomics during the Session 01 prototype.

* Four further fetchers (`fund_fetch()`, `agent_fetch()`,
  `offering_fetch()`, `event_fetch()`) will be exported as skeletons
  in the following development cycle. v0.1.0.9000 itself only ships
  `issuer_fetch()` as a functional fetcher.

## New features

* New dataset `cgvn` (Codigo Brasileiro de Governanca Corporativa)
  covered by `issuer_fetch()`. Two tables: `submissao` (12 fields,
  one row per ICBGC informe filed by a company per fiscal year) and
  `praticas` (11 fields, "pratique ou explique" detail with 54
  recommended practices per filing — `id_item`, `capitulo`,
  `principio`, `pratica_recomendada`, `pratica_adotada` ∈
  {Sim, Nao, Parcialmente, Nao se Aplica}, `explicacao`). CKAN
  coverage 2021+. `praticas` does not carry `codigo_cvm`; CD_CVM
  filtering routes through `cgvn/submissao` automatically. Embedded
  dictionary and codelist snapshots regenerated to include the new
  tables. Decision doc:
  `data-raw/decisions/cvmdata_v0-2_planejamento_decisao.md`.

* New dataset `vlmo` (Valores Mobiliarios Negociados e Detidos por
  insiders, art. 11 of CVM Resolution 44) covered by `issuer_fetch()`.
  Two tables: `submissao` (12 fields, one row per filing) and
  `consolidado` (17 fields, one row per security movement). Unlike the
  other detail tables, `consolidado` carries **no
  `keep_latest_version`** transformation: it is event-per-row, so every
  `versao` is retained verbatim (deduping by version would collapse
  distinct movements). Insider identity is **opaque by design of the
  CVM** — the detail has no CPF; only the category `tipo_cargo` and, for
  corporate insiders, a name in `empresa` plus `tipo_empresa`. The
  `issuer` argument therefore filters the **issuing company**, not the
  individual insider; a per-category filter is a trivial `dplyr` step on
  the returned tibble. `consolidado` does not carry `codigo_cvm`; CD_CVM
  filtering routes through `vlmo/submissao` automatically. The package
  table is named `consolidado` (not `con`, the CVM file token) because
  `con` is a reserved device name on Windows. Embedded dictionary and
  codelist snapshots regenerated to include the new tables. Decision
  doc: `data-raw/decisions/cvmdata_v0-2_planejamento_decisao.md`.

* New dataset `fca` (Formulario Cadastral) covered by `issuer_fetch()`,
  the largest v0.2 surface with **10 tables**: `submissao` (9 fields,
  classic convention identical to ITR/DFP/FRE — `cnpj_cia`, `dt_refer`,
  `cd_cvm`) plus 9 FRE-detail tables (`cnpj_companhia` /
  `data_referencia`): `auditor`, `canal_divulgacao`,
  `departamento_acionistas`, `dri`, `endereco`, `escriturador`,
  `geral`, `pais_estrangeiro_negociacao`, `valor_mobiliario`. The
  classic-vs-detail split means CD_CVM filtering of a detail routes
  through `fca/submissao` (which carries `cd_cvm` + `cnpj_cia`) and maps
  to the detail's `cnpj_companhia`. CKAN coverage 2021+.

  Note: `fca/departamento_acionistas` is published with a valid
  23-field header but **zero data rows from 2024 onward** (it carried
  data through 2023, then zeroed after a regulatory change). The reader
  returns the empty tibble without aborting; use `fca/endereco` or
  `fca/dri` for shareholder-department contact information.

* **B3 ticker support in `issuer = `**. The `issuer` argument now
  recognises B3 trading tickers (e.g. `"PETR4"`, `"BBDC11"`,
  `"ITSA4F"`) alongside CNPJ, CD_CVM and free text. A ticker is
  resolved to its issuer CNPJ via `fca/valor_mobiliario` (the
  `codigo_negociacao` column), analogous to the existing CD_CVM →
  CNPJ resolution via `submissao` — no external data source. Only
  active securities (empty/future `data_fim_negociacao`) are matched;
  the lookup table is cached per R session. Tickers cover only
  exchange-listed securities, so an unknown ticker aborts with
  `cvmdata_error_input` rather than failing silently. Embedded
  dictionary and codelist snapshots regenerated to include the FCA
  tables. Decision doc:
  `data-raw/decisions/cvmdata_v0-2_planejamento_decisao.md`.

* New dataset `ipe` (Informacoes Periodicas e Eventuais) covered by
  `issuer_fetch()`. A **single-table manifest** (`ipe`, 13 fields,
  ~50k documents/year) of every periodic and eventual document a
  company filed with the CVM: `cnpj_companhia`, `data_referencia`,
  `codigo_cvm`, `categoria`, `tipo`, `especie`, `assunto`,
  `data_entrega`, `tipo_apresentacao`, `protocolo_entrega`, `versao`
  and `link_download`. There is no separate `submissao` table — the
  CSV *is* the manifest. `codigo_cvm` is native, so CD_CVM filtering
  matches directly (no `submissao` bridge). The manifest is
  **event-per-row**: like `vlmo/consolidado` it declares **no
  `keep_latest_version`** transformation, so re-submissions and every
  `versao` of a document are retained verbatim. Slice by document
  class with a trivial `dplyr::filter()` on `categoria` on the
  returned tibble. `link_download` is returned as a plain URL to the
  document on the CVM portal; **OCR and PDF download are out of
  scope**. IPE overlaps VLMO on the "Valores Mobiliarios negociados e
  detidos" category — IPE *indexes* the document, VLMO carries the
  *structured* insider movements; see the `ipe-vlmo` article. CKAN
  coverage 2021+. Embedded dictionary and codelist snapshots
  regenerated to include the new table. Decision doc:
  `data-raw/decisions/cvmdata_v0-2_planejamento_decisao.md`.

* `cvm_groups()` lists the 18 CKAN groups published by the CVM Open
  Data Portal, with the number of datasets each group carries and the
  canonical `cvmdata` fetcher contract (`issuer`, `fund`, `agent`,
  `offering` or `event`) that covers it. The table is static (verified
  against `<https://dados.cvm.gov.br/group/>` on 2026-05-25) and serves
  as the navigation entry point for the universe of CVM data; only the
  `companhias` group is functionally implemented in v0.1.0.9000, but
  the remaining 17 rows document the planned coverage exposed via the
  four skeleton fetchers shipped in the previous development entry.

* `cvm_datasets()`, `cvm_tables()` and `cvm_dataset_years()` gained an
  optional `group` argument, completing the discovery surface started
  in the previous entry (`cvm_dictionary()` and `cvm_codelist()`
  already accepted it). When `group` is `NULL` (default) the functions
  preserve their v0.1 behaviour: `cvm_datasets()` returns every
  installed dataset across every group, `cvm_tables()` and
  `cvm_dataset_years()` resolve the group by uniqueness across the
  schema tree. When set, the functions restrict the result to that
  group; unknown groups abort with `cvmdata_error_input`. From v0.4
  onward, when datasets may collide between groups, calling
  `cvm_tables("foo")` without `group` aborts with
  `cvmdata_error_input_ambiguous`.

* Four new fetchers exported with skeleton implementation:
  `fund_fetch()` (fund datasets — `fundos-de-investimento`,
  `fundos-de-investimento-imobiliarios`, `fundos-estruturados`,
  full implementation arriving in v0.4-v0.6); `agent_fetch()`
  (registered agents across the eight `administradores`,
  `agentes-autonomos`, `agentes-fiduciarios`, `auditores`,
  `consultores-de-valores-mobiliarios`,
  `coordenadores-de-ofertas`, `participantes-intermediarios` and
  `investidores-nao-residentes` groups, v0.7);
  `offering_fetch()` (public offerings — `ofertas-publicas` and
  `plataformas-de-crowdfunding`, v0.7); and `event_fetch()`
  (sanctioning proceedings and declaratory acts —
  `atividade-sancionadora` and `atos-declaratorios`, v0.8).
  Calling any of these in v0.1.0.9000 aborts with the new
  condition class `cvmdata_error_input_group` and a message
  pointing to ROADMAP.md. Exporting the skeletons now locks the
  complete public API surface ahead of incremental data
  implementation, so later releases (v0.4+) extend coverage
  without reshaping the API.

* New condition class `cvmdata_error_input_group` (inherits from
  `cvmdata_error_input`, which in turn inherits from
  `cvmdata_error`). Emitted by the four new skeleton fetchers
  when called in v0.1.0.9000. Sibling of
  `cvmdata_error_input_ambiguous` (introduced in the previous
  development entry); neither subclass is a parent of the other.

* Parquet mirror became `<group>`-aware end-to-end. The
  GitHub-Releases producer (`inst/etl/0{1,2,2b,3}-*.R`) and the
  workflow `.github/workflows/etl-mirror.yaml` now take `--group`
  (matrix `(group, dataset)`), write to
  `<workspace>/out/parquet/<group>/<dataset>/...`, and publish to the
  moving release `mirror-<group>-<dataset>-latest`. The mirror
  consumer (`R/util-mirror-assets.R`, `R/source-mirror-duckdb.R`)
  reads the same naming convention; `mirror_release_tag()` and
  `mirror_list_assets()` gained a leading `group` argument. The
  session-scoped asset cache now keys on `(group, dataset)`.
  Operational note: the four pre-Sessao-08 GitHub Releases
  (`mirror-cad-latest`, ...) must be renamed in place via the GitHub
  API to `mirror-companhias-<dataset>-latest` before consumers on
  this code can read them; the rename is the operator's task and is
  intentionally not automated. Until that rename happens,
  `source = "mirror"` aborts with HTTP 404; users can fall back to
  `cvm_source_set("cvm")`.

* Returned tibbles (`cvm_tbl` class) now carry a `group` provenance
  attribute, slotted between `fetched_at` and `dataset`. The total
  number of attached attributes goes from five to six (`source`,
  `fetched_at`, `group`, `dataset`, `table`, `package_version`).
  `print.cvm_tbl()` renders `group` in the header alongside the
  existing fields, so a snapshot taken at the REPL self-documents
  which CKAN group the data came from. `load_schema()` stamps the
  resolved group onto the schema list so downstream callers
  propagate it without re-running the schema-tree lookup.

## Documentation

* New article `vignettes/articles/groups-overview.Rmd` lists the 18
  CKAN groups and maps each to one of the five fetcher contracts,
  with a worked example per fetcher (only `issuer_fetch()` runs;
  the four skeletons stay in `eval = FALSE` chunks until v0.4+).
  Linked from the pkgdown Articles navbar.

* Article `cvm-defects.Rmd` renamed to `data-defects.Rmd`. The
  taxonomy of publication quirks covers any upstream source the
  package will integrate (the universe widens beyond CVM proper
  from v0.4+); the new name reflects that scope. URL on the pkgdown
  site moves from `/articles/cvm-defects.html` to
  `/articles/data-defects.html`. No content change.

* `_pkgdown.yml`: `cvm_groups` listed first in the Discovery
  reference; the section description now points users at it as the
  entry to the group taxonomy.

## Internal

* Reader identifier classification refactored from an ad-hoc regex
  list (`R/util-csv-cvm.R:.identifier_patterns`) to a prefix-based
  helper (`identifier_columns()`) with two lists: `.identifier_prefixes`
  (`^cnpj`, `^cpf`, `^codigo_`, `^cd_cvm`, `^cep`, `^ddi_`, `^ddd_`,
  `^id_`, `^protocolo`) and `.identifier_exact` (`caixa_postal`,
  `tel`, `versao`). Covers v0.1 without regression and absorbs the
  v0.2 identifier columns (`codigo_cvm_auditor`, `cnpj_escriturador`,
  `cpf_responsavel`, `id_item`, `ddi_telefone`, `protocolo_entrega`,
  `codigo_negociacao`) without per-dataset additions.
* `tx_keep_latest_version()` (transform-schema) now accepts an extra
  `keys: [...]` field in the YAML transformation declaration. Used
  by `cgvn/praticas` to dedup on `(cnpj_companhia, data_referencia,
  id_item)` so the 54 distinct practices per filing all survive.
* New internal helper `cdcvm_col(df)` resolves the CVM-code column
  to either `cd_cvm` (CAD/ITR/DFP/FRE submissao) or `codigo_cvm`
  (CGVN/VLMO/IPE submissao). Applied by `match_by_cd_cvm()` and
  `resolve_cd_cvm_via_submissao()` so the CD_CVM lookup path works
  for both naming conventions.
* Codelist builder (`data-raw/build-codelists-snapshot.R`) exclude
  pattern list re-aligned with the reader's identifier rules
  (broader `^codigo_` and `^id_` instead of the v0.1 narrow exact
  matches; added `^ddi_` and `^protocolo`). Mirrors the reader
  refactor so new identifier-shaped columns in v0.2 datasets are
  not falsely promoted to codelists.

* Cache layout migrated from `<cache>/{raw,parquet}/<dataset>/` to
  `<cache>/{raw,parquet}/<group>/<dataset>/`. The `<group>` segment
  is the CVM CKAN group slug (`companhias` for the four v0.1
  datasets); this clears the path for v0.2+ datasets that live under
  other groups (`fundos-de-investimento`, etc.) without colliding
  dataset slugs. A one-time internal helper
  (`cache_migrate_v0_1_to_v0_2()`, not exported) runs automatically
  on first invocation of `cvm_fetch()`, `cvm_cache_info()` or
  `cvm_cache_clear()` post-upgrade and relocates pre-existing
  artifacts; the helper is idempotent and writes an audit log under
  `tools::R_user_dir("cvmdata", "config")/cache_migrate_log.rds`.
* `cvm_cache_info()` now exposes the `group` column as the first
  key, ahead of `dataset`.
* `cvm_cache_clear()` gained a `group` argument that scopes deletion
  to a CKAN group (e.g. `cvm_cache_clear(group = "companhias")`).
  Precedence: `what = "all"` overrides the filter; otherwise the
  target path is composed as
  `<cache>/<what>/<group>/<dataset>/<year>/`, with each segment
  becoming optional from the right.
* Schema YAML files moved from
  `inst/extdata/schemas/<dataset>/<table>.yaml` to
  `inst/extdata/schemas/<group>/<dataset>/<table>.yaml`. The internal
  loader `load_schema()` gained an optional `group` argument; when
  omitted (the v0.1.0.9000 path) it resolves by uniqueness across the
  installed schema tree, so existing calls compile unchanged. The
  constant `.dataset_group_map` shipped by the previous release as
  technical debt has been removed -- `dataset_group()`, `known_groups()`
  and the new `known_datasets()` now walk the installed schema tree on
  first call and memoize the result per R session.
* `cvm_dictionary_snapshot.csv` and `cvm_codelists_snapshot.csv` gained
  a `group` column as the first key column. Composite key changed from
  `(dataset, table, ...)` to `(group, dataset, table, ...)`. The
  bundled CSVs were regenerated against the live CVM portal; aside
  from the new column, the dictionary snapshot is byte-identical to
  the previous build and the codelists snapshot reflects organic
  drift in a handful of FRE categorical columns.
* `cvm_dictionary()` and `cvm_codelist()` gained an optional `group`
  argument. When omitted, both functions resolve by uniqueness across
  the embedded snapshot; from v0.4 onward, datasets present in more
  than one group will abort with `cvmdata_error_input_ambiguous`
  (a new condition class that inherits from `cvmdata_error_input`).
* New condition class `cvmdata_error_input_ambiguous` (inherits from
  `cvmdata_error_input`, which in turn inherits from `cvmdata_error`).
  Emitted by `load_schema()`, `dataset_group()`, `cvm_dictionary()`
  and `cvm_codelist()` when a `(dataset, table)` resolution returns
  more than one candidate group and the caller did not supply `group`
  to disambiguate.

## Bug fixes

* `cvm_fetch()` and `cad_fetch()` no longer fail with the cryptic
  `cvmdata_error_internal` "Got archive=, file=" when the R session
  runs under `LC_CTYPE = "C"`. The schema loader now reads the bundled
  YAMLs forcing UTF-8 instead of relying on the active locale, so
  multibyte characters in the schema comment headers (e.g.
  "Demonstração", "Exercício") never cause `yaml::read_yaml()` to
  return `NULL`. A regression test under `LC_CTYPE = "C"` was added.
* The PDF version of the package manual now builds cleanly on the
  macOS R builder with the default pdflatex `inputenc` setup; a stray
  U+2264 ("less than or equal to") character in the roxygen docs of
  `cvm_codelist()` has been replaced by ASCII.

# cvmdata 0.1.0 (2026-05-24)

First public release. Covers the four core CVM publicly-traded-company
datasets — CAD (registry), DFP (annual statements), ITR (quarterly
statements) and FRE (reference form) — with a tidy `cvm_fetch()` API,
year-partitioned mirror in GitHub Releases (refreshed weekly), and an
HTTP-with-cache backend against `dados.cvm.gov.br` for byte-level
freshness.

## Breaking changes

* The default `source` of `cvm_fetch()` is now `"mirror"` (parquet via
  DuckDB), not `"cvm"` (CVM Open Data Portal). Scripts that need
  byte-level freshness from the regulator should pass `source = "cvm"`
  explicitly or persist the choice with `cvm_source_set("cvm")`. The
  `"cvm"` backend remains fully supported.

## ETL and mirror

* New stage `inst/etl/02b-validate.R` runs between csv-to-parquet
  generation and the GitHub Releases publish. Applies a hybrid set of
  `pointblank` checks: structural failures (missing parquet,
  unreadable file, `n_rows == 0`, wrong identifier type) exit 1 and
  block the publish; content failures (CNPJ format, `cd_cvm` regex,
  date range) emit a warning and let the publish proceed. The
  validation markdown report is uploaded as a workflow artifact for
  post-hoc inspection regardless of outcome.
* `arrow` and `pointblank` join the `Suggests` field — both are
  consumed only by the ETL scripts.

## Documentation

* New article `cache-and-mirror.Rmd` (CRAN-safe via bundled RDS)
  documents the dual-backend contract, the L1 / L3 cache layout, the
  four common workflows (mirror switch, CVM vs Mirror equivalence,
  cache inspection, TTL + LRU tuning) and the eight pre-publish
  checks the mirror ETL runs. Linked from `README.Rmd` and the
  pkgdown navbar.

# cvmdata 0.0.0.9000

* Initial scaffolding.
* First implementation: `cad_fetch()` for the CAD registry.
* Exported utility: `cnpj_clean()` for stripping punctuation from CNPJ
  vectors.
* Add ITR (quarterly financial statements) coverage: 11 schemas
  mirroring DFP.
* `companies` arg accepts CD_CVM on every table of a dataset, even
  those that don't carry `cd_cvm` natively (e.g. `composicao_capital`,
  `parecer`): the CD_CVM is resolved to CNPJ via the dataset's
  `submissao` table for the same year. Previously the filter silently
  returned an empty tibble for these tables.
* Add FRE (annual reference form) coverage: 36 schemas including 8 with
  `meta_status: missing` (administrador_PCD, empregado_PCD, and six
  empregado tables that the CVM does not publish a META for); first
  dataset exercising the missing-META reader policy against real data.
* `companies` arg now also filters FRE-detail tables, which use a
  different header convention from CAD/ITR/DFP: `cnpj_companhia`,
  `data_referencia`, `nome_companhia` (no `cd_cvm`). `match_by_cnpj()`,
  `match_by_text()`, `disambiguate_text_match()` and
  `tx_keep_latest_version()` accept either column pair; existing
  CAD/ITR/DFP behaviour is unchanged.
* Public cache API: `cvm_cache_path()`, `cvm_cache_set_path()`,
  `cvm_cache_info()` and `cvm_cache_clear()`. The internal source
  backend now consumes `cvm_cache_path()` as the single source of
  truth for the cache root. `cvm_cache_info()` lists every artifact
  under `<cache>/raw/` (upstream CSV/ZIP plus CSVs extracted from
  yearly ZIPs) with ETag/Last-Modified metadata sourced from
  `*.etag.rds` sidecars when present. `cvm_cache_clear()` accepts
  `what ∈ c("all", "raw")` plus optional `dataset` and `year`
  filters; in interactive sessions it asks for confirmation via
  `utils::askYesNo()`.
* Public source API: `cvm_source_get()` and `cvm_source_set()`.
  `cvm_source_get()` reads `getOption("cvmdata.source", "cvm")`;
  `cvm_source_set()` validates the value against
  `c("cvm", "mirror")` and persists it. `cvm_fetch()` now declares
  `source = NULL` and resolves the default via `cvm_source_get()`,
  so precedence is arg > option > built-in default. The built-in
  default is `"cvm"` in the v0.1 series and transitions to
  `"mirror"` in the release that ships the Phase F mirror; this
  flip will be announced in NEWS.md of that release. Until then,
  passing `source = "mirror"` aborts with
  `cvmdata_error_internal` (in-domain value, not yet implemented).
