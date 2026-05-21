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
