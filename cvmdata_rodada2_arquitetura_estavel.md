# cvmdata — Arquitetura estável (extrato canônico da Rodada 2)

> **Status**: extrato consolidado em 2026-05-19 a partir do
> `cvmdata_rodada2_plano_arquitetural-v02.md` original (arquivado em
> `archive/`). Este documento contém **apenas as seções da Rodada 2
> que permanecem válidas após as rodadas posteriores** (2.5, 2.6,
> 3.0, 3.0.1, 3.0.2).
>
> **Seções removidas do original** (motivo entre parênteses):
>
> - §0 Status do documento (changelog histórico Rodada 2.5).
> - §1 Sumário Executivo (continha nomes hoje obsoletos — `fetch_cvm`,
>   `cnpj`, `period_end_date` etc.; conteúdo canônico está no naming
>   doc v03 e no fechamento da Rodada 1).
> - §3 Design da API Pública (substituído pelo naming doc v03 §1-§6).
> - §4 Schemas Tidy de Saída (substituído pelo naming doc v03 §3-§4 +
>   `cvmdata_rodada2-6_schemas.md` + YAMLs protótipo em
>   `schemas_proto/`).
> - §12.3 Pendências para Rodada 2.5 (já resolvidas; vide naming doc).
>
> **Seções mantidas neste extrato**: §2 (Arquitetura), §5 (Cache),
> §6 (ETL), §7 (Validation), §8 (Testes), §9 (CI/CD), §10
> (Documentação), §11 (Roadmap), §12 (Riscos/Premissas) — esta última
> com §12.3 filtrada.
>
> ---
>
> ## Régua de leitura para Claude Code
>
> **Quando há conflito entre este documento e o naming doc v03 ou os
> documentos da Rodada 3.0/3.0.2, prevalece o material posterior.**
> Em particular, os nomes abaixo que aparecem no texto a seguir devem
> ser interpretados conforme o mapeamento canônico atual:
>
> | No texto deste documento | Nome canônico atual (naming v03) |
> |---|---|
> | `fetch_cvm()` | `cvm_fetch()` |
> | `fetch_cad()`, `fetch_itr()`, `fetch_dfp()`, `fetch_fre()` | `cad_fetch()`, `itr_fetch()`, `dfp_fetch()`, `fre_fetch()` |
> | `fetch_fii()`, `fetch_fidc()` | `fii_fetch()`, `fidc_fetch()` |
> | `cnpj` (coluna) | `cnpj_cia` (com pontuação como vem da CVM) |
> | `cvm_code` (coluna) | `cd_cvm` (character, não integer) |
> | `company_name` (coluna) | `denom_cia` |
> | `reference_date` (coluna) | `dt_refer` |
> | `period_start_date`, `period_end_date` | `dt_ini_exerc`, `dt_fim_exerc` |
> | `version` (coluna) | `versao` (character) |
> | Nomes de tabela em EN (`balance_sheet_*`, `audit_opinion`, etc.) | Em PT, snake_case: `bpa_con`, `parecer`, `composicao_capital`, `orgao_administracao`, etc. |
> | Valores de células em EN | Em PT como vêm da CVM: `"Conselho de Administração"`, `"ÚLTIMO"`, `"PENÚLTIMO"`, `"REAL"`, `"MIL"` |
> | `validate = TRUE/FALSE` (booleano) | `validate = "strict"`/`"warn"`/`"skip"` |
> | `on_error = TRUE/FALSE` | `on_error = "abort"`/`"warn"`/`"silent"` |
>
> Atributos do tibble retornado (`source`, `fetched_at`, `dataset`,
> `table`, `package_version`) **permanecem em inglês** — vide naming
> doc v03 §5.
>
> Princípio reitor (naming doc §0.1): *"se vem da CVM, fica como na
> CVM (snake_case minúsculo); se não vem da CVM, é decisão do
> pacote."* Vale para nomes de tabela, nomes de coluna do tibble
> retornado por `cvm_fetch()`, valores categóricos e texto livre.
>
> ## Documentos canônicos a consultar em paralelo
>
> - `cvmdata_rodada1_fechamento.md` — escopo macro, fontes de dados,
>   versões.
> - `cvmdata_projeto_instrucoes_customizadas-v02.md` — régua de
>   idioma, tom, convenções de código.
> - `cvmdata_rodada2-5_naming_unificado-v03.md` — **naming canônico**;
>   prevalece em todos os conflitos com este extrato.
> - `cvmdata_rodada2-6_schemas.md` + `schemas_proto/` — YAMLs
>   protótipo e padrão de schema por tabela.
> - `cvmdata_rodada3-0_decisoes_pre_implementacao.md` — formato CSV
>   para snapshots de dicionário e codelists; nome `submissao` para
>   tabela de cabeçalho ITR/DFP/FRE.
> - `cvmdata_rodada3-0-2_politica_reader_sem_meta.md` — política do
>   reader para tabelas FRE sem META; refinamentos à hierarquia de
>   classes de condição (`cvmdata_warn`, `cvmdata_error_meta_unavailable`).

---

## 2. Arquitetura de Pacote

### 2.1 Estrutura de diretórios

#### 2.1.1 Alternativas avaliadas

**Alternativa A: organização por função.**

```
R/
├── api/              # fetch_cvm, fetch_itr, fetch_dfp, ...
├── schemas/          # schema definitions, transformations
├── cache/            # cache backend
├── mirror/           # mirror access, DuckDB queries
├── http/             # CKAN, HTTP utilities
├── validation/       # pointblank wrappers
└── utils/            # helpers
```

Prós: minimiza acoplamento entre módulos; modificações no cache não
tocam schemas. Contras: força um único diretório `schemas/` que cresce
linearmente com o número de classes (companies + funds + FII + FIDC).
Em v0.4+ o `schemas/` teria centenas de arquivos misturando classes.

**Alternativa B: organização por classe de entidade.**

```
R/
├── companies/        # fetch_itr, fetch_dfp, schemas_companies, ...
├── funds/            # fetch_fii, schemas_funds, ...
├── core/             # fetch_cvm, dispatch, cache, mirror
└── utils/
```

Prós: cada classe é um módulo autocontido; alinha com a forma como o
escopo é entregue em versões (v0.1 mexe só em `companies/`). Contras:
duplicação se duas classes precisarem da mesma utilidade (ex: parser
de CSV CVM é igual para companhias e fundos).

**Alternativa C: híbrido (recomendada).**

```
R/
├── api/                          # public API entry points
│   ├── fetch_cvm.R               # generic dispatcher
│   ├── fetch_companies.R         # fetch_itr, fetch_dfp, fetch_fre, fetch_cad
│   └── fetch_funds.R             # placeholder for v0.4+
├── schemas/                      # schema definitions per class
│   ├── companies/
│   │   ├── schema_cad.R
│   │   ├── schema_itr.R
│   │   ├── schema_dfp.R
│   │   └── schema_fre.R
│   └── funds/                    # placeholder for v0.4+
├── transform/                    # CVM raw → tidy transformations
│   ├── companies_transform.R
│   └── shared_transform.R        # parsers shared across classes
├── source/                       # data source backends
│   ├── source_cvm_http.R         # primary: CVM HTTP
│   ├── source_mirror_duckdb.R    # secondary: GitHub mirror
│   └── source_cache_local.R      # local cache
├── dispatch/                     # internal routing
│   ├── dispatch_class.R          # dataset → class resolution
│   └── dispatch_table.R          # class + table → schema lookup
├── validate/                     # pointblank wrappers
│   └── validate_companies.R
├── utils/
│   ├── http.R                    # CKAN, range requests, retries
│   ├── csv_cvm.R                 # ISO-8859-1, semicolon, decimal parsing
│   ├── encoding.R                # latin1 → UTF-8
│   ├── attrs.R                   # source attribute machinery
│   ├── cli.R                     # message formatting
│   └── zzz.R                     # .onLoad, .onUnload, package options
└── package_metadata.R            # metadata constants
```

#### 2.1.2 Recomendação e justificativa

Recomendada: **Alternativa C (híbrido)**.

Justificativa:

- Mantém um único ponto de entrada para a espinha dorsal
  (`R/api/fetch_cvm.R`).
- Isola schemas por classe (`R/schemas/companies/`,
  `R/schemas/funds/`) sem precisar inventar nomes longos.
- Centraliza utilidades genuinamente compartilhadas (`R/utils/`,
  `R/source/`, `R/transform/shared_transform.R`).
- A expansão v0.4+ exige apenas (a) adicionar arquivos em
  `R/schemas/funds/`, (b) implementar `fetch_funds.R`, (c) registrar
  novos datasets no dispatcher. Zero refatoração de companhias.

#### 2.1.3 Estrutura completa do diretório do pacote

> **Nota — `R/` é flat [correção 2026-05-19]**. A representação abaixo
> exibe subpastas em `R/` (`R/api/`, `R/schemas/companies/`, etc.) como
> forma de comunicar **agrupamento modular**, não estrutura literal de
> filesystem. `R CMD INSTALL`, `R CMD check` e o package loader do R
> só carregam arquivos em `R/*.R` — subpastas de `R/` são **ignoradas
> silenciosamente** (sem warning), o que faz `devtools::check()` passar
> verde sem ter visto o código. Nenhum pacote CRAN/rOpenSci do nicho
> (`microdatasus`, `rb3`, `GetDFPData2`, `tidycensus`, `dplyr`,
> `usethis`, `httr2`) usa subpastas em `R/`.
>
> **Régua operacional travada na Sessão 1 da Rodada 3 plena**: `R/` é
> flat, com **prefixos de hífen** convertendo os agrupamentos do
> diagrama em prefixos de arquivo:
>
> | Agrupamento conceitual (diagrama) | Arquivo real |
> |---|---|
> | `R/api/fetch_companies.R` | `R/api-fetch-companies.R` |
> | `R/api/fetch_cvm.R` (futuro) | `R/api-fetch-cvm.R` |
> | `R/schemas/load.R` | `R/schema-load.R` |
> | `R/schemas/companies/schema_cad.R` (futuro) | `R/schema-companies-cad.R` |
> | `R/source/source_cvm_http.R` | `R/source-cvm-http.R` |
> | `R/source/source_mirror_duckdb.R` (futuro) | `R/source-mirror-duckdb.R` |
> | `R/transform/transform_cad.R` | `R/transform-cad.R` |
> | `R/dispatch/dispatch_class.R` (futuro) | `R/dispatch-class.R` |
> | `R/validate/validate_companies.R` (futuro) | `R/validate-companies.R` |
> | `R/utils/csv_cvm.R` | `R/util-csv-cvm.R` |
> | `R/utils/attrs.R` | `R/util-attrs.R` |
> | `R/utils/errors.R` | `R/util-errors.R` |
> | `R/utils/print_cvm_tbl.R` | `R/util-print-cvm-tbl.R` |
>
> A árvore abaixo permanece como **referência conceitual** do plano
> arquitetural; o mapeamento acima é o que entra no tarball.

```
cvmdata/
├── DESCRIPTION
├── NAMESPACE                      # auto-gerado por roxygen2
├── NEWS.md
├── LICENSE                        # MIT (proposta)
├── LICENSE.md
├── README.md                      # inglês, canônico
├── README.Rmd                     # fonte do README.md
├── README.pt-BR.md                # complementar opcional
├── R/                             # ver Alternativa C acima
├── man/                           # auto-gerado por roxygen2
├── tests/
│   ├── testthat.R
│   └── testthat/
│       ├── _snaps/                # snapshots testthat 3.x
│       ├── fixtures/              # ZIPs pequenos e CSVs de teste
│       │   ├── itr_mini.zip
│       │   ├── fre_mini.zip
│       │   └── cad_mini.csv
│       ├── helper-cvmdata.R       # helpers compartilhados
│       ├── helper-mocks.R         # mocks de HTTP, mirror
│       ├── test-fetch_cvm.R
│       ├── test-fetch_itr.R
│       ├── test-fetch_dfp.R
│       ├── test-fetch_fre.R
│       ├── test-fetch_cad.R
│       ├── test-schemas.R
│       ├── test-dispatch.R
│       ├── test-cache.R
│       ├── test-source.R
│       ├── test-transform.R
│       ├── test-validate.R
│       └── test-utils.R
├── vignettes/
│   ├── cvmdata.Rmd                # introdução geral
│   ├── itr-dfp.Rmd                # demonstrações financeiras
│   ├── fre.Rmd                    # formulário de referência (ESG)
│   ├── cache-and-mirror.Rmd       # entendendo as fontes
│   └── roadmap.Rmd                # planejamento v0.2/v0.3/v0.4+
├── data-raw/                      # scripts de geração de dados internos
│   ├── build_dataset_index.R      # gera inst/extdata/dataset_index.rds
│   ├── build_table_index.R        # gera inst/extdata/table_index.rds
│   ├── build_company_index.R      # gera inst/extdata/company_index.rds
│   └── README.md
├── inst/
│   ├── extdata/                   # dados embarcados pequenos
│   │   ├── dataset_index.rds      # mapa dataset → classe → URL CKAN
│   │   ├── table_index.rds        # mapa dataset → tabelas internas
│   │   └── schema_versions.rds    # histórico de schemas por ano
│   └── WORDLIST                   # spell-check whitelist
├── pkgdown/
│   ├── _pkgdown.yml
│   ├── extra.css
│   └── extra.scss
├── .github/
│   ├── workflows/
│   │   ├── R-CMD-check.yaml
│   │   ├── test-coverage.yaml
│   │   ├── lint.yaml
│   │   ├── pkgdown.yaml
│   │   └── etl-mirror.yaml
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.yaml
│   │   └── feature_request.yaml
│   └── pull_request_template.md
├── .gitignore
├── .Rbuildignore
├── .lintr
├── .editorconfig
├── codecov.yml
├── _pkgdown.yml -> pkgdown/_pkgdown.yml  # opcional
└── cran-comments.md
```

### 2.2 Sistema de classes: S3, S4 ou R6?

#### 2.2.1 Alternativas

**S3.** Pseudo-OO baseada em atributo `class`. Dispatch leve via
`UseMethod()`. Padrão do tidyverse (tibble, vctrs, ggplot2, dplyr).

**S4.** Sistema OO formal com slots e definições de classe via
`setClass()`. Padrão do Bioconductor. Dispatch multi-argumento.

**R6.** OO clássico por referência. Objetos mutáveis. Útil para
clientes HTTP statefull, conexões persistentes, sessões.

#### 2.2.2 Recomendação e justificativa

Recomendada: **S3 minimalista**.

Justificativa:

- Aderência ao tidyverse: o retorno é um tibble, e tibble já é S3. O
  output `fetch_itr()` é um tibble com uma subclasse adicional
  (`cvm_tbl`, herdando de `tbl_df`, `tbl`, `data.frame`).
- Dispatch interno do `fetch_cvm()` é resolvido por `switch()` sobre
  `dataset`, não por dispatch S3 explícito. Não há benefício em S4
  para esse caso.
- Não há objetos mutáveis longos: cada chamada `fetch_*()` é
  funcional. Não justifica R6.
- S3 mantém a curva de aprendizagem do código mais baixa para
  contribuidores futuros — característica relevante dado o objetivo de
  longo prazo de comunidade.

Classes S3 internas do pacote:

- `cvm_tbl` (subclasse de `tbl_df`) — todo tibble retornado pelas
  funções públicas. Carrega atributos `source`, `fetched_at`,
  `n_entities`, `class_entity`, `dataset`, `tables`.
- `cvm_dataset_spec` — objeto interno descrevendo um dataset (URL
  CKAN, classe de entidade, tabelas internas esperadas, schema map).
- `cvm_table_schema` — objeto interno descrevendo o schema de uma
  tabela: nome CVM original, nome tidy, colunas (mapa CVM → tidy),
  tipos, regras de transformação.
- `cvm_source` — objeto interno representando a fonte ativa
  (`cvm_source_http`, `cvm_source_mirror`, `cvm_source_cache`),
  servindo como handle para dispatch.

Print methods custom apenas para `cvm_tbl` (exibe os atributos de
proveniência junto com o tibble normal):

```r
#' @export
print.cvm_tbl <- function(x, ...) {
  src <- attr(x, "source", exact = TRUE)
  fetched <- attr(x, "fetched_at", exact = TRUE)
  cli::cli_inform(c(
    "i" = "{.field source}: {src}",
    "i" = "{.field fetched_at}: {fetched}"
  ))
  NextMethod()
}
```

### 2.3 Dependências

#### 2.3.1 `Imports`

Pacotes carregados sempre que `cvmdata` é carregado. Cada um precisa
de justificativa porque pesa no `R CMD check` da instalação.

| Pacote        | Por quê                                                              | Versão mínima sugerida |
|---------------|----------------------------------------------------------------------|:----------------------:|
| `tibble`      | Tipo de retorno padrão; print methods, attribute preservation        | >= 3.2.0               |
| `vctrs`       | Coerção segura de tipos, especialmente em colunas monetárias e datas | >= 0.6.0               |
| `rlang`       | `abort()`, `warn()`, `inform()`, `arg_match()`, NSE                  | >= 1.1.0               |
| `dplyr`       | Joins entre tabelas internas (FRE), filtragens por entidade          | >= 1.1.0               |
| `purrr`       | `map_dfr()`, `pmap()` para iterar sobre anos/empresas                | >= 1.0.0               |
| `stringr`     | Normalização de nomes de empresa, CNPJ                               | >= 1.5.0               |
| `readr`       | `read_delim()` com encoding ISO-8859-1, separador `;`                | >= 2.1.0               |
| `httr2`       | HTTP client moderno (sucessor de httr), retries, timeouts            | >= 1.0.0               |
| `arrow`       | Leitura de Parquet local e remoto (mirror)                           | >= 14.0.0              |
| `duckdb`      | Engine SQL para queries no mirror Parquet                            | >= 1.0.0               |
| `cli`         | Formatação de mensagens (informativas, warnings, erros)              | >= 3.6.0               |
| `withr`       | `with_options()`, `with_dir()` em código interno                     | >= 2.5.0               |

Justificativas adicionais:

- **`arrow` + `duckdb` juntos**: `arrow` faz a leitura local rápida
  do Parquet quando o usuário tem o arquivo no cache; `duckdb` faz
  query remota via HTTP range requests no GitHub Releases sem baixar
  o Parquet inteiro. São complementares, não redundantes.
- **`httr2` em vez de `httr`**: `httr` está em modo manutenção. Para
  um pacote novo entrando no CRAN em 2026, `httr2` é a escolha
  forward-compatible.
- **Não usar `data.table`**: o pacote é tidy-first. Operações de
  `dplyr` são suficientes na escala dos dados; quando o usuário
  precisar de performance extrema, pode converter o resultado via
  `data.table::as.data.table()` no seu código.

#### 2.3.2 `Suggests`

Dependências opcionais, usadas em vignettes, testes, ou features
não-críticas.

| Pacote          | Uso                                                                 |
|-----------------|---------------------------------------------------------------------|
| `testthat`      | Framework de testes (>= 3.0.0 para edition 3)                       |
| `pointblank`    | Validação de schemas (>= 0.12.0)                                    |
| `knitr`         | Renderização de vignettes                                           |
| `rmarkdown`     | Renderização de vignettes                                           |
| `covr`          | Cobertura de testes em CI                                           |
| `lintr`         | Lint em CI                                                          |
| `styler`        | Formatação de código em CI                                          |
| `ggplot2`       | Exemplos em vignettes (não é dependência funcional)                 |
| `scales`        | Formatação de números monetários em vignettes                       |
| `gt` ou `kableExtra` | Apresentação tabular em vignettes (escolher um na Rodada 3)    |

Decisão pendente: `pointblank` em `Imports` ou `Suggests`?

- Argumento Imports: validação acontece também no consumo runtime,
  não só no ETL.
- Argumento Suggests: a validação runtime pode ser opcional (o
  usuário decide ativá-la); só o ETL precisa garantidamente do
  pointblank.

Recomendação: **`Suggests`**, com a validação runtime sendo opt-in
via `options(cvmdata.validate_runtime = TRUE)`. Reduz peso de
instalação para usuários que só consomem dados. ETL roda em ambiente
CI controlado onde a instalação de `pointblank` é explícita.

#### 2.3.3 `Depends`

**Recomendação: vazio (exceto `R (>= 4.1)`).**

Justificativa: pacotes no `Depends` poluem o search path do usuário e
são desencorajados pelo guia tidyverse. `R (>= 4.1)` está no `Depends`
para garantir disponibilidade do pipe nativo `|>`.

```
Depends:
    R (>= 4.1)
```

#### 2.3.4 `LinkingTo`

**Vazio.** Nenhum código C/C++ próprio. `arrow` e `duckdb` têm suas
próprias dependências de compilação, mas são auto-contidas.

#### 2.3.5 `SystemRequirements`

`arrow` exige libarrow; `duckdb` traz seu próprio binário. Em macOS e
Windows os binários CRAN cobrem. Em Linux pode ser necessário
documentar:

```
SystemRequirements: libcurl: libcurl-devel (rpm) or libcurl4-openssl-dev (deb)
```

(herdado da dependência transitiva via `httr2`/`curl`).

### 2.4 Estratégia de namespace

#### 2.4.1 O que exportar

Funções públicas, exportadas via `@export` roxygen:

```
# Espinha dorsal multi-classe
fetch_cvm()

# Aliases tipados v0.1 (companhias)
fetch_cad()
fetch_itr()
fetch_dfp()
fetch_fre()

# Discovery / metadata
list_datasets()
list_tables()
list_companies()
cvm_metadata()

# Cache / source management
cvm_cache_path()
cvm_cache_clear()
cvm_cache_info()
cvm_source_info()
cvm_set_source()

# Print methods
print.cvm_tbl()
format.cvm_tbl()
```

Aliases tipados para fundos (v0.4+) — não exportados na v0.1:

```
fetch_fundos_555()
fetch_fii()
fetch_fidc()
```

#### 2.4.2 O que manter interno

Tudo o resto. Funções internas seguem convenção tidyverse com
prefixo `.` removido (não usar `.minha_funcao()`) — em vez disso,
manter funções não-exportadas no arquivo apropriado e identificá-las
por roxygen `@noRd`:

```r
#' Resolve CVM dataset id to its entity class
#' @noRd
resolve_dataset_class <- function(dataset) {
  # ...
}
```

#### 2.4.3 Re-exports

Recomendação: **não re-exportar** funções de `dplyr`, `tibble`, ou
similares. Isso evita confusão sobre origem das funções e segue a
convenção do guia tidyverse para pacotes que consomem (não estendem)
o tidyverse.

Única exceção possível: re-exportar o pipe `|>` é desnecessário
porque é base R (R >= 4.1).

### 2.4.4 Estratégia anti-conflito

Para todos os usos de funções de outros pacotes dentro do código
fonte do `cvmdata`, sempre qualificar via `pkg::fun()`:

```r
# RUIM
filter(df, cnpj == x)

# BOM
dplyr::filter(df, .data$cnpj == x)
```

Justificativa: `R CMD check --as-cran` exige; evita NOTES sobre
`undefined global functions`; torna explícita a origem de cada
função no código fonte (auditoria). Exceção: dentro de pipelines
longos onde a qualificação repetida prejudica legibilidade, usar
`@importFrom` no roxygen e manter qualificação no primeiro uso.

### 2.5 Padrão de nomeação de arquivos R/

Recomendação: **um arquivo por família de funções**, não um arquivo
por função.

Exemplos:

- `R/api/fetch_companies.R` contém `fetch_cad()`, `fetch_itr()`,
  `fetch_dfp()`, `fetch_fre()` — todas relacionadas a companhias.
- `R/schemas/companies/schema_itr.R` contém a definição de schema
  para todas as 19 tabelas do ITR.
- `R/utils/http.R` contém helpers HTTP genéricos.

Justificativa: arquivos por função produzem proliferação (centenas de
arquivos com 5-10 linhas cada). Famílias mantêm contexto e facilitam
navegação. Limite informal: arquivo com mais de ~600 linhas é sinal
de que precisa ser dividido.

Nomes de arquivos: `snake_case.R`, sem prefixos exceto `zzz.R` para o
arquivo de carga (.onLoad, .onUnload, package options).

### 2.6 Padrão de comentários em código

#### 2.6.1 Comentários em inglês

Política rígida: todo comentário, identifier, e mensagem em código
fonte do pacote é **em inglês**. Documento de planejamento (este
arquivo) é em português; código é em inglês.

Justificativa: CRAN policy não exige formalmente, mas é prática
universal em pacotes que pretendem ter alcance internacional. Pacotes
exclusivamente em português têm taxa de adoção reduzida fora do
Brasil mesmo entre usuários que poderiam se beneficiar.

#### 2.6.2 Estilo de comentários

- Comentários inline `# ...`: explicam **porquê**, não **o quê**. O
  código já explica o quê.
- Comentários de cabeçalho de arquivo: opcional, mas útil para
  arquivos longos. Resumo de 2-3 linhas no topo.
- TODO/FIXME/HACK: prefixados explicitamente e seguidos por iniciais
  do autor e issue/PR de referência: `# TODO(SSB): handle DFP edge
  case, see #42`.

#### 2.6.3 Padrão roxygen2

Toda função exportada tem bloco roxygen com:

- `@title` — uma frase
- `@description` — 1-3 frases
- `@param` para cada argumento
- `@return` descreve o tibble retornado, listando colunas-chave e
  atributos
- `@examples` — exemplos executáveis ou claramente marcados como
  `\dontrun{}` quando dependem de rede
- `@export`
- `@family` quando apropriado (ex: `@family fetchers`)
- `@seealso` para funções relacionadas

---

## 5. Estratégia de Cache

### 5.1 O que armazenar em cache

Decisão a tomar: três níveis possíveis de cacheamento.

| Nível | O que                                  | Tamanho típico | Quando útil                          |
|-------|----------------------------------------|----------------|--------------------------------------|
| L1    | ZIP raw da CVM                         | 30-100 MB/ano  | Recomputar transformações; auditoria |
| L2    | CSVs descompactados (UTF-8)            | 200-500 MB/ano | Acesso rápido sem unzip              |
| L3    | Parquet transformado                   | 10-50 MB/ano   | Query rápida via arrow/duckdb        |
| L4    | Tibble retornado (cachem em memória)   | varia          | Chamadas repetidas mesma sessão      |

Recomendação: **L1 + L3 + L4 (não L2)**.

Justificativa:

- **L1 (ZIP raw)** é a fonte de verdade. Cache permite reprocessar
  com novas transformações sem re-download. Tamanho aceitável (~1
  GB acumulado em 5 anos de ITR).
- **L2 (CSVs descompactados)** é redundante com L1 + extração
  on-demand. Custo de descompressão é baixo (<1s para ITR de uma
  empresa). Eliminado para economizar espaço.
- **L3 (Parquet)** é o output transformado pelo pacote. Permite
  consulta seletiva via DuckDB sem reparse de CSV. Aproveita schema
  tidy congelado.
- **L4 (memória)** evita recomputação dentro de uma sessão. Usa
  `cachem::cache_mem()` com limite agressivo (50 MB).

### 5.2 Localização

Padrão CRAN: `tools::R_user_dir("cvmdata", which = "cache")`.

Por sistema operacional:
- Linux: `~/.cache/cvmdata/`
- macOS: `~/Library/Caches/cvmdata/`
- Windows: `%LOCALAPPDATA%/cvmdata/cache/`

Estrutura dentro:

```
cvmdata/cache/
├── raw/                  # L1: ZIPs CVM
│   ├── cia_aberta-doc-itr/
│   │   ├── itr_cia_aberta_2024.zip
│   │   ├── itr_cia_aberta_2024.zip.meta.json   # ETag, mtime, sha256
│   │   └── ...
│   ├── cia_aberta-doc-dfp/
│   ├── cia_aberta-doc-fre/
│   └── cia_aberta-cad/
├── parquet/              # L3: transformados
│   ├── cia_aberta-doc-itr/
│   │   ├── bpa_con/
│   │   │   ├── year=2024/
│   │   │   │   └── part-0.parquet
│   │   │   ├── year=2025/
│   │   │   └── ...
│   │   ├── bpp_con/
│   │   └── ...
│   └── ...
├── manifest.duckdb       # índice DuckDB para queries cross-dataset
└── cache_meta.json       # metadados gerais (versão schema, last_purge, ...)
```

Justificativa do layout Parquet particionado: permite query DuckDB
otimizada por ano, leitura seletiva, e é compatível com o formato
exato do mirror remoto (mesma estrutura).

### 5.3 Política de invalidação

#### 5.3.1 Estratégias

Três mecanismos coexistem:

**a) ETag/Last-Modified HTTP.** Antes de servir cache L1, fazer
`HEAD` no endpoint CVM e comparar ETag/Last-Modified com metadata
salva. Se mudou, invalidar. Tempo da operação: ~200ms por dataset.

**b) TTL (time-to-live).** Padrão 30 dias. Após o TTL, cache é
considerado stale e o pacote refaz HEAD antes de servir.

**c) Manual.** `cvm_cache_clear()` permite limpeza total ou seletiva.

#### 5.3.2 Recomendação

Combinar (a) e (b): HEAD HTTP ao consultar, com TTL como upper bound
para evitar HEADs em sessões offline. Em modo `source = "cache"`,
ignorar TTL (assumir cache válido).

### 5.4 Tamanho máximo

#### 5.4.1 CRAN policy

CRAN policy explicita: pacotes não devem escrever em diretórios fora
do `tools::R_user_dir()` ou diretório temporário. Não há limite
formal, mas conduta esperada é "razoável".

Recomendação: limite default de **100 MB** total para cache, com
opção de aumentar via `options(cvmdata.cache_max_size_mb = ...)`.

#### 5.4.2 Política de eviction

Quando o cache atinge 90% do limite, remover arquivos por LRU (least
recently used) até cair abaixo de 70%.

### 5.5 Backend

#### 5.5.1 Para arquivos físicos (L1 + L3): direto no filesystem

Não usar `cachem` para arquivos grandes — `cachem` é otimizado para
key-value de valores R em memória, não para arquivos. Usar
`file.path()` + `file.exists()` + `tools::R_user_dir()` diretamente.

#### 5.5.2 Para L4 (resultado de query em memória): `cachem::cache_mem()`

Cache em memória da sessão para evitar reparse quando o usuário
chama `fetch_itr()` repetidamente com mesmos argumentos.

### 5.6 Fallback hierárquico

Ordem de resolução com `source = "auto"`:

```
1. L4 (memory cache) → se hit, retornar.
2. L1 (raw ZIP no disk) → se não-stale, transformar para L3 e retornar.
3. CVM HTTP → download para L1, transformar, retornar.
4. Mirror GitHub Releases → query DuckDB direto, retornar.
5. Erro: nenhuma fonte disponível.
```

### 5.7 Escala para múltiplas classes

Em v0.4+, fundos diários gerariam volume muito maior que companhias
anuais. ICVM 555 informe diário tem ~20.000 fundos × 250 dias úteis
× ~10 colunas ≈ 50 milhões de linhas por ano.

Mitigações previstas:

- **Particionamento mais fino**: fundos por mês, não por ano
  (`parquet/.../month=2024-01/...`).
- **Limite de cache local**: usuário pode ter que aumentar
  `cvmdata.cache_max_size_mb` para 500 MB ou mais para fundos.
- **Lazy evaluation via DuckDB**: para fundos, padrão pode mudar
  para "não baixar ZIP completo; consultar mirror via SQL". Decidir
  na fase de implementação v0.4.

Não pré-otimizar para v0.1.

---

## 6. Pipeline ETL do Mirror (GitHub Actions)

### 6.1 Visão geral

O mirror é mantido como GitHub Release no próprio repositório
`cvmdata`. Workflow GitHub Actions roda semanalmente, verifica se há
mudança em qualquer ZIP CVM, e republica Parquet via release nova.

Pontos-chave:

- **Trigger**: cron `0 7 * * 2` (terças, 07:00 UTC = 04:00 BRT).
- **Event-driven via hash**: só republica se ETag/sha256 mudou.
- **Validação pré-publish**: pointblank gates bloqueiam release com
  schema inválido ou dados óbvios corrompidos.
- **Rollback automático**: falha em validação → não publica, abre
  issue.
- **Versionamento**: tag `snapshot-YYYY-MM-DD` por release.

### 6.2 Workflow YAML completo

```yaml
# .github/workflows/etl-mirror.yaml
name: etl-mirror

on:
  schedule:
    - cron: '0 7 * * 2'  # Tuesdays at 07:00 UTC
  workflow_dispatch:
    inputs:
      force_rebuild:
        description: 'Force full rebuild even if hashes unchanged'
        required: false
        default: 'false'
        type: choice
        options:
          - 'true'
          - 'false'
      datasets:
        description: 'Comma-separated dataset ids (empty = all)'
        required: false
        default: ''
        type: string

permissions:
  contents: write   # to create release
  issues:   write   # to file failure issues
  actions:  read

env:
  R_KEEP_PKG_SOURCE: yes
  CVMDATA_ETL_MODE:  github_actions

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      changed_datasets: ${{ steps.detect.outputs.changed_datasets }}
      snapshot_date:    ${{ steps.detect.outputs.snapshot_date }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup R
        uses: r-lib/actions/setup-r@v2
        with:
          r-version: 'release'
          use-public-rspm: true

      - name: Setup R dependencies
        uses: r-lib/actions/setup-r-dependencies@v2
        with:
          packages: |
            any::httr2
            any::jsonlite
            any::digest
            any::cli

      - name: Detect changes via HEAD
        id: detect
        run: Rscript inst/etl/01_detect_changes.R
        env:
          FORCE_REBUILD: ${{ github.event.inputs.force_rebuild }}
          DATASETS:      ${{ github.event.inputs.datasets }}

  build-parquet:
    needs: detect-changes
    if: needs.detect-changes.outputs.changed_datasets != '[]'
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        dataset: ${{ fromJson(needs.detect-changes.outputs.changed_datasets) }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup R
        uses: r-lib/actions/setup-r@v2
        with:
          r-version: 'release'
          use-public-rspm: true

      - name: Setup R dependencies
        uses: r-lib/actions/setup-r-dependencies@v2
        with:
          extra-packages: |
            any::arrow
            any::readr
            any::dplyr
            any::tibble
            any::vctrs
            any::rlang
            any::stringr
            any::cli
            any::yaml
            any::digest
            local::.

      - name: Download ZIP from CVM
        run: Rscript inst/etl/02_download_zip.R "${{ matrix.dataset }}"

      - name: Transform to Parquet
        run: Rscript inst/etl/03_transform_to_parquet.R "${{ matrix.dataset }}"

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: parquet-${{ matrix.dataset }}
          path: build/parquet/${{ matrix.dataset }}/
          retention-days: 7

  validate-parquet:
    needs: [detect-changes, build-parquet]
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup R
        uses: r-lib/actions/setup-r@v2
        with:
          r-version: 'release'
          use-public-rspm: true

      - name: Setup R dependencies
        uses: r-lib/actions/setup-r-dependencies@v2
        with:
          extra-packages: |
            any::arrow
            any::duckdb
            any::pointblank
            any::dplyr
            any::tibble
            any::rlang
            any::cli
            any::yaml
            local::.

      - name: Download artifacts
        uses: actions/download-artifact@v4
        with:
          pattern: parquet-*
          path: build/parquet/
          merge-multiple: false

      - name: Run pointblank validation gates
        id: validate
        run: Rscript inst/etl/04_validate.R
        continue-on-error: false

      - name: Upload validation report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: validation-report
          path: build/validation/
          retention-days: 90

  publish-release:
    needs: [detect-changes, build-parquet, validate-parquet]
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Download artifacts
        uses: actions/download-artifact@v4
        with:
          pattern: parquet-*
          path: build/parquet/
          merge-multiple: false

      - name: Setup R
        uses: r-lib/actions/setup-r@v2
        with:
          r-version: 'release'

      - name: Setup R dependencies
        uses: r-lib/actions/setup-r-dependencies@v2
        with:
          extra-packages: |
            any::arrow
            any::duckdb
            any::jsonlite
            any::cli
            local::.

      - name: Build manifest.duckdb
        run: Rscript inst/etl/05_build_manifest.R "${{ needs.detect-changes.outputs.snapshot_date }}"

      - name: Bundle release assets
        run: Rscript inst/etl/06_bundle_release.R "${{ needs.detect-changes.outputs.snapshot_date }}"

      - name: Generate release notes
        id: notes
        run: Rscript inst/etl/07_release_notes.R "${{ needs.detect-changes.outputs.snapshot_date }}" > release_notes.md

      - name: Publish GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: snapshot-${{ needs.detect-changes.outputs.snapshot_date }}
          name: "Mirror snapshot ${{ needs.detect-changes.outputs.snapshot_date }}"
          body_path: release_notes.md
          files: |
            build/release/*.parquet
            build/release/manifest.duckdb
            build/release/checksums.txt
            build/release/snapshot_info.json
          prerelease: false
          draft: false

  notify-failure:
    needs: [detect-changes, build-parquet, validate-parquet, publish-release]
    if: failure()
    runs-on: ubuntu-latest
    steps:
      - name: Open issue on failure
        uses: dacbd/create-issue-action@v2
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          title: "ETL mirror failed on ${{ github.event.schedule || github.event.workflow_dispatch }}"
          body: |
            The mirror ETL workflow failed. See https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }} for details.
            Snapshot date attempted: ${{ needs.detect-changes.outputs.snapshot_date }}
            Datasets attempted: ${{ needs.detect-changes.outputs.changed_datasets }}
          labels: bug,etl-failure
```

### 6.3 Scripts ETL (`inst/etl/`)

Cada step do workflow chama um script R em `inst/etl/`. Resumo do
que cada um faz:

- `01_detect_changes.R` — itera sobre o catálogo de datasets (lido de
  `inst/extdata/dataset_index.rds`), faz HEAD HTTP em cada URL,
  compara ETag/Last-Modified com snapshot anterior, emite
  `changed_datasets` em JSON array.
- `02_download_zip.R` — baixa ZIP do dataset_id para
  `build/raw/<dataset_id>/`. Confere sha256.
- `03_transform_to_parquet.R` — aplica transformação tidy (mesmo
  código usado pelo pacote em runtime). Escreve Parquet particionado.
- `04_validate.R` — roda pointblank. Falha crítica → exit 1.
- `05_build_manifest.R` — constrói `manifest.duckdb` com índice de
  partições.
- `06_bundle_release.R` — empacota assets, gera `checksums.txt` e
  `snapshot_info.json`.
- `07_release_notes.R` — gera markdown sumarizando o que mudou.

### 6.4 Estrutura do release

Cada release `snapshot-YYYY-MM-DD` no GitHub contém:

```
snapshot-2026-05-19/
├── snapshot_info.json
├── checksums.txt
├── manifest.duckdb
├── itr/
│   ├── header_2024.parquet
│   ├── bpa_con_2024.parquet
│   ├── ...
├── dfp/...
├── fre/...
└── cad/
    └── cad_2026-05-19.parquet
```

### 6.5 Compatibilidade pacote ↔ release

O pacote precisa saber **qual release consumir**. Estratégia
recomendada: **híbrido**. Em runtime, o pacote:

1. Pega o latest release.
2. Lê `snapshot_info.json` para confirmar `schema_version`.
3. Se `schema_version` ≥ minimum requerido pelo pacote, usa.
4. Se não, lista releases mais recentes até achar um compatível.

Em `inst/extdata/`, manter `mirror_compat.json`:

```json
{
  "min_snapshot_schema_version": 1,
  "max_snapshot_schema_version": 1,
  "tested_against_snapshot": "snapshot-2026-05-19"
}
```

### 6.6 Custo estimado

- **GitHub Actions free tier**: ilimitado para Actions em repo
  público.
- **GitHub Releases**: ilimitado em número e armazenamento para repos
  públicos.

Tempo estimado por run completo na v0.1: ~15-20 min wall-clock.

### 6.7 Secrets necessários

- `GITHUB_TOKEN`: automático.
- Nenhum secret externo necessário para a v0.1.

---

## 7. Validation Gates com pointblank

### 7.1 Onde inserir validação

Três pontos de validação, com semânticas diferentes:

| Ponto                       | Tipo            | Falha → |
|-----------------------------|-----------------|---------|
| (a) ETL pré-publish          | Bloqueante      | Não publica release, abre issue |
| (b) Pacote em runtime        | Não-bloqueante  | Warning para o usuário, retorna dados |
| (c) Testes unitários         | Bloqueante      | Falha CI |

### 7.2 Gates do ETL (pré-publish)

#### 7.2.1 Asserções por schema

Para cada Parquet recém-gerado, validar:

```r
# inst/etl/04_validate.R
library(pointblank)
library(arrow)
library(yaml)

run_etl_validation <- function(parquet_path, schema_yaml_path) {
  schema  <- yaml::read_yaml(schema_yaml_path)
  df      <- arrow::read_parquet(parquet_path)
  expected_cols <- vapply(schema$columns, `[[`, "", "tidy")

  agent <- create_agent(
    tbl   = df,
    label = basename(parquet_path),
    actions = action_levels(
      warn_at  = 0.05,    # 5% rows failing → warn
      stop_at  = 0.20,    # 20% rows failing → stop ETL
      notify_at = 0.10
    )
  ) |>
    col_exists(columns = expected_cols) |>
    rows_distinct(columns = c("cnpj", "reference_date", "version")) |>
    col_vals_not_null(columns = c("cnpj", "reference_date")) |>
    col_is_character(columns = "cnpj") |>
    col_is_date(columns = "reference_date") |>
    col_vals_regex(
      columns = "cnpj",
      regex   = "^\\d{2}\\.\\d{3}\\.\\d{3}/\\d{4}-\\d{2}$"
    ) |>
    interrogate()

  if (any_failures(agent, "stop")) {
    stop(
      "Validation failed for ", basename(parquet_path),
      " — ETL aborted."
    )
  }

  agent
}
```

#### 7.2.2 Asserções customizadas por tabela

Tabelas específicas têm checks específicos:

- **`composicao_capital`**: soma de ordinárias + preferenciais deve
  igualar o total.
- **`bpa_con`**: account_code "1" (Ativo Total) deve existir; valor
  positivo.
- **Tabelas FRE de gênero/raça**: soma das categorias não-negativa.

#### 7.2.3 Foreign keys cross-table

`cad` é referencial. Todo `cnpj` em ITR/DFP/FRE deve existir em
`cad`. Para v0.1, validar soft-fail (warn, não stop).

### 7.3 Gates em runtime do pacote

#### 7.3.1 Opt-in via opção

Por padrão, **não validar em runtime**. Razões: custo (~1-3s por
chamada), confusão potencial para iniciantes. Ativável via
`options(cvmdata.validate_runtime = TRUE)`.

#### 7.3.2 Checks runtime essenciais

Schema drift detection: comparar colunas presentes com colunas
esperadas no YAML; warn se divergência.

### 7.4 Logging

ETL: validation report HTML em `build/validation/`, bundled como
GitHub Actions artifact.

Runtime: warnings R nativos com classe
`cvmdata_warning_schema_drift`.

---

## 8. Estratégia de Testes

### 8.1 Princípios gerais

1. **Determinismo CRAN-friendly.** Testes em `tests/testthat/` rodam
   sem rede. Testes que tocam internet → `test-integration-*.R`
   com `skip_on_cran()` + `skip_if_offline()`.
2. **Fixtures pequenos e reais.** Amostras de 50-200 linhas de CSVs
   CVM em `tests/testthat/fixtures/`, congeladas em data conhecida.
   Cada fixture vem com `*.meta.json` registrando origem.
3. **Cobertura alvo 90%.** Métrica via `covr::package_coverage()`,
   publicada no Codecov.

### 8.2 Framework e organização

`testthat` 3.x com edition 3:

```
Config/testthat/edition: 3
Config/testthat/parallel: true
```

Organização espelha `R/`: um arquivo de teste por arquivo R relevante.

### 8.3 Fixtures: política de gestão

Versionados no Git. Atualização manual via script auxiliar em
`inst/scripts/refresh-fixtures.R`. Tamanho total cap em 5 MB.

Critérios de seleção:

- **CAD**: amostragem estratificada por `SIT`.
- **ITR/DFP**: 5-10 empresas cobrindo setores, tamanhos, versões.
- **FRE**: cobertura de todas as 36 tabelas com pelo menos 5 linhas
  cada.

### 8.4 Mocks de HTTP

`httptest2` registra respostas mockadas em `tests/testthat/_mocks/`,
geradas via `httptest2::start_capturing()`, regravadas quando CVM
muda servidor.

### 8.5 Snapshot tests

`testthat::expect_snapshot()` usado para:

- Mensagens de erro (cada classe de erro tem snapshot).
- Estrutura de output (`dplyr::glimpse()` snapshotado).
- Atributos (`cvmdata_metadata` serializado).

### 8.6 Testes de regressão de schema

Cada vez que CVM muda schema:

1. Adicionar fixture novo pós-mudança.
2. Atualizar YAML de schema.
3. Escrever teste em `test-schemas-regression.R` carregando
   fixture antigo e novo, verificando que ambos chegam ao schema tidy
   unificado.

Documenta evolução temporal do dado fonte no repositório.

### 8.7 Testes de integração (skip_on_cran)

Em `test-integration-cvm.R`:

```r
test_that("real CVM endpoint returns ITR 2024 CSV", {
  skip_on_cran()
  skip_if_offline("dados.cvm.gov.br")
  skip_if(Sys.getenv("CVMDATA_RUN_INTEGRATION") != "true")
  # ...
})
```

Guarda `CVMDATA_RUN_INTEGRATION` evita run em CI default; só em
workflow `integration.yaml` weekly.

### 8.8 Política de paralelismo

`Config/testthat/parallel: true` no DESCRIPTION (usa
`parallel::detectCores() - 1`). Em fixtures pesados, paralelizar via
`future.apply` ou `purrr::map()` paralelizado.

### 8.9 O que não testamos

- **Cache real em `tools::R_user_dir()` do CI**: usar
  `withr::with_tempdir()`.
- **Compatibilidade com tidyverse 1.x**: declaramos versão mínima.
- **Performance**: microbenchmarks em `inst/benchmarks/`, manuais.

---

## 9. CI/CD

### 9.1 Visão geral dos workflows GitHub Actions

| Workflow | Trigger | Objetivo |
|---|---|---|
| `R-CMD-check.yaml` | push, PR | Matriz devel/release/oldrel × Ubuntu/macOS/Windows |
| `test-coverage.yaml` | push em `main`, PR | Cobertura via `covr::codecov()` |
| `lint.yaml` | push, PR | `lintr` + `styler` em modo check |
| `pkgdown.yaml` | push em `main`, tags | Build e deploy do site `pkgdown` |
| `etl-mirror.yaml` | cron, manual | Pipeline ETL (já documentado na §6) |
| `integration.yaml` | cron weekly, manual | Testes contra CVM e mirror reais |

### 9.2 R-CMD-check (workflow principal)

Matriz:
- `ubuntu-latest` × R devel/release/oldrel-1
- `macos-latest` × R release
- `windows-latest` × R release

Configuração:
- `error-on: "warning"` — qualquer WARNING falha o build.
- `_R_CHECK_FORCE_SUGGESTS_: false`.

### 9.3 Cobertura via Codecov

```yaml
coverage:
  status:
    project:
      default:
        target: 90%
        threshold: 1%
    patch:
      default:
        target: 80%

ignore:
  - "R/utils/cli_helpers.R"
  - "tests/"
  - "vignettes/"
  - "inst/etl/"
  - "inst/scripts/"
```

### 9.4 Lint e style

`.lintr` na raiz:

```r
linters: linters_with_defaults(
  line_length_linter(80L),
  object_name_linter(styles = c("snake_case")),
  cyclocomp_linter(complexity_limit = 20L),
  object_usage_linter = NULL,
  commented_code_linter = NULL
)
exclusions: list(
  "inst/etl/",
  "tests/testthat/fixtures/",
  "data-raw/"
)
encoding: "UTF-8"
```

### 9.5 pkgdown

Workflow constrói site em `gh-pages`. Configuração detalhada em §10.4.

### 9.6 Integration (rede real)

Workflow separado weekly + manual. Guarda
`CVMDATA_RUN_INTEGRATION=true` para evitar run acidental.

### 9.7 Branching e fluxo de release

**Modelo**: trunk-based com PR review.

- `main` sempre verde.
- Features em branches curtos (`feat/<short>`) com PR.
- Hotfixes em `hotfix/<issue-number>`.
- Não usamos Gitflow.

**Versionamento**: SemVer com convenção R. Desenvolvimento:
`0.0.0.9001+`. Releases: tagueados (`v0.1.0`).

**Release checklist** (em `.github/RELEASE_CHECKLIST.md`):

1. `devtools::check(remote = TRUE, manual = TRUE)` local limpo.
2. R-CMD-check verde nos 5 jobs.
3. `revdepcheck::revdep_check()` (vazio em v0.1).
4. Atualizar `NEWS.md`.
5. `usethis::use_version("minor")`.
6. `pkgdown::build_site()` local + revisão.
7. Tag e push.
8. `devtools::submit_cran()`.

### 9.8 Segredos e variáveis

- `CODECOV_TOKEN`
- `MAINTAINER_EMAIL`
- `SENDGRID_KEY` (alternativa: GitHub Issues automáticas)

Nenhum segredo para acessar CVM ou mirror — ambos públicos.

---

## 10. Documentação

### 10.1 Princípios

1. **Inglês canônico, português complementar.** CRAN-bound docs em
   inglês. Vignettes em PT existem como complemento no site pkgdown
   (em `vignettes/articles/`), não embarcadas no tarball.
2. **Documentação como interface pública.** Todo símbolo exportado
   tem `?` completo. Quebras → entrada em `NEWS.md`.
3. **Exemplos executáveis quando possível.** Demo data
   (`cvmdata_demo`) permite exemplos rápidos sem rede.

### 10.2 README e NEWS

`README.md` gerado de `README.Rmd` via `devtools::build_readme()`.
Estrutura:

1. Badges (R-CMD-check, codecov, CRAN status, lifecycle, pkgdown).
2. Parágrafo introdutório (EN).
3. Instalação.
4. Quick start.
5. "What's covered" — datasets × status.
6. Data provenance (CVM + mirror).
7. Link para vignettes e site pkgdown.
8. Citação.
9. CoC, contributing, license.

`NEWS.md` segue `### Breaking changes` / `### New features` /
`### Bug fixes` / `### Documentation` / `### Internal`.

### 10.3 Roxygen2

Toda função exportada tem:

- `@title`
- `@description`
- `@param` para cada argumento
- `@return` descreve tibble e atributos
- `@examples` — executáveis ou `\dontrun{}`
- `@export`
- `@family` quando apropriado
- `@seealso`

### 10.4 pkgdown site

Configuração em `_pkgdown.yml`:

- Template Bootstrap 5 com light-switch.
- Navbar: intro, reference, articles, news.
- Reference agrupada por `has_concept("fetchers")`, schema helpers,
  utilities, demo data.
- Articles em duas categorias: "User guides" (EN) e "Guias em
  português" (PT).

### 10.5 Vignettes em inglês (canônicas, embarcadas)

1. **`cvmdata.Rmd`** — introdução (~3-5 min).
2. **`itr-dfp.Rmd`** — schema das 19 tabelas (~10 min).
3. **`fre.Rmd`** — 36 tabelas categorizadas (~12 min).
4. **`cache-and-mirror.Rmd`** — fontes (~7 min).
5. **`roadmap.Rmd`** — planejamento (~3 min).

Em `vignettes/articles/` (web-only):

6-8. Versões em PT das três primeiras vignettes.

### 10.6 Documentação interna (não exportada)

Função interna sem `@export` recebe roxygen quando é reutilizada ou
tem lógica não-trivial. Vai para `man/internal/` via
`@keywords internal`.

### 10.7 Demo data

`data/cvmdata_demo.rda` contém lista nomeada:

- `cvmdata_demo$itr_bpa_con_2023` — ~50 linhas.
- `cvmdata_demo$dfp_dre_con_2023` — ~50 linhas.
- `cvmdata_demo$fre_directors_gender_2024` — ~30 linhas.
- `cvmdata_demo$cad_subset` — ~20 linhas.

Total compactado ~80 KB. Permite exemplos executáveis sem rede.

### 10.8 Citação

`inst/CITATION` para `citation("cvmdata")`.

### 10.9 Code of conduct e contributing

Arquivos padrão `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1) e
`CONTRIBUTING.md`. Templates em `.github/ISSUE_TEMPLATE/` e
`.github/PULL_REQUEST_TEMPLATE.md`.

---

## 11. Roadmap

### 11.1 Filosofia

Roadmap organizado em **fases**, não em datas. Cada fase é
auto-contida. Datas são estimativas em horas-pessoa de trabalho
focado.

A v0.1 corresponde às fases A-F e representa ~50-60% do esforço
total do pacote completo — porque é onde a arquitetura multi-classe
é construída pela primeira vez.

### 11.2 Fases

#### Fase A — Esqueleto (pré-v0.1) — 8-12h

- Estrutura de diretórios proposta na §2.
- `DESCRIPTION`, `NAMESPACE`, `LICENSE`.
- Configuração de CI/CD.
- README e site pkgdown vazios mas válidos.

#### Fase B — Cache + source CVM (pré-v0.1) — 16-20h

- `R/cache/` completo: paths, ETag, TTL, eviction LRU.
- `R/source/cvm/` para ZIP/CSV puros, sem schema.
- Testes: cache paths, ETag flow, mock HTTP.

#### Fase C — Dispatch + schemas (pré-v0.1) — 24-32h

- `R/dispatch/` resolvendo (dataset, table, entity) → handler.
- `R/schemas/companies/` com YAMLs para CAD e ITR.
- Parser YAML em `R/schemas/load.R`.

#### Fase D — CAD + ITR ponta-a-ponta (pré-v0.1) — 20-28h

- `fetch_cad()` e `fetch_itr()` exportadas.
- Aliases tipados.
- Vignette `itr-dfp.Rmd` parcial.
- Cobertura ≥85%.

#### Fase E — DFP + FRE (pré-v0.1) — 40-60h

- Replicar schemas DFP.
- Schemas FRE para todas as 36 tabelas.
- `fetch_dfp()` e `fetch_fre()` exportadas.
- Vignettes completas.

#### Fase F — Pipeline ETL + mirror (pré-v0.1) — 24-32h

- Workflow `etl-mirror.yaml` funcional.
- Scripts `inst/etl/01-07` completos.
- Primeiro snapshot publicado.
- `source_mirror_fetch()` integrado.

#### Marco: release v0.1.0

Após validação de:

- R-CMD-check verde nos 5 jobs.
- Cobertura ≥90%.
- `revdepcheck` limpo.
- Documentação revisada.
- `devtools::check_win_devel()` e `check_mac_release()` limpos.
- Pelo menos 30 dias de ETL rodando estável.

Submissão a CRAN.

#### Fase G — v0.2.0: FCA, FC, IPE — 30-40h

#### Fase H — v0.3.0: Companhias estrangeiras e incentivadas — 20-30h

#### Fase I — v0.4.0: Primeira classe de fundos — 50-70h

Recomendação: ICVM 555 primeiro (cobertura mais ampla, demanda
acadêmica maior).

#### Fase J — v0.5.0: FII — 30-40h

#### Fase K — v0.6.0: FIDC e fundos estruturados — 40-50h

#### Fase L — v1.0.0: Estabilização — 40-60h

- Auditoria de API.
- Vignettes consolidadas.
- Benchmarks documentados.
- Paper de software.

### 11.3 Total estimado

| Marco | Esforço cumulativo |
|---|:-:|
| v0.1.0 (companhias abertas parte 1) | ~140-190h |
| v0.2.0 (FCA, FC, IPE)               | ~170-230h |
| v0.3.0 (estrangeiras, incentivadas) | ~190-260h |
| v0.4.0 (ICVM 555)                   | ~240-330h |
| v0.5.0 (FII)                        | ~270-370h |
| v0.6.0 (FIDC e estruturados)        | ~310-420h |
| v1.0.0 (estabilização)              | ~350-480h |

### 11.4 Critério de priorização

1. Estabilidade do schema CVM.
2. Demanda em pesquisa acadêmica e relatórios DataSenado.
3. Existência de pacote concorrente cobrindo bem o mesmo dataset.
4. Esforço proporcional ao retorno.

---

## 12. Riscos, Premissas e Pendências

### 12.1 Premissas operacionais

1. **A CVM mantém o portal `dados.cvm.gov.br` com estabilidade de
   estrutura.** Mudanças incrementais de schema são esperadas;
   reorganização disruptiva não é.
2. **GitHub Releases continua gratuito para repositórios públicos
   com artifacts de até 2 GB cada.** Snapshot atual cabe em ~500 MB
   Parquet comprimido. Margem de 4×.
3. **CRAN aceita pacotes que baixam dados sob demanda quando
   respeitam o policy de cache em `tools::R_user_dir()` e declaram a
   fonte.** Precedentes: `microdatasus`, `GetDFPData2`, `rfb`,
   `tidycensus`.
4. **O R-CMD-check em rede tem variabilidade aceitável.** Testes
   embarcados no CRAN não dependem de rede.
5. **Sidney é o mantenedor único na v0.1.** Bus-factor 1. Mitigação:
   documentação interna abundante, CI estrito, separação clara
   entre código do pacote e ETL.

### 12.2 Riscos identificados

| ID | Risco | Severidade | Probabilidade | Mitigação |
|:-:|---|:-:|:-:|---|
| R-01 | CVM reestrutura portal e quebra URLs | Alta | Média | URL builders em ~3 funções; mirror como fallback. |
| R-02 | Schema de uma tabela ITR/DFP/FRE muda silenciosamente | Alta | Alta | Validation gate no ETL bloqueia publicação; alerta. |
| R-03 | GitHub muda política de Releases | Média | Baixa | Pacote pode operar contra CVM direto; plano B: Cloudflare R2. |
| R-04 | CRAN rejeita pacote por tamanho ou política de rede | Média | Baixa | Pré-submissão revisada; demo data <100 KB; sem rede em exemplos. |
| R-05 | Volume de FRE explode | Média | Média | Schemas YAML extensíveis. |
| R-06 | Conflito com pacote concorrente | Baixa | Média | Posicionamento multi-classe; coexistência aceitável. |
| R-07 | pointblank perde manutenção | Baixa | Baixa | Camada isolada; troca por `validate` viável em ~1-2 dias. |
| R-08 | `tools::R_user_dir()` deprecation | Baixa | Muito baixa | API estável desde R 4.0. |
| R-09 | Encoding ISO-8859-1 muda para UTF-8 sem aviso | Média | Baixa | Detecção via `readr::guess_encoding()`. |
| R-10 | DuckDB Parquet incompatibilidade entre versões | Baixa | Baixa | Pinning de versão no ETL; teste em R-CMD-check. |

### 12.3 Pendências para Rodada 2.5 (naming)

**Removido neste extrato** (todas as pendências aqui listadas
foram resolvidas nas Rodadas 2.5, 2.6, 3.0 e 3.0.2 — consultar
o naming doc v03 e os fechamentos correspondentes).

### 12.4 Pendências para Rodada 3 (implementação)

1. **Checklist passo-a-passo de implementação** das fases A-F.
2. **Lista de issues GitHub iniciais** para abrir na criação do
   repositório.
3. **Definição final dos YAMLs de schema** para CAD e ITR.

### 12.5 Pendências menores

1. **Licença.** Proposta MIT. Alternativa: GPL-3. Recomendação: MIT.
2. **Nome do mantenedor em `DESCRIPTION`**: Sidney completo + ORCID.
3. **E-mail de contato CRAN**: estável; conta pessoal preferível.
4. **Logo do pacote (hexsticker)**: opcional, não-bloqueante.

### 12.6 O que este plano deliberadamente não decide

- **Estratégia de comunicação com a CVM** (reportar bugs, sugerir
  documentação). Fora do escopo arquitetural.
- **Estratégia de publicação acadêmica.** JOSS, Revista de Saúde
  Pública, ou similar fica para v1.0.
- **Cobertura de dados pré-2010.** Fora do v0.1.

---
