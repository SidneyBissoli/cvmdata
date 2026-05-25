# cvmdata 0.1.0.9000 (in development)

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
  carry maintenance cost and confuse reviewers during the upcoming
  rOpenSci submission.

* `cad_fetch()` has been removed without replacement. Use
  `issuer_fetch("cad", "companhias")` instead — the call site is one
  character longer and removes a thin alias that was only retained
  for ergonomics during the Session 01 prototype.

* Four further fetchers (`fund_fetch()`, `agent_fetch()`,
  `offering_fetch()`, `event_fetch()`) will be exported as skeletons
  in the following development cycle. v0.1.0.9000 itself only ships
  `issuer_fetch()` as a functional fetcher.

## Internal

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
