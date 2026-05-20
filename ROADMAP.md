# ROADMAP — `cvmdata`

Plano de execução organizado por fases (não por datas). Rastreia o
progresso sessão a sessão.

- [x] = entregue
- [~] = em andamento
- [ ] = pendente

---

## Pré-v0.1 (companhias abertas — Resolução CVM 80/22)

### Fase A — Esqueleto (8-12h)

- [~] Inicialização do pacote (`DESCRIPTION`, `NAMESPACE`, `LICENSE`).
- [~] Estrutura de diretórios (`R/` flat com prefixos hífen;
  `tests/testthat/`, `inst/extdata/`, `data-raw/`, `vignettes/`,
  `pkgdown/`, `.github/workflows/`).
- [~] `NEWS.md` inicial.
- [~] `README.Rmd` com badges placeholder.
- [~] `CLAUDE.md` e `ROADMAP.md`.
- [~] Workflow `R-CMD-check.yaml`.
- [ ] `.lintr` config travada.
- [ ] Workflow `test-coverage.yaml`.
- [ ] Workflow `lint.yaml`.
- [ ] Workflow `pkgdown.yaml`.
- [ ] `pkgdown/_pkgdown.yml` configurado.
- [ ] `CODE_OF_CONDUCT.md` e `CONTRIBUTING.md`.

### Fase B — Cache + source CVM (16-20h)

- [ ] `cvm_cache_path()`, `cvm_cache_set_path()`, `cvm_cache_info()`,
  `cvm_cache_clear()`.
- [ ] L1 (ZIP raw) + L3 (Parquet) + L4 (`cachem::cache_mem()`).
- [ ] Invalidação por ETag/Last-Modified + TTL.
- [ ] LRU eviction quando atinge 90% do limite.
- [ ] `source_cvm_http_get()` para CSV direto e ZIP-then-extract.
- [ ] `cvm_source_get()` / `cvm_source_set()`.
- [ ] Testes mockados via `httptest2`.

### Fase C — Dispatch + schemas (24-32h)

- [ ] `load_schema(dataset, table)` parser do YAML com validações
  (mutual exclusion de URLs; `meta_status: missing` exige
  `expected_field_names`).
- [ ] `dispatch_class(dataset)` (companies → futures funds).
- [ ] `dispatch_table(dataset, table)`.
- [ ] YAMLs para CAD/companhias (já existe em `schemas_proto/`).
- [ ] YAMLs para ITR (19 tabelas: `bpa_con`/`bpa_ind`/.../`submissao`).
- [ ] YAMLs para DFP (mesmo set que ITR).
- [ ] YAMLs para FRE (36 tabelas incluindo `submissao` + 8 com
  `meta_status: missing`).
- [ ] Geração programática dos YAMLs restantes a partir do snapshot
  de dicionário.

### Fase D — CAD + ITR ponta-a-ponta (20-28h)

- [~] **Sessão 1**: `cad_fetch()` ponta-a-ponta (alias mais simples).
  - [ ] YAML CAD em `inst/extdata/schemas/cad/companhias.yaml`.
  - [ ] `load_schema()` mínimo.
  - [ ] `source_cvm_http_get()` para CSV direto (sem ZIP).
  - [ ] `read_cvm_csv()` com regra de identificadores → character.
  - [ ] `transform_cad()`.
  - [ ] `cvm_fetch_internal()` (orquestrador não-exportado).
  - [ ] `cad_fetch()` API pública.
  - [ ] `cvm_attach_metadata()` + classe `cvm_tbl`.
  - [ ] `print.cvm_tbl()`.
  - [ ] Hierarquia `cvmdata_error_*` / `cvmdata_warn_*`.
  - [ ] Testes mockados (httptest2) + fixture CAD.
  - [ ] Doc roxygen completa.
  - [ ] Vignette stub `cvmdata.Rmd`.
- [ ] **Sessão 2 (provável)**: `itr_fetch()` + pipeline ZIP-based +
  `cvm_fetch()` genérico.
- [ ] Cobertura ≥85%.

### Fase E — DFP + FRE (40-60h)

- [ ] `dfp_fetch()` reutilizando pipeline ITR.
- [ ] `fre_fetch()` (35 tabelas detail + `submissao`).
- [ ] Política do reader para 8 tabelas FRE sem META (Rodada 3.0.2).
- [ ] Vignette `itr-dfp.Rmd`.
- [ ] Vignette `fre.Rmd`.

### Fase F — Pipeline ETL + mirror (24-32h)

- [ ] Scripts `inst/etl/01-07.R`.
- [ ] Workflow `etl-mirror.yaml` (cron `0 7 * * 2`).
- [ ] Detecção de mudança via hash de `meta_*.txt` +
  `dictionary_entry_inventory.json`.
- [ ] Validação pre-publish com pointblank.
- [ ] Primeiro snapshot publicado em GitHub Releases.
- [ ] `source_mirror_duckdb.R` integrado ao dispatch.

### Marco — release v0.1.0

- [ ] R-CMD-check verde nos 5 jobs (Ubuntu devel/release/oldrel-1,
  macOS release, Windows release).
- [ ] Cobertura ≥90%.
- [ ] `revdepcheck::revdep_check()` limpo.
- [ ] `devtools::check_win_devel()` e `check_mac_release()` limpos.
- [ ] ≥30 dias de ETL rodando estável.
- [ ] Submissão rOpenSci (<https://github.com/ropensci/software-review>).
- [ ] Aceitação rOpenSci.
- [ ] Submissão CRAN (feita pelo rOpenSci).

---

## v0.2+ (escopo futuro, fora da Sessão 1)

- [ ] **v0.2**: `fca`, `vlmo`, `cgvn`, `ipe` (companhias parte 2).
- [ ] **v0.3**: eventos societários + estrangeiras + incentivadas.
- [ ] **v0.4**: ICVM 555 (fundos de investimento — primeira classe não-companhia).
- [ ] **v0.5**: FII (fundos imobiliários).
- [ ] **v0.6**: FIDC + estruturados.
- [ ] **v1.0**: estabilização + paper no The R Journal.

---

## Pendências documentais

- [ ] Aplicar refinamentos da Rodada 3.0.2 ao naming doc v03 → v04
  (subsessão dedicada de edição).
- [ ] Aplicar refinamentos da Rodada 3.0 ao naming doc (parcialmente
  feito na v03).
- [ ] Acrescentar `cran-comments.md` quando aparecer a primeira NOTE
  inevitável.
