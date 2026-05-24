# Changelog

## cvmdata 0.1.0 (2026-05-24)

First public release. Covers the four core CVM publicly-traded-company
datasets — CAD (registry), DFP (annual statements), ITR (quarterly
statements) and FRE (reference form) — with a tidy
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
API, year-partitioned mirror in GitHub Releases (refreshed weekly), and
an HTTP-with-cache backend against `dados.cvm.gov.br` for byte-level
freshness.

### Breaking changes

- The default `source` of
  [`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
  is now `"mirror"` (parquet via DuckDB), not `"cvm"` (CVM Open Data
  Portal). Scripts that need byte-level freshness from the regulator
  should pass `source = "cvm"` explicitly or persist the choice with
  `cvm_source_set("cvm")`. The `"cvm"` backend remains fully supported.

### ETL and mirror

- New stage `inst/etl/02b-validate.R` runs between csv-to-parquet
  generation and the GitHub Releases publish. Applies a hybrid set of
  `pointblank` checks: structural failures (missing parquet, unreadable
  file, `n_rows == 0`, wrong identifier type) exit 1 and block the
  publish; content failures (CNPJ format, `cd_cvm` regex, date range)
  emit a warning and let the publish proceed. The validation markdown
  report is uploaded as a workflow artifact for post-hoc inspection
  regardless of outcome.
- `arrow` and `pointblank` join the `Suggests` field — both are consumed
  only by the ETL scripts.

### Documentation

- New article `cache-and-mirror.Rmd` (CRAN-safe via bundled RDS)
  documents the dual-backend contract, the L1 / L3 cache layout, the
  four common workflows (mirror switch, CVM vs Mirror equivalence, cache
  inspection, TTL + LRU tuning) and the eight pre-publish checks the
  mirror ETL runs. Linked from `README.Rmd` and the pkgdown navbar.

## cvmdata 0.0.0.9000

- Initial scaffolding.
- First implementation:
  [`cad_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cad_fetch.md)
  for the CAD registry.
- Exported utility:
  [`cnpj_clean()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_clean.md)
  for stripping punctuation from CNPJ vectors.
- Add ITR (quarterly financial statements) coverage: 11 schemas
  mirroring DFP.
- `companies` arg accepts CD_CVM on every table of a dataset, even those
  that don’t carry `cd_cvm` natively (e.g. `composicao_capital`,
  `parecer`): the CD_CVM is resolved to CNPJ via the dataset’s
  `submissao` table for the same year. Previously the filter silently
  returned an empty tibble for these tables.
- Add FRE (annual reference form) coverage: 36 schemas including 8 with
  `meta_status: missing` (administrador_PCD, empregado_PCD, and six
  empregado tables that the CVM does not publish a META for); first
  dataset exercising the missing-META reader policy against real data.
- `companies` arg now also filters FRE-detail tables, which use a
  different header convention from CAD/ITR/DFP: `cnpj_companhia`,
  `data_referencia`, `nome_companhia` (no `cd_cvm`). `match_by_cnpj()`,
  `match_by_text()`, `disambiguate_text_match()` and
  `tx_keep_latest_version()` accept either column pair; existing
  CAD/ITR/DFP behaviour is unchanged.
- Public cache API:
  [`cvm_cache_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_path.md),
  [`cvm_cache_set_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_set_path.md),
  [`cvm_cache_info()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_info.md)
  and
  [`cvm_cache_clear()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_clear.md).
  The internal source backend now consumes
  [`cvm_cache_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_path.md)
  as the single source of truth for the cache root.
  [`cvm_cache_info()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_info.md)
  lists every artifact under `<cache>/raw/` (upstream CSV/ZIP plus CSVs
  extracted from yearly ZIPs) with ETag/Last-Modified metadata sourced
  from `*.etag.rds` sidecars when present.
  [`cvm_cache_clear()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_clear.md)
  accepts `what ∈ c("all", "raw")` plus optional `dataset` and `year`
  filters; in interactive sessions it asks for confirmation via
  [`utils::askYesNo()`](https://rdrr.io/r/utils/askYesNo.html).
- Public source API:
  [`cvm_source_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_get.md)
  and
  [`cvm_source_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_set.md).
  [`cvm_source_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_get.md)
  reads `getOption("cvmdata.source", "cvm")`;
  [`cvm_source_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_set.md)
  validates the value against `c("cvm", "mirror")` and persists it.
  [`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
  now declares `source = NULL` and resolves the default via
  [`cvm_source_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_get.md),
  so precedence is arg \> option \> built-in default. The built-in
  default is `"cvm"` in the v0.1 series and transitions to `"mirror"` in
  the release that ships the Phase F mirror; this flip will be announced
  in NEWS.md of that release. Until then, passing `source = "mirror"`
  aborts with `cvmdata_error_internal` (in-domain value, not yet
  implemented).
