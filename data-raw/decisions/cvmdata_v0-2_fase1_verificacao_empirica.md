# Rodada v0.2 — Fase 1: verificação empírica

> Sub-documento de trabalho. Insumo para a Fase 2 (decisões §3.1–§3.9 do
> prompt `cvmdata_rodada_v0-2_planejamento_prompt.md`). Quando a Fase 2
> fechar, este arquivo é consolidado no documento de decisão canônico
> `cvmdata_v0-2_planejamento_decisao.md` (ou removido como rascunho).
>
> Data da verificação: 2026-05-28. Fonte para todas as afirmações neste
> documento: CKAN API do portal `dados.cvm.gov.br` + METAs + amostras
> reais dos CSVs do ano 2024.

## 0. Sumário do que mudou em relação ao prompt da rodada

Achados que reorganizam as decisões §3 antes de a Fase 2 começar:

1. **Ticker B3 está disponível nativamente nos dados CVM** —
   `Codigo_Negociacao` é coluna do CSV
   `fca/valor_mobiliario`. Isso **viabiliza a alternativa (b) da §3.7**
   (resolução ticker → CNPJ via campo CVM, análoga ao lookup CD_CVM →
   CNPJ via `submissao` já implementado). Não há mais necessidade de
   importar mapa externo nem violar o fora-de-escopo B3.
2. **VLMO não expõe identidade individual de insiders** — só categoria
   (`Tipo_Cargo`, `Tipo_Empresa`, `Empresa`). Não há CPF; o `Empresa`
   parece nome PJ do controlador. Decisão §3.3 simplifica: `issuer`
   filtra a **companhia emissora**, e as linhas são movimentações de
   insiders **agregadas por essa companhia**. Sem novo identificador.
3. **VLMO não tem variante individual** — só `_con` (formulário
   consolidado), confirmado pelo CKAN, pelos METAs e pelo conteúdo do
   ZIP 2024. **`report_type` não se aplica.** Decisão §3.6 trivial.
4. **CKAN só serve 2021-2026** para os 4 datasets — janela de retenção
   do portal. O histórico mencionado no prompt (IPE desde 2003;
   demais desde 2010) **só existe** se o mirror próprio do pacote
   for preservado. Decisão §3.2 (cobertura IPE) deixa de ser "expor
   desde 2003" e vira "a janela é a do mirror".
5. **Sobreposição IPE × VLMO confirmada**: a coluna `Categoria` do IPE
   inclui "Valores Mobiliários Negociados e Detidos (art. 11 da Res.
   CVM 44)". IPE indexa o documento (com `Link_Download`); VLMO traz
   os dados estruturados do mesmo formulário. Documentar na vignette.

## 1. Inventário CKAN (verificado 2026-05-28)

Origem: `dados.cvm.gov.br/api/3/action/package_show?id=<slug>`.

| Dataset | Slug CKAN | Anos disponíveis | META URL |
|---|---|---|---|
| `fca` | `cia_aberta-doc-fca` | 2021-2026 | `dados.cvm.gov.br/dados/CIA_ABERTA/DOC/FCA/META/fca_cia_aberta.zip` |
| `vlmo` | `cia_aberta-doc-vlmo` | 2021-2026 | `dados.cvm.gov.br/dados/CIA_ABERTA/DOC/VLMO/META/meta_vlmo_cia_aberta.zip` |
| `cgvn` | `cia_aberta-doc-cgvn` | 2021-2026 | `dados.cvm.gov.br/dados/CIA_ABERTA/DOC/CGVN/META/meta_cgvn_cia_aberta.zip` |
| `ipe` | `cia_aberta-doc-ipe` | 2021-2026 | `dados.cvm.gov.br/dados/CIA_ABERTA/DOC/IPE/META/meta_ipe_cia_aberta.txt` |

URL padrão dos dados:
`dados.cvm.gov.br/dados/CIA_ABERTA/DOC/<XXXX>/DADOS/<xxxx>_cia_aberta_<YYYY>.zip`.
Cadência declarada: semanal para os quatro. Janela de retenção:
6 anos. `temporal_partitioning: yearly` em todos.

`fca`, `vlmo`, `cgvn` têm META **em ZIP** (com um arquivo TXT por
tabela dentro). `ipe` tem META **em TXT plano** (uma única tabela).

## 2. Tabelas por dataset (verificado por amostra 2024)

### 2.1 FCA — 10 CSVs por ano (1 submissao + 9 detail)

| Tabela do pacote | CSV no ZIP | n_fields | Convenção header | n_rows 2024 | Observações |
|---|---|---|---|---|---|
| `submissao` | `fca_cia_aberta_2024.csv` | 9 | **CLÁSSICA** (`CNPJ_CIA`, `DT_REFER`, `VERSAO`, `DENOM_CIA`, `CD_CVM`, `CATEG_DOC`, `ID_DOC`, `DT_RECEB`, `LINK_DOC`) | 1288 | Idêntica ao submissao ITR/DFP/FRE; reaproveita o transformer canônico |
| `auditor` | `fca_cia_aberta_auditor_2024.csv` | 15 | FRE-detail | 1042 | Tem `Codigo_CVM_Auditor`, `CPF_CNPJ_Auditor` (campo misto), `CPF_Responsavel_Tecnico` |
| `canal_divulgacao` | `fca_cia_aberta_canal_divulgacao_2024.csv` | 7 | FRE-detail | 1396 | — |
| `departamento_acionistas` | `fca_cia_aberta_departamento_acionistas_2024.csv` | 23 | FRE-detail | **1 (só header)** | Anomalia a confirmar em outro ano antes de declarar `expected_field_count` |
| `dri` | `fca_cia_aberta_dri_2024.csv` | 26 | FRE-detail | 1020 | Diretor de Relações com Investidores; tem `CPF_Responsavel` |
| `endereco` | `fca_cia_aberta_endereco_2024.csv` | 21 | FRE-detail | 1473 | Endereço da companhia |
| `escriturador` | `fca_cia_aberta_escriturador_2024.csv` | 24 | FRE-detail | 561 | Tem `CNPJ_Escriturador` |
| `geral` | `fca_cia_aberta_geral_2024.csv` | 26 | FRE-detail | 734 | "Estado corrente" do cadastro; tem `Codigo_CVM` |
| `pais_estrangeiro_negociacao` | `fca_cia_aberta_pais_estrangeiro_negociacao_2024.csv` | 7 | FRE-detail | 90 | Poucas linhas; só companhias com BDR/dual listing |
| `valor_mobiliario` | `fca_cia_aberta_valor_mobiliario_2024.csv` | 18 | FRE-detail | 1024 | **Tem `Codigo_Negociacao` (= ticker B3)**, `Mercado`, `Segmento`, `Entidade_Administradora` |

Anomalias para a Fase 2 confirmar antes de fechar schemas:

- `departamento_acionistas` está vazia em 2024 (apenas o cabeçalho).
  Pode ser opcional / baixa adesão. Verificar 2025 ou 2023 antes de
  declarar `expected_field_count` no YAML.

### 2.2 VLMO — 2 CSVs por ano (1 submissao + 1 detail consolidado)

| Tabela do pacote | CSV no ZIP | n_fields | Convenção header | n_rows 2024 | Observações |
|---|---|---|---|---|---|
| `submissao` | `vlmo_cia_aberta_2024.csv` | 12 | FRE-detail-like (`CNPJ_Companhia`, `Nome_Companhia`, `Data_Referencia`, `Versao`, `Codigo_CVM`, `Categoria`, `Tipo`, `Data_Entrega`, `Tipo_Apresentacao`, `Motivo_Reapresentacao`, `Protocolo_Entrega`, `Link_Download`) | 5931 | 12 campos — NÃO é o submissao de 9 campos clássico; **decidir o nome** (`submissao` para coerência ou `documento` para diferenciar) |
| `con` (consolidado) | `vlmo_cia_aberta_con_2024.csv` | 17 | FRE-detail-like (sem `Codigo_CVM` no detail) | 61485 | `Tipo_Empresa`, `Empresa`, `Tipo_Cargo`, `Tipo_Movimentacao`, `Descricao_Movimentacao`, `Tipo_Operacao`, `Tipo_Ativo`, `Caracteristica_Valor_Mobiliario`, `Intermediario`, `Data_Movimentacao`, `Quantidade`, `Preco_Unitario`, `Volume` |

Insider identity: o detail não traz CNPJ/CPF do insider; apenas
categoria (`Tipo_Cargo` ∈ {Controlador, Administrador, Conselho
Fiscal, …}) e — quando o insider é PJ — `Tipo_Empresa` + nome em
`Empresa`. **A identidade individual é opaca por design da CVM.**

### 2.3 CGVN — 2 CSVs por ano (1 submissao + 1 detail "praticas")

| Tabela do pacote | CSV no ZIP | n_fields | Convenção header | n_rows 2024 | Observações |
|---|---|---|---|---|---|
| `submissao` | `cgvn_cia_aberta_2024.csv` | 12 | FRE-detail-like (`CNPJ_Companhia`, `Data_Referencia`, `Versao`, `Nome_Empresarial`, `ID_Documento`, `Codigo_CVM`, `Categoria`, `Data_Entrega`, `Link_Download`, `Data_Inicio_Exercicio_Social`, `Data_Fim_Exercicio_Social`, `Motivo_Reapresentacao`) | 406 | Volume baixo: só 406 informes no ano — adesão limitada ao ICBGC |
| `praticas` | `cgvn_cia_aberta_praticas_2024.csv` | 11 | FRE-detail-like | 21493 | Modelo "pratique ou explique": `ID_Item`, `Capitulo`, `Principio`, `Pratica_Recomendada`, `Pratica_Adotada`, `Explicacao` |

`Pratica_Adotada` é a coluna semanticamente categórica (codelist).
`Explicacao` é texto livre (não-codelist). `Capitulo` e `Principio`
provavelmente são texto livre estruturado (a verificar
cardinalidade).

### 2.4 IPE — 1 CSV por ano (manifesto único)

| Tabela do pacote | CSV no ZIP | n_fields | Convenção header | n_rows 2024 | Observações |
|---|---|---|---|---|---|
| `ipe` (manifesto) | `ipe_cia_aberta_2024.csv` | 13 | FRE-detail-like (`CNPJ_Companhia`, `Nome_Companhia`, `Codigo_CVM`, `Data_Referencia`, `Categoria`, `Tipo`, `Especie`, `Assunto`, `Data_Entrega`, `Tipo_Apresentacao`, `Protocolo_Entrega`, `Versao`, `Link_Download`) | 50127 | Volume alto: ~50k documentos/ano; **OCR fora de escopo** (travado) |

`Categoria` do IPE inclui o art. 11 (VLMO) e outras categorias
estruturais. `Link_Download` aponta para PDFs no portal da CVM.
**Nenhuma tabela `submissao` separada** — o próprio CSV já é o
manifesto.

## 3. Convenções de header consolidadas

Duas convenções coexistem na v0.2 (já vistas na v0.1 entre
ITR/DFP submissao e FRE-detail):

**Convenção clássica** (9 campos) — só em `fca/submissao`:
`CNPJ_CIA`, `DT_REFER`, `VERSAO`, `DENOM_CIA`, `CD_CVM`,
`CATEG_DOC`, `ID_DOC`, `DT_RECEB`, `LINK_DOC`. Idêntico ao
ITR/DFP/FRE submissao do v0.1; pode reaproveitar o mesmo
transformer canônico e o lookup CD_CVM → CNPJ via `submissao` já
implementado.

**Convenção FRE-detail-like** — todas as demais (FCA detail × 9,
VLMO submissao+con, CGVN submissao+praticas, IPE):
`CNPJ_Companhia`, `Data_Referencia`, `Versao`, `Nome_*`,
`ID_Documento` ou `Protocolo_Entrega`. Variações:

- `Nome_Empresarial` em FCA detail e CGVN
- `Nome_Companhia` em VLMO e IPE
  Preservar como vem da CVM; não unificar.

- `ID_Documento` em FCA detail e CGVN; **ausente** em VLMO e IPE
  (substituído por `Protocolo_Entrega`)

- **VLMO e IPE submissao trazem `Codigo_CVM`** (12-13 campos no
  total); o detail VLMO `con` **não** traz `Codigo_CVM` → reativa o
  lookup CD_CVM → CNPJ via submissao quando o usuário filtra por
  CD_CVM contra `vlmo/con`.

## 4. Identificadores novos a adicionar ao reader → character

Lista canônica atual em `R/util-csv-cvm.R`:
`c("cnpj_cia", "cd_cvm", "cep", "tel", "ddd_*", "cpf", "id_documento", "cnpj_companhia")`.

Novos campos identificadores observados nos 4 datasets v0.2:

- `codigo_cvm` (VLMO submissao, CGVN submissao, IPE, FCA geral) —
  igual semântica a `cd_cvm`, nome diferente
- `codigo_cvm_auditor` (FCA auditor) — número da CVM do auditor
- `cnpj_escriturador` (FCA escriturador)
- `cpf_cnpj_auditor` (FCA auditor) — **campo misto** PF/PJ; aceita
  CPF ou CNPJ na mesma coluna
- `cpf_responsavel_tecnico` (FCA auditor)
- `cpf_responsavel` (FCA dri)
- `protocolo_entrega` (VLMO submissao, IPE)
- `id_item` (CGVN praticas) — chave da prática no código
- `ddi_telefone`, `ddi_fax` (FCA detail) — prefixo internacional
- `caixa_postal` (FCA endereco)
- `codigo_negociacao` (FCA valor_mobiliario) — **ticker B3**

A maioria casa com regex já existente no reader (`^cnpj`, `^cpf`,
`^codigo`, `^cd_`, `^ddi`, `^id_`, `^protocolo`); confirmar
cobertura ou estender a lista explicitamente na sessão de
implementação.

## 5. Codelist candidatos por dataset

Critério atual em `data-raw/build-codelists-snapshot.R`: `varchar`,
`tamanho < 200`, ≤ 50 valores distintos, excluindo identificadores
+ nomes próprios + descrições. Aplicando ao v0.2:

- **FCA detail**: `Tipo_Endereco`, `Tipo_Responsavel`,
  `Origem_Auditor`, `Sigla_UF`, `Sigla_Entidade_Administradora`,
  `Mercado`, `Segmento`, `Valor_Mobiliario` (no detail
  `valor_mobiliario`)
- **FCA geral**: `Categoria_Registro_CVM`, `Situacao_Emissor`,
  `Situacao_Registro_CVM`, `Especie_Controle_Acionario`,
  `Setor_Atividade`, `Pais_Origem`, `Pais_Custodia_Valores_Mobiliarios`
- **VLMO submissao**: `Categoria`, `Tipo`, `Tipo_Apresentacao`
- **VLMO con**: `Tipo_Cargo`, `Tipo_Empresa`, `Tipo_Movimentacao`,
  `Tipo_Operacao`, `Tipo_Ativo`, `Caracteristica_Valor_Mobiliario`
- **CGVN submissao**: `Categoria`
- **CGVN praticas**: `Pratica_Adotada` (P/E provável: "Adotada" /
  "Adotada parcialmente" / "Não adotada" / "Não aplicável"),
  `Capitulo`, `Principio` (cardinalidade a confirmar — pode ficar
  alta para `Principio`)
- **IPE**: `Categoria`, `Tipo`, `Especie`, `Tipo_Apresentacao`

Campos com texto livre (excluir): `Explicacao` (CGVN),
`Descricao_Movimentacao` (VLMO), `Assunto` (IPE),
`Descricao_Atividade` (FCA), `Contato`, `Responsavel`, `Auditor`.

## 6. `report_type` na v0.2

Nenhum dataset da v0.2 tem variante individual/consolidada.
Comportamento atual do `issuer_fetch` (aborta `cvmdata_error_input`
quando `report_type` é passado a tabela sem variantes) cobre o
caso. Sem mudança necessária.

VLMO `_con` é "formulário consolidado" no sentido de **único
formato existente**, não o eixo `ind/con` das demonstrações
contábeis (ITR/DFP). Tratar como **tabela única**, sem `report_type`.

## 7. `keep_latest_version` na v0.2

Todas as tabelas têm coluna `Versao`. Chave de dedup:

- `fca/submissao`: `(cnpj_cia, dt_refer)` — padrão clássico
- FCA detail × 9, CGVN praticas: `(cnpj_companhia, data_referencia)`
  (em CGVN também faz sentido incluir `id_item`)
- CGVN submissao, VLMO submissao: `(cnpj_companhia, data_referencia)`
- VLMO con: `(cnpj_companhia, data_referencia, data_movimentacao,
  tipo_movimentacao, tipo_ativo, …)` — chave composta complexa por
  natureza linha-por-evento; **provavelmente não dedup por
  versao** (cada versão pode trazer eventos diferentes); a Fase 2
  decide
- IPE: **provavelmente não dedup**. Manifesto evento-por-linha; o
  `Versao` parece referir-se à versão do documento referenciado, não
  a versão do registro. A Fase 2 decide.

## 8. Datas → `Date` (automático via dicionário)

Padrões observados nos METAs:

- FCA submissao: `DT_REFER`, `DT_RECEB` (clássico)
- FCA detail / CGVN / VLMO / IPE: `Data_*` (snake_case já
  preservado pelo reader)

Todos serão convertidos automaticamente se o dicionário declarar
`tipo_dados: date`. A confirmar no parser do snapshot de dicionário
(é o que os METAs declaram).

## 9. `vl_conta × escala_moeda`?

Não há. VLMO traz `Quantidade`, `Preco_Unitario`, `Volume` como
numéricos diretos (sem coluna de escala). Sem `multiply_by_scale`
na v0.2.

## 10. Ticker B3 — achado que muda §3.7

`fca/valor_mobiliario` tem coluna `Codigo_Negociacao` —
literalmente o ticker B3 (PETR4, VALE3, etc.) declarado pela
própria companhia no formulário cadastral. Outras colunas
relevantes na mesma tabela: `Mercado` (Bolsa / Balcão organizado),
`Segmento` (Novo Mercado / Nível 1 / Nível 2 / Tradicional /
Bovespa Mais), `Sigla_Entidade_Administradora` (B3 / BVMF),
`Data_Inicio_Negociacao`, `Data_Fim_Negociacao`.

Implicação para a §3.7: a alternativa (b) do prompt — "derivar de
algum campo já presente nos dados CVM, se existir" — **é viável e
limpa**. Lookup ticker → (CNPJ, CD_CVM) sai de
`fca/valor_mobiliario`, ano corrente ou último com `Data_Fim_Negociacao`
nulo, análogo ao lookup CD_CVM → CNPJ via `submissao` que já está
implementado. Sem dependência externa, sem violar o fora-de-escopo
B3.

Custo: a primeira chamada com `issuer = "PETR4"` exige carregar o
`fca/valor_mobiliario` daquele ano. Cacheável.

## 11. Janela temporal real

CKAN do portal CVM serve **2021-2026** para os 4 datasets. O texto
do prompt (IPE desde 2003; demais desde 2010) refere-se ao
histórico **publicado historicamente**, não ao que está vivo no
portal hoje.

Consequência para o pacote:

- `first_year` no schema: declarar 2021 (verdade atual do portal),
  com nota explicativa.
- O mirror próprio (etl-mirror.yaml) pode preservar histórico se
  rodar regularmente — primeiro publish da v0.2 captura 2021-2026;
  publishes subsequentes acumulam (a CVM pode retirar 2021 quando
  2027 entrar). Política de retenção no mirror é decisão à parte
  (§3.9 do prompt).
- Para anos pré-2021: depende do mirror. Pode ser apresentado como
  feature gradual, não bloqueante para v0.2.

## 12. Aprofundamento (2026-05-28, executado após a redação inicial)

Verificações adicionais para fechar dúvidas antes da Fase 2:

### 12.1 `fca/departamento_acionistas` em outros anos

Hipótese da redação inicial: anomalia de 2024 (apenas header).
Resultado:

| Ano | n_linhas (`departamento_acionistas`) | n_linhas (`auditor` para comparação) |
|---|---|---|
| 2023 | 546 | 1005 |
| 2024 | **0** | 1041 |
| 2025 | **0** | 1069 |

A tabela foi populada em 2023 e zerou em 2024-2025. Reflete mudança
regulatória: a seção "Departamento de Acionistas" do Anexo FCA foi
consolidada em outra seção (provavelmente `endereco` ou `dri`).

Implicações:

- A tabela existe no schema CVM (META declara campos) e o CSV vem com
  cabeçalho válido a cada ano, **mas o conteúdo está vazio**.
- Schema do pacote deve declarar `expected_field_count` (vem do META,
  fato estável). YAML escreve normalmente.
- **O reader não pode abortar por `nrow == 0L`** quando o CSV chega só
  com header. Verificar no caminho atual do `read_cvm_csv()` na sessão
  de implementação; se houver regressão, adicionar teste.
- Vignette deve mencionar que `fca/departamento_acionistas` vem vazia
  em anos a partir de 2024 (e a alternativa é `fca/endereco` ou
  `fca/dri`, a confirmar).

### 12.2 `vlmo/con` — categorias de `Tipo_Cargo` e outras codelists

Categorias reais observadas no CSV 2024 (61.485 linhas):

- **`Tipo_Cargo`** (5 categorias válidas + vazia):
  - Conselho de Administração ou Vinculado
  - Conselho Fiscal ou Vinculado
  - Controlador ou Vinculado
  - Diretor ou Vinculado
  - Órgão Estatutário ou Vinculado
- **`Tipo_Empresa`** (3): Companhia, Controlada, Controladora
- **`Tipo_Operacao`** (2): Crédito, Débito
- **`Tipo_Ativo`** (11): Ações, BDR Patrocinados, Bônus de Subscrição,
  Debêntures, Derivativos, Opção de Compra, Opção de Venda, Opções de
  Plano de Remuneração, Outros, Recibo de Subscrição, Units
- **`Tipo_Movimentacao`** (39): Compra, Venda, Compra à vista,
  Desdobramento/bonificação, Doação (doador), etc. — semanticamente
  limpa
- **`Caracteristica_Valor_Mobiliario`** (651 distintos): **texto livre**,
  variantes ortográficas (ex.: "1 ACAO ORDINARIA E 04 ACOES
  PREFERENCIAIS", "1 ACAO ORDINARIA E 4 ACOES PREFREENCIAIS" — typos
  preservados como vêm da CVM). **Excluir da codelist** — o critério
  atual (≤ 50 distintos) já remove automaticamente.

Confirma que VLMO entrega codelist rica e bem comportada.

### 12.3 `cgvn/praticas` — cardinalidade

CSV 2024 (21.493 linhas):

- **`Capitulo`** (5): Acionistas, Conselho de Administração, Diretoria,
  Ética e Conflito de Interesses, Órgãos de Fiscalização e Controle
- **`Principio`** (30): Acordos de Acionistas, Assembleia Geral, etc. —
  hierarquia estável dentro do código de governança
- **`Pratica_Adotada`** (4 categorias válidas + vazia): Sim, Não,
  Parcialmente, Não se Aplica
- **`ID_Item`** (54 distintos, formato `N.N.N`): identificador da
  prática no código → vai para `character` (cobre o padrão `^id_` do
  reader), não para codelist

Todos os três campos categóricos cabem no critério atual de codelist
(≤ 50 ou `Capitulo`/`Pratica_Adotada` bem dentro).

### 12.4 `fca/valor_mobiliario` — cobertura do `Codigo_Negociacao` (ticker)

CSV 2024 (1023 linhas):

- **Total de linhas**: 1023
- **Linhas com `Codigo_Negociacao` preenchido**: 570 (55,7%)
- **CNPJs distintos em `valor_mobiliario`**: 670
- **CNPJs com pelo menos um `Codigo_Negociacao`**: **408**
- **Distribuição `Mercado`**:
  - Bolsa: ~570 linhas (todas com ticker)
  - Balcão Organizado: 289 (parcialmente — alguns sem ticker)
  - Balcão Não-Organizado: 81 (sem ticker)
  - Vazio: 81
- **Total distintos de tickers**: ~408 (várias linhas por CNPJ
  correspondem a séries diferentes, e.g. ON + PN)

Interpretação:

- Companhias com valor mobiliário em Balcão Não-Organizado (debêntures
  privadas, etc.) **não têm ticker** — é esperado, não é dado faltante.
- Companhias com ações em bolsa **declaram seus tickers no FCA** —
  cobertura é 100% das que têm ticker.
- O lookup ticker → (CNPJ, CD_CVM) via `fca/valor_mobiliario` cobre
  todo o universo onde "ticker" faz sentido. Onde não faz sentido,
  o lookup aborta com `cvmdata_error_input` ("ticker não encontrado")
  — comportamento desejado, não silent-fail.

**§3.7 alternativa (b) — viável e limpa. Sem dependência de fonte
externa.**

### 12.5 Sequência tracer-bullet — confirmada

Os achados acima reforçam a ordem **CGVN → VLMO → FCA → IPE**:

- CGVN é genuinamente o mais simples (2 tabelas, codelists pequenas,
  modelo "pratique ou explique" sem aresta);
- VLMO em 2º expõe codelists ricas mas bem comportadas e o submissao
  no estilo FRE-detail (12 campos), sem ainda lidar com a explosão
  para 10 tabelas;
- FCA em 3º traz a maior complexidade simultânea (10 tabelas,
  `submissao` clássico de 9 campos diferente do FRE-detail do VLMO/CGVN,
  ticker B3, tabela vazia `departamento_acionistas`) — só faz sentido
  depois que VLMO e CGVN validaram o pipeline FRE-detail;
- IPE em 4º pelos motivos da redação inicial (sem submissao, manifesto,
  sobreposição conceitual com VLMO).

## 13. Próximos passos

1. **Sidney revisa este sub-doc.** Confirma os fatos, sinaliza
   reinterpretações, eventualmente pede aprofundamento (ex.: verificar
   `departamento_acionistas` em outro ano antes da Fase 2; abrir a
   CSV de `vlmo/con` para ver categorias reais de `Tipo_Cargo`).
2. **Fase 2** começa a partir dos achados acima:
   - §3.1 schemas — esqueleto direto deste inventário
   - §3.2 IPE — manifesto, sem `submissao`, sem dedup por versão (a
     confirmar), cobertura = janela do mirror
   - §3.3 VLMO — identidade opaca, `issuer` filtra companhia
     emissora, sem novo identificador de pessoa
   - §3.4 CGVN — duas tabelas, `Pratica_Adotada` como codelist
   - §3.5 FCA × CAD — FCA `geral` traz o estado corrente do cadastro
     com mais detalhe que `cad/companhias`; documentar relação na
     vignette (FCA = histórico versionado anual; CAD = snapshot
     atual)
   - §3.6 `report_type` — não se aplica, sem mudança
   - §3.7 ticker B3 — **alt (b) recomendada**: lookup via
     `fca/valor_mobiliario`
   - §3.8 subdivisão — propor ordem tracer-bullet
     (CGVN → FCA → VLMO → IPE)
   - §3.9 snapshots/mirror/testes — extensão da matrix do
     `etl-mirror.yaml` para 8 entradas (4 já + 4 novas)
3. **Fase 3**: consolidar Fases 1 + 2 no documento de decisão
   canônico `cvmdata_v0-2_planejamento_decisao.md`. Sessões Claude
   Code derivadas (uma por dataset) saem a partir daí.
