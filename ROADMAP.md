# ROADMAP — `cvmdata`

Plano de execução organizado por fases (não por datas). Rastreia o
progresso sessão a sessão.

- [x] = entregue
- [~] = parcial / em andamento
- [ ] = pendente
- [-] = descartado (anotado para preservar histórico da decisão)

---

## Pré-v0.1 (companhias abertas — Resolução CVM 80/22)

### Fase A — Esqueleto (8-12h)

- [x] Inicialização do pacote (`DESCRIPTION`, `NAMESPACE`, `LICENSE`,
  `LICENSE.md`).
- [x] Estrutura de diretórios (`R/` flat com prefixos hífen;
  `tests/testthat/`, `inst/extdata/schemas/cad/`, `data-raw/`,
  `vignettes/`, `.github/workflows/`).
- [x] `NEWS.md` inicial (formato `# cvmdata 0.0.0.9000`).
- [x] `README.Rmd` com badges + `README.md` renderizado.
- [x] `CLAUDE.md` (contexto persistente) e `ROADMAP.md` (este arquivo).
- [x] Workflow `R-CMD-check.yaml` (matriz r-lib check-standard: macOS
  release / Windows release / Ubuntu devel-release-oldrel1).
- [x] `.lintr` config travada (linha 80, snake_case, cyclocomp ≤ 20).
- [x] `.Rbuildignore` e `.gitignore` (incluindo `.claude/` e `memory/`).
- [ ] Workflow `test-coverage.yaml`.
- [ ] Workflow `lint.yaml`.
- [ ] Workflow `pkgdown.yaml`.
- [ ] `pkgdown/_pkgdown.yml` configurado.
- [ ] `CODE_OF_CONDUCT.md` e `CONTRIBUTING.md`.

### Fase B — Cache + source CVM (16-20h)

- [ ] `cvm_cache_path()`, `cvm_cache_set_path()`, `cvm_cache_info()`,
  `cvm_cache_clear()` (família pública).
- [~] L1 (raw) implementado para CSV direto (Sessão 01) e para ZIP
  (Sessão 02, em `<cache>/raw/<dataset>/<year>/`). Falta L3 (Parquet,
  Fase F) e L4 (`cachem::cache_mem()`).
- [~] Invalidação por ETag/Last-Modified implementada (sidecar RDS),
  estendida para ZIPs anuais na Sessão 02. TTL ainda não imposto.
- [ ] Limite de tamanho via `options(cvmdata.cache_max_size_mb)` e
  eviction LRU quando atinge 90%.
- [x] `source_cvm_http_get()` para CSV direto (Sessão 01) e ZIP-yearly
  (Sessão 02, com extração do CSV alvo via `report_type`).
- [ ] `cvm_source_get()` / `cvm_source_set()`.
- [x] Suite de testes mockados de HTTP via
  `httr2::with_mocked_responses` (com `httptest2` em Suggests
  para uso futuro).

### Fase C — Dispatch + schemas (24-32h)

- [x] `load_schema(dataset, table)` parser do YAML com validações
  (mutual exclusion de URLs e de `cvm_file_pattern` vs
  `cvm_file_pattern_variants`; `meta_status: missing` exige
  `expected_field_names`; `temporal_partitioning ∈ {none, yearly}`
  com `first_year` obrigatório quando yearly; chaves de variants
  restritas a `ind`/`con`).
- [-] `dispatch_class(dataset)` (companies → futures funds) — descartado.
  Pipeline genérico em `cvm_fetch_internal()` + schema YAML por tabela
  torna o dispatch desnecessário; quando fundos entrarem, basta novo
  dataset id e novos YAMLs.
- [-] `dispatch_table(dataset, table)` — descartado pelo mesmo motivo.
  Sessão 02 substituiu o `switch()` por `apply_schema_transformations()`
  dirigido pelo YAML.
- [x] YAML para CAD/companhias em `inst/extdata/schemas/cad/`
  (`expected_field_count` corrigido para 47 vs protótipo 46;
  `transformations: []` explicitado na Sessão 02).
- [x] YAMLs para DFP (11 tabelas conceituais, Sessão 02:
  `submissao`, `bpa`, `bpp`, `dre`, `dra`, `dfc_md`, `dfc_mi`,
  `dmpl`, `dva`, `composicao_capital`, `parecer`). As 8 com variantes
  ind/con usam `cvm_file_pattern_variants`.
- [ ] YAMLs para ITR (mesmo set que DFP — pipeline reusa
  `cvm_file_pattern_variants`).
- [ ] YAMLs para FRE (36 tabelas incluindo `submissao` + 8 com
  `meta_status: missing`).
- [ ] Geração programática dos YAMLs restantes a partir do snapshot
  de dicionário.
- [ ] Snapshot de dicionário `cvm_dictionary_snapshot.csv` em
  `inst/extdata/` (substitui heurística de Date atual em
  `read_cvm_csv()` pela regra canônica `tipo_dados = "date"`).
- [ ] Snapshot de codelists `cvm_codelists_snapshot.csv`.

### Fase D — CAD + ITR ponta-a-ponta (20-28h)

- [x] **Sessão 01**: `cad_fetch()` ponta-a-ponta — concluída.
  - [x] YAML CAD em `inst/extdata/schemas/cad/companhias.yaml`.
  - [x] `load_schema()` mínimo.
  - [x] `source_cvm_http_get()` para CSV direto (sem ZIP).
  - [x] `read_cvm_csv()` com regra de identificadores → character
    e heurística de Date interim (`dt_*`/`data_*`).
  - [x] `transform_cad()` (tolower colnames).
  - [x] `cvm_fetch_internal()` orquestrador não-exportado.
  - [x] `cad_fetch()` API pública.
  - [x] `cvm_attach_metadata()` + classe `cvm_tbl`.
  - [x] `print.cvm_tbl()`.
  - [x] Hierarquia `cvmdata_error_*` / `cvmdata_warn_*` via
    `cvmdata_abort()`/`cvmdata_warn()`.
  - [x] `cnpj_clean()` exportada (utilitária do naming doc §1.6).
  - [x] Testes mockados via `httr2::with_mocked_responses` +
    fixture `cad_sample.csv` (51 linhas reais).
  - [x] Doc roxygen completa para `cad_fetch()` e `cnpj_clean()`.
  - [x] Vignette stub `cvmdata.Rmd` em `eval = interactive()`.
- [x] **Sessão 02**: `cvm_fetch()` + DFP ponta-a-ponta — concluída
  (commit `298c272`, 2026-05-21).
  - [x] `cvm_fetch(dataset, table, ...)` como **API principal**.
    `cad_fetch()` mantido como alias trivial sobre `cvm_fetch()` (passa
    `source = "cvm"` até a Fase F entregar o mirror).
  - [x] Pipeline ZIP-yearly em `source_cvm_http_get()`: download do ZIP
    anual, extração do CSV alvo via `report_type`, cache com sidecar
    ETag.
  - [x] `cvm_datasets()` (lista de datasets) e `cvm_tables(dataset)`
    (tabelas de um dataset).
  - [x] `cvm_dataset_years(dataset)` — descoberta dinâmica via HTML
    listing do diretório do portal, cacheado por sessão.
  - [x] Default `years = NULL` → último ano disponível (via
    `cvm_dataset_years()` interno).
  - [x] Novo arg `report_type ∈ c("ind", "con")`, obrigatório para
    tabelas com variantes; erro para `composicao_capital`/`submissao`/
    `parecer`.
  - [x] `companies` com detecção automática (CNPJ 14 dígitos / CD_CVM
    ≤6 dígitos / busca textual) + word boundary + mapa de abreviações
    (BANCO↔BCO, COMPANHIA↔CIA, INDUSTRIA↔IND, PARTICIPACOES↔PART).
    Prompt interativo planejado (`utils::menu()`); ainda só `interactive()`
    pendente — hoje retorna todas as matches sem perguntar.
  - [x] `source = c("mirror", "cvm")` com default `"mirror"`. Stub de
    `"mirror"` aborta com `cvmdata_error_input` apontando para `"cvm"`
    até a Fase F entregar o backend parquet.
  - [x] Tracer: `cvm_fetch(dataset = "dfp", table = "bpa",
    report_type = "ind", companies = "BCO BRASIL", years = 2024)`.
  - [x] `apply_schema_transformations()` genérico cobre
    `multiply_by_scale` (com `scale_factor()` UNIDADE/MIL/MILHÃO/BILHÃO),
    `drop`, e `keep_latest_version` (groupby cnpj_cia+dt_refer, mantém
    maior `versao`).
  - [x] `transform_cad()` removido; CAD usa o pipeline genérico com
    `transformations: []`.
  - Pendências reabertas: prompt interativo de seleção de companhias
    quando há múltiplas matches em `interactive()`. Pendências da Sessão
    01 ainda válidas em
    `cvmdata_rodada3-1_sessao_01_scaffolding_cad_fetch.md` §6.
- [ ] **Sessão 03**: ITR + FRE ponta-a-ponta.
  - [ ] 11 YAMLs ITR (paralelos aos DFP, `cvm_archive_url_pattern`
    troca DFP → ITR, `first_year: 2011`).
  - [ ] 36 YAMLs FRE (1 header `submissao` + 35 detail; 8 desses com
    `meta_status: missing` precisam `expected_field_names`).
  - [ ] Política do reader para 8 tabelas FRE sem META (Rodada 3.0.2).
  - [ ] Vignettes `itr-dfp.Rmd` e `fre.Rmd`.
- [x] Cobertura ≥85% (atualmente 85.34% pós-Sessão 02, retomada após
  queda para 72% no merge de DFP).
- [ ] Substituir heurística de Date em `read_cvm_csv()` pela regra
  canônica baseada no snapshot de dicionário (depende de Fase C).
- [ ] Semântica diferenciada para `on_error = "warn"/"silent"`
  (atualmente aceitos por `arg_match0` mas só `"abort"` é exercitado).

### Fase E — Polimento e cobertura (20-30h)

- [-] `dfp_fetch()` / `itr_fetch()` / `fre_fetch()` — descartados.
  `cvm_fetch()` cobre tudo (decisão Sessão 02).
- [~] Política do reader para 8 tabelas FRE sem META
  (`meta_status: missing`; vide Rodada 3.0.2) — esqueleto pronto em
  `validate_field_names()` + modo `warn`/`strict`/`skip`; falta
  exercitar com YAMLs FRE reais (Sessão 03).
- [~] Exercitar branches `validate_field_names()` em `read_cvm_csv()`
  — modo `warn` coberto na Sessão 02; modo `strict` em `meta_status:
  missing` ainda não exercitado por nenhum YAML real.
- [ ] `cvm_dictionary()` lendo do snapshot.
- [ ] Família `cvm_cache_*()` pública (`path`, `set_path`, `info`,
  `clear`).
- [ ] `cvm_source_get()` / `cvm_source_set()`.
- [ ] Prompt interativo de seleção de companhias com múltiplas matches
  (`utils::menu()` em `interactive()`).
- [ ] `cnpj_format()` (operação inversa de `cnpj_clean()`).
- [ ] Subir cobertura para ≥90% (gate do marco v0.1.0; áreas baixas
  hoje: `discovery.R` 60%, `source-cvm-http.R` 62%).
- [ ] Vignette `cvm-fetch.Rmd` (substitui stub atual).
- [ ] Vignette de defeitos conhecidos da CVM (Rodada 2.6 §11.5).

### Fase F — Pipeline ETL + mirror (24-32h)

- [ ] Scripts `inst/etl/01-07.R`.
- [ ] Workflow `etl-mirror.yaml` (cron `0 7 * * 2`).
- [ ] Detecção de mudança via hash de `meta_*.txt` +
  `dictionary_entry_inventory.json` (defesa em profundidade
  contra mudanças silenciosas; Rodada 3.0.2 §4.3).
- [ ] Validação pre-publish com `pointblank`.
- [ ] Primeiro snapshot publicado em GitHub Releases.
- [ ] `source-mirror-duckdb.R` integrado ao dispatch
  (`source = "mirror"`; atualmente aborta com
  `cvmdata_error_input`).
- [ ] Vignette `cache-and-mirror.Rmd`.

### Marco — release v0.1.0

- [ ] R-CMD-check verde nos 5 jobs (Ubuntu devel/release/oldrel-1,
  macOS release, Windows release).
- [ ] Cobertura ≥90%.
- [ ] `revdepcheck::revdep_check()` limpo.
- [ ] `devtools::check_win_devel()` e `check_mac_release()` limpos.
- [ ] ≥30 dias de ETL rodando estável.
- [ ] Submissão rOpenSci (<https://github.com/ropensci/software-review>).
- [ ] Aceitação rOpenSci.
- [ ] Submissão CRAN (feita pelo rOpenSci em nome do mantenedor).

---

## v0.2+ (escopo futuro, fora do v0.1)

- [ ] **v0.2**: `fca`, `vlmo`, `cgvn`, `ipe` (companhias parte 2).
  - [ ] Suporte a ticker B3 no argumento `companies` (atualmente só
    CD_CVM e CNPJ; ticker exige join com mapping externo).
  - [ ] `cnpj_format()` (operação inversa de `cnpj_clean()`).
- [ ] **v0.3**: eventos societários + estrangeiras + incentivadas.
- [ ] **v0.4**: ICVM 555 (fundos de investimento — primeira classe
  não-companhia; pode exigir revisar L1/L3 cache para volume
  diário).
- [ ] **v0.5**: FII (fundos imobiliários).
- [ ] **v0.6**: FIDC + estruturados.
- [ ] **v1.0**: estabilização + paper no The R Journal.

---

## Pendências documentais

- [x] Nota corretiva sobre `R/` flat aplicada ao
  `cvmdata_rodada2_arquitetura_estavel.md` §2.1.3 (Sessão 01).
- [x] `inst/extdata/schemas/cad/companhias.yaml` atualizado com
  `expected_field_count: 47` (Sessão 01).
- [ ] Aplicar refinamentos da Rodada 3.0.2 ao naming doc v03 → v04
  (subsessão dedicada de edição editorial; item 9 do §7 de
  `cvmdata_rodada3-0-2_politica_reader_sem_meta.md`).
- [ ] Aplicar refinamentos da Rodada 3.0 ao naming doc (parcialmente
  feito na v03 — vide cabeçalho do naming doc).
- [ ] Acrescentar `cran-comments.md` quando aparecer a primeira NOTE
  inevitável.
- [ ] Atualizar `schemas_proto/cad/companhias.yaml` com
  `expected_field_count: 47` ou marcar como registro histórico
  congelado (decidir na próxima sessão).
