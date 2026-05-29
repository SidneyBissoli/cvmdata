# CLAUDE.md — Contexto persistente do pacote `cvmdata`

Documento de referência para sessões do Claude Code no diretório
`C:/Users/SIDNEY/OneDrive/programacao/R/packages/cvmdata`. Consolida o
essencial dos canônicos de planejamento para que sessões futuras não
precisem reler tudo. Quando este `CLAUDE.md` divergir de um canônico,
**prevalece o canônico** — em particular
`cvmdata_rodada2-5_naming_unificado-v03.md` para naming de colunas e
tabelas, `cvmdata_rodada3-0-2_politica_reader_sem_meta.md` para a
política do reader, e
`data-raw/decisions/cvmdata_arquitetura_grupos_decisao_v2.md` para a
arquitetura de 5 fetchers por contrato. Estado de execução por fase no
`ROADMAP.md`; histórico de breaking changes em `NEWS.md`.

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
| Atributos do tibble retornado | **Inglês** (`source`, `fetched_at`, `group`, `dataset`, `table`, `package_version`) |
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

## 2. Naming canônico

### 2.1 Funções públicas

Padrão `object_verb` (Dev Guide rOpenSci). API pública organizada em
**5 fetchers por contrato de dado**, um por tipo de entidade regulada
pela CVM. `issuer_fetch()` é funcional e cobre v0.1–v0.3 (grupo
`companhias`); os outros 4 são skeletons exportados que abortam com
`cvmdata_error_input_group`, com implementação plena em v0.4–v0.8.
Skeletons foram exportados antes da implementação para **travar a
superfície da API pública cedo**, de modo que as releases v0.4+
estendam cobertura sem reformatar a API.

```r
# Issuer datasets — companhias abertas (grupo CKAN "companhias").
# Cobertura por dataset/sessão vive no ROADMAP.md — não duplicar status aqui.
issuer_fetch(dataset, table,
             issuer      = NULL,      # CNPJ / CD_CVM / texto, vetor
             year        = NULL,      # integer vector, NULL → último
             source      = NULL,      # via cvm_source_get()
             report_type = NULL,      # "ind" / "con" / NULL
             on_error    = "abort",
             validate    = "strict",
             ...)

# Skeletons (abort com cvmdata_error_input_group no ciclo atual)
fund_fetch(dataset, table, fund = NULL, date = NULL, ...)        # v0.4-v0.6
agent_fetch(dataset, table, agent = NULL, as_of = NULL, ...)     # v0.7
offering_fetch(dataset, table, offering = NULL,
               date_range = NULL, ...)                            # v0.7
event_fetch(dataset, table, event = NULL, date_range = NULL, ...)  # v0.8

# Descoberta
cvm_groups()                                          # 18 grupos + contrato
cvm_datasets(group = NULL)                            # datasets disponíveis
cvm_tables(dataset, group = NULL)                     # tabelas de um dataset
cvm_dictionary(dataset, table, group = NULL)          # dicionário do snapshot
cvm_codelist(dataset, table, column, group = NULL)    # valores categóricos
cvm_dataset_years(dataset, group = NULL)              # range de anos publicados

# Cache
cvm_cache_path()
cvm_cache_set_path(path)
cvm_cache_clear(what = c("all", "raw", "parquet"),
                group = NULL, dataset = NULL, year = NULL,
                confirm = interactive())
cvm_cache_info()

# Source
cvm_source_get()
cvm_source_set(source)

# Utilidades
cnpj_clean(x)
cnpj_format(x)                # inverso de cnpj_clean
```

Argumento `group` nas funções de descoberta resolve por unicidade quando
omitido (`NULL`); a partir de v0.4, quando um slug de dataset puder
ocorrer em mais de um grupo, omitir `group` aborta com
`cvmdata_error_input_ambiguous`.

Domínio dos argumentos enumerados (validados via `rlang::arg_match0()`):

- `source ∈ c("mirror", "cvm")`. **Default `"mirror"`**: lê parquets do
  release `mirror-<group>-<dataset>-latest` via API GitHub + DuckDB
  local; ~30× mais rápido que `"cvm"`. Backend `"cvm"` (portal aberto
  `dados.cvm.gov.br`) permanece suportado por chamada explícita
  (`source = "cvm"`) ou via `cvm_source_set("cvm")` para frescor byte
  a byte. Precedência: arg explícito > `getOption("cvmdata.source")` >
  default. A assinatura declara `source = NULL` para consulta dinâmica
  do option (mesmo padrão de `cvm_cache_path()` ↔ `cvm_cache_set_path()`).
- `validate ∈ c("strict", "warn", "skip")`, default `"strict"`.
- `on_error ∈ c("abort", "warn", "silent")`, default `"abort"`.
- `report_type ∈ c("ind", "con")` ou `NULL` (só em `issuer_fetch()`).
  **Obrigatório** para tabelas com variantes individual/consolidada
  (`bpa`, `bpp`, `dre`, `dra`, `dfc_md`, `dfc_mi`, `dmpl`, `dva`).
  **Erro** se passado a tabelas sem essa distinção
  (`composicao_capital`, `submissao`, `parecer`, `companhias`).
- `year`: integer vector ou `NULL`. `NULL` → **último ano disponível**,
  descoberto por `HEAD` probing decrescente. Para histórico, integer
  vector explícito (`year = 2012:2024`). Helper `cvm_dataset_years()`
  devolve o range. **Sem sentinela `"all"`** — tipo único.

Sobre exercícios contidos em cada CSV anual: o portal publica em cada
ano apenas `ORDEM_EXERC ∈ {ÚLTIMO, PENÚLTIMO}` — o ano declarado e
seu N-1. `issuer_fetch()` não reconstrói o antepenúltimo: retorna o
conteúdo literal do CSV do `year` pedido. Para histórico mais longo,
pedir `year = (N-2):N` e empilhar; dedup por
`(cd_cvm, cd_conta, dt_fim_exerc)` é trivial.

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

CGVN/VLMO/IPE seguem uma terceira convenção (FRE-detail-like): mesma
`cnpj_companhia` / `data_referencia`, mas a coluna CVM-code se chama
`codigo_cvm` (não `cd_cvm`). O resolver `match_by_cd_cvm()` aceita
qualquer das duas via helper interno `cdcvm_col(df)`; semântica
idêntica.

### 2.3 Submissão (header de ITR/DFP/FRE)

Tabela de cabeçalho dos três datasets chama-se `submissao`. 9 campos:
`cnpj_cia`, `dt_refer`, `versao`, `denom_cia`, `cd_cvm`, `categ_doc`,
`id_doc`, `dt_receb`, `link_doc`.

### 2.4 Regra dos identificadores → character

Campos identificadores (CNPJ, CD_CVM, CEP, telefones, CPF, ID_*,
DDI/DDD, protocolos, ticker B3) são forçados a **character** mesmo
quando o META declara `numeric`. O META da CVM declara mal — CEPs
perdem zero à esquerda, CD_CVM tem padding heterogêneo entre datasets,
ID_Item da CGVN é `N.N.N`, etc. Implementação em
`R/util-csv-cvm.R::identifier_columns()`: classificação por **prefixos
regex** (`^cnpj`, `^cpf`, `^codigo_`, `^cd_cvm`, `^cep`, `^ddi_`,
`^ddd_`, `^id_`, `^protocolo`) **+ exact-match** para os esquisitos
(`caixa_postal`, `tel`, `versao`). Refator de v0.2 — Sessão 10 —
substituiu a lista monolítica de regex `.identifier_patterns` por
duas listas planas + um helper testável.

### 2.5 Datas

Conversão para `Date` é **automática** sempre que o snapshot de
dicionário declarar `tipo_dados = "date"`.

### 2.6 vl_conta × escala_moeda

Em tabelas ITR/DFP contábeis: `VL_CONTA` é multiplicada por
`ESCALA_MOEDA` (`UNIDADE`=1, `MIL`=1e3, `MILHÃO`=1e6, `BILHÃO`=1e9) e
retornada em reais absolutos. `escala_moeda` é removida do tibble;
`moeda` mantida (constante `"REAL"` na v0.1).

### 2.7 Seleção de companhias via `issuer`

Argumento único com **detecção automática de tipo** (implementado em
`filter_by_issuer()` em `R/api-issuer-fetch.R`):

| Padrão do input (após `as.character()`) | Interpretação | Match contra |
|---|---|---|
| `^[0-9]{14}$` | CNPJ sem pontuação | `cnpj_clean(cnpj_cia)` |
| Contém `.` ou `/` ou `-` e tem 14 dígitos | CNPJ com pontuação | `cnpj_cia` literal e/ou `cnpj_clean(cnpj_cia)` |
| `^[0-9]{1,6}$` | CD_CVM | `cd_cvm` (com ou sem zero-padding); se a tabela não tem `cd_cvm`, resolve para CNPJ via `submissao` |
| Resto (≥1 token alfabético) | Busca textual com fronteira de palavra e mapa de abreviações (`BCO ↔ BANCO`, `CIA ↔ COMPANHIA`, `S.A. ↔ S/A`) | `denom_cia` normalizada |

Resolução CD_CVM → CNPJ via `submissao`: quando o usuário passa CD_CVM
contra uma tabela sem `cd_cvm` (`composicao_capital`, `parecer`), o
pipeline lê a `submissao` do mesmo dataset/year e faz lookup antes de
filtrar. CD_CVMs ausentes na `submissao` daquele ano abortam com
`cvmdata_error_input`. Datasets sem tabela `submissao` abortam com
mensagem instruindo o uso de CNPJ ou texto.

Match textual: múltiplas matches em modo `interactive()` exibem lista
numerada via `utils::menu()`; em batch/CI abortam com
`cvmdata_error_input` listando candidatos. Zero matches aborta com
`cvmdata_error_input`.

Política de versão: por default, mantém apenas o registro de maior
`VERSAO` por `(cnpj_cia, dt_refer)` via transformação canônica
`keep_latest_version` no YAML.

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

## 4. Estrutura do pacote

**Régua R/ é flat.** `R CMD INSTALL` ignora subpastas de `R/` — a
representação modular do canônico de arquitetura fica como referência
conceitual; arquivos reais usam **prefixos de hífen**:

| Prefixo | Conteúdo |
|---|---|
| `api-` | Fetchers públicos (`issuer`, `fund`, `agent`, `offering`, `event`) + `cvm-groups` |
| `schema-` | Loader de YAML (`schema-load.R`) |
| `source-` | Backends de dados (`source-cvm-http.R`, `source-mirror-duckdb.R`) |
| `transform-` | Transformações declarativas (`transform-schema.R`) |
| `util-` | Helpers internos (`util-cnpj.R`, `util-errors.R`, `util-attrs.R`, etc.) |
| (sem prefixo) | API estável transversal: `cache.R`, `discovery.R`, `source.R`, `cvmdata-package.R` |

Layout dos schemas: `inst/extdata/schemas/<group>/<dataset>/<table>.yaml`
(`<group>` é o slug CKAN; `"companhias"` para os 4 datasets de v0.1
e `cgvn` adicionado no ciclo `0.1.0.9000`).
Layout do ETL: `inst/etl/{00-config,01-fetch-cvm,02-csv-to-parquet,02b-validate,03-publish,util-hash}.R`.

`data-raw/` mistura **build scripts** regeneráveis (`build-*.R` para
snapshots, fixtures e vignette data) com **auditorias one-shot**
(`run-capacity-audit.R`, `validate-mirror-end-to-end.R`) e
**`data-raw/decisions/`**. Os canônicos NÃO vivem todos no mesmo lugar:
- **Raiz do repo**: `cvmdata_rodada2-5_naming_unificado-v03.md` (naming)
  e `cvmdata_rodada3-0-2_politica_reader_sem_meta.md` (reader), junto
  com os demais docs `cvmdata_rodada*.md` e os `PROMPT_CLAUDE_*.md` de
  sessão.
- **`data-raw/decisions/`**: `cvmdata_arquitetura_grupos_decisao_v2.md`
  (arquitetura de grupos) + docs de planejamento v0.2
  (`cvmdata_v0-2_*.md`).

Apenas os build scripts são regenerados em ciclo normal; canônicos só
mudam por decisão deliberada.

Documentação narrativa em `vignettes/`: `cvmdata.Rmd` é o vignette
canônico embarcado no tarball (overview do pacote); `vignettes/articles/`
contém artigos longos publicados **apenas no site pkgdown**
(`.Rbuildignored`), sem peso na tarball CRAN.

---

## 5. Sistema de classes S3

S3 minimalista. Classes internas:

- `cvm_tbl` — subclasse de `tbl_df`. Todo tibble retornado por
  funções públicas. Carrega 6 atributos em inglês: `source`,
  `fetched_at`, `group`, `dataset`, `table`, `package_version`.
- `cvm_table_schema` — objeto interno descrevendo o schema lido do
  YAML. Carrega `$group` stampado por `load_schema()` para que os
  callers downstream propaguem sem re-lookup.
- `cvm_source` — handle interno para dispatch HTTP / mirror / cache.

`print.cvm_tbl()` é o único método print custom: exibe `source`,
`fetched_at`, `group`, `dataset` e `table` antes do tibble normal,
depois delega a `NextMethod()`.

---

## 6. Hierarquia de classes de condição

```
cvmdata_error                          (pai genérico de erros)
├── cvmdata_error_input                (argumento inválido do usuário)
│   ├── cvmdata_error_input_ambiguous  ((dataset, table) ocorre em mais
│   │                                   de um group; passar group explícito)
│   └── cvmdata_error_input_group      (fund/agent/offering/event_fetch
│                                       chamada antes da implementação plena
│                                       — aponta para ROADMAP)
├── cvmdata_error_http                 (falha de rede / HTTP)
├── cvmdata_error_parse                (falha de parse ou validação)
├── cvmdata_error_meta_unavailable     (META oficial não publicado — strict)
└── cvmdata_error_internal             (qualquer outro)

cvmdata_warn                           (pai genérico de warnings)
├── cvmdata_warn_validation            (divergência no warn mode)
├── cvmdata_warn_meta_unavailable      (META ausente, warn mode)
├── cvmdata_warn_year_fallback         (year = NULL caiu para ano anterior
│                                       porque max year não tinha dados da
│                                       companhia pedida)
├── cvmdata_warn_partial_failure       (batch yearly: alguns anos falharam
│                                       HTTP sob on_error = "warn"; demais
│                                       sobreviventes empilhados e retornados)
└── cvmdata_warn_eviction              (LRU eviction removeu unidades do
                                        cache local para honrar
                                        options(cvmdata.cache_max_size_mb))
```

Implementação via wrapper interno `cvmdata_abort(message, class, ...)`
que adiciona `"cvmdata_error"` ao final do vetor de classes
automaticamente. Análogo `cvmdata_warn()` para warnings.

---

## 7. Política do reader em três modos validate

| `validate` | Tabela com META | Tabela sem META |
|---|---|---|
| `"strict"` (default) | Valida; divergência → `cvmdata_error_parse` | Aborta com `cvmdata_error_meta_unavailable` |
| `"warn"` | Valida; divergência → `cvmdata_warn_validation` | Emite `cvmdata_warn_meta_unavailable` e entrega tibble |
| `"skip"` | Pula validação | Pula validação (silencioso) |

Mensagens em inglês, via `cli::cli_abort()` / `cli::cli_warn()`. Símbolo
`x` para erro, `!` para warning, `i` para info. Sob `meta_status: missing`
em modo `"warn"`, o reader valida `expected_field_names` do YAML contra
o cabeçalho do CSV (defesa em profundidade).

8 tabelas FRE têm `meta_status: missing` (sem META oficial CVM):
`administrador_PCD`, `empregado_PCD`,
`empregado_local_declaracao_genero`, `empregado_local_declaracao_raca`,
`empregado_posicao_declaracao_genero`,
`empregado_posicao_declaracao_raca`, `empregado_posicao_faixa_etaria`,
`empregado_posicao_local`.

Schema do YAML por tabela: campos canônicos (`dataset`, `table`,
`cvm_archive_url_pattern` xor `cvm_file_url_pattern`, `cvm_file_pattern`,
`cvm_dictionary_url`, `meta_status`, `encoding`, `delimiter`,
`temporal_partitioning ∈ {none, yearly}`, `first_year`,
`expected_field_count`, `expected_field_names`, `transformations`).
Domínio de `action` em `transformations`: `multiply_by_scale` (requer
`scale_column:`), `drop`, `keep_latest_version` (aceita `keys: [...]`
opcional para compor chaves extras com a dupla implícita
`(cnpj, data)` — usado em `cgvn/praticas` com `keys: [id_item]`).
Detalhes no naming doc v03 e no loader (`R/schema-load.R`).

---

## 8. Cache

Cache em `tools::R_user_dir("cvmdata", which = "cache")`. Layout
`<group>`-aware:

- **L1** raw CVM: `<cache>/raw/<group>/<dataset>/[<year>/]`. Cobre CSV
  direto (CAD) e ZIP yearly (DFP/ITR/FRE). Sidecar `*.etag.rds` com
  ETag/Last-Modified/`fetched_at`. Invalidação por HEAD HTTP com TTL
  default 30 dias (`options(cvmdata.cache_ttl_seconds)`; `0` = sempre
  HEAD, `Inf` = nunca enquanto sidecar existir).
- **L3** parquet mirror:
  `<cache>/parquet/<group>/<dataset>/<table>/[report_type=R/]year=Y/part-0.parquet`.
  Sidecar `<cache>/parquet/<group>/<dataset>/__source_hash.json`
  invalida por hash content-addressed contra o asset homônimo do
  release. Sem TTL.
- **L4** memória da sessão: planejado (`cachem::cache_mem()`, 50 MB),
  ainda não em `Imports`. **L2** não é usado.

Fallback por `source`:

- `source = "mirror"` (default): L4 → L3 → GitHub Releases → erro.
- `source = "cvm"`: L4 → L1 → portal CVM HTTP → erro.

Eviction LRU: default 100 MiB
(`options(cvmdata.cache_max_size_mb)`). Quando soma > 90%, próximo
download dispara eviction até cair a 80%. Unidade: diretório do ano
para yearly, par `{artifact, sidecar}` para não-particionados.
`0`/negativo/`Inf` desligam a engine. Aviso agregado por
`cvmdata_warn_eviction` (opt-in `options(cvmdata.cache_warn_evictions)`
— default `interactive()`). CSVs extraídos via `unzip()` contam para o
limite mas não disparam eviction.

`cvm_cache_clear()` manual: `what ∈ c("all", "raw", "parquet")` +
`group/dataset/year` opcionais. `what = "all"` ignora filtros; senão
compõe `<cache>/<what>/<group>/<dataset>/<year>/` com cada segmento
opcional da direita pra esquerda. `what = "parquet"` rejeita `year`
(L3 aninha year sob table); para granularidade year-level usar
`what = "raw"`.

Mirror parquet: workflow semanal `etl-mirror.yaml` (cron `0 7 * * 2`)
roda matrix bidimensional `(group, dataset)` (`fail-fast: false`); cada
job encadeia os scripts `01→02→02b→03` com flags `--group --dataset`. O
publish detecta mudança via hash SHA-256 (`util-hash.R`) e skipa
republish quando o hash bate o anterior. Encoding dos asset names:
`<table>__report_type=R__year=Y__part-0.parquet` (Hive-style achatado);
GitHub Releases sanitiza `=` → `.` no URL público;
`parse_mirror_asset_name()` em `R/util-mirror-assets.R` tolera ambos.

---

## 9. Política de testes

- `testthat` 3.x edition 3, `Config/testthat/edition: 3`.
- **Sem rede em `tests/testthat/`**. Testes de integração em
  `test-integration-*.R` com `skip_on_cran()` + `skip_if_offline()` +
  guarda `CVMDATA_RUN_INTEGRATION=true`.
- **Mocks HTTP** via `httptest2` (e em alguns casos
  `httr2::with_mocked_responses()`).
- **Fixtures pequenos e reais** em `tests/testthat/fixtures/`: cada
  fixture com `*.meta.json` registrando origem. Inclui
  `cad_sample.csv`, ZIPs `{dfp,itr,fre,cgvn}_cia_aberta_2024.zip` e
  parquets `mirror-*.parquet` gerados por
  `data-raw/build-mirror-test-fixtures.R` (raw ZIPs do CGVN+ via
  `build_cgvn_raw_fixture()` no mesmo script; CAD/DFP/ITR/FRE foram
  commitados manualmente antes de o script existir).
- **Snapshot tests** para mensagens de erro, atributos serializados,
  estrutura de output (`dplyr::glimpse()` snapshotado).
- **Cobertura alvo 90%**.

Cache real fica em `tools::R_user_dir("cvmdata", "cache")`. Em testes,
é redirecionado para tempdir via `options(cvmdata.cache_dir = ...)`.

Gate por commit: `devtools::check() == 0E/0W/0N` com `--as-cran`, lint
clean, testes verdes, `pkgdown::build_site()` funcionando.

CI em `.github/workflows/`: `R-CMD-check.yaml` (matrix release/devel +
SO), `lint.yaml` (`lintr::lint_package()`), `test-coverage.yaml`
(covr → Codecov), `pkgdown.yaml` (deploy do site), `etl-mirror.yaml`
(cron `0 7 * * 2` + dispatch manual, ver §8). Os quatro primeiros
travam por push/PR; o quinto é operacional.

---

## 10. Workflow de desenvolvimento

- Modo **tracer bullet**: implementar a função mais simples ponta-a-ponta
  antes de generalizar.
- **Estado de execução vive em `ROADMAP.md`** — sessão por sessão, fase
  por fase. `CLAUDE.md` não duplica status; consultar o roadmap antes
  de assumir que algo está entregue.
- **Não reabrir decisões travadas** (canônicos das Rodadas 2.5/2.6/3.0,
  decisão de grupos 2026-05-25, decisões pós-3.4 em `NEWS.md` + git
  log). Se acha que precisa rever, perguntar antes de agir.
- **Não inventar URLs, nomes de arquivos CVM, conteúdo de schemas**.
  Usar YAMLs validados em `inst/extdata/schemas/` ou `schemas_proto/`
  para protótipos, ou perguntar.

### 10.1 Comandos não-óbvios

Comandos triviais de pacote R (`devtools::check()`, `devtools::test()`,
`devtools::document()`, `devtools::build_readme()`, `devtools::install()`,
`devtools::build()`, `lintr::lint_package()`, `covr::package_coverage()`)
não estão listados aqui — usar diretamente.

```powershell
# Um único teste por nome — desc parcial casa por regex
Rscript -e "testthat::test_file('tests/testthat/test-issuer-fetch-cad.R', desc = 'returns a cvm_tbl')"

# Regenerar README.pt-BR.md (build_readme() só cobre o canônico README.Rmd)
Rscript -e "knitr::knit('README.pt-BR.Rmd', output = 'README.pt-BR.md')"

# Regenerar snapshots/fixtures embarcados — batem no portal CVM real,
# exigem rede, ~30 s cada; rodar quando schemas ou geradores mudarem
Rscript data-raw/build-dictionary-snapshot.R    # inst/extdata/cvm_dictionary_snapshot.csv
Rscript data-raw/build-codelists-snapshot.R     # inst/extdata/cvm_codelists_snapshot.csv
Rscript data-raw/build-mirror-test-fixtures.R   # tests/testthat/fixtures/mirror-*.parquet
Rscript data-raw/build-vignette-data.R          # inst/extdata/vignette-data/*.rds

# ETL do mirror — dispatch manual (cron `0 7 * * 2` em etl-mirror.yaml)
gh workflow run etl-mirror.yaml

# ETL local (smoke) — --group + --dataset são obrigatórios
Rscript inst/etl/01-fetch-cvm.R       --group companhias --dataset cad
Rscript inst/etl/02-csv-to-parquet.R  --group companhias --dataset cad
Rscript inst/etl/02b-validate.R       --group companhias --dataset cad
Rscript inst/etl/03-publish.R         --group companhias --dataset cad
```

### 10.2 Stage `schemas_proto/`

Diretório `schemas_proto/` na raiz (excluído da tarball via
`.Rbuildignore`) é a área de stage para YAMLs antes da promoção para
`inst/extdata/schemas/<group>/<dataset>/<table>.yaml`. Workflow:
escrever o YAML em stage, validar contra dados reais com
`issuer_fetch(..., validate = "warn")` (ou o fetcher correspondente
quando v0.4+), ajustar `expected_field_count`/`expected_field_names`/
`transformations` até zero divergência, então mover para
`inst/extdata/schemas/`. Conteúdo atual de `schemas_proto/` é rascunho
parcial — não usar como fonte canônica.

### 10.3 Critério de inclusão das codelists

Lógica enterrada em `data-raw/build-codelists-snapshot.R`. Replicar se
o gerador for revisitado:

- **Pelo dicionário**: colunas onde `dominio` enumera valores com
  separador `/` ou `|` (capta `S/N`, `PF/PJ`).
- **Por cardinalidade observada**: colunas `tipo_dados = "varchar"`
  com `tamanho < 200` e ≤ 50 valores distintos no último ano,
  EXCLUINDO prefixos: identificadores (`cnpj`, `cd_cvm`, `codigo_cvm`,
  `cep`, `tel`, `ddd`, `cpf`, `id_doc`, `id_documento`, `versao`),
  `^cd_` (códigos contábeis), `^nome_`/`^denom_` (nomes próprios),
  `^ds_` (descrições texto livre), `^email`/`^logradouro`/`^compl`/
  `^bairro`/`^mun($|_)`/`^municipio_` (endereço).
- **Tabelas `meta_status: missing`**: excluídas (declarar codelist sem
  ancoragem CVM violaria "se vem da CVM, fica como na CVM").

---

## 11. Objetivos do projeto

- **Gate de qualidade**: rOpenSci via review formal em
  <https://github.com/ropensci/software-review>. Ancora todo o trabalho
  enquanto princípio de design — decisões que não passem o filtro
  "isso ajuda ou atrapalha a aceitação rOpenSci?" devem ser rejeitadas.
- **Timing de submissão** (decisão de 2026-05-28): a submissão ao
  rOpenSci ocorre **ao fim do ciclo de desenvolvimento, após v1.0**,
  com os 5 fetchers funcionais e os 18 grupos CKAN cobertos — não como
  etapa intermediária.
- **CRAN**: permanece **acoplado ao aceite rOpenSci**; rOpenSci submete
  em nome do mantenedor quando aceito.
- **The R Journal**: paper sobre o pacote, **somente após o aceite
  rOpenSci**.

Sequenciamento canônico em `ROADMAP.md`, seção "Fim do ciclo —
submissão rOpenSci, CRAN e publicação".
