# ROADMAP — cvmdata

Plano de execução por fases.

= entregue

\[~\] = parcial / em andamento

= pendente

\[-\] = descartado

------------------------------------------------------------------------

## Pré-v0.1 - companhias abertas

### Fase A — Esqueleto

Inicialização do pacote (`DESCRIPTION`, `NAMESPACE`, `LICENSE`,
`LICENSE.md`).

Estrutura de diretórios (`R/` flat com prefixos hífen;
`tests/testthat/`, `inst/extdata/schemas/`, `data-raw/`, `vignettes/`,
`.github/workflows/`).

`NEWS.md` inicial.

`README.Rmd` + `README.md` com badges.

`README.pt-BR.Rmd` + `README.pt-BR.md`.

`CLAUDE.md` e `ROADMAP.md`.

`.lintr` config travada (linha 80, snake_case, cyclocomp ≤ 20).

`.Rbuildignore` e `.gitignore`.

Workflow `R-CMD-check.yaml` (matriz macOS release / Windows release /
Ubuntu devel-release-oldrel1).

Workflow `test-coverage.yaml`.

Workflow `lint.yaml`.

Workflow `pkgdown.yaml` + `pkgdown/_pkgdown.yml`.

`CODE_OF_CONDUCT.md` e `CONTRIBUTING.md`.

### Fase B — Cache + source CVM

Família cache pública
([`cvm_cache_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_path.md),
[`cvm_cache_set_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_set_path.md),
[`cvm_cache_info()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_info.md),
[`cvm_cache_clear()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_clear.md)).

Cache L1 (raw) para CSV direto e ZIP yearly.

Invalidação por ETag/Last-Modified com TTL configurável.

Limite de tamanho + eviction LRU.

`source_cvm_http_get()` para CSV direto e ZIP yearly.

[`cvm_source_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_get.md)
/
[`cvm_source_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_set.md).

Suite de testes mockados de HTTP.

### Fase C — Dispatch + schemas

`load_schema(dataset, table)` com validações.

\[-\] `dispatch_class(dataset)` — pipeline genérico + YAML por tabela
tornou desnecessário.

\[-\] `dispatch_table(dataset, table)` — idem.

YAML CAD/companhias.

YAMLs DFP (11 tabelas).

YAMLs ITR (11 tabelas).

YAMLs FRE (36 tabelas, 8 com `meta_status: missing`).

Geração programática dos YAMLs restantes a partir do snapshot de
dicionário.

`cvm_dictionary_snapshot.csv` + gerador em `data-raw/`.

`cvm_codelists_snapshot.csv` + gerador em `data-raw/`.

### Fase D — Datasets ponta-a-ponta

[`cad_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cad_fetch.md)
ponta-a-ponta.

`cvm_fetch(dataset, table, ...)` como API principal.

Pipeline ZIP-yearly em `source_cvm_http_get()`.

[`cvm_datasets()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_datasets.md)
e `cvm_tables(dataset)`.

`cvm_dataset_years(dataset)`.

Default `years = NULL` → último ano disponível, com fallback descendente
quando companhia ausente no max year.

Argumento `report_type ∈ c("ind", "con")`.

Argumento `companies` com detecção automática (CNPJ / CD_CVM / busca
textual).

Argumento `source ∈ c("mirror", "cvm")`.

DFP ponta-a-ponta.

ITR ponta-a-ponta.

FRE ponta-a-ponta (header detail com `cnpj_companhia` /
`data_referencia`, sem `cd_cvm`).

Lookup automático CD_CVM → CNPJ via `submissao` para tabelas sem
`cd_cvm` nativo.

`apply_schema_transformations()` genérico (`multiply_by_scale`, `drop`,
`keep_latest_version`).

Conversão automática de datas via dicionário (`tipo_dados = "date"`).

Semântica diferenciada para `on_error = "warn"`/`"silent"`.

### Fase E — Polimento e cobertura

\[-\] `dfp_fetch()` / `itr_fetch()` / `fre_fetch()` —
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
cobre tudo.

Política do reader em três modos (`strict`/`warn`/`skip`) para tabelas
com e sem META.

`cvm_dictionary(dataset, table)`.

`cvm_codelist(dataset, table, column)`.

Prompt interativo de seleção de companhias com múltiplas matches.

[`cnpj_format()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_format.md).

Cobertura ≥90%.

Vignette `cvmdata.Rmd` (intro CRAN-safe).

Article `cvm-fetch.Rmd`.

Article `itr-dfp.Rmd`.

Article `fre.Rmd`.

Article `cvm-defects.Rmd`.

Article `cache-and-mirror.Rmd`.

### Fase F — Pipeline ETL + mirror

Scripts ETL em `inst/etl/` (`00-config.R`, `01-fetch-cvm.R`,
`02-csv-to-parquet.R`, `02b-validate.R`, `03-publish.R`).

Workflow `etl-mirror.yaml` (`workflow_dispatch` + cron semanal, matrix
de 4 datasets).

Detecção de mudança via hash SHA-256.

Primeiro bulk publish do v0.1 (cad + dfp + itr + fre).

Backend mirror funcional (`source = "mirror"`): inventário GitHub
Releases + DuckDB local + filter pushdown por nome de asset.

Cache L3 (parquet local) com invalidação por hash.

`cvm_cache_clear(what = "parquet")`.

Validação pre-publish via `pointblank` (`02b-validate.R`).

\[-\] Snapshots datados imutáveis do mirror — adiados para releases
manuais do pacote, não para o cron.

### Marco — release v0.1.0

Flip do default de `source` para `"mirror"`.

Bump `DESCRIPTION` para `0.1.0`.

`cran-comments.md`.

`inst/CITATION`.

Tag git `v0.1.0` + GitHub release.

Reabrir ciclo de dev `0.1.0.9000`.

[`devtools::check_win_devel()`](https://devtools.r-lib.org/reference/check_win.html)
enviado.

\[~\]
[`devtools::check_mac_release()`](https://devtools.r-lib.org/reference/check_mac_release.html)
— pendente (504 transitório, retentar).

Submissão rOpenSci (pre-submission inquiry).

Aceitação rOpenSci.

Submissão CRAN (feita pelo rOpenSci em nome do mantenedor).

------------------------------------------------------------------------

## v0.2+ (escopo futuro)

**v0.2**: `fca`, `vlmo`, `cgvn`, `ipe` (companhias parte 2).

Suporte a ticker B3 no argumento `companies`.

**v0.3**: eventos societários + estrangeiras + incentivadas.

**v0.4**: ICVM 555 (fundos de investimento).

**v0.5**: FII (fundos imobiliários).

**v0.6**: FIDC + estruturados.

**v1.0**: estabilização + paper no The R Journal.

------------------------------------------------------------------------

## Pendências documentais

Nota corretiva sobre `R/` flat no canônico.

`inst/extdata/schemas/cad/companhias.yaml` com
`expected_field_count: 47`.

Refinamentos da Rodada 3.0.2 ao naming doc v04.

Refinamentos da Rodada 3.0 ao naming doc.

`cran-comments.md`.

`schemas_proto/cad/companhias.yaml` — atualizar ou marcar como histórico
congelado.
