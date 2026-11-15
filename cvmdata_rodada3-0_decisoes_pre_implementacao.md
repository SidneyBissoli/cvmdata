# Rodada 3.0 — Decisões pré-implementação

> **Data de fechamento**: 2026-05-19 **Versão do documento**: v01
> **Status**: travado (incremental — não reabre decisões anteriores)
> **Idioma**: português brasileiro **Documentos predecessores**:
> `cvmdata_rodada1_fechamento.md`,
> `cvmdata_rodada2_plano_arquitetural-v02.md`,
> `cvmdata_rodada2-5_naming_unificado-v02.md`,
> `cvmdata_rodada2-6_schemas.md` **Documentos sucessores**: Rodada 3
> plena — scaffolding + geração programática dos ~72 YAMLs restantes +
> implementação do reader.

------------------------------------------------------------------------

## 1. Resumo executivo

A Rodada 3.0 fechou as três decisões de design pequenas mas com
consequências em cascata que o fechamento da Rodada 2.6 deixou para
resolução prévia à Rodada 3 plena:

1.  **P1** — Nome canônico-PT da tabela de cabeçalho ITR/DFP: decidido
    **`submissao`**. Aplica-se também ao FRE-header (verificação
    empírica confirmou estrutura idêntica nos três datasets).
2.  **P2** — Formato do snapshot de dicionário CVM: decidido **CSV**
    (`inst/extdata/cvm_dictionary_snapshot.csv`).
3.  **P3** — Formato e schema do snapshot de codelists empíricas:
    decidido **CSV** (`inst/extdata/cvm_codelists_snapshot.csv`), schema
    mínimo `dataset`, `table`, `column`, `value` + campo opcional
    `first_seen_year`; geração por varredura histórica completa com
    cache por hash.

Essas três decisões destravam: (i) a geração programática dos ~72 YAMLs
restantes, que precisa do nome canônico em §4.1 e §4.2 do naming doc;
(ii) a implementação do reader, que precisa saber em qual formato ler o
snapshot de dicionário para inferir tipos automaticamente; (iii) o
workflow ETL de atualização, que precisa de formato definido para
escrever.

Achado lateral relevante registrado em §6 como item novo da Rodada 3
plena: oito tabelas FRE têm dados publicados mas **não têm META
correspondente** no `meta_fre_cia_aberta.zip` — reader precisará de
política para esse caso.

------------------------------------------------------------------------

## 2. P1 — Nome canônico-PT do header ITR/DFP

### 2.1 Verificação empírica realizada

Inspeção direta dos arquivos do Portal de Dados Abertos CVM em
2026-05-19. URLs e arquivos verificados:

- `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/ITR/DADOS/itr_cia_aberta_2024.zip`
  (HTTP 200, 32.7 MB) — extraído `itr_cia_aberta_2024.csv`.
- `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/DFP/DADOS/dfp_cia_aberta_2024.zip`
  (HTTP 200, 13.4 MB) — extraído `dfp_cia_aberta_2024.csv`.
- `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/FRE/DADOS/fre_cia_aberta_2024.zip`
  (HTTP 200, 8.4 MB) — extraído `fre_cia_aberta_2024.csv`.
- `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/ITR/DADOS/itr_cia_aberta_2018.zip`
  (HTTP 200, 23.5 MB) — verificação histórica do ITR-header em 2018.
- `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/ITR/META/meta_itr_cia_aberta_txt.zip`
  — extraído `meta_itr_cia_aberta.txt` (dicionário do CSV-header).

Achados estruturais idênticos entre ITR, DFP e FRE-header — 9 campos na
mesma ordem:

    CNPJ_CIA;DT_REFER;VERSAO;DENOM_CIA;CD_CVM;CATEG_DOC;ID_DOC;DT_RECEB;LINK_DOC

Caracterização empírica das três tabelas:

| dataset    | linhas (2024) | `CATEG_DOC` distinto |
|------------|---------------|----------------------|
| ITR-header | 2.448         | `"ITR"`              |
| DFP-header | 873           | `"DFP"`              |
| FRE-header | 5.110         | `"FRE WEB"`          |

Verificação histórica: ITR-header em 2018 tem exatamente a mesma
estrutura de 9 campos — schema estável no tempo.

Achado adicional importante: o `meta_itr_cia_aberta_txt.zip` contém um
arquivo chamado `meta_itr_cia_aberta.txt` (sem sufixo de demonstração
contábil) com o dicionário dos 9 campos do CSV-header. A própria CVM
trata o header como tabela com identidade própria — não apenas como
artefato de junção. Trechos das descrições oficiais do META:

- `DT_RECEB`: “Data da recebimento do documento” (sic; português oficial
  CVM).
- `ID_DOC`: “Identificador do documento”.
- `CATEG_DOC`: “Categoria do documento”.
- `LINK_DOC`: “Endereço para download do documento”.

A semântica oficial CVM é clara: **cada linha = uma submissão documental
à CVM, com seus metadados administrativos** (data de recebimento, ID
atribuído, categoria, link público no RAD).

### 2.2 Alternativas avaliadas

| Candidato | Prós | Contras |
|----|----|----|
| `cabecalho` | Tradução natural de “header”; familiar | Descreve forma (linha-topo) e não conteúdo; em PT-BR sugere uma linha-resumo, mas a tabela tem milhares de linhas; colide com “header” como termo informal usado no plano arquitetural para se referir a esta mesma tabela |
| `formulario` | Coerente com terminologia CVM (“Formulário de Referência”) | “Formulário” é o objeto inteiro (todas as tabelas-detalhe + header), não apenas esta tabela; nome enganoso por escopo errado |
| `protocolo` | Termo administrativo BR forte; captura ato de protocolar na autarquia; coerente com os 4 campos próprios (categoria, ID, data de recebimento, link) | Tem outros usos consagrados (protocolo de comunicação, protocolo de pesquisa); leve ambiguidade no contexto técnico |
| `submissao` | Captura semântica exata (cada linha = uma submissão); coerente com `DT_RECEB`, `ID_DOC`, `LINK_DOC`, `CATEG_DOC`; termo neutro e técnico; tradução direta de “submission” no jargão CVM/RAD; sem ambiguidade no contexto do pacote | “Submissão” tem leve conotação coloquial de “sujeição” em PT-BR, mas no contexto técnico/regulatório o uso é unívoco |

Candidatos descartados sem entrar na tabela: `entrega` (coloquial
demais), `documento` (genérico e colidiria com `id_doc`), `arquivamento`
(jurisprudência, não CVM), `registro` (genérico demais), `metadados`
(colide com terminologia técnica do pacote).

### 2.3 Decisão e justificativa

**Decisão: `submissao`** como nome canônico-PT da tabela de cabeçalho.

Justificativa rastreável aos critérios listados no prompt:

1.  **Coerência com o conteúdo factual**: a tabela registra submissões
    documentais à CVM. Os 4 campos próprios não-chave (`CATEG_DOC`,
    `ID_DOC`, `DT_RECEB`, `LINK_DOC`) são todos atributos da submissão,
    não do documento em si nem da companhia.
2.  **Paralelismo ITR/DFP/FRE-header**: verificação empírica demonstrou
    estrutura idêntica nos três datasets — mesmo nome `submissao`
    aplica-se aos três sem ressalva.
3.  **Snake_case minúsculo em PT**: atende régua §0 do naming doc.
4.  **Distinguibilidade de “header”**: o termo “header” usado
    informalmente no plano arquitetural não é nome de tabela; é
    referência conceitual à forma do CSV. `submissao` evita a colisão
    semântica.
5.  **Não-ambiguidade**: `submissao` no contexto regulatório/CVM tem
    significado único; concorrente `protocolo` carrega leve ambiguidade.

Nota de continuidade: a Rodada 2.5 (decisão 20, §10) **removeu uma
tabela `cabecalho` fictícia** que constava de versões anteriores do
naming doc, declarando que o nome real seria definido após verificação
empírica na Rodada 3. Esta sessão fecha essa pendência: o nome **não é**
`cabecalho`.

### 2.4 Aplicabilidade a FRE-header

**Aplicável**. O FRE-header (`fre_cia_aberta_<ano>.csv`) tem os mesmos 9
campos na mesma ordem (verificação empírica de 2024) e representa o
mesmo conceito de submissão documental. O caveat §3.0 do naming doc —
que distingue convenção de naming entre FRE-header
(SCREAMING_SNAKE_CASE) e FRE-detail (Title_Case_With_Underscores) —
refere-se ao **estilo de capitalização dos campos**, não ao **nome da
tabela**. A tabela canônica do FRE-header chama-se `submissao`, idêntica
a ITR e DFP.

Consequência operacional: nas três coleções `cvm_tables("itr")`,
`cvm_tables("dfp")`, `cvm_tables("fre")` existe uma tabela chamada
`submissao` com as mesmas 9 colunas (`cnpj_cia`, `dt_refer`, `versao`,
`denom_cia`, `cd_cvm`, `categ_doc`, `id_doc`, `dt_receb`, `link_doc`),
distinguindo-se apenas por `categ_doc` (`"ITR"`, `"DFP"`, `"FRE WEB"`).

------------------------------------------------------------------------

## 3. P2 — Formato do snapshot de dicionário CVM

### 3.1 Critérios de decisão

Da §6 item 3 do fechamento da Rodada 2.6, alinhados à estrutura interna
já travada em §7.5 e §11 do naming doc:

1.  **Tamanho final em `inst/extdata`** — CRAN policy: pacote total \<5
    MB sem pedido de exceção. Snapshot estimado \<500 KB em qualquer dos
    formatos.
2.  **Velocidade de carregamento** —
    [`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md)
    é função de descoberta interativa; UX exige tempo de leitura \< 100
    ms.
3.  **Versionabilidade em Git** — o snapshot será atualizado por GitHub
    Action; revisão humana via PR depende de diff legível.
4.  **Coerência com o stack travado** — `arrow` já está no stack da
    Rodada 1/2 (Imports do pacote); Parquet “vem de graça” do ponto de
    vista de dependências.

### 3.2 Alternativas avaliadas

Benchmark empírico realizado em 2026-05-19. Snapshot piloto construído a
partir dos arquivos META reais da CVM (CAD + 11 META do ITR expandidos
para 19 tabelas con/ind + proxy para DFP com a mesma expansão + 50 META
do FRE; resultado total **1.014 linhas úteis** após exclusão das 22
tabelas FRE-fantasma documentadas na Rodada 2.6).

| Formato | Tamanho em disco | Tempo de leitura (mediana de 30 rodadas) | Diff Git | Dependência |
|----|----|----|----|----|
| **CSV** | 91 KiB | 3.4 ms | Inteligível | nenhuma adicional (`readr` já no stack) |
| **Parquet** | 20 KiB | 2.4 ms | Ininteligível | `arrow` (já no stack) |
| **RDS-equivalente (pickle)** | 163 KiB | 0.17 ms | Ininteligível | nenhuma adicional ([`base::readRDS`](https://rdrr.io/r/base/readRDS.html)) |

Caveat metodológico: o benchmark foi feito em Python com `pandas` +
`pyarrow` (R não disponível neste ambiente). Os tempos absolutos não são
iguais aos de R, mas a **ordem de grandeza e o ranking relativo entre
formatos** são equivalentes — ambos os ecossistemas usam o mesmo binário
Apache Arrow C++ por baixo para Parquet, e CSV via
[`readr::read_csv`](https://readr.tidyverse.org/reference/read_delim.html)
em R tem perfil de performance similar a `pandas.read_csv`. Para RDS
especificamente, `readRDS` tende a ser ainda mais rápido em R do que
pickle em Python (formato nativo otimizado). A ordenação **RDS \<
Parquet \< CSV** em tempo deve se manter em R; **CSV \< RDS \< Parquet**
em tamanho deve se manter para este conteúdo (texto-pesado em PT). Para
o snapshot piloto, todos os três formatos ficam **muito abaixo dos
limiares-critério**: \< 500 KB em tamanho e \< 100 ms em tempo.

Simulação de diff Git (CSV): a mudança de uma única descrição de campo
gera um diff de 1 linha, legível em PR sem ferramentas adicionais —
equivalente ao que reviewers humanos têm hoje em PRs do `cvmdata`. Em
Parquet e RDS, a mesma mudança torna o arquivo inteiro opaco no diff.

### 3.3 Estrutura interna (referência ao §7.5/§11 do naming doc)

Estrutura **não está em discussão** — já travada na Rodada 2.5/2.6.
Reproduzida aqui para referência: tabela longa com chave composta
`dataset` + `table` + `column` e as 7 colunas do schema oficial CVM de
[`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md):

| Coluna do snapshot | Tipo | Origem |
|----|----|----|
| `dataset` | character | chave (`"cad"`, `"itr"`, `"dfp"`, `"fre"`) |
| `table` | character | chave (snake_case PT, ex.: `"bpa_con"`, `"submissao"`) |
| `column` | character | chave (snake_case minúsculo, ex.: `"vl_conta"`) |
| `campo` | character | nome original CVM (preserva SCREAMING_SNAKE_CASE ou Title_Case) |
| `descricao` | character | descrição oficial CVM em PT |
| `dominio` | character | domínio oficial CVM (`"Alfanumérico"`, `"AAAA-MM-DD"`, etc.) |
| `tipo_dados` | character | tipo oficial CVM (`"varchar"`, `"date"`, `"smallint"`, `"numeric"`, `"decimal"`) |
| `tamanho` | integer | tamanho oficial CVM (NA quando ausente) |
| `precisao` | integer | precisão oficial CVM (NA quando ausente) |
| `scale` | integer | escala oficial CVM (NA quando ausente) |

A coluna `campo` preserva o nome original CVM (não é redundante com
`column` — em FRE-detail, `column = "cnpj_companhia"` e
`campo = "CNPJ_Companhia"`, ambos necessários para rastreamento).

### 3.4 Decisão e justificativa

**Decisão: CSV.** Arquivo final em
`inst/extdata/cvm_dictionary_snapshot.csv`, encoding UTF-8, delimitador
`","` (não `";"` — o snapshot é arquivo do pacote, não da CVM, segue
convenção tidy padrão).

Justificativa rastreável aos critérios:

- **Tamanho** (91 KiB): cabe trivialmente em `inst/extdata/`; folga de
  duas ordens de grandeza vs limite CRAN.
- **Velocidade** (3.4 ms): muito abaixo do limiar UX de 100 ms;
  diferença prática entre 3 ms e 0.17 ms é imperceptível ao usuário.
- **Diff Git inteligível**: argumento decisivo. O snapshot será
  atualizado por workflow automatizado; revisão humana via PR é o
  mecanismo de detecção de mudanças silenciosas no schema CVM (defesa em
  profundidade, alinhado com a filosofia de `expected_field_count` na
  §7.2 do naming doc). CSV permite revisão granular linha-a-linha sem
  ferramentas adicionais.
- **Coerência com o stack travado**:
  [`readr::read_csv()`](https://readr.tidyverse.org/reference/read_delim.html)
  já está disponível via `readr` no Imports; sem nova dependência.
- **Coerência com o princípio reitor “fica como vem”**: o dicionário CVM
  já é texto (TXT formato bloco); manter como texto preserva paralelismo
  direto com a fonte.

Trade-off aceito: cede 4× em tamanho vs Parquet, mas o benefício de diff
legível supera qualquer ganho marginal de espaço em uma faixa onde todos
os formatos são confortavelmente pequenos.

### 3.5 Decisões aninhadas

**Nome do arquivo**: `cvm_dictionary_snapshot.csv` (sem mudança da forma
proposta no naming doc §7.4).

**Localização**: raiz de `inst/extdata/`. Sem subpasta. Coerente com o
tratamento do snapshot como recurso único do pacote, junto com
`cvm_codelists_snapshot.csv` (P3). Subpasta `inst/extdata/schemas/` fica
reservada para os ~75 YAMLs por tabela.

**Política/trigger de atualização**: alinhada ao workflow ETL já travado
na Rodada 1 (terças 07:00 UTC, event-driven via hash). O workflow:

1.  Computa SHA-256 de cada `meta_*.txt` baixado do Portal CVM (ou, para
    os META dentro de ZIP, dos arquivos extraídos).
2.  Compara com hashes do run anterior (armazenados em
    `data-raw/dictionary_hashes.json`).
3.  Se algum hash mudou (ou novo `meta_*` apareceu), regenera o snapshot
    e abre PR para revisão humana antes do merge.
4.  Bumpa também o YAML afetado quando `expected_field_count` divergir
    do schema novo — defesa em profundidade contra mudanças silenciosas.

Periodicidade do workflow alinhada com o ETL de mirror do Plano
Arquitetural §8 (terças 07:00 UTC). A regeneração propriamente dita roda
como step adicional no mesmo workflow, não em workflow separado —
economia de boilerplate CI/CD.

------------------------------------------------------------------------

## 4. P3 — Formato do snapshot de codelists empíricas

### 4.1 Critérios de decisão

Idênticos aos de P2 (mesma natureza de artefato: tabela longa,
versionada, atualizada periodicamente, embarcada em `inst/extdata`),
mais um critério adicional:

5.  **Custo-benefício de campos opcionais** — cada campo opcional
    adicional implica custo de geração no workflow ETL (varredura
    completa para `frequency`, varredura histórica para
    `first_seen_year`/`last_seen_year`) e ruído anual no diff Git
    (campos que mudam a cada execução invalidam a vantagem de CSV
    versionado).

### 4.2 Alternativas avaliadas

Mesmas três opções de P2: CSV, Parquet, RDS. Como o conteúdo de codelist
é estruturalmente análogo ao de dicionário (chaves character + valores
character em PT, baixa cardinalidade, sem campos binários grandes), os
trade-offs de formato são os mesmos. Estimativa de tamanho:

- ~3-5 colunas categóricas médias × 75 tabelas reais v0.1 = ~300
  entradas (`dataset`, `table`, `column`).
- ~5-10 valores médios por entrada = ~1.500-3.000 linhas no snapshot
  completo.
- Em CSV com 5 colunas (`dataset`, `table`, `column`, `value`,
  `first_seen_year`), com strings PT médias de ~30 chars/valor:
  **~150-300 KiB**.

Verificação parcial: a tabela `fre/administrador_membro_conselho_fiscal`
em 2024 tem 9.495 linhas e 21 colunas, das quais **2 são categóricas
reais** — `Orgao_Administracao` (4 valores) e `Eleito_Controlador` (2
valores; domínio `S/N`). Datas e identificadores numéricos foram
corretamente excluídos do conjunto categórico. Cardinalidade empírica
observada é menor que a estimativa conservadora — o snapshot deve ficar
mais perto do limite inferior (~150 KiB).

### 4.3 Schema final (obrigatórios e opcionais)

| Coluna | Tipo | Obrigatório/Opcional | Notas |
|----|----|----|----|
| `dataset` | character | obrigatório (chave) | identificador curto do dataset |
| `table` | character | obrigatório (chave) | snake_case PT |
| `column` | character | obrigatório (chave) | snake_case minúsculo |
| `value` | character | obrigatório | valor categórico em PT como vem da CVM |
| `first_seen_year` | integer | **opcional incluído na v0.1** | primeiro ano em que o valor foi observado na série histórica |

Campos **deferidos para v0.2+** com justificativa:

- `frequency` (integer, contagem de ocorrências): **não incluído na
  v0.1**. Custo de geração baixo (cabe na varredura existente), mas
  ruído alto — o valor muda a cada release CVM, fazendo todas as linhas
  do snapshot virarem “sujas” no diff Git anual, o que invalida a
  vantagem do CSV legível. Caso de uso “identificar valores raros” pode
  ser atendido pelo próprio reader (`distinct() |> count()` sobre o
  tibble retornado por
  [`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)).
  Yagni para v0.1.
- `last_seen_year` (integer, último ano observado): **não incluído na
  v0.1**. Custo equivalente a `first_seen_year`, mas com comportamento
  semelhante a `frequency` — todo valor ainda presente recebe
  `last_seen_year = ano_corrente` em cada update, gerando ruído anual.
  Alternativa preferível: quando um valor deixa de aparecer em N
  releases consecutivos, **remover do snapshot** (com registro em
  NEWS.md). Decisão de política para Rodada 3 plena.

Razão estrutural para incluir `first_seen_year` mas não os outros:
**estabilidade do valor** — `first_seen_year` muda em zero linhas nas
execuções rotineiras do workflow (só muda quando um valor novo aparece
pela primeira vez); `frequency` e `last_seen_year` mudam em toda linha
em toda execução, invalidando a versionabilidade.

### 4.4 Estratégia de geração

**Varredura histórica completa** do primeiro release disponível por
dataset até o release mais recente. Custo único na geração inicial do
snapshot (Rodada 3 plena); custo incremental por release novo nos
updates do workflow.

Otimização operacional: cache por hash de CSV. O workflow ETL armazena
em `data-raw/codelist_csv_hashes.json` o SHA-256 de cada CSV processado;
quando um release roda novamente, varre apenas os CSVs cujo hash mudou.
Em prática, depois do snapshot inicial, cada execução semanal processa
apenas o release mais recente de cada dataset (e re-processa releases
antigos só se a CVM os reemitir, o que é evento raro).

Trade-off rejeitado: **snapshot pontual** (apenas o release mais
recente). Rejeitado porque perderia valores raros que só aparecem em
recortes históricos específicos (ex.: companhias delistadas que deixaram
de submeter; categorias regulatórias que mudaram entre 2010 e 2024). O
custo extra da varredura histórica é pago uma única vez na
inicialização.

Resumo do contrato operacional do workflow:

1.  Para cada `(dataset, table)` no snapshot de dicionário, baixar todos
    os CSVs disponíveis no Portal CVM (com cache local permanente,
    alimentado pelo mirror próprio da Rodada 1).
2.  Para cada CSV cujo hash mudou desde último run, varrer colunas
    candidatas a codelist (cardinalidade ≤ 50 valores únicos, tipo
    character não-data; threshold definitivo a confirmar na Rodada 3
    plena com base em distribuição empírica).
3.  Para cada par `(coluna, valor)` observado, atualizar
    `first_seen_year` (min do conjunto histórico).
4.  Materializar `inst/extdata/cvm_codelists_snapshot.csv` ordenado por
    `dataset`, `table`, `column`, `value`.
5.  Se o snapshot mudou, abrir PR para revisão humana.

### 4.5 Decisão e justificativa

**Decisão: CSV.** Arquivo final em
`inst/extdata/cvm_codelists_snapshot.csv`, encoding UTF-8, delimitador
`","`.

Justificativa rastreável aos critérios:

- **Tamanho** (~150-300 KiB estimado): cabe trivialmente em
  `inst/extdata/`; folga vs limite CRAN.
- **Velocidade**: mesma ordem de grandeza do snapshot de dicionário
  (estrutura análoga); leitura em \<10 ms.
- **Diff Git inteligível**: argumento decisivo. Mudança em codelist é
  evento epistemicamente importante — pode indicar (a) novo valor
  categórico legítimo emitido pela CVM, (b) novo valor por erro de
  submissão de uma companhia, ou (c) deprecação silenciosa de valor
  antigo. PR para revisão humana é o mecanismo correto.
- **Coerência com P2**: mesmo formato no mesmo lugar facilita manutenção
  do workflow e cognição do reviewer humano.
- **Coerência com o princípio “fica como vem”**: valores categóricos vêm
  da CVM em PT; preservados como vêm em texto legível.

Trade-off aceito: cede 5-10× em tamanho vs Parquet, mas todos os
formatos são confortavelmente pequenos na faixa absoluta.

------------------------------------------------------------------------

## 5. Atualizações requeridas no naming doc

Lista de refinamentos a aplicar ao
`cvmdata_rodada2-5_naming_unificado-v02.md` em sessão de edição dedicada
(não executada nesta sessão).

### 5.1 Refinamentos incrementais a aplicar

1.  **Cabeçalho do documento** — adicionar nova entrada no bloco
    “Refinamentos incrementais — Rodada 3.0 (2026-05-19)” listando as
    três decisões (P1, P2, P3) com referência cruzada a este documento.
2.  **§3 (Colunas-chave universais)** — sem alteração estrutural, mas
    adicionar à tabela inicial a nota: a tabela canônica que contém
    estas 5 colunas-chave + 4 colunas de metadados de submissão
    (`categ_doc`, `id_doc`, `dt_receb`, `link_doc`) chama-se `submissao`
    em ITR, DFP e FRE.
3.  **§4.1 (Tabelas ITR e DFP)** — adicionar linha na tabela:
    `submissao` \| “Registro de submissão do documento à CVM (metadados
    administrativos)” \| “tabela de cabeçalho do formulário”. Ajustar
    total para 19 tabelas espelhadas ITR/DFP (era “18 tabelas
    espelhadas + 1 tabela de cabeçalho a nomear na Rodada 3”).
4.  **§4.2 (Tabelas FRE)** — em “Categoria A — Cabeçalho”, substituir “a
    confirmar nome empírico” por `submissao`. Total FRE: 36 tabelas
    reais (1 submissao + 35 detalhes). Manter a nota sobre 14
    tabelas-fantasma do META — mas atualizar para **22
    tabelas-fantasma** (achado refinado em 2026-05-19; vide §5.2 deste
    documento).
5.  **§7 (YAMLs de schema interno)** — adicionar nova subseção §7.8
    “Snapshot de codelists empíricas” descrevendo schema final (5
    colunas obrigatórias: `dataset`, `table`, `column`, `value`,
    `first_seen_year`) e formato (CSV em
    `inst/extdata/cvm_codelists_snapshot.csv`). Vinculação direta ao
    princípio §4.4 do fechamento da Rodada 2.6 (“codelists vêm de
    varredura empírica, não do META”).
6.  **§7.4 (Dicionário CVM em snapshot separado)** — substituir “ou
    equivalente, formato final a decidir na Rodada 3” por “formato CSV,
    encoding UTF-8, delimitador `\",\"`” com referência à §3.4 deste
    documento.

### 5.2 Itens §11 a marcar como \[RESOLVIDO 3.0\]

Bullets de §11 do naming doc que passam para `[RESOLVIDO 3.0]`:

- **§11.1, primeiro bullet** (nome canônico-PT da tabela de cabeçalho
  ITR/DFP): de `[RESOLVIDO 2.6]` com caveat “nome canônico-PT permanece
  a decidir” → **\[RESOLVIDO 3.0\]: tabela chama-se `submissao`;
  aplica-se também a FRE-header**.
- **§11.4, primeiro bullet** (nome final do snapshot de dicionário,
  formato em aberto): de `[ABERTO]` (registrado implicitamente em
  “Permanece pendência Rodada 3”) → **\[RESOLVIDO 3.0\]:
  `inst/extdata/cvm_dictionary_snapshot.csv` em formato CSV UTF-8**.
- **§11.4, segundo bullet** (workflow GitHub Action para atualização do
  snapshot): de `[ABERTO]` → **\[REFINADO 3.0\]: trigger por hash dos
  `meta_*.txt` + abertura de PR para revisão humana; integrado ao
  workflow ETL existente (terças 07:00 UTC)**. Continua aberto na parte
  de **implementação** do workflow — decisão de design fechada, execução
  fica na Rodada 3 plena.

Adições novas à §11 (não substituem itens existentes):

- **§11.4, nova subseção \[ADIÇÃO 3.0\]**: snapshot de codelists
  empíricas — formato CSV em `inst/extdata/cvm_codelists_snapshot.csv`,
  schema mínimo de 5 colunas, geração por varredura histórica completa
  com cache por hash. Estratégia detalhada em §4 deste documento.
- **§11.3 (Conteúdo), novo bullet \[ADIÇÃO 3.0\]**: descoberta empírica
  de **8 tabelas FRE com dados publicados mas sem META correspondente**
  (vide §6 item novo deste documento). Reader deve definir política para
  esse caso na Rodada 3 plena.

------------------------------------------------------------------------

## 6. Pendências e tarefas remanescentes para Rodada 3 plena

Atualização do §6 do fechamento da Rodada 2.6, item a item. Itens
fechados nesta sessão removidos da lista de pendências; itens
remanescentes refinados ou inalterados.

| Item original (§6 da 2.6) | Status pós-3.0 | Nota |
|----|----|----|
| 1\. Snapshot completo do dicionário CVM (~72 YAMLs restantes) | **sem mudança** | Continua sendo o item de maior peso para a Rodada 3 plena. Geração programática agora tem todos os pré-requisitos: nome canônico (`submissao`), formato do snapshot (CSV), schema (§7.5 + extensões 3.0) |
| 2\. Travar nome canônico-PT da tabela de cabeçalho ITR/DFP | **RESOLVIDO 3.0** | `submissao` (§2 deste documento). Aplica-se também a FRE-header |
| 3\. Formato do snapshot de dicionário CVM | **RESOLVIDO 3.0** | CSV em `inst/extdata/cvm_dictionary_snapshot.csv` (§3 deste documento) |
| 4\. Formato do snapshot de codelists empíricas | **RESOLVIDO 3.0** | CSV em `inst/extdata/cvm_codelists_snapshot.csv`, schema 5 colunas, varredura histórica com cache (§4 deste documento) |
| 5\. Implementação do reader | **sem mudança** | Continua sendo o item central da Rodada 3 plena (ambiente Claude Code). Especificação completa em §6 item 5 do fechamento da Rodada 2.6 |
| 6\. Workflow GitHub Action para atualização periódica | **refinado** | Trigger por hash de `meta_*.txt` + hash de CSVs mais recentes; abertura de PR para revisão humana; integrado ao workflow ETL semanal já travado na Rodada 1. Decisões de design fechadas; implementação na Rodada 3 plena |
| 7\. Validação empírica em casos limítrofes | **sem mudança** | Itens marcados `[ABERTO]` na §11.5 do naming doc; depende do reader implementado |

Item novo identificado nesta sessão:

8.  **\[NOVO 3.0\]** **Política do reader para tabelas FRE com dados mas
    sem META**. Verificação empírica em 2026-05-19 detectou 8 tabelas
    FRE publicadas no `fre_cia_aberta_2024.zip` que **não têm META
    correspondente** no `meta_fre_cia_aberta.zip`: `administrador_PCD`,
    `empregado_PCD`, `empregado_local_declaracao_genero`,
    `empregado_local_declaracao_raca`,
    `empregado_posicao_declaracao_genero`,
    `empregado_posicao_declaracao_raca`,
    `empregado_posicao_faixa_etaria`, `empregado_posicao_local`.
    Cobertura faltante do META é defeito conhecido da CVM (juntando-se
    aos defeitos documentados em §11.5 do naming doc). Decisão para
    Rodada 3 plena: reader deve aceitar leitura sem validação contra
    META, com warning informativo (`cvmdata_error_parse` rebaixado a
    [`cli::cli_warn()`](https://cli.r-lib.org/reference/cli_abort.html)
    quando META ausente, mantido como erro quando META presente mas
    divergente). YAMLs dessas 8 tabelas terão `cvm_dictionary_url: null`
    e `expected_field_count` derivado de contagem empírica do CSV em vez
    do META. Tabelas entram no snapshot de dicionário com
    `descricao = NA` para todas as colunas (a CVM não fornece a
    descrição); usuário poderá enriquecer manualmente em release futuro.

Dependências entre itens (atualizadas):

- Item 1 (geração dos YAMLs) depende dos resultados de P1, P2 e P3 desta
  sessão — agora destravado.
- Item 5 (reader) depende de itens 1, 8, e do snapshot de dicionário
  materializado.
- Item 6 (workflow) depende de itens 1, 3 e 4 — agora destravado em
  design, falta implementar.
- Item 7 (validação em casos limítrofes) depende do reader minimamente
  funcional.

------------------------------------------------------------------------

## 7. Pergunta acionável para o mantenedor

Próximo passo — escolher uma opção:

**(a)** Seguir para a **Rodada 3 plena** (scaffolding + implementação em
Claude Code) com este documento como referência. O mantenedor aplica os
refinamentos do §5.1 ao naming doc em algum momento da Rodada 3 — pode
ser logo no início (antes do scaffolding) ou em paralelo. As decisões de
§2/§3/§4 são suficientes para destravar a geração dos ~72 YAMLs e a
implementação do reader sem esperar o naming doc atualizado.

**(b)** Subsessão dedicada curta para **atualizar o naming doc com os
refinamentos da Rodada 3.0** antes de qualquer codificação. Tira do
caminho crítico a edição editorial que, se postergada, pode gerar
inconsistência entre documentos durante a Rodada 3 plena. A sessão é de
pura edição (sem novas decisões); estimada em 30-45 minutos.

**(c)** Subsessão temática adicional. Possíveis temas levantados pela
verificação desta sessão: (c1) política do reader para as 8 tabelas FRE
sem META — item 8 do §6 acima; (c2) auditoria do META DFP em paralelo ao
ITR (não baixado nesta sessão; o naming doc §11.4 nota “DFP a confirmar
na Rodada 3”); (c3) outro.

Qual?
