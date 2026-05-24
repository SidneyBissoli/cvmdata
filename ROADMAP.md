# ROADMAP — `cvmdata`

Plano de execução por fases. 

- [x] = entregue
- [~] = parcial / em andamento
- [ ] = pendente
- [-] = descartado

---

## Pré-v0.1 - companhias abertas

### Fase A — Esqueleto

- [x] Inicialização do pacote (`DESCRIPTION`, `NAMESPACE`, `LICENSE`,
  `LICENSE.md`).
- [x] Estrutura de diretórios (`R/` flat com prefixos hífen;
  `tests/testthat/`, `inst/extdata/schemas/`, `data-raw/`,
  `vignettes/`, `.github/workflows/`).
- [x] `NEWS.md` inicial.
- [x] `README.Rmd` + `README.md` com badges.
- [x] `README.pt-BR.Rmd` + `README.pt-BR.md`.
- [x] `CLAUDE.md` e `ROADMAP.md`.
- [x] `.lintr` config travada (linha 80, snake_case, cyclocomp ≤ 20).
- [x] `.Rbuildignore` e `.gitignore`.
- [x] Workflow `R-CMD-check.yaml` (matriz macOS release / Windows
  release / Ubuntu devel-release-oldrel1).
- [x] Workflow `test-coverage.yaml`.
- [x] Workflow `lint.yaml`.
- [x] Workflow `pkgdown.yaml` + `pkgdown/_pkgdown.yml`.
- [x] `CODE_OF_CONDUCT.md` e `CONTRIBUTING.md`.

### Fase B — Cache + source CVM

- [x] Família cache pública (`cvm_cache_path()`,
  `cvm_cache_set_path()`, `cvm_cache_info()`, `cvm_cache_clear()`).
- [x] Cache L1 (raw) para CSV direto e ZIP yearly.
- [x] Invalidação por ETag/Last-Modified com TTL configurável.
- [x] Limite de tamanho + eviction LRU.
- [x] `source_cvm_http_get()` para CSV direto e ZIP yearly.
- [x] `cvm_source_get()` / `cvm_source_set()`.
- [x] Suite de testes mockados de HTTP.

### Fase C — Dispatch + schemas

- [x] `load_schema(dataset, table)` com validações.
- [-] `dispatch_class(dataset)` — pipeline genérico + YAML por
  tabela tornou desnecessário.
- [-] `dispatch_table(dataset, table)` — idem.
- [x] YAML CAD/companhias.
- [x] YAMLs DFP (11 tabelas).
- [x] YAMLs ITR (11 tabelas).
- [x] YAMLs FRE (36 tabelas, 8 com `meta_status: missing`).
- [ ] Geração programática dos YAMLs restantes a partir do snapshot
  de dicionário.
- [x] `cvm_dictionary_snapshot.csv` + gerador em `data-raw/`.
- [x] `cvm_codelists_snapshot.csv` + gerador em `data-raw/`.

### Fase D — Datasets ponta-a-ponta

- [x] `cad_fetch()` ponta-a-ponta.
- [x] `cvm_fetch(dataset, table, ...)` como API principal.
- [x] Pipeline ZIP-yearly em `source_cvm_http_get()`.
- [x] `cvm_datasets()` e `cvm_tables(dataset)`.
- [x] `cvm_dataset_years(dataset)`.
- [x] Default `years = NULL` → último ano disponível, com fallback
  descendente quando companhia ausente no max year.
- [x] Argumento `report_type ∈ c("ind", "con")`.
- [x] Argumento `companies` com detecção automática
  (CNPJ / CD_CVM / busca textual).
- [x] Argumento `source ∈ c("mirror", "cvm")`.
- [x] DFP ponta-a-ponta.
- [x] ITR ponta-a-ponta.
- [x] FRE ponta-a-ponta (header detail com `cnpj_companhia` /
  `data_referencia`, sem `cd_cvm`).
- [x] Lookup automático CD_CVM → CNPJ via `submissao` para tabelas
  sem `cd_cvm` nativo.
- [x] `apply_schema_transformations()` genérico
  (`multiply_by_scale`, `drop`, `keep_latest_version`).
- [x] Conversão automática de datas via dicionário
  (`tipo_dados = "date"`).
- [x] Semântica diferenciada para `on_error = "warn"`/`"silent"`.

### Fase E — Polimento e cobertura

- [-] `dfp_fetch()` / `itr_fetch()` / `fre_fetch()` — `cvm_fetch()`
  cobre tudo.
- [x] Política do reader em três modos (`strict`/`warn`/`skip`)
  para tabelas com e sem META.
- [x] `cvm_dictionary(dataset, table)`.
- [x] `cvm_codelist(dataset, table, column)`.
- [x] Prompt interativo de seleção de companhias com múltiplas
  matches.
- [x] `cnpj_format()`.
- [x] Cobertura ≥90%.
- [x] Vignette `cvmdata.Rmd` (intro CRAN-safe).
- [x] Article `cvm-fetch.Rmd`.
- [x] Article `itr-dfp.Rmd`.
- [x] Article `fre.Rmd`.
- [x] Article `cvm-defects.Rmd`.
- [x] Article `cache-and-mirror.Rmd`.

### Fase F — Pipeline ETL + mirror

- [x] Scripts ETL em `inst/etl/` (`00-config.R`, `01-fetch-cvm.R`,
  `02-csv-to-parquet.R`, `02b-validate.R`, `03-publish.R`).
- [x] Workflow `etl-mirror.yaml` (`workflow_dispatch` + cron semanal,
  matrix de 4 datasets).
- [x] Detecção de mudança via hash SHA-256.
- [x] Primeiro bulk publish do v0.1 (cad + dfp + itr + fre).
- [x] Backend mirror funcional (`source = "mirror"`): inventário
  GitHub Releases + DuckDB local + filter pushdown por nome de
  asset.
- [x] Cache L3 (parquet local) com invalidação por hash.
- [x] `cvm_cache_clear(what = "parquet")`.
- [x] Validação pre-publish via `pointblank` (`02b-validate.R`).
- [-] Snapshots datados imutáveis do mirror — adiados para releases
  manuais do pacote, não para o cron.

### Marco — release v0.1.0

- [x] Flip do default de `source` para `"mirror"`.
- [x] Bump `DESCRIPTION` para `0.1.0`.
- [x] `cran-comments.md`.
- [x] `inst/CITATION`.
- [x] Tag git `v0.1.0` + GitHub release.
- [x] Reabrir ciclo de dev `0.1.0.9000`.
- [x] `devtools::check_win_devel()` enviado.
- [~] `devtools::check_mac_release()` — pendente (504 transitório,
  retentar).
- [ ] Submissão rOpenSci (pre-submission inquiry).
- [ ] Aceitação rOpenSci.
- [ ] Submissão CRAN (feita pelo rOpenSci em nome do mantenedor).

---

## v0.2+ (escopo futuro)

- [ ] **v0.2**: `fca`, `vlmo`, `cgvn`, `ipe` (companhias parte 2).
  - [ ] Suporte a ticker B3 no argumento `companies`.
- [ ] **v0.3**: eventos societários + estrangeiras + incentivadas.
- [ ] **v0.4**: ICVM 555 (fundos de investimento).
- [ ] **v0.5**: FII (fundos imobiliários).
- [ ] **v0.6**: FIDC + estruturados.
- [ ] **v1.0**: estabilização + paper no The R Journal.

---

## Pendências documentais

- [x] Nota corretiva sobre `R/` flat no canônico.
- [x] `inst/extdata/schemas/cad/companhias.yaml` com
  `expected_field_count: 47`.
- [ ] Refinamentos da Rodada 3.0.2 ao naming doc v04.
- [ ] Refinamentos da Rodada 3.0 ao naming doc.
- [x] `cran-comments.md`.
- [ ] `schemas_proto/cad/companhias.yaml` — atualizar ou marcar
  como histórico congelado.
