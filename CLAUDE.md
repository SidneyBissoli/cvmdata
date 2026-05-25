# CLAUDE.md — Contexto persistente do pacote cvmdata

Documento de referência para sessões do Claude Code no diretório
`C:/Users/SIDNEY/OneDrive/programacao/R/packages/cvmdata`. Consolida o
essencial de sete documentos canônicos da fase de planejamento (Rodadas
1, 2, 2.5, 2.6, 3.0, 3.0.2, 3.1) para que sessões futuras não precisem
reler tudo. Quando este `CLAUDE.md` divergir de um documento canônico,
**prevalece o canônico** — em particular
`cvmdata_rodada2-5_naming_unificado-v03.md` para naming,
`cvmdata_rodada3-0-2_politica_reader_sem_meta.md` para política do
reader, e `cvmdata_rodada3-1_sessao_01_scaffolding_cad_fetch.md` para o
estado pós-Sessão 01. Estado de execução por fase no `ROADMAP.md`.

Comunicação com Sidney é em **português brasileiro**. Tom direto,
técnico, sem fluff, sem puxa-saquismo. Quando ele perguntar problemas,
dizer diretamente; se não houver, dizer isso. Críticas construtivas
bem-vindas. Em decisões arquiteturais relevantes não fechadas nos
canônicos: apresentar 2-3 alternativas com prós/contras e recomendar
uma.

------------------------------------------------------------------------

## 1. Régua de idioma

Princípio reitor:

> **Se vem da CVM, fica como na CVM** (apenas normalização tipográfica
> para snake_case minúsculo quando o original está em
> SCREAMING_SNAKE_CASE). **Se não vem da CVM, é decisão do pacote.**

Distribuição:

| Categoria | Idioma |
|----|----|
| Nomes de função (públicas e internas) | **Inglês** |
| Nomes de argumento de função | **Inglês** |
| Atributos do tibble retornado | **Inglês** (`source`, `fetched_at`, `dataset`, `table`, `package_version`) |
| Classes de condição | **Inglês** (`cvmdata_error_*`, `cvmdata_warn_*`) |
| Options e env vars | **Inglês** (`cvmdata.verbosity`, `CVMDATA_VERBOSITY`) |
| Nomes de arquivo e pasta no projeto | **Inglês** |
| Comentários em código | **Inglês** |
| README.md, NEWS.md, DESCRIPTION, roxygen | **Inglês** |
| Mensagens de erro/warning emitidas por funções | **Inglês** (via `cli::cli_*`) |
| Workflows GitHub Actions e comentários YAML | **Inglês** |
| **Nomes de tabelas** do pacote | **Português** (snake_case, fiel à CVM) |
| **Nomes de colunas** nos tibbles retornados | **Português** (snake_case, fiel à CVM) |
| Colunas-meta de funções de descoberta | **Português** (`conjunto_dados`, `n_tabelas`, `tabela`, `campo`, `descricao`, `tipo_dados`, `dominio`, `tamanho`, `precisao`, `scale`) |
| Valores em células categóricas | **Português** (como vem da CVM) |
| Texto livre em colunas descritivas | **Português** (como vem da CVM) |
| Documentos de planejamento | **Português** |

Caveat: a palavra `dataset` permanece em inglês como argumento de função
(palavra técnica internacionalizada); a coluna paralela em
[`cvm_datasets()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_datasets.md)
chama-se `conjunto_dados` em PT. Mismatch deliberado.

------------------------------------------------------------------------

## 2. Naming canônico (resumo do naming doc v03)

### 2.1 Funções públicas

Padrão `object_verb` (Dev Guide rOpenSci).
**[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
é a API principal para obtenção de dados de qualquer dataset.** Aliases
tipados por dataset *não* são exportados —
[`cad_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cad_fetch.md)
permanece apenas por ergonomia da Sessão 01 (CAD = caso simples sem ZIP,
sem variantes), e internamente delega para
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md).
**Decisão tomada em 2026-05-20** depois que comparação empírica entre
dois caminhos de download mostrou que o portal de dados abertos
(`dados.cvm.gov.br`) entrega TODOS os dados que o portal RAD/ENET por
documento entrega, em formato tabular muito mais conveniente e 30× mais
rápido (~0,93 s o ZIP anual inteiro contra ~30 s por documento
individual). Vide `cvmdata_rodada3-1_*.md` e o histórico desta sessão.

``` r

# API principal — funciona para qualquer (dataset, table)
cvm_fetch(dataset, table,
          companies   = NULL,
          years       = NULL,
          source      = NULL,   # default resolvido via cvm_source_get()
          report_type = NULL,
          on_error    = "abort",
          validate    = "strict",
          ...)

# Alias mantido (Sessão 01) — internamente delega para cvm_fetch()
cad_fetch(companies = NULL, ...)

# Descoberta
cvm_datasets()                       # lista de datasets disponíveis
cvm_tables(dataset)                  # tabelas de um dataset
cvm_dictionary(dataset, table)       # dicionário oficial do snapshot
cvm_codelist(dataset, table, column) # valores categóricos do snapshot
cvm_dataset_years(dataset)           # range de anos com dados publicados

# Cache
cvm_cache_path()
cvm_cache_set_path(path)
cvm_cache_clear(what = c("all", "raw", "parquet"), dataset = NULL,
                year = NULL, confirm = interactive())
cvm_cache_info()

# Source
cvm_source_get()
cvm_source_set(source)

# Utilidades
cnpj_clean(x)                 # exportada na v0.1
cnpj_format(x)                # inverso de cnpj_clean — formata 14 dígitos
```

Domínio dos argumentos enumerados (validados via
[`rlang::arg_match0()`](https://rlang.r-lib.org/reference/arg_match.html)):

- `source ∈ c("mirror", "cvm")`. **Default a partir de v0.1.0 =
  `"mirror"`** (commit isolado do flip executado na sessão do marco,
  marcado ⚠️ breaking em `NEWS.md`). Backend mirror lê parquets do
  release `mirror-<dataset>-latest` via API GitHub (inventário cacheado
  por sessão) + DuckDB local. Pipeline: filter pushdown manual por nome
  de asset (years/report_type extraídos do encoding
  `<table>__report_type=R__year=Y__part-0.parquet`, com a sanitização
  `=` → `.` aplicada pelo GitHub Releases) → download para L3 em
  `<cache>/parquet/<dataset>/<table>/[report_type=R/] year=Y/part-0.parquet`
  → DuckDB lê local → reattach de `year`/`report_type` como colunas
  regulares no tibble (Decisão 2 da 3.13 = Alt 1). Cache L3 é invalidado
  por hash via sidecar `<cache>/parquet/<dataset>/__source_hash.json`,
  confrontado contra o asset homônimo do release; quando o hash muda, o
  L3 inteiro do dataset é evicted antes da próxima leitura. Backend
  `"cvm"` (portal aberto via HTTP em `dados.cvm.gov.br`) permanece
  totalmente suportado e selecionável por chamada (`source = "cvm"`) ou
  via `cvm_source_set("cvm")` quando se precisa de frescor byte a byte
  contra o regulador. A precedência é: arg explícito \>
  `getOption("cvmdata.source")` \> built-in default. **Decisão tomada na
  Sessão 3.6** (2026-05-22): Alt 2 do trio
  default-mirror/default-cvm/auto-fallback — declarar default mirror em
  v0.1 antes do release deixaria o pacote inutilizável out-of-the-box;
  com mirror já depositado em GitHub Releases, default natural por ser
  ~30× mais rápido. A “quebra de reprodutibilidade” do flip é
  controlável via `cvm_source_set("cvm")` e pelo atributo `source` que o
  tibble já carrega via `cvm_attach_metadata()`. A assinatura pública de
  [`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
  declara `source = NULL` para que o option seja consultado
  dinamicamente — alinhamento com o padrão da família cache
  ([`cvm_cache_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_path.md)
  ↔︎
  [`cvm_cache_set_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_set_path.md)).
- `validate ∈ c("strict", "warn", "skip")`, default `"strict"`.
- `on_error ∈ c("abort", "warn", "silent")`, default `"abort"`.
- `report_type ∈ c("ind", "con")` ou `NULL`. **Obrigatório** para
  tabelas que têm variantes individual/consolidada (`bpa`, `bpp`, `dre`,
  `dra`, `dfc_md`, `dfc_mi`, `dmpl`, `dva`). **Erro** se passado a
  tabelas que não têm essa distinção (`composicao_capital`, `submissao`,
  `parecer`).
- `years`: integer vector ou `NULL`. `NULL` (default) → **último ano
  disponível**, descoberto por `HEAD` probing decrescente a partir do
  ano corrente. Para histórico, passar integer vector explícito
  (`years = 2012:2024`). O helper `cvm_dataset_years(dataset)` devolve o
  range disponível para enumeração. **Sem sentinela `"all"`** —
  argumento permanece com tipo único (integer), evita observação de
  type-mixing em review rOpenSci/CRAN.

Sobre exercícios contidos em cada CSV anual: o portal CVM publica em
cada ano apenas `ORDEM_EXERC ∈ {ÚLTIMO, PENÚLTIMO}` — i.e., o ano
declarado e seu N-1. O antepenúltimo do ano N é o último do ano N-2.
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
não tenta reconstruir o antepenúltimo: retorna o conteúdo literal do CSV
declarado em `years`. Usuários que queiram histórico mais longo pedem
`years = (N-2):N` e empilham; a deduplicação por
`(cd_cvm, cd_conta, dt_fim_exerc)` é trivial.

### 2.2 Colunas-chave universais (CAD + ITR + DFP + FRE-header)

| Coluna | Tipo | Origem CVM | Notas |
|----|----|----|----|
| `cnpj_cia` | character | CNPJ_CIA | **Com pontuação** como vem da CVM |
| `cd_cvm` | character | CD_CVM | Sempre character; ITR é zero-padded, CAD não — character preserva ambos |
| `denom_cia` | character | DENOM_CIA | — |
| `dt_refer` | Date | DT_REFER | Conversão automática via dicionário |
| `versao` | character | VERSAO | Identificador → character |

FRE-detail usa convenção diferente: `cnpj_companhia`, `data_referencia`,
`nome_companhia`, `versao`, `id_documento`. **Sem `cd_cvm`**.
Preservação estrita; joins exigem mapeamento explícito do usuário.

### 2.3 Submissão (header de ITR/DFP/FRE)

Tabela de cabeçalho dos três datasets chama-se `submissao` (decisão
travada na Rodada 3.0). 9 campos: `cnpj_cia`, `dt_refer`, `versao`,
`denom_cia`, `cd_cvm`, `categ_doc`, `id_doc`, `dt_receb`, `link_doc`.

### 2.4 Regra dos identificadores → character

Campos identificadores (CNPJ, CD_CVM, CEP, telefones, CPF, ID_Documento)
são forçados a **character** mesmo quando o META declara `numeric`. O
META da CVM declara mal — CEPs perdem zero à esquerda, CD_CVM tem
padding heterogêneo entre datasets, etc. Lista canônica no reader:
`c("cnpj_cia", "cd_cvm", "cep", "tel", "ddd_*", "cpf", "id_documento", "cnpj_companhia")`.

### 2.5 Datas

Conversão de string para `Date` é **automática** sempre que o snapshot
de dicionário declarar `tipo_dados = "date"`. `convert_to_date` foi
removido do domínio aceito em `transformations:`.

### 2.6 vl_conta × escala_moeda

Em tabelas ITR/DFP contábeis: `VL_CONTA` é multiplicada por
`ESCALA_MOEDA` (`UNIDADE`=1, `MIL`=1e3, `MILHÃO`=1e6, `BILHÃO`=1e9) e
retornada em reais absolutos. `escala_moeda` é removida do tibble;
`moeda` mantida (constante `"REAL"` na v0.1).

### 2.7 Seleção de companhias via `companies`

Argumento único com **detecção automática de tipo**:

| Padrão do input (após [`as.character()`](https://rdrr.io/r/base/character.html)) | Interpretação | Match contra |
|----|----|----|
| `^[0-9]{14}$` | CNPJ sem pontuação | `cnpj_clean(cnpj_cia)` |
| Contém `.` ou `/` ou `-` e tem 14 dígitos | CNPJ com pontuação | `cnpj_cia` literal e/ou `cnpj_clean(cnpj_cia)` |
| `^[0-9]{1,6}$` | CD_CVM | `cd_cvm` (com ou sem zero-padding); se a tabela alvo não tem `cd_cvm`, resolve para CNPJ via `submissao` (vide abaixo) |
| Resto (≥1 token alfabético) | Busca textual | `denom_cia` |

**Resolução CD_CVM → CNPJ via submissao** (decisão hotfix pós-Sessão 03,
2026-05-21): quando o usuário passa CD_CVM contra uma tabela que não
carrega `cd_cvm` (`composicao_capital`, `parecer` em DFP/ITR; e
provavelmente várias FRE-detail no futuro), o pipeline lê a `submissao`
do mesmo dataset/year (já no mesmo ZIP anual, custo extra mínimo) e faz
lookup CD_CVM → CNPJ antes de aplicar o filtro. CD_CVMs ausentes na
`submissao` daquele ano abortam com `cvmdata_error_input`. Caso o
dataset não publique uma tabela `submissao` (não acontece para
ITR/DFP/FRE; pode acontecer para datasets v0.2+), aborta com mensagem
instruindo o uso de CNPJ ou texto. O caminho silencioso anterior
(retornar tibble vazio sem aviso) foi removido. Para regressão zero:
tabelas com `cd_cvm` nativo (`bpa`, `bpp`, etc.) continuam usando o
filtro direto, sem o lookup adicional.

Busca textual: tokeniza o input por espaços, normaliza (uppercase, sem
acentos, sem pontuação), aplica **mapa de abreviações** conhecidas
(`BANCO ↔︎ BCO`, `COMPANHIA ↔︎ CIA`, `S.A. ↔︎ S/A`, e outras a fechar
quando enumerarmos `denom_cia` real), e exige que **todos os tokens**
casem em `denom_cia` normalizada com **fronteira de palavra** (regex
`\bTOKEN\b`). Exemplos:

``` r

cvm_fetch("dfp", "bpa", companies = "banco brasil")
# Tokens: "banco" + "brasil"
# Expande: ("banco"|"bco") AND ("brasil")
# Casa: "BCO BRASIL S.A." (cd_cvm 001023)
# Não casa: "BCO BRASILEIRO DE DESCONTOS" (token "brasileiro" != "brasil")
```

Multiplas matches:

- Modo interativo
  ([`interactive()`](https://rdrr.io/r/base/interactive.html)): exibe
  lista numerada e pede ao usuário escolher (via
  [`utils::menu()`](https://rdrr.io/r/utils/menu.html) ou similar).
  `Esc` aborta com `cvmdata_error_input`.
- Modo não-interativo (CI/batch/scripts): aborta com
  `cvmdata_error_input` listando todas as matches e instruindo o usuário
  a passar CD_CVM ou CNPJ.

Zero matches: aborta com `cvmdata_error_input` (“nenhuma companhia casa
com `{input}`”).

Política de versão: por default, mantém apenas o registro de maior
`VERSAO` por `(cnpj_cia, dt_refer)`. Implementado via transformação
canônica `keep_latest_version` no YAML. Para histórico de versões, ver
roadmap v0.2+.

------------------------------------------------------------------------

## 3. Convenções de código R

- Pipe: `|>` (nunca `%>%`). `R (>= 4.1)` no `Depends`.
- Strings: aspas duplas por padrão;
  [`stringr::str_c()`](https://stringr.tidyverse.org/reference/str_c.html)
  em vez de
  [`paste()`](https://rdrr.io/r/base/paste.html)/[`paste0()`](https://rdrr.io/r/base/paste.html).
- Indentação 2 espaços, sem tabs.
- Largura máxima 80 chars (tolerância até 100).
- Style guide: tidyverse.
- Lint clean
  ([`lintr::lint_package()`](https://lintr.r-lib.org/reference/lint.html)
  retorna `character(0)`) antes de qualquer commit.
- **Fully-qualified namespaces** em todo código
  ([`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html),
  [`readr::read_delim()`](https://readr.tidyverse.org/reference/read_delim.html)).
  Exceção em pipelines longos com `@importFrom` no roxygen.
- Toda função exportada tem bloco roxygen completo: `@title`,
  `@description`, `@param`, `@return`, `@examples`, `@export`, `@family`
  (quando apropriado), `@seealso`.
- Mensagens via
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html) /
  [`cli::cli_warn()`](https://cli.r-lib.org/reference/cli_abort.html) /
  [`cli::cli_inform()`](https://cli.r-lib.org/reference/cli_abort.html).
  **Nunca** [`print()`](https://rdrr.io/r/base/print.html) ou
  [`cat()`](https://rdrr.io/r/base/cat.html) fora de métodos
  `print.*`/`str.*`.
- Estilo cli: `{.fn nome_funcao}`, `{.val "valor"}`, `{.var nome_var}`;
  símbolos `x` (erro), `i` (info), `!` (warn), `v` (sucesso).

------------------------------------------------------------------------

## 4. Estrutura de diretórios

**Régua R/ é flat** (travada na Sessão 1 da Rodada 3 plena, 2026-05-19).
`R CMD INSTALL` ignora subpastas de `R/` — a representação modular do
`cvmdata_rodada2_arquitetura_estavel.md` §2.1.3 fica como referência
conceitual; arquivos reais usam **prefixos de hífen**.

    cvmdata/
    ├── DESCRIPTION
    ├── NAMESPACE                      # auto-gerado por roxygen2
    ├── NEWS.md
    ├── LICENSE
    ├── LICENSE.md
    ├── README.md                      # gerado de README.Rmd
    ├── README.Rmd
    ├── README.pt-BR.md                # gerado de README.pt-BR.Rmd
    ├── README.pt-BR.Rmd
    ├── CODE_OF_CONDUCT.md             # Contributor Covenant 2.1
    ├── CONTRIBUTING.md
    ├── CLAUDE.md                      # este arquivo
    ├── ROADMAP.md
    ├── R/                             # FLAT, sem subpastas
    │   ├── cvmdata-package.R          # _PACKAGE sentinel
    │   ├── api-cvm-fetch.R            # cvm_fetch() exportada + cvm_fetch_internal()
    │   │                              #   + filter_by_companies() + busca textual
    │   ├── api-cad-fetch.R            # cad_fetch() — alias trivial sobre cvm_fetch()
    │   ├── cache.R                    # API pública de cache + engine de eviction:
    │   │                              #   cvm_cache_path(), cvm_cache_set_path(),
    │   │                              #   cvm_cache_info(), cvm_cache_clear();
    │   │                              #   build_cache_units(), cache_enforce_limit()
    │   ├── discovery.R                # cvm_datasets(), cvm_tables(),
    │   │                              #   cvm_dictionary(), cvm_codelist(),
    │   │                              #   cvm_dataset_years() (não segue prefixo
    │   │                              #   por enquanto — exceção tolerada)
    │   ├── schema-load.R              # load_schema() + validate_schema() +
    │   │                              #   resolve_file_pattern()
    │   ├── source.R                   # API pública de source:
    │   │                              #   cvm_source_get(), cvm_source_set()
    │   ├── source-cvm-http.R          # source_cvm_http_get() (CSV direto +
    │   │                              #   ZIP-yearly) + download_with_etag()
    │   ├── source-mirror-duckdb.R     # source_mirror_duckdb_get() funcional
    │   │                              #   (Sessão 3.13): filter pushdown por
    │   │                              #   nome de asset, download → L3, DuckDB
    │   │                              #   read local, reattach year/report_type,
    │   │                              #   hash-based eviction via sidecar
    │   ├── transform-schema.R         # apply_schema_transformations() genérico
    │   │                              #   (multiply_by_scale / drop /
    │   │                              #   keep_latest_version) — substituiu
    │   │                              #   transform-cad.R na Sessão 02
    │   ├── util-attrs.R               # cvm_attach_metadata()
    │   ├── util-cnpj.R                # cnpj_clean(), cnpj_format()
    │   ├── util-csv-cvm.R             # read_cvm_csv() + validate_field_count() +
    │   │                              #   validate_field_names() + emit_validation()
    │   ├── util-errors.R              # cvmdata_abort(), cvmdata_warn()
    │   ├── util-mirror-assets.R       # mirror_list_assets() (inventário GitHub
    │   │                              #   API cacheado por sessão) +
    │   │                              #   parse_mirror_asset_name() (tolera = e .)
    │   │                              #   + filter_mirror_assets() — Sessão 3.13
    │   └── util-print-cvm-tbl.R       # print.cvm_tbl()
    ├── man/                           # auto-gerado
    ├── tests/
    │   ├── testthat.R
    │   └── testthat/
    │       ├── fixtures/              # CSV/ZIP de amostra (cad_sample.csv +
    │       │                          #   dfp/itr/fre cia_aberta_2024.zip) +
    │       │                          #   parquet mini-fixtures mirror-*.parquet
    │       │                          #   gerados por data-raw/build-mirror-test-
    │       │                          #   fixtures.R (Sessão 3.13)
    │       ├── _snaps/
    │       ├── helper-*.R
    │       └── test-*.R               # ~17 arquivos, mock HTTP via httr2
    │                                  #   with_mocked_responses + httptest2
    ├── inst/
    │   ├── CITATION                   # citação canônica do pacote
    │   ├── etl/                       # ETL do mirror (rodado por etl-mirror.yaml)
    │   │   ├── 00-config.R            # constantes + helpers compartilhados
    │   │   ├── 01-fetch-cvm.R         # baixa ZIPs anuais do portal CVM
    │   │   ├── 02-csv-to-parquet.R    # converte CSV → parquet particionado por ano
    │   │   ├── 02b-validate.R         # pointblank pre-publish (Sessão 3.14):
    │   │   │                          #   3 checks sintéticos (existence, readable,
    │   │   │                          #   n_rows > 0) + 5 pointblank universais
    │   │   │                          #   (cnpj/cd_cvm regex, vl_conta numeric,
    │   │   │                          #   identifier character, date range);
    │   │   │                          #   hard estrutural aborta, soft conteúdo warna
    │   │   ├── 03-publish.R           # hash-detection + publica em GitHub Releases
    │   │   └── util-hash.R            # compute_source_hash(dataset) consumido por
    │   │                              #   03-publish.R (Sessão 3.12)
    │   └── extdata/
    │       ├── schemas/<dataset>/<table>.yaml
    │       ├── cvm_dictionary_snapshot.csv
    │       ├── cvm_codelists_snapshot.csv
    │       └── vignette-data/         # dados pré-computados para vignettes
    ├── data-raw/                      # out of tarball; mistura build scripts
    │                                  #   (build-dictionary-snapshot.R,
    │                                  #   build-codelists-snapshot.R,
    │                                  #   build-mirror-test-fixtures.R,
    │                                  #   build-vignette-data.R) com auditorias
    │                                  #   one-shot (run-capacity-audit.R,
    │                                  #   validate-mirror-end-to-end.R +
    │                                  #   validate-mirror-end-to-end.rds lido
    │                                  #   pelo article cache-and-mirror.Rmd em
    │                                  #   knit time CRAN-safe,
    │                                  #   mirror-capacity-audit.md). Apenas os
    │                                  #   build scripts são regenerados em ciclo
    │                                  #   normal (vide §12.1).
    ├── vignettes/
    ├── pkgdown/                       # _pkgdown.yml + assets do site
    ├── .github/workflows/             # R-CMD-check, test-coverage, lint,
    │                                  #   pkgdown, etl-mirror
    └── ...

Mapeamento agrupamento → prefixo: `api-`, `schema-`, `source-`,
`transform-`, `util-`.

------------------------------------------------------------------------

## 5. Sistema de classes S3

S3 minimalista. Classes internas:

- `cvm_tbl` — subclasse de `tbl_df`. Todo tibble retornado por funções
  públicas. Carrega 5 atributos em inglês (`source`, `fetched_at`,
  `dataset`, `table`, `package_version`).
- `cvm_table_schema` — objeto interno descrevendo o schema lido do YAML.
- `cvm_source` — handle interno para dispatch HTTP / mirror / cache.

`print.cvm_tbl()` é o único método print custom: exibe `source` e
`fetched_at` antes do tibble normal, depois delega a
[`NextMethod()`](https://rdrr.io/r/base/UseMethod.html).

------------------------------------------------------------------------

## 6. Hierarquia de classes de condição

    cvmdata_error                          (pai genérico de erros)
    ├── cvmdata_error_input                (argumento inválido do usuário)
    ├── cvmdata_error_http                 (falha de rede / HTTP)
    ├── cvmdata_error_parse                (falha de parse ou validação)
    ├── cvmdata_error_meta_unavailable     (META oficial não publicado — strict)
    └── cvmdata_error_internal             (qualquer outro)

    cvmdata_warn                           (pai genérico de warnings)
    ├── cvmdata_warn_validation            (divergência no warn mode)
    ├── cvmdata_warn_meta_unavailable      (META ausente, warn mode)
    ├── cvmdata_warn_year_fallback         (years = NULL caiu para ano anterior
    │                                       porque max year não tinha dados da
    │                                       companhia pedida)
    ├── cvmdata_warn_partial_failure       (batch yearly: alguns anos
    │                                       falharam HTTP sob
    │                                       on_error = "warn"; demais
    │                                       sobreviventes foram empilhados
    │                                       e retornados)
    └── cvmdata_warn_eviction              (LRU eviction removeu unidades
                                            do cache local para honrar
                                            options(cvmdata.cache_max_size_mb);
                                            default emite em interactive()
                                            e silencia em batch, controlado
                                            por
                                            options(cvmdata.cache_warn_evictions))

Implementação via wrapper interno `cvmdata_abort(message, class, ...)`
que adiciona `"cvmdata_error"` ao final do vetor de classes
automaticamente. Análogo `cvmdata_warn()` para warnings.

------------------------------------------------------------------------

## 7. Schema dos YAMLs por tabela

Localização: `inst/extdata/schemas/<dataset>/<table>.yaml`.

``` yaml
dataset: <dataset>
table: <table>

# Exatamente um dos dois é não-nulo
cvm_archive_url_pattern: <URL do ZIP ou null>
cvm_file_url_pattern: <URL direta do CSV ou null>
cvm_file_pattern: "<nome do CSV, com {year} quando aplicável>"

# Notação archive.zip#entry.txt quando o META vive dentro de ZIP
cvm_dictionary_url: "<URL ou null se meta_status: missing>"

# Domínio aceito: available (default) | missing
meta_status: available

encoding: ISO-8859-1
delimiter: ";"

# Domínio aceito: none | yearly
temporal_partitioning: <none | yearly>
first_year: <int presente quando != none>

expected_field_count: <int>

# Obrigatório quando meta_status: missing; opcional quando available
expected_field_names:
  - <field 1>
  - <field 2>

# Sempre presente, ainda que vazia
transformations: []
```

Domínio aceito em `action` dentro de `transformations`:

| `action` | Significado |
|----|----|
| `multiply_by_scale` | Coluna multiplicada por outra de escala; requer `scale_column:` |
| `drop` | Coluna removida do tibble |
| `keep_latest_version` | Tabela mantém só o maior `versao` por chave |

`convert_to_date` foi removido — datas são automáticas via dicionário.

8 tabelas FRE têm `meta_status: missing` (sem META oficial CVM):
`administrador_PCD`, `empregado_PCD`,
`empregado_local_declaracao_genero`, `empregado_local_declaracao_raca`,
`empregado_posicao_declaracao_genero`,
`empregado_posicao_declaracao_raca`, `empregado_posicao_faixa_etaria`,
`empregado_posicao_local`.

------------------------------------------------------------------------

## 8. Política do reader em três modos validate

| `validate` | Tabela com META | Tabela sem META |
|----|----|----|
| `"strict"` (default) | Valida; divergência → `cvmdata_error_parse` | Aborta com `cvmdata_error_meta_unavailable` |
| `"warn"` | Valida; divergência → `cvmdata_warn_validation` | Emite `cvmdata_warn_meta_unavailable` e entrega tibble |
| `"skip"` | Pula validação | Pula validação (silencioso) |

Mensagens em inglês, via
[`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html) /
[`cli::cli_warn()`](https://cli.r-lib.org/reference/cli_abort.html).
Símbolo `x` para erro, `!` para warning, `i` para info. Sob
`meta_status: missing` em modo `"warn"`, o reader valida
`expected_field_names` do YAML contra o cabeçalho do CSV (defesa em
profundidade).

------------------------------------------------------------------------

## 9. Snapshots embarcados em `inst/extdata/`

### `cvm_dictionary_snapshot.csv`

CSV UTF-8, delimitador `,`. 10 colunas obrigatórias + 1 opcional:

| Coluna | Tipo | Origem |
|----|----|----|
| `dataset` | character | chave |
| `table` | character | chave |
| `campo` | character | chave; nome snake_case minúsculo (bate com [`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)) |
| `campo_original` | character | nome do campo como publicado no META CVM (preserva caps/mixed case) |
| `descricao` | character | descrição oficial CVM |
| `dominio` | character | domínio oficial CVM |
| `tipo_dados` | character | tipo oficial CVM |
| `tamanho` | integer | tamanho oficial CVM (NA quando ausente) |
| `precisao` | integer | precisão oficial CVM (NA) |
| `scale` | integer | escala oficial CVM (NA) |
| `meta_status` | character (opcional) | `"available"` (default) ou `"missing"` |

Quando `meta_status = "missing"`: `descricao`, `dominio`, `tipo_dados`,
`tamanho`, `precisao`, `scale` ficam `NA`. **Não inventamos** descrições
ausentes.

### `cvm_codelists_snapshot.csv`

CSV UTF-8, delimitador `,`. 4 colunas (v0.1):

| Coluna | Tipo | Conteúdo |
|----|----|----|
| `dataset` | character | chave |
| `table` | character | chave |
| `campo` | character | chave; snake_case minúsculo (mesma convenção de [`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md)) |
| `value` | character | valor categórico em PT como vem da CVM |

Chave composta `(dataset, table, campo, value)`. `first_seen_year`,
`last_seen_year` e `frequency` deferidos para v0.2+ (decisão Sessão
3.4). Razão: a v0.1 amostra apenas o último ano disponível por dataset
(~30 s de geração); marcar `first_seen_year` com o único ano amostrado
entrega informação enganosa (parece “categoria nova” quando é só “ano
único na amostra”) e, quando v0.2 trouxer cobertura histórica, todos os
valores cairão para 2010-2015 — exatamente o “ruído de diff Git” que
motivou deferir as outras duas. Schema do CSV embarcado é estável dentro
da v0.1; v0.2 pode adicionar a coluna sem quebra para o leitor interno.

Critério de inclusão (Sessão 3.4):

- **Pelo dicionário**: colunas onde `dominio` enumera valores com
  separador `/` ou `|` (capta `S/N`, `PF/PJ`).
- **Por cardinalidade observada**: colunas `tipo_dados = "varchar"` com
  `tamanho < 200` e ≤ 50 valores distintos no último ano disponível,
  EXCLUINDO pelos seguintes prefixos (texto livre, identificadores e PII
  corporativa/pessoal):
  - identificadores `.identifier_patterns` do reader (`cnpj`, `cd_cvm`,
    `codigo_cvm`, `cep`, `tel`, `ddd`, `cpf`, `id_doc`, `id_documento`,
    `versao`);
  - `^cd_` (códigos contábeis como `cd_conta`);
  - `^nome_`, `^denom_` (nomes próprios e razões sociais);
  - `^ds_` (descrições de conta, texto livre);
  - `^email`, `^logradouro`, `^compl`, `^bairro`, `^mun($|_)`,
    `^municipio_` (componentes de endereço com universo grande).
- **Tabelas `meta_status: missing`**: excluídas (sem META oficial,
  declarar codelist é decisão do pacote sem ancoragem CVM — viola a
  régua “se vem da CVM, fica como na CVM”).

------------------------------------------------------------------------

## 10. Estratégia de cache

Cache em `tools::R_user_dir("cvmdata", which = "cache")`.

Níveis:

- L1: ZIP raw da CVM (`<cache>/raw/<dataset>/[<year>/]`). Cobre CAD (CSV
  direto) e DFP/ITR/FRE (ZIP yearly). Sidecar `*.etag.rds` carrega
  ETag/Last-Modified/`fetched_at`.
- L3: Parquet do mirror
  (`<cache>/parquet/<dataset>/<table>/ [report_type=R/]year=Y/part-0.parquet`).
  Sidecar `<cache>/parquet/<dataset>/__source_hash.json` armazena o
  SHA-256 do release atual para invalidação. Ativado de fato na **Sessão
  3.13**.
- L4: tibble em memória da sessão
  ([`cachem::cache_mem()`](https://cachem.r-lib.org/reference/cache_mem.html),
  50 MB — planejado, ainda não implementado em v0.1).

L2 (CSV descompactado) **não** é usado.

Invalidação:

- **L1**: HEAD HTTP em `cvm_dictionary_url`/`cvm_file_url_pattern` antes
  de servir cache, comparando ETag/Last-Modified. TTL default 30 dias
  via `options(cvmdata.cache_ttl_seconds)` (imposto na Sessão 3.7).
  Dentro da janela, `download_with_etag()` retorna o `dest_path` sem
  HEAD nem GET. Valores especiais: `0` = sempre HEAD; `Inf` = nunca HEAD
  enquanto o sidecar existir; sidecar sem `fetched_at` parseável cai
  para HEAD para refrescar metadados.
- **L3**: comparação de hash via sidecar
  `<cache>/parquet/<dataset>/__source_hash.json` contra o asset
  `__source_hash.json` do release `mirror-<dataset>-latest` (a API
  GitHub é consultada em `mirror_list_assets()` no início de cada
  `cvm_fetch(..., source = "mirror")`). Hash igual → no-op; hash
  diferente → `unlink(<cache>/parquet/<dataset>/)` antes da próxima
  leitura. Hash `NA` (release antigo sem o sidecar publicado) → L3
  preservado por respeito a mirrors legados. Não há TTL no L3:
  invalidação é exclusivamente content-addressed.
- [`cvm_cache_clear()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_clear.md)
  manual aceita `what ∈ c("all", "raw", "parquet")` (extensão da Sessão
  3.13). `what = "parquet"` rejeita `year` porque o layout L3 aninha
  year sob table — passar `dataset` sozinho evict o dataset inteiro;
  para granularidade year-level, usar `what = "raw"`.

Fallback hierárquico depende de `source`:

- `source = "mirror"` (default pós-flip): L4 (planejado) → L3 (parquet
  local) → Mirror GitHub Releases (filter pushdown manual por nome de
  asset → download → DuckDB lê local) → erro.
- `source = "cvm"` (default em v0.1 pré-flip): L4 (planejado) → L1 (ZIP
  raw em disco) → CVM HTTP → erro.

**Mirror parquet ativado em v0.1.** Workflow semanal (`etl-mirror.yaml`,
cron `0 7 * * 2`) executa matrix paralela de 4 datasets
(`fail-fast: false`); cada job roda `01-fetch-cvm.R` →
`02-csv-to-parquet.R` → `03-publish.R`. O publish detecta mudança via
hash SHA-256 das URLs de `cvm_dictionary_url` (`util-hash.R`, Sessão
3.12) e skipa republish quando o hash bate o do release anterior. Volume
estimado para companhias abertas (CAD + DFP + ITR + FRE em parquet
snappy) ≈ 3 GB, cabe folgado em GitHub Releases (limite 2 GB por
arquivo, 100 GB por release). Encoding dos asset names:
`<table>__report_type=R__year=Y__part-0.parquet` (Hive-style achatado
por `gsub("[/\\\\]", "__", rel)` em `03-publish.R`); o GitHub Releases
sanitiza `=` → `.` no URL público, e o reader
(`parse_mirror_asset_name()` em `R/util-mirror-assets.R`) tolera ambos
os encodings.

Limite default 100 MiB, configurável via
`options(cvmdata.cache_max_size_mb = ...)` — imposto na Sessão 3.8.
Quando a soma das **unidades de cache** ultrapassa 90% do limite, o
próximo download (no fim do ramo de gravação real de
`download_with_etag()`, depois do
[`saveRDS()`](https://rdrr.io/r/base/readRDS.html) do sidecar) dispara
LRU eviction até cair para 80% do limite **ou** esgotar a lista de
candidatos. A engine vive em `R/cache.R` (`read_cache_max_size()`,
`build_cache_units()`, `cache_current_size_bytes()`,
`cache_enforce_limit()`). Unidade de eviction: diretório do ano
`<cache>/raw/<dataset>/<YYYY>/` para datasets yearly (DFP/ITR/FRE), par
`{artifact, sidecar}` para não-particionados (CAD); âncora de ordenação
é [`file.mtime()`](https://rdrr.io/r/base/file.info.html) do upstream
artifact (ZIP/CSV). Files órfãos (artifact sem sidecar, sidecar sem
artifact) são ignorados na contabilidade —
[`cvm_cache_clear()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_clear.md)
segue sendo o caminho para limpá-los. O artefato recém-gravado é
protegido contra self-eviction (parâmetro `protect` passado pelo
trigger). Valores especiais: `0` ou negativo desligam a engine; `Inf`
idem; tipo inválido cai para o default 100 MiB (defesa).
Observabilidade: `cvmdata_warn_eviction` é emitida agregada ao fim de
cada rodada (`{N} unit(s)`, `{X} MiB` liberados, limite atual); default
[`interactive()`](https://rdrr.io/r/base/interactive.html) via
`options(cvmdata.cache_warn_evictions)` — batch silencia, REPL avisa.
Atributo `total_size_bytes` em
[`cvm_cache_info()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_info.md)
(Sessão 3.8) entrega a contagem corrente. CSVs extraídos via
[`unzip()`](https://rdrr.io/r/utils/unzip.html) contam para o limite
(mesma unidade do ZIP), mas o trigger só dispara em downloads reais —
não em extrações; cache acima de 90% pós-`unzip` se auto-corrige no
próximo download.

------------------------------------------------------------------------

## 11. Política de testes

- `testthat` 3.x com edition 3, `Config/testthat/edition: 3`.
- **Testes determinísticos CRAN-friendly**: sem rede em
  `tests/testthat/`. Testes de integração com CVM real em
  `test-integration-*.R` com `skip_on_cran()` + `skip_if_offline()` +
  guarda `CVMDATA_RUN_INTEGRATION=true`.
- **Fixtures pequenos e reais** em `tests/testthat/fixtures/` (50-200
  linhas, ~5 MB total cap). Cada fixture com `*.meta.json` registrando
  origem.
- **Mocks de HTTP** via `httptest2`. Mocks em `tests/testthat/_mocks/`.
- **Snapshot tests** para mensagens de erro, atributos serializados,
  estrutura de output
  ([`dplyr::glimpse()`](https://pillar.r-lib.org/reference/glimpse.html)
  snapshotado).
- **Cobertura alvo 90%** via
  [`covr::package_coverage()`](http://covr.r-lib.org/reference/package_coverage.md).

Cada commit deve deixar o pacote **verde em
[`devtools::check()`](https://devtools.r-lib.org/reference/check.html)**:
`0 errors`, `0 warnings`, testes passando, lint clean,
[`pkgdown::build_site()`](https://pkgdown.r-lib.org/reference/build_site.html)
funcionando. Gate não-negociável.

------------------------------------------------------------------------

## 12. Workflow de desenvolvimento

- Modo **tracer bullet**: implementar a função mais simples
  ponta-a-ponta antes de generalizar.
- **Estado atual de execução vive em `ROADMAP.md`** — sessão por sessão,
  fase por fase. `CLAUDE.md` não duplica status; consulta o roadmap
  antes de assumir que algo está ou não entregue.
- **Não reabrir decisões travadas** (26 da 2.5, 7 da 2.6, 3 da 3.0, 4 da
  3.0.2, mais a Sessão 02 sobre
  [`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
  como API principal e o portal de dados abertos como caminho default vs
  RAD/ENET, e as decisões pós-3.4 registradas em `NEWS.md` + histórico
  de commits). Se acha que precisa rever, perguntar antes de agir.
- **Não inventar URLs, nomes de arquivos CVM, conteúdo de schemas**.
  Usar YAMLs validados em `inst/extdata/schemas/` (ou `schemas_proto/`
  para protótipos ainda não promovidos) ou perguntar.

### 12.1 Comandos comuns (PowerShell + Rscript)

`Rscript.exe` resolve para `C:\Program Files\R\R-4.5.3\bin\Rscript.exe`
no `PATH`. Todos os comandos abaixo rodam do diretório raiz do pacote.

``` powershell
# Gate completo (precisa estar verde a cada commit)
Rscript -e "devtools::check()"

# Suite de testes (testthat 3.x edition 3)
Rscript -e "devtools::test()"

# Um único arquivo de teste — exige caminho relativo
Rscript -e "devtools::test_active_file('tests/testthat/test-cad-fetch.R')"

# Um único `test_that()` por nome — desc parcial casa por regex
Rscript -e "testthat::test_file('tests/testthat/test-cad-fetch.R', desc = 'returns a cvm_tbl')"

# Lint do pacote — deve retornar character(0)
Rscript -e "lintr::lint_package()"

# Cobertura (alvo ≥90%, gate atual ≥85%)
Rscript -e "print(covr::package_coverage())"

# Regenerar man/*.Rd + NAMESPACE a partir do roxygen
Rscript -e "devtools::document()"

# Regenerar README.md a partir de README.Rmd
Rscript -e "devtools::build_readme()"

# Regenerar README.pt-BR.md a partir de README.pt-BR.Rmd
# (devtools::build_readme() só cobre o canônico README.Rmd)
Rscript -e "knitr::knit('README.pt-BR.Rmd', output = 'README.pt-BR.md')"

# Carregar o pacote sem instalar (smoke check rápido)
Rscript -e "devtools::load_all(); print(cvm_fetch)"

# R CMD INSTALL local
Rscript -e "devtools::install(quick = TRUE, upgrade = 'never')"

# Build do tarball CRAN (.tar.gz)
Rscript -e "devtools::build()"

# Regenerar snapshots e fixtures embarcados (rodar quando os scripts
# fonte em data-raw/ ou os YAMLs em inst/extdata/schemas/ mudarem).
# Os scripts batem no portal CVM real — exigem rede e levam ~30 s cada.
Rscript data-raw/build-dictionary-snapshot.R    # inst/extdata/cvm_dictionary_snapshot.csv
Rscript data-raw/build-codelists-snapshot.R     # inst/extdata/cvm_codelists_snapshot.csv
Rscript data-raw/build-mirror-test-fixtures.R   # tests/testthat/fixtures/mirror-*.parquet
Rscript data-raw/build-vignette-data.R          # inst/extdata/vignette-data/*.rds

# ETL do mirror — dispatch manual do workflow (precisa gh CLI autenticado);
# o cron `0 7 * * 2` em .github/workflows/etl-mirror.yaml dispara semanalmente
gh workflow run etl-mirror.yaml

# ETL local (smoke) — rodar os scripts individualmente sem subir release
Rscript inst/etl/01-fetch-cvm.R       --dataset cad
Rscript inst/etl/02-csv-to-parquet.R  --dataset cad
Rscript inst/etl/02b-validate.R       --dataset cad   # Sessão 3.14
Rscript inst/etl/03-publish.R         --dataset cad
```

Notas:

- [`devtools::check()`](https://devtools.r-lib.org/reference/check.html)
  executa `R CMD check` com `--as-cran`, roda a vignette `cvmdata.Rmd`
  (configurada `eval = interactive()` para não bater no portal CVM) e os
  testes. **Zero errors, zero warnings, zero notes** é o gate.
- Os testes `tests/testthat/test-*.R` mockam HTTP via `httptest2` (e em
  alguns casos
  [`httr2::with_mocked_responses()`](https://httr2.r-lib.org/reference/with_mocked_responses.html)).
  Nenhum teste bate no portal CVM real — testes de integração reais
  virão em arquivos `test-integration-*.R` com guarda
  `CVMDATA_RUN_INTEGRATION=true`.
- Fixtures em `tests/testthat/fixtures/`: `cad_sample.csv` (51 linhas
  reais do CAD), `dfp_cia_aberta_2024.zip`, `itr_cia_aberta_2024.zip` e
  `fre_cia_aberta_2024.zip` (cada ZIP com subset de companhias e
  `*.meta.json` registrando a origem; o FRE exercita as 8 tabelas
  `meta_status: missing`).
- `inst/extdata/schemas/cad/companhias.yaml` declara
  `expected_field_count: 47` (corrigido de 46 do protótipo na Sessão
  01).
- O cache real de produção fica em
  `tools::R_user_dir("cvmdata", which = "cache")`. Em testes, é
  redirecionado para tempdir via `options(cvmdata.cache_dir = ...)`.
- Workflows GitHub Actions em `.github/workflows/`: `R-CMD-check.yaml`
  (matriz macOS/Windows/Ubuntu), `test-coverage.yaml` (codecov),
  `lint.yaml` (`LINTR_ERROR_ON_LINT=true`), `pkgdown.yaml` (deploy para
  `gh-pages`), `etl-mirror.yaml` (cron semanal + manual dispatch).

### 12.2 Stage `schemas_proto/`

Diretório `schemas_proto/` na raiz (excluído da tarball via
`.Rbuildignore`) é a área de stage para YAMLs de schema antes da
promoção para `inst/extdata/schemas/<dataset>/<table>.yaml`. Workflow:
escrever o YAML em `schemas_proto/<dataset>/<table>.yaml`, validar
contra dados reais com `cvm_fetch(..., validate = "warn")`, ajustar
`expected_field_count`/`expected_field_names`/`transformations` até zero
divergência, então mover para `inst/extdata/schemas/`. Conteúdo atual:
rascunhos parciais (não confiar como fonte canônica até o homônimo
aparecer em `inst/extdata/schemas/`).

------------------------------------------------------------------------

## 13. Stack técnica do pacote (Imports/Suggests)

`Depends`: `R (>= 4.1)` (para `|>`).

**Estado atual** (vide `DESCRIPTION`):

- `Imports`: `cli`, `DBI`, `duckdb`, `httr2`, `readr`, `rlang`,
  `tibble`, `yaml`. `DBI` + `duckdb` entraram na **Sessão 3.13**
  (backend `source = "mirror"`).
- `Suggests`: `arrow`, `covr`, `digest`, `dplyr`, `httptest2`,
  `jsonlite`, `knitr`, `lintr`, `pkgdown`, `pointblank`, `rmarkdown`,
  `styler`, `testthat (>= 3.0.0)`, `withr`. `digest` + `jsonlite` são
  consumidos pelo ETL (`inst/etl/util-hash.R`); no path de leitura do
  usuário, `mirror_list_assets()` usa `jsonlite` indiretamente via
  [`httr2::resp_body_json()`](https://httr2.r-lib.org/reference/resp_body_raw.html).
  `arrow` + `pointblank` entraram na **Sessão 3.14** (consumidos por
  `inst/etl/02b-validate.R`).

**Previstos para fases seguintes** (entram no `DESCRIPTION` quando o
código que os exige aterrissar):

- `Imports`: `purrr`/`stringr`/`vctrs` (helpers internos quando o
  pipeline genérico ganhar mais peso). `arrow` deixou de ser necessário
  no path padrão porque DuckDB lê Parquet local diretamente.
- `Suggests`: `ggplot2` + `scales` (vignettes ilustrativas, Fase E).

------------------------------------------------------------------------

## 14. Objetivos do projeto

- **Objetivo intermediário**: aceitação rOpenSci via review formal em
  <https://github.com/ropensci/software-review>. É o gate de qualidade
  que ancora todo o trabalho.
- **Objetivo final**: CRAN. rOpenSci submete em nome do mantenedor
  quando aceito.
- **Consequência**: artigo no The R Journal sobre o pacote.

Decisões de design que não passem o filtro “isso ajuda ou atrapalha a
aceitação rOpenSci?” devem ser rejeitadas.
