# cvmdata v0.2 — documento de decisão (planejamento)

> Rodada de planejamento da v0.2 (companhias, parte 2). Análogo a
> `cvmdata_arquitetura_grupos_decisao_v2.md`. Base empírica (CKAN
> resources, METAs, amostras 2024) em
> `cvmdata_v0-2_fase1_verificacao_empirica.md`.
>
> **Status**: pronto para revisão de Sidney. Implementação derivada
> dele em sessões Claude Code separadas (ver §5).
>
> Data: 2026-05-28. Origem: rodada solicitada por
> `cvmdata_rodada_v0-2_planejamento_prompt.md`.

---

## 1. Sumário executivo

A v0.2 adiciona **4 datasets** ao grupo `companhias`: `cgvn`, `vlmo`,
`fca`, `ipe`. Todos via `issuer_fetch()` já existente. **Sem mudança
arquitetural; sem fetcher novo.**

**Decisões fechadas pela rodada:**

| § | Tema | Decisão |
|:-:|:-:|---|
| 3.1 | Schemas | 15 tabelas no total (FCA 10 + VLMO 2 + CGVN 2 + IPE 1). Convenção de header herdada da v0.1 (`fca/submissao` clássica; demais FRE-detail-like). |
| 3.2 | IPE manifesto | Tabela única `ipe/ipe`, sem `submissao` separado. Sem download de PDFs. Sem dedup-por-versao. |
| 3.3 | VLMO identidade | Insiders opacos por design CVM (só categoria). `issuer` filtra companhia emissora. Sem novo identificador de pessoa física. |
| 3.4 | CGVN praticas | Modelo "pratique ou explique" direto. Codelists: `Capitulo` (5), `Principio` (30), `Pratica_Adotada` (4). |
| 3.5 | FCA × CAD | FCA = histórico versionado anual; CAD = snapshot atual sem versão. Sem dedup automático entre os dois — documentar relação na vignette. |
| 3.6 | `report_type` | Não se aplica a nenhum dataset v0.2. Comportamento atual do `issuer_fetch` (aborta se passado) cobre. |
| 3.7 | Ticker B3 | **Lookup ticker → CNPJ via `fca/valor_mobiliario`** (alt b do prompt). Não usa fonte externa. |
| 3.8 | Subdivisão | **Monobloco v0.2.0**, com 4 sessões Claude Code internas: **CGVN → VLMO → FCA → IPE**. |
| 3.9 | Snapshots/mirror/testes | Estender matrix `(group, dataset)` do `etl-mirror.yaml` para 8 entradas; regenerar snapshots; fixtures pequenas e reais por dataset. |

**Pendências para Sidney decidir antes da implementação** (§6):
nenhuma bloqueante. Itens listados em §6 são pequenos ajustes
ergonômicos.

---

## 2. Verificação empírica (resumo)

Detalhado em `cvmdata_v0-2_fase1_verificacao_empirica.md`.
Destaques que orientaram as decisões abaixo:

- **CKAN serve 2021–2026** para os 4 datasets (janela de retenção).
  Histórico anterior depende exclusivamente do mirror.
- **VLMO não tem variante individual** — só `_con`. `report_type` não
  se aplica.
- **`departamento_acionistas` está vazio em 2024 e 2025** (era 546
  linhas em 2023). Mudança regulatória; reader precisa tolerar
  `nrow == 0L`.
- **`Codigo_Negociacao` (ticker B3) está em `fca/valor_mobiliario`**:
  408 CNPJs com ticker / 670 com valor mobiliário declarado / 1023
  linhas totais em 2024. Cobre 100% das companhias com ações
  negociadas em bolsa.
- **VLMO opaco para insiders**: detail tem `Tipo_Cargo` (5 categorias),
  `Tipo_Empresa` (3) e nome de empresa controladora em `Empresa`, mas
  **sem CPF**. Identidade individual fora do escopo do dado.

---

## 3. Decisões

### 3.1 Schemas por dataset

Os YAMLs vão em `inst/extdata/schemas/companhias/<dataset>/<table>.yaml`.
Conteúdo decidido aqui; escrita real na sessão de implementação.

#### 3.1.1 FCA — 10 tabelas

| YAML | n_campos | `temporal_partitioning` | `first_year` | `meta_status` | Convenção | Transformações |
|---|---|---|---|---|---|---|
| `submissao.yaml` | 9 | yearly | 2021 | available | clássica | `keep_latest_version` por `(cnpj_cia, dt_refer)` |
| `auditor.yaml` | 15 | yearly | 2021 | available | FRE-detail | `keep_latest_version` por `(cnpj_companhia, data_referencia)` |
| `canal_divulgacao.yaml` | 7 | yearly | 2021 | available | FRE-detail | `keep_latest_version` |
| `departamento_acionistas.yaml` | 23 | yearly | 2021 | available | FRE-detail | `keep_latest_version`. **Nota: vem vazia desde 2024.** |
| `dri.yaml` | 26 | yearly | 2021 | available | FRE-detail | `keep_latest_version` |
| `endereco.yaml` | 21 | yearly | 2021 | available | FRE-detail | `keep_latest_version` |
| `escriturador.yaml` | 24 | yearly | 2021 | available | FRE-detail | `keep_latest_version` |
| `geral.yaml` | 26 | yearly | 2021 | available | FRE-detail | `keep_latest_version` |
| `pais_estrangeiro_negociacao.yaml` | 7 | yearly | 2021 | available | FRE-detail | `keep_latest_version` |
| `valor_mobiliario.yaml` | 18 | yearly | 2021 | available | FRE-detail | `keep_latest_version` |

URL pattern (idem ITR/DFP/FRE):
`dados.cvm.gov.br/dados/CIA_ABERTA/DOC/FCA/DADOS/fca_cia_aberta_{year}.zip`.
META URL:
`dados.cvm.gov.br/dados/CIA_ABERTA/DOC/FCA/META/fca_cia_aberta.zip`.
Encoding: `ISO-8859-1`. Delimitador: `;`.

#### 3.1.2 VLMO — 2 tabelas

| YAML | n_campos | `temporal_partitioning` | `first_year` | `meta_status` | Convenção | Transformações |
|---|---|---|---|---|---|---|
| `submissao.yaml` | 12 | yearly | 2021 | available | FRE-detail (`Codigo_CVM`, `Categoria`, `Tipo`, …) | `keep_latest_version` por `(cnpj_companhia, data_referencia)` |
| `consolidado.yaml` (era `con`; ver Sessão 11) | 17 | yearly | 2021 | available | FRE-detail-like sem `Codigo_CVM` | **Sem `keep_latest_version`** — é tabela evento-por-linha; manter versões |

URL pattern:
`.../DOC/VLMO/DADOS/vlmo_cia_aberta_{year}.zip`.
META URL: `.../DOC/VLMO/META/meta_vlmo_cia_aberta.zip`.

Nome `submissao` é mantido por consistência com ITR/DFP/FRE/FCA,
mesmo com 12 campos (≠ 9 clássicos). O contrato semântico é o mesmo:
header de um documento + lookup CD_CVM → CNPJ para o detail.

#### 3.1.3 CGVN — 2 tabelas

| YAML | n_campos | `temporal_partitioning` | `first_year` | `meta_status` | Convenção | Transformações |
|---|---|---|---|---|---|---|
| `submissao.yaml` | 12 | yearly | 2021 | available | FRE-detail | `keep_latest_version` por `(cnpj_companhia, data_referencia)` |
| `praticas.yaml` | 11 | yearly | 2021 | available | FRE-detail | `keep_latest_version` por `(cnpj_companhia, data_referencia, id_item)` |

URL pattern:
`.../DOC/CGVN/DADOS/cgvn_cia_aberta_{year}.zip`.
META URL: `.../DOC/CGVN/META/meta_cgvn_cia_aberta.zip`.

#### 3.1.4 IPE — 1 tabela

| YAML | n_campos | `temporal_partitioning` | `first_year` | `meta_status` | Convenção | Transformações |
|---|---|---|---|---|---|---|
| `ipe.yaml` | 13 | yearly | 2021 | available | FRE-detail | **Sem `keep_latest_version`** — manifesto |

URL pattern:
`.../DOC/IPE/DADOS/ipe_cia_aberta_{year}.zip`.
META URL: `.../DOC/IPE/META/meta_ipe_cia_aberta.txt` (TXT, não ZIP).

#### 3.1.5 Identifiers → character — extensão da lista do reader

`R/util-csv-cvm.R` lista atualmente:
`c("cnpj_cia", "cd_cvm", "cep", "tel", "ddd_*", "cpf", "id_documento",
"cnpj_companhia")`.

Verificar cobertura por regex dos novos campos:

| Campo v0.2 | Padrão de regex atual cobre? | Decisão |
|---|---|---|
| `codigo_cvm` | parcial (não casa `^cd_`/`^cnpj`) | Adicionar `codigo_cvm` à lista |
| `codigo_cvm_auditor` | `^codigo_cvm` se adicionado acima | OK por prefixo |
| `cnpj_escriturador` | `^cnpj` | OK |
| `cpf_cnpj_auditor` | `^cpf` ou `^cnpj` | OK (qualquer um) |
| `cpf_responsavel_tecnico` | `^cpf` | OK |
| `cpf_responsavel` | `^cpf` | OK |
| `protocolo_entrega` | não cobre | Adicionar `protocolo_entrega` |
| `id_item` | `^id_` | OK |
| `ddi_telefone`, `ddi_fax` | parcial (atual é `ddd_*`) | Estender para `ddd_*` ∪ `ddi_*` |
| `caixa_postal` | não cobre | Adicionar `caixa_postal` |
| `codigo_negociacao` | `^codigo_` se aceitar prefixo | Adicionar `codigo_negociacao` (ticker) |

**Recomendação**: na sessão de implementação, refatorar a lista do
reader para um vetor explícito de **exact match** + um conjunto de
prefixos (`^cnpj`, `^cpf`, `^codigo_`, `^cd_`, `^ddi_`, `^ddd_`,
`^id_`, `^protocolo`). Adicionar `caixa_postal` como exact match
porque não tem prefixo natural.

### 3.2 IPE — tratamento do manifesto

**Decisões:**

- **Tabela única `ipe/ipe`** com os 13 campos do CSV anual. Sem
  `submissao` separado — o próprio CSV é o manifesto.
- **`issuer` filtra** por `cnpj_companhia` ou `codigo_cvm` (campos
  nativos do CSV). Busca textual cai em `nome_companhia`.
- **OCR fora de escopo permanente**. `link_download` é exposto como
  coluna de URL no tibble; o usuário decide se faz download.
- **Cobertura temporal**: `first_year: 2021` (verdade atual do
  portal). Mirror próprio acumula histórico organicamente. Vignette
  da v0.2 explica.
- **Sem `keep_latest_version`**: cada linha é um documento publicado
  evento-por-linha; manter integridade do manifesto. Se duas linhas
  com mesma `(cnpj_companhia, data_referencia, categoria, tipo,
  protocolo_entrega)` aparecerem em versões diferentes, é
  intencional — o usuário pode filtrar com `dplyr` se quiser.
- **Sobreposição com VLMO**: documentar na vignette. IPE indexa
  publicações (com `link_download`); VLMO traz os dados estruturados
  do mesmo formulário (art. 11). Recomendação ao usuário: para a
  movimentação efetiva, usar VLMO; para encontrar o PDF da
  publicação, usar IPE.

**Alternativas consideradas:**

- (a) **Dedup automático no `ipe` para manter só a última versão por
  protocolo**: rejeitado. Quebra o contrato "manifesto integral".
  Usuário pode fazer no consumo.
- (b) **Tabela separada `ipe/submissao`**: rejeitado. Não há
  estrutura de duas tabelas na fonte; criar uma vazia para coerência
  com FCA/VLMO/CGVN só polui o discovery.

### 3.3 VLMO — modelo de identidade

**Decisão**: `issuer` filtra **a companhia emissora** (via
`cnpj_companhia` em `submissao` e `con`, ou via `codigo_cvm` em
`submissao` com lookup CD_CVM → CNPJ para `con` que não tem
`Codigo_CVM`). Linhas do `con` representam movimentações de insiders
**agregadas por categoria** (`Tipo_Cargo`), sem identidade individual.

**Pessoas físicas (insiders) ficam opacas por design da CVM** — não
há CPF de administrador no detail. **Nenhum identificador novo
adicionado para PF** (a lista do reader não cresce por causa disso).

**Pessoas jurídicas** (controladores PJ) aparecem com nome em
`Empresa` + `Tipo_Empresa ∈ {Companhia, Controlada, Controladora}`.
Sem CNPJ próprio — só nome. Usuário que queira agrupar por
controlador PJ faz por texto, sem chave estável.

**Alternativas consideradas:**

- (a) **Adicionar argumento `insider` ao `issuer_fetch` para filtrar
  por `Tipo_Cargo`**: rejeitado por dois motivos. (i) extensão de API
  específica de um dataset viola o contrato `issuer_fetch` genérico;
  (ii) filtro categórico simples já é trivial via `dplyr` no
  tibble retornado.
- (b) **Documentar a opacidade na vignette VLMO**: aceito. Mensagem
  clara sobre o que VLMO entrega vs o que não entrega.

### 3.4 CGVN — estrutura "pratique ou explique"

**Decisão**: 2 tabelas, modelo direto.

- `cgvn/submissao` (12 campos): header do informe ICBGC anual por
  companhia.
- `cgvn/praticas` (11 campos): uma linha por prática recomendada do
  código. `ID_Item` (54 distintos, formato `N.N.N`) identifica a
  prática; `Capitulo` (5) e `Principio` (30) são metadados
  hierárquicos; `Pratica_Adotada` (Sim/Não/Parcialmente/Não se
  Aplica) é o veredito; `Explicacao` é texto livre quando aplicável.

**Codelists confirmadas** (verificação empírica §12.3):
`Capitulo` (5), `Principio` (30), `Pratica_Adotada` (4).

**Codelist a NÃO incluir**: `Explicacao` (texto livre).

### 3.5 FCA × CAD — relação documentada

**Decisão**: manter como datasets separados com semânticas distintas.

- **CAD (`cad/companhias`)**: snapshot **atual** (estado corrente do
  cadastro CVM). Sem `Versao`, sem `Data_Referencia` por linha.
  Atualizado conforme CVM publica.
- **FCA (`fca/geral`, entre outras)**: histórico **versionado anual**
  do formulário cadastral entregue pela companhia, com `Versao` e
  `Data_Referencia`. Cobertura no portal: 2021+.

**Quando usar qual** (vignette):

- Usuário quer o estado **agora**: CAD.
- Usuário quer reconstruir o histórico declarado: FCA.
- Usuário quer comparar declaração FCA com snapshot CAD: faz join
  manual em `cnpj_cia` (no CAD) ↔ `cnpj_companhia` (no FCA) via
  `cnpj_clean()`.

**Sem dedup automático entre os dois.** São datasets que coexistem
com chaves de identidade compatíveis mas semânticas diferentes.

**Alternativas consideradas:**

- (a) **Renomear `cad` para `cad_snapshot` ou similar para
  diferenciar**: rejeitado. `cad` é o nome publicado pela CVM
  (`cia_aberta-cadastro`); a régua "se vem da CVM, fica como na CVM"
  prevalece sobre clareza ergonômica.
- (b) **Deprecar `cad` em favor de `fca/geral`**: rejeitado. CAD tem
  cobertura temporal diferente (snapshot atual completo, sem
  versão), e o caso de uso "estado atual" é legítimo. Deprecar custa
  documentação sem ganho.

### 3.6 `report_type`

**Decisão**: **não se aplica a nenhum dataset v0.2.** Comportamento
atual do `issuer_fetch` (aborta `cvmdata_error_input` quando
`report_type` é passado a tabela sem variantes) cobre os 4 datasets
sem mudança.

VLMO `_con` é o **único formato existente** do formulário, não o eixo
`ind/con` das demonstrações contábeis. Tratado como tabela única.

### 3.7 Ticker B3 — lookup nativo via FCA

**Decisão**: implementar **lookup ticker B3 → (CNPJ, CD_CVM) via
`fca/valor_mobiliario`** — alt (b) do prompt. Sem dependência
externa, sem violar o fora-de-escopo B3 (endpoints B3 permanecem
inacessíveis).

**Mecânica:**

- `issuer_fetch` ganha detecção de padrão ticker B3 em `issuer`.
  Pattern: `^[A-Z]{4}[0-9]{1,2}[A-Z]?$` (PETR4, VALE3, BBDC11,
  HGLG11, ITSA4F — última letra opcional para BDR/fracionado). Vai
  além do detector atual (CNPJ/CD_CVM/texto).
- Quando detecta ticker, dispara lookup interno
  `resolve_ticker_via_fca()`:
  1. Carrega `fca/valor_mobiliario` do ano corrente
     (`cvm_dataset_years("fca") |> max()`).
  2. Filtra por `Codigo_Negociacao == ticker` (com `Data_Fim_Negociacao`
     nula ou ainda no futuro para excluir tickers extintos).
  3. Retorna o `CNPJ_Companhia` correspondente.
  4. Aplica o filtro normal `cnpj_companhia`/`cnpj_cia` à tabela alvo.
- Lookup é cacheado por sessão (mesmo padrão do `mirror_list_assets`).
- Ticker não encontrado: aborta com `cvmdata_error_input` ("ticker
  não localizado em `fca/valor_mobiliario` do ano `{Y}`. Verifique
  ortografia ou use CNPJ/CD_CVM").

**Cobertura empírica (§12.4)**: 408 CNPJs cobrem 100% das companhias
com ações em bolsa B3. Companhias com apenas debêntures/balcão não
têm ticker — comportamento correto, não silent-fail.

**Alternativas rejeitadas:**

- (a) **Mapa estático embarcado em `inst/extdata/`** derivado de
  fonte aberta: rejeitado. Mapa fica desatualizado entre releases;
  novo IPO entre v0.2.0 e v0.2.1 fica invisível. Dependência de
  fonte externa que precisaria de processo de manutenção.
- (c) **Adiar suporte a ticker para v0.3+**: rejeitado. Achado de
  §12.4 destrava a (b); adiar perde valor para o usuário sem motivo.

### 3.8 Subdivisão da v0.2

**Decisão**: **monobloco v0.2.0**. Ciclo de dev `0.1.0.9000` continua
acumulando trabalho; release único v0.2.0 ao fim. Subdivisão em
v0.2.1/v0.2.2/etc rejeitada porque o pacote tem zero usuários
externos hoje (decisão de timing rOpenSci de 2026-05-28 mantém o
projeto fora de circulação até pós-v1.0).

**Sequência tracer-bullet** das sessões Claude Code de implementação:

| Sessão | Dataset | Por quê nessa ordem |
|---|---|---|
| Sessão 10 | **CGVN** | O mais simples: 2 tabelas FRE-detail-like puras, codelists pequenas e bem comportadas, sem `submissao` clássico, sem variantes, sem ticker. Valida o pipeline `<group>/<dataset>/<table>.yaml` para um dataset 100% novo desde Sessão 05. |
| Sessão 11 | **VLMO** | Continua com 2 tabelas; introduz codelist categórica rica (`Tipo_Cargo`, `Tipo_Movimentacao` etc.) e a decisão de "sem `keep_latest_version`" para tabela evento-por-linha. Pipeline FRE-detail completo. |
| Sessão 12 | **FCA** | 10 tabelas + 1 com convenção clássica (`submissao` 9 campos) + ticker B3 + tabela vazia (`departamento_acionistas`). Maior superfície. Antes de IPE para que tabela vazia + ticker estejam testados. |
| Sessão 13 | **IPE** | Manifesto sem `submissao`, sem `keep_latest_version`, 50k linhas/ano, sobreposição conceitual com VLMO. Quando chega, todas as decisões de produto v0.2 já estão fechadas. |

**Gate por sessão**: `devtools::check()` 0E/0W/0N, lint clean,
cobertura ≥ 90%. Snapshots de dicionário/codelist regenerados ao fim
de cada sessão (não acumulado).

### 3.9 Snapshots, mirror e testes

**ETL mirror — matrix `(group, dataset)` estendida** em
`.github/workflows/etl-mirror.yaml`: hoje 4 entradas (companhias × {cad,
dfp, itr, fre}); v0.2 adiciona 4 → **8 entradas totais**. Sem mudança
estrutural no workflow; só dado na matriz.

**Capacidade do mirror** — projeção (CSV → parquet Snappy, ~5×
compressão):

- CGVN: 22k linhas/ano × 11 cols × ~80 bytes = ~3 MB/ano CSV → ~600
  KB/ano parquet
- VLMO: 61k linhas/ano (con) + 6k (submissao) = ~17 MB/ano CSV →
  ~3.5 MB/ano parquet
- FCA: ~8k linhas distribuídas em 10 tabelas, várias com muitas
  colunas; ~5 MB/ano CSV → ~1 MB/ano parquet
- IPE: 50k linhas × 13 cols × ~150 bytes = ~100 MB/ano CSV → ~20
  MB/ano parquet

**Total novo (5 anos × 4 datasets) ≈ 600 MB parquet.** Folga
confortável no limite GitHub Releases (2 GB/asset; 100 GB/release).
IPE é o maior contribuidor; auditar antes do primeiro publish.

**Snapshots embarcados**:

- `inst/extdata/cvm_dictionary_snapshot.csv`: regenerar com linhas
  dos 4 datasets (group = "companhias", coluna `meta_status` ⊂
  {available}, todas com META). Gerador
  `data-raw/build-dictionary-snapshot.R` já lê de
  `inst/extdata/schemas/companhias/`; após escrever os YAMLs, basta
  rerodar.
- `inst/extdata/cvm_codelists_snapshot.csv`: regenerar idem. Os
  campos categóricos catalogados em §12.2/§12.3 e listados em §5 do
  sub-doc Fase 1 são os candidatos. Critério atual de inclusão
  (`varchar`, `tamanho < 200`, ≤ 50 distintos, exclusões por prefixo)
  cobre tudo sem ajuste.

**Fixtures de teste**:

- Cada dataset ganha **1 ZIP fixture** com subset de companhias
  (~3-5 CNPJs) para 1 ano. Sugestão de subset: BCO BRASIL
  (`001023`), MAGAZINE LUIZA (`022470`) — mesmas usadas em
  ITR/DFP/FRE — para coerência com fixtures existentes.
- FCA fixture exercita as 10 tabelas, incluindo
  `departamento_acionistas` vazia.
- VLMO fixture inclui múltiplas linhas por `(cnpj, data_ref,
  data_movimentacao)` para testar que **não** há dedup por versão.
- CGVN fixture cobre as 4 categorias de `Pratica_Adotada`.
- IPE fixture inclui pelo menos uma linha de cada `Categoria` mais
  comum (movimentação art. 11, comunicado ao mercado, fato relevante).

Geradas por `data-raw/build-mirror-test-fixtures.R` (estender). Cada
ZIP fixture acompanha `*.meta.json` com origem. Cap de tamanho:
~200 KB por fixture (parquet equivalente após reduzir).

---

## 4. Schemas propostos — resumo tabular

(Detalhes de campo por tabela vão para os YAMLs nas sessões 10-13.)

### FCA

```
companhias/fca/
├── submissao.yaml              (9 fields, classical, keep_latest_version)
├── auditor.yaml                (15 fields, FRE-detail, keep_latest_version)
├── canal_divulgacao.yaml       (7 fields, FRE-detail)
├── departamento_acionistas.yaml (23 fields, FRE-detail; empty since 2024)
├── dri.yaml                    (26 fields, FRE-detail)
├── endereco.yaml               (21 fields, FRE-detail)
├── escriturador.yaml           (24 fields, FRE-detail)
├── geral.yaml                  (26 fields, FRE-detail)
├── pais_estrangeiro_negociacao.yaml (7 fields, FRE-detail)
└── valor_mobiliario.yaml       (18 fields, FRE-detail; carries ticker)
```

### VLMO

```
companhias/vlmo/
├── submissao.yaml    (12 fields, FRE-detail-like with Codigo_CVM, keep_latest_version)
└── consolidado.yaml  (17 fields, FRE-detail-like without Codigo_CVM, no dedup;
                       renamed from `con` — reserved device name on Windows)
```

### CGVN

```
companhias/cgvn/
├── submissao.yaml  (12 fields, FRE-detail, keep_latest_version)
└── praticas.yaml   (11 fields, FRE-detail, keep_latest_version with id_item key)
```

### IPE

```
companhias/ipe/
└── ipe.yaml        (13 fields, FRE-detail-like, no submissao, no dedup)
```

**Total**: 15 novas tabelas, 4 novos datasets.

---

## 5. Plano tracer-bullet — sessões Claude Code

Cada sessão é independente; gate `devtools::check() == 0E/0W/0N`,
lint clean, cobertura ≥ 90%. Cada uma deixa o pacote pronto para
release intermediário se necessário (mas só releva v0.2.0 ao final
da Sessão 13).

### Sessão 10 — CGVN — **concluída**
- [x] Escrever `inst/extdata/schemas/companhias/cgvn/{submissao,praticas}.yaml`.
- [x] Baixar e armazenar fixture `cgvn_cia_aberta_2024.zip` em
  `tests/testthat/fixtures/` (38 KB, BB+MGLU subset, 4 categorias de
  `Pratica_Adotada`).
- [x] Testes: tracer end-to-end, codelists (`cvm_codelist`), dedup
  `keep_latest_version` por `(cnpj_companhia, data_referencia, id_item)`,
  lookup CD_CVM via submissao (CGVN/submissao tem `codigo_cvm` e
  `cnpj_companhia`, não `cd_cvm` / `cnpj_cia`; helper `cdcvm_col()`
  generalizado), `identifier_columns()` unit tests.
- [x] Estender `etl-mirror.yaml` matrix com `(companhias, cgvn)`.
- [x] Regenerar `cvm_dictionary_snapshot.csv` e
  `cvm_codelists_snapshot.csv` para incluir CGVN.
- [x] `NEWS.md`: entrada sob v0.1.0.9000 (New features + Internal:
  refator do reader para prefix-based + exact-match;
  `tx_keep_latest_version` aceita `keys:`; `cdcvm_col()` helper).
- [x] Gate: `devtools::check() --as-cran` 0E/0W/0N (58.7s);
  lint clean; testes 819 PASS / 0 FAIL / 1 SKIP (Windows);
  cobertura 92.79%.

### Sessão 11 — VLMO — **concluída**
- [x] Escrever `inst/extdata/schemas/companhias/vlmo/{submissao,consolidado}.yaml`.
  **Rename `con` → `consolidado`**: a tabela detail NÃO pode chamar-se
  `con` porque `con.yaml` colide com o nome de dispositivo reservado
  `CON` do Windows (recusado pelo OneDrive). O nome de tabela é decisão
  do pacote (a CVM só nomeia o arquivo, não a tabela), então a régua "se
  vem da CVM, fica como na CVM" não é violada. O `cvm_file_pattern`
  continua apontando para o CSV real `vlmo_cia_aberta_con_{year}.csv`.
- [x] Fixture `vlmo_cia_aberta_2024.zip` (~5 KB, BB+MGLU subset) +
  `.meta.json`; `build_vlmo_raw_fixture()` em
  `data-raw/build-mirror-test-fixtures.R` (modelo `build_cgvn`).
- [x] Testes (`test-issuer-fetch-vlmo.R`): tracer end-to-end de
  `submissao` + `consolidado`, filtro por CNPJ, lookup CD_CVM → CNPJ via
  `vlmo/submissao` (padded + unpadded; `consolidado` não tem
  `codigo_cvm`), ausência de `keep_latest_version` em `consolidado`
  (data frame sintético interno), discovery, codelist `tipo_cargo` (5
  categorias), dictionary 12/17 linhas, `report_type` aborta.
- [x] Estender `etl-mirror.yaml` matrix com `(companhias, vlmo)` +
  choice list.
- [x] Regenerar `cvm_dictionary_snapshot.csv` (+29 linhas) e
  `cvm_codelists_snapshot.csv` (+56 linhas) — diff só adiciona VLMO.
- [x] `NEWS.md`: entrada sob v0.1.0.9000 (New features).
- [x] Gate verde (`devtools::check()` 0E/0W/0N, lint clean,
  cobertura ≥ 90%).

### Sessão 12 — FCA — **concluída**
- [x] Escrever os 10 YAMLs FCA em
  `inst/extdata/schemas/companhias/fca/` (`submissao` clássico de 9
  campos + 9 detail FRE-detail). META zip confirmado em disco:
  `fca_cia_aberta.zip` (NÃO prefixado com `meta_`), com entries
  internas `meta_fca_cia_aberta[_<table>].txt`. `expected_field_count`
  por tabela validado contra o CSV 2024 real (validate = "warn", zero
  divergência).
- [x] **Item §3.1.5 (estender `R/util-csv-cvm.R` com identifiers
  novos) NÃO foi necessário**: o refator prefix-based + exact-match da
  Sessão 10 já cobre todos os identifiers da FCA
  (`codigo_cvm_auditor`, `codigo_negociacao`, `cnpj_escriturador`,
  `cpf_responsavel_tecnico`, `caixa_postal`, etc.) sem mudança de
  código. O item do canônico foi redigido antes do refator da S10.
- [x] **Implementar `resolve_ticker_via_fca()` + `ticker_lookup_table()`
  + `is_active_ticker()`** e o detector regex de ticker
  (`^[A-Z]{4}[0-9]{1,2}[A-Z]?$`) em `classify_issuer_tokens()`
  (`R/api-issuer-fetch.R`). Detecção após CNPJ/CD_CVM; cache por
  sessão keyed por ano; ticker inexistente aborta
  `cvmdata_error_input`. Filtra apenas tickers ativos
  (`data_fim_negociacao` nulo/futuro). Alternativa (b) da §3.7 — sem
  fonte externa.
- [x] Fixture `fca_cia_aberta_2024.zip` (~5 KB, BB+MGLU subset) com as
  10 tabelas, incluindo `departamento_acionistas` só-header e os
  tickers BBAS3/MGLU3 em `valor_mobiliario`; `.meta.json`.
  `build_fca_raw_fixture()` em `data-raw/build-mirror-test-fixtures.R`
  (com selector de target por CLI para gerar só a FCA em isolamento).
- [x] Testes (`test-issuer-fetch-fca.R`): tracer multi-tabela
  (submissao clássico + detail FRE-detail), filtro por CNPJ, lookup
  CD_CVM → CNPJ via `fca/submissao` (ponte clássico → FRE-detail,
  padded + unpadded), lookup ticker → CNPJ (case-insensitive) +
  abort de ticker inexistente, roteamento de tokens
  (ticker/CD_CVM/CNPJ/texto particionam o input),
  `departamento_acionistas` `nrow == 0L` sem aborto nos 3 modos
  validate, `report_type` aborta, discovery (10 tabelas),
  `cvm_dataset_years` mockado, dictionary 9/18/23 linhas.
- [x] Estender `etl-mirror.yaml` matrix com `(companhias, fca)` +
  choice list.
- [x] Regenerar `cvm_dictionary_snapshot.csv` (+176 linhas) e
  `cvm_codelists_snapshot.csv` (+218 linhas) — diff só adiciona FCA.
- [x] `NEWS.md`: entrada sob v0.1.0.9000 (New features) — dataset FCA
  + ticker B3 + nota de `departamento_acionistas` vazia.
- [x] Gate verde (`devtools::check()` 0E/0W/0N, lint clean,
  cobertura ≥ 90%).

### Sessão 13 — IPE — **concluída**
- [x] Escrever schema `ipe/ipe.yaml` (tabela única, 13 campos,
  FRE-detail-like com `Codigo_CVM` nativo, `transformations: []`).
  META confirmado em disco: `meta_ipe_cia_aberta.txt` **TXT plano**
  (sem `#entry`, ao contrário de FCA/VLMO/CGVN), parseia em blocos
  `Campo:`. `expected_field_count: 13` validado contra o CSV 2024 real
  (header bate exatamente).
- [x] **Item de refator do reader NÃO foi necessário**: o prefix-based
  + exact-match da Sessão 10 já cobre `codigo_cvm` (`^codigo_`) e
  `protocolo_entrega` (`^protocolo`) sem mudança de código.
- [x] Fixture `ipe_cia_aberta_2024.zip` (~15 KB, BB+MGLU subset, 330
  linhas, 27 categorias distintas), bem abaixo do cap de 200 KB;
  `.meta.json` registra as categorias incluídas.
  `build_ipe_raw_fixture()` em `data-raw/build-mirror-test-fixtures.R`
  (com `ipe` no selector de target por CLI).
- [x] Testes (`test-issuer-fetch-ipe.R`): tracer end-to-end de
  manifesto (13 campos, tipos), filtro por CNPJ, slice por `categoria`
  no tibble retornado, lookup CD_CVM **direto** padded+unpadded (IPE
  tem `codigo_cvm` nativo) + asserção de que **não** passa por
  submissao, **sem dedup automático** (df sintético de 3 versões
  sobrevive; contraste com schema que dedupa), ticker B3 → CNPJ via
  `fca/valor_mobiliario` (fixture FCA + IPE encenadas), `report_type`
  aborta, discovery (1 tabela), `cvm_dataset_years` mockado, dictionary
  13 linhas.
- [x] Estender `etl-mirror.yaml` matrix com `(companhias, ipe)` +
  choice list.
- [x] Regenerar `cvm_dictionary_snapshot.csv` (+13 linhas) e
  `cvm_codelists_snapshot.csv` (+29 linhas: `especie` 26 +
  `tipo_apresentacao` 3; `categoria`/`tipo` ficam de fora por > 50
  distintos no ano cheio; `assunto` é texto livre) — diff só adiciona
  IPE.
- [x] `NEWS.md`: entrada sob v0.1.0.9000 (New features) — dataset IPE
  (manifesto evento-por-linha, `codigo_cvm` nativo, sem dedup, OCR fora
  de escopo).
- [x] Vignette nova `vignettes/articles/ipe-vlmo.Rmd` + entrada no
  `_pkgdown.yml`; `getting-started.Rmd` (8 datasets + bloco IPE);
  `groups-overview.Rmd`; READMEs regenerados.
- [x] Gate verde (`devtools::check()` 0E/0W/0N, lint clean,
  cobertura ≥ 90%).

### Pós-Sessão 13 — release v0.2.0
- Auditoria final do mirror (primeiro publish dos 4 datasets novos).
- Bump `DESCRIPTION` para `0.2.0`.
- `NEWS.md`: seção `# cvmdata 0.2.0` consolidando.
- Tag git `v0.2.0` + GitHub Release.
- Reabrir ciclo `0.2.0.9000`.

---

## 6. Riscos e contingências

| Risco | Probabilidade | Impacto | Mitigação |
|---|---|---|---|
| Reader aborta em `nrow == 0L` (caso `fca/departamento_acionistas`) | Baixa (caminho atual provavelmente tolera) | Alto se acontecer (bloqueia FCA inteiro) | Teste de regressão na Sessão 12 antes de qualquer outro do FCA |
| Detector regex de ticker captura falso-positivo (palavra `PROVA` é 4 letras + 0 dígitos? não — precisa de dígito após; mas `MGLU3` é válido — verificar `^[A-Z]{4}[0-9]{1,2}[A-Z]?$`) | Média | Médio (erro de roteamento) | Aplicar regex **depois** de testar CNPJ/CD_CVM (já é a ordem natural). Adicionar teste com strings ambíguas. |
| Volume IPE no mirror cresce além do esperado | Baixa | Médio (artifact > 2 GB) | Particionar IPE por ano no parquet já é o default. Auditar tamanho no primeiro publish. |
| Mudança de schema CVM entre verificação (2026-05-28) e implementação | Baixa | Alto (schemas YAML errados) | Cada sessão de implementação refaz `validate = "warn"` contra dados reais antes de declarar `expected_field_count` definitivo. |
| Cardinalidade real de codelist > 50 em algum campo não-amostrado | Baixa | Baixo (filtro automático já exclui) | Não bloqueante; campo simplesmente fica fora da codelist. |
| `Codigo_Negociacao` em FCA não cobre BDRs / debêntures negociadas | Confirmado (~40% sem ticker) | Médio | Lookup aborta com mensagem clara orientando uso de CNPJ/CD_CVM. Documentado na vignette. |
| Política de retenção CVM aperta de 6 para 3 anos durante o ciclo | Baixa | Médio | Mirror próprio absorve. ETL semanal já cobre. |
| Janela 2021+ frustra usuário esperando histórico longo | Média | Baixo | Documentação clara na vignette + `cvm_dataset_years()` mostra o range real. |

---

## 7. Decisões fechadas

### Decisões principais da rodada

1. 15 novas tabelas em 4 datasets (FCA 10, VLMO 2, CGVN 2, IPE 1).
2. `first_year: 2021` para todos os 4 (janela do portal CVM hoje).
3. Convenção de cabeçalho: `fca/submissao` clássica; demais
   FRE-detail.
4. Sem `report_type` em nenhum dataset v0.2.
5. `keep_latest_version` em todos os submissao + FCA detail + CGVN
   praticas; **não** em `vlmo/con` e `ipe/ipe`.
6. Identidade dos insiders no VLMO permanece opaca (sem CPF, sem
   novo identificador no reader).
7. Ticker B3 via lookup interno em `fca/valor_mobiliario`. Sem fonte
   externa.
8. Monobloco v0.2.0 em 4 sessões Claude Code:
   CGVN → VLMO → FCA → IPE.
9. ETL mirror matrix passa de 4 para 8 entradas.
10. Fixtures pequenas e reais por dataset (~200 KB cada).

### Pendências ergonômicas fechadas em 2026-05-28

Pequenas decisões de processo confirmadas após a redação inicial,
todas com Sidney optando pelo default proposto:

11. **Refator da lista de identifiers do reader na Sessão 10**:
    `R/util-csv-cvm.R` passa a aplicar regra **prefix-based**
    (`^cnpj`, `^cpf`, `^codigo_`, `^cd_`, `^ddi_`, `^ddd_`, `^id_`,
    `^protocolo`) + lista de **exact-match** para os esquisitos
    (`caixa_postal`, `tel`). Cobre v0.1 sem regressão e absorve os
    identifiers novos da v0.2 sem código adicional.
12. **Vignette dedicada `ipe-vlmo.Rmd`** (Sessão 13): a sobreposição
    IPE × VLMO ganha capítulo próprio no pkgdown, não nota dentro da
    vignette geral.
13. **Detecção de ticker na Sessão 12** (junto com FCA): o
    `resolve_ticker_via_fca()` e o detector regex de ticker no
    dispatcher do `issuer` entram no mesmo passe que cria os schemas
    FCA. Sem sessão extra pós-13.
14. **Cobertura pré-2021 não será resgatada**: o robô ETL semanal
    captura 2021+ no primeiro publish pós-v0.2 (próxima retirada da
    janela CVM é em 2027 — tempo de sobra). Sem rodada manual extra,
    sem dependência de archive.org / fonte externa.

### Pendências fora do escopo desta rodada (para registro)

- v0.3: `cia_estrangeira-*` (similar arquitetura), `incentivada-*` (se
  aplicável a `issuer_fetch`), `eventos-societarios-*`.
- v0.4: `fund_fetch()` implementação plena.
- Mudança da política de timing rOpenSci se a comunidade pedir
  release antecipado (decisão do mantenedor).

---

## 8. Sequência de implementação

Todas as decisões fechadas. Implementação encadeada por:

1. Sessão 10 (CGVN) — prompt em `PROMPT_CLAUDE_CODE_sessao_10_cgvn.md`.
2. Sessão 11 (VLMO) — prompt derivado deste doc após Sessão 10
   aterrissar.
3. Sessão 12 (FCA + ticker B3) — idem.
4. Sessão 13 (IPE + vignette `ipe-vlmo.Rmd`) — idem.
5. Pós-Sessão 13: release v0.2.0 (bump DESCRIPTION, tag, mirror
   publish final, NEWS consolidado).
