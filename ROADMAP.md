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
- [x] `devtools::check_mac_release()` — PASS em
  `aarch64-apple-darwin23` (macOS Tahoe 26.2, Apple M1) sob
  R 4.6.0 patched, 0E/0W/0N.
> **Submissão rOpenSci, aceite e submissão CRAN foram realocadas para o
> fim do ciclo de desenvolvimento** (após v1.0). Decisão de Sidney
> (2026-05-28): a submissão ao rOpenSci só ocorre depois de todo o
> escopo planejado estar implementado e o pacote estabilizado. Ver a
> seção final "Fim do ciclo — submissão rOpenSci, CRAN e publicação".
> A decisão arquitetural de "grupos" (5 fetchers por contrato cobrindo
> os 18 grupos CKAN) está consolidada no documento canônico
> `data-raw/decisions/cvmdata_arquitetura_grupos_decisao_v2.md`.

---

## v0.1.0.9000 — migração arquitetural de grupos

Ciclo de desenvolvimento entre v0.1.0 e v0.2.0. Implementa a
decisão arquitetural de grupos fechada em 2026-05-25 (vide
`data-raw/decisions/cvmdata_arquitetura_grupos_decisao_v2.md`).
Reorganiza a API pública em 5 fetchers por contrato de dado,
migra cache/schemas/snapshots/mirror para layout `<group>`-aware,
e exporta skeletons dos 4 fetchers ainda não implementados.

Ordem das sessões é estrita — cada uma assume o estado da
anterior. Gate por sessão: `devtools::check() == 0E/0W/0N`,
lint clean, cobertura ≥ 90%.

### Sessão 04 — Cache layout migration

- [x] Helper interno `cache_migrate_v0_1_to_v0_2()`
  (não exportado, idempotente, com log em
  `tools::R_user_dir("cvmdata", "config")/cache_migrate_log.rds`).
- [x] `R/cache.R`, `R/source-cvm-http.R`,
  `R/source-mirror-duckdb.R` operando sobre
  `<cache>/raw/<group>/<dataset>/` e
  `<cache>/parquet/<group>/<dataset>/<table>/...`.
- [x] `cvm_cache_info()` reporta coluna `group`.
- [x] `cvm_cache_clear()` ganha argumento `group = NULL`.
- [x] Testes: cache vazio, cache antigo, cache misto, arquivo
  conflitante (`cvmdata_error_internal` + instrução de
  `cvm_cache_clear("all")` manual).
- [x] `R/util-group-lookup.R` novo com lookup constante
  `.dataset_group_map` + funções internas `dataset_group()` e
  `known_groups()`. Tabela documentada como dívida técnica a ser
  substituída por lookup schema-driven na Sessão 05.
- [x] Entrada em `NEWS.md` sob "Internal" da `0.1.0.9000`
  documentando o novo layout, a migração automática, a coluna
  `group` em `cvm_cache_info()` e o argumento `group` em
  `cvm_cache_clear()`.

### Sessão 05 — Schemas + dictionary/codelist migration

- [x] `git mv inst/extdata/schemas/{cad,dfp,itr,fre}/` →
  `inst/extdata/schemas/companhias/{cad,dfp,itr,fre}/`.
- [x] `load_schema()` aceita `group` (opcional com unicidade;
  ambiguidade aborta com `cvmdata_error_input_ambiguous` listando
  os grupos onde `(dataset, table)` ocorre).
- [x] `R/util-group-lookup.R` reescrito como lookup
  **schema-driven** (lendo `list.dirs(inst/extdata/schemas/)` com
  memoização por sessão), substituindo a tabela constante
  `.dataset_group_map` deixada como dívida técnica pela Sessão 04.
- [x] Nova classe de condição `cvmdata_error_input_ambiguous`
  (herda de `cvmdata_error_input`), introduzida em `load_schema()`
  e reutilizável por `cvm_dictionary()` / `cvm_codelist()` /
  futuras funções de descoberta.
- [x] `cvm_dictionary_snapshot.csv` regenerado com `group` como
  primeira coluna; gerador em `data-raw/build-dictionary-snapshot.R`
  atualizado.
- [x] `cvm_codelists_snapshot.csv` regenerado com `group` como
  primeira coluna; gerador em `data-raw/build-codelists-snapshot.R`
  atualizado.
- [x] `cvm_dictionary()`, `cvm_codelist()` aceitam `group`.
- [x] Testes de regressão: snapshots batem com versão anterior
  módulo nova coluna.

### Sessão 06 — Rename + deprecation abrupta + argumentos no singular

- [x] `R/api-cvm-fetch.R` → `R/api-issuer-fetch.R`.
- [x] `cvm_fetch_internal()` → `issuer_fetch_internal()`.
- [x] `cvm_fetch()` → `issuer_fetch()`.
- [x] Argumentos renomeados para singular:
  - `companies` → `issuer`
  - `years` → `year`
- [x] `cvm_fetch()` removida sem wrapper.
- [x] `cad_fetch()` removida sem wrapper (`R/api-cad-fetch.R` apagado).
- [x] Todos os exemplos roxygen atualizados.
- [x] `vignettes/cvmdata.Rmd` e todos os articles atualizados
  (`cvm-fetch.Rmd` → `issuer-fetch.Rmd`).
- [x] Todos os testes migrados (`grep -rl "cvm_fetch\|cad_fetch" tests/ R/`
  + sed).
- [x] `NEWS.md` com entrada `⚠️ breaking` documentando o caminho
  de migração.
- [x] Testes cobrindo rename + arg singular aceitando vetor.

### Sessão 07 — Esqueletos dos 4 fetchers restantes

- [x] `R/api-fund-fetch.R` com signature canônica + abort
  `cvmdata_error_input_group`.
- [x] `R/api-agent-fetch.R` idem.
- [x] `R/api-offering-fetch.R` idem.
- [x] `R/api-event-fetch.R` idem.
- [x] Testes de signature + dispatch + abort previsto para cada.
- [x] Documentação roxygen completa, `@examples` marcados
  `@examplesIf FALSE`.
- [x] `_pkgdown.yml` lista as 5 funções em Reference com nota
  de estado.
- [x] Classe de condição nova `cvmdata_error_input_group`
  (`cvmdata_error_input_ambiguous` já vem da Sessão 05).

### Sessão 08 — Discovery + cvm_groups() + ETL release rename

- [x] `R/api-cvm-groups.R` com `cvm_groups()` lendo da taxonomia
  estática (tibble com `group`, `n_datasets`, `contract`).
- [x] Argumento `group` adicionado em `cvm_datasets()`,
  `cvm_tables()`, `cvm_dictionary()`, `cvm_codelist()`,
  `cvm_dataset_years()` (opcional com unicidade). Os dois últimos
  já vinham da Sessão 05.
- [x] `etl-mirror.yaml` com matrix bidimensional `(group, dataset)`.
- [x] Scripts `inst/etl/0{1,2,2b,3}*.R` ganham CLI flag `--group`.
- [x] `inst/etl/03-publish.R` nomeia releases
  `mirror-<group>-<dataset>-latest`.
- [x] Consumer side (`R/util-mirror-assets.R`,
  `R/source-mirror-duckdb.R`) lê o novo formato; cache de inventário
  passa a chavear por `(group, dataset)`.
- [x] **Rename in-place** dos 4 releases atuais via GitHub API
  (`gh release edit` ou REST), com checkpoint após cada um;
  rollback documentado em caso de falha parcial. Tarefa manual do
  mantenedor pós-Sessão 08 (não roda no CI).
- [x] `vignettes/articles/cache-and-mirror.Rmd` atualizado.
- [x] `vignettes/articles/groups-overview.Rmd` novo (lista 18
  grupos, mapeia para 5 contratos, exemplos por fetcher;
  `issuer_fetch()` real, 4 skeletons com `eval = FALSE`).
- [x] `vignettes/articles/cvm-defects.Rmd` renomeado para
  `data-defects.Rmd` (defeito não é só "do CVM"; cobre toda fonte
  de dado a partir de v0.4+).
- [x] `pkgdown/_pkgdown.yml` lista `cvm_groups` em Discovery e
  inclui `groups-overview` + `data-defects` na navbar de articles.
- [x] Atributo `group` adicionado em tibble retornado
  (6 atributos: `source`, `fetched_at`, `group`, `dataset`,
  `table`, `package_version`); `print.cvm_tbl()` exibe `group`.

### Pós-Sessão 08 — estado pós-migração arquitetural

Migração de grupos concluída (Sessões 04-08). A pre-submission ao
rOpenSci **não** ocorre aqui: foi movida para o fim do ciclo de
desenvolvimento (ver seção final "Fim do ciclo — submissão rOpenSci,
CRAN e publicação").

---

## v0.2+ (escopo futuro)

Nomenclatura por **grupo CKAN da CVM** (18 grupos verificados em
<https://dados.cvm.gov.br/group/>, 2026-05-25). Cada release
incremental cobre um grupo ou subconjunto coerente; o fetcher
correspondente já existe em skeleton desde v0.1.0.9000.

### v0.2 — `companhias` (parte 2)

Cobertos por `issuer_fetch()` (já funcional; novos datasets aterrissam
incrementalmente no ciclo `0.1.0.9000` rumo à v0.2.0).

- [x] Dataset `fca` (Formulário Cadastral).
- [x] Dataset `vlmo` (Valores Mobiliários Negociados e Detidos).
- [x] Dataset `cgvn` (Informe do Código de Governança Corporativa).
- [x] Dataset `ipe` (documentos periódicos e eventuais).
- [x] Suporte a ticker B3 no argumento `issuer` de
  `issuer_fetch()`.

### Marco — release v0.2.0

- [x] Bump `DESCRIPTION` para `0.2.0`.
- [x] `NEWS.md`: seção `# cvmdata 0.2.0` consolidando os 4 datasets
  novos + ticker B3.
- [x] Auditoria final do mirror (primeiro publish de cgvn/vlmo/fca/ipe
  via `etl-mirror.yaml`; IPE ~38 MB total, dentro do limite).
- [x] Tag git `v0.2.0` + GitHub Release.
- [x] Reabrir ciclo de dev `0.2.0.9000`.
- [ ] Pendência operacional (fora do v0.2.0): `dfp/itr/fre` falham no
  fetch de anos históricos de `composicao_capital` (lado-CVM, surgiu
  entre 24 e 29/05); mirrors de 24/05 seguem servindo. Investigar em
  sessão de ETL dedicada.

### v0.3 — `companhias` (parte 3) + perfis não-default

Ainda cobertos por `issuer_fetch()`. (ICBGC saiu desta lista — é o
mesmo dataset que `cgvn` em v0.2.)

- [ ] Programas de recompra de ações.
- [ ] Cadastro de companhias estrangeiras.
- [ ] Cadastro de companhias incentivadas.
- [ ] Eventos societários remanescentes do grupo `companhias`.

### v0.4 — `fundos-de-investimento` (22 datasets)

Coberto por `fund_fetch()` (skeleton já exportado). Maior chunk
de trabalho do projeto; provável quebra em v0.4.1 → v0.4.x
conforme cada dataset entra.

- [ ] Implementação completa de `fund_fetch()` (substitui o abort
  do skeleton).
- [ ] Argumento `fund` com detecção automática (CNPJ; texto livre
  fica para v0.5+ se útil).
- [ ] Argumento `date` (datas pontuais, default `NULL` → último
  mês disponível).
- [ ] Cadastro de fundos (`fi-cad` e variantes).
- [ ] Informes diários, mensais, trimestrais.
- [ ] Composição e Diversificação de Aplicações (CDA).
- [ ] Balancetes mensais.
- [ ] Balanços semestrais.
- [ ] Lâminas (ICVM 555).
- [ ] Formulários complementares.
- [ ] FIDC: informe mensal + composição de carteira.
- [ ] Tratamento de Resolução CVM 175 (Classe / Subclasse).
- [ ] Identificadores novos no reader: `cnpj_fundo`,
  `cnpj_administrador`.

### v0.5 — `fundos-de-investimento-imobiliarios` (4 datasets)

Coberto por `fund_fetch()`.

- [ ] Informe mensal FII.
- [ ] Informe trimestral FII.
- [ ] Demais 2 datasets do grupo.

### v0.6 — `fundos-estruturados` (10 datasets)

Coberto por `fund_fetch()`. Inclui FAPI, FIIM, FIP, etc. FIDC
aparece aqui também em alguns datasets — coordenar com v0.4 para
não duplicar.

- [ ] Balancetes de fundos estruturados.
- [ ] Informes trimestrais e quadrimestrais FIP.
- [ ] Medidas de fundos estruturados (PL + nº cotistas).
- [ ] Demais datasets do grupo.

### v0.7 — `agent_fetch()` full + `offering_fetch()` full

Implementação completa dos skeletons exportados em v0.1.0.9000.

Grupos cobertos por `agent_fetch()`:

- [ ] `administradores` (Administradores de Carteira + FII).
- [ ] `agentes-autonomos`.
- [ ] `agentes-fiduciarios`.
- [ ] `auditores`.
- [ ] `consultores-de-valores-mobiliarios`.
- [ ] `coordenadores-de-ofertas`.
- [ ] `participantes-intermediarios`.
- [ ] `investidores-nao-residentes`.
- [ ] Argumento `agent` com detecção CPF/CNPJ/texto por dataset.
- [ ] Argumento `as_of` (snapshot temporal).
- [ ] `cpf_clean()` e `cpf_format()` exportadas como utilitários.

Grupos cobertos por `offering_fetch()`:

- [ ] `ofertas-publicas`.
- [ ] `plataformas-de-crowdfunding` (Resolução CVM 88).
- [ ] Argumento `offering` (`numero_oferta` string).
- [ ] Argumento `date_range` (vetor `c(from, to)`).

### v0.8 — `event_fetch()` full

- [ ] `atividade-sancionadora` (processos sancionadores).
- [ ] `atos-declaratorios` (deliberações da diretoria CVM).
- [ ] Argumento `event` (ID de processo / ato).
- [ ] Argumento `date_range`.

### v1.0 — estabilização

Fecha o desenvolvimento de features. Pré-requisito para o gate de
submissão (seção final).

- [ ] Implementação real dos 5 fetchers concluída (v0.4-v0.8
  entregues; `fund_fetch()`, `agent_fetch()`, `offering_fetch()` e
  `event_fetch()` saem de skeleton para funcionais).
- [ ] Audit completo de cobertura: todos os 18 grupos e 76
  datasets do portal mapeados.
- [ ] Vignettes finais por contrato
  (`issuer-fetch.Rmd`, `fund-fetch.Rmd`, `agent-fetch.Rmd`,
  `offering-fetch.Rmd`, `event-fetch.Rmd`).
- [ ] Promoção do lifecycle de `experimental` para `stable`.
- [ ] `devtools::check()` 0E/0W/0N nos três runners; cobertura
  ≥ 90%; lint clean.

---

## Fim do ciclo — submissão rOpenSci, CRAN e publicação

Gate movido para o **fim do desenvolvimento**, após v1.0. Decisão de
Sidney (2026-05-28): a submissão ao rOpenSci só ocorre depois de todo o
escopo planejado estar implementado e o pacote estabilizado. Substitui o
plano anterior, que previa a pre-submission logo após a Sessão 08.

Consequência: neste plano a entrada no CRAN está acoplada ao aceite do
rOpenSci, logo o pacote permanece **fora do CRAN durante todo o
desenvolvimento v0.2-v0.8**. Distribuição até lá é via GitHub
(`pak::pak("SidneyBissoli/cvmdata")`).

### Pré-requisitos (gate)

- [ ] v1.0 fechada (ver seção acima): 5 fetchers funcionais, 18 grupos
  e 76 datasets cobertos, lifecycle `stable`.
- [ ] `devtools::check()` 0E/0W/0N nos três runners; cobertura ≥ 90%;
  lint clean.
- [ ] pkgdown completo e publicado.

### Submissão rOpenSci

- [ ] Reescrever `data-raw/rOpenSci-presubmission-draft.md` refletindo a
  arquitetura final e a cobertura completa (5 fetchers, 18 grupos, 76
  datasets).
- [ ] Submeter pre-submission inquiry ao rOpenSci.
- [ ] Submissão formal ao rOpenSci software peer review.
- [ ] Endereçar feedback dos reviewers.
- [ ] Aceitação rOpenSci.

### Submissão CRAN (após aceite rOpenSci)

- [ ] `cran-comments.md` revisado para v1.0.
- [ ] Submissão ao CRAN.
- [ ] Aceitação no CRAN.

### Publicação acadêmica (após aceite rOpenSci)

- [ ] Paper no The R Journal. **Dependência explícita**: somente após o
  aceite pelo rOpenSci (decisão de Sidney, 2026-05-28).

---

## Pendências documentais

- [x] Nota corretiva sobre `R/` flat no canônico.
- [x] `inst/extdata/schemas/cad/companhias.yaml` com
  `expected_field_count: 47`.
- [ ] Refinamentos da Rodada 3.0.2 ao naming doc v04.
- [ ] Refinamentos da Rodada 3.0 ao naming doc.
- [x] `cran-comments.md`.
- [x] `schemas_proto/` — apagados os três YAMLs órfãos (cad/companhias,
  fre/administrador_membro_conselho_fiscal, itr/bpa_con), todos
  superseded pelos homônimos em `inst/extdata/schemas/`. Diretório
  removido; será recriado pelo workflow §12.2 quando v0.2+ precisar
  de novo stage.
