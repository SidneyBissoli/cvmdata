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
