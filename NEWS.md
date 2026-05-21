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
