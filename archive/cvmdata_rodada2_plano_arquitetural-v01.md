# `cvmdata` — Plano Arquitetural (Rodada 2)

> Documento de planejamento técnico do pacote R `cvmdata`. Versão de
> referência para a fase de implementação. Todas as decisões da
> Rodada 1 são tratadas como travadas; este documento apenas as
> operacionaliza.
>
> **Idioma deste documento**: português brasileiro.
> **Idioma de todo código, schema, identificador, mensagem do pacote,
> e documentação CRAN**: inglês.

---

## 1. Sumário Executivo

`cvmdata` é um pacote R cujo objetivo de longo prazo é fornecer uma
API tidy para o universo completo de dados abertos publicados pela
CVM (Comissão de Valores Mobiliários) — companhias abertas, fundos de
investimento ICVM 555, fundos imobiliários (FII), fundos de direitos
creditórios (FIDC), fundos estruturados, companhias estrangeiras e
incentivadas, emissores. A v0.1 (release inicial CRAN) cobre apenas a
classe "companhias abertas, parte 1" — `cad`, `itr`, `dfp`, `fre` —
mas a arquitetura interna é multi-classe desde o primeiro commit, de
modo que a expansão para fundos (v0.4+) seja aditiva, não
disruptiva.

A espinha dorsal da API é a função genérica `fetch_cvm()`, com
aliases tipados (`fetch_itr()`, `fetch_dfp()`, `fetch_fre()`,
`fetch_cad()` na v0.1; `fetch_fii()`, `fetch_fidc()` previstos para
v0.4+). O dispatch interno reconhece a classe de entidade pelo
identificador do dataset e roteia para módulos especializados em
`R/companies/` e (futuramente) `R/funds/`. Todos os retornos são
tibbles com atributos de proveniência (`source`, `fetched_at`,
`n_entities`, `class`).

A fonte primária é o Portal de Dados Abertos da CVM
(`dados.cvm.gov.br`), consumido via HTTP direto e API CKAN para
metadados. A fonte secundária é um mirror próprio em GitHub Releases
do repositório `cvmdata`, armazenado em Parquet particionado e
consultado via DuckDB com HTTP range requests. O fallback CVM → mirror
é automático e transparente: cada tibble retornado declara, via
atributo `source`, de onde os dados vieram. O mirror é mantido por um
GitHub Actions workflow disparado por cron semanal (terças 07:00 UTC),
event-driven via comparação de hash dos ZIPs CVM, com gates de
validação pointblank antes da publicação do release.

O pacote depende de `tidyverse` core (dplyr, tibble, vctrs, rlang,
purrr, stringr), `readr` para parsing de CSV CVM com encoding
ISO-8859-1 e separador `;`, `arrow` para Parquet, `duckdb` para
consulta ao mirror, `pointblank` para validação, `httr2` para
requests, `cli` para mensagens e `tools::R_user_dir()` para cache
local persistente respeitando CRAN policy.

A normalização de schemas é tratada como decisão de design central.
O pacote converte dois padrões inconsistentes da própria CVM (FRE usa
PascalCase português, ITR/DFP/CAD usam SCREAMING_SNAKE abreviado) em
um único schema tidy em snake_case inglês, com colunas-chave
unificadas (`cnpj`, `cvm_code`, `reference_date`, `version`,
`company_name`). Valores monetários em escala "MIL" são multiplicados
por 1000 por padrão; `ORDEM_EXERC` "ÚLTIMO"/"PENÚLTIMO" vira coluna
booleana `is_current_period` mais coluna `comparison_period_end`.

Validação acontece em três pontos: no ETL do mirror (gates
bloqueantes antes do release), no pacote ao consumir dados (gates
não-bloqueantes que emitem warnings via `rlang::warn()`) e nos
testes (snapshot tests com fixtures pequenas). Testes seguem
`testthat` 3.x com `skip_on_cran()` para integração de rede. Cobertura
alvo: 90%.

CI/CD usa cinco workflows GitHub Actions: `R-CMD-check` em matriz (R
devel/release/oldrel × Ubuntu/macOS/Windows), `test-coverage`
(covr + Codecov), `lint` (lintr + styler check), `pkgdown` (site
automático) e `etl-mirror` (pipeline de produção do mirror). Política
de versionamento: SemVer. Branching: trunk-based com PRs apenas para
mudanças não-triviais.

A documentação tem três camadas: README e NEWS em inglês (CRAN
policy), vignettes em inglês como camada canônica (5 vignettes
planejadas para v0.1: introdução, ITR/DFP, FRE/ESG, cache-and-mirror,
roadmap) e vignettes complementares em português brasileiro como
material adicional para a comunidade brasileira. Todas as funções
exportadas têm exemplos roxygen2 executáveis envoltos em `\dontrun{}`
ou `if (interactive())` quando dependem de rede.

O roadmap macroscópico tem doze fases (A–L), desde scaffolding até
release v0.4 com primeira classe de fundos. A v0.1 está estimada em
~50-60% do esforço total, porque tudo o que vier depois é
incremental sobre o trilho já construído. Premissas-chave: CVM
mantém estabilidade de schema (mitigado por versionamento interno);
GitHub Releases segue gratuito para repositórios públicos pequenos
(mitigado por possível migração a R2/Zenodo se romper); CRAN aceita
pacotes que consultam dados externos em runtime (precedentes:
`microdatasus`, `GetDFPData2`, `tidycensus`).

Decisões pendentes pós-Rodada 2: naming detalhado de funções
(Rodada 2.5), checklist de implementação navegável (Rodada 3),
licença final (sugestão: MIT por paralelo com `educabR`).

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

Exemplo mínimo:

```r
#' Fetch ITR (Quarterly Information Form) data from CVM
#'
#' Downloads and tidies Quarterly Information Form (ITR) data
#' published by CVM for Brazilian listed companies. Handles fallback
#' to the package mirror automatically when the CVM source does not
#' cover the requested year.
#'
#' @param table Character. Internal ITR table name, e.g. `"bpa_con"`,
#'   `"bpp_con"`, `"dre_con"`. Use [list_tables()] to see all
#'   available tables. If `NULL`, returns the form header table.
#' @param companies Character or integer vector. Company identifiers.
#'   Accepts CVM codes (e.g. `c(9512, 4170)`), CNPJ strings
#'   (e.g. `"00.000.000/0001-91"`) or B3 tickers (e.g. `"PETR4"`).
#'   If `NULL`, returns all companies.
#' @param years Integer vector. Reference years. Defaults to the most
#'   recent available year. Use `years = NULL` to fetch all years
#'   available in the active source.
#' @param ... Reserved for future arguments.
#'
#' @return A tibble of class `cvm_tbl` with columns specific to the
#'   selected `table`. Always includes `cnpj`, `cvm_code`,
#'   `reference_date`, `version`, `company_name`. Carries attributes
#'   `source`, `fetched_at`, `n_entities`, `class_entity`, `dataset`,
#'   `tables`.
#'
#' @examples
#' \dontrun{
#' # Fetch consolidated balance sheet for Petrobras and Vale, 2024
#' fetch_itr(table = "bpa_con", companies = c("PETR4", "VALE3"),
#'           years = 2024)
#' }
#' @family fetchers
#' @seealso [fetch_dfp()] for annual filings; [fetch_cvm()] for the
#'   generic backbone.
#' @export
fetch_itr <- function(table = NULL, companies = NULL, years = NULL,
                      ...) {
  # implementation
}
```

---

## 3. Design da API Pública

Esta seção operacionaliza o **Padrão C híbrido** decidido na
Rodada 1, com extensão para múltiplas classes de entidades. Não
define nomes finais (subsessão dedicada, Rodada 2.5), mas trava a
**estrutura** da API: quantas funções, quais argumentos, dispatch
interno, contrato de retorno, tratamento de erros.

### 3.1 Espinha dorsal multi-classe: `fetch_cvm()`

#### 3.1.1 Assinatura

```r
fetch_cvm <- function(
  dataset,
  table     = NULL,
  entities  = NULL,
  period    = NULL,
  source    = c("auto", "cvm", "mirror", "cache"),
  on_error  = c("abort", "warn", "silent"),
  validate  = NULL,
  ...
) {
  # implementation
}
```

Tipos e contratos:

- `dataset`: caractere de comprimento 1. Aceita identificador CVM
  oficial (`"cia_aberta-doc-itr"`, `"cia_aberta-cad"`) ou alias curto
  registrado internamente (`"itr"`, `"cad"`, `"fre"`, `"dfp"`,
  `"fii-doc-mensal"`, etc.). A função `list_datasets()` enumera os
  válidos.
- `table`: caractere de comprimento 1 ou `NULL`. Aplicável apenas a
  datasets que têm múltiplas tabelas internas (ITR, DFP, FRE).
  Quando `NULL` para datasets multi-tabela, retorna a tabela de
  cabeçalho (`itr_cia_aberta_2024.csv` no caso do ITR). Para datasets
  mono-tabela (CAD), `table` é ignorado com warning se não-NULL.
- `entities`: vetor caractere ou inteiro. Identificadores das
  entidades de interesse. Aceitação por classe:
  - Companhias: CD_CVM (inteiro), CNPJ (caractere com ou sem
    pontuação), ticker B3 (caractere de 4-6 chars iniciando com
    letras maiúsculas).
  - Fundos (v0.4+): CNPJ do fundo, código CVM do fundo.
- `period`: vetor ou objeto Date/integer. Aceita:
  - `years` (integer vector) para datasets anuais (ITR, DFP, FRE).
  - `dates` (Date vector ou ISO string) para datasets diários (futuro:
    fundos ICVM 555).
  - Range via `c(start, end)` quando ambos lados são do mesmo tipo.
  - Single value para um período específico.
- `source`: enum. `"auto"` (default) tenta CVM primeiro, cai para
  mirror, depois cache, conforme disponibilidade. `"cvm"`, `"mirror"`,
  `"cache"` forçam fonte específica e falham se indisponível.
- `on_error`: enum de comportamento de falha. `"abort"` (default) usa
  `rlang::abort()`. `"warn"` registra warning e retorna tibble vazio
  com schema correto. `"silent"` retorna tibble vazio sem mensagem.
- `validate`: `NULL`, `TRUE` ou `FALSE`. Quando `NULL`, segue
  `getOption("cvmdata.validate_runtime", default = FALSE)`. Quando
  `TRUE`, executa pointblank gates após a transformação. Quando
  `FALSE`, pula validação.
- `...`: reservado para argumentos específicos de subclasses. Não
  documentar usos ainda.

#### 3.1.2 Comportamento de defaults

Decisão de design importante: **quando o usuário passa `NULL` em
`entities` ou `period`, o pacote retorna `tudo o que está disponível`,
não erro.**

Justificativa: comportamento espelha o que pacotes precedentes
(`microdatasus`, `tidycensus`, `arrow` ao listar Parquet) fazem.
Reduz fricção em sessão exploratória inicial. A função emite
`cli::cli_inform()` informando o volume estimado antes do download
quando passa de um threshold (ex: > 200 MB), oferecendo opt-out via
`getOption("cvmdata.warn_on_large_fetch", default = TRUE)`.

Alternativa rejeitada: exigir `entities` ou `period` não-NULL,
forçando o usuário a escolher escopo. Rejeitada porque atrapalha o
caso de uso analítico real (estudo populacional de companhias
abertas precisa de todas as empresas).

#### 3.1.3 Dispatch interno

O `fetch_cvm()` roteia em três etapas:

```r
fetch_cvm <- function(dataset, table = NULL, entities = NULL,
                      period = NULL, source = "auto",
                      on_error = "abort", validate = NULL, ...) {
  # 1. normalize dataset id (alias → canonical)
  dataset_id <- resolve_dataset_id(dataset)

  # 2. resolve class (companies / funds / fii / fidc / ...)
  entity_class <- resolve_dataset_class(dataset_id)

  # 3. dispatch to class-specific implementation
  switch(
    entity_class,
    "companies" = fetch_companies_internal(
      dataset_id, table, entities, period, source, on_error,
      validate, ...
    ),
    "funds_555" = fetch_funds_555_internal(
      dataset_id, table, entities, period, source, on_error,
      validate, ...
    ),
    "fii" = fetch_fii_internal(
      dataset_id, table, entities, period, source, on_error,
      validate, ...
    ),
    "fidc" = fetch_fidc_internal(
      dataset_id, table, entities, period, source, on_error,
      validate, ...
    ),
    rlang::abort(
      message = c(
        "Unknown entity class for dataset",
        "x" = "Dataset {.val {dataset_id}} resolved to class {.val {entity_class}}, which is not implemented."
      ),
      class = "cvmdata_error_unknown_class"
    )
  )
}
```

Importante: os ramos `funds_555`, `fii`, `fidc` existem no roteador
desde a v0.1, mas em v0.1 eles emitem `rlang::abort()` com classe
`cvmdata_error_not_yet_supported` mencionando a versão alvo:

```r
fetch_fii_internal <- function(...) {
  rlang::abort(
    message = c(
      "FII datasets are not yet supported.",
      "i" = "Planned for cvmdata v0.4. Track progress at https://github.com/sidneybissoli/cvmdata/issues/X."
    ),
    class = c("cvmdata_error_not_yet_supported",
              "cvmdata_error")
  )
}
```

Justificativa: força o esqueleto multi-classe a existir desde v0.1.
Quando v0.4 chegar, o `switch()` já está pronto; só falta substituir
a implementação stub pelo código real.

### 3.2 Aliases tipados v0.1: companhias abertas

#### 3.2.1 `fetch_cad()`

Cadastro de companhias abertas. Único dataset CAD da v0.1 não tem
componente temporal (é snapshot único).

```r
fetch_cad <- function(
  companies = NULL,
  source    = c("auto", "cvm", "mirror", "cache"),
  on_error  = c("abort", "warn", "silent"),
  validate  = NULL,
  ...
) {
  fetch_cvm(
    dataset  = "cad",
    table    = NULL,
    entities = companies,
    period   = NULL,
    source   = match.arg(source),
    on_error = match.arg(on_error),
    validate = validate,
    ...
  )
}
```

Argumento renomeado: `entities` → `companies` para clareza. Tipo
aceito: CD_CVM, CNPJ, ticker B3.

#### 3.2.2 `fetch_itr()`

```r
fetch_itr <- function(
  table     = NULL,
  companies = NULL,
  years     = NULL,
  source    = c("auto", "cvm", "mirror", "cache"),
  on_error  = c("abort", "warn", "silent"),
  validate  = NULL,
  ...
) {
  fetch_cvm(
    dataset  = "itr",
    table    = table,
    entities = companies,
    period   = years,
    source   = match.arg(source),
    on_error = match.arg(on_error),
    validate = validate,
    ...
  )
}
```

`table` aceita: `"header"`, `"bpa_con"`, `"bpa_ind"`, `"bpp_con"`,
`"bpp_ind"`, `"dre_con"`, `"dre_ind"`, `"dra_con"`, `"dra_ind"`,
`"dfc_md_con"`, `"dfc_md_ind"`, `"dfc_mi_con"`, `"dfc_mi_ind"`,
`"dmpl_con"`, `"dmpl_ind"`, `"dva_con"`, `"dva_ind"`,
`"composicao_capital"`, `"parecer"`. (19 valores total.)

Convenções dos nomes de tabela tidy:

- Substituir SCREAMING_SNAKE original por `snake_case`.
- Manter sufixo `_con`/`_ind` para distinguir consolidado de
  individual (paralelo direto à CVM).
- Manter abreviações financeiras conhecidas (`bpa`, `bpp`, `dre`,
  `dra`, `dfc_md`, `dfc_mi`, `dmpl`, `dva`) porque são jargão padrão
  de contabilidade brasileira; traduzir seria pior.

#### 3.2.3 `fetch_dfp()`

Paralelo direto ao ITR. Mesma assinatura, mesmo conjunto de tabelas:

```r
fetch_dfp <- function(
  table     = NULL,
  companies = NULL,
  years     = NULL,
  source    = c("auto", "cvm", "mirror", "cache"),
  on_error  = c("abort", "warn", "silent"),
  validate  = NULL,
  ...
) {
  fetch_cvm(
    dataset  = "dfp",
    table    = table,
    entities = companies,
    period   = years,
    source   = match.arg(source),
    on_error = match.arg(on_error),
    validate = validate,
    ...
  )
}
```

#### 3.2.4 `fetch_fre()`

```r
fetch_fre <- function(
  table     = NULL,
  companies = NULL,
  years     = NULL,
  source    = c("auto", "cvm", "mirror", "cache"),
  on_error  = c("abort", "warn", "silent"),
  validate  = NULL,
  ...
) {
  fetch_cvm(
    dataset  = "fre",
    table    = table,
    entities = companies,
    period   = years,
    source   = match.arg(source),
    on_error = match.arg(on_error),
    validate = validate,
    ...
  )
}
```

`table` aceita os 36 valores correspondentes às 36 tabelas internas
FRE. Lista completa: ver Seção 4.5.

Observação importante: o FRE 2024 tem `data_referencia` formato
"YYYY-12-31" anual, mas as empresas podem entregar versões
atualizadas durante o ano. O campo `version` indica revisão.

### 3.3 Aliases tipados v0.4+: fundos (ilustrativo)

Não implementados na v0.1. Documentados aqui para travar a forma da
API:

```r
fetch_fundos_555 <- function(
  table       = NULL,
  funds       = NULL,
  period      = NULL,         # Date vector ou range
  source      = c("auto", "cvm", "mirror", "cache"),
  on_error    = c("abort", "warn", "silent"),
  validate    = NULL,
  ...
) {
  fetch_cvm(
    dataset  = "fundos_555",
    table    = table,
    entities = funds,
    period   = period,
    ...
  )
}

fetch_fii <- function(
  table  = NULL,
  funds  = NULL,
  period = NULL,
  ...
) {
  fetch_cvm(dataset = "fii", table = table, entities = funds,
            period = period, ...)
}

fetch_fidc <- function(
  table  = NULL,
  funds  = NULL,
  period = NULL,
  ...
) {
  fetch_cvm(dataset = "fidc", table = table, entities = funds,
            period = period, ...)
}
```

Diferença de design entre companhias e fundos:

- Companhias usam `years` (granularidade anual coerente com ITR/DFP).
- Fundos usam `period` aceitando Date vector, range, ou intervalo.
  Informe diário ICVM 555 é granular ao dia.

A função genérica `fetch_cvm()` aceita `period` em qualquer formato e
delega a normalização para a função interna especializada da classe.

### 3.4 Validação de inputs

#### 3.4.1 Resolução de identificadores de entidade

`entities` aceita múltiplos formatos. O pacote precisa detectar e
normalizar.

```r
normalize_company_id <- function(x) {
  if (is.null(x)) return(NULL)
  if (is.numeric(x)) {
    # treat as CVM code
    return(list(type = "cvm_code", values = as.integer(x)))
  }
  x <- as.character(x)
  # detect CNPJ: 14 digits (with or without punctuation)
  is_cnpj <- stringr::str_detect(
    x, "^\\d{2}\\.?\\d{3}\\.?\\d{3}/?\\d{4}-?\\d{2}$"
  )
  # detect ticker: 4 letters + 1-2 digits
  is_ticker <- stringr::str_detect(
    x, "^[A-Z]{4}\\d{1,2}$"
  )
  # detect CVM code as character
  is_code <- stringr::str_detect(x, "^\\d{1,7}$")

  classes <- dplyr::case_when(
    is_cnpj   ~ "cnpj",
    is_ticker ~ "ticker",
    is_code   ~ "cvm_code",
    TRUE      ~ "unknown"
  )

  if (any(classes == "unknown")) {
    bad <- x[classes == "unknown"]
    rlang::abort(
      message = c(
        "Unrecognized company identifier(s).",
        "x" = "Found: {.val {bad}}",
        "i" = "Accepted forms: CVM code (e.g. {.val 9512}), CNPJ (e.g. {.val \"33.000.167/0001-01\"}), or B3 ticker (e.g. {.val \"PETR4\"})."
      ),
      class = "cvmdata_error_invalid_identifier"
    )
  }

  # mixed types allowed; resolve each to CD_CVM internally
  list(
    raw     = x,
    types   = classes,
    resolved = resolve_to_cvm_code(x, classes)
  )
}
```

Resolução `ticker → CD_CVM` exige tabela de lookup interna. Estratégia:

- v0.1: incluir lookup table em `inst/extdata/ticker_to_cvm.rds`,
  construído a partir do dataset CAD da CVM (CAD não tem ticker
  diretamente, mas pode ser cruzado com lookup externo — pendência:
  ver Seção 3.4.2).
- Alternativa: scraping de `sistemaswebb3-listados.b3.com.br` foi
  excluído por decisão da Rodada 1 (fora de escopo permanente).
- Solução adotada: lookup table pré-construído via data-raw script
  como **dado interno**, com nota explícita no docs avisando que
  pode estar desatualizado entre releases. Aceitação de ticker é
  best-effort, não garantida.

#### 3.4.2 Decisão pendente: source de lookup ticker→CD_CVM

Opções:

- **(a)** Embedded snapshot em `inst/extdata/ticker_to_cvm.rds`,
  atualizado a cada release. Pro: zero dependência runtime. Contra:
  desatualiza entre releases.
- **(b)** Buscar do mirror GitHub Releases em runtime. Pro: sempre
  atualizado. Contra: depende de rede para qualquer chamada que use
  ticker.
- **(c)** Não suportar ticker. Aceitar só CNPJ e CD_CVM. Pro:
  simplifica. Contra: piora UX significativamente — analistas pensam
  em PETR4, não em CD_CVM 9512.

Recomendação: **(a)** para v0.1, com plano de migrar para **(b)** em
v0.2 se demanda justificar. O lookup table é pequeno (~500 entradas)
e cabe trivialmente em `inst/extdata/`. Documentar a limitação na
docs de `fetch_*()`:

> Note: ticker resolution uses an internal lookup table snapshot
> updated at each `cvmdata` release. For most recent listings, pass
> CD_CVM or CNPJ directly.

#### 3.4.3 Validação de `period`

```r
normalize_period <- function(period, granularity) {
  if (is.null(period)) return(NULL)

  switch(
    granularity,
    "yearly" = normalize_period_yearly(period),
    "daily"  = normalize_period_daily(period),
    rlang::abort("Unknown granularity: {granularity}",
                 class = "cvmdata_error_internal")
  )
}

normalize_period_yearly <- function(period) {
  # accept: integer vector, character "2024", or range c(2020, 2024)
  years <- as.integer(period)
  if (any(is.na(years))) {
    rlang::abort(
      c("Invalid year specification.",
        "x" = "Could not parse: {.val {period[is.na(years)]}}"),
      class = "cvmdata_error_invalid_period"
    )
  }
  current <- as.integer(format(Sys.Date(), "%Y"))
  if (any(years < 2010 | years > current + 1)) {
    out_of_range <- years[years < 2010 | years > current + 1]
    rlang::warn(
      c("Some years are outside the expected range.",
        "i" = "Out of range: {.val {out_of_range}}",
        "i" = "ITR data starts at 2011, DFP at 2010. FRE at 2010 (with format change in 2010)."),
      class = "cvmdata_warning_year_out_of_range"
    )
  }
  sort(unique(years))
}
```

### 3.5 Contrato de retorno

#### 3.5.1 Forma

**Tibble com subclasse `cvm_tbl`.** Sempre.

- Quando o dataset é mono-tabela (CAD): um tibble.
- Quando o dataset é multi-tabela e `table` é especificado: um
  tibble.
- Quando o dataset é multi-tabela e `table` é `NULL`: o tibble do
  cabeçalho (header form) — ou seja, a lista de submissões, não
  todas as tabelas concatenadas.

Decisão crítica: **nunca retornar uma `list` de tibbles.** Quem
quiser múltiplas tabelas faz múltiplas chamadas e junta no próprio
código. Justificativa: o tipo de retorno consistente facilita
composição em pipes; uma `list` quebra o pipe e introduz
complexidade desnecessária para o caso comum (analista quer uma
tabela por vez).

Alternativa rejeitada: argumento `table = "*"` para retornar lista
de todas as tabelas. Rejeitada porque mistura dois tipos de retorno e
porque o volume seria proibitivo (ITR ano completo: ~900MB, FRE ano
completo: ~58MB).

#### 3.5.2 Atributos

Todo `cvm_tbl` carrega:

```r
attr(x, "source")        # "cvm", "mirror", "cache"
attr(x, "fetched_at")    # POSIXct, UTC
attr(x, "dataset")       # canonical dataset id, e.g. "itr"
attr(x, "tables")        # character vector of tables fetched
attr(x, "n_entities")    # integer, distinct entities in result
attr(x, "class_entity")  # "companies", "funds_555", "fii", ...
attr(x, "period_filter") # original period argument (for reproducibility)
attr(x, "entities_filter") # original entities argument
attr(x, "cvmdata_version") # packageVersion("cvmdata")
```

Justificativa: preserva reproducibility. Análise pode ser auditada
para descobrir de onde os dados vieram e quando foram baixados, sem
precisar refazer a query.

#### 3.5.3 Colunas-chave unificadas

Independentemente do dataset, as primeiras colunas do tibble são as
chaves de junção comuns, com nomes padronizados em snake_case
inglês:

| Coluna           | Tipo  | Origem CVM                                       |
|------------------|-------|--------------------------------------------------|
| `cnpj`           | chr   | CNPJ_CIA (ITR/DFP/CAD) ou CNPJ_Companhia (FRE)   |
| `cvm_code`       | int   | CD_CVM                                           |
| `company_name`   | chr   | DENOM_CIA ou Nome_Companhia                      |
| `reference_date` | Date  | DT_REFER ou Data_Referencia                      |
| `version`        | int   | VERSAO                                           |

A função interna `normalize_keys()` é aplicada a todo tibble antes de
retornar, garantindo presença e tipo dessas cinco colunas. Colunas
específicas da tabela vêm depois.

### 3.6 Funções auxiliares

#### 3.6.1 Discovery

```r
list_datasets <- function(class = NULL) {
  # class: NULL, "companies", "funds_555", "fii", "fidc", "all"
  # returns a tibble: dataset_id, class, title, n_tables, source_url
}

list_tables <- function(dataset) {
  # dataset: dataset id from list_datasets()
  # returns a tibble: table_id, n_rows_estimate, description
}

list_companies <- function(
  active_only = TRUE,
  source = c("auto", "cvm", "mirror", "cache")
) {
  # convenience wrapper for fetch_cad() returning company directory
  # active_only: filter SIT == "ATIVO"
  # returns a tibble: cnpj, cvm_code, company_name, sector, status
}

cvm_metadata <- function(dataset) {
  # full CKAN metadata for a dataset
  # returns a list (parsed JSON from CKAN package_show endpoint)
}
```

#### 3.6.2 Cache e source

```r
cvm_cache_path <- function() {
  # returns the directory path used by cvmdata for cache
  tools::R_user_dir("cvmdata", which = "cache")
}

cvm_cache_clear <- function(
  what = c("all", "raw", "parquet", "queries"),
  older_than = NULL  # difftime ou character "30 days"
) {
  # removes files; returns invisible tibble of removed paths
}

cvm_cache_info <- function() {
  # returns tibble: path, size_bytes, mtime, type, dataset
}

cvm_source_info <- function() {
  # current resolution: which source is being used, fallback chain status
  # returns list with: active_source, cvm_reachable, mirror_reachable,
  # cache_size_mb, last_etl_run
}

cvm_set_source <- function(
  source = c("auto", "cvm", "mirror", "cache")
) {
  # session-scoped override of the source resolution order
  # equivalent to options(cvmdata.source = source)
}
```

### 3.7 Tratamento de erros

#### 3.7.1 Hierarquia de classes de condição

Todas as condições emitidas pelo pacote (erros, warnings,
informações) carregam classes hierárquicas, permitindo handlers
específicos:

```
cvmdata_condition
├── cvmdata_error
│   ├── cvmdata_error_invalid_identifier
│   ├── cvmdata_error_invalid_period
│   ├── cvmdata_error_unknown_dataset
│   ├── cvmdata_error_unknown_class
│   ├── cvmdata_error_unknown_table
│   ├── cvmdata_error_not_yet_supported
│   ├── cvmdata_error_network
│   ├── cvmdata_error_source_unavailable
│   ├── cvmdata_error_validation_failed
│   └── cvmdata_error_internal
├── cvmdata_warning
│   ├── cvmdata_warning_year_out_of_range
│   ├── cvmdata_warning_source_fallback
│   ├── cvmdata_warning_validation_soft_fail
│   ├── cvmdata_warning_large_fetch
│   └── cvmdata_warning_schema_drift
└── cvmdata_message
    ├── cvmdata_message_source_resolution
    ├── cvmdata_message_cache_hit
    └── cvmdata_message_download_progress
```

#### 3.7.2 Idioma das mensagens

Política rígida: **todas as mensagens em inglês**. O pacote vai para
CRAN; mensagens em português quebrariam usuários internacionais.

A localização para português brasileiro pode ser feita em release
posterior via `.po` files (`tools::update_pkg_po()`) — registrado
como pendência futura, não bloqueia v0.1.

#### 3.7.3 Padrão de uso de `rlang::abort()` e `cli::cli_inform()`

```r
# Error
rlang::abort(
  message = c(
    "Failed to fetch dataset.",                       # title
    "x" = "Dataset {.val {dataset}} not found.",      # the bad
    "i" = "Use {.fn list_datasets} to see available." # hint
  ),
  class = c("cvmdata_error_unknown_dataset",
            "cvmdata_error")
)

# Warning
rlang::warn(
  message = c(
    "Falling back to mirror.",
    "!" = "CVM source unreachable for years {.val {failed_years}}.",
    "i" = "Mirror snapshot from {.val {snapshot_date}}."
  ),
  class = c("cvmdata_warning_source_fallback",
            "cvmdata_warning")
)

# Info
cli::cli_inform(c(
  "v" = "Cached {.val {n_rows}} rows for dataset {.val {dataset}}."
))
```

Convenção dos símbolos cli:

- `"x"` para o erro/sintoma
- `"i"` para informação contextual
- `"!"` para alerta
- `"v"` para sucesso
- `">"` para próximos passos

### 3.8 Opções de pacote (`options()`)

Opções aceitas via `options()` ou `Sys.setenv()` para configuração
session-scoped:

```r
options(
  # Source resolution
  cvmdata.source            = "auto",      # "auto", "cvm", "mirror", "cache"
  cvmdata.cvm_timeout       = 60,          # seconds
  cvmdata.mirror_url        = NULL,        # override mirror base URL

  # Cache
  cvmdata.cache_enabled     = TRUE,
  cvmdata.cache_max_size_mb = 100,         # CRAN-friendly default
  cvmdata.cache_ttl_days    = 30,

  # Validation
  cvmdata.validate_runtime  = FALSE,       # opt-in
  cvmdata.validate_strict   = FALSE,       # warn vs abort on validation fail

  # Logging
  cvmdata.verbose           = TRUE,
  cvmdata.warn_on_large_fetch = TRUE,
  cvmdata.large_fetch_threshold_mb = 200
)
```

Em `R/utils/zzz.R`:

```r
.onLoad <- function(libname, pkgname) {
  op <- options()
  defaults <- list(
    cvmdata.source            = "auto",
    cvmdata.cvm_timeout       = 60,
    cvmdata.mirror_url        = NULL,
    cvmdata.cache_enabled     = TRUE,
    cvmdata.cache_max_size_mb = 100,
    cvmdata.cache_ttl_days    = 30,
    cvmdata.validate_runtime  = FALSE,
    cvmdata.validate_strict   = FALSE,
    cvmdata.verbose           = TRUE,
    cvmdata.warn_on_large_fetch = TRUE,
    cvmdata.large_fetch_threshold_mb = 200
  )
  toset <- !(names(defaults) %in% names(op))
  if (any(toset)) options(defaults[toset])
  invisible()
}
```

### 3.9 Pendências para Rodada 2.5 (naming)

Decisões de naming fino que ficam para subsessão dedicada:

- Nomes finais dos aliases — `fetch_itr()` vs `cvm_itr()` vs
  `get_itr()`? Convenção tidyverse prefere verbos curtos. Recomendação
  preliminar: `fetch_*()`.
- Nomes das tabelas internas em snake_case — manter abreviações
  contábeis (`bpa_con`, `dre_ind`) ou expandir (`assets_consolidated`,
  `income_statement_individual`)? Recomendação preliminar: manter
  abreviações por familiaridade com analistas brasileiros, mas
  documentar expansão no help da função.
- Idioma das colunas das tabelas tidy — `cnpj` em inglês ou
  `cnpj` literal (que é igual em PT-BR e inglês)? Casos como `setor`
  vs `sector`, `pais` vs `country` precisam decisão consistente.
  Recomendação preliminar: inglês quando termo tem tradução, original
  quando é jargão brasileiro intraduzível (`cnpj`, `cd_cvm`).

---

## 4. Schemas Tidy de Saída

Esta seção documenta a transformação de schemas CVM raw → tidy para
os quatro datasets da v0.1. A documentação foi construída a partir
de inspeção empírica direta dos ZIPs CVM em 16/05/2026.

### 4.0 Convenções gerais de transformação

#### 4.0.1 Heterogeneidade entre datasets — fato verificado

Inspeção empírica revelou que a própria CVM usa convenções
inconsistentes entre datasets. O pacote normaliza tudo para um
padrão único.

| Aspecto              | ITR/DFP/CAD                           | FRE                              |
|----------------------|---------------------------------------|----------------------------------|
| Caixa dos nomes      | `SCREAMING_SNAKE_CASE`                | `PascalCase_Com_Subscritos`      |
| CNPJ da companhia    | `CNPJ_CIA`                            | `CNPJ_Companhia`                 |
| Nome da companhia    | `DENOM_CIA`                           | `Nome_Companhia`                 |
| Data de referência   | `DT_REFER`                            | `Data_Referencia`                |
| Versão               | `VERSAO`                              | `Versao`                         |
| Código CVM           | `CD_CVM`                              | (ausente na maioria das tabelas) |

Decisão: **todo output do pacote usa snake_case inglês uniforme**,
mapeando ambos os padrões CVM para as colunas-chave unificadas
definidas na Seção 3.5.3.

#### 4.0.2 Encoding

Todos os CSVs CVM são **ISO-8859-1 (latin1)**. O pacote converte
para UTF-8 internamente em todos os caminhos:

```r
readr::locale(encoding = "ISO-8859-1")
```

Texto livre (campos de declaração no `parecer`, observações) contém
acentos que precisam sobreviver à conversão. Teste automatizado:
snapshot de uma linha com `"Demonstrações"` esperando bytes UTF-8
corretos no output.

#### 4.0.3 Separador e decimais

- Separador de coluna: `;`
- Separador decimal: `.` (ponto)
- Separador de milhares: ausente
- Encoding de NA: campo vazio entre `;;`

```r
readr::read_delim(
  file,
  delim         = ";",
  locale        = readr::locale(
    encoding         = "ISO-8859-1",
    decimal_mark     = ".",
    grouping_mark    = "",
    date_format      = "%Y-%m-%d"
  ),
  na            = c("", "NA"),
  show_col_types = FALSE
)
```

#### 4.0.4 Tratamento de `VERSAO`

CVM permite reapresentações. Uma submissão pode ter `versao = 1`
(original), `versao = 2` (primeira reapresentação), e assim por
diante. **Política do pacote**: retornar **apenas a versão mais
recente** por padrão, com argumento `keep_all_versions = FALSE` no
`fetch_*()` para opt-in da inclusão de todas. Decisão pendente: como
expor essa opção (na assinatura pública, em options, ambos?).

Lógica interna:

```r
keep_latest_version <- function(df, group_cols) {
  df |>
    dplyr::group_by(dplyr::across(dplyr::all_of(group_cols))) |>
    dplyr::filter(.data$version == max(.data$version)) |>
    dplyr::ungroup()
}
```

`group_cols` para ITR/DFP: `c("cnpj", "reference_date")`.
`group_cols` para FRE: `c("cnpj", "reference_date")`.
`group_cols` para CAD: não aplicável (snapshot).

#### 4.0.5 Tratamento de `ORDEM_EXERC`

Tabelas BPA/BPP/DRE/DRA/DFC/DMPL/DVA da ITR/DFP têm coluna
`ORDEM_EXERC` com valores `"ÚLTIMO"` ou `"PENÚLTIMO"`. Indica se a
linha refere-se ao período corrente da submissão ou ao período de
comparação (mesmo período do ano anterior).

Transformação tidy:

- Coluna `is_current_period`: booleano. `TRUE` quando original era
  `"ÚLTIMO"`.
- Coluna `comparison_period_end`: Date. Quando `is_current_period`
  é `TRUE`, é `NA`. Quando é `FALSE`, é o `dt_fim_exerc` daquela
  linha (data de fim do período comparativo).

Justificativa: nomes em português com acento codificado como
ISO-8859-1 são frágeis. Booleano + Date é mais analítico. Quem
preferir o original pode acessar `attr(x, "raw_columns")` (decisão
pendente: implementar ou não).

#### 4.0.6 Tratamento de `ESCALA_MOEDA`

Valor `"MIL"` indica que `VL_CONTA` está expresso em milhares de
reais. Empírico: 100% das observações inspecionadas têm `MIL`.

Política do pacote: **multiplicar VL_CONTA por 1000 por padrão**,
produzindo coluna `account_value` em reais. Coluna
`currency_scale_original` é preservada para reproducibilidade
(valores possíveis: `"unit"`, `"thousand"`, `"million"`; sempre
`"thousand"` no observado, mas estrutura genérica).

Recomendação alternativa rejeitada: manter em milhares. Rejeitada
porque a maioria das análises monetárias quer reais. Quem prefere
milhares pode dividir manualmente.

#### 4.0.7 Tratamento de `CD_CONTA` hierárquico

Coluna `CD_CONTA` (CVM) → `account_code` (tidy). Formato
hierárquico: `"3.01.01.02"`. A profundidade do código indica nível
na árvore de demonstrações.

Coluna adicional derivada: `account_level` (integer) — número de
componentes do `account_code` (`"3" = 1, "3.01" = 2, "3.01.01" = 3,
...`). Calculada por `stringr::str_count(account_code, "\\.") + 1`.

Útil para filtragens analíticas: `filter(account_level == 2)` pega
grupos principais (Receitas, Custos, Despesas).

#### 4.0.8 Tratamento do "4º trimestre ausente"

Companhias abertas entregam ITR para Q1, Q2 e Q3, e DFP para o ano
fiscal completo (que substitui o Q4). Empírico: nenhuma submissão
ITR com `DT_REFER = "YYYY-12-31"` (todas as datas são março, junho,
ou setembro).

Política do pacote: **não fingir que existe Q4 do ITR**. Documentar
isso explicitamente na vignette ITR/DFP. Função utilitária
`reconstruct_q4()` na v0.2+ que combina DFP com ITR-Q3 para
estimar Q4 derivado:

```r
# v0.2+ - documented as derived, not native
reconstruct_q4(year)
# returns Q4 estimate = DFP[year] - ITR_Q3[year]
```

Para v0.1, não implementar. Documentar a limitação.

#### 4.0.9 Tratamento de datas

CVM usa formato ISO `"YYYY-MM-DD"`. Conversão direta com
`readr::locale(date_format = "%Y-%m-%d")`. Empírico: 100% das datas
inspecionadas seguem esse formato.

Exceção: campos como `Data_Composicao_Capital_Social` (FRE) podem
conter `NA` ou data vazia. Tratamento: deixa como `NA_Date_`, não
lança warning.

#### 4.0.10 Tratamento de CNPJ

CVM entrega CNPJ formatado: `"00.000.000/0001-91"`. Política do
pacote: preservar formatação original na coluna `cnpj` (tipo
caractere), e adicionar coluna `cnpj_clean` (apenas dígitos) para
joins. Coluna `cnpj_clean` é caractere, não inteiro, porque pode
começar com zero (`"00000000000191"`).

Decisão pendente: incluir coluna `cnpj_root` (8 primeiros dígitos,
identifica a empresa-mãe)?

Recomendação: sim, porque é frequentemente usada em análise de
holdings. Custo zero.

### 4.1 Dataset `cad` — Informação Cadastral

**Fonte CVM**: `https://dados.cvm.gov.br/dados/CIA_ABERTA/CAD/DADOS/cad_cia_aberta.csv`

**Estrutura**: arquivo único CSV com 46 colunas, ~2.674 linhas
(snapshot em 10/05/2026, conferido). Sem componente temporal — é
sempre o estado atual.

#### 4.1.1 Schema CVM original (46 colunas)

```
CNPJ_CIA              DENOM_SOCIAL          DENOM_COMERC
DT_REG                DT_CONST              DT_CANCEL
MOTIVO_CANCEL         SIT                   DT_INI_SIT
CD_CVM                SETOR_ATIV            TP_MERC
CATEG_REG             DT_INI_CATEG          SIT_EMISSOR
DT_INI_SIT_EMISSOR    CONTROLE_ACIONARIO    TP_ENDER
LOGRADOURO            COMPL                 BAIRRO
MUN                   UF                    PAIS
CEP                   DDD_TEL               TEL
DDD_FAX               FAX                   EMAIL
TP_RESP               RESP                  DT_INI_RESP
LOGRADOURO_RESP       COMPL_RESP            BAIRRO_RESP
MUN_RESP              UF_RESP               PAIS_RESP
CEP_RESP              DDD_TEL_RESP          TEL_RESP
DDD_FAX_RESP          FAX_RESP              EMAIL_RESP
CNPJ_AUDITOR          AUDITOR
```

#### 4.1.2 Schema tidy de saída (após transformação)

| Coluna tidy                  | Tipo  | Origem CVM           | Notas                             |
|------------------------------|-------|----------------------|-----------------------------------|
| `cnpj`                       | chr   | CNPJ_CIA             | Mantém formatação                 |
| `cnpj_clean`                 | chr   | CNPJ_CIA             | Apenas dígitos                    |
| `cnpj_root`                  | chr   | CNPJ_CIA             | 8 primeiros dígitos               |
| `cvm_code`                   | int   | CD_CVM               |                                   |
| `corporate_name`             | chr   | DENOM_SOCIAL         | Razão social                      |
| `trade_name`                 | chr   | DENOM_COMERC         | Nome fantasia                     |
| `registration_date`          | Date  | DT_REG               | Registro CVM                      |
| `incorporation_date`         | Date  | DT_CONST             |                                   |
| `cancellation_date`          | Date  | DT_CANCEL            | NA se ativa                       |
| `cancellation_reason`        | chr   | MOTIVO_CANCEL        |                                   |
| `status`                     | fct   | SIT                  | "ATIVO", "CANCELADA", ...         |
| `status_start_date`          | Date  | DT_INI_SIT           |                                   |
| `sector`                     | chr   | SETOR_ATIV           |                                   |
| `market_type`                | chr   | TP_MERC              |                                   |
| `registration_category`      | chr   | CATEG_REG            |                                   |
| `registration_category_start`| Date  | DT_INI_CATEG         |                                   |
| `issuer_status`              | chr   | SIT_EMISSOR          |                                   |
| `issuer_status_start`        | Date  | DT_INI_SIT_EMISSOR   |                                   |
| `shareholder_control`        | chr   | CONTROLE_ACIONARIO   |                                   |
| `address_type`               | chr   | TP_ENDER             |                                   |
| `address_street`             | chr   | LOGRADOURO           |                                   |
| `address_complement`         | chr   | COMPL                |                                   |
| `address_district`           | chr   | BAIRRO               |                                   |
| `address_city`               | chr   | MUN                  |                                   |
| `address_state`              | chr   | UF                   |                                   |
| `address_country`            | chr   | PAIS                 |                                   |
| `address_postal_code`        | chr   | CEP                  |                                   |
| `phone_ddd`                  | chr   | DDD_TEL              |                                   |
| `phone`                      | chr   | TEL                  |                                   |
| `fax_ddd`                    | chr   | DDD_FAX              |                                   |
| `fax`                        | chr   | FAX                  |                                   |
| `email`                      | chr   | EMAIL                |                                   |
| `responsible_type`           | chr   | TP_RESP              |                                   |
| `responsible_name`           | chr   | RESP                 |                                   |
| `responsible_start_date`     | Date  | DT_INI_RESP          |                                   |
| `responsible_address_*`      | chr×7 | LOGRADOURO_RESP, ... | Mesma estrutura de address        |
| `responsible_phone_*`        | chr×4 | DDD_TEL_RESP, ...    |                                   |
| `responsible_email`          | chr   | EMAIL_RESP           |                                   |
| `auditor_cnpj`               | chr   | CNPJ_AUDITOR         |                                   |
| `auditor_name`               | chr   | AUDITOR              |                                   |

#### 4.1.3 Transformações de tipo

```r
transform_cad <- function(raw) {
  raw |>
    dplyr::transmute(
      cnpj                   = .data$CNPJ_CIA,
      cnpj_clean             = stringr::str_remove_all(.data$CNPJ_CIA, "[^0-9]"),
      cnpj_root              = stringr::str_sub(
        stringr::str_remove_all(.data$CNPJ_CIA, "[^0-9]"),
        1, 8
      ),
      cvm_code               = as.integer(.data$CD_CVM),
      corporate_name         = .data$DENOM_SOCIAL,
      trade_name             = .data$DENOM_COMERC,
      registration_date      = as.Date(.data$DT_REG),
      incorporation_date     = as.Date(.data$DT_CONST),
      cancellation_date      = as.Date(.data$DT_CANCEL),
      cancellation_reason    = .data$MOTIVO_CANCEL,
      status                 = factor(
        .data$SIT,
        levels = c("ATIVO", "CANCELADA", "CONCORDATA",
                   "FALIDA", "LIQUIDACAO", "PARALISADA")
      ),
      status_start_date      = as.Date(.data$DT_INI_SIT),
      sector                 = .data$SETOR_ATIV,
      # ... and so on
    )
}
```

#### 4.1.4 Filtros aceitos por `fetch_cad()`

Quando o usuário passa `companies = c("PETR4", 9512, "33.000.167/0001-01")`:

1. Resolver cada identificador para `cvm_code` (via lookup interno
   ticker→code, parsing CNPJ).
2. Filtrar `dplyr::filter(.data$cvm_code %in% resolved_codes)`.
3. Retornar tibble filtrado.

### 4.2 Dataset `itr` — Formulário de Informações Trimestrais

**Fonte CVM**: `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/ITR/DADOS/itr_cia_aberta_YYYY.zip`

**Estrutura**: 19 tabelas internas por ano. Cobertura empírica:
2011-2026.

#### 4.2.1 Tabelas internas

| Tabela CVM                                     | Nome tidy             | Descrição                                   |
|------------------------------------------------|-----------------------|---------------------------------------------|
| `itr_cia_aberta_YYYY.csv`                      | `header`              | Cabeçalho do formulário (1 linha por submissão) |
| `itr_cia_aberta_BPA_con_YYYY.csv`              | `bpa_con`             | Balanço Patrimonial Ativo, consolidado      |
| `itr_cia_aberta_BPA_ind_YYYY.csv`              | `bpa_ind`             | Balanço Patrimonial Ativo, individual       |
| `itr_cia_aberta_BPP_con_YYYY.csv`              | `bpp_con`             | Balanço Patrimonial Passivo, consolidado    |
| `itr_cia_aberta_BPP_ind_YYYY.csv`              | `bpp_ind`             | Balanço Patrimonial Passivo, individual     |
| `itr_cia_aberta_DRE_con_YYYY.csv`              | `dre_con`             | Demonstração do Resultado, consolidado      |
| `itr_cia_aberta_DRE_ind_YYYY.csv`              | `dre_ind`             | Demonstração do Resultado, individual       |
| `itr_cia_aberta_DRA_con_YYYY.csv`              | `dra_con`             | Demonstração de Resultado Abrangente, con   |
| `itr_cia_aberta_DRA_ind_YYYY.csv`              | `dra_ind`             | Demonstração de Resultado Abrangente, ind   |
| `itr_cia_aberta_DFC_MD_con_YYYY.csv`           | `dfc_md_con`          | Fluxo de Caixa, Método Direto, con          |
| `itr_cia_aberta_DFC_MD_ind_YYYY.csv`           | `dfc_md_ind`          | Fluxo de Caixa, Método Direto, ind          |
| `itr_cia_aberta_DFC_MI_con_YYYY.csv`           | `dfc_mi_con`          | Fluxo de Caixa, Método Indireto, con        |
| `itr_cia_aberta_DFC_MI_ind_YYYY.csv`           | `dfc_mi_ind`          | Fluxo de Caixa, Método Indireto, ind        |
| `itr_cia_aberta_DMPL_con_YYYY.csv`             | `dmpl_con`            | Mutações do Patrimônio Líquido, con         |
| `itr_cia_aberta_DMPL_ind_YYYY.csv`             | `dmpl_ind`            | Mutações do Patrimônio Líquido, ind         |
| `itr_cia_aberta_DVA_con_YYYY.csv`              | `dva_con`             | Valor Adicionado, consolidado               |
| `itr_cia_aberta_DVA_ind_YYYY.csv`              | `dva_ind`             | Valor Adicionado, individual                |
| `itr_cia_aberta_composicao_capital_YYYY.csv`   | `composicao_capital`  | Composição do capital social                |
| `itr_cia_aberta_parecer_YYYY.csv`              | `parecer`             | Pareceres e declarações                     |

#### 4.2.2 Schema do header (`table = "header"`)

CVM raw: 9 colunas.

| Coluna tidy        | Tipo  | CVM        | Notas                                         |
|--------------------|-------|------------|-----------------------------------------------|
| `cnpj`             | chr   | CNPJ_CIA   |                                               |
| `cnpj_clean`       | chr   | CNPJ_CIA   | Derivada                                      |
| `reference_date`   | Date  | DT_REFER   |                                               |
| `version`          | int   | VERSAO     |                                               |
| `company_name`     | chr   | DENOM_CIA  |                                               |
| `cvm_code`         | int   | CD_CVM     |                                               |
| `doc_category`     | chr   | CATEG_DOC  | Sempre "ITR"                                  |
| `doc_id`           | int   | ID_DOC     | ID interno CVM                                |
| `receipt_date`     | Date  | DT_RECEB   | Data de protocolo                             |
| `doc_url`          | chr   | LINK_DOC   | URL para PDF na RAD                           |

#### 4.2.3 Schema das tabelas BPA/BPP/DRE/DRA/DFC/DVA

Estas seis tabelas compartilham estrutura. Variação:

- BPA, BPP: usa `DT_FIM_EXERC` (snapshot patrimonial em data única,
  sem `DT_INI_EXERC`)
- DRE, DRA, DFC, DVA: usa `DT_INI_EXERC` e `DT_FIM_EXERC` (fluxo
  acumulado entre datas)
- DMPL: usa `DT_INI_EXERC`, `DT_FIM_EXERC` e `COLUNA_DF`
  (componente do patrimônio: capital social, reservas, etc.)

CVM raw para BPA (14 colunas):
```
CNPJ_CIA, DT_REFER, VERSAO, DENOM_CIA, CD_CVM, GRUPO_DFP,
MOEDA, ESCALA_MOEDA, ORDEM_EXERC, DT_FIM_EXERC,
CD_CONTA, DS_CONTA, VL_CONTA, ST_CONTA_FIXA
```

Schema tidy para BPA:

| Coluna tidy             | Tipo  | CVM            | Notas                                       |
|-------------------------|-------|----------------|---------------------------------------------|
| `cnpj`                  | chr   | CNPJ_CIA       |                                             |
| `cnpj_clean`            | chr   | CNPJ_CIA       | Derivada                                    |
| `cvm_code`              | int   | CD_CVM         |                                             |
| `company_name`          | chr   | DENOM_CIA      |                                             |
| `reference_date`        | Date  | DT_REFER       | Data da submissão                           |
| `version`               | int   | VERSAO         |                                             |
| `report_type`           | chr   | GRUPO_DFP      | "DF Consolidado - Balanço Patrimonial Ativo"|
| `currency`              | chr   | MOEDA          | Sempre "REAL"                               |
| `currency_scale_original`| chr  | ESCALA_MOEDA   | "MIL" no observado; preservada              |
| `is_current_period`     | lgl   | ORDEM_EXERC    | TRUE se "ÚLTIMO"                            |
| `period_end_date`       | Date  | DT_FIM_EXERC   |                                             |
| `account_code`          | chr   | CD_CONTA       | "1", "1.01", "1.01.01", ...                 |
| `account_level`         | int   | (derivada)     | Número de níveis em CD_CONTA                |
| `account_description`   | chr   | DS_CONTA       |                                             |
| `account_value`         | dbl   | VL_CONTA       | Multiplicado por 1000 se escala = "MIL"     |
| `account_value_original`| dbl   | VL_CONTA       | Valor cru (raw, sem multiplicação)          |
| `is_fixed_account`      | lgl   | ST_CONTA_FIXA  | TRUE se "S"                                 |

Schema tidy para DRE/DRA/DFC/DVA — idem ao BPA, com duas colunas
adicionais:

| Coluna tidy        | Tipo  | CVM            | Notas                                       |
|--------------------|-------|----------------|---------------------------------------------|
| `period_start_date`| Date  | DT_INI_EXERC   | Data inicial do período                     |
| `period_end_date`  | Date  | DT_FIM_EXERC   | Data final do período                       |

Schema tidy para DMPL — idem ao DRE, com coluna adicional:

| Coluna tidy        | Tipo  | CVM            | Notas                                       |
|--------------------|-------|----------------|---------------------------------------------|
| `equity_column`    | chr   | COLUNA_DF      | "Capital Social Integralizado", "Reservas", ... |

#### 4.2.4 Schema da tabela `composicao_capital`

CVM raw (10 colunas):
```
CNPJ_CIA, DT_REFER, VERSAO, DENOM_CIA,
QT_ACAO_ORDIN_CAP_INTEGR, QT_ACAO_PREF_CAP_INTEGR, QT_ACAO_TOTAL_CAP_INTEGR,
QT_ACAO_ORDIN_TESOURO, QT_ACAO_PREF_TESOURO, QT_ACAO_TOTAL_TESOURO
```

Schema tidy:

| Coluna tidy                    | Tipo  | CVM                       |
|--------------------------------|-------|---------------------------|
| `cnpj`                         | chr   | CNPJ_CIA                  |
| `cnpj_clean`                   | chr   | derived                   |
| `reference_date`               | Date  | DT_REFER                  |
| `version`                      | int   | VERSAO                    |
| `company_name`                 | chr   | DENOM_CIA                 |
| `paid_in_common_shares`        | dbl   | QT_ACAO_ORDIN_CAP_INTEGR  |
| `paid_in_preferred_shares`     | dbl   | QT_ACAO_PREF_CAP_INTEGR   |
| `paid_in_total_shares`         | dbl   | QT_ACAO_TOTAL_CAP_INTEGR  |
| `treasury_common_shares`       | dbl   | QT_ACAO_ORDIN_TESOURO     |
| `treasury_preferred_shares`    | dbl   | QT_ACAO_PREF_TESOURO      |
| `treasury_total_shares`        | dbl   | QT_ACAO_TOTAL_TESOURO     |
| `free_float_common_shares`     | dbl   | (derivada)                |
| `free_float_preferred_shares`  | dbl   | (derivada)                |
| `free_float_total_shares`      | dbl   | (derivada)                |

#### 4.2.5 Schema da tabela `parecer`

CVM raw (8 colunas):
```
CNPJ_CIA, DT_REFER, VERSAO, DENOM_CIA,
TP_RELAT_ESP, TP_PARECER_DECL,
NUM_ITEM_PARECER_DECL, TXT_PARECER_DECL
```

Schema tidy:

| Coluna tidy            | Tipo  | CVM                    |
|------------------------|-------|------------------------|
| `cnpj`                 | chr   | CNPJ_CIA               |
| `cnpj_clean`           | chr   | derived                |
| `reference_date`       | Date  | DT_REFER               |
| `version`              | int   | VERSAO                 |
| `company_name`         | chr   | DENOM_CIA              |
| `special_report_type`  | chr   | TP_RELAT_ESP           |
| `opinion_type`         | chr   | TP_PARECER_DECL        |
| `opinion_item_number`  | int   | NUM_ITEM_PARECER_DECL  |
| `opinion_text`         | chr   | TXT_PARECER_DECL       |

Observação: `opinion_text` pode ser muito longo (>10000 chars), com
acentos e quebras de linha. O parser precisa preservar tudo isso na
conversão para UTF-8.

### 4.3 Dataset `dfp` — Demonstrações Financeiras Padronizadas

**Fonte CVM**: `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/DFP/DADOS/dfp_cia_aberta_YYYY.zip`

**Estrutura**: 19 tabelas internas por ano, espelhando exatamente a
ITR (mesmos nomes, mesma estrutura). Cobertura empírica: 2010-2026.

#### 4.3.1 Diferenças face ao ITR

- Período: ano fiscal completo (não trimestre).
- `reference_date` é tipicamente `"YYYY-12-31"`, mas a CVM permite
  exercícios não-coincidentes com ano civil.
- Mesmas 19 tabelas. Schemas idênticos ao ITR.

**O pacote pode compartilhar 100% do código de transformação entre
ITR e DFP**, parametrizando apenas o `dataset_id`. Eu recomendo
implementar via função única `transform_itr_dfp_table()` em
`R/transform/companies_transform.R`:

```r
transform_itr_dfp_table <- function(raw, table_name, dataset_id) {
  switch(
    table_name,
    "header"             = transform_header(raw, dataset_id),
    "composicao_capital" = transform_composicao_capital(raw),
    "parecer"            = transform_parecer(raw),
    "dmpl_con"           = transform_financial_with_equity_col(raw),
    "dmpl_ind"           = transform_financial_with_equity_col(raw),
    transform_financial(raw, table_name)  # default: BPA/BPP/DRE/...
  )
}
```

Justificativa: zero duplicação. Manutenção em um único lugar. Tests
podem rodar sobre fixture do ITR e DFP indiscriminadamente.

### 4.4 Dataset `fre` — Formulário de Referência

**Fonte CVM**: `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/FRE/DADOS/fre_cia_aberta_YYYY.zip`

**Estrutura**: **36 tabelas internas confirmadas** por inspeção
direta de `fre_cia_aberta_2024.zip` em 16/05/2026. Cobertura
empírica: 2021-2026 no Portal (cobertura pré-2021 disponível em
formato anterior, fora de escopo v0.1).

#### 4.4.1 Mudança de schema CVM em 2020

**Importante**: a CVM substituiu o FRE legado (estrutura PDF) pelo FRE
estruturado em 2020. Os ZIPs disponíveis no Portal são apenas para
anos 2020+ (Resolução CVM nº 80/22 consolidou). A v0.1 do `cvmdata`
trata FRE 2021-presente. Anos anteriores: pendência v0.2+ via OCR de
PDFs IPE — mas isso já está fora do escopo permanente do pacote.

#### 4.4.2 Inventário completo das 36 tabelas

Categorização proposta:

##### Categoria A: Cabeçalho e header (1 tabela)

| Tabela CVM                                                  | Nome tidy           |
|-------------------------------------------------------------|---------------------|
| `fre_cia_aberta_YYYY.csv`                                   | `header`            |

##### Categoria B: Capital social e ações (5 tabelas)

| Tabela CVM                                                       | Nome tidy                          |
|------------------------------------------------------------------|------------------------------------|
| `fre_cia_aberta_capital_social_YYYY.csv`                         | `capital_social`                   |
| `fre_cia_aberta_capital_social_classe_acao_YYYY.csv`             | `capital_social_share_class`       |
| `fre_cia_aberta_capital_social_titulo_conversivel_YYYY.csv`      | `capital_social_convertible`       |
| `fre_cia_aberta_distribuicao_capital_YYYY.csv`                   | `capital_distribution`             |
| `fre_cia_aberta_distribuicao_capital_classe_acao_YYYY.csv`       | `capital_distribution_share_class` |

##### Categoria C: Posição acionária (2 tabelas)

| Tabela CVM                                                       | Nome tidy                       |
|------------------------------------------------------------------|---------------------------------|
| `fre_cia_aberta_posicao_acionaria_YYYY.csv`                      | `shareholder_position`          |
| `fre_cia_aberta_posicao_acionaria_classe_acao_YYYY.csv`          | `shareholder_position_class`    |

##### Categoria D: Administração e governança (4 tabelas)

| Tabela CVM                                                                  | Nome tidy                  |
|-----------------------------------------------------------------------------|----------------------------|
| `fre_cia_aberta_administrador_membro_conselho_fiscal_YYYY.csv`              | `directors_and_fiscal`     |
| `fre_cia_aberta_membro_comite_YYYY.csv`                                     | `committee_members`        |
| `fre_cia_aberta_auditor_YYYY.csv`                                           | `auditor`                  |
| `fre_cia_aberta_responsavel_YYYY.csv`                                       | `responsible_officer`      |

##### Categoria E: ESG/diversidade — administradores (3 tabelas)

| Tabela CVM                                                                  | Nome tidy                       |
|-----------------------------------------------------------------------------|---------------------------------|
| `fre_cia_aberta_administrador_declaracao_genero_YYYY.csv`                   | `directors_gender_declaration`  |
| `fre_cia_aberta_administrador_declaracao_raca_YYYY.csv`                     | `directors_race_declaration`    |
| `fre_cia_aberta_administrador_PCD_YYYY.csv`                                 | `directors_pcd_declaration`     |

##### Categoria F: ESG/diversidade — empregados (7 tabelas)

| Tabela CVM                                                                  | Nome tidy                                  |
|-----------------------------------------------------------------------------|--------------------------------------------|
| `fre_cia_aberta_empregado_local_declaracao_genero_YYYY.csv`                 | `employees_local_gender`                   |
| `fre_cia_aberta_empregado_local_declaracao_raca_YYYY.csv`                   | `employees_local_race`                     |
| `fre_cia_aberta_empregado_local_faixa_etaria_YYYY.csv`                      | `employees_local_age_band`                 |
| `fre_cia_aberta_empregado_PCD_YYYY.csv`                                     | `employees_pcd`                            |
| `fre_cia_aberta_empregado_posicao_declaracao_genero_YYYY.csv`               | `employees_position_gender`                |
| `fre_cia_aberta_empregado_posicao_declaracao_raca_YYYY.csv`                 | `employees_position_race`                  |
| `fre_cia_aberta_empregado_posicao_faixa_etaria_YYYY.csv`                    | `employees_position_age_band`              |
| `fre_cia_aberta_empregado_posicao_local_YYYY.csv`                           | `employees_position_location`              |

(Nota: 8 tabelas listadas, mas Categoria F totaliza 7 — uma das
tabelas é compartilhada com PCD. Verificar com lista completa abaixo.)

##### Categoria G: Remuneração (5 tabelas)

| Tabela CVM                                                                  | Nome tidy                          |
|-----------------------------------------------------------------------------|------------------------------------|
| `fre_cia_aberta_remuneracao_total_orgao_YYYY.csv`                           | `compensation_total_by_organ`      |
| `fre_cia_aberta_remuneracao_maxima_minima_media_YYYY.csv`                   | `compensation_max_min_avg`         |
| `fre_cia_aberta_remuneracao_variavel_YYYY.csv`                              | `compensation_variable`            |
| `fre_cia_aberta_remuneracao_acao_YYYY.csv`                                  | `compensation_share_based`         |
| `fre_cia_aberta_acao_entregue_YYYY.csv`                                     | `shares_delivered`                 |

##### Categoria H: Valores mobiliários (3 tabelas)

| Tabela CVM                                                                  | Nome tidy                          |
|-----------------------------------------------------------------------------|------------------------------------|
| `fre_cia_aberta_titular_valor_mobiliario_YYYY.csv`                          | `securities_holders`               |
| `fre_cia_aberta_outro_valor_mobiliario_YYYY.csv`                            | `other_securities`                 |
| `fre_cia_aberta_titulo_exterior_YYYY.csv`                                   | `foreign_listed_securities`        |

##### Categoria I: Relacionamentos (2 tabelas)

| Tabela CVM                                                                  | Nome tidy                |
|-----------------------------------------------------------------------------|--------------------------|
| `fre_cia_aberta_relacao_familiar_YYYY.csv`                                  | `family_relationships`   |
| `fre_cia_aberta_relacao_subordinacao_YYYY.csv`                              | `subordination_links`    |

##### Categoria J: Outras informações empresariais (4 tabelas)

| Tabela CVM                                                                  | Nome tidy                       |
|-----------------------------------------------------------------------------|---------------------------------|
| `fre_cia_aberta_participacao_sociedade_YYYY.csv`                            | `subsidiary_participation`      |
| `fre_cia_aberta_mercado_estrangeiro_YYYY.csv`                               | `foreign_market`                |
| `fre_cia_aberta_transacao_parte_relacionada_YYYY.csv`                       | `related_party_transactions`    |

Contagem: A(1) + B(5) + C(2) + D(4) + E(3) + F(8) + G(5) + H(3) +
I(2) + J(3) = 36. **Confere com o inventário empírico.**

Lista numerada para referência completa:

```
01. header
02. capital_social
03. capital_social_share_class
04. capital_social_convertible
05. capital_distribution
06. capital_distribution_share_class
07. shareholder_position
08. shareholder_position_class
09. directors_and_fiscal
10. committee_members
11. auditor
12. responsible_officer
13. directors_gender_declaration
14. directors_race_declaration
15. directors_pcd_declaration
16. employees_local_gender
17. employees_local_race
18. employees_local_age_band
19. employees_pcd
20. employees_position_gender
21. employees_position_race
22. employees_position_age_band
23. employees_position_location
24. compensation_total_by_organ
25. compensation_max_min_avg
26. compensation_variable
27. compensation_share_based
28. shares_delivered
29. securities_holders
30. other_securities
31. foreign_listed_securities
32. family_relationships
33. subordination_links
34. subsidiary_participation
35. foreign_market
36. related_party_transactions
```

#### 4.4.3 Schemas detalhados das tabelas-chave do FRE

**Tabela 13: `directors_gender_declaration`**

CVM raw (12 colunas):
```
CNPJ_Companhia, Data_Referencia, Versao, ID_Documento,
Nome_Companhia, Orgao_Administracao,
Quantidade_Feminino, Quantidade_Masculino, Quantidade_Nao_Binario,
Quantidade_Outros, Quantidade_Sem_Resposta, Nao_Aplicavel
```

Schema tidy:

| Coluna tidy                       | Tipo  | CVM                      |
|-----------------------------------|-------|--------------------------|
| `cnpj`                            | chr   | CNPJ_Companhia           |
| `cnpj_clean`                      | chr   | derived                  |
| `reference_date`                  | Date  | Data_Referencia          |
| `version`                         | int   | Versao                   |
| `doc_id`                          | int   | ID_Documento             |
| `company_name`                    | chr   | Nome_Companhia           |
| `admin_body`                      | chr   | Orgao_Administracao      |
| `n_female`                        | int   | Quantidade_Feminino      |
| `n_male`                          | int   | Quantidade_Masculino     |
| `n_non_binary`                    | int   | Quantidade_Nao_Binario   |
| `n_other_gender`                  | int   | Quantidade_Outros        |
| `n_no_response_gender`            | int   | Quantidade_Sem_Resposta  |
| `not_applicable`                  | lgl   | Nao_Aplicavel            |

Observação: `admin_body` em FRE pode assumir valores como
`"Conselho de Administração"`, `"Diretoria Estatutária"`, `"Conselho
Fiscal"`. Decisão de mantê-lo em português (jargão jurídico
intraduzível sem perda) ou criar enum em inglês: pendência Rodada 2.5.

**Tabela 14: `directors_race_declaration`**

Schema tidy:

| Coluna tidy              | Tipo  | CVM                      |
|--------------------------|-------|--------------------------|
| `cnpj`                   | chr   | CNPJ_Companhia           |
| ...keys padrão...        |       |                          |
| `admin_body`             | chr   | Orgao_Administracao      |
| `n_yellow`               | int   | Quantidade_Amarelo       |
| `n_white`                | int   | Quantidade_Branco        |
| `n_black`                | int   | Quantidade_Preto         |
| `n_pardo`                | int   | Quantidade_Pardo         |
| `n_indigenous`           | int   | Quantidade_Indigena      |
| `n_other_race`           | int   | Quantidade_Outros        |
| `n_no_response_race`     | int   | Quantidade_Sem_Resposta  |
| `not_applicable`         | lgl   | Nao_Aplicavel            |

Observação sobre `pardo`: termo IBGE oficial (categoria racial de
classificação no Brasil). Não traduzir como `mixed_race` porque perde
a especificidade do termo brasileiro institucional. Documentar no
help da função.

**Tabela 24: `compensation_total_by_organ`**

CVM raw (27 colunas):
```
CNPJ_Companhia, Data_Referencia, Versao, ID_Documento, Nome_Companhia,
Data_Inicio_Exercicio_Social, Data_Fim_Exercicio_Social,
Total_Remuneracao, Orgao_Administracao,
Numero_Membros, Total_Remuneracao_Orgao, Numero_Membros_Remunerados,
Salario, Beneficios_Diretos_Indiretos, Participacoes_Comites,
Outros_Valores_Fixos, Descricao_Outros_Remuneracoes_Fixas,
Bonus, Participacao_Resultados, Participacao_Reunioes,
Outros_Valores_Variaveis, Comissoes,
Descricao_Outros_Remuneracoes_Variaveis,
Pos_emprego, Cessacao_Cargo, Baseada_Acoes, Observacao
```

Schema tidy (sumário):

| Coluna tidy                          | Tipo  | CVM                                  |
|--------------------------------------|-------|--------------------------------------|
| `cnpj`                               | chr   | CNPJ_Companhia                       |
| `reference_date`                     | Date  | Data_Referencia                      |
| `version`                            | int   | Versao                               |
| `fiscal_year_start`                  | Date  | Data_Inicio_Exercicio_Social         |
| `fiscal_year_end`                    | Date  | Data_Fim_Exercicio_Social            |
| `admin_body`                         | chr   | Orgao_Administracao                  |
| `n_members`                          | int   | Numero_Membros                       |
| `n_members_compensated`              | dbl   | Numero_Membros_Remunerados           |
| `total_compensation`                 | dbl   | Total_Remuneracao_Orgao              |
| `total_company_compensation`         | dbl   | Total_Remuneracao                    |
| `salary`                             | dbl   | Salario                              |
| `benefits_direct_indirect`           | dbl   | Beneficios_Diretos_Indiretos         |
| `committee_participation`            | dbl   | Participacoes_Comites                |
| `other_fixed_compensation`           | dbl   | Outros_Valores_Fixos                 |
| `other_fixed_compensation_desc`      | chr   | Descricao_Outros_Remuneracoes_Fixas  |
| `bonus`                              | dbl   | Bonus                                |
| `profit_sharing`                     | dbl   | Participacao_Resultados              |
| `meeting_participation`              | dbl   | Participacao_Reunioes                |
| `other_variable_compensation`        | dbl   | Outros_Valores_Variaveis             |
| `commissions`                        | dbl   | Comissoes                            |
| `other_variable_compensation_desc`   | chr   | Descricao_Outros_Remuneracoes_Variaveis |
| `post_employment`                    | dbl   | Pos_emprego                          |
| `termination`                        | dbl   | Cessacao_Cargo                       |
| `share_based`                        | dbl   | Baseada_Acoes                        |
| `observation`                        | chr   | Observacao                           |

Observação: valores numéricos no FRE estão em **reais nominais**,
não em milhares. Diferente do ITR/DFP. Não aplicar multiplicação
por 1000.

**Tabela 7: `shareholder_position`**

CVM raw (28 colunas) — uma das tabelas mais complexas do FRE.
Schema tidy completo:

| Coluna tidy                                  | Tipo  | CVM                                       |
|----------------------------------------------|-------|-------------------------------------------|
| `cnpj`                                       | chr   | CNPJ_Companhia                            |
| `reference_date`                             | Date  | Data_Referencia                           |
| `version`                                    | int   | Versao                                    |
| `shareholder_id`                             | chr   | ID_Acionista                              |
| `shareholder_name`                           | chr   | Acionista                                 |
| `shareholder_person_type`                    | chr   | Tipo_Pessoa_Acionista                     |
| `shareholder_cpf_cnpj`                       | chr   | CPF_CNPJ_Acionista                        |
| `related_shareholder_id`                     | chr   | ID_Acionista_Relacionado                  |
| `related_shareholder_name`                   | chr   | Acionista_Relacionado                     |
| `related_shareholder_person_type`            | chr   | Tipo_Pessoa_Acionista_Relacionado         |
| `related_shareholder_cpf_cnpj`               | chr   | CPF_CNPJ_Acionista_Relacionado            |
| `common_shares_free_float`                   | dbl   | Quantidade_Acao_Ordinaria_Circulacao      |
| `pct_common_shares_free_float`               | dbl   | Percentual_Acao_Ordinaria_Circulacao      |
| `preferred_shares_free_float`                | dbl   | Quantidade_Acao_Preferencial_Circulacao   |
| `pct_preferred_shares_free_float`            | dbl   | Percentual_Acao_Preferencial_Circulacao   |
| `total_shares_free_float`                    | dbl   | Quantidade_Total_Acoes_Circulacao         |
| `pct_total_shares_free_float`                | dbl   | Percentual_Total_Acoes_Circulacao         |
| `nationality`                                | chr   | Nacionalidade                             |
| `state`                                      | chr   | Sigla_UF                                  |
| `foreign_resident`                           | lgl   | Residente_Exterior                        |
| `legal_representative_name`                  | chr   | Representante_Legal                       |
| `legal_representative_person_type`           | chr   | Tipo_Pessoa_Representante_Legal           |
| `legal_representative_cpf_cnpj`              | chr   | CPF_CNPJ_Representante_legal              |
| `capital_composition_date`                   | Date  | Data_Composicao_Capital_Social            |
| `last_change_date`                           | Date  | Data_Ultima_Alteracao                     |
| `is_controlling_shareholder`                 | lgl   | Acionista_Controlador                     |
| `is_shareholders_agreement_party`            | lgl   | Participante_Acordo_Acionistas            |

**Tabela 9: `directors_and_fiscal`**

CVM raw (21 colunas). Schema tidy de notável complexidade — inclui
data de nascimento de administradores (PII sensível, mas público):

| Coluna tidy                          | Tipo  | CVM                                |
|--------------------------------------|-------|------------------------------------|
| `cnpj`                               | chr   | CNPJ_Companhia                     |
| `reference_date`                     | Date  | Data_Referencia                    |
| `version`                            | int   | Versao                             |
| `admin_body`                         | chr   | Orgao_Administracao                |
| `name`                               | chr   | Nome                               |
| `cpf`                                | chr   | CPF                                |
| `profession`                         | chr   | Profissao                          |
| `position`                           | chr   | Cargo_Eletivo_Ocupado              |
| `position_complement`                | chr   | Complemento_Cargo_Eletivo_Ocupado  |
| `election_date`                      | Date  | Data_Eleicao                       |
| `inauguration_date`                  | Date  | Data_Posse                         |
| `first_term_start_date`              | Date  | Data_Inicio_Primeiro_Mandato       |
| `term_length`                        | chr   | Prazo_Mandato                      |
| `elected_by_controller`              | lgl   | Eleito_Controlador                 |
| `other_role`                         | chr   | Outro_Cargo_Funcao                 |
| `professional_experience`            | chr   | Experiencia_Profissional           |
| `birth_date`                         | Date  | Data_Nascimento                    |
| `consecutive_terms`                  | int   | Numero_Mandatos_Consecutivos       |
| `meeting_attendance_pct`             | dbl   | Percentual_Participacao_Reunioes   |

#### 4.4.4 Padrão recorrente: tabelas de declaração de gênero/raça/PCD

Categorias E (administradores) e F (empregados) têm 11 tabelas com
padrão estrutural muito similar. Implementar via função
parametrizada:

```r
transform_diversity_declaration <- function(
  raw, kind = c("gender", "race", "pcd", "age_band")
) {
  # generic transformation, with column mapping depending on `kind`
}
```

Justificativa: reduz código duplicado de ~330 linhas (11 × ~30) para
~70 linhas (uma função genérica + dispatcher).

#### 4.4.5 Decisão pendente: explosão de fatores

Tabelas como `directors_gender_declaration` têm uma linha por
companhia × admin_body. Quando o analista pede `fetch_fre(table =
"directors_gender_declaration", companies = c("PETR4", "VALE3"))`,
recebe um tibble com várias linhas por empresa (uma por órgão).

Tipo do retorno em "long" format (uma linha por
companhia×órgão×categoria) seria mais flexível para análises com
`ggplot2` e `dplyr`. Versão "wide" (uma linha por
companhia×órgão, colunas para cada categoria) é o padrão CVM.

Decisão preliminar: **manter wide por default** (paralelo direto ao
CVM), e oferecer função auxiliar `cvm_pivot_diversity()` para
converter para long quando solicitado:

```r
fetch_fre(table = "directors_gender_declaration", companies = "PETR4") |>
  cvm_pivot_diversity()  # converte para long
```

Decisão pendente para Rodada 2.5: nome dessa função utilitária.

### 4.5 Modelo extensível de schemas

#### 4.5.1 Especificação interna

Toda tabela é descrita por um objeto `cvm_table_schema` armazenado em
`inst/extdata/schemas/<dataset>/<table>.yaml`. Exemplo
(`itr/bpa_con.yaml`):

```yaml
dataset: itr
table: bpa_con
entity_class: companies
csv_pattern: "itr_cia_aberta_BPA_con_(\\d{4})\\.csv"
period_granularity: yearly
encoding: ISO-8859-1
delim: ";"
columns:
  - cvm: CNPJ_CIA
    tidy: cnpj
    type: character
    role: key
  - cvm: DT_REFER
    tidy: reference_date
    type: date
    role: key
  - cvm: VERSAO
    tidy: version
    type: integer
    role: key
  - cvm: DENOM_CIA
    tidy: company_name
    type: character
  - cvm: CD_CVM
    tidy: cvm_code
    type: integer
    role: key
  - cvm: GRUPO_DFP
    tidy: report_type
    type: character
  - cvm: MOEDA
    tidy: currency
    type: character
  - cvm: ESCALA_MOEDA
    tidy: currency_scale_original
    type: character
  - cvm: ORDEM_EXERC
    tidy: order_exerc_raw
    type: character
    transform: order_exerc_to_logical
  - cvm: DT_FIM_EXERC
    tidy: period_end_date
    type: date
  - cvm: CD_CONTA
    tidy: account_code
    type: character
  - cvm: DS_CONTA
    tidy: account_description
    type: character
  - cvm: VL_CONTA
    tidy: account_value_original
    type: double
    transform: apply_currency_scale
  - cvm: ST_CONTA_FIXA
    tidy: is_fixed_account
    type: logical
    transform: s_n_to_logical
derived_columns:
  - tidy: cnpj_clean
    formula: "remove_non_digits(cnpj)"
  - tidy: account_level
    formula: "count_dots(account_code) + 1"
  - tidy: is_current_period
    formula: "order_exerc_raw == 'ÚLTIMO'"
  - tidy: account_value
    formula: "apply_scale(account_value_original, currency_scale_original)"
```

#### 4.5.2 Por que YAML em vez de R puro

Alternativas avaliadas:

- **YAML** (recomendada): externa ao código; permite editar schema
  sem mexer em arquivos `.R`; facilita validação por linter externo;
  data-raw script gera índice consolidado em `inst/extdata/schemas.rds`
  no momento de build.
- **R lists** (`R/schemas/companies/itr.R`): familiar, mas mistura
  dados e código; revisão de schema vira revisão de código R.
- **JSON**: viável, mas YAML é mais legível para humano.

Recomendação: YAML como fonte de verdade; `data-raw/build_schemas.R`
converte para RDS embarcado em `inst/extdata/`. Em runtime, o pacote
carrega o RDS (rápido) e usa para transformação. YAML fica versionado
no Git como fonte de verdade auditável.

#### 4.5.3 Como adicionar uma classe nova (v0.4+)

Para incluir FII na v0.4:

1. Adicionar `R/schemas/funds/` e arquivos YAML para cada tabela FII.
2. Adicionar `R/transform/funds_transform.R`.
3. Registrar novos dataset_ids em
   `data-raw/build_dataset_index.R`.
4. Implementar `fetch_fii_internal()` em `R/api/fetch_funds.R`.
5. Adicionar testes em `tests/testthat/test-fetch_fii.R`.

Zero modificação em código de companhias.

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

Pseudocódigo do fluxo:

```r
fetch_with_cache <- function(dataset, ...) {
  cache_meta <- read_cache_meta(dataset)
  is_stale <- (
    is.null(cache_meta) ||
    difftime(Sys.time(), cache_meta$fetched_at, units = "days") >
      getOption("cvmdata.cache_ttl_days", 30)
  )
  if (!is_stale) {
    return(read_from_cache(dataset, ...))
  }
  # try HEAD CVM
  head_result <- safe_head_cvm(dataset)
  if (!is.null(head_result) &&
      head_result$etag == cache_meta$etag) {
    update_cache_meta(dataset, last_check = Sys.time())
    return(read_from_cache(dataset, ...))
  }
  # download fresh
  fetch_from_source(dataset, ...)
}
```

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

```r
maybe_evict_cache <- function() {
  limit_mb <- getOption("cvmdata.cache_max_size_mb", 100)
  current_mb <- get_cache_size_mb()
  if (current_mb < limit_mb * 0.9) return(invisible())

  files_lru <- list_cache_files_lru()
  target_mb <- limit_mb * 0.7
  while (current_mb > target_mb && nrow(files_lru) > 0) {
    f <- files_lru[1, ]
    file.remove(f$path)
    current_mb <- current_mb - f$size_mb
    files_lru <- files_lru[-1, ]
  }
}
```

#### 5.4.3 Aviso ao usuário

Quando o cache cresce além de 70% do limite, emitir
`cli::cli_alert_info()` na próxima chamada `fetch_*()`:

```
i Cache size: 78 MB of 100 MB limit (78%). Use cvm_cache_clear() to free space.
```

### 5.5 Backend

#### 5.5.1 Para arquivos físicos (L1 + L3): direto no filesystem

Não usar `cachem` para arquivos grandes — `cachem` é otimizado para
key-value de valores R em memória, não para arquivos. Usar
`file.path()` + `file.exists()` + `tools::R_user_dir()` diretamente.

#### 5.5.2 Para L4 (resultado de query em memória): `cachem::cache_mem()`

Cache em memória da sessão para evitar reparse quando o usuário
chama `fetch_itr()` repetidamente com mesmos argumentos:

```r
# in R/utils/cache_memory.R
.cvmdata_mem_cache <- NULL

.onLoad <- function(libname, pkgname) {
  .cvmdata_mem_cache <<- cachem::cache_mem(
    max_size = 50 * 1024^2,    # 50 MB
    max_age  = 60 * 60,        # 1 hora
    evict    = "lru"
  )
}

fetch_with_mem_cache <- function(key, fn) {
  if (is.null(.cvmdata_mem_cache)) return(fn())
  cached <- .cvmdata_mem_cache$get(key)
  if (!cachem::is.key_missing(cached)) return(cached)
  result <- fn()
  .cvmdata_mem_cache$set(key, result)
  result
}
```

Decisão pendente: `cachem` em `Imports` ou `Suggests`?

- Em `Imports`: garante L4 sempre disponível.
- Em `Suggests`: L4 vira opt-in, mas não pesa em instalação.

Recomendação: **`Imports`**. Tamanho de `cachem` é pequeno (kilobytes)
e o benefício de performance justifica.

### 5.6 Fallback hierárquico

Ordem de resolução com `source = "auto"`:

```
1. L4 (memory cache) → se hit, retornar.
2. L1 (raw ZIP no disk) → se não-stale, transformar para L3 e retornar.
3. CVM HTTP → download para L1, transformar, retornar.
4. Mirror GitHub Releases → query DuckDB direto, retornar.
5. Erro: nenhuma fonte disponível.
```

A escolha de pular L3 cache para L4 é deliberada: L3 já está
materializado por `fetch_*()` e cabe em L4 quando pequeno. Se for
muito grande para L4, L3 é regenerado a cada chamada (custo
aceitável para datasets que não cabem em memória).

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

#### 6.3.1 `01_detect_changes.R`

Itera sobre o catálogo de datasets (lido de `inst/extdata/dataset_index.rds`),
faz `HEAD` HTTP em cada URL de ZIP/CSV, compara `ETag` ou
`Last-Modified` com o snapshot anterior (lido do release mais
recente). Emite `changed_datasets` para `${GITHUB_OUTPUT}` (JSON
array de ids) e `snapshot_date` como ISO date.

```r
# inst/etl/01_detect_changes.R
suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
  library(cli)
})

force_rebuild <- identical(Sys.getenv("FORCE_REBUILD"), "true")
datasets_arg  <- Sys.getenv("DATASETS")

dataset_index <- readRDS("inst/extdata/dataset_index.rds")
if (nzchar(datasets_arg)) {
  selected <- strsplit(datasets_arg, ",")[[1]] |> trimws()
  dataset_index <- dataset_index[dataset_index$id %in% selected, ]
}

previous_manifest <- tryCatch(
  fromJSON("https://github.com/sidneybissoli/cvmdata/releases/latest/download/snapshot_info.json"),
  error = function(e) list(datasets = list())
)

changed <- character()
for (i in seq_len(nrow(dataset_index))) {
  ds  <- dataset_index[i, ]
  for (url in ds$urls[[1]]) {
    resp <- tryCatch(
      req_perform(req_method(request(url), "HEAD")),
      error = function(e) NULL
    )
    if (is.null(resp)) next
    etag <- resp_header(resp, "ETag")
    lm   <- resp_header(resp, "Last-Modified")
    prev <- previous_manifest$datasets[[ds$id]]
    if (force_rebuild ||
        is.null(prev) ||
        !identical(prev$etag, etag) ||
        !identical(prev$last_modified, lm)) {
      changed <- c(changed, ds$id)
      break
    }
  }
}
changed <- unique(changed)

cli_inform("Detected {length(changed)} changed dataset(s)")
writeLines(c(
  paste0("changed_datasets=", toJSON(as.list(changed), auto_unbox = TRUE)),
  paste0("snapshot_date=", format(Sys.Date()))
), con = Sys.getenv("GITHUB_OUTPUT"))
```

#### 6.3.2 `02_download_zip.R`

Recebe `dataset_id` por argumento. Baixa o ZIP (ou CSV no caso de
CAD) para `build/raw/<dataset_id>/`. Confere sha256.

#### 6.3.3 `03_transform_to_parquet.R`

Aplica a transformação tidy (mesmo código usado pelo pacote em
runtime, importado via `local::.`). Escreve Parquet particionado em
`build/parquet/<dataset_id>/<table>/year=YYYY/part-0.parquet`.

#### 6.3.4 `04_validate.R`

Roda pointblank em cada Parquet recém-gerado. Em caso de falha
crítica, sai com `quit(status = 1)`.

#### 6.3.5 `05_build_manifest.R`

Constrói `manifest.duckdb` com índice de todas as partições, suas
linhas, tamanhos, hash. Usado pelo pacote em runtime para query
seletiva.

#### 6.3.6 `06_bundle_release.R`

Empacota Parquet e manifest em assets do release. Gera
`checksums.txt` (sha256 de cada arquivo) e `snapshot_info.json`
(metadata legível: data, datasets incluídos, hashes CVM no momento
do bundle).

#### 6.3.7 `07_release_notes.R`

Gera markdown sumarizando o que mudou desde o último snapshot: novos
datasets, número de linhas adicionadas, alertas de pointblank
(soft fails que não bloquearam mas merecem atenção).

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
│   ├── bpa_ind_2024.parquet
│   ├── ...
├── dfp/
│   ├── header_2024.parquet
│   ├── bpa_con_2024.parquet
│   ├── ...
├── fre/
│   ├── header_2024.parquet
│   ├── ...
└── cad/
    └── cad_2026-05-19.parquet
```

Cada arquivo Parquet tem ~5-30 MB. Total esperado por snapshot na
v0.1: ~500 MB-1 GB. Acumulando histórico: ~15-20 snapshots de 1 GB
em 2 anos = 15-20 GB. GitHub Releases comporta isso confortavelmente
(limite por release é 2 GB e número de releases é ilimitado).

### 6.5 Compatibilidade pacote ↔ release

O pacote precisa saber **qual release consumir**. Estratégias:

#### 6.5.1 Alternativas

- **(a)** Sempre o latest release.
- **(b)** Versão específica fixada em `inst/extdata/required_snapshot.txt`.
- **(c)** Híbrido: pacote tenta latest; cai para versão mínima se
  schema diverge.

#### 6.5.2 Recomendação

**(c) híbrido.** Em runtime, o pacote:

1. Pega o latest release via `https://github.com/sidneybissoli/cvmdata/releases/latest`.
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

Quando uma versão futura do pacote mudar schema (ex: v0.2 adiciona
FCA), incrementa `schema_version` no ETL e no pacote. Pacote v0.1
continua funcionando porque os Parquet antigos têm `schema_version =
1` e o pacote v0.1 espera `1`.

### 6.6 Custo estimado

- **GitHub Actions free tier**: 2.000 minutos/mês para conta
  pessoal em repos públicos. Pacote em repo público = ilimitado para
  Actions (não conta minutos).
- **GitHub Releases**: ilimitado em número e armazenamento para repos
  públicos.

Tempo estimado por run completo na v0.1:
- detect-changes: ~2 min (HEAD em todos os datasets)
- build-parquet: ~3-8 min por dataset, paralelo via matrix
- validate-parquet: ~3 min
- publish-release: ~2 min
- **Total wall-clock**: ~15-20 min por terça-feira

**Custo estimado v0.4+ com fundos**: indeterminado. Pode estourar
tempo de transformação se rodar tudo serial. Mitigação: matrix
expansion por fund-class ou shard por CNPJ.

### 6.7 Secrets necessários

- `GITHUB_TOKEN`: automático, fornecido pelo runner. Suficiente para
  criar releases e issues no próprio repo.
- Nenhum secret externo necessário para a v0.1.

Futuro: se migrar mirror para Cloudflare R2 ou Zenodo,
`CLOUDFLARE_ACCESS_KEY`, `ZENODO_API_TOKEN`. Não necessário agora.

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
  expected_cols <- c(
    expected_cols,
    vapply(schema$derived_columns, `[[`, "", "tidy")
  )

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
    col_vals_in_set(
      columns = "currency",
      set     = c("REAL"),
      preconditions = ~ . |> dplyr::filter(!is.na(.data$currency))
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

Tabelas específicas têm checks específicos. Exemplos:

**`composicao_capital` (ITR/DFP)**: a soma de ordinárias + preferenciais
deve igualar o total (com tolerância para floats):

```r
agent |>
  col_vals_equal(
    columns = "paid_in_total_shares",
    value   = vars(paid_in_common_shares + paid_in_preferred_shares),
    na_pass = TRUE
  )
```

**`bpa_con` (ITR/DFP)**: account_code "1" (Ativo Total) deve existir
em toda submissão; valor deve ser positivo.

```r
agent |>
  col_vals_gt(
    columns       = "account_value",
    value         = 0,
    preconditions = ~ . |> dplyr::filter(.data$account_code == "1")
  )
```

**`directors_gender_declaration` (FRE)**: soma das categorias deve
ser razoável (não-negativa, com valor `not_applicable = TRUE`
permitido).

```r
agent |>
  col_vals_gte(
    columns = c("n_female", "n_male", "n_non_binary",
                "n_other_gender", "n_no_response_gender"),
    value   = 0,
    na_pass = TRUE
  )
```

#### 7.2.3 Foreign keys cross-table

`cad` é referencial. Todo `cnpj` em ITR/DFP/FRE deve existir em
`cad` ou em `cad_history` (futuro v0.2 com FCA). Para v0.1, validar
soft-fail (warn, não stop):

```r
agent_xref <- create_agent(
  tbl   = itr_header,
  label = "itr_header_cnpj_in_cad",
  actions = action_levels(warn_at = 0.05, stop_at = 0.50)
) |>
  rows_complete(columns = "cnpj_in_cad") |>
  interrogate()
```

(Implementação real exige left join entre os dois Parquets antes do
agent.)

### 7.3 Gates em runtime do pacote

#### 7.3.1 Opt-in via opção

Por padrão, **não validar em runtime**. Razões:

- Custo (~1-3s por chamada com pointblank em tibble grande).
- Mensagens podem confundir analistas iniciantes.

Quando o usuário fizer:

```r
options(cvmdata.validate_runtime = TRUE)
fetch_itr(table = "bpa_con", years = 2024)
```

O pacote roda um conjunto reduzido de checks essenciais antes de
retornar, emitindo `rlang::warn()` com classe
`cvmdata_warning_validation_soft_fail`.

#### 7.3.2 Checks runtime essenciais

```r
validate_runtime <- function(df, table, dataset) {
  if (!isTRUE(getOption("cvmdata.validate_runtime", FALSE))) {
    return(invisible(df))
  }
  schema <- load_schema(dataset, table)
  expected_cols <- vapply(schema$columns, `[[`, "", "tidy")

  missing_cols <- setdiff(expected_cols, names(df))
  if (length(missing_cols) > 0) {
    rlang::warn(
      message = c(
        "Schema drift detected in {.val {dataset}}/{.val {table}}",
        "!" = "Missing columns: {.val {missing_cols}}",
        "i" = "Source may have changed since last package update."
      ),
      class = c("cvmdata_warning_schema_drift",
                "cvmdata_warning")
    )
  }
  invisible(df)
}
```

### 7.4 Logging

ETL: validation report bundled como artifact (`build/validation/`).
HTML rendered via `pointblank::interrogate(agent) |> get_agent_report(display = "html")`,
incluído no GitHub Actions artifact e mencionado nas release notes
quando há soft fails.

Runtime: warnings R nativos, captáveis por
`withCallingHandlers()` para integração em pipelines de monitoramento
do usuário.

---

## 8. Estratégia de Testes

### 8.1 Princípios gerais

A política de testes do `cvmdata` é guiada por três princípios:

1. **Determinismo CRAN-friendly.** Testes em `tests/testthat/` devem
   rodar sem rede, sem cache externo, sem dependência de
   `dados.cvm.gov.br` ou do mirror GitHub. Todo teste que toca a
   internet é movido para o sufixo de integração (`test-integration-*.R`)
   e protegido por `testthat::skip_on_cran()` + `skip_if_offline()`.
2. **Fixtures pequenos e reais.** Em vez de mockar dataframes
   sintéticos, mantemos amostras reais (50-200 linhas) dos CSVs da
   CVM em `tests/testthat/fixtures/`, congeladas em uma data conhecida.
   Cada fixture vem acompanhada de um arquivo `*.meta.json` registrando
   a origem (URL CVM exato), a data de download, e o número de linhas
   originais antes da redução.
3. **Cobertura alvo 90%.** Métrica via `covr::package_coverage()`,
   publicada no Codecov. Linhas não cobertas devem ser justificadas
   por comentário `# nocov` apenas para handlers de erro raríssimos
   (e.g., falhas de hardware durante escrita de cache). Branches de
   `if (interactive())` e similares são excluídos via `.covrignore`.

### 8.2 Framework e organização

`testthat` versão 3.x com edição `3` declarada em `DESCRIPTION`:

```
Config/testthat/edition: 3
Config/testthat/parallel: true
```

O modo paralelo é habilitado porque a maioria dos testes é puramente
funcional (transformações in-memory sobre fixtures), com benefício
mensurável em `R CMD check` local.

A organização de arquivos espelha a estrutura de `R/`:

```
tests/
├── testthat/
│   ├── helper-fixtures.R          # carregadores compartilhados
│   ├── helper-mocks.R             # mocks HTTP via httptest2
│   ├── helper-skip.R              # skip_on_cran wrappers
│   ├── fixtures/
│   │   ├── cad/
│   │   │   └── cad_cia_aberta_sample.csv
│   │   ├── itr/
│   │   │   ├── 2024/
│   │   │   │   ├── itr_cia_aberta_2024_header.csv
│   │   │   │   ├── itr_cia_aberta_bpa_con_2024.csv
│   │   │   │   └── ... (até 19 arquivos)
│   │   │   └── meta.json
│   │   ├── dfp/2023/...
│   │   └── fre/2024/...
│   ├── test-api-fetch_cvm.R       # dispatch público
│   ├── test-api-fetch_cad.R       # alias tipado
│   ├── test-api-fetch_itr.R
│   ├── test-api-fetch_dfp.R
│   ├── test-api-fetch_fre.R
│   ├── test-api-validate-inputs.R
│   ├── test-dispatch-resolve.R    # roteamento interno
│   ├── test-schemas-load.R        # parser YAML de schemas
│   ├── test-schemas-cad.R         # rename + cast CAD
│   ├── test-schemas-itr.R         # rename + cast ITR (19 tabelas)
│   ├── test-schemas-dfp.R
│   ├── test-schemas-fre.R         # 36 tabelas
│   ├── test-transform-cad.R       # transformação ponta-a-ponta
│   ├── test-transform-itr.R
│   ├── test-transform-dfp.R
│   ├── test-transform-fre.R
│   ├── test-cache-paths.R         # resolução de paths
│   ├── test-cache-etag.R          # invalidação ETag
│   ├── test-cache-ttl.R           # invalidação TTL
│   ├── test-cache-size.R          # limite 100 MB e LRU
│   ├── test-source-cvm.R          # parser de URL CVM (mockado)
│   ├── test-source-mirror.R       # parser de release GitHub (mockado)
│   ├── test-source-fallback.R     # cvm → mirror → erro
│   ├── test-validate-pointblank.R # checks runtime
│   ├── test-errors.R              # classes de erro
│   ├── test-utils-period.R        # normalize_period_yearly/quarterly
│   ├── test-utils-entities.R      # normalize_company_id (CNPJ/CVM/ticker)
│   ├── test-integration-cvm.R     # rede real, skip_on_cran
│   └── test-integration-mirror.R  # rede real, skip_on_cran
├── testthat.R
└── README.md                      # como atualizar fixtures
```

### 8.3 Fixtures: política de gestão

Os fixtures são versionados no Git. Atualização manual e
deliberada, com script auxiliar em `inst/scripts/refresh-fixtures.R`:

```r
# Reduces real CVM CSV files to small, deterministic samples
# Run manually when refreshing fixtures. Not part of CI.
refresh_fixtures <- function(
  dataset = c("cad", "itr", "dfp", "fre"),
  year    = 2024,
  n_rows  = 100,
  seed    = 42
) {
  dataset <- match.arg(dataset)
  set.seed(seed)
  # Download, sample, write under tests/testthat/fixtures/<dataset>/
  # Always record meta.json with origin URL, download timestamp,
  # and original row count.
}
```

Critérios de seleção da amostra:

- **CAD**: amostragem aleatória estratificada por `SIT` (situação
  registral) para garantir cobertura de ativos, cancelados,
  paralisados.
- **ITR/DFP**: subconjunto de 5-10 empresas escolhidas para cobrir
  variação de setor (CVM 22 codifica setor), tamanho e versão de
  retransmissão (1, 2, 3+). Inclusão obrigatória de pelo menos uma
  empresa com DRE consolidada e individual em ambos os trimestres do
  ano-amostra.
- **FRE**: subconjunto cobrindo as 36 tabelas, garantindo que todas
  tenham pelo menos 5 linhas. Algumas tabelas FRE são esparsamente
  preenchidas (e.g., `fatos_relevantes_fre` pode ter 0 linhas para a
  maioria das empresas); a amostra prioriza empresas com FRE
  completo.

Tamanho total dos fixtures cap em 5 MB para não inflar o tarball
CRAN. Hoje a estimativa é ~2.5 MB.

### 8.4 Mocks de HTTP

Para testar a camada `R/source/cvm/` e `R/source/mirror/` sem rede,
usamos `httptest2`. O padrão é registrar respostas mockadas em
`tests/testthat/_mocks/`:

```r
# test-source-cvm.R
library(httptest2)

with_mock_dir("cvm_itr_2024", {
  test_that("fetch_cvm correctly parses CVM ITR ZIP", {
    skip_if_not_installed("httptest2")
    result <- cvmdata:::source_cvm_fetch(
      dataset = "itr",
      table   = "bpa_con",
      year    = 2024
    )
    expect_s3_class(result, "tbl_df")
    expect_named(result, c("cnpj", "company_name", ...))
  })
})
```

A pasta `_mocks/cvm_itr_2024/` é gerada uma única vez via
`httptest2::start_capturing()` e depois congelada no repositório.
Quando a CVM altera o servidor (URL, headers), regravamos os mocks
manualmente.

### 8.5 Snapshot tests

`testthat::expect_snapshot()` é usado para:

- **Mensagens de erro**: cada classe de erro
  (`cvmdata_error_validation_input`, `cvmdata_error_source_unreachable`,
  `cvmdata_error_schema_drift`, etc.) tem um snapshot da mensagem
  formatada via `cli::cli_abort()`. Quando refatoramos mensagens,
  o snapshot guia o review.
- **Estrutura de output**: `dplyr::glimpse()` do retorno de
  `fetch_itr(table = "bpa_con", years = 2023, entities = "PETR4")`
  é snapshotado, capturando nomes de colunas, tipos e ordem.
- **Atributos**: o atributo `cvmdata_metadata` anexado ao retorno é
  serializado para snapshot.

Snapshots vivem em `tests/testthat/_snaps/`.

### 8.6 Testes de regressão de schema

Cada vez que descobrimos que a CVM mudou um schema (e.g., adicionou
uma coluna em `bpa_con` em 2023), o caso passa por três etapas:

1. Adicionamos um fixture novo capturando o estado pós-mudança.
2. Atualizamos o YAML de schema correspondente.
3. Escrevemos um teste em `test-schemas-regression.R` que carrega o
   fixture antigo e o novo e verifica que ambos chegam ao schema
   tidy unificado.

Isso documenta a evolução temporal do dado fonte dentro do
repositório do pacote — útil para auditoria de pesquisa
reprodutível.

### 8.7 Testes de integração (skip_on_cran)

Em `test-integration-cvm.R`:

```r
test_that("real CVM endpoint returns ITR 2024 CSV", {
  skip_on_cran()
  skip_if_offline("dados.cvm.gov.br")
  skip_if(Sys.getenv("CVMDATA_RUN_INTEGRATION") != "true")

  result <- fetch_itr(table = "header", years = 2024)
  expect_s3_class(result, "tbl_df")
  expect_gt(nrow(result), 1000)
})
```

A guarda `CVMDATA_RUN_INTEGRATION` evita que esses testes rodem
sequer no CI default: só rodam em workflow dedicado
(`.github/workflows/integration.yml`, weekly cron). Justificativa:
testes de integração ficam vermelhos por motivos alheios ao código
(manutenção CVM, lentidão de rede), e poluem o sinal de PR.

### 8.8 Política de paralelismo nos testes

Sidney pede paralelismo explícito por default. Em R, isso significa:

- `Config/testthat/parallel: true` no DESCRIPTION (testthat usa
  `parallel::makeCluster()` com `parallel::detectCores() - 1`).
- Em fixtures pesados (carregar 36 CSVs FRE), usar `future.apply`
  ou `purrr::map()` paralelizado quando aplicável. Para fixtures
  pequenos, paralelizar é overhead.
- No CI, set `_R_CHECK_TESTS_NLINES_=0` para output completo em
  falhas.

### 8.9 O que não testamos

Decisões explícitas de **não-teste**:

- **Cache real em `tools::R_user_dir()` do CI**: cada job de CI usa
  diretório temporário via `withr::with_tempdir()`. Não persistimos
  cache entre jobs.
- **Compatibilidade com versões antigas do tidyverse**: declaramos
  versão mínima em `DESCRIPTION` e testamos contra ela + `release` +
  `devel` no R-CMD-check. Não regredimos para tidyverse 1.x.
- **Performance**: não temos teste de benchmark dentro do `testthat`.
  Microbenchmarks vivem em `inst/benchmarks/` e são manuais.

---

## 9. CI/CD

### 9.1 Visão geral dos workflows GitHub Actions

Cinco workflows, todos em `.github/workflows/`:

| Workflow | Trigger | Objetivo |
|---|---|---|
| `R-CMD-check.yaml` | push, PR | Matriz devel/release/oldrel × Ubuntu/macOS/Windows |
| `test-coverage.yaml` | push em `main`, PR | Cobertura via `covr::codecov()` |
| `lint.yaml` | push, PR | `lintr` + `styler` em modo check |
| `pkgdown.yaml` | push em `main`, tags | Build e deploy do site `pkgdown` |
| `etl-mirror.yaml` | cron, manual | Pipeline ETL (já documentado na §6) |
| `integration.yaml` | cron weekly, manual | Testes contra CVM e mirror reais |

### 9.2 R-CMD-check (workflow principal)

```yaml
name: R-CMD-check

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  R-CMD-check:
    runs-on: ${{ matrix.config.os }}
    name: ${{ matrix.config.os }} (R ${{ matrix.config.r }})

    strategy:
      fail-fast: false
      matrix:
        config:
          - {os: ubuntu-latest,  r: 'devel',  http-user-agent: 'release'}
          - {os: ubuntu-latest,  r: 'release'}
          - {os: ubuntu-latest,  r: 'oldrel-1'}
          - {os: macos-latest,   r: 'release'}
          - {os: windows-latest, r: 'release'}

    env:
      GITHUB_PAT: ${{ secrets.GITHUB_TOKEN }}
      R_KEEP_PKG_SOURCE: yes
      _R_CHECK_TESTS_NLINES_: 0
      _R_CHECK_FORCE_SUGGESTS_: false

    steps:
      - uses: actions/checkout@v4

      - uses: r-lib/actions/setup-pandoc@v2

      - uses: r-lib/actions/setup-r@v2
        with:
          r-version: ${{ matrix.config.r }}
          http-user-agent: ${{ matrix.config.http-user-agent }}
          use-public-rspm: true

      - uses: r-lib/actions/setup-r-dependencies@v2
        with:
          extra-packages: |
            any::rcmdcheck
            any::pkgload
            local::.
          needs: check

      - uses: r-lib/actions/check-r-package@v2
        with:
          args: 'c("--no-manual", "--as-cran")'
          error-on: '"warning"'
          check-dir: '"check"'

      - name: Upload check artifacts
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: ${{ matrix.config.os }}-${{ matrix.config.r }}-results
          path: check
```

Pontos relevantes:

- `error-on: "warning"` — qualquer `WARNING` falha o build (política
  CRAN-strict desde o dia zero, para reduzir surpresas no
  submission).
- `_R_CHECK_FORCE_SUGGESTS_: false` — pacotes em `Suggests` são
  testados via `requireNamespace()` no código, não exigidos no
  check.
- Matriz inclui `oldrel-1` (segundo R mais recente menos um) porque
  CRAN exige suporte aos dois últimos lançamentos.

### 9.3 Cobertura via Codecov

```yaml
name: test-coverage

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test-coverage:
    runs-on: ubuntu-latest
    env:
      GITHUB_PAT: ${{ secrets.GITHUB_TOKEN }}

    steps:
      - uses: actions/checkout@v4

      - uses: r-lib/actions/setup-r@v2
        with:
          use-public-rspm: true

      - uses: r-lib/actions/setup-r-dependencies@v2
        with:
          extra-packages: any::covr
          needs: coverage

      - name: Test coverage
        run: |
          cov <- covr::package_coverage(
            quiet = FALSE,
            clean = FALSE,
            install_path = file.path(normalizePath(Sys.getenv("RUNNER_TEMP"), winslash = "/"), "package")
          )
          covr::to_cobertura(cov)
        shell: Rscript {0}

      - uses: codecov/codecov-action@v4
        with:
          fail_ci_if_error: true
          files: ./cobertura.xml
          token: ${{ secrets.CODECOV_TOKEN }}

      - name: Show testthat output
        if: always()
        run: |
          find '${{ runner.temp }}/package' -name 'testthat.Rout*' -exec cat '{}' \; || true
        shell: bash

      - name: Upload test results
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: coverage-test-failures
          path: ${{ runner.temp }}/package
```

Arquivo `codecov.yml` na raiz:

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

comment:
  layout: "reach, diff, flags, files"
  behavior: default
  require_changes: true

ignore:
  - "R/utils/cli_helpers.R"   # banner helpers, no logic
  - "tests/"
  - "vignettes/"
  - "inst/etl/"               # ETL scripts run only in dedicated workflow
  - "inst/scripts/"           # maintenance scripts, run manually
```

### 9.4 Lint e style

```yaml
name: lint

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint:
    runs-on: ubuntu-latest
    env:
      GITHUB_PAT: ${{ secrets.GITHUB_TOKEN }}

    steps:
      - uses: actions/checkout@v4

      - uses: r-lib/actions/setup-r@v2

      - uses: r-lib/actions/setup-r-dependencies@v2
        with:
          extra-packages: |
            any::lintr
            any::styler
          needs: lint

      - name: Lint
        run: lintr::lint_package()
        shell: Rscript {0}
        env:
          LINTR_ERROR_ON_LINT: true

      - name: Style check
        run: |
          unstyled <- styler::style_pkg(dry = "on")
          n_changed <- sum(unstyled$changed, na.rm = TRUE)
          if (n_changed > 0) {
            cat("Files needing styling:\n")
            print(unstyled[unstyled$changed, ])
            stop("Run styler::style_pkg() locally and commit the changes.")
          }
        shell: Rscript {0}
```

Arquivo `.lintr` na raiz:

```r
linters: linters_with_defaults(
  line_length_linter(80L),
  object_name_linter(styles = c("snake_case")),
  cyclocomp_linter(complexity_limit = 20L),
  object_usage_linter = NULL,  # noisy with .data and rlang
  commented_code_linter = NULL # we keep TODO comments
)
exclusions: list(
  "inst/etl/",
  "tests/testthat/fixtures/",
  "data-raw/"
)
encoding: "UTF-8"
```

### 9.5 pkgdown

```yaml
name: pkgdown

on:
  push:
    branches: [main]
    tags: ['v*']
  workflow_dispatch:

jobs:
  pkgdown:
    runs-on: ubuntu-latest
    env:
      GITHUB_PAT: ${{ secrets.GITHUB_TOKEN }}
    permissions:
      contents: write

    steps:
      - uses: actions/checkout@v4

      - uses: r-lib/actions/setup-pandoc@v2

      - uses: r-lib/actions/setup-r@v2
        with:
          use-public-rspm: true

      - uses: r-lib/actions/setup-r-dependencies@v2
        with:
          extra-packages: any::pkgdown
          needs: website

      - name: Build site
        run: pkgdown::build_site_github_pages(new_process = FALSE, install = FALSE)
        shell: Rscript {0}

      - name: Deploy to GitHub Pages
        uses: JamesIves/github-pages-deploy-action@v4
        with:
          clean: false
          branch: gh-pages
          folder: docs
```

O `_pkgdown.yml` (detalhe na §10) define a estrutura do site,
incluindo grupo `@family fetchers` na barra lateral.

### 9.6 Integration (rede real)

Workflow separado, weekly, manual sob demanda:

```yaml
name: integration

on:
  schedule:
    - cron: '0 8 * * 1'  # Mondays 08:00 UTC
  workflow_dispatch:

jobs:
  integration:
    runs-on: ubuntu-latest
    env:
      GITHUB_PAT: ${{ secrets.GITHUB_TOKEN }}
      CVMDATA_RUN_INTEGRATION: "true"

    steps:
      - uses: actions/checkout@v4
      - uses: r-lib/actions/setup-r@v2
      - uses: r-lib/actions/setup-r-dependencies@v2
        with:
          extra-packages: local::.
          needs: check

      - name: Run integration tests
        run: |
          options(crayon.enabled = FALSE)
          testthat::test_dir(
            "tests/testthat",
            filter = "integration",
            reporter = "summary",
            stop_on_failure = TRUE
          )
        shell: Rscript {0}

      - name: Notify on failure
        if: failure()
        uses: dawidd6/action-send-mail@v3
        with:
          server_address: smtp.sendgrid.net
          server_port: 587
          username: apikey
          password: ${{ secrets.SENDGRID_KEY }}
          subject: '[cvmdata] integration tests failed'
          to: ${{ secrets.MAINTAINER_EMAIL }}
          from: cvmdata-ci
          body: 'Integration run failed. See ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}'
```

### 9.7 Branching e fluxo de release

**Modelo**: trunk-based com PR review.

- `main` é sempre verde (R-CMD-check passa em todos os OS).
- Features em branches curtos (`feat/<short>`) com PR.
- Hotfixes em `hotfix/<issue-number>` ramificados de `main`.
- Não usamos branches `develop` / `release/*` (Gitflow). O custo é
  desproporcional para um pacote com um único mantenedor inicial.

**Versionamento**: SemVer com convenção R adicional. Durante
desenvolvimento, `0.0.0.9001`, `0.0.0.9002`, etc. (sufixo
`.9000+`). Releases tagueados (`v0.1.0`, `v0.2.0`).

**Release checklist** (em `.github/RELEASE_CHECKLIST.md`):

1. `devtools::check(remote = TRUE, manual = TRUE)` local limpo.
2. `R-CMD-check` no GitHub Actions verde em todos os 5 jobs da
   matriz.
3. `revdepcheck::revdep_check()` (vazio em v0.1, mas o passo entra
   no checklist).
4. Atualizar `NEWS.md` com seção `# cvmdata 0.X.0` no topo.
5. `usethis::use_version("minor")` bump.
6. `pkgdown::build_site()` local + revisão visual.
7. Tag `git tag v0.X.0` e push.
8. `devtools::submit_cran()` (a partir de v0.1.0 estável).

### 9.8 codecov.yml (consolidado)

Já listado em §9.3.

### 9.9 Segredos e variáveis

GitHub repo secrets necessários:

- `CODECOV_TOKEN` — upload de cobertura.
- `MAINTAINER_EMAIL` — destinatário de notificações de falha do ETL
  e integration.
- `SENDGRID_KEY` — credencial SMTP (alternativa: GitHub Issues
  automáticas).

Nenhum segredo é necessário para acessar CVM ou mirror — ambos são
públicos.

### 9.10 Observações operacionais

- **Tempo de execução do R-CMD-check completo**: estimativa 5-8
  minutos por job, ~30-40 minutos para a matriz completa. Aceitável.
- **Custo GitHub Actions**: dentro do tier gratuito de projeto
  público.
- **Reprodutibilidade**: `r-lib/actions/setup-r-dependencies@v2`
  usa `pak` com lockfile implícito; pinning manual via
  `renv` não é necessário no pacote (o usuário final é quem decide).

---

## 10. Documentação

### 10.1 Princípios

A documentação do `cvmdata` segue três princípios:

1. **Inglês canônico, português complementar.** Tudo que vai ao
   CRAN — `DESCRIPTION`, `NEWS.md`, roxygen, vignettes oficiais — é
   em inglês. Vignettes em português brasileiro existem como
   complemento, hospedadas no site `pkgdown` mas não embarcadas no
   tarball (declaradas como `vignette: false` ou colocadas em
   `vignettes/articles/`, que `pkgdown` reconhece como "articles"
   apenas-web).
2. **Documentação como interface pública.** Todo símbolo exportado
   tem entrada `?` completa com `@param`, `@return`, `@examples`,
   `@family`, `@seealso`. A documentação é parte do contrato — quebras
   exigem entrada em `NEWS.md`.
3. **Exemplos executáveis quando possível.** A política CRAN exige
   exemplos rápidos (≤5s). Como nossas funções tocam rede, usamos
   o padrão `if (interactive()) { ... }` para exemplos longos e
   `\dontrun{}` para exemplos que dependem de dados grandes
   downloadáveis. Para exemplos verdadeiramente rápidos, embarcamos
   um pequeno dataset `cvmdata_demo` (ver §10.7) que permite
   demonstrar a API sem rede.

### 10.2 README e NEWS

`README.md` é gerado a partir de `README.Rmd` via
`devtools::build_readme()`. Estrutura:

1. Badges: R-CMD-check, codecov, CRAN status, lifecycle (experimental
   em v0.1, stable a partir de v1.0), pkgdown.
2. Parágrafo introdutório (1-2 linhas, EN).
3. Bloco de instalação (`install.packages("cvmdata")` quando estável;
   `pak::pak("user/cvmdata")` durante desenvolvimento).
4. "Quick start" com 1 exemplo executável (usando demo data).
5. Seção "What's covered" com tabela datasets × status.
6. Seção "Data provenance" mencionando CVM + mirror.
7. Link para vignettes e site pkgdown.
8. Citação (`citation("cvmdata")`).
9. Code of conduct, contributing, license.

`NEWS.md` segue o estilo `### Breaking changes`, `### New features`,
`### Bug fixes`, `### Documentation`, `### Internal`. Toda mudança
visível ao usuário entra em uma das três primeiras seções. Mudanças
de schema interno que afetem output entram como `Breaking changes`
mesmo entre versões 0.x.

### 10.3 Roxygen2

Convenções aplicadas a todas as funções exportadas:

```r
#' Fetch ITR (quarterly) statements from CVM
#'
#' @description
#' Downloads, parses, and tidies ITR (Informações Trimestrais) data
#' from CVM open data portal or from the bundled GitHub Releases
#' mirror. Returns a tidy tibble with one row per
#' company × period × account combination.
#'
#' @param table A character scalar identifying the ITR table.
#'   See `?cvmdata::itr_tables` for the full list.
#' @param years Integer vector of reference years (e.g., 2023:2024).
#'   Defaults to the most recent year.
#' @param entities Optional character vector of entity identifiers
#'   to filter on. Accepts CNPJs (with or without punctuation),
#'   CVM codes, or B3 tickers. See `?cvmdata::normalize_entity_id`.
#' @param source One of `"auto"`, `"cvm"`, `"mirror"`. Defaults to
#'   `"auto"`, which prefers mirror for completed quarters and CVM
#'   for the current quarter.
#' @param on_error One of `"abort"`, `"warn"`, `"silent"`. Controls
#'   behaviour when a year's archive is missing.
#' @param validate Logical. Run pointblank runtime checks before
#'   returning. Defaults to `getOption("cvmdata.validate_runtime",
#'   FALSE)`.
#'
#' @return A `tibble` with `cvmdata_metadata` attribute. Columns
#'   depend on `table`; see `vignette("itr-dfp", package =
#'   "cvmdata")` for the full schema reference.
#'
#' @family fetchers
#' @seealso
#'   [fetch_dfp()] for annual statements,
#'   [fetch_cad()] for the registry,
#'   [fetch_fre()] for the reference form.
#'
#' @examples
#' \dontrun{
#' # Most recent quarter, balance sheet (assets), consolidated
#' bpa <- fetch_itr(table = "bpa_con", years = 2024)
#'
#' # Multiple companies, multiple years, individual statements
#' fetch_itr(
#'   table    = "dre_ind",
#'   years    = 2022:2024,
#'   entities = c("PETR4", "VALE3", "ITUB4")
#' )
#' }
#'
#' # Quick demo using bundled data (no network)
#' if (interactive()) {
#'   demo <- cvmdata::cvmdata_demo$itr_bpa_con_2023
#'   dplyr::glimpse(demo)
#' }
#'
#' @export
fetch_itr <- function(...) { ... }
```

Diretrizes específicas:

- `@family fetchers` agrupa todas as funções públicas de fetch,
  produzindo seção "See also" automaticamente no pkgdown.
- `@param` sempre indica tipo esperado e default.
- `@return` sempre menciona atributos.
- `@examples` evita rede direta; usa `\dontrun{}` ou demo data.

### 10.4 pkgdown site

Configuração em `_pkgdown.yml`:

```yaml
url: https://<user>.github.io/cvmdata/
template:
  bootstrap: 5
  light-switch: true
  bslib:
    primary: "#1f5582"   # azul institucional sóbrio

navbar:
  structure:
    left:  [intro, reference, articles, news]
    right: [search, github]
  components:
    articles:
      text: Articles
      menu:
        - text: "User guides"
        - text: "Working with ITR/DFP"
          href: articles/itr-dfp.html
        - text: "Working with FRE"
          href: articles/fre.html
        - text: "Cache and mirror"
          href: articles/cache-and-mirror.html
        - text: "Roadmap"
          href: articles/roadmap.html
        - text: ---
        - text: "Guias em português"
        - text: "Introdução (pt-BR)"
          href: articles/pt-BR-introducao.html
        - text: "ITR/DFP (pt-BR)"
          href: articles/pt-BR-itr-dfp.html
        - text: "FRE (pt-BR)"
          href: articles/pt-BR-fre.html

reference:
- title: "Fetchers (public API)"
  desc: "Functions to download and tidy CVM data."
  contents:
  - has_concept("fetchers")
- title: "Schema helpers"
  contents:
  - itr_tables
  - dfp_tables
  - fre_tables
  - cvm_dataset_index
- title: "Utilities"
  contents:
  - normalize_entity_id
  - cvmdata_cache_info
  - cvmdata_cache_clear
- title: "Demo data"
  contents:
  - cvmdata_demo

articles:
- title: User guides
  contents:
  - itr-dfp
  - fre
  - cache-and-mirror
  - roadmap
- title: Guias em português
  contents:
  - pt-BR-introducao
  - pt-BR-itr-dfp
  - pt-BR-fre
```

### 10.5 Vignettes em inglês (canônicas, embarcadas)

Em `vignettes/`, build pelo CRAN:

1. **`cvmdata.Rmd`** ("Introduction to cvmdata", ~3-5 min de
   leitura). Conceitos: tidy CVM data, mirror, cache. Exemplo
   ponta-a-ponta com `cvmdata_demo`.
2. **`itr-dfp.Rmd`** (~10 min). Schema completo das 19 tabelas (BPA,
   BPP, DRE, DRA, DFC, DVA, DMPL, composição de capital, parecer,
   header), em ambas as flavors (consolidado/individual). Como
   ler uma DRE da Petrobras em 5 linhas. Diferenças entre
   tabelas ITR (trimestrais, sempre acumuladas no tri) e DFP
   (anuais, fechamento de ano).
3. **`fre.Rmd`** (~12 min). As 36 tabelas FRE, categorizadas
   (governança, capital, remuneração, fatores de risco, etc.).
   Casos de uso ilustrativos: composição de diretoria por gênero
   e raça-cor (Resolução CVM 80 + tabela `directors_gender`,
   `directors_race`); remuneração total por órgão
   (`compensation_total_by_organ`).
4. **`cache-and-mirror.Rmd`** (~7 min). Como o cache funciona,
   onde fica, como limpar, como auditar; quando o pacote usa
   CVM direto vs mirror; tabela de compat
   `mirror_compat.json`; comportamento offline.
5. **`roadmap.Rmd`** (~3 min). Quais datasets virão em quais
   versões, com link para a issue tracker.

Em `vignettes/articles/` (apenas-web, não embarcadas):

6. **`pt-BR-introducao.Rmd`** — equivalente do `cvmdata.Rmd` em
   português.
7. **`pt-BR-itr-dfp.Rmd`** — equivalente em português.
8. **`pt-BR-fre.Rmd`** — equivalente em português.

Decisão de design: o usuário brasileiro tem acesso integral à
documentação em sua língua via site, mas o tarball CRAN não carrega
duplicatas (mantendo `R CMD check --as-cran` enxuto).

### 10.6 Documentação interna (não exportada)

Função interna sem `@export` ainda recebe roxygen quando:

- É reutilizada em mais de um arquivo R.
- Tem lógica não-trivial.

Esses arquivos `.Rd` vão para `man/internal/` via opção
`@keywords internal`, não aparecem no índice mas existem no help.
Política equivalente à do tidyverse.

### 10.7 Demo data

`data/cvmdata_demo.rda` contém uma lista nomeada com:

- `cvmdata_demo$itr_bpa_con_2023` — ~50 linhas, 5 empresas.
- `cvmdata_demo$dfp_dre_con_2023` — ~50 linhas, 5 empresas.
- `cvmdata_demo$fre_directors_gender_2024` — ~30 linhas.
- `cvmdata_demo$cad_subset` — ~20 linhas.

Documentado em `R/data-cvmdata_demo.R` via roxygen com `@docType
data`. Tamanho total compactado: ~80 KB. Permite exemplos
executáveis sem rede em todos os contextos (R CMD check, vignettes,
README).

### 10.8 Citação

`inst/CITATION` permite `citation("cvmdata")`:

```r
citHeader("To cite the cvmdata package:")

bibentry(
  bibtype  = "Manual",
  title    = "cvmdata: Tidy Access to Brazilian CVM Open Data",
  author   = person("Sidney", "<Last>"),
  year     = sub("-.*", "", meta$Date),
  note     = sprintf("R package version %s", meta$Version),
  url      = "https://CRAN.R-project.org/package=cvmdata"
)
```

### 10.9 Code of conduct e contributing

Arquivos padrão `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1) e
`CONTRIBUTING.md` (com seções: ambiente de desenvolvimento,
checklist de PR, política de schemas YAML, como atualizar
fixtures, política de issue triage). Templates de issue e PR em
`.github/ISSUE_TEMPLATE/` e `.github/PULL_REQUEST_TEMPLATE.md`.

---

## 11. Roadmap

### 11.1 Filosofia

O roadmap é organizado em **fases**, não em datas. Cada fase é
auto-contida: tem um conjunto definido de datasets, uma API
incremental, testes próprios e (em fases marcadas) um release no
CRAN. Datas são estimativas em horas-pessoa de trabalho focado, não
em calendário absoluto.

A v0.1 corresponde às fases A-F e representa cerca de 50-60% do
esforço total do pacote completo — porque é onde a arquitetura
multi-classe é construída pela primeira vez. As fases posteriores
adicionam dispatch entries, schemas e transformações, mas o
esqueleto está pronto.

### 11.2 Fases

#### Fase A — Esqueleto (pré-v0.1)

- Estrutura de diretórios proposta na §2.
- `DESCRIPTION`, `NAMESPACE`, `LICENSE`.
- Configuração de CI/CD (R-CMD-check, coverage, lint).
- README e site pkgdown vazios mas válidos.
- Decisões da Rodada 1 transcritas para `inst/architecture/`.

Saída: repo público, primeiro PR mergeado, CI verde.
Esforço: 8-12h.

#### Fase B — Cache + source CVM (pré-v0.1)

- `R/cache/` completo: paths, ETag, TTL, eviction LRU.
- `R/source/cvm/` para ZIP/CSV puros, sem schema.
- Função interna `download_cvm_archive(dataset, year)` que retorna
  caminho local.
- Testes: cache paths, ETag flow, mock HTTP.

Saída: capacidade de baixar e cachear qualquer arquivo CVM.
Esforço: 16-20h.

#### Fase C — Dispatch + schemas (pré-v0.1)

- `R/dispatch/` resolvendo (dataset, table, entity) → handler.
- `R/schemas/companies/` com YAMLs para CAD e ITR.
- Parser YAML em `R/schemas/load.R`.
- `R/transform/companies/` aplicando rename + cast.

Saída: arquitetura multi-classe funcionando para o subset CAD+ITR.
Esforço: 24-32h.

#### Fase D — CAD + ITR ponta-a-ponta (pré-v0.1)

- `fetch_cad()` e `fetch_itr()` exportadas e funcionais.
- Aliases tipados.
- Vignette `itr-dfp.Rmd` parcial.
- Cobertura ≥85% nos módulos tocados.

Saída: usuário pode rodar `fetch_itr(table = "bpa_con", years =
2024)` e receber tibble tidy.
Esforço: 20-28h.

#### Fase E — DFP + FRE (pré-v0.1)

- Replicar schemas DFP (paralelo direto a ITR).
- Schemas FRE para todas as 36 tabelas — fase mais trabalhosa do
  v0.1.
- `fetch_dfp()` e `fetch_fre()` exportadas.
- Vignettes `itr-dfp.Rmd` e `fre.Rmd` completas.

Saída: cobertura completa da classe "companhias abertas, parte 1".
Esforço: 40-60h (FRE domina pelo número de tabelas).

#### Fase F — Pipeline ETL + mirror (pré-v0.1)

- Workflow `etl-mirror.yaml` (já descrito na §6) funcional.
- Scripts `inst/etl/01-07` completos.
- Primeiro snapshot publicado em GitHub Releases.
- `source_mirror_fetch()` integrado ao dispatch.
- `mirror_compat.json` versionado.

Saída: pacote pode operar contra mirror, ETL automático rodando
semanalmente.
Esforço: 24-32h.

#### Marco: release v0.1.0

Após validação de:

- R-CMD-check verde nos 5 jobs.
- Cobertura ≥90%.
- `revdepcheck` limpo.
- Documentação revisada (READ MORE, peer-eyes sobre vignettes).
- `devtools::check_win_devel()` e `check_mac_release()` limpos.
- Pelo menos 30 dias de ETL rodando estável.

Submissão a CRAN.

#### Fase G — v0.2.0: FCA, FC, IPE

- **FCA** (Formulário Cadastral) — variante anual do CAD com
  informações estendidas.
- **FC** (Formulário Cadastral simplificado) — versão consolidada
  no portal CVM.
- **IPE** (Informações Periódicas e Eventuais) — fatos relevantes,
  comunicados ao mercado, atas de assembleia. Dataset rico para
  pesquisas em governança e eventos corporativos.

Esforço estimado: 30-40h.

#### Fase H — v0.3.0: Companhias estrangeiras e incentivadas

- Replicação dos schemas ITR/DFP/FRE para a classe
  "companhias_estrangeiras" e "companhias_incentivadas".
- Pequenas diferenças de schema documentadas.
- Dispatch reconhece a classe.

Esforço estimado: 20-30h.

#### Fase I — v0.4.0: Primeira classe de fundos

Decisão pendente entre:

- **Opção I.a — ICVM 555 (fundos de investimento regulamentados)**:
  universo grande (~20 mil fundos), informe diário, composição
  da carteira, taxa de administração, captação/resgate. Caso de
  uso mais comum entre pesquisadores em economia/finanças
  acadêmica.
- **Opção I.b — FII (fundos imobiliários)**: universo menor (~400
  fundos), informe mensal e trimestral, distribuição de
  rendimentos. Caso de uso mais comum entre investidores pessoa
  física.

Recomendação: **I.a primeiro**. Motivos: cobertura mais ampla,
demanda acadêmica maior, schema mais estável historicamente. FII
fica para v0.5.

Esforço estimado: 50-70h (primeira classe nova exige expansão do
dispatch e da camada de cache para volumes maiores).

#### Fase J — v0.5.0: FII

- Esquema FII (informe mensal/trimestral, distribuições).
- Esforço: 30-40h.

#### Fase K — v0.6.0: FIDC e fundos estruturados

- FIDC, FIP, FIA estruturados.
- Esforço: 40-50h.

#### Fase L — v1.0.0: Estabilização

- Auditoria de API: tudo que era "experimental" promovido a
  "stable" ou removido.
- Vignettes consolidadas.
- Performance review: benchmarks documentados em
  `inst/benchmarks/`.
- Paper de software (JOSS ou Revista de Estatística aplicada à
  Pesquisa em Saúde, Economia ou Finanças).

Esforço: 40-60h.

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

A v0.1 absorve ~40-50% do esforço total justamente por construir a
infraestrutura. Adicionar uma nova classe de dataset após v0.1 é
estimado em 20-50h.

### 11.4 Critério de priorização

Decisões sobre o que entra em qual versão dependem de:

1. Estabilidade do schema CVM (datasets com mudanças frequentes
   ficam para versões mais maduras).
2. Demanda em pesquisa acadêmica e relatórios DataSenado.
3. Existência de pacote concorrente cobrindo bem o mesmo dataset
   (caso exista cobertura adequada, despriorizar).
4. Esforço de implementação proporcional ao retorno em
   abrangência.

---

## 12. Riscos, Premissas e Pendências

### 12.1 Premissas operacionais

1. **A CVM mantém o portal `dados.cvm.gov.br` com estabilidade de
   estrutura.** Mudanças incrementais de schema são esperadas;
   reorganização disruptiva do portal não é. Premissa baseada no
   histórico de 2012-2026.
2. **GitHub Releases continua gratuito para repositórios públicos
   com artifacts de até 2 GB cada.** Atual snapshot completo do
   universo CVM cabe em ~500 MB Parquet comprimido. Margem de 4×.
3. **CRAN aceita pacotes que baixam dados sob demanda quando
   respeitam o policy de cache em `tools::R_user_dir()` e
   declaram a fonte.** Precedentes: `microdatasus`, `GetDFPData2`,
   `rfb`, `tidycensus`. O `cvmdata` segue padrão equivalente.
4. **O R-CMD-check em rede tem variabilidade aceitável.** Os
   testes embarcados no CRAN não dependem de rede; testes de
   integração ficam no workflow dedicado.
5. **Sidney é o mantenedor único na v0.1.** Premissa de
   bus-factor 1. Mitigação: documentação interna abundante
   (`inst/architecture/`), CI estrito, e separação clara entre
   código do pacote e pipeline ETL.

### 12.2 Riscos identificados

| ID | Risco | Severidade | Probabilidade | Mitigação |
|:-:|---|:-:|:-:|---|
| R-01 | CVM reestrutura portal e quebra URLs | Alta | Média | `R/source/cvm/url_builders.R` isola a lógica de URL em ~3 funções; mudança fica localizada. Mirror fornece fallback. |
| R-02 | Schema de uma tabela ITR/DFP/FRE muda silenciosamente | Alta | Alta | Validation gate no ETL bloqueia publicação; alerta por e-mail; vamos saber antes do usuário. |
| R-03 | GitHub muda política de Releases (preço/tamanho) | Média | Baixa | Mirror é adiantado; pacote pode operar contra CVM direto. Plano B: mover mirror para Cloudflare R2. |
| R-04 | CRAN rejeita pacote por tamanho ou política de rede | Média | Baixa | Pré-submissão via `usethis::use_release_issue()` e revisão local com flags estritas. Demo data <100 KB; sem rede em exemplos automáticos. |
| R-05 | Volume de FRE explode (novas seções por norma CVM) | Média | Média | Schemas YAML são extensíveis; adicionar tabela = adicionar arquivo. Sem refactor estrutural. |
| R-06 | Conflito com pacote concorrente (e.g., GetDFPData2 ressurge) | Baixa | Média | Posicionamento claro: `cvmdata` é multi-classe; concorrente foca em ITR/DFP. Coexistência aceitável. |
| R-07 | pointblank perde manutenção | Baixa | Baixa | Camada de validação é isolada em `R/validate/`; troca por outra biblioteca (e.g., validate) viável em ~1-2 dias. |
| R-08 | `tools::R_user_dir()` deprecation ou mudança de path | Baixa | Muito baixa | API estável desde R 4.0. Reativo. |
| R-09 | Encoding ISO-8859-1 dos CSVs muda para UTF-8 sem aviso | Média | Baixa | Detecção automática via `readr::guess_encoding()` antes do parse; código já robusto. |
| R-10 | DuckDB Parquet incompatibilidade entre versões | Baixa | Baixa | Pinning de versão DuckDB no workflow ETL; teste de leitura em R-CMD-check. |

### 12.3 Pendências para Rodada 2.5 (naming)

Decisões adiadas para a próxima rodada de planejamento:

1. **Nomes finais das tabelas FRE em snake_case inglês.** A §4.2.4
   propôs uma categorização A-J mas os nomes individuais
   (`directors_gender`, `compensation_total_by_organ`, etc.)
   precisam de revisão coletiva. Algumas tabelas têm tradução
   ambígua do português; e.g., "parte_relacionada" pode ser
   `related_party` (literal) ou `related_party_transaction`
   (mais informativo). Decisão Rodada 2.5.
2. **Nome da coluna padronizada de período.** Atualmente
   propomos `period_end_date` para DFP e ITR. Alternativas:
   `reference_date`, `as_of_date`, `period`. Decisão Rodada 2.5.
3. **Convenção de naming para colunas de moeda.** CVM usa centavos
   inteiros em algumas tabelas e reais decimais em outras. O
   pacote padroniza para reais decimais (float64) com sufixo
   `_brl`, mas casos como `_brl_thousands` (DRE em mil) precisam
   ser definidos. Decisão Rodada 2.5.
4. **Política de naming para abreviações.** `cnpj`, `cvm_code`,
   `b3_ticker` são óbvios. Mas `dpc` (depreciação), `dva` (valor
   adicionado), `dmpl` (mutações do patrimônio líquido) — deixar
   como sigla CVM ou expandir? Decisão Rodada 2.5.

### 12.4 Pendências para Rodada 3 (implementação)

1. **Checklist passo-a-passo de implementação** das fases A-F com
   ordem de execução, dependências entre tarefas, critérios de
   "done" por tarefa.
2. **Lista de issues GitHub iniciais** a serem abertas no momento
   da criação do repositório (templating).
3. **Definição final dos YAMLs de schema** para CAD e ITR (a partir
   da empírica capturada nesta rodada).

### 12.5 Pendências menores

1. **Licença.** Proposta MIT (default da comunidade R, simples,
   compatível com CRAN). Alternativa: GPL-3 (alinhado com R-base).
   Recomendação: MIT, salvo objeção do mantenedor.
2. **Nome do mantenedor em `DESCRIPTION`**: Sidney completo +
   ORCID. Confirmar com o usuário.
3. **E-mail de contato CRAN**: precisa ser estável; conta
   pessoal preferível a institucional para evitar mudanças se
   o vínculo institucional mudar.
4. **Logo do pacote (hexsticker)**: opcional, não-bloqueante.
   Pode ser feito em qualquer momento via `hexSticker::sticker()`.

### 12.6 O que este plano deliberadamente não decide

- **Estratégia de comunicação com a CVM** (e.g., reportar bugs no
  portal, sugerir documentação adicional). Decisão depende de
  interesse do mantenedor e fica fora do escopo arquitetural.
- **Estratégia de publicação acadêmica do pacote.** JOSS, Revista
  de Saúde Pública, ou similar fica para v1.0 (Fase L).
- **Cobertura de dados pré-2010.** A CVM disponibiliza
  arquivos legacy em formato distinto; suporte fica fora do v0.1.
  Decisão de incluir em v0.2+ depende de demanda.

---

## Encerramento

Este documento é a referência arquitetural travada da Rodada 2.
Mudanças estruturais (e.g., trocar o padrão de organização de
diretórios, alterar a assinatura de `fetch_cvm()`, mudar o modelo
de cache) exigem retorno explícito ao planejamento; mudanças
incrementais (novos schemas, novos checks de validação) seguem
o fluxo normal de PR.

A próxima rodada (2.5) trata exclusivamente do naming
unificado em snake_case inglês para todas as colunas das 19
tabelas ITR, 19 DFP, 36 FRE e do CAD. Em paralelo, a Rodada 3
produz o checklist de implementação das fases A-F.
