# cvmdata — decisão arquitetural de grupos (v0.1.0.9000) — v2

> **Sessão**: plan-mode, 2026-05-25 (rev. 2 após três rodadas com Sidney).
> **Status**: **decisões fechadas**. Pendências do v1 resolvidas. Documento
> serve como input direto para a próxima sessão Claude Code (CLI).
> **Idioma**: PT-BR (sessão de planejamento); identificadores de código em EN,
> fiel à Régua de Idioma (CLAUDE.md §1).

---

## Histórico de revisão

- **v1** (2026-05-25 manhã): proposta inicial com 4 fetchers + lista de
  6 pendências para Sidney.
- **v2** (2026-05-25 tarde): após 3 rodadas de discussão com Sidney,
  fecha em **5 fetchers** com argumentos no singular, deprecation
  abrupta, mirror rename in-place, cache migration automática,
  skeletons na v0.1.0.9000. Sem pendências residuais.

---

## 0. Sumário executivo

API pública pós-rename (v0.1.0.9000):

```r
issuer_fetch  (dataset, table, issuer   = NULL, year       = NULL, report_type = NULL, ...)
fund_fetch    (dataset, table, fund     = NULL, date       = NULL, ...)
agent_fetch   (dataset, table, agent    = NULL, as_of      = NULL, ...)
offering_fetch(dataset, table, offering = NULL, date_range = NULL, ...)
event_fetch   (dataset, table, event    = NULL, date_range = NULL, ...)
```

5 fetchers cobrindo os 18 grupos CKAN do portal CVM. Argumentos no
singular (tidyverse-canônico, aceitam vetor). Discovery permanece sob
prefixo `cvm_*` e ganha `cvm_groups()` + arg `group` opcional nas demais.

**`cvm_fetch()` e `cad_fetch()` removidos sem wrapper** em v0.1.0.9000
(deprecation abrupta — pacote pré-CRAN, sem usuários externos).

**Justificativa em uma frase**: os 18 grupos CVM colapsam em 5 contratos
de dado coerentes (issuer, fund, agent, offering, event) quando o
critério é tipo de chave de identidade + granularidade temporal +
caso de uso típico — e a fidelidade à CVM é régua sobre conteúdo,
não sobre forma da API.

**Custo de migração**: 5 sessões Claude Code, estimativa 22-30 h
total, distribuídas em 2-3 meses calendário.

---

## 1. Verificação empírica da taxonomia CVM (preservada do v1)

Conferido contra <https://dados.cvm.gov.br/group/> em 2026-05-25:
**18 grupos CKAN, 76 datasets**.

| # | Grupo CKAN (slug) | Datasets | Contrato |
|---|---|---|---|
| 1  | `administradores`                     | 2  | agent |
| 2  | `agentes-autonomos`                   | 1  | agent |
| 3  | `agentes-fiduciarios`                 | 1  | agent |
| 4  | `atividade-sancionadora`              | 1  | event |
| 5  | `atos-declaratorios`                  | 1  | event |
| 6  | `auditores`                           | 1  | agent |
| 7  | **`companhias`**                      | **12** | issuer |
| 8  | `consultores-de-valores-mobiliarios`  | 1  | agent |
| 9  | `coordenadores-de-ofertas`            | 1  | agent |
| 10 | `emissores-de-cepac`                  | 1  | issuer |
| 11 | **`fundos-de-investimento`**          | **22** | fund |
| 12 | `fundos-de-investimento-imobiliarios` | 4  | fund |
| 13 | **`fundos-estruturados`**             | **10** | fund |
| 14 | `investidores-nao-residentes`         | 1  | agent |
| 15 | `ofertas-publicas`                    | 2  | offering |
| 16 | `participantes-intermediarios`        | 1  | agent |
| 17 | `plataformas-de-crowdfunding`         | 1  | offering |
| 18 | `securitizadoras`                     | 4  | issuer |

Soma: 18 grupos, 76 datasets, **5 contratos**.

### 1.1 Mapping grupo → contrato (decisão final)

| Contrato | Grupos cobertos (n) | Datasets aprox. | Chave de identidade | Periodicidade |
|---|---|---|---|---|
| **issuer** | companhias, securitizadoras, emissores-de-cepac (3) | ~17 | CNPJ + denominação (+ CD_CVM para companhias) | Anual/Trimestral; `report_type ∈ {ind, con}` para contábeis |
| **fund** | fundos-de-investimento, fundos-de-investimento-imobiliarios, fundos-estruturados (3) | ~36 | CNPJ + nome do fundo + administrador | Mensal/Trimestral; sem `report_type` |
| **agent** | administradores, agentes-autonomos, agentes-fiduciarios, auditores, consultores-de-valores-mobiliarios, coordenadores-de-ofertas, participantes-intermediarios, investidores-nao-residentes (8) | ~10 | CPF ou CNPJ + nº registro | Cadastro estático / atualização periódica |
| **offering** | ofertas-publicas, plataformas-de-crowdfunding (2) | ~3 | `numero_oferta` + `data_oferta` | Ad-hoc por evento; ranges de data úteis |
| **event** | atividade-sancionadora, atos-declaratorios (2) | ~2 | ID de processo / ato + data | Ad-hoc por evento; ranges de data úteis |

### 1.2 Decisões fechadas na rodada 3 (issuer unificado, offering separado)

**`issuer_fetch()` unificado** (não split em `company_fetch` + `spe_fetch`):

- Régua: "issuer cobre toda empresa que emite valor mobiliário,
  incluindo companhias abertas". Aplicada com consistência.
- Contrato de dado é o mesmo: CNPJ + denominação + datas; `report_type`
  obrigatório para tabelas contábeis quando existem (ITR/DFP/FRE), 
  default `NULL` quando não existem (CAD, securitizadoras, CEPAC).
- Filtro `issuer`: aceita CNPJ, CD_CVM (quando aplicável), ou texto livre
  contra denominação.
- Split duplicaria lógica de filter-by-issuer (CNPJ detection, busca
  textual com expansão de abreviações, lookup CD_CVM → CNPJ via
  `submissao`); drift garantido em 12 meses.
- rOpenSci review: reviewer não tem como justificar duas funções com
  signature e semântica idênticas.

**`offering_fetch()` separado de `event_fetch()`**:

- Ofertas e eventos têm chaves de identidade e casos de uso diferentes.
- "Liste todas as IPOs de 2024" é caso de uso natural em
  finanças/research que merece signature dedicada.
- Crowdfunding (Res. CVM 88) é "oferta pública dispensada de registro,
  intermediada por plataforma" — semanticamente uma oferta.
- Atividade sancionadora e atos declaratórios têm casos de uso de
  auditoria/monitoramento regulatório — natureza diferente.

---

## 2. Análise das opções (preservada do v1, resumo)

Opções consideradas:

- **A** — `cvm_fetch(group, dataset, table, ...)` com `...` permissivo.
  Reprovou: red flag em rOpenSci, doc explode, erros tardios.
- **B** — Função por grupo CKAN (18 fetchers).
  Reprovou: duplicação entre grupos com contrato idêntico, 31 funções
  públicas no total, NAMESPACE acima da mediana.
- **C** — Híbrida (`cvm_fetch()` com dispatch interno por dataset único).
  Reprovou empiricamente: slugs CVM já são group-qualified
  (`fi-cad`, `cia_aberta-cad-cia_aberta`); colisões garantidas.
- **D** — B + cvm_* router. Pior de dois mundos.
- **E** — Síntese: fetcher por contrato de dado. **Adotada.**

Detalhe completo da análise no v1 do documento.

---

## 3. API pública resultante (final)

### 3.1 Fetchers (5)

```r
issuer_fetch(dataset, table,
             issuer      = NULL,
             year        = NULL,
             report_type = NULL,
             source      = NULL,
             on_error    = "abort",
             validate    = "strict",
             ...)

fund_fetch(dataset, table,
           fund     = NULL,
           date     = NULL,
           source   = NULL,
           on_error = "abort",
           validate = "strict",
           ...)

agent_fetch(dataset, table,
            agent    = NULL,
            as_of    = NULL,
            source   = NULL,
            on_error = "abort",
            validate = "strict",
            ...)

offering_fetch(dataset, table,
               offering   = NULL,
               date_range = NULL,
               source     = NULL,
               on_error   = "abort",
               validate   = "strict",
               ...)

event_fetch(dataset, table,
            event      = NULL,
            date_range = NULL,
            source     = NULL,
            on_error   = "abort",
            validate   = "strict",
            ...)
```

`...` em cada uma é **reservado para forward compatibility, não
permissivo**. Argumentos fora dos nomeados abortam.

### 3.2 Argumentos no singular — política

Decidido: todos os argumentos identificadores e temporais ficam no
**singular** apesar de aceitarem vetor de qualquer comprimento.

Padrão tidyverse-canônico: `dplyr::filter(.data, name == c("a","b"))`
aceita vetor; o nome do arg descreve o tipo do elemento, não a
cardinalidade. Sem efeito em ergonomia.

| Argumento | Aceita | Default | Semântica |
|---|---|---|---|
| `issuer` | CNPJ / CD_CVM / texto livre (vetor) | `NULL` (todos) | Detecção automática por elemento. |
| `fund` | CNPJ (vetor) | `NULL` (todos) | Sem texto livre por enquanto (denominação instável pós-Res. 175). Reavaliar em v0.5. |
| `agent` | CPF / CNPJ / texto (vetor) | `NULL` (todos) | Tipos aceitos variam por grupo: agentes autônomos só CPF; coordenadores só CNPJ; administradores aceitam todos. Validação dinâmica por dataset+table. |
| `offering` | `numero_oferta` string (vetor) | `NULL` (todos) | IDs de oferta específicos. |
| `event` | ID de processo/ato string (vetor) | `NULL` (todos) | IDs específicos. |
| `year` | integer (vetor) | `NULL` (último ano) | Default mantém semântica atual de `cvm_fetch()`. |
| `date` | `Date` (vetor) | `NULL` (último mês/data disponível) | Datas pontuais. |
| `date_range` | `Date` vetor de tamanho 2: `c(from, to)` | `NULL` (range completo) | Janela contínua. |
| `as_of` | `Date` escalar | `NULL` (cadastro mais recente) | Snapshot temporal. |
| `report_type` | `"ind"` / `"con"` / `NULL` | `NULL` | Obrigatório para tabelas contábeis com variantes; erro se passado a tabelas sem variantes. |

### 3.3 Semântica de `date` vs `date_range`

Para evitar ambiguidade (questão levantada por Sidney na rodada 3):

- **`date`** (em `fund_fetch`): "datas pontuais". Default `NULL` → último
  mês disponível. `date = as.Date("2024-03-31")` → exato. Vetor →
  meses específicos.
- **`date_range`** (em `offering_fetch`, `event_fetch`): "janela".
  Default `NULL` → range completo disponível. Vetor de tamanho 2 →
  janela `[from, to]`. Vetor de tamanho ≠ 2 aborta com
  `cvmdata_error_input`.

Naming consistente: `date` para pontual, `date_range` para janela.

### 3.4 Discovery (6, +1 nova)

```r
cvm_groups()
# → tibble (group, n_datasets, contract)
#   18 linhas, ordenadas alfabeticamente por group.

cvm_datasets(group = NULL)
# → tibble (group, conjunto_dados, n_tabelas, contract)
#   group = NULL retorna tudo; group = "<slug>" filtra.

cvm_tables(dataset, group = NULL)
# → tibble (tabela, group, conjunto_dados, n_campos)
#   group = NULL resolve por unicidade; aborta com lista se ambíguo.

cvm_dictionary(dataset, table, group = NULL)
cvm_codelist(dataset, table, column, group = NULL)
cvm_dataset_years(dataset, group = NULL)
# Idem regra de unicidade.
```

`group` opcional com default `NULL`: resolve por unicidade
`(dataset, table)`; aborta listando matches quando ambíguo. Ergonomia
atual preservada para companhias.

### 3.5 Cache (4) — preservadas

```r
cvm_cache_path()
cvm_cache_set_path(path)
cvm_cache_info()
cvm_cache_clear(what    = c("all", "raw", "parquet"),
                dataset = NULL,
                group   = NULL,
                year    = NULL,
                confirm = interactive())
```

### 3.6 Source (2) — preservadas

```r
cvm_source_get()
cvm_source_set(source)
```

### 3.7 Utilidades (2) — preservadas

```r
cnpj_clean(x)
cnpj_format(x)
```

Para v0.4+ avaliar `cpf_clean()` e `cpf_format()` (CPFs em `agent_fetch()`
para agentes autônomos).

### 3.8 Total de funções públicas

- 5 fetch + 6 discovery + 4 cache + 2 source + 2 util = **19 funções**

Comparável a `httr2` (~30), `readr` (~40), bem abaixo de `dplyr` (~70).
Adequado para um pacote com escopo "tidy API ao universo CVM".

### 3.9 Deprecation abrupta

`cvm_fetch()` e `cad_fetch()` são **removidos sem wrapper** em
v0.1.0.9000.

- Pacote não está no CRAN, zero usuários externos.
- v0.1.0 foi tagueada há horas — janela de breaking change limpa.
- Wrapper deprecated soft custaria 2 arquivos de código, 2 testes,
  poluição de exemplo em vignette, sem benefício real.

NEWS.md ganha entrada `⚠️ breaking` explicando o caminho de migração:

```
cvm_fetch(dataset, table, companies = X, years = Y, ...)
   ↓
issuer_fetch(dataset, table, issuer = X, year = Y, ...)

cad_fetch(...)
   ↓
issuer_fetch("cad", "companhias", ...)
```

---

## 4. Impacto em itens correlatos

### 4.1 API de descoberta

Vide §3.4. `cvm_groups()` novo; `group` opcional nas demais
funções de descoberta com default `NULL` e resolução por unicidade.

### 4.2 Cache layout

```
ANTES:  <cache>/raw/<dataset>/[<year>/]
DEPOIS: <cache>/raw/<group>/<dataset>/[<year>/]

ANTES:  <cache>/parquet/<dataset>/<table>/[report_type=R/]year=Y/...
DEPOIS: <cache>/parquet/<group>/<dataset>/<table>/[report_type=R/]year=Y/...
```

**Migração automática**: na primeira invocação de qualquer `*_fetch()`
pós-upgrade, helper interno `cache_migrate_v0_1_to_v0_2()` move
silenciosamente:

- `<cache>/raw/{cad,dfp,itr,fre}/` →
  `<cache>/raw/companhias/{cad,dfp,itr,fre}/`
- `<cache>/parquet/{cad,dfp,itr,fre}/` →
  `<cache>/parquet/companhias/{cad,dfp,itr,fre}/`

Idempotente. Log em
`tools::R_user_dir("cvmdata", "config")/cache_migrate_log.rds`.

Em caso de falha (arquivo conflitante, permissão), aborta com
`cvmdata_error_internal` e instrução para `cvm_cache_clear("all")`
manual + re-download.

### 4.3 Mirror GitHub Releases — rename in-place

```
ANTES:  mirror-cad-latest, mirror-dfp-latest, mirror-itr-latest, mirror-fre-latest
DEPOIS: mirror-companhias-cad-latest, mirror-companhias-dfp-latest, ...
```

**In-place** via GitHub API. Ferramenta: `gh release edit <tag> --tag <newtag>`
ou equivalente via REST API. Executado na **Sessão 08**, junto com
o deploy do código que lê o novo nome.

Razão: nenhum usuário externo na v0.1.0 ainda. Renomear é estritamente
mais limpo do que recriar.

Article `cache-and-mirror.Rmd` é atualizado no mesmo commit.

Workflow `etl-mirror.yaml` ganha matrix bidimensional `(group, dataset)`:

```yaml
strategy:
  fail-fast: false
  matrix:
    include:
      - { group: companhias, dataset: cad }
      - { group: companhias, dataset: dfp }
      - { group: companhias, dataset: itr }
      - { group: companhias, dataset: fre }
```

Scripts `inst/etl/0{1,2,2b,3}*.R` ganham CLI flag `--group`.

### 4.4 Schema YAML layout

```
ANTES:  inst/extdata/schemas/<dataset>/<table>.yaml
DEPOIS: inst/extdata/schemas/<group>/<dataset>/<table>.yaml
```

Migração via `git mv`:

```bash
git mv inst/extdata/schemas/cad inst/extdata/schemas/companhias/cad
git mv inst/extdata/schemas/dfp inst/extdata/schemas/companhias/dfp
git mv inst/extdata/schemas/itr inst/extdata/schemas/companhias/itr
git mv inst/extdata/schemas/fre inst/extdata/schemas/companhias/fre
```

`load_schema()` ganha parâmetro `group` (opcional com unicidade).

### 4.5 Snapshots dicionário e codelist

Ambos CSVs ganham coluna `group` como primeira coluna.

```
ANTES (dictionary): dataset, table, campo, campo_original, descricao, ...
DEPOIS:             group, dataset, table, campo, campo_original, descricao, ...

ANTES (codelist):   dataset, table, campo, value
DEPOIS:             group, dataset, table, campo, value
```

Chave composta passa de `(dataset, table, campo)` para
`(group, dataset, table, campo)`. Geradores em `data-raw/` atualizados;
populam `group = "companhias"` para os 4 datasets v0.1.

### 4.6 Atributos do tibble retornado

Adiciona `group`. Total passa de 5 para 6 atributos em inglês:

```r
attr(x, "source")          # "mirror" | "cvm"
attr(x, "fetched_at")      # POSIXct
attr(x, "group")           # "companhias" | "fundos-de-investimento" | ...
attr(x, "dataset")         # "dfp" | "balancete" | ...
attr(x, "table")           # "bpa" | "composicao_carteira" | ...
attr(x, "package_version") # "0.1.0.9000"
```

`print.cvm_tbl()` header curto:

```
# <cvm_tbl: dfp/bpa from companhias>
# Source: mirror  Fetched: 2026-05-25 14:23:11 UTC
# A tibble: 12,450 × 27
```

### 4.7 Classes de condição

Adições:

- `cvmdata_error_input_group` — grupo inválido ou
  `(group, dataset)` inválido.
- `cvmdata_error_input_ambiguous` — descoberta com `group = NULL`
  e dataset/table presente em múltiplos grupos.

Erros pré-existentes preservados.

**Removida**: `cvmdata_warn_deprecated` (não emitida em lugar nenhum —
deprecation é abrupta, sem wrapper).

### 4.8 Identificadores → character

Lista canônica global preservada em `R/util-csv-cvm.R`. Adições futuras:

- v0.4+: `cnpj_fundo`, `cnpj_administrador`
- v0.7+: `nr_processo`, `nr_oferta`, `nr_ato`, `cd_registro`

Não fragmentar por grupo. Identificadores podem aparecer em qualquer
tabela.

### 4.9 Testes e fixtures

```
ANTES:  tests/testthat/fixtures/dfp_cia_aberta_2024.zip
DEPOIS: tests/testthat/fixtures/companhias/dfp_cia_aberta_2024.zip
```

Mocks HTTP análogos: `_mocks/companhias/dfp/...`.

Testes existentes (~17 arquivos) atualizados em massa via sed para
chamar `issuer_fetch()` em vez de `cvm_fetch()`/`cad_fetch()`.

Testes novos para `fund_fetch()`, `agent_fetch()`, `offering_fetch()`,
`event_fetch()` esqueléticos: signature + dispatch + abort com
mensagem instrutiva.

### 4.10 Vignettes e articles

- `vignettes/cvmdata.Rmd` — intro genérica, exemplos com
  `issuer_fetch()`. Nota sobre universo multi-grupo no início.
- `vignettes/articles/issuer-fetch.Rmd` — renomeação de
  `cvm-fetch.Rmd`, foco em issuers (companhias + securitizadoras +
  CEPAC).
- `vignettes/articles/itr-dfp.Rmd` — preservado, atualiza para
  `issuer_fetch()`.
- `vignettes/articles/fre.Rmd` — preservado.
- `vignettes/articles/cvm-defects.Rmd` — renomeado para
  `data-defects.Rmd`.
- `vignettes/articles/cache-and-mirror.Rmd` — atualiza layout L1/L3
  para incluir `<group>`; URLs de mirror releases para
  `mirror-companhias-<dataset>-latest`.
- `vignettes/articles/groups-overview.Rmd` — **novo**. Lista 18
  grupos, mapeia para 5 contratos, dá exemplo de chamada para cada
  fetcher. Funcionando inicialmente só para `issuer` (companhias);
  os outros 4 contratos teaser com "available in v0.4+".

Pkgdown navbar reorganizado em árvore por contrato (vide v1 §5.12
do documento anterior; estrutura idêntica).

---

## 5. Migration plan v0.1.0.9000 → v0.2.0

5 sessões Claude Code em ordem. Cada uma deixa
`devtools::check() == 0E/0W/0N`, lint clean, cobertura ≥ 90%.

### 5.1 Sessão 04 — Cache layout migration

**Escopo**:

- Adicionar `cache_migrate_v0_1_to_v0_2()` interno (não exportado).
- Atualizar `R/cache.R`, `R/source-cvm-http.R`,
  `R/source-mirror-duckdb.R` para usar
  `<cache>/raw/<group>/<dataset>/` e
  `<cache>/parquet/<group>/<dataset>/`.
- Atualizar `cvm_cache_info()` para reportar `group`.
- `cvm_cache_clear()` ganha `group = NULL`.
- Tests de migração: cache vazio, cache antigo, cache misto,
  arquivo conflitante.

**Estimativa**: 4-5 h.

### 5.2 Sessão 05 — Schemas + dictionary/codelist migration

**Escopo**:

- `git mv inst/extdata/schemas/{cad,dfp,itr,fre}/` →
  `inst/extdata/schemas/companhias/{cad,dfp,itr,fre}/`.
- `load_schema()` aceita `group` com unicidade.
- Re-gerar `cvm_dictionary_snapshot.csv` e
  `cvm_codelists_snapshot.csv` com coluna `group`.
- `cvm_dictionary()`, `cvm_codelist()` aceitam `group`.
- Tests de regressão.

**Estimativa**: 4-6 h.

### 5.3 Sessão 06 — Rename + deprecation abrupta + argumentos no singular

**Escopo**:

- Renomear `R/api-cvm-fetch.R` → `R/api-issuer-fetch.R`.
- Renomear `cvm_fetch_internal()` → `issuer_fetch_internal()`.
- Renomear `cvm_fetch()` → `issuer_fetch()`.
- **Renomear argumentos para singular**:
  - `companies` → `issuer`
  - `years` → `year`
- **Remover** `cvm_fetch()` e `cad_fetch()` (sem wrapper).
- Atualizar todos os exemplos roxygen.
- Atualizar `vignettes/cvmdata.Rmd` e todos os articles.
- Atualizar todos os testes (`grep -rl "cvm_fetch\|cad_fetch" tests/ R/`
  + sed).
- `NEWS.md` com entrada `⚠️ breaking`.
- Tests cobrindo o rename + arg singular.

**Estimativa**: 6-8 h. Gargalo: vignettes e articles.

### 5.4 Sessão 07 — Esqueletos dos 4 fetchers restantes

**Escopo**:

- Criar `R/api-fund-fetch.R`, `R/api-agent-fetch.R`,
  `R/api-offering-fetch.R`, `R/api-event-fetch.R` com signature
  canônica + corpo que aborta com `cvmdata_error_input_group`
  ("group X not yet implemented in v0.1.0.9000; see ROADMAP.md").
- Tests de signature + dispatch + abort previsto.
- Documentação roxygen completa, com `@examples` marcados
  `@examplesIf FALSE` (não executáveis até implementação real).
- Atualizar `_pkgdown.yml` para listar as 5 funções em Reference,
  com nota sobre o estado de cada.

**Razão**: rOpenSci review recebe a v0.2 ou v0.3 e vê a API completa.
Skeleton sem implementação documenta intenção e ancora arquitetura.

**Estimativa**: 3-4 h.

### 5.5 Sessão 08 — Discovery + cvm_groups() + ETL release rename

**Escopo**:

- Adicionar `R/api-cvm-groups.R` com `cvm_groups()` lendo do
  snapshot embarcado.
- Adicionar `group` em `cvm_datasets()`, `cvm_tables()`,
  `cvm_dictionary()`, `cvm_codelist()`, `cvm_dataset_years()`.
- Atualizar `etl-mirror.yaml` para matrix bidimensional
  `(group, dataset)`.
- Atualizar `inst/etl/03-publish.R` para nomear releases
  `mirror-<group>-<dataset>-latest`.
- **Renomear** os 4 releases atuais via GitHub API (in-place).
- Atualizar article `cache-and-mirror.Rmd` para citar novo formato.
- Atualizar vignette intro com cobertura por grupo.

**Estimativa**: 5-7 h. Gargalo: rename de releases (manual, com cuidado).

### 5.6 Total

22-30 horas de Claude Code distribuídas em 5 sessões. Mantenedor
solo em tempo parcial → 2-3 semanas calendário.

Estado pós-Sessão 08:

- 5 fetchers exportados (1 funcional, 4 com skeleton).
- 18 grupos listáveis via `cvm_groups()`.
- Cache, schemas, snapshots, mirror — todos `<group>`-aware.
- `cvm_fetch()` e `cad_fetch()` removidos.
- pkgdown atualizado.

Pronto para submissão rOpenSci.

---

## 6. Atualização do rOpenSci pre-submission inquiry

Draft em `data-raw/rOpenSci-presubmission-draft.md` descartado. Reescrito
do zero pós-Sessão 08.

Esqueleto:

```markdown
# cvmdata: tidy access to Brazilian CVM open data

## Scope

`cvmdata` provides a tidy R API to data published by the Brazilian
Securities and Exchange Commission (CVM). The CVM Open Data Portal
organizes 76 datasets into 18 thematic groups; `cvmdata` exposes
these via five fetchers (`issuer_fetch()`, `fund_fetch()`,
`agent_fetch()`, `offering_fetch()`, `event_fetch()`) corresponding
to five data contracts.

v0.1 covers four datasets from the **companhias** group
(`cad`, `dfp`, `itr`, `fre`). Subsequent releases extend coverage
incrementally:

- v0.2: rest of `companhias` (8 datasets)
- v0.3: foreign and incentivized issuers (estrangeiras, incentivadas)
- v0.4: `fundos-de-investimento` (22 datasets)
- v0.5: `fundos-de-investimento-imobiliarios`
- v0.6: `fundos-estruturados`
- v0.7+: remaining 11 groups under `agent_fetch()`,
  `offering_fetch()` and `event_fetch()`

## Statement of need

[Adaptação do draft anterior, com escopo de longo prazo
"todo o universo CVM" e v0.1 = companhias.]

## API

Five fetch functions, six discovery functions, four cache functions,
two source functions, two utility functions. Full reference at
<https://sidneybissoli.github.io/cvmdata/reference/>.

## Comparison with related work

[GetDFPData2 e rb3, como no draft anterior.]

## Quality assurance

[Cobertura, CI, mirror parquet, lint, etc.]
```

**Submissão**: após Sessão 08. Antes disso, reviewer leria com
`cvm_fetch()` em circulação e gastaria review budget perguntando por
que API foi planejada com escopo amplo. Esperar 5 sessões compensa.

---

## 7. Atualizações documentais (resumo)

### 7.1 `CLAUDE.md`

**§2 reescreve**:

- Remove banner "⚠️ Decisão arquitetural em aberto".
- Adiciona "API por contrato de dado" com tabela `(grupo, contrato)`.
- Lista atualizada de funções públicas em §2.1.
- Naming convention: prefixos `<contract>_` para fetch
  (`issuer_`, `fund_`, `agent_`, `offering_`, `event_`);
  `cvm_*` para descoberta, cache, source, util.
- Política de argumentos no singular documentada.

**§4 estrutura de diretórios**:

```
R/
├── api-issuer-fetch.R       (rename de api-cvm-fetch.R)
├── api-fund-fetch.R         (novo, skeleton)
├── api-agent-fetch.R        (novo, skeleton)
├── api-offering-fetch.R     (novo, skeleton)
├── api-event-fetch.R        (novo, skeleton)
├── api-cvm-groups.R         (novo, lista grupos)
├── discovery.R              (atualizado com group=)
├── ...                      (resto preservado; api-cad-fetch.R removido)
```

**§9 snapshots** atualiza para incluir coluna `group`.

**§10 cache** atualiza layout para
`<cache>/raw/<group>/<dataset>/...`.

**§12 workflow** atualiza para Sessões 04-08 entregues.

### 7.2 `README.md` / `README.pt-BR.md`

- "Quick start" atualizado para `issuer_fetch()` com argumentos no
  singular.
- Parágrafo "Coverage" listando estado atual e roadmap por grupos.
- Seção "Documentation" listando 5 famílias de fetch.

### 7.3 `NEWS.md`

```markdown
# cvmdata 0.1.0.9000 (in development)

## Breaking changes

* `cvm_fetch()` has been renamed `issuer_fetch()` and its arguments
  renamed to singular form for tidyverse-canonical naming:
  - `companies` → `issuer`
  - `years` → `year`
  Migration is mechanical: replace `cvm_fetch(companies = X, years = Y, ...)`
  with `issuer_fetch(issuer = X, year = Y, ...)`. The new singular
  arguments still accept vectors of any length.

* `cad_fetch()` removed without wrapper. Use
  `issuer_fetch("cad", "companhias", ...)` instead.

* Four new fetchers exported with skeleton implementation:
  `fund_fetch()`, `agent_fetch()`, `offering_fetch()`,
  `event_fetch()`. Full implementation arrives in v0.4+. Calling
  these on v0.1.0.9000 aborts with `cvmdata_error_input_group` and
  a pointer to ROADMAP.md.

* Cache layout migrated from `<cache>/raw/<dataset>/` to
  `<cache>/raw/<group>/<dataset>/`. A one-time internal migration
  runs automatically on first invocation post-upgrade.

* The four `mirror-<dataset>-latest` GitHub Releases have been
  renamed in-place to `mirror-companhias-<dataset>-latest`.

* Schema YAML files moved from
  `inst/extdata/schemas/<dataset>/<table>.yaml` to
  `inst/extdata/schemas/<group>/<dataset>/<table>.yaml`.

* `cvm_dictionary_snapshot.csv` and `cvm_codelists_snapshot.csv`
  gained a `group` column as first key column.

* Returned tibbles now carry a `group` provenance attribute.

## New features

* `cvm_groups()` lists the 18 CVM CKAN groups with their dataset
  counts and the canonical fetcher for each.
* `cvm_datasets()`, `cvm_tables()`, `cvm_dictionary()`,
  `cvm_codelist()` and `cvm_dataset_years()` gained an optional
  `group` argument. When omitted, the functions resolve by
  uniqueness; ambiguous cases abort with a listing of matches.
```

### 7.4 `ROADMAP.md`

- Marca v0.1.0 como entregue.
- Sub-seção nova **"v0.1.0.9000 — architectural migration"** com
  Sessões 04-08.
- Atualiza v0.2+ refletindo nova nomenclatura.
- Pendência rOpenSci marcada "deferida até pós-Sessão 08".

---

## 8. Sketch de cronograma

```
2026-06  Sessão 04 (cache migration)
2026-06  Sessão 05 (schemas + snapshots)
2026-07  Sessão 06 (rename + deprecation + singular args)
2026-07  Sessão 07 (4 skeletons)
2026-08  Sessão 08 (discovery + cvm_groups + ETL rename in-place)
2026-08  Pre-submission inquiry rOpenSci
2026-09  rOpenSci review (4-12 semanas típico)
2026-11  Aceitação rOpenSci (otimista)
2026-12  Submissão CRAN
2027-Q1  v0.2.0 (companhias parte 2)
2027-Q2  v0.3.0 (companhias parte 3 — estrangeiras + incentivadas)
2027-Q3  v0.4.0 (fundos-de-investimento, 22 datasets — gargalo)
2027-Q4  v0.5.0 (FII)
2028-Q1  v0.6.0 (fundos estruturados)
2028-Q2  v0.7.0 (agent_fetch + offering_fetch + event_fetch full)
2028-Q3  v1.0.0 (estabilização + The R Journal)
```

Caminho crítico: v0.4.0 (22 datasets de fundos). Pode quebrar em
v0.4.1 → v0.4.9 conforme cada dataset entra.

---

## 9. Riscos e contingências

### 9.1 Cache migration falha em estado misto

**Risco**: usuário tem cache parcial; migração para no meio.

**Mitigação**:

- Helper idempotente com `try-recover` por arquivo.
- Log em `tools::R_user_dir("cvmdata", "config")/cache_migrate_log.rds`.
- Em caso de falha, aborta com instrução `cvm_cache_clear("all")` +
  re-download.
- Test coverage explícita do caminho de falha.

### 9.2 GitHub release rename in-place falha parcialmente

**Risco**: 2 dos 4 releases renomeiam, 2 falham. Estado misto.

**Mitigação**:

- Script de rename roda em transação manual com checkpoint após cada
  rename.
- Em caso de falha, rollback: renomear de volta os já-renomeados.
- Documentar comandos exatos no commit message da Sessão 08.
- Após confirmação visual no GitHub UI, atualizar código no mesmo
  commit.

### 9.3 rOpenSci reviewer questiona escolha de 5 fetchers

**Risco**: reviewer prefere unificação (Opção A) ou fragmentação por
grupo (Opção B).

**Mitigação**:

- Documento de submissão argumenta explicitamente a decisão de 5
  contratos, citando os 18 grupos e a coalescência empírica em 5
  chaves de identidade.
- Tabela `(group, contract)` no apêndice da submissão.
- Discussão pública no GitHub via `data-raw/rOpenSci-architecture-rationale.md`
  para reviewer poder se referir.

### 9.4 Argumentos no singular criam estranhamento

**Risco**: usuário familiar com `dplyr` aceita; usuário vindo de
`GetDFPData2` ou Python `pandas` pode estranhar `year = 2018:2024`
quando esperaria `years`.

**Mitigação**:

- Roxygen `@param` explícito: "Integer vector (singular naming
  follows tidyverse conventions)".
- Exemplos em vignette mostram passagem de vetor com `year =`.
- Sem mitigação ativa de comportamento — é decisão de naming
  consciente.

### 9.5 Decisão da Rodada 1 nominalmente em conflito

**Risco**: decisão "Padrão C híbrido" da Rodada 1 está em conflito
com a recomendação atual (5 fetchers por contrato).

**Mitigação**:

- Sidney aceitou a reabertura em rodada 2 do plan-mode.
- Evidência nova: verificação empírica dos 18 grupos × 76 datasets
  + colisão de slugs entre grupos.
- Atualizar `cvmdata_rodada1_fechamento.md` com nota anexa
  registrando a sobreposição desta decisão.

---

## 10. Decisões fechadas (sem pendência residual)

Tudo abaixo está fechado pós-rodada 3:

| Item | Decisão final |
|---|---|
| **Fetcher principal** | `issuer_fetch()` (unificado, cobre companhias + securitizadoras + CEPAC) |
| **Fetcher de fundos** | `fund_fetch()` (cobre 3 grupos) |
| **Fetcher de partes** | `agent_fetch()` (cobre 8 grupos) |
| **Fetcher de ofertas** | `offering_fetch()` (separado, cobre ofertas-publicas + plataformas-de-crowdfunding) |
| **Fetcher de eventos** | `event_fetch()` (cobre atividade-sancionadora + atos-declaratorios) |
| **Argumentos identificadores** | Singular (`issuer`, `fund`, `agent`, `offering`, `event`) |
| **Argumentos temporais pontuais** | Singular (`year`, `date`, `as_of`) |
| **Argumento temporal de janela** | `date_range` (distinto de `date` para evitar ambiguidade) |
| **`cvm_fetch()`** | Removida sem wrapper em v0.1.0.9000 |
| **`cad_fetch()`** | Removida sem wrapper em v0.1.0.9000 |
| **Cache migration** | Automática + silenciosa no primeiro `*_fetch()` pós-upgrade |
| **Mirror release rename** | In-place via GitHub API |
| **Skeletons dos 4 fetchers não-issuer** | Exportados em v0.1.0.9000 com abort instrutivo |
| **Mapping grupo → contrato** | Tabela §1.1 (5 contratos cobrem 18 grupos) |
| **`cvm_groups()` nova** | Sim, listando os 18 grupos |
| **Coluna `group` em snapshots** | Sim, como primeira coluna em ambos |
| **Atributo `group` em tibble retornado** | Sim, totalizando 6 atributos |
| **Ordem das sessões** | 04 → 05 → 06 → 07 → 08, sem pulos |

---

## 11. Resumo: 1 página

- **Decisão**: 5 fetchers por contrato de dado
  (`issuer_fetch`, `fund_fetch`, `agent_fetch`, `offering_fetch`,
  `event_fetch`), cobrindo os 18 grupos CKAN do portal CVM.
  Argumentos no singular. `cvm_fetch()` e `cad_fetch()` removidos
  sem wrapper em v0.1.0.9000.

- **Por quê**: Opção A (`...` permissivo) e Opção C (dataset
  globalmente único — impossível pelos slugs CVM) reprovam em
  rOpenSci review. Opção B pura (18 funções) duplica código. Síntese
  por contrato de dado equilibra ergonomia, fidelidade, manutenibilidade.

- **Como**: 5 sessões Claude Code em ordem
  (cache → schemas/snapshots → rename → skeletons → discovery+ETL).
  Estimativa 22-30 h total.

- **Quando**: 2026-06 a 2026-08. Submissão rOpenSci em 2026-08.
  CRAN previsto Q4 2026.

- **Pendências**: **nenhuma.** Documento serve como input direto
  para a próxima sessão Claude Code (Sessão 04, cache migration).

Fim do documento.
