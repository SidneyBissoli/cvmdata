# CLAUDE.md — Contexto persistente do pacote `cvmdata`

Documento de referência para sessões do Claude Code no diretório
`C:/Users/SIDNEY/OneDrive/programacao/R/packages/cvmdata`. Consolida o
essencial de seis documentos canônicos da fase de planejamento (Rodadas
1, 2.5, 2.6, 3.0, 3.0.2) para que sessões futuras não precisem reler
tudo. Quando este `CLAUDE.md` divergir de um documento canônico,
**prevalece o canônico** — em particular `cvmdata_rodada2-5_naming_unificado-v03.md`
para naming e `cvmdata_rodada3-0-2_politica_reader_sem_meta.md` para
política do reader.

Comunicação com Sidney é em **português brasileiro**. Tom direto,
técnico, sem fluff, sem puxa-saquismo. Quando ele perguntar problemas,
dizer diretamente; se não houver, dizer isso. Críticas construtivas
bem-vindas. Em decisões arquiteturais relevantes não fechadas nos
canônicos: apresentar 2-3 alternativas com prós/contras e recomendar
uma.

---

## 1. Régua de idioma

Princípio reitor:

> **Se vem da CVM, fica como na CVM** (apenas normalização tipográfica
> para snake_case minúsculo quando o original está em SCREAMING_SNAKE_CASE).
> **Se não vem da CVM, é decisão do pacote.**

Distribuição:

| Categoria | Idioma |
|---|---|
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

Caveat: a palavra `dataset` permanece em inglês como argumento de
função (palavra técnica internacionalizada); a coluna paralela em
`cvm_datasets()` chama-se `conjunto_dados` em PT. Mismatch deliberado.

---

## 2. Naming canônico (resumo do naming doc v03)

### 2.1 Funções públicas

Padrão `object_verb` (Dev Guide rOpenSci).

```r
# Espinha dorsal genérica
cvm_fetch(dataset, table, companies = NULL, years = NULL,
          source = "auto", on_error = "abort", validate = "strict", ...)

# Aliases tipados v0.1
cad_fetch(companies = NULL, ...)
itr_fetch(table, companies = NULL, years = NULL, ...)
dfp_fetch(table, companies = NULL, years = NULL, ...)
fre_fetch(table, companies = NULL, years = NULL, ...)

# Descoberta
cvm_datasets()
cvm_tables(dataset)
cvm_dictionary(dataset, table)

# Cache
cvm_cache_path()
cvm_cache_set_path(path)
cvm_cache_clear(what = "all", ...)
cvm_cache_info()

# Source
cvm_source_get()
cvm_source_set(source)

# Utilidades
cnpj_clean(x)   # exportada na v0.1
```

`source` aceita `"auto"` (portal → mirror fallback), `"portal"`,
`"mirror"`. `validate` aceita `"strict"` (default), `"warn"`, `"skip"`.
`on_error` aceita `"abort"` (default), `"warn"`, `"silent"`. Validação
via `rlang::arg_match()`.

### 2.2 Colunas-chave universais (CAD + ITR + DFP + FRE-header)

| Coluna | Tipo | Origem CVM | Notas |
|---|---|---|---|
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
`c("cnpj_cia", "cd_cvm", "cep", "tel", "ddd_*", "cpf", "id_documento",
"cnpj_companhia")`.

### 2.5 Datas

Conversão de string para `Date` é **automática** sempre que o snapshot
de dicionário declarar `tipo_dados = "date"`. `convert_to_date` foi
removido do domínio aceito em `transformations:`.

### 2.6 vl_conta × escala_moeda

Em tabelas ITR/DFP contábeis: `VL_CONTA` é multiplicada por
`ESCALA_MOEDA` (`UNIDADE`=1, `MIL`=1e3, `MILHÃO`=1e6, `BILHÃO`=1e9) e
retornada em reais absolutos. `escala_moeda` é removida do tibble;
`moeda` mantida (constante `"REAL"` na v0.1).

---

## 3. Convenções de código R

- Pipe: `|>` (nunca `%>%`). `R (>= 4.1)` no `Depends`.
- Strings: aspas duplas por padrão; `stringr::str_c()` em vez de
  `paste()`/`paste0()`.
- Indentação 2 espaços, sem tabs.
- Largura máxima 80 chars (tolerância até 100).
- Style guide: tidyverse.
- Lint clean (`lintr::lint_package()` retorna `character(0)`) antes
  de qualquer commit.
- **Fully-qualified namespaces** em todo código (`dplyr::filter()`,
  `readr::read_delim()`). Exceção em pipelines longos com `@importFrom`
  no roxygen.
- Toda função exportada tem bloco roxygen completo: `@title`,
  `@description`, `@param`, `@return`, `@examples`, `@export`,
  `@family` (quando apropriado), `@seealso`.
- Mensagens via `cli::cli_abort()` / `cli::cli_warn()` /
  `cli::cli_inform()`. **Nunca** `print()` ou `cat()` fora de métodos
  `print.*`/`str.*`.
- Estilo cli: `{.fn nome_funcao}`, `{.val "valor"}`, `{.var nome_var}`;
  símbolos `x` (erro), `i` (info), `!` (warn), `v` (sucesso).

---

## 4. Estrutura de diretórios

**Régua R/ é flat** (travada na Sessão 1 da Rodada 3 plena, 2026-05-19).
`R CMD INSTALL` ignora subpastas de `R/` — a representação modular do
`cvmdata_rodada2_arquitetura_estavel.md` §2.1.3 fica como referência
conceitual; arquivos reais usam **prefixos de hífen**.

```
cvmdata/
├── DESCRIPTION
├── NAMESPACE                      # auto-gerado por roxygen2
├── NEWS.md
├── LICENSE
├── LICENSE.md
├── README.md                      # gerado de README.Rmd
├── README.Rmd
├── CLAUDE.md                      # este arquivo
├── ROADMAP.md
├── R/                             # FLAT, sem subpastas
│   ├── cvmdata-package.R          # _PACKAGE sentinel
│   ├── api-cad-fetch.R            # cad_fetch() e cvm_fetch_internal()
│   ├── api-fetch-cvm.R            # cvm_fetch() — futuro
│   ├── schema-load.R              # load_schema()
│   ├── source-cvm-http.R          # source_cvm_http_get()
│   ├── transform-cad.R            # transform_cad()
│   ├── util-attrs.R               # cvm_attach_metadata()
│   ├── util-csv-cvm.R             # read_cvm_csv()
│   ├── util-errors.R              # cvmdata_abort(), cvmdata_warn()
│   └── util-print-cvm-tbl.R       # print.cvm_tbl()
├── man/                           # auto-gerado
├── tests/
│   ├── testthat.R
│   └── testthat/
│       ├── fixtures/              # CSV/ZIP de amostra
│       ├── _snaps/
│       ├── helper-*.R
│       └── test-*.R
├── inst/
│   └── extdata/
│       ├── schemas/<dataset>/<table>.yaml
│       ├── cvm_dictionary_snapshot.csv
│       └── cvm_codelists_snapshot.csv
├── data-raw/                      # scripts geradores (out of tarball)
├── vignettes/
├── pkgdown/
├── .github/workflows/
└── ...
```

Mapeamento agrupamento → prefixo:
`api-`, `schema-`, `source-`, `transform-`, `dispatch-`, `validate-`,
`util-`.

---

## 5. Sistema de classes S3

S3 minimalista. Classes internas:

- `cvm_tbl` — subclasse de `tbl_df`. Todo tibble retornado por
  funções públicas. Carrega 5 atributos em inglês (`source`,
  `fetched_at`, `dataset`, `table`, `package_version`).
- `cvm_table_schema` — objeto interno descrevendo o schema lido do
  YAML.
- `cvm_source` — handle interno para dispatch HTTP / mirror / cache.

`print.cvm_tbl()` é o único método print custom: exibe `source` e
`fetched_at` antes do tibble normal, depois delega a `NextMethod()`.

---

## 6. Hierarquia de classes de condição

```
cvmdata_error                          (pai genérico de erros)
├── cvmdata_error_input                (argumento inválido do usuário)
├── cvmdata_error_http                 (falha de rede / HTTP)
├── cvmdata_error_parse                (falha de parse ou validação)
├── cvmdata_error_meta_unavailable     (META oficial não publicado — strict)
└── cvmdata_error_internal             (qualquer outro)

cvmdata_warn                           (pai genérico de warnings)
├── cvmdata_warn_validation            (divergência no warn mode)
└── cvmdata_warn_meta_unavailable      (META ausente, warn mode)
```

Implementação via wrapper interno `cvmdata_abort(message, class, ...)`
que adiciona `"cvmdata_error"` ao final do vetor de classes
automaticamente. Análogo `cvmdata_warn()` para warnings.

---

## 7. Schema dos YAMLs por tabela

Localização: `inst/extdata/schemas/<dataset>/<table>.yaml`.

```yaml
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
|---|---|
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

---

## 8. Política do reader em três modos validate

| `validate` | Tabela com META | Tabela sem META |
|---|---|---|
| `"strict"` (default) | Valida; divergência → `cvmdata_error_parse` | Aborta com `cvmdata_error_meta_unavailable` |
| `"warn"` | Valida; divergência → `cvmdata_warn_validation` | Emite `cvmdata_warn_meta_unavailable` e entrega tibble |
| `"skip"` | Pula validação | Pula validação (silencioso) |

Mensagens em inglês, via `cli::cli_abort()` / `cli::cli_warn()`. Símbolo
`x` para erro, `!` para warning, `i` para info. Sob `meta_status: missing`
em modo `"warn"`, o reader valida `expected_field_names` do YAML contra
o cabeçalho do CSV (defesa em profundidade).

---

## 9. Snapshots embarcados em `inst/extdata/`

### `cvm_dictionary_snapshot.csv`

CSV UTF-8, delimitador `,`. 10 colunas obrigatórias + 1 opcional:

| Coluna | Tipo | Origem |
|---|---|---|
| `dataset` | character | chave |
| `table` | character | chave |
| `column` | character | chave |
| `campo` | character | nome original CVM (preserva caps) |
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

CSV UTF-8, delimitador `,`. 4 colunas obrigatórias + 1 opcional:

| Coluna | Tipo | Conteúdo |
|---|---|---|
| `dataset` | character | chave |
| `table` | character | chave |
| `column` | character | chave |
| `value` | character | valor categórico em PT como vem da CVM |
| `first_seen_year` | integer (opcional, incluído v0.1) | primeiro ano observado |

Chave composta `(dataset, table, column)`. `frequency` e
`last_seen_year` deferidos para v0.2+ (ruído de diff Git).

---

## 10. Estratégia de cache

Cache em `tools::R_user_dir("cvmdata", which = "cache")`.

Níveis:

- L1: ZIP raw da CVM (`raw/<dataset>/`)
- L3: Parquet transformado (`parquet/<dataset>/<table>/year=<ano>/`)
- L4: tibble em memória da sessão (`cachem::cache_mem()`, 50 MB)

L2 (CSV descompactado) **não** é usado.

Invalidação:

- HEAD HTTP em `cvm_dictionary_url`/`cvm_file_url_pattern` antes de
  servir cache; comparar ETag/Last-Modified.
- TTL default 30 dias.
- `cvm_cache_clear()` manual.

Fallback hierárquico com `source = "auto"`:
1. L4 (memória) → 2. L1 (raw no disco) → 3. CVM HTTP →
4. Mirror GitHub Releases (via DuckDB HTTP range requests) → 5. erro.

Limite default 100 MB, configurável via
`options(cvmdata.cache_max_size_mb = ...)`. Eviction LRU quando atinge
90% do limite.

---

## 11. Política de testes

- `testthat` 3.x com edition 3, `Config/testthat/edition: 3`.
- **Testes determinísticos CRAN-friendly**: sem rede em `tests/testthat/`.
  Testes de integração com CVM real em `test-integration-*.R` com
  `skip_on_cran()` + `skip_if_offline()` + guarda
  `CVMDATA_RUN_INTEGRATION=true`.
- **Fixtures pequenos e reais** em `tests/testthat/fixtures/` (50-200
  linhas, ~5 MB total cap). Cada fixture com `*.meta.json` registrando
  origem.
- **Mocks de HTTP** via `httptest2`. Mocks em
  `tests/testthat/_mocks/`.
- **Snapshot tests** para mensagens de erro, atributos serializados,
  estrutura de output (`dplyr::glimpse()` snapshotado).
- **Cobertura alvo 90%** via `covr::package_coverage()`.

Cada commit deve deixar o pacote **verde em `devtools::check()`**:
`0 errors`, `0 warnings`, testes passando, lint clean,
`pkgdown::build_site()` funcionando. Gate não-negociável.

---

## 12. Workflow de desenvolvimento

- Modo **tracer bullet**: implementar a função mais simples ponta-a-ponta
  antes de generalizar.
- Sequência da Sessão 1: `cad_fetch()` é o tracer (CAD = CSV direto, sem
  ZIP, sem variantes, sem transformações). `cvm_fetch()` genérico só
  depois de ter pelo menos 2-3 aliases concretos.
- **Não reabrir decisões travadas** (26 da 2.5, 7 da 2.6, 3 da 3.0, 4
  da 3.0.2). Se acha que precisa rever, perguntar antes de agir.
- **Não inventar URLs, nomes de arquivos CVM, conteúdo de schemas**. Usar
  YAMLs validados em `schemas_proto/` ou perguntar.

---

## 13. Stack técnica do pacote (Imports/Suggests previstos)

`Imports` (populados conforme implementação avança):
`tibble`, `vctrs`, `rlang`, `dplyr`, `purrr`, `stringr`, `readr`,
`httr2`, `arrow`, `duckdb`, `cli`, `withr`, `yaml`.

`Suggests`:
`testthat (>= 3.0.0)`, `pointblank`, `knitr`, `rmarkdown`, `covr`,
`lintr`, `styler`, `pkgdown`, `httptest2`, `ggplot2`, `scales`.

`Depends`: `R (>= 4.1)` (para `|>`).

---

## 14. Objetivos do projeto

- **Objetivo intermediário**: aceitação rOpenSci via review formal em
  <https://github.com/ropensci/software-review>. É o gate de qualidade
  que ancora todo o trabalho.
- **Objetivo final**: CRAN. rOpenSci submete em nome do mantenedor
  quando aceito.
- **Consequência**: artigo no The R Journal sobre o pacote.

Decisões de design que não passem o filtro "isso ajuda ou atrapalha a
aceitação rOpenSci?" devem ser rejeitadas.
