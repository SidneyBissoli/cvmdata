# `cvmdata` Rodada 2.5 — Naming Unificado

> Documento canônico de naming do pacote R `cvmdata`. Consolida 26
> decisões fechadas em sessão iterativa, mais a régua geral de idioma
> que as governa.
>
> **Idioma deste documento**: português brasileiro.
> **Status**: travado. Não reabrir sem evidência substancial nova.
> **Substitui em parte**: `cvmdata_rodada2_plano_arquitetural.md`
> (decisões de naming). Em caso de conflito entre os dois documentos,
> prevalece este.
> **Pré-requisitos**: `cvmdata_rodada1_fechamento.md` (escopo macro) e
> `cvmdata_rodada2_plano_arquitetural.md` (plano técnico).

> ### Refinamentos incrementais — Rodada 2.6 (2026-05-18)
>
> Os ajustes abaixo derivaram de verificação empírica direta dos arquivos
> do Portal de Dados Abertos CVM em 2026-05-18, na subsessão Rodada 2.6
> (schemas). São **incrementais**: não reabrem nenhuma das 26 decisões da
> Rodada 2.5, apenas adicionam precisão onde a redação original
> generalizava sem evidência.
>
> - §3 (Colunas-chave universais): adicionada §3.0 com caveat empírico
>   sobre divergência de convenção de naming entre CAD/ITR/DFP/FRE-header
>   e FRE-detail. Decisão: preservação estrita (sem renomeação).
> - §7.2 (Estrutura mínima do YAML): expandida com novos campos
>   `cvm_archive_url_pattern`, `cvm_file_url_pattern`,
>   `temporal_partitioning`, `first_year`, `expected_field_count`. A
>   notação `archive.zip#entry.txt` em `cvm_dictionary_url` é parte
>   normativa.
> - §7.3 (Domínio de `action`): removido `convert_to_date`. Conversão
>   `date` é automática a partir do `Tipo Dados: date` declarado no META
>   da CVM; não deve ser declarada em `transformations:`.
> - §11 (Pendências empíricas): itens resolvidos na Rodada 2.6 marcados
>   como `[RESOLVIDO 2.6]`; pendências remanescentes refinadas.

---

## Sumário

- [0. Régua geral](#0-régua-geral)
- [1. Funções públicas](#1-funções-públicas)
- [2. Argumentos canônicos](#2-argumentos-canônicos)
- [3. Colunas-chave universais](#3-colunas-chave-universais)
- [4. Nomes de tabelas](#4-nomes-de-tabelas)
- [5. Atributos do tibble retornado](#5-atributos-do-tibble-retornado)
- [6. Mensagens, erros, verbosidade](#6-mensagens-erros-verbosidade)
- [7. YAMLs de schema interno](#7-yamls-de-schema-interno)
- [8. Funções utilitárias](#8-funções-utilitárias)
- [9. Transformações que alteram a forma do tibble](#9-transformações-que-alteram-a-forma-do-tibble)
- [10. Histórico das 26 decisões](#10-histórico-das-26-decisões)
- [11. Pendências empíricas para Rodada 3](#11-pendências-empíricas-para-rodada-3)

---

## 0. Régua geral

### 0.1 Princípio reitor

> **Se vem da CVM, fica como na CVM** (apenas com normalização tipográfica
> para snake_case minúsculo quando o original está em SCREAMING_SNAKE_CASE).
> **Se não vem da CVM, é decisão do pacote.**

### 0.2 Distribuição de idiomas

| Categoria | Idioma | Exemplos |
|---|---|---|
| Nomes de função (públicas e internas) | **Inglês** | `cvm_fetch`, `cvm_dictionary`, `cad_fetch`, `cnpj_clean` |
| Nomes de argumento de função | **Inglês** | `dataset`, `table`, `companies`, `years`, `source`, `on_error`, `validate` |
| Atributos do tibble retornado | **Inglês** | `source`, `fetched_at`, `dataset`, `table`, `package_version` |
| Classes de condição (erros) | **Inglês** | `cvmdata_error`, `cvmdata_error_input`, `cvmdata_error_http` |
| Options e env vars do pacote | **Inglês** | `cvmdata.verbosity`, `CVMDATA_VERBOSITY` |
| Nomes de arquivo e pasta no projeto | **Inglês** | `R/companies/`, `inst/extdata/schemas/` |
| Comentários em código | **Inglês** | — |
| README.md, NEWS.md, DESCRIPTION, roxygen | **Inglês** | — |
| Mensagens de erro/warning | **Inglês** | (via `cli::cli_*` ou `rlang::*`) |
| **Nomes de tabelas** do pacote | **Português** (snake_case) | `bpa_con`, `dre_ind`, `composicao_capital`, `parecer`, `orgao_administracao`, `evento_societario`, `assembleia_geral`, `remuneracao_*` |
| **Nomes de colunas** nos tibbles retornados por `cvm_fetch` | **Português** (snake_case, fiel à CVM) | `cnpj_cia`, `cd_cvm`, `denom_cia`, `dt_refer`, `versao`, `dt_ini_exerc`, `dt_fim_exerc`, `cd_conta`, `vl_conta` |
| Colunas-meta retornadas por funções de descoberta | **Português** (snake_case) | `conjunto_dados`, `grupo`, `descricao`, `n_tabelas`, `primeiro_ano`, `tabela`, `n_colunas`, `campo`, `tipo_dados`, `dominio`, `tamanho`, `precisao`, `scale` |
| Valores em células categóricas | **Português** (como vem da CVM) | `"Conselho de Administração"`, `"Diretoria Estatutária"`, `"ÚLTIMO"`, `"PENÚLTIMO"`, `"REAL"`, `"MIL"`, `"UNIDADE"` |
| Texto livre em colunas descritivas | **Português** (como vem da CVM) | `denom_cia`, `ds_conta`, etc. |
| README.pt-BR.md, vinhetas em PT | **Português** | `vignettes/cvmdata-pt-BR.Rmd` |
| Documentos de planejamento | **Português** | este documento |

### 0.3 Caveat sobre `dataset` (palavra técnica)

A palavra `dataset` entrou no vocabulário técnico PT da comunidade R
sem tradução natural. Em consequência:

- O **argumento** `dataset` em `cvm_fetch()`, `cvm_dictionary()` e
  `cvm_tables()` permanece em inglês.
- A **coluna** equivalente no retorno de `cvm_datasets()` chama-se
  `conjunto_dados` — em PT, fiel à nomenclatura oficial CVM no portal
  `dados.cvm.gov.br`.

O mismatch é deliberado e documentado.

### 0.4 Padrão de nomeação de função: `object_verb`

Conforme Dev Guide rOpenSci §"Function and argument naming":

> "Consider an `object_verb()` naming scheme for functions in your
> package that take a common data type or interact with a common API."

Aplicação: todas as funções públicas do pacote começam com `cvm_` ou
com o prefixo do dataset (`cad_`, `itr_`, `dfp_`, `fre_`, e futuros
`fii_`, `fidc_`, etc.).

### 0.5 Régua para argumentos de comportamento adverso

Argumentos que controlam comportamento em situações adversas usam
**três níveis paralelos** (mesma régua mental para o usuário):

- `validate = c("strict", "warn", "skip")` — default `"strict"`.
- `on_error = c("abort", "warn", "silent")` — default `"abort"`.

---

## 1. Funções públicas

### 1.1 Função genérica

```r
cvm_fetch(
  dataset,
  table,
  companies = NULL,
  years = NULL,
  source = "auto",
  on_error = "abort",
  validate = "strict",
  ...
)
```

Aceita dataset de qualquer classe (companhias na v0.1; fundos na
v0.4+). Argumentos `companies`/`years` se aplicam à classe companhias;
classes futuras podem ter outros argumentos análogos via dispatch
interno (decisão arquitetural mantida da Rodada 2).

### 1.2 Aliases tipados

#### v0.1 (companhias abertas)

| Função | Datasets | Comentário |
|---|---|---|
| `cad_fetch()` | `cad` | Cadastro de companhias abertas |
| `itr_fetch()` | `itr` | Informações trimestrais |
| `dfp_fetch()` | `dfp` | Demonstrações financeiras padronizadas |
| `fre_fetch()` | `fre` | Formulário de referência |

#### v0.2 (companhias abertas, parte 2 — antecipação de naming)

| Função | Datasets |
|---|---|
| `fca_fetch()` | `fca` — Formulário cadastral anual |
| `vlmo_fetch()` | `vlmo` — Negociação por insiders |
| `cgvn_fetch()` | `cgvn` — Código de governança |
| `ipe_fetch()` | `ipe` — Informações periódicas e eventuais |

#### v0.4+ (fundos — ilustrativo, sujeito a confirmação)

| Função | Datasets |
|---|---|
| `fi_fetch()` | Fundos de investimento ICVM 555 |
| `fii_fetch()` | Fundos de investimento imobiliário |
| `fidc_fetch()` | Fundos de investimento em direitos creditórios |
| `fie_fetch()` | Fundos estruturados |

### 1.3 Funções de descoberta

```r
cvm_datasets()              # sem argumentos; lista todos os datasets do pacote
cvm_tables(dataset)         # dataset obrigatório; lista tabelas do dataset
cvm_dictionary(dataset, table)  # ambos obrigatórios; descreve colunas da tabela
```

Comportamento quando argumentos obrigatórios são omitidos: erro
informativo via `cli::cli_abort()` indicando uso correto e função
relacionada para listagem.

### 1.4 Funções de cache

```r
cvm_cache_path()                    # retorna path atual do cache (read-only)
cvm_cache_set_path(path)            # define path (persiste em option ou env var)
cvm_cache_clear(what = "all", ...)  # limpa cache; what aceita "all", nome de dataset, ou critério temporal
cvm_cache_info()                    # retorna tibble com estado do cache
```

Path default segue `tools::R_user_dir("cvmdata", "cache")` (CRAN
policy).

### 1.5 Funções de source

```r
cvm_source_get()         # retorna source default configurado
cvm_source_set(source)   # define source default; persiste em option ou env var
```

Argumento `source` em `cvm_fetch()` continua funcionando como override
pontual da configuração global.

**Domínio fechado** de valores aceitos por `source`:

| Valor | Comportamento |
|---|---|
| `"auto"` | Tenta portal CVM; se falhar, faz fallback automático para mirror GitHub Releases |
| `"portal"` | Força portal CVM oficial; sem fallback |
| `"mirror"` | Força mirror próprio em GitHub Releases; sem tentar portal |

Validação via `rlang::arg_match()`.

### 1.6 Funções utilitárias

| Função | v0.1 | Descrição |
|---|---|---|
| `cnpj_clean(x)` | Exportada | Remove pontuação de vetor de CNPJ, retorna só dígitos (character) |
| `cnpj_format(x)` | Deferida v0.2+ | Adiciona pontuação canônica a vetor de CNPJ em dígitos |

---

## 2. Argumentos canônicos

Argumentos que aparecem em mais de uma função e devem ser **idênticos
em nome, tipo, default e semântica** em todas as funções:

| Argumento | Tipo | Default | Domínio | Funções onde aparece |
|---|---|---|---|---|
| `dataset` | chr | (obrigatório) | identificador curto do dataset (`"itr"`, `"dfp"`, `"fre"`, `"cad"`) | `cvm_fetch`, `cvm_dictionary`, `cvm_tables` |
| `table` | chr | `NULL` em `cvm_fetch`; obrigatório em `cvm_dictionary` | snake_case PT (`"bpa_con"`, etc.) | `cvm_fetch`, aliases, `cvm_dictionary` |
| `companies` | chr/int | `NULL` (todas) | CD_CVM, CNPJ, ou ticker B3 | `cvm_fetch`, `cad_fetch`, `itr_fetch`, `dfp_fetch`, `fre_fetch` |
| `years` | int | `NULL` (mais recente) | inteiros entre `first_year` do dataset e ano corrente | `itr_fetch`, `dfp_fetch`, `fre_fetch` |
| `source` | chr | `"auto"` | `"auto"`, `"portal"`, `"mirror"` | `cvm_fetch` e todos os aliases |
| `on_error` | chr | `"abort"` | `"abort"`, `"warn"`, `"silent"` | `cvm_fetch` e todos os aliases |
| `validate` | chr | `"strict"` | `"strict"`, `"warn"`, `"skip"` | `cvm_fetch` e todos os aliases |

### 2.1 Semântica de `on_error`

| Valor | Falha simples (HTTP 503 etc.) | Batch parcial (várias entidades, uma falha) |
|---|---|---|
| `"abort"` | Aborta com `cvmdata_error_http` ou equivalente | Primeira falha aborta tudo |
| `"warn"` | Warning via `rlang::warn()`/`cli::cli_warn()`; pacote tenta fallback (portal → mirror); retorna o que conseguiu | Warnings por entidade que falhou; tibble retorna com as que deram certo |
| `"silent"` | Fallback silencioso; retorna o que conseguiu | Idem `"warn"` mas sem warnings |

### 2.2 Semântica de `validate`

| Valor | Comportamento |
|---|---|
| `"strict"` | Valida schema; divergência aborta com classe `cvmdata_error_parse` |
| `"warn"` | Valida; divergência gera warning mas tibble é entregue |
| `"skip"` | Pula validação por completo |

---

## 3. Colunas-chave universais

Conjunto mínimo de colunas presentes em tibbles retornados pelo pacote
no escopo CAD + ITR + DFP + header do FRE. Nomes em PT, snake_case,
fiéis à CVM.

| Coluna | Tipo | Origem CVM | Notas |
|---|---|---|---|
| `cnpj_cia` | character | CNPJ_CIA | **Com pontuação** como vem da CVM (`"12.345.678/0001-90"`); usar `cnpj_clean()` para versão sem pontuação |
| `cd_cvm` | character | CD_CVM | Código de registro CVM. **[RESOLVIDO 2.6]** Verificado empiricamente: CAD armazena sem padding (35..28010, 2-5 dígitos); ITR armazena zero-padded a 6 dígitos (`000094`..`001023`). Inteiro perderia o padding do ITR. Mantido como character |
| `denom_cia` | character | DENOM_CIA | Denominação social/razão social |
| `dt_refer` | Date | DT_REFER | Data de submissão à CVM |
| `versao` | character | VERSAO | Revisão do arquivo. **[RESOLVIDO 2.6 parcialmente]** Verificado: em ITR/BPA 2024 ocorrem valores 1..5; CVM declara `smallint` no META. Mantido como character por princípio "identificador → character" e proteção contra mudanças futuras de formato. Pacote faz `keep_latest` por default |

### 3.0 Caveat empírico — divergência de naming em tabelas FRE-detail

Verificação Rodada 2.6 (2026-05-18) constatou que o FRE usa **duas
convenções de naming distintas** dentro do mesmo dataset:

1. **FRE-header** (`fre_cia_aberta_<ano>.csv`, uma linha por submissão):
   usa SCREAMING_SNAKE_CASE igual a CAD/ITR/DFP — `CNPJ_CIA`,
   `DT_REFER`, `DENOM_CIA`, `CD_CVM`, `VERSAO`, `CATEG_DOC`, `ID_DOC`,
   `DT_RECEB`, `LINK_DOC`.
2. **FRE-detail** (~35 tabelas, ex.:
   `fre_cia_aberta_administrador_membro_conselho_fiscal_<ano>.csv`):
   usa Title_Case_With_Underscores — `CNPJ_Companhia`,
   `Data_Referencia`, `Nome_Companhia`, `Versao`, `ID_Documento`. **Sem
   `CD_CVM`**; o identificador-documento é `ID_Documento`.

Equivalência conceitual:

| Conceito | CAD/ITR/DFP/FRE-header | FRE-detail |
|---|---|---|
| CNPJ da companhia | `cnpj_cia` | `cnpj_companhia` |
| Data de submissão | `dt_refer` | `data_referencia` |
| Razão social | `denom_cia` | `nome_companhia` |
| Versão do documento | `versao` | `versao` (igual) |
| Código CVM | `cd_cvm` | (ausente) |
| Identificador do documento | `id_doc` | `id_documento` |

**Decisão Rodada 2.6 — preservação estrita.** Tibbles FRE-detail são
retornados com `cnpj_companhia`, `data_referencia`, `nome_companhia`,
etc., fielmente à fonte. Não há renomeação para uniformizar.
Consequência operacional: joins entre FRE-detail e CAD/ITR/DFP exigem
mapeamento explícito do usuário:

```r
itr <- itr_fetch("itr", "bpa_con", years = 2024)
fre <- fre_fetch("fre", "administrador_membro_conselho_fiscal", years = 2024)

dplyr::left_join(
  itr, fre,
  by = c("cnpj_cia" = "cnpj_companhia", "dt_refer" = "data_referencia")
)
```

Uma utilitária `cvm_normalize_keys()` que uniformiza nomes via lookup
permanece **deferida para v0.2+** caso o caso de uso se justifique
empiricamente.

A frase "presentes em todo tibble retornado" da introdução desta seção
deve ser lida como "presentes em CAD + ITR + DFP + FRE-header"; FRE-detail
opera com o conjunto análogo da segunda coluna da tabela acima.

### 3.1 Colunas adicionais em tabelas contábeis (ITR/DFP)

Em tabelas das demonstrações financeiras (BPA, BPP, DRE, DRA, DFC,
DMPL, DVA, todas em variantes `_con` e `_ind`):

| Coluna | Tipo | Origem CVM | Semântica |
|---|---|---|---|
| `dt_ini_exerc` | Date | DT_INI_EXERC | Início do exercício de referência (em demonstrações de fluxo: DRE/DFC/DVA/DMPL) |
| `dt_fim_exerc` | Date | DT_FIM_EXERC | Fim do exercício de referência |
| `grupo_dfp` | character | GRUPO_DFP | Grupo da demonstração financeira; constante por tabela (redundante com nome da tabela, mas preservado) |
| `moeda` | character | MOEDA | Constante `"REAL"` em v0.1; mantida em antecipação a fundos com moeda estrangeira (v0.4+) |
| `escala_moeda` | — | ESCALA_MOEDA | **Removida** do tibble retornado; valor já foi internalizado em `vl_conta` |
| `ordem_exerc` | character | ORDEM_EXERC | `"ÚLTIMO"` ou `"PENÚLTIMO"` (preservado em PT como vem da CVM) |
| `cd_conta` | character | CD_CONTA | Código hierárquico da conta no plano de contas CVM (ex.: `"1.01.01"`) |
| `ds_conta` | character | DS_CONTA | Descrição da conta em PT |
| `vl_conta` | numeric | VL_CONTA × ESCALA_MOEDA | Valor em **unidades absolutas** (não em milhares); ver §9 |

---

## 4. Nomes de tabelas

Régua geral travada: **nomes de tabelas em PT, snake_case minúsculo**,
preservando siglas oficiais CVM e jargão jurídico-contábil brasileiro.

### 4.1 Tabelas ITR e DFP (19 tabelas espelhadas)

Ambos os datasets têm a mesma estrutura de tabelas:

| Tabela | Significado | Comentário |
|---|---|---|
| `bpa_con` | Balanço Patrimonial Ativo — consolidado | sigla CVM |
| `bpa_ind` | Balanço Patrimonial Ativo — individual | sigla CVM |
| `bpp_con` | Balanço Patrimonial Passivo — consolidado | sigla CVM |
| `bpp_ind` | Balanço Patrimonial Passivo — individual | sigla CVM |
| `dre_con` | Demonstração do Resultado do Exercício — consolidado | sigla CVM |
| `dre_ind` | Demonstração do Resultado do Exercício — individual | sigla CVM |
| `dra_con` | Demonstração do Resultado Abrangente — consolidado | sigla CVM |
| `dra_ind` | Demonstração do Resultado Abrangente — individual | sigla CVM |
| `dfc_md_con` | Demonstração do Fluxo de Caixa - Método Direto — consolidado | sigla CVM |
| `dfc_md_ind` | Demonstração do Fluxo de Caixa - Método Direto — individual | sigla CVM |
| `dfc_mi_con` | Demonstração do Fluxo de Caixa - Método Indireto — consolidado | sigla CVM |
| `dfc_mi_ind` | Demonstração do Fluxo de Caixa - Método Indireto — individual | sigla CVM |
| `dmpl_con` | Demonstração das Mutações do Patrimônio Líquido — consolidado | sigla CVM |
| `dmpl_ind` | Demonstração das Mutações do Patrimônio Líquido — individual | sigla CVM |
| `dva_con` | Demonstração do Valor Adicionado — consolidado | sigla CVM |
| `dva_ind` | Demonstração do Valor Adicionado — individual | sigla CVM |
| `composicao_capital` | Composição do capital social | tabela auxiliar |
| `parecer` | Parecer do auditor independente | tabela auxiliar |

Total: 18 tabelas espelhadas entre ITR e DFP + 1 tabela de cabeçalho a
nomear na Rodada 3 (pendência empírica — vide §11).

### 4.2 Tabelas FRE (Formulário de Referência)

As ~36 tabelas FRE estão agrupadas em categorias A-J no plano
arquitetural §4.4.2 (referência interna; **não exposta como coluna em
`cvm_tables()`**). Nomes em PT, snake_case minúsculo:

#### Categorias e exemplos de tabelas

- **Categoria A — Cabeçalho**: a confirmar nome empírico
- **Categoria B — Capital e ações**: `composicao_capital`,
  `alteracoes_capital`, `historico_dividendos`, etc.
- **Categoria C — Posição acionária**: `posicao_acionaria`, etc.
- **Categoria D — Administração e governança**: `orgao_administracao`,
  `comites`, `auditor`, etc.
- **Categoria E — ESG/diversidade (administradores)**:
  `administradores_diversidade_*`
- **Categoria F — ESG/diversidade (empregados)**:
  `empregados_diversidade_*`, `empregados_localizacao_posicao`
- **Categoria G — Remuneração**: `remuneracao_administradores`,
  `remuneracao_resumo`, `remuneracao_baseada_acoes`, etc.
- **Categoria H — Valores mobiliários**: `titular_valor_mobiliario`,
  `outro_valor_mobiliario`, etc.
- **Categoria I — Relacionamentos**: `relacao_familiar`,
  `relacao_subordinacao`
- **Categoria J — Outras informações**: `assembleia_geral`,
  `evento_societario`, etc.

**Nomes individuais finais das 36 tabelas FRE** ficam para a Rodada 3
(verificação empírica do conteúdo de cada arquivo CSV-CVM antes de
travar nome canônico). A régua a aplicar é a desta seção: PT,
snake_case, preservar siglas e jargão.

### 4.3 Outras tabelas (datasets v0.2+)

Datasets `fca`, `vlmo`, `cgvn`, `ipe` (v0.2) e `eventos_societarios`,
`cia_estrang`, `cia_incent` (v0.3) terão nomes de tabela travados em
rodadas futuras seguindo a mesma régua.

---

## 5. Atributos do tibble retornado

Tibble retornado por `cvm_fetch()` e aliases carrega **5 atributos em
inglês** com metadados de proveniência:

| Atributo | Tipo | Conteúdo |
|---|---|---|
| `source` | character | `"portal"`, `"mirror"`, ou `"cache"` |
| `fetched_at` | POSIXct | Timestamp UTC da busca |
| `dataset` | character | Identificador do dataset (`"itr"`, etc.) |
| `table` | character | Identificador da tabela |
| `package_version` | character | Versão do `cvmdata` que produziu o tibble |

**Caveat**: atributos R podem ser perdidos em algumas operações dplyr
(`filter` preserva; `bind_rows` dropa). Documentar em vinheta.

---

## 6. Mensagens, erros, verbosidade

### 6.1 Hierarquia de classes de condição

Todas em inglês, snake_case, conforme `rlang::abort(class = c(...))`:

```
cvmdata_error                  (pai genérico para captura universal)
├── cvmdata_error_input        (argumento inválido do usuário)
├── cvmdata_error_http         (falha de rede ou HTTP)
├── cvmdata_error_parse        (falha ao ler/parsear arquivo ou validação de schema)
└── cvmdata_error_internal     (qualquer outro)
```

Implementação via `rlang::abort(class = c("cvmdata_error_<tipo>",
"cvmdata_error"), ...)`. Captura específica:

```r
tryCatch(
  cvm_fetch("itr", "bpa_con"),
  cvmdata_error_http = function(e) {
    # tenta mirror, retry, etc.
  }
)
```

### 6.2 Padrão de mensagens

- Função preferida para erros: `cli::cli_abort()` ou `rlang::abort()`.
- Função preferida para informações: `cli::cli_inform()` ou
  `rlang::inform()`.
- Função preferida para warnings: `cli::cli_warn()` ou `rlang::warn()`.
- `print()` e `cat()` proibidos fora de métodos `print.*`/`str.*`.
- Idioma: **inglês**.
- Estilo cli: `{.fn nome_funcao}`, `{.val "valor"}`, `{.var nome_var}`
  para componentes; símbolos `"x"` (erro), `"i"` (info), `"!"`
  (warning), `"v"` (sucesso).

### 6.3 Verbosidade

| Configuração | Tipo | Valores |
|---|---|---|
| `cvmdata.verbosity` (option) | character | `"quiet"`, `"normal"` (default), `"debug"` |
| `CVMDATA_VERBOSITY` (env var) | character | Idem |

Pacote usa `rlang::inform()` / `cli::cli_inform()` internamente, o que
respeita automaticamente `rlib_message_verbosity` (padrão tidyverse
compartilhado) por baixo dos panos. Quando `rlib_message_verbosity =
"quiet"`, todas as mensagens informativas são silenciadas
independentemente do `cvmdata.verbosity`.

Nível `"debug"` é exclusivo do `cvmdata.verbosity` (expõe detalhes
HTTP, URLs, etc.). Não há equivalente em `rlib_message_verbosity`.

---

## 7. YAMLs de schema interno

### 7.1 Localização e formato

`inst/extdata/schemas/<dataset>/<table>.yaml`

### 7.2 Estrutura mínima

A estrutura abaixo é a forma canônica do YAML por tabela, **refinada na
Rodada 2.6** após verificação empírica de três casos (CAD, ITR/BPA,
FRE-detail) que revelaram heterogeneidade nas topologias de download da
CVM (CSV direto vs. CSV dentro de ZIP) e na localização dos dicionários.

```yaml
# inst/extdata/schemas/<dataset>/<table>.yaml
dataset: <dataset>
table: <table>

# Topologia de download. Exatamente um dos dois padrões abaixo deve ser
# não-nulo; o outro é null:
# - cvm_file_url_pattern: a tabela é um CSV diretamente baixável; sem ZIP.
# - cvm_archive_url_pattern: a tabela é uma entrada dentro de um ZIP anual
#   (ou outra periodicidade); cvm_file_pattern é o nome da entrada interna.
cvm_archive_url_pattern: <URL do ZIP ou null>
cvm_file_url_pattern: <URL direta do CSV ou null>
cvm_file_pattern: "<nome do CSV, com {year} interpolável quando aplicável>"

# Dicionário CVM. Se o dicionário vive dentro de um ZIP, usar notação
# `archive.zip#entry.txt` (separador `#`).
cvm_dictionary_url: "<URL do META, opcionalmente com #entry>"

# Configurações do parser. Empíricos: ISO-8859-1 e `;` para todos os
# datasets v0.1 verificados.
encoding: ISO-8859-1
delimiter: ";"

# Particionamento temporal. Domínio fechado:
# - none: arquivo único, sem partição temporal (caso CAD).
# - yearly: um arquivo por ano civil (caso ITR, DFP, FRE).
# Tipos futuros (`monthly`, `quarterly`) podem ser adicionados.
temporal_partitioning: <none | yearly>
first_year: <int ou ausente>  # presente quando temporal_partitioning != none

# Apoio à validação no tempo de leitura.
expected_field_count: <int>

# Transformações que alteram a forma do tibble (vide §9). Lista sempre
# presente, ainda que vazia. Quando vazia, declare explicitamente como [].
transformations:
  - column: <coluna>
    action: <ação do domínio §7.3>
    note: "<justificativa em inglês>"
```

Notas de campo:

- **`cvm_archive_url_pattern` vs `cvm_file_url_pattern`** são mutuamente
  exclusivos por convenção (validado pelo reader). Quando o arquivo é
  CSV direto, `cvm_file_url_pattern` carrega a URL e
  `cvm_archive_url_pattern` é `null`. Quando o arquivo vem em ZIP,
  `cvm_archive_url_pattern` carrega a URL do ZIP e `cvm_file_pattern` é
  a entrada interna; `cvm_file_url_pattern` é `null`.
- **`cvm_file_pattern`** é o nome do arquivo CSV. Quando o dataset tem
  particionamento temporal, contém `{year}` (ou outro placeholder futuro)
  interpolado pelo reader.
- **`cvm_dictionary_url`** com sufixo `#entry` significa "o dicionário é
  a entrada `entry` dentro do ZIP". Sem `#`, a URL é direta.
- **`temporal_partitioning: none`** implica que cada download substitui
  o anterior (o dataset é um snapshot do estado atual, não uma série
  temporal). Caso CAD.
- **`expected_field_count`** existe para detectar mudança não-anunciada
  de schema CVM (defesa em profundidade).

### 7.2.1 Caso resolvido na Rodada 2.6: `convert_to_date` automático

Verificação empírica mostrou que o META da CVM declara consistentemente
`Tipo Dados: date` com `Domínio: AAAA-MM-DD` para todos os campos de
data (formato ISO-8601). Tornar `convert_to_date` uma ação declarada
por coluna inflaria os YAMLs sem ganho — `bpa_con` teria 2 entries só
para isso, e `administrador_membro_conselho_fiscal` teria 5. Portanto:

> **Regra**: conversão de string para `Date` é **automática** quando o
> snapshot de dicionário declara `tipo_dados = "date"` para a coluna.
> **Não deve ser declarada** em `transformations:` do YAML.

Refletido em §7.3 (remoção do `convert_to_date` do domínio de `action`).

### 7.3 Domínio aceito em `action`

Conjunto após refinamento Rodada 2.6:

| `action` | Significado |
|---|---|
| `multiply_by_scale` | Coluna é multiplicada por outra coluna de escala (ex.: `vl_conta` × `escala_moeda`). Requer campo adicional `scale_column:` na entrada |
| `drop` | Coluna é removida do tibble retornado |
| `keep_latest_version` | Tabela mantém apenas o registro com maior `versao` (default em todas as tabelas). Ação de escopo tabela, não coluna; quando presente em YAML, omite o campo `column:` ou usa `column: "<table>"` por convenção |

`convert_to_date` foi **removido** do domínio na Rodada 2.6. Conversão
de data é automática a partir do `tipo_dados = "date"` no snapshot de
dicionário (vide §7.2.1).

Adições futuras de actions devem ser documentadas como incrementos
desta tabela.

### 7.4 Dicionário CVM em snapshot separado

Para evitar duplicação massiva, o dicionário oficial CVM **não** é
replicado nos YAMLs por tabela. Em vez disso, vive em snapshot único
em `inst/extdata/cvm_dictionary_snapshot.csv` (ou equivalente, formato
final a decidir na Rodada 3), atualizado periodicamente por GitHub
Action. A função `cvm_dictionary()` lê do snapshot.

### 7.5 Schema retornado por `cvm_dictionary()`

| Coluna | Tipo | Origem CVM |
|---|---|---|
| `campo` | character | nome do campo no dicionário CVM (snake_case minúsculo) |
| `descricao` | character | descrição em PT do dicionário CVM |
| `tipo_dados` | character | tipo conforme CVM (`"Texto"`, `"Numero"`, `"Data"`) |
| `dominio` | character | codelist quando aplicável; NA caso contrário |
| `tamanho` | integer | comprimento máximo conforme CVM |
| `precisao` | integer | precisão decimal (colunas Numero) |
| `scale` | integer | escala decimal (colunas Numero) |

Sete colunas, todas vindas do dicionário oficial CVM, em PT.

### 7.6 Schema retornado por `cvm_datasets()`

| Coluna | Tipo | Conteúdo |
|---|---|---|
| `conjunto_dados` | character | Identificador curto (`"cad"`, `"itr"`, etc.) |
| `grupo` | character | Taxonomia oficial CVM (~54 valores possíveis em PT) |
| `descricao` | character | Descrição em PT |
| `n_tabelas` | integer | Número de tabelas; NA para datasets v0.2+ ainda não dimensionados |
| `primeiro_ano` | integer | Ano de início de cobertura |

### 7.7 Schema retornado por `cvm_tables(dataset)`

| Coluna | Tipo | Conteúdo |
|---|---|---|
| `tabela` | character | Identificador da tabela em snake_case PT |
| `descricao` | character | Descrição em PT |
| `n_colunas` | integer | Número de colunas da tabela |

Sem coluna `dataset` (constante após filtro pelo argumento). Sem coluna
`grupo` (já está em `cvm_datasets()`; não duplica).

---

## 8. Funções utilitárias

### 8.1 `cnpj_clean(x)`

Exportada na v0.1. Função de transformação de CNPJ.

**Assinatura**: `cnpj_clean(x)`

- `x`: vetor character de CNPJs em formato CVM (com pontuação:
  `"12.345.678/0001-90"`) ou em qualquer formato com não-dígitos
  intercalados.

**Retorno**: vetor character de mesmo tamanho que `x`, contendo apenas
os 14 dígitos do CNPJ.

**Caso de uso**: joins com bases externas (Receita Federal, DATASUS,
IBGE, eSocial) que armazenam CNPJ sem pontuação.

```r
df_cvm |>
  dplyr::mutate(cnpj_join = cnpj_clean(cnpj_cia)) |>
  dplyr::left_join(df_receita, by = c("cnpj_join" = "cnpj"))
```

### 8.2 `cnpj_format(x)`

**Deferida** para v0.2+. Operação inversa: dígitos → formato com
pontuação. Yagni para v0.1 (caso de uso "imprimir CNPJ formatado" é
periférico).

---

## 9. Transformações que alteram a forma do tibble

Esta seção documenta transformações que o pacote aplica e que **alteram
a forma do tibble retornado** vs o arquivo CVM bruto (não apenas o
conteúdo de células). Toda transformação aqui listada deve ter
reflexo no YAML mínimo da tabela afetada (seção `transformations:`) e
em `@details` do help da função alias (`itr_fetch`, `dfp_fetch`).

### 9.1 `vl_conta` × `escala_moeda`

**Tabelas afetadas**: todas as 16 tabelas contábeis de ITR e DFP
(`bpa_con`, `bpa_ind`, `bpp_con`, `bpp_ind`, `dre_con`, `dre_ind`,
`dra_con`, `dra_ind`, `dfc_md_con`, `dfc_md_ind`, `dfc_mi_con`,
`dfc_mi_ind`, `dmpl_con`, `dmpl_ind`, `dva_con`, `dva_ind`).

**Comportamento**:

1. Pacote lê `VL_CONTA` do arquivo CVM bruto (em unidades de
   `ESCALA_MOEDA`).
2. Multiplica internamente por fator de escala:
   - `"UNIDADE"` → ×1
   - `"MIL"` → ×1.000
   - `"MILHÃO"` → ×1.000.000
   - `"BILHÃO"` → ×1.000.000.000
3. Resultado vai para a coluna `vl_conta` do tibble retornado, em
   **unidades absolutas (reais inteiros)**.
4. A coluna `escala_moeda` é **removida** do tibble retornado.
5. A coluna `moeda` é **mantida** (mesmo sendo constante `"REAL"` em
   v0.1, em antecipação à expansão futura para fundos com moeda
   estrangeira em v0.4+).

### 9.2 Política para outras colunas constantes descobertas em fase empírica

**Regra**: perguntar ao mantenedor caso a caso. Não há régua
automática de remoção. Default conservador é manter a coluna mesmo
sendo constante.

### 9.3 `VERSAO` — manter apenas última revisão

**Tabelas afetadas**: todas que aceitam reapresentações pela CVM.

**Comportamento**: pacote retorna apenas o registro com maior `versao`
para cada combinação de `cnpj_cia` + `dt_refer` + chaves específicas
da tabela. Comportamento default; usuário pode desativar via argumento
a definir na Rodada 3.

Refletido no YAML como `action: keep_latest_version`.

---

## 10. Histórico das 26 decisões

Esta seção preserva o caminho de raciocínio, incluindo decisões que
foram **revertidas**, para futura auditoria editorial. Cada item lista
o **estado final** e, quando relevante, o histórico de reaberturas.

### Decisões fechadas e estáveis

| Nº | Tópico | Estado final |
|---|---|---|
| 1 | Padrão de naming de função | `object_verb` (Dev Guide rOpenSci) → `cvm_fetch`, `cad_fetch`, `itr_fetch`, etc. |
| 2 | Siglas contábeis BR | Mantidas como sufixos de tabela: `bpa_con`, `bpp_ind`, `dre_con`, `dfc_md_con`, etc. |
| 4 | Nome da função de dicionário | `cvm_dictionary()` |
| 6 | Comportamento de `cvm_dictionary()` sem argumentos | Erro informativo via `cli::cli_abort()` apontando para `cvm_datasets()` / `cvm_tables()` |
| 12 | Família de funções de cache | 4 funções: `cvm_cache_path()`, `cvm_cache_set_path()`, `cvm_cache_clear()`, `cvm_cache_info()` |
| 13 | Família de funções de source | 2 funções: `cvm_source_get()`, `cvm_source_set()`; domínio fechado `"auto"`/`"portal"`/`"mirror"` |
| 18 | Valores de células categóricas | **Preservados em PT** como vêm da CVM (não traduzidos para EN) |
| 19 | Schema do `cvm_dictionary()` | 7 colunas conforme dicionário oficial CVM: `campo`, `descricao`, `dominio`, `tipo_dados`, `tamanho`, `precisao`, `scale` |
| 20 | Tabela `cabecalho` fictícia | Removida; nome real do arquivo de cabeçalho ITR/DFP é pendência empírica para Rodada 3 |
| 21 | Atributos do tibble retornado | 5 atributos em **inglês**: `source`, `fetched_at`, `dataset`, `table`, `package_version` |
| 22 | YAMLs de schema interno | **Mínimos** com seção opcional `transformations:`; dicionário CVM em snapshot separado |
| 23 | Classes de condição | Hierarquia: `cvmdata_error` + 4 sub-classes (`_input`, `_http`, `_parse`, `_internal`) |
| 24 | Option de verbosidade | `cvmdata.verbosity` com 3 níveis (`"quiet"`/`"normal"`/`"debug"`); env var `CVMDATA_VERBOSITY`; respeita `rlib_message_verbosity` automaticamente |
| 25 | Argumento `validate` em `cvm_fetch` | 3 níveis: `"strict"`/`"warn"`/`"skip"`; default `"strict"` |
| 26 | Argumento `on_error` em `cvm_fetch` | 3 níveis: `"abort"`/`"warn"`/`"silent"`; default `"abort"` |

### Decisões revertidas no curso da sessão

| Nº | Tópico original | Por quê reverteu | Estado final |
|---|---|---|---|
| 3 | Traduzir `composicao_capital` → `capital_composition`, `parecer` → `audit_opinion` | Mudança de régua de idioma (decisão pós-14): nomes de tabela ficam em PT | Tabelas **mantidas em PT**: `composicao_capital`, `parecer` |
| 5 | `cvm_dictionary(dataset, table = NULL)` retorna concat com coluna `tabela` | Sub-decisão posterior: tornar `table` obrigatório por minimalismo | `cvm_dictionary(dataset, table)` com **ambos obrigatórios**; retorno enxuto sem coluna `tabela` |
| 7 | Schema de retorno bilíngue lado-a-lado (`description_en` + `description_pt`) | Adoção do schema CVM puro (decisão 19) | Schema CVM puro de 7 colunas |
| 7-bis | Argumento `details = TRUE` adicionando coluna `unit` | Idem decisão 19; `dominio` da CVM cobre função análoga | **Argumento `details` removido** |
| 8 | Campo `role` no dicionário com 6 valores (`key`, `measure`, `categorical`, `temporal`, `descriptive`, `flag`) | Princípio "mínima transformação do dado-fonte": não adicionar metadados que a CVM não fornece | **Campo `role` removido**; filtros semânticos delegados a `tipo_dados` + `descricao` + filtros fuzzy via `stringr::str_detect` |
| 9 | Coluna `entity_class` em `cvm_datasets()` | A CVM já fornece taxonomia oficial via `grupo` (~54 valores) | Coluna chama-se **`grupo`** e herda valores da CVM |
| 10 | `cvm_datasets()` com 6 colunas (`dataset`, `entity_class`, `description_en`, `description_pt`, `n_tables`, `first_year`) | Mudança de régua de idioma + adoção do `grupo` | 5 colunas em PT: `conjunto_dados`, `grupo`, `descricao`, `n_tabelas`, `primeiro_ano` |
| 11 | `cvm_tables()` com 6 colunas (D — variante com `entity_class`) | Mudança de régua de idioma + simplificação | 3 colunas em PT: `tabela`, `descricao`, `n_colunas` |
| 14 | Colunas-chave universais em EN (`cnpj`, `cnpj_clean`, `cvm_code`, `entity_name`, `filing_date`, `version`) | Adoção da régua "se vem da CVM, fica como na CVM" | 5 colunas em PT preservando CVM: `cnpj_cia`, `cd_cvm`, `denom_cia`, `dt_refer`, `versao`; `cnpj_clean` removida como coluna mas exportada como **função utilitária** |
| 15 | `period_start_date` / `period_end_date` (EN com `_date`) | Idem | `dt_ini_exerc` / `dt_fim_exerc` |
| 16 | `issuer_status_start_date` (EN) | Idem | `dt_ini_sit_emiss` |
| 17 | FRE em EN (`governing_body`, `corporate_event`, `compensation_*`, `shareholder_meeting`) | Idem | FRE em PT: `orgao_administracao`, `evento_societario`, `remuneracao_*`, `assembleia_geral` |

### Decisões adicionais não numeradas (consequências cascateadas)

- **Régua de idioma diferenciada** (princípio reitor): cunhada no
  fluxo da sessão; documentada em §0.1.
- **CNPJ preservado com pontuação**: `cnpj_cia` armazenado tal como
  vem da CVM (`"12.345.678/0001-90"`).
- **`cnpj_clean()` como função utilitária pública**: exportada na
  v0.1. `cnpj_format()` deferida para v0.2+.
- **`vl_conta` em unidades absolutas**: multiplicação interna por
  escala; `escala_moeda` removida do retorno; `moeda` mantida.
- **`cd_cvm` e `versao` como character**: princípio "identificador →
  character"; pendência empírica de validação na Rodada 3.

---

## 11. Pendências empíricas para Rodada 3

Itens cuja resolução exige verificação direta nos arquivos da CVM.
Atualizado pós-Rodada 2.6: itens fechados marcados com `[RESOLVIDO 2.6]`,
parciais com `[PARCIAL 2.6]`.

### 11.1 Nomeação

- **[RESOLVIDO 2.6]** Nome do arquivo de cabeçalho de ITR/DFP. Verificação
  empírica em `itr_cia_aberta_2024.zip`: o arquivo de cabeçalho é
  `itr_cia_aberta_<ano>.csv` (sem sufixo de demonstração contábil). Tem
  9 campos: `CNPJ_CIA`, `DT_REFER`, `VERSAO`, `DENOM_CIA`, `CD_CVM`,
  `CATEG_DOC`, `ID_DOC`, `DT_RECEB`, `LINK_DOC`. Caveat: o nome
  canônico-PT para esta tabela (`cabecalho`? `formulario`? `header`?)
  permanece a decidir na Rodada 3 — o nome de arquivo CVM não sugere
  termo natural em PT.
- Nomes finais individuais das ~36 tabelas FRE. **[PARCIAL 2.6]** Inventário
  empírico no `fre_cia_aberta_2024.zip` confirma 36 CSVs com nomes
  `fre_cia_aberta_<table>_2024.csv`. A régua canônica "fica como na CVM"
  aplicada produz mapeamento direto (nome da tabela = sufixo do CSV).
  Nota: o META zip tem 50 dicionários (14 a mais que CSVs no release
  2024), indicando tabelas pré-anunciadas pela CVM mas ainda não
  populadas. Decisão Rodada 3: incluir apenas tabelas presentes em pelo
  menos um release.
- Nomes de tabelas dos datasets v0.2 (`fca`, `vlmo`, `cgvn`, `ipe`) e
  v0.3 (eventos societários, estrangeiras, incentivadas). Permanece
  pendente; mesma régua a aplicar.

### 11.2 Tipos

- **[RESOLVIDO 2.6]** `cd_cvm` admite zeros à esquerda em ITR (zero-padded
  a 6 dígitos: `000094`..`001023`) **mas não em CAD** (sem padding:
  `35`..`28010`). Coerção para inteiro perderia o padding do ITR.
  Mantida decisão **character** em todos os datasets.
- **[PARCIAL 2.6]** `versao`. ITR/BPA 2024: valores empíricos 1..5; META
  declara `smallint`. Mantido `character` por princípio "identificador
  → character" e proteção contra mudanças futuras de formato. Sem
  evidência para reabrir.
- **[ADIÇÃO 2.6]** **Aviso geral sobre `Tipo Dados` do META CVM**: não
  confiar cegamente. Empíricos:
  - `CEP`, `TEL`, `DDD_*` no CAD: META declara `numeric`, mas dados
    perdem zeros à esquerda (CEPs de SP aparecem como 7 dígitos onde
    deveriam ter 8). Tratar como character na leitura.
  - `CD_CVM` no CAD: META declara `numeric`, mas no ITR é armazenado
    zero-padded em char(6). Tratar como character.
  - Regra de implementação Rodada 3: para campos identificadores
    (CNPJ, CD_CVM, CEP, telefones, CPF), forçar leitura como character
    **mesmo quando o META declara numeric**, independente de dataset.

### 11.3 Conteúdo

- Conteúdo exato do dicionário CVM (`meta_*.txt`) para as ~75 tabelas
  do v0.1. **[PARCIAL 2.6]** 3 dicionários inspecionados a fundo (CAD,
  ITR/BPA, FRE/administrador_membro_conselho_fiscal); estrutura comum
  confirmada (formato bloco, alfabetizado, com campos
  `Descrição`/`Domínio`/`Tipo Dados`/`Tamanho`/`Precisão`/`Scale`).
  Snapshot completo dos demais ~72 fica para Rodada 3.
- **[RESOLVIDO 2.6]** **CVM não publica codelist enumerada no META**
  exceto para domínios triviais (`S/N`, `AAAA-MM-DD`). Para domínios
  enumerados maiores (`ORDEM_EXERC`, `ESCALA_MOEDA`, `Orgao_Administracao`,
  `SIT`, etc.), o META apenas declara `Domínio: Alfanumérico`. Codelists
  têm que ser **varridas empiricamente do CSV**, não extraídas do META.
- **[RESOLVIDO 2.6]** **Codelist tem escopo (tabela, coluna), não coluna
  isolada**. Mesma coluna `Orgao_Administracao` aparece com codelists
  diferentes em tabelas diferentes do FRE. Exemplo verificado em 2024:
  - `administrador_membro_conselho_fiscal`: 4 valores (`"Conselho Fiscal"`,
    `"Pertence apenas ao Conselho de Administração"`,
    `"Pertence apenas à Diretoria"`,
    `"Pertence à Diretoria e ao Conselho de Administração"`).
  - `administrador_declaracao_genero`: 5 valores (`"Conselho Fiscal -
    Efetivos"`, `"Conselho Fiscal - Suplentes"`, `"Conselho de
    Administração - Efetivos"`, `"Conselho de Administração -
    Suplentes"`, `"Diretoria"`).
  Estrutura interna do snapshot de codelists em Rodada 3 deve refletir
  isso (chave composta `dataset` + `table` + `column`).
- Eventuais colunas constantes em datasets que possam ser candidatas a
  remoção. **[PARCIAL 2.6]** Confirmado para `MOEDA = "REAL"` e
  `GRUPO_DFP` (constante por tabela contábil; redundante com nome da
  tabela). Decisões mantidas conforme §9 — perguntar caso a caso ao
  mantenedor; default conservador é manter.

### 11.4 Infraestrutura

- Nome final do snapshot de dicionário
  (`inst/extdata/cvm_dictionary_snapshot.csv` ou outro formato).
  Permanece pendência Rodada 3.
- Workflow GitHub Action para atualização periódica do snapshot.
  Permanece pendência Rodada 3.
- **[PARCIAL 2.6]** Padrão dos arquivos `cvm_file_pattern` em cada YAML
  de schema. Confirmados para 3 tabelas (vide YAMLs entregues na
  Rodada 2.6: `cad/companhias.yaml`, `itr/bpa_con.yaml`,
  `fre/administrador_membro_conselho_fiscal.yaml`). Geração programática
  do restante na Rodada 3.
- **[PARCIAL 2.6]** URL exata do dicionário CVM (`cvm_dictionary_url`)
  por tabela. Padrões verificados:
  - CAD: `https://dados.cvm.gov.br/dados/CIA_ABERTA/CAD/META/meta_cad_cia_aberta.txt`
    (TXT direto)
  - ITR: `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/ITR/META/meta_itr_cia_aberta_txt.zip#meta_itr_cia_aberta_<sigla>.txt`
    (ZIP com um TXT por demonstrativo, não por variante con/ind)
  - FRE: `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/FRE/META/meta_fre_cia_aberta.zip#meta_fre_cia_aberta_<table>.txt`
    (ZIP com um TXT por tabela)
  - DFP: padrão análogo ao ITR a confirmar na Rodada 3.

### 11.5 Validação de design

- Verificar empiricamente se as transformações documentadas em §9
  cobrem todas as transformações que o pacote efetivamente aplica
  (auditoria cruzada).
- Verificar comportamento de `vl_conta` em casos limítrofes (valores
  negativos, NA, escala mista entre linhas de uma mesma tabela, etc.).
- **[ADIÇÃO 2.6]** **Defeitos de qualidade conhecidos da CVM**, descobertos
  durante a verificação. Documentar em vinheta:
  - Caracteres de controle embutidos em campos texto-livre (ex.: BEL
    `\u0007` em `Experiencia_Profissional` no FRE/administrador). O
    parser deve preservar (princípio "fica como vem"); pode-se oferecer
    utilitária opcional `cvm_strip_control_chars()` em v0.2+.
  - CEPs perdem zeros à esquerda no CAD (`Tipo Dados: numeric` na fonte).
    Mantido como vem da CVM em v0.1; possível utilitária `cep_pad()`
    em v0.2+.
  - Empty `Descrição`/`Domínio` em alguns campos do META FRE (ex.:
    `Data_Inicio_Primeiro_Mandato` em `administrador_membro_conselho_fiscal`).
    Reader deve aceitar campos com metadados parciais.
- **[ADIÇÃO 2.6]** **Precisão numérica de `VL_CONTA`**: o META declara
  `decimal(29, 10)` — até 29 dígitos de precisão, dos quais 10 decimais.
  Em R, `double` (IEEE 754, ~15-17 dígitos significativos) pode perder
  precisão para valores extremos. Validar em Rodada 3 se algum valor real
  na base ultrapassa o limite; se sim, decidir entre uso de `bit64::integer64`,
  `decimal64`-like via pacote externo, ou aceitar a perda documentada.

---

## Pontos de continuação para a Rodada 3

1. Validação empírica das pendências listadas em §11.
2. Geração programática dos ~75 YAMLs de schema a partir do snapshot
   de dicionário CVM.
3. Implementação do scaffolding do pacote (estrutura de diretórios,
   DESCRIPTION, NEWS, .gitignore, CI workflows).
4. Implementação de `cad_fetch()` como prova de conceito.
5. Implementação dos demais aliases (`itr_fetch`, `dfp_fetch`,
   `fre_fetch`).
6. Implementação de `cvm_dictionary`, `cvm_datasets`, `cvm_tables`,
   `cnpj_clean`, família de cache e source.
7. Testes (testthat) e validação (pointblank ou equivalente).
8. Documentação: vinhetas, README, NEWS, pkgdown.

Decisões editoriais residuais (idioma das mensagens em cli; estrutura
final dos arquivos data-raw; convenções de teste) ficam para sessão
dedicada ou para o curso da Rodada 3.
