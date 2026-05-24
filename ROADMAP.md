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
- [x] Workflow `test-coverage.yaml` — Sessão 3.7. Usa
  `codecov/codecov-action@v4` com `CODECOV_TOKEN` secret (Alt 1 do
  trio codecov-oficial/artifact). Badge já existe em README.Rmd
  apontando para `app.codecov.io/gh/SidneyBissoli/cvmdata` — primeiro
  run real do workflow precisa do token criado em codecov.io.
- [x] Workflow `lint.yaml` — Sessão 3.7. Roda `lintr::lint_package()`
  com `LINTR_ERROR_ON_LINT=true` (PR falha em qualquer divergência
  de `.lintr`).
- [x] Workflow `pkgdown.yaml` — Sessão 3.7. Deploy via
  `JamesIves/github-pages-deploy-action@v4.5.0` na branch órfã
  `gh-pages` (Alt 1 do par branch/actions-deploy-pages, padrão
  `usethis::use_pkgdown_github_pages()`). Site em
  `https://sidneybissoli.github.io/cvmdata/` após primeiro push.
- [x] `pkgdown/_pkgdown.yml` configurado — Sessão 3.7. 5 famílias
  (`fetchers`, `cache`, `source`, `discovery`, `utilities`)
  agrupando as 14 funções exportadas até a 3.6.
- [x] `CODE_OF_CONDUCT.md` e `CONTRIBUTING.md` — Sessão 3.10.
  Contributor Covenant 2.1 (canônico, sem desvios) com endpoint de
  report `sbissoli76@gmail.com` (Alt 1 do trio email-pessoal/issue-
  tracker/email-dedicado; mesmo email já público em `Authors@R`).
  `CONTRIBUTING.md` médio (~150 linhas, Alt 2 do trio mínimo/médio/
  completo): Reporting issues, Submitting a PR, Development setup,
  Quality gate (comandos literais), Adding/modifying schema YAML
  (formato mínimo + ações de `transformations`), Project goals.
  README.Rmd ganhou seção `Contributing` com paragrafo padrão
  rOpenSci/usethis apontando para ambos; pkgdown 2.x detecta CoC/
  CONTRIBUTING automaticamente no navbar.

### Fase B — Cache + source CVM (16-20h)

- [x] `cvm_cache_path()`, `cvm_cache_set_path()`, `cvm_cache_info()`,
  `cvm_cache_clear()` (família pública) — entregues na Sessão 3.5 em
  `R/cache.R`. `source-cvm-http.R` passou a consumir `cvm_cache_path()`
  como single source of truth para a raiz do cache.
  `cvm_cache_info()` lista upstream artifacts + CSVs extraídos como
  linhas separadas, com etag/last_modified vindo dos sidecars
  `*.etag.rds` quando presentes. `cvm_cache_clear()` aceita
  `what ∈ c("all", "raw")` + filtros opcionais `dataset` e `year`;
  `confirm = interactive()` pede confirmação via `utils::askYesNo()`
  em sessão interativa, apaga direto em batch.
- [~] L1 (raw) implementado para CSV direto (Sessão 01) e para ZIP
  (Sessão 02, em `<cache>/raw/<dataset>/<year>/`). Falta L3 (Parquet,
  Fase F) e L4 (`cachem::cache_mem()`).
- [x] Invalidação por ETag/Last-Modified implementada (sidecar RDS),
  estendida para ZIPs anuais na Sessão 02. TTL imposto na Sessão 3.7
  via `options(cvmdata.cache_ttl_seconds)` (default 30 dias =
  2 592 000 s; `0` força HEAD em toda chamada; `Inf` desliga HEAD
  enquanto o sidecar existir; sidecar sem `fetched_at` parseável cai
  para HEAD para refrescar metadados).
- [x] Limite de tamanho via `options(cvmdata.cache_max_size_mb)` e
  eviction LRU quando atinge 90% — Sessão 3.8. Default 100 MiB.
  Engine em `R/cache.R` (`read_cache_max_size()`,
  `build_cache_units()`, `cache_current_size_bytes()`,
  `cache_enforce_limit()`); trigger amortizado em
  `download_with_etag()` no ramo que grava bytes (TTL/304 fast paths
  pulam). Métrica de ordenação `file.mtime()` do upstream artifact
  (Alt 1 da decisão 1); escopo todo o conteúdo de `<cache>/raw/`
  com unidade atômica = diretório do ano (yearly) ou par
  `{artifact, sidecar}` (none) (Alt 2 da decisão 2); gatilho após
  gravação + target 80% (Alt 1 da decisão 3). Limite `0`/negativo/
  `Inf` desliga; tipo inválido cai para default. Observabilidade
  via `cvmdata_warn_eviction` (nova classe em §6 do CLAUDE.md),
  default `interactive()` via
  `options(cvmdata.cache_warn_evictions)` (Alt 3 da decisão 5).
  Atributo `total_size_bytes` adicionado a `cvm_cache_info()` (Alt
  1 da decisão 4). Sem export novo (Alt 1 da decisão 6).
- [x] `source_cvm_http_get()` para CSV direto (Sessão 01) e ZIP-yearly
  (Sessão 02, com extração do CSV alvo via `report_type`).
- [x] `cvm_source_get()` / `cvm_source_set()` — entregues na Sessão 3.6
  em `R/source.R`. `cvm_fetch()` agora declara `source = NULL` e
  resolve via `cvm_source_get()` (precedência: arg > option > default).
  Default em v0.1 é `"cvm"`; transiciona para `"mirror"` na release
  que ativar a Fase F. Mirror permanece bloqueado por
  `cvmdata_error_internal` até lá.
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
- [x] YAMLs para ITR (mesmo set que DFP — pipeline reusa
  `cvm_file_pattern_variants`) — Sessão 03.
- [x] YAMLs para FRE (36 tabelas incluindo `submissao` + 8 com
  `meta_status: missing`) — Sessão 03.2.
- [ ] Geração programática dos YAMLs restantes a partir do snapshot
  de dicionário.
- [x] Snapshot de dicionário `cvm_dictionary_snapshot.csv` em
  `inst/extdata/` (865 linhas cobrindo 51 tabelas com META oficial +
  8 FRE-detail `meta_status: missing` com placeholders). Gerador
  reprodutível em `data-raw/build-dictionary-snapshot.R`.
- [x] Snapshot de codelists `cvm_codelists_snapshot.csv` em
  `inst/extdata/` (445 valores em 133 colunas codelist sobre 46
  tabelas: 46 do dicionário S/N+PF/PJ + 87 promovidas por
  cardinalidade observada ≤ 50 no último ano disponível). Gerador
  reprodutível em `data-raw/build-codelists-snapshot.R`.

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
    `cvm_dataset_years()` interno). Hotfix pós-Sessão 02: quando
    `companies != NULL`, faz fallback descendente até 3 anos quando o
    max year não tem dados da companhia pedida (companhias com
    calendário fiscal não-civil — agros etc. — fazem o portal listar
    ZIPs do ano corrente sem cobertura de empresas civis), emitindo
    `cvmdata_warn_year_fallback`.
  - [x] Novo arg `report_type ∈ c("ind", "con")`, obrigatório para
    tabelas com variantes; erro para `composicao_capital`/`submissao`/
    `parecer`.
  - [x] `companies` com detecção automática (CNPJ 14 dígitos / CD_CVM
    ≤6 dígitos / busca textual) + word boundary + mapa de abreviações
    (BANCO↔BCO, COMPANHIA↔CIA, INDUSTRIA↔IND, PARTICIPACOES↔PART).
    Prompt interativo via `utils::menu()` em `interactive()` e abort em
    batch entregues como hotfix pós-Sessão 02 (vide Fase E).
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
  - Hotfixes pós-Sessão 02 entregues: (a) `filter_by_companies()`
    usava `sprintf("%06s", ...)` que pad com espaços, não zeros — CD_CVM
    sem zero-padding (`"1023"`) nunca casava `"001023"`; trocado por
    `formatC(as.integer(.), width = 6, flag = "0", format = "d")`.
    (b) Prompt interativo `utils::menu()` para múltiplas matches em
    busca textual, abort em batch. (c) Fallback descendente quando
    `years = NULL` + companhia ausente no max year. Pendências da
    Sessão 01 ainda válidas em
    `cvmdata_rodada3-1_sessao_01_scaffolding_cad_fetch.md` §6.
- [x] **Sessão 03**: ITR + FRE ponta-a-ponta.
  - [x] 11 YAMLs ITR (paralelos aos DFP, `cvm_archive_url_pattern`
    troca DFP → ITR, `first_year: 2011`). Auditoria empírica do ZIP
    2024 confirmou paridade total de schema com DFP (`expected_field_count`
    idêntico em todas as 11 tabelas, mesmo set de variantes ind/con,
    mesmo padrão de naming de CSV). Fixture
    `tests/testthat/fixtures/itr_cia_aberta_2024.zip` (6.94 KB, 3 CSVs,
    BCO BRASIL + MAGAZINE LUIZA × 3 trimestres) com `.meta.json` de
    origem; tracer test + discovery em `test-cvm-fetch.R`.
  - Hotfix pós-Sessão 03: tabelas sem `cd_cvm` (`composicao_capital`,
    `parecer` em DFP e ITR) retornavam tibble vazio silenciosamente
    quando `companies` recebia CD_CVM. Implementada resolução automática
    CD_CVM → CNPJ via `submissao` do mesmo dataset/year
    (`resolve_cd_cvm_via_submissao()` em `R/api-cvm-fetch.R`). Mesmo
    custo de runtime apenas no primeiro lookup por sessão (cache de
    disco + HEAD revalidando ETag). CD_CVMs inexistentes na submissao
    daquele ano abortam com `cvmdata_error_input`. CLAUDE.md §2.7
    atualizado.
  - [x] **Sessão 03.2**: 36 YAMLs FRE (1 header `submissao` + 35
    detail; 8 com `meta_status: missing` + `expected_field_names`).
    Auditoria empírica do ZIP 2024 (URL META é
    `meta_fre_cia_aberta.zip`, sem o sufixo `_txt.zip` previsto;
    `first_year = 2010`; META de `empregado_local_faixa_etaria` vive
    sem o prefixo `meta_` no entry dentro do ZIP — anomalia tratada
    como `available` mesmo assim). Nenhum `multiply_by_scale` em FRE
    (sem `VL_CONTA`/`ESCALA_MOEDA`). Fixture
    `tests/testthat/fixtures/fre_cia_aberta_2024.zip` (4.4 KB, 3 CSVs:
    `submissao`, `auditor`, `empregado_PCD`; BCO BRASIL + MAGAZINE
    LUIZA + BCO NORDESTE; BB carrega linha sintética VERSAO=99 em
    `auditor` para exercitar `keep_latest_version` na chave
    `(cnpj_companhia, data_referencia)`).
  - [x] **Sessão 03.2**: ajustes cirúrgicos para FRE-detail. Detail
    tables FRE usam header diferente do CAD/ITR/DFP (CLAUDE.md §2.2):
    `cnpj_companhia`/`data_referencia`/`nome_companhia`, sem `cd_cvm`.
    `match_by_cnpj()`, `match_by_text()`, `disambiguate_text_match()` e
    `tx_keep_latest_version()` agora aceitam o par alternativo via
    helpers `cnpj_col()`/`name_col()` em `R/api-cvm-fetch.R`. Zero
    efeito em CAD/ITR/DFP.
  - [x] **Sessão 03.2**: política do reader exercitada pela primeira
    vez contra YAMLs reais com `meta_status: missing` — três modos
    (`strict`/`warn`/`skip`) cobertos por testes que reescrevem o
    header de `empregado_PCD` no cache.
  - [x] **Sessão 3.9**: Articles `itr-dfp.Rmd` e `fre.Rmd` em
    `vignettes/articles/` (eval = TRUE, CVM real). Reference table
    no topo de cada um (11/36 tabelas); 2 workflows por article.
    itr-dfp cobre `multiply_by_scale` + `keep_latest_version` +
    lookup CD_CVM→CNPJ via `submissao`; fre cobre header alternativo
    (`cnpj_companhia`), `meta_status: missing` (workflow PCD), cap
    table (`posicao_acionaria`).
- [x] Cobertura ≥85% (atualmente 85.34% pós-Sessão 02, retomada após
  queda para 72% no merge de DFP).
- [x] Substituir heurística de Date em `read_cvm_csv()` pela regra
  canônica baseada no snapshot de dicionário (`tipo_dados = "date"`).
  `build_col_types()` consulta `cvm_dictionary()` via
  `resolve_dict_columns()`; snapshot prevalece para colunas cobertas
  e heurística `^(dt_|data_)` atua como fallback para
  `meta_status: missing` e schemas sintéticos (Sessão 3.4).
- [x] Semântica diferenciada para `on_error = "warn"/"silent"` —
  Sessão 3.7. Escopo: HTTP failures em batches yearly
  (`years = c(...)` com >1 elementos). `"warn"` empilha os anos
  sobreviventes e emite `cvmdata_warn_partial_failure` listando os
  que falharam; `"silent"` empilha sem emitir warning; `"abort"`
  (default) propaga a primeira falha. Total failure (todos os anos)
  sempre aborta com `cvmdata_error_http`. Single-year, non-yearly
  (CAD) e o fallback descendente quando `years = NULL` continuam
  abortando regardless. Parse/validation continuam governados por
  `validate` — fora do escopo do `on_error` por design (evita
  mascarar drift de schema da CVM).

### Fase E — Polimento e cobertura (20-30h)

- [-] `dfp_fetch()` / `itr_fetch()` / `fre_fetch()` — descartados.
  `cvm_fetch()` cobre tudo (decisão Sessão 02).
- [x] Política do reader para 8 tabelas FRE sem META
  (`meta_status: missing`; vide Rodada 3.0.2) — esqueleto em
  `validate_field_names()` exercitado contra YAMLs reais nos três
  modos (`strict`/`warn`/`skip`) na Sessão 03.2.
- [x] Exercitar branches `validate_field_names()` em `read_cvm_csv()`
  — modo `warn` coberto na Sessão 02; modos `strict` e `skip` em
  `meta_status: missing` cobertos na Sessão 03.2.
- [x] `cvm_dictionary(dataset, table)` lendo do snapshot, com cache
  por sessão; atributo `meta_status = "missing"` quando aplicável.
- [x] `cvm_codelist(dataset, table, column)` lendo do snapshot de
  codelists embarcado, com cache por sessão. Erros distinguem
  dataset/table/column desconhecidos vs. coluna conhecida mas não-
  codelist (Sessão 3.4).
- [x] Família `cvm_cache_*()` pública (`path`, `set_path`, `info`,
  `clear`) — Sessão 3.5. Detalhes na entrada equivalente da Fase B.
- [x] `cvm_source_get()` / `cvm_source_set()` — Sessão 3.6. Detalhes
  na entrada equivalente da Fase B.
- [x] Prompt interativo de seleção de companhias com múltiplas matches
  (`utils::menu()` em `interactive()`); aborta com `cvmdata_error_input`
  em batch listando as matches. CLAUDE.md §2.7.
- [x] `cnpj_format()` (operação inversa de `cnpj_clean()`). Política
  estrita-tolerante: input não-character aborta com
  `cvmdata_error_input`; vetor com elementos sem 14 dígitos retorna
  `NA_character_` para esses e emite `cvmdata_warn` listando posições
  (Sessão 3.4).
- [x] Subir cobertura para ≥90% (gate do marco v0.1.0). Pós-Sessão 3.6
  total **95.31%**: `source-cvm-http.R` 60.45% → 100%; `discovery.R`
  78.41% → 90.53%; `transform-schema.R` 86.27% → 100%. Branches
  ainda fora cobrem só guards defensivos (snapshot ausente / pacote
  não instalado / dataset com schema dir vazio).
- [x] **Sessão 3.9**: Article `cvm-fetch.Rmd` (deep dive da API) em
  `vignettes/articles/`. Stub `vignettes/cvmdata.Rmd` reescrito como
  intro CRAN-safe (RDS pré-computado em
  `inst/extdata/vignette-data/`); `data-raw/build-vignette-data.R`
  regera as RDS hitando a CVM. Layout final:
  1 vignette (`cvmdata.Rmd`) + 4 articles (`cvm-fetch`, `itr-dfp`,
  `fre`, `cvm-defects`).
- [x] **Sessão 3.9**: Article `cvm-defects.Rmd` cobrindo os 13
  defeitos conhecidos da publicação CVM (naming doc §11.5 +
  descobertos em implementação). Híbrido: tabela-índice no topo +
  mini-exemplo para os 5 estruturais (#5 padding CD_CVM, #7
  `multiply_by_scale`, #8 META missing, #11 `keep_latest_version`,
  #13 lookup CD_CVM→CNPJ).

### Fase F — Pipeline ETL + mirror (24-32h)

Decisões de arquitetura travadas na Sessão 3.11
(`data-raw/mirror-capacity-audit.md`):

- **Provedor**: GitHub Releases (mesmo repo `SidneyBissoli/cvmdata`).
  v1.0 projetado em 26.36 GB parquet snappy (92% concentrado em
  FI/ICVM 555). Pior arquivo individual = 451 MB (FI/CDA anual), bem
  abaixo do limite de 2 GB/arquivo.
- **Escopo**: modular — 1 release por dataset
  (`mirror-<dataset>-latest`).
- **URL policy**: latest móvel + snapshots datados
  (`mirror-<dataset>-snapshot-YYYY-MM-DD`).
- **Formato**: parquet snappy + Hive-style `year=YYYY/` (compatível
  com `arrow::open_dataset()` e DuckDB filter pushdown).

Itens entregues:

- [x] Scripts ETL em `inst/etl/`: `00-config.R`, `01-fetch-cvm.R`,
  `02-csv-to-parquet.R`, `03-publish.R`. Pipeline completo
  (fetch → parquet → upload via `gh release`) idempotente; suporta
  variants `report_type` (ind/con) em DFP/ITR contábeis. Entregue na
  Sessão 3.11.
- [x] Workflow `.github/workflows/etl-mirror.yaml` com trigger
  `workflow_dispatch` (Sessão 3.11) + cron `0 7 * * 2` e matrix de
  4 datasets com `fail-fast: false` (Sessão 3.12).
- [x] `R/source-mirror-duckdb.R` criado como stub. Bloco
  `source = "mirror"` em `cvm_fetch_internal()` agora delega para
  `source_mirror_duckdb_get()`; classe trocada de
  `cvmdata_error_internal` para `cvmdata_error_input` com mensagem
  acionável apontando para `cvm_source_set("cvm")`. Sessão 3.11.
- [x] Detecção de mudança via hash SHA-256 das URLs de
  `cvm_dictionary_url` (meta_*.txt e fragmentos de
  meta_*_txt.zip). `inst/etl/util-hash.R` traz
  `compute_source_hash(dataset)`; `03-publish.R` baixa o
  `__source_hash.json` do release anterior, compara, e skipa publish
  quando o hash bate. Sessão 3.12.
- [x] Primeiro bulk publish do v0.1 (cad + dfp + itr + fre) via
  dispatch manual do workflow exercitando matrix completa.
  Sessão 3.12.
- [-] Snapshots datados imutáveis (`mirror-<dataset>-snapshot-YYYY-MM-DD`)
  ficam para releases do pacote (v0.1.0+), não para o cron semanal.
  Decisão da Sessão 3.12: 26 GB/snapshot × 52/ano = pagar storage por
  reprodutibilidade que ninguém pede em cadência semanal; vignette/paper
  fixam release de pacote, não data arbitrária. Cron mantém só
  `latest`. Helper `mirror_tag_snapshot()` em `00-config.R` continua
  pronto para o uso manual em releases.

Itens pendentes para Sessões 3.13-3.14:

- [ ] Validação pre-publish com `pointblank`.
- [ ] `source-mirror-duckdb.R` funcional (DuckDB HTTP range requests
  com filter pushdown por `year` + `companies`); stub atual aborta com
  `cvmdata_error_input`. Sessão 3.13.
- [ ] Vignette `cache-and-mirror.Rmd`. Sessão 3.14.
- [ ] Flip do default de `source` de `"cvm"` para `"mirror"`.
  Sessão 3.14 (ou início v0.1.0).

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
