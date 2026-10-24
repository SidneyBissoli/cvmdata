# CLAUDE.md — Contexto persistente do pacote cvmdata

Documento de referência para sessões do Claude Code no diretório
`C:/Users/SIDNEY/OneDrive/programacao/R/packages/cvmdata`. Consolida o
essencial dos canônicos de planejamento para que sessões futuras não
precisem reler tudo. Quando este `CLAUDE.md` divergir de um canônico,
**prevalece o canônico** — em particular
`data-raw/decisions/cvmdata_rodada2-5_naming_unificado-v03.md` para
naming de colunas e tabelas,
`data-raw/decisions/cvmdata_rodada3-0-2_politica_reader_sem_meta.md`
para a política do reader, e
`data-raw/decisions/cvmdata_v0-3_funcao_unica_decisao.md` para a
arquitetura da API (função única
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md),
2026-10-16/19 — §2.1).
`data-raw/decisions/cvmdata_arquitetura_grupos_decisao_v2.md`
(2026-05-25) é HISTÓRICO: os 5 fetchers por contrato que ele previa
foram superados; valem ainda a §1.1 (mapping grupo → contrato), §3.2
(singular), §4.3 (mirror) e §4.6 (atributo `group`). Estado de execução
por fase no `ROADMAP.md`; histórico de breaking changes em `NEWS.md`.

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

Caveat: a palavra `dataset` permanece em inglês como argumento de função
(palavra técnica internacionalizada); a coluna paralela em
[`cvm_datasets()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_datasets.md)
chama-se `conjunto_dados` em PT. Mismatch deliberado.

------------------------------------------------------------------------

## 2. Naming canônico

### 2.1 Funções públicas

Padrão `object_verb` (Dev Guide rOpenSci). **Função única** (decisão de
Sidney, 2026-10-16, que reabriu a arquitetura de 5 fetchers por contrato
de 2026-05-25):
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
serve qualquer conjunto; os grupos planejados para v0.4–v0.8 (fundos,
agentes, ofertas, eventos) estendem
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
pelo YAML de cada conjunto, sem funções novas. Os 4 skeletons
(`fund_fetch()`, `agent_fetch()`, `offering_fetch()`, `event_fetch()`) e
a classe `cvmdata_error_input_group` saíram na v0.3.
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)
segue exportada como wrapper DEPRECADO
([`lifecycle::deprecate_warn()`](https://lifecycle.r-lib.org/reference/deprecate_soft.html)),
com o comportamento antigo intacto (`issuer` aceita CNPJ / CD_CVM /
texto / ticker; `report_type`), até ser removida.

\
`# Função única — qualquer conjunto coberto (hoje: grupo "companhias").`\
`# Cobertura por dataset/sessão vive no ROADMAP.md — não duplicar status aqui.`\
[`cvm_fetch`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)`(``dataset``, ``table``,`\
`          cnpj     ``=`` ``NULL``,      ``# SÓ CNPJ (com ou sem pontuação); código CVM`\
`                                ``# e nome são recusados (cvmdata_error_input)`\
`          ticker   ``=`` ``NULL``,      ``# código B3; resolvido via fca/valor_mobiliario`\
`                                ``` # no mesmo `source`, contra a UNIÃO dos anos ``\
`                                ``# com ticker (2018→último; deslistadas`\
`                                ``` # resolvem); soma-se a `cnpj` ``\
`          year     ``=`` ``NULL``,      ``# anos inteiros, NULL → último; OU`\
`          from     ``=`` ``NULL``,      ``# janela de datas COMPLETAS ("YYYY-MM-DD"),`\
`          to       ``=`` ``NULL``,      ``#   os dois juntos; filtra pela data de`\
`                                ``#   REFERÊNCIA (dt_refer/data_referencia);`\
`                                ``` #   com `year` = erro; em cad = erro ``\
`          as_of    ``=`` ``NULL``,      ``# data COMPLETA; só em tabela-registro com`\
`                                ``` #   `as_of:` no YAML (cad/companhias): ``\
`                                ``#   registros vigentes na data, linhas de HOJE`\
`          basis    ``=`` ``NULL``,      ``# "ind" / "con" / c("ind","con") — ver abaixo`\
`          reading  ``=`` ``NULL``,      ``# "original" / "restated" / os dois — só nas`\
`                                ``#   16 tabelas com ordem_exerc; ver abaixo`\
`          source   ``=`` ``NULL``,      ``# via cvm_source_get()`\
`          on_error ``=`` ``"abort"``,`\
`          validate ``=`` ``"strict"``,`\
`          ``...``)``                  ``# reservado: qualquer extra aborta`\
\
`# Todas as versões de um documento (Parte 3 das versões, 2026-10-24,`\
`# Forma B: função separada; cvm_fetch() segue devolvendo só a vigente).`\
`# Assinatura = a parte de cvm_fetch() que IDENTIFICA o documento; recusa`\
`# por nome reading / from / to / as_of (filtros da leitura vigente).`\
`` # Só tabelas com `keep_latest_version` no YAML; outra = cvmdata_error_input. ``\
`# Colunas da tabela (+ year, basis) + superseded_at (Date),`\
`# superseded_by_versao, history_source ("current" na vigente; "rad" /`\
`# "mirror" no espelho; "cvm" no CSV), id_doc, motivo_reapresentacao.`\
`# source = "mirror": part-N ∪ __history por union_by_name (DuckDB);`\
`# source = "cvm": CSV anual SEM keep_latest_version + cli_inform de que`\
`# o CSV guarda só parte das versões (completo só no espelho/RAD).`\
[`cvm_versions`](https://sidneybissoli.github.io/cvmdata/reference/cvm_versions.md)`(``dataset``, ``table``, cnpj ``=`` ``NULL``, ticker ``=`` ``NULL``, year ``=`` ``NULL``,`\
`             basis ``=`` ``NULL``, source ``=`` ``NULL``, on_error ``=`` ``"abort"``,`\
`             validate ``=`` ``"strict"``, ``...``)`\
\
`# Deprecada (wrapper com aviso; remoção em release futura)`\
[`issuer_fetch`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)`(``dataset``, ``table``, issuer ``=`` ``NULL``, year ``=`` ``NULL``, source ``=`` ``NULL``,`\
`             report_type ``=`` ``NULL``, on_error ``=`` ``"abort"``, validate ``=`` ``"strict"``, ``...``)`\
\
`# Descoberta`\
[`cvm_groups`](https://sidneybissoli.github.io/cvmdata/reference/cvm_groups.md)`(``)``                                          ``# 18 grupos + contrato`\
[`cvm_datasets`](https://sidneybissoli.github.io/cvmdata/reference/cvm_datasets.md)`(``group ``=`` ``NULL``)``                            ``# datasets disponíveis`\
[`cvm_tables`](https://sidneybissoli.github.io/cvmdata/reference/cvm_tables.md)`(``dataset``, group ``=`` ``NULL``)``                     ``# tabelas de um dataset`\
[`cvm_dictionary`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md)`(``dataset``, ``table``, group ``=`` ``NULL``)``          ``# dicionário do snapshot`\
[`cvm_codelist`](https://sidneybissoli.github.io/cvmdata/reference/cvm_codelist.md)`(``dataset``, ``table``, ``column``, group ``=`` ``NULL``)``    ``# valores categóricos`\
[`cvm_dataset_years`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dataset_years.md)`(``dataset``, group ``=`` ``NULL``)``              ``# range de anos publicados`\
\
`# Cache`\
[`cvm_cache_path`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_path.md)`(``)`\
[`cvm_cache_set_path`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_set_path.md)`(``path``)`\
[`cvm_cache_clear`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_clear.md)`(``what ``=`` `[`c`](https://rdrr.io/r/base/c.html)`(``"all"``, ``"raw"``, ``"parquet"``)``,`\
`                group ``=`` ``NULL``, dataset ``=`` ``NULL``, year ``=`` ``NULL``,`\
`                confirm ``=`` `[`interactive`](https://rdrr.io/r/base/interactive.html)`(``)``)`\
[`cvm_cache_info`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_info.md)`(``)`\
\
`# Source`\
[`cvm_source_get`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_get.md)`(``)`\
[`cvm_source_set`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_set.md)`(``source``)`\
\
`# Utilidades`\
[`cnpj_clean`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_clean.md)`(``x``)`\
[`cnpj_format`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_format.md)`(``x``)``                ``# inverso de cnpj_clean`

Argumento `group` nas funções de descoberta resolve por unicidade quando
omitido (`NULL`); a partir de v0.4, quando um slug de dataset puder
ocorrer em mais de um grupo, omitir `group` aborta com
`cvmdata_error_input_ambiguous`.

Domínio dos argumentos enumerados (validados via
[`rlang::arg_match0()`](https://rlang.r-lib.org/reference/arg_match.html)):

- `source ∈ c("mirror", "cvm")`. **Default `"mirror"`**: lê parquets do
  release `mirror-<group>-<dataset>-latest` via API GitHub + DuckDB
  local; ~30× mais rápido que `"cvm"`. Backend `"cvm"` (portal aberto
  `dados.cvm.gov.br`) permanece suportado por chamada explícita
  (`source = "cvm"`) ou via `cvm_source_set("cvm")` para frescor byte a
  byte. Precedência: arg explícito \> `getOption("cvmdata.source")` \>
  default. A assinatura declara `source = NULL` para consulta dinâmica
  do option (mesmo padrão de
  [`cvm_cache_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_path.md)
  ↔︎
  [`cvm_cache_set_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_set_path.md)).

- `validate ∈ c("strict", "warn", "skip")`, default `"strict"`.

- `on_error ∈ c("abort", "warn", "silent")`, default `"abort"`.

- `basis` (Sidney, 2026-10-19; nome escolhido contra `report_type`,
  `type_format`, `scope`, `report`, `type`, `view`): `"ind"`, `"con"` ou
  `c("ind", "con")` (empilha as duas). **Obrigatório, sem padrão**, para
  tabelas com variantes individual/consolidada (`bpa`, `bpp`, `dre`,
  `dra`, `dfc_md`, `dfc_mi`, `dmpl`, `dva`) — recusado `"con"` como
  padrão: 35% das cias DFP 2023 só têm `"ind"`. Essas tabelas trazem
  **sempre** a coluna `basis` no resultado, nos dois backends
  (`set_basis_column()` em `R/api-cvm-fetch.R` substitui o `report_type`
  vazado pelo mirror). **Erro** se passado a tabelas sem a divisão
  (`composicao_capital`, `submissao`, `parecer`, `companhias`) — não
  ignorar calado. `report_type ∈ c("ind", "con")` ou `NULL` sobrevive só
  em
  [`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)
  (deprecada).

- `year`: integer vector ou `NULL`. `NULL` → **último ano disponível**,
  descoberto por `HEAD` probing decrescente. Para histórico, integer
  vector explícito (`year = 2012:2024`). Helper
  [`cvm_dataset_years()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dataset_years.md)
  devolve o range. **Sem sentinela `"all"`** — tipo único. Ano anterior
  ao `first_year` da TABELA (medido no espelho em 2026-10-21; uma tabela
  pode começar depois do dataset: `composicao_capital` 2020, 14 do FRE

  2023\) = `cvmdata_error_input` antes de baixar
  (`check_published_years()`); em janela `from`/`to`, os anos
  inexistentes caem com `cli_inform`.

- `from`/`to` (só em
  [`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)):
  datas completas, os dois juntos (`"YYYY-MM-DD"` ou `Date`); `year`
  junto = erro; data incompleta = erro (recusado por complexidade); em
  tabela sem partição anual = erro. Os anos lidos são os abrangidos pela
  janela; o corte é pós-leitura pela data de REFERÊNCIA do documento
  (`dt_refer` ou `data_referencia`), nunca pela data de entrega
  (`filter_by_reference_date()`).

- `as_of` (Sidney, 2026-10-21; frente Deslistadas): data completa, só em
  tabela-registro cujo YAML declara `as_of: {registered, cancelled}`
  (hoje `cad/companhias`: `dt_reg`/`dt_cancel`); outra tabela = erro.
  Mantém os REGISTROS vigentes na data (`dt_reg <= X` e `dt_cancel`
  vazia ou `> X`), olhando cada `(cnpj_cia, cd_cvm)` — 34 CNPJ têm dois
  registros. As linhas são as de HOJE (a CVM não publica o cadastro do
  passado); o retrato do ano é `fca/geral`. Chave do CAD =
  `(cnpj_cia, cd_cvm, tp_merc)`: 107 registros repetem-se só por
  `tp_merc` e ficam como a CVM publica (receita de uma linha por
  registro no help); `tp_merc` vazio nas canceladas. Sem argumentos
  extras de código CVM ou mercado (recusados 2026-10-21). Mesmo nome
  previsto na v0.7 para os cadastros de agentes.

Sobre exercícios contidos em cada CSV anual: o portal publica em cada
ano apenas `ORDEM_EXERC ∈ {ÚLTIMO, PENÚLTIMO}` — o ano declarado e seu
N-1. Sem `reading`,
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
retorna o conteúdo literal do CSV do `year` pedido (não reconstrói o
antepenúltimo; para histórico mais longo, pedir `year = (N-2):N` e
empilhar).

- `reading` (Sidney, 2026-10-20; Parte 2 das versões): as duas leituras
  de um exercício. `"original"` = linhas `ÚLTIMO` do arquivo de `year`;
  `"restated"` = linhas `PENÚLTIMO` do arquivo de `year + 1` (lido pelo
  pacote; só se publicado — senão `cli_inform` e devolve o que existe);
  `c("original", "restated")` empilha na ordem pedida. Coluna `reading`
  no resultado só quando o argumento é dado; linhas como a CVM publica
  (`dt_refer`/`versao` do documento de origem;
  `dt_fim_exerc`/`dt_ini_exerc` identificam o exercício). Só nas 16
  tabelas com `ordem_exerc` (DFP/ITR `bpa`…`dva`, conferido no
  dicionário); em outra tabela = erro. `year = NULL` resolve o último
  ano como sem `reading`, depois busca o seguinte. Com `from`/`to`, a
  janela corta por `dt_fim_exerc`. Medido 2026-10-20: ano do arquivo =
  ano de `dt_refer` (0 divergências em dfp/itr bpa/dre); no ITR o
  `PENÚLTIMO` de `bpa`/`bpp` é o fechamento do ano anterior (leitura
  reexpressa do trimestre não existe para balanço); 21 bancos trazem o
  comparativo individual de 2024 **zerado** na DFP 2025 (Res. CMN 4.966
  sem reapresentar) — fica zero, como na CVM. Fixture real
  `dfp_cia_aberta_2025.zip` + `mirror-dfp-bpa-ind-2025.parquet` (BB con
  reexpressa 12 contas; BB ind zeros; MGLU igual).

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

CGVN/VLMO/IPE seguem uma terceira convenção (FRE-detail-like): mesma
`cnpj_companhia` / `data_referencia`, mas a coluna CVM-code se chama
`codigo_cvm` (não `cd_cvm`). O resolver `match_by_cd_cvm()` aceita
qualquer das duas via helper interno `cdcvm_col(df)`; semântica
idêntica.

### 2.3 Submissão (header de ITR/DFP/FRE)

Tabela de cabeçalho dos três datasets chama-se `submissao`. 9 campos:
`cnpj_cia`, `dt_refer`, `versao`, `denom_cia`, `cd_cvm`, `categ_doc`,
`id_doc`, `dt_receb`, `link_doc`. É o **índice de entregas** do dataset:
uma linha por documento entregue, reapresentações incluídas (sem
`keep_latest_version` desde 0.2.0.9000 — Parte 1 das versões, ROADMAP).
A entrega vigente de um `(cnpj_cia, dt_refer)` é a última por
`(dt_receb, id_doc, versao)`; o pacote a calcula onde precisa
(`check_filings()`), não a marca com coluna.

### 2.4 Regra dos identificadores → character

Campos identificadores (CNPJ, CD_CVM, CEP, telefones, CPF, ID\_\*,
DDI/DDD, protocolos, ticker B3) são forçados a **character** mesmo
quando o META declara `numeric`. O META da CVM declara mal — CEPs perdem
zero à esquerda, CD_CVM tem padding heterogêneo entre datasets, ID_Item
da CGVN é `N.N.N`, etc. Implementação em
`R/util-csv-cvm.R::identifier_columns()`: classificação por **prefixos
regex** (`^cnpj`, `^cpf`, `^codigo_`, `^cd_cvm`, `^cep`, `^ddi_`,
`^ddd_`, `^id_`, `^protocolo`) **+ exact-match** para os esquisitos
(`caixa_postal`, `tel`, `versao`). Refator de v0.2 — Sessão 10 —
substituiu a lista monolítica de regex `.identifier_patterns` por duas
listas planas + um helper testável.

### 2.5 Datas

Conversão para `Date` é **automática** sempre que o snapshot de
dicionário declarar `tipo_dados = "date"`.

### 2.6 vl_conta × escala_moeda

Em tabelas ITR/DFP contábeis: `VL_CONTA` é multiplicada por
`ESCALA_MOEDA` (`UNIDADE`=1, `MIL`=1e3, `MILHÃO`=1e6, `BILHÃO`=1e9) e
retornada em reais absolutos. `escala_moeda` é removida do tibble;
`moeda` mantida (constante `"REAL"` na v0.1).

### 2.7 Seleção de companhias via `issuer` (e `cnpj`/`ticker`)

Em
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
(v0.3) a seleção é por **`cnpj`** (só CNPJ, com ou sem pontuação —
`check_cnpj()` recusa código CVM e nome, inclusive como cortesia a quem
migra do GetDFPData2) e/ou **`ticker`** (código B3 → CNPJ via
`fca/valor_mobiliario`, lido do mesmo `source`; `check_ticker()` recusa
o que não tem forma de ticker). O ticker é procurado na UNIÃO de todos
os anos do FCA com a coluna (`ticker_first_year: 2018` no YAML; vazia em
2010–2017), não só no ano pedido — assim o código de uma deslistada
(GOLL4, BPAN4) resolve para qualquer `year` (decisão 2026-10-21;
`resolve_ticker_all_years()`). Os dois se somam; CNPJ ausente da tabela
= zero linhas, calado; ticker ausente de TODOS os anos =
`cvmdata_error_input`; ticker que aponta para mais de um CNPJ =
`cvmdata_error_input` pedindo `cnpj` (guarda; medido 2026-10-21: nenhum
reusado). Busca textual e CD_CVM ficaram SÓ em
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)
(deprecada); o cadastro `cvm_fetch("cad", "companhias")` é o lugar de
resolver nome/código → CNPJ. Sem `cpf`: a CVM não publica CPF (cadastros
PF só trazem nome; filtro de PF fica para a v0.7).

Em
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md),
argumento único com **detecção automática de tipo** (implementado em
`filter_by_issuer()` em `R/api-issuer-fetch.R`, que
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
reaproveita só no ramo CNPJ):

| Padrão do input (após [`as.character()`](https://rdrr.io/r/base/character.html)) | Interpretação | Match contra |
|----|----|----|
| `^[0-9]{14}$` | CNPJ sem pontuação | `cnpj_clean(cnpj_cia)` |
| Contém `.` ou `/` ou `-` e tem 14 dígitos | CNPJ com pontuação | `cnpj_cia` literal e/ou `cnpj_clean(cnpj_cia)` |
| `^[0-9]{1,6}$` | CD_CVM | `cd_cvm` (com ou sem zero-padding); se a tabela não tem `cd_cvm`, resolve para CNPJ via `submissao` |
| Resto (≥1 token alfabético) | Busca textual com fronteira de palavra e mapa de abreviações (`BCO ↔︎ BANCO`, `CIA ↔︎ COMPANHIA`, `S.A. ↔︎ S/A`) | `denom_cia` normalizada |

Resolução CD_CVM → CNPJ via `submissao`: quando o usuário passa CD_CVM
contra uma tabela sem `cd_cvm` (`composicao_capital`, `parecer`), o
pipeline lê a `submissao` do mesmo dataset/year e faz lookup antes de
filtrar. CD_CVMs ausentes na `submissao` daquele ano abortam com
`cvmdata_error_input`. Datasets sem tabela `submissao` abortam com
mensagem instruindo o uso de CNPJ ou texto.

Match textual: múltiplas matches em modo
[`interactive()`](https://rdrr.io/r/base/interactive.html) exibem lista
numerada via [`utils::menu()`](https://rdrr.io/r/utils/menu.html); em
batch/CI abortam com `cvmdata_error_input` listando candidatos. Zero
matches aborta com `cvmdata_error_input`.

Política de versão: as tabelas de **detalhe** mantêm apenas a **última
entrega** por `(cnpj_cia, dt_refer)` via transformação canônica
`keep_latest_version` no YAML, ordenando por data de recebimento
(`dt_receb`/`data_entrega`), depois id do documento
(`id_doc`/`id_documento`/`protocolo_entrega`), depois `versao`. Tabelas
sem colunas de entrega caem na maior `VERSAO`. A **`submissao` não
deduplica** (0.2.0.9000): é o índice de entregas e devolve todas, com a
data de recebimento — quem faz join por `(cnpj, data)` casa todas as
entregas; a vigente é a última pela mesma ordem (§2.3). `VERSAO` **não é
chave** (medido 2026-10-18: TRV XLIII DFP 2023 tem duas v1; Travessia VI
DFP 2024 tem 1, 2, 1 e a v1 de agosto é a vigente). Depois do backend,
`check_filings()` (`R/util-filing-checks.R`) confere a tabela contra a
`submissao` (calculando a entrega vigente de cada chave antes de
comparar): em DFP/ITR tira linhas idênticas e avisa (varredura
2010-2026: 884 casos com a demonstração inteira em dobro, a maioria com
UMA entrega no índice; em `vlmo` linhas idênticas são legítimas e
ficam); avisa quando a tabela traz entrega anterior à última. Desliga
com `options(cvmdata.check_filings = FALSE)`.

------------------------------------------------------------------------

## 3. Convenções de código R

- Pipe: `|>` (nunca `%>%`). `R (>= 4.1)` no `Depends`.
- Strings: aspas duplas por padrão;
  [`stringr::str_c()`](https://stringr.tidyverse.org/reference/str_c.html)
  em vez de
  [`paste()`](https://rdrr.io/r/base/paste.html)/[`paste0()`](https://rdrr.io/r/base/paste.html).
- Indentação 2 espaços, sem tabs.
- Largura máxima 80 chars (tolerância até 100).
- Style guide: tidyverse, aplicado pelo
  [Air](https://posit-dev.github.io/air/) (`air format .`; configuração
  em `air.toml`). Rodar antes do lintr.
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

## 4. Estrutura do pacote

**Régua R/ é flat.** `R CMD INSTALL` ignora subpastas de `R/` — a
representação modular do canônico de arquitetura fica como referência
conceitual; arquivos reais usam **prefixos de hífen**:

| Prefixo | Conteúdo |
|----|----|
| `api-` | Fetcher público (`api-cvm-fetch.R`: casca de validação sobre `issuer_fetch_internal()`), `api-issuer-fetch.R` (pipeline + wrapper deprecado + `filter_by_issuer()` + resolver de ticker) + `cvm-groups` |
| `schema-` | Loader de YAML (`schema-load.R`) |
| `source-` | Backends de dados (`source-cvm-http.R`, `source-mirror-duckdb.R`) |
| `transform-` | Transformações declarativas (`transform-schema.R`) |
| `util-` | Helpers internos (`util-cnpj.R`, `util-errors.R`, `util-attrs.R`, etc.) |
| (sem prefixo) | API estável transversal: `cache.R`, `discovery.R`, `source.R`, `cvmdata-package.R` |

Layout dos schemas:
`inst/extdata/schemas/<group>/<dataset>/<table>.yaml` (`<group>` é o
slug CKAN; `"companhias"` na cobertura atual). Datasets cobertos vivem
no `ROADMAP.md`. Layout do ETL:
`inst/etl/{00-config,01-fetch-cvm,02-csv-to-parquet,02b-validate,03-publish,util-hash}.R`.

`data-raw/` mistura **build scripts** regeneráveis (`build-*.R` para
snapshots, fixtures e vignette data) com **auditorias one-shot**
(`run-capacity-audit.R`, `validate-mirror-end-to-end.R`) e
**`data-raw/decisions/`**, onde vivem TODOS os canônicos rastreados
(desde 2026-10-19): - `cvmdata_rodada2-5_naming_unificado-v03.md`
(naming) e `cvmdata_rodada3-0-2_politica_reader_sem_meta.md` (reader) —
citados por seção no código e no schema do CAD. -
`cvmdata_v0-3_funcao_unica_decisao.md` (arquitetura vigente),
`cvmdata_arquitetura_grupos_decisao_v2.md` (histórico; mapping de
grupos) + docs de planejamento v0.2 (`cvmdata_v0-2_*.md`). Os demais
`cvmdata_rodada*.md` (rodadas 1, 2, 2.6, 3.0, 3.1) e os
`PROMPT_CLAUDE_*.md` de sessão ficam FORA do repo (histórico;
`git show ad04382^:<nome>`). O `.gitignore` ancora `/cvmdata_rodada*.md`
e `/cvmdata_arquitetura_*` na raiz de propósito: sem a barra o padrão
engolia esta pasta.

Apenas os build scripts são regenerados em ciclo normal; canônicos só
mudam por decisão deliberada.

Documentação narrativa em `vignettes/`: `cvmdata.Rmd` é o vignette
canônico embarcado no tarball (overview do pacote);
`vignettes/articles/` contém artigos longos publicados **apenas no site
pkgdown** (`.Rbuildignored`), sem peso na tarball CRAN.

------------------------------------------------------------------------

## 5. Sistema de classes S3

S3 minimalista. Classes internas:

- `cvm_tbl` — subclasse de `tbl_df`. Todo tibble retornado por funções
  públicas. Carrega 6 atributos em inglês: `source`, `fetched_at`,
  `group`, `dataset`, `table`, `package_version`.
- `cvm_table_schema` — objeto interno descrevendo o schema lido do YAML.
  Carrega `$group` stampado por `load_schema()` para que os callers
  downstream propaguem sem re-lookup.
- `cvm_source` — handle interno para dispatch HTTP / mirror / cache.

`print.cvm_tbl()` é o único método print custom: exibe `source`,
`fetched_at`, `group`, `dataset` e `table` antes do tibble normal,
depois delega a [`NextMethod()`](https://rdrr.io/r/base/UseMethod.html).

------------------------------------------------------------------------

## 6. Hierarquia de classes de condição

    cvmdata_error                          (pai genérico de erros)
    ├── cvmdata_error_input                (argumento inválido do usuário;
    │   │                                   inclui cnpj/ticker/basis/from/to
    │   │                                   malformados em cvm_fetch())
    │   └── cvmdata_error_input_ambiguous  ((dataset, table) ocorre em mais
    │                                       de um group; passar group explícito)
    │       (cvmdata_error_input_group saiu na v0.3 com os skeletons)
    ├── cvmdata_error_http                 (falha de rede / HTTP)
    │   └── cvmdata_error_http_transport   (o portal não respondeu: DNS,
    │                                       connect TCP, TLS, timeout de
    │                                       leitura — distinto de um status
    │                                       HTTP como 404; o ETL usa a
    │                                       distinção no disjuntor do stage 01)
    ├── cvmdata_error_parse                (falha de parse ou validação)
    │   └── cvmdata_error_zip_member_missing (CSV da tabela-detalhe ausente
    │                                       no ZIP anual — tabela não existia
    │                                       naquele ano; ETL trata como skip)
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
    ├── cvmdata_warn_year_listing_fallback (cvm_dataset_years: índice de
    │                                       diretório da CVM inalcançável após
    │                                       retries; caiu para first_year:ano_atual)
    ├── cvmdata_warn_eviction              (LRU eviction removeu unidades do
    │                                       cache local para honrar
    │                                       options(cvmdata.cache_max_size_mb))
    ├── cvmdata_warn_duplicate_filing      (DFP/ITR: a CVM repetiu linhas;
    │                                       cópias idênticas removidas)
    ├── cvmdata_warn_conflicting_filing    (DFP/ITR: cópias da mesma entrega
    │                                       com vl_conta diferente; mantidas)
    └── cvmdata_warn_stale_filing          (a tabela traz entrega anterior à
                                            última do índice submissao)

Implementação via wrapper interno `cvmdata_abort(message, class, ...)`
que adiciona `"cvmdata_error"` ao final do vetor de classes
automaticamente. Análogo `cvmdata_warn()` para warnings.

------------------------------------------------------------------------

## 7. Política do reader em três modos validate

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

8 tabelas FRE têm `meta_status: missing` (sem META oficial CVM):
`administrador_PCD`, `empregado_PCD`,
`empregado_local_declaracao_genero`, `empregado_local_declaracao_raca`,
`empregado_posicao_declaracao_genero`,
`empregado_posicao_declaracao_raca`, `empregado_posicao_faixa_etaria`,
`empregado_posicao_local`.

Schema do YAML por tabela: campos canônicos (`dataset`, `table`,
`cvm_archive_url_pattern` xor `cvm_file_url_pattern`,
`cvm_file_pattern`, `cvm_dictionary_url`, `meta_status`, `encoding`,
`delimiter`, `temporal_partitioning ∈ {none, yearly}`, `first_year`,
`expected_field_count`, `expected_field_names`, `transformations`).
Domínio de `action` em `transformations`: `multiply_by_scale` (requer
`scale_column:`), `drop`, `keep_latest_version` (aceita `keys: [...]`
opcional para compor chaves extras com a dupla implícita `(cnpj, data)`
— usado em `cgvn/praticas` com `keys: [id_item]`). Detalhes no naming
doc v03 e no loader (`R/schema-load.R`).

------------------------------------------------------------------------

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
- **L4** memória da sessão: planejado
  ([`cachem::cache_mem()`](https://cachem.r-lib.org/reference/cache_mem.html),
  50 MB), ainda não em `Imports`. **L2** não é usado.

Fallback por `source`:

- `source = "mirror"` (default): L4 → L3 → GitHub Releases → erro.
- `source = "cvm"`: L4 → L1 → portal CVM HTTP → erro.

Eviction LRU: default 100 MiB (`options(cvmdata.cache_max_size_mb)`).
Quando soma \> 90%, próximo download dispara eviction até cair a 80%.
Unidade: diretório do ano para yearly, par `{artifact, sidecar}` para
não-particionados. `0`/negativo/`Inf` desligam a engine. Aviso agregado
por `cvmdata_warn_eviction` (opt-in
`options(cvmdata.cache_warn_evictions)` — default
[`interactive()`](https://rdrr.io/r/base/interactive.html)). CSVs
extraídos via [`unzip()`](https://rdrr.io/r/utils/unzip.html) contam
para o limite mas não disparam eviction.

[`cvm_cache_clear()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_clear.md)
manual: `what ∈ c("all", "raw", "parquet")` + `group/dataset/year`
opcionais. `what = "all"` ignora filtros; senão compõe
`<cache>/<what>/<group>/<dataset>/<year>/` com cada segmento opcional da
direita pra esquerda. `what = "parquet"` rejeita `year` (L3 aninha year
sob table); para granularidade year-level usar `what = "raw"`.

Mirror parquet: workflow semanal `etl-mirror.yaml` (cron `0 7 * * 2`)
roda matrix bidimensional `(group, dataset)` (`fail-fast: false`); cada
job encadeia os scripts `01→02→02b→03` com flags `--group --dataset`. O
publish detecta mudança via hash SHA-256 (`util-hash.R`) e skipa
republish quando o hash bate o anterior. O hash cobre os META **e o
conteúdo (linhas e colunas, sem atributos) de cada parquet**; até
2026-10-19 cobria só os META e o mirror ficou congelado no retrato de
junho/2026. Depois do upload, o release é forçado para fora de draft e
conferido sem credencial (o vlmo foi draft = 404 para todos de junho a
outubro). Rodada com `year` é smoke test e NÃO publica (o publish deixa
o release igual aos parquets locais e apagaria os outros anos). O
release é atualizado NO LUGAR (`gh release edit` + upload `--clobber` +
`delete-asset` dos que sobraram, com `=` → `.` na comparação), nunca
apagado e recriado: o delete+create deixava o mirror vazio durante o
upload e, em 19/10, falhou calado no fre/itr. `__source_hash.json` sobe
por último; um upload que falha (o GitHub responde 500 esporádico no
`--clobber`) é tentado de novo até três vezes. **Histórico de entregas
substituídas** (Parte 3 das versões, 2026-10): para cada partição cujo
hash de conteúdo mudou, o publish baixa o parquet do release anterior e
compara entrega por entrega (`inst/etl/util-history.R`: chave
`(cnpj, data[, extras do YAML])`, assinatura = linhas ordenadas sobre as
colunas comuns, SEM `versao`/ `id_doc`/`dt_receb` — documento novo com
os mesmos números não é versão); as linhas das entregas trocadas ou
sumidas vão, com `superseded_at` e `superseded_by_versao`, para o asset
acumulativo `<table>__report_type=R__year=Y__history.parquet`, que nunca
é apagado como stale. Só tabelas com `keep_latest_version` têm
histórico; o `-latest` não muda; o cliente ignora o asset (o parser
recusa o nome); o JSON ganha o mapa `history` (partição → sha256),
`hash` mantém o significado. `03-publish.R --dry-run` = smoke local sem
tocar o release. Fora do repo, o portfolio-monitor
(`R/collect_vigia_mirror_cvm.R`) confere toda semana, sem credencial, a
última entrega de cada dataset na CVM contra a do espelho, e abre o item
`cvmdata:mirror-atrasado` no painel quando falta entrega há mais de 7
dias ou o release não abre anônimo — é o alarme que faltou de junho a
outubro/2026. Encoding dos asset names:
`<table>__report_type=R__year=Y__part-0.parquet` (Hive-style achatado);
GitHub Releases sanitiza `=` → `.` no URL público;
`parse_mirror_asset_name()` em `R/util-mirror-assets.R` tolera ambos.

------------------------------------------------------------------------

## 9. Política de testes

- `testthat` 3.x edition 3, `Config/testthat/edition: 3`.
- **Sem rede em `tests/testthat/`**. Testes de integração em
  `test-integration-*.R` com `skip_on_cran()` + `skip_if_offline()` +
  guarda `CVMDATA_RUN_INTEGRATION=true`.
- **Mocks HTTP** via `httptest2` (e em alguns casos
  [`httr2::with_mocked_responses()`](https://httr2.r-lib.org/reference/with_mocked_responses.html)).
- **Fixtures pequenos e reais** em `tests/testthat/fixtures/`: cada
  fixture com `*.meta.json` registrando origem. Inclui `cad_sample.csv`,
  ZIPs `{dfp,itr,fre,cgvn}_cia_aberta_2024.zip` e parquets
  `mirror-*.parquet` gerados por `data-raw/build-mirror-test-fixtures.R`
  (raw ZIPs do CGVN+ via `build_cgvn_raw_fixture()` no mesmo script;
  CAD/DFP/ITR/FRE foram commitados manualmente antes de o script
  existir).
- **Snapshot tests** para mensagens de erro, atributos serializados,
  estrutura de output
  ([`dplyr::glimpse()`](https://pillar.r-lib.org/reference/glimpse.html)
  snapshotado).
- **Cobertura alvo 90%**.

Cache real fica em `tools::R_user_dir("cvmdata", "cache")`. Em testes, é
redirecionado para tempdir via `options(cvmdata.cache_dir = ...)`.

Gate por commit: `devtools::check() == 0E/0W/0N` com `--as-cran`, lint
clean, testes verdes,
[`pkgdown::build_site()`](https://pkgdown.r-lib.org/reference/build_site.html)
funcionando.

CI em `.github/workflows/`: `R-CMD-check.yaml` (matrix release/devel +
SO), `lint.yaml`
([`lintr::lint_package()`](https://lintr.r-lib.org/reference/lint.html)),
`test-coverage.yaml` (covr → Codecov), `pkgdown.yaml` (deploy do site),
`etl-mirror.yaml` (cron `0 7 * * 2` + dispatch manual, ver §8). Os
quatro primeiros travam por push/PR; o quinto é operacional.

------------------------------------------------------------------------

## 10. Workflow de desenvolvimento

- Modo **tracer bullet**: implementar a função mais simples
  ponta-a-ponta antes de generalizar.
- **Estado de execução vive em `ROADMAP.md`** — sessão por sessão, fase
  por fase. `CLAUDE.md` não duplica status; consultar o roadmap antes de
  assumir que algo está entregue.
- **Não reabrir decisões travadas** (canônicos das Rodadas 2.5/2.6/3.0,
  decisão de grupos 2026-05-25, decisões pós-3.4 em `NEWS.md` + git
  log). Se acha que precisa rever, perguntar antes de agir.
- **Não inventar URLs, nomes de arquivos CVM, conteúdo de schemas**.
  Usar YAMLs validados em `inst/extdata/schemas/` ou `schemas_proto/`
  para protótipos, ou perguntar.

### 10.1 Comandos não-óbvios

Comandos triviais de pacote R
([`devtools::check()`](https://devtools.r-lib.org/reference/check.html),
[`devtools::test()`](https://devtools.r-lib.org/reference/test.html),
[`devtools::document()`](https://devtools.r-lib.org/reference/document.html),
[`devtools::build_readme()`](https://devtools.r-lib.org/reference/build_readme.html),
[`devtools::install()`](https://devtools.r-lib.org/reference/install.html),
[`devtools::build()`](https://devtools.r-lib.org/reference/build.html),
[`lintr::lint_package()`](https://lintr.r-lib.org/reference/lint.html),
[`covr::package_coverage()`](http://covr.r-lib.org/reference/package_coverage.md))
não estão listados aqui — usar diretamente.

``` powershell
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

Lógica enterrada em `data-raw/build-codelists-snapshot.R`. Replicar se o
gerador for revisitado:

- **Pelo dicionário**: colunas onde `dominio` enumera valores com
  separador `/` ou `|` (capta `S/N`, `PF/PJ`).
- **Por cardinalidade observada**: colunas `tipo_dados = "varchar"` com
  `tamanho < 200` e ≤ 50 valores distintos no último ano, EXCLUINDO
  prefixos: identificadores (`cnpj`, `cd_cvm`, `codigo_cvm`, `cep`,
  `tel`, `ddd`, `cpf`, `id_doc`, `id_documento`, `versao`), `^cd_`
  (códigos contábeis), `^nome_`/`^denom_` (nomes próprios), `^ds_`
  (descrições texto livre), `^email`/`^logradouro`/`^compl`/
  `^bairro`/`^mun($|_)`/`^municipio_` (endereço).
- **Tabelas `meta_status: missing`**: excluídas (declarar codelist sem
  ancoragem CVM violaria “se vem da CVM, fica como na CVM”).

------------------------------------------------------------------------

## 11. Objetivos do projeto

- **Gate de qualidade**: rOpenSci via review formal em
  <https://github.com/ropensci/software-review>. Ancora todo o trabalho
  enquanto princípio de design — decisões que não passem o filtro “isso
  ajuda ou atrapalha a aceitação rOpenSci?” devem ser rejeitadas.
- **Timing de submissão** (decisão de 2026-05-28): a submissão ao
  rOpenSci ocorre **ao fim do ciclo de desenvolvimento, após v1.0**, com
  os 5 fetchers funcionais e os 18 grupos CKAN cobertos — não como etapa
  intermediária.
- **CRAN**: permanece **acoplado ao aceite rOpenSci**; rOpenSci submete
  em nome do mantenedor quando aceito.
- **The R Journal**: paper sobre o pacote, **somente após o aceite
  rOpenSci**.

Sequenciamento canônico em `ROADMAP.md`, seção “Fim do ciclo — submissão
rOpenSci, CRAN e publicação”.
