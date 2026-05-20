# Rodada 2.6 — Schemas de prova de conceito

> **Data de fechamento**: 2026-05-18
> **Versão do documento**: v01
> **Status**: travado (incremental — não reabre decisões anteriores)
> **Idioma**: português brasileiro
> **Documentos predecessores**:
> `cvmdata_rodada1_fechamento.md`,
> `cvmdata_rodada2_plano_arquitetural.md`,
> `cvmdata_rodada2-5_naming_unificado.md` (versão atualizada com bloco
> "Refinamentos incrementais — Rodada 2.6")
> **Documentos sucessores**: a produzir na Rodada 3 (scaffolding +
> implementação).

---

## 1. Resumo executivo

A Rodada 2.6 teve duas metades. A primeira (sessão anterior) fez
verificação empírica direta no Portal de Dados Abertos CVM
(2026-05-18) e produziu três YAMLs de schema-template em
`inst/extdata/schemas/<dataset>/<tabela>.yaml`, cobrindo casos
representativos de três níveis de complexidade. Essa verificação
também derivou sete refinamentos incrementais ao naming doc da
Rodada 2.5, registrados no próprio naming doc com a marca
`[RESOLVIDO 2.6]` / `[PARCIAL 2.6]` / `[ADIÇÃO 2.6]`.

Esta segunda metade é puramente de síntese. Não há reverificação
empírica nem reabertura de decisões. O entregável é este documento,
que consolida o que foi feito, decidido e o que permanece aberto para
a Rodada 3.

Não houve revisão das 26 decisões da Rodada 2.5. Os refinamentos da
Rodada 2.6 são todos aditivos: precisam de algum lugar canônico do
naming doc os campos `cvm_archive_url_pattern`,
`cvm_file_url_pattern`, `temporal_partitioning`, `first_year` e
`expected_field_count`; e marcam como resolvidas pendências que a
Rodada 2.5 listou em §11. Nenhuma decisão foi revertida.

---

## 2. Entregáveis produzidos

### 2.1 YAMLs (3 arquivos)

Caminhos relativos ao pacote (montagem futura sob
`inst/extdata/schemas/`):

| Arquivo | Caracterização |
|---|---|
| `cad/companhias.yaml` | Caso simples: CSV direto sem ZIP, sem partição temporal, sem transformações declaradas |
| `itr/bpa_con.yaml` | Caso intermediário: CSV dentro de ZIP anual, dicionário também em ZIP, com `multiply_by_scale` + `drop` em `transformations` |
| `fre/administrador_membro_conselho_fiscal.yaml` | Caso categórico: CSV dentro de ZIP anual, dicionário dentro de ZIP, sem transformações declaradas, naming de colunas heterogêneo (`Title_Case_With_Underscores`) |

Conteúdo já validado na primeira metade da rodada. Esta sessão não os
reabre.

### 2.2 Naming doc — refinamentos incrementais aplicados

Os sete refinamentos abaixo aparecem no naming doc atualizado, no bloco
"Refinamentos incrementais — Rodada 2.6" do cabeçalho e nas seções
indicadas. Listagem em ordem do documento, sem discussão (o detalhe
está no próprio naming doc).

1. **§3 — Colunas-chave universais**: adicionada §3.0 com caveat
   empírico sobre a divergência de convenção de naming entre
   CAD/ITR/DFP/FRE-header (SCREAMING_SNAKE_CASE) e FRE-detail
   (Title_Case_With_Underscores). Decisão associada: preservação
   estrita, sem renomeação.
2. **§7.2 — YAML mínimo**: adicionados `cvm_archive_url_pattern` e
   `cvm_file_url_pattern` como pares mutuamente exclusivos para
   distinguir topologia "CSV direto" de "CSV dentro de ZIP".
3. **§7.2 — YAML mínimo**: adicionados `temporal_partitioning`
   (domínio fechado: `none` | `yearly`) e `first_year` (presente
   quando `temporal_partitioning != none`).
4. **§7.2 — YAML mínimo**: adicionado `expected_field_count` como
   apoio à detecção de mudança não-anunciada de schema CVM.
5. **§7.2 — YAML mínimo**: a notação `archive.zip#entry.txt` em
   `cvm_dictionary_url` foi promovida a parte normativa do schema.
6. **§7.2.1 + §7.3 — Domínio de `action`**: removido `convert_to_date`
   do domínio aceito. Conversão de string para `Date` passa a ser
   automática quando o snapshot de dicionário declara
   `tipo_dados = "date"` para a coluna; não deve ser declarada em
   `transformations:`.
7. **§11 — Pendências empíricas**: marcação consistente com novos
   labels (`[RESOLVIDO 2.6]`, `[PARCIAL 2.6]`, `[ADIÇÃO 2.6]`) e
   três adições novas (alerta `Tipo Dados` do META CVM não-confiável
   para identificadores; defeitos de qualidade conhecidos da CVM com
   exemplos verificados; precisão decimal de `VL_CONTA` em R double).

---

## 3. Verificação empírica realizada

Esta seção é um dump de fatos verificados em 2026-05-18, organizado
para auditoria posterior. Não inclui interpretação — interpretações
estão em §4.

### 3.1 Topologia de download por dataset

| dataset/tabela | `cvm_archive_url_pattern` | `cvm_file_url_pattern` | `cvm_file_pattern` | `cvm_dictionary_url` |
|---|---|---|---|---|
| `cad/companhias` | `null` | `https://dados.cvm.gov.br/dados/CIA_ABERTA/CAD/DADOS/cad_cia_aberta.csv` | `cad_cia_aberta.csv` | `https://dados.cvm.gov.br/dados/CIA_ABERTA/CAD/META/meta_cad_cia_aberta.txt` |
| `itr/bpa_con` | `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/ITR/DADOS/itr_cia_aberta_{year}.zip` | `null` | `itr_cia_aberta_BPA_con_{year}.csv` | `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/ITR/META/meta_itr_cia_aberta_txt.zip#meta_itr_cia_aberta_BPA.txt` |
| `fre/administrador_membro_conselho_fiscal` | `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/FRE/DADOS/fre_cia_aberta_{year}.zip` | `null` | `fre_cia_aberta_administrador_membro_conselho_fiscal_{year}.csv` | `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/FRE/META/meta_fre_cia_aberta.zip#meta_fre_cia_aberta_administrador_membro_conselho_fiscal.txt` |

Observações estruturais derivadas da tabela acima:

- **Heterogeneidade real**: nem todos os datasets v0.1 publicam o CSV
  embrulhado em ZIP. CAD é CSV direto; ITR e FRE são ZIPs anuais.
  Justifica a presença simultânea dos campos `cvm_archive_url_pattern`
  e `cvm_file_url_pattern` (mutuamente exclusivos por convenção).
- **Heterogeneidade do dicionário**: CAD publica META como TXT direto;
  ITR e FRE publicam META dentro de um ZIP separado dos dados. ITR
  agrupa o META por demonstrativo (um TXT cobre `bpa_con` e `bpa_ind`);
  FRE granulariza por tabela (um TXT por tabela). Justifica a notação
  `archive.zip#entry.txt`.

### 3.2 Encoding e delimitador (todos os 3 datasets verificados)

Os três datasets foram lidos com sucesso em:

- `encoding: ISO-8859-1`
- `delimiter: ";"`

Confirmado em CAD, ITR/BPA (2024 e 2018) e FRE/administrador (2024).
Nenhum dataset v0.1 verificado neste recorte usou UTF-8 ou separador
distinto. Os dois valores serão tratados como defaults do reader, mas
permanecem declarados em cada YAML (sem indireção implícita).

### 3.3 Inspeção dos dicionários CVM

Forma comum dos arquivos META CVM (bloco repetido por campo):

```
Campo: <nome>
Descrição: <texto livre em PT>
Domínio: <texto: "Alfanumérico", "AAAA-MM-DD", "S/N", "Numero", etc.>
Tipo Dados: <texto: "varchar", "date", "smallint", "numeric", "decimal">
Tamanho: <inteiro>
Precisão: <inteiro, presente em campos numéricos>
Scale: <inteiro, presente em campos numéricos>
```

Contagem empírica de campos por tabela verificada:

| dataset/tabela | Nº de campos no META |
|---|---|
| `cad/companhias` | 46 |
| `itr/bpa_con` | 14 |
| `fre/administrador_membro_conselho_fiscal` | 21 |

Observação central da inspeção: **a CVM não enumera codelists ricas no
META**. Para domínios triviais o `Domínio:` é populado (`S/N`,
`AAAA-MM-DD`); para domínios enumerados maiores
(`ORDEM_EXERC`, `ESCALA_MOEDA`, `Orgao_Administracao`, `SIT`,
`Categoria`, etc.), o META limita-se a `Domínio: Alfanumérico`. Esse
fato motivou §4.4 e §4.5 abaixo.

### 3.4 Inspeção amostral dos CSVs

Cabeçalhos reais (primeira linha do CSV) e amostragem de valores:

- **CAD/companhias** (2026-05-18, snapshot único): 46 colunas,
  `CD_CVM` armazenado sem zero-padding (`35`..`28010`, 2-5 dígitos);
  campos identificadores formalmente `numeric` no META mas que perdem
  zeros à esquerda (CEPs paulistas como 7 dígitos, DDDs, telefones).
- **ITR/BPA_con** (2024 zip): 14 colunas; `CD_CVM` em char(6)
  zero-padded (`000094`..`001023`); `VERSAO` inteiro pequeno (1..5);
  `DT_REFER`, `DT_INI_EXERC`, `DT_FIM_EXERC` em `AAAA-MM-DD`.
- **FRE/administrador_membro_conselho_fiscal** (2024 zip): 21 colunas;
  identificador é `ID_Documento` (não `CD_CVM`); convenção de naming
  Title_Case_With_Underscores; cinco colunas de data (`Data_Referencia`,
  `Data_Eleicao`, `Data_Posse`, `Data_Nascimento`,
  `Data_Inicio_Primeiro_Mandato`); coluna categórica
  `Orgao_Administracao` com codelist específica desta tabela (vide §4.5).

Cross-tab empírica relevante (ITR/BPA, 2024):

| `ORDEM_EXERC` × `ESCALA_MOEDA` | UNIDADE | MIL | MILHÃO | BILHÃO |
|---|---|---|---|---|
| ÚLTIMO | observado | observado | ausente | ausente |
| PENÚLTIMO | observado | observado | ausente | ausente |

Verificação também executada em 2018 (mesmo padrão; sem ocorrências de
`MILHÃO` ou `BILHÃO` nos dois recortes). Decisão associada: manter os
quatro fatores de escala no domínio do reader (`multiply_by_scale`),
em defesa contra mudanças futuras na fonte.

---

## 4. Decisões pontuais novas tomadas na Rodada 2.6

### 4.1 Nome do YAML FRE — `administrador_membro_conselho_fiscal`

**Achado**: o prompt original da Rodada 2.6 (primeira metade) solicitava
`orgao_administracao.yaml`. Inventário empírico do
`fre_cia_aberta_2024.zip` mostra que não existe arquivo com esse nome
no release CVM. `Orgao_Administracao` é uma **coluna** que aparece em
múltiplas tabelas FRE (administrador_membro_conselho_fiscal,
administrador_declaracao_genero, administrador_declaracao_raca,
administrador_PCD, remuneracao_total_orgao, entre outras).

**Alternativa rejeitada**: cunhar uma tabela canônica
`orgao_administracao` agrupando tabelas semanticamente relacionadas
— violaria o princípio reitor "se vem da CVM, fica como na CVM".

**Decisão**: o nome canônico da tabela é
`administrador_membro_conselho_fiscal`, idêntico ao sufixo do CSV
publicado pela CVM. Esta tabela é a fonte master de registros de
administradores; as demais (declaração de gênero, raça, PCD,
remuneração) derivam dela.

### 4.2 Heterogeneidade de naming FRE-detail — preservação estrita

**Achado**: o FRE usa duas convenções distintas dentro do mesmo
dataset. O cabeçalho (`fre_cia_aberta_<ano>.csv`) usa
SCREAMING_SNAKE_CASE igual a CAD/ITR/DFP (`CNPJ_CIA`, `DT_REFER`,
`DENOM_CIA`, `CD_CVM`, `VERSAO`). As ~35 tabelas-detalhe usam
Title_Case_With_Underscores e não trazem `CD_CVM` (o identificador-
documento é `ID_Documento`).

**Alternativa rejeitada**: renomear FRE-detail para uniformizar com o
restante do pacote (`cnpj_companhia` → `cnpj_cia`, etc.).

**Decisão**: preservação estrita. Tibbles FRE-detail retornam
`cnpj_companhia`, `data_referencia`, `nome_companhia`, etc. Joins com
CAD/ITR/DFP exigem mapeamento explícito do usuário (exemplo no naming
doc §3.0). Uma utilitária `cvm_normalize_keys()` permanece
**deferida** para v0.2+ se o caso de uso se justificar empiricamente.
Consequência editorial: a frase "presentes em todo tibble retornado"
da introdução de §3 passa a ser lida como "presentes em CAD + ITR +
DFP + FRE-header".

### 4.3 CD_CVM definitivamente character

**Achado**: `CD_CVM` em CAD está sem zero-padding (`35`..`28010`,
2-5 dígitos); em ITR está zero-padded a 6 (`000094`..`001023`). META
declara `numeric` em ambos.

**Alternativa rejeitada**: coerção para inteiro com formatação no
tempo de impressão — perderia o padding nativo do ITR e quebraria
joins lexicais entre datasets.

**Decisão**: `cd_cvm` mantido como character em **todos** os
datasets, conforme o princípio "identificador → character" já adotado
para `cnpj_cia` e `versao`. Pendência empírica §11.2 da Rodada 2.5
**resolvida**.

### 4.4 Codelists não vêm do META — vêm da varredura empírica do CSV

**Achado**: para domínios enumerados não-triviais (`ORDEM_EXERC`,
`ESCALA_MOEDA`, `Orgao_Administracao`, `SIT`, `Categoria`), o META
limita-se a `Domínio: Alfanumérico`. Não enumera valores.

**Alternativa rejeitada**: tentar derivar codelist do `Domínio:` do
META — fonte vazia para os casos relevantes.

**Decisão**: codelists serão construídas por **varredura empírica do
CSV** (`distinct()` sobre cada coluna categórica em cada tabela),
versionadas em snapshot separado e atualizadas por GitHub Action.
Estrutura do snapshot será definida na Rodada 3 (vide §6).

### 4.5 Codelist é (tabela, coluna), não coluna

**Achado**: a coluna `Orgao_Administracao` aparece em múltiplas
tabelas FRE com codelists materialmente diferentes. Verificado em 2024:

- `administrador_membro_conselho_fiscal` (4 valores): `"Conselho
  Fiscal"`, `"Pertence apenas ao Conselho de Administração"`,
  `"Pertence apenas à Diretoria"`, `"Pertence à Diretoria e ao
  Conselho de Administração"`.
- `administrador_declaracao_genero` (5 valores): `"Conselho Fiscal -
  Efetivos"`, `"Conselho Fiscal - Suplentes"`, `"Conselho de
  Administração - Efetivos"`, `"Conselho de Administração -
  Suplentes"`, `"Diretoria"`.

**Alternativa rejeitada**: tratar codelists como propriedade da
coluna isolada (chave `dataset` + `column`).

**Decisão**: a chave canônica de uma codelist é a tripla
`(dataset, table, column)`. Reflexo na Rodada 3: schema do snapshot
de codelists deve conter essas três colunas como chave composta antes
da coluna `value`.

### 4.6 `convert_to_date` automático — fora do domínio de `action`

**Achado**: o META CVM declara consistentemente `Tipo Dados: date`
com `Domínio: AAAA-MM-DD` para todos os campos de data observados
(formato ISO-8601). Listar `convert_to_date` por coluna em
`transformations:` apenas inflaria os YAMLs sem ganho — `bpa_con`
teria 2 entries só por isso, e `administrador_membro_conselho_fiscal`
teria 5.

**Alternativa rejeitada**: manter `convert_to_date` como ação
declarável para garantir explicitude do schema.

**Decisão**: conversão de `Date` é **automática** sempre que o
snapshot de dicionário declarar `tipo_dados = "date"` para a coluna.
Não se declara em `transformations:`. `convert_to_date` foi removido
do domínio aceito de `action`. Trade-off aceito: a regra "automática"
exige que o snapshot de dicionário esteja disponível no tempo de
leitura — restrição que já é necessária por outras razões (§7.4 do
naming doc).

### 4.7 Aviso geral: `Tipo Dados` do META CVM não é confiável para identificadores

**Achado**: vários campos identificadores são declarados `numeric` no
META mas armazenados com características que exigem character (zeros
à esquerda preservados na fonte, padding lexical, ou perda de zeros
nos dados que precisa ser tratada como caractere para join correto).
Exemplos verificados: `CD_CVM`, `CEP`, `TEL`, `DDD_*` no CAD.

**Alternativa rejeitada**: confiar no `Tipo Dados` declarado e tratar
discrepâncias caso a caso na fase de implementação.

**Decisão**: regra de implementação para a Rodada 3 — para campos
identificadores (CNPJ, CD_CVM, CEP, telefones, CPF), o reader força
character **mesmo quando o META declara numeric**, independentemente
de dataset. A lista canônica de campos sob essa regra fica para ser
formalizada com a implementação.

---

## 5. Resolução de pendências §11 do naming doc

Mapeamento linha por linha dos itens registrados em §11 do naming doc
da Rodada 2.5, com status pós-2.6. Labels usados são exatamente os do
naming doc atualizado.

| item (§11 naming doc) | status pós-2.6 | nota |
|---|---|---|
| Nome do arquivo de cabeçalho de ITR/DFP | `[RESOLVIDO 2.6]` | Confirmado `itr_cia_aberta_<ano>.csv` com 9 campos. Nome canônico-PT da tabela permanece a decidir (vide §6 item 2 deste documento) |
| Nomes finais individuais das ~36 tabelas FRE | `[PARCIAL 2.6]` | Inventário do `fre_cia_aberta_2024.zip` confirma 36 CSVs; mapeamento direto nome-tabela = sufixo-CSV. META tem 50 dicionários (14 a mais que CSVs), indicando tabelas pré-anunciadas pela CVM ainda não populadas. Decisão: incluir só tabelas com dado real em ao menos um release |
| Nomes de tabelas dos datasets v0.2/v0.3 (`fca`, `vlmo`, `cgvn`, `ipe`, etc.) | `[ABERTO]` | Mesma régua a aplicar; verificação empírica em rodada dedicada |
| `cd_cvm` admite zeros à esquerda em ITR mas não em CAD | `[RESOLVIDO 2.6]` | Mantido character em todos os datasets — vide §4.3 |
| `versao` (smallint vs character) | `[PARCIAL 2.6]` | Mantido character por princípio "identificador → character"; sem evidência para reabrir |
| Aviso geral sobre `Tipo Dados` do META CVM | `[ADIÇÃO 2.6]` | Documentado em naming doc §11.2; regra de implementação consolidada em §4.7 deste documento |
| Conteúdo exato do dicionário para as ~75 tabelas v0.1 | `[PARCIAL 2.6]` | 3 dicionários inspecionados; estrutura comum confirmada (formato bloco). Snapshot dos demais ~72 fica para Rodada 3 |
| CVM não publica codelist enumerada no META | `[RESOLVIDO 2.6]` | Codelists serão varridas empiricamente — vide §4.4 |
| Codelist tem escopo (tabela, coluna) | `[RESOLVIDO 2.6]` | Chave composta `dataset` + `table` + `column` — vide §4.5 |
| Colunas constantes candidatas a remoção | `[PARCIAL 2.6]` | Confirmado para `MOEDA = "REAL"` e `GRUPO_DFP` (constante por tabela). Default conservador é manter; consultar mantenedor caso a caso |
| Nome final do snapshot de dicionário (formato e estrutura) | `[ABERTO]` | Rodada 3 — vide §6 item 3 |
| Workflow GitHub Action para atualização do snapshot | `[ABERTO]` | Rodada 3 — vide §6 item 6 |
| Padrão dos arquivos `cvm_file_pattern` em cada YAML | `[PARCIAL 2.6]` | Confirmados para 3 tabelas (vide YAMLs entregues); geração programática do restante na Rodada 3 |
| URL exata do dicionário CVM por tabela | `[PARCIAL 2.6]` | Padrões verificados para CAD (TXT direto), ITR (ZIP com TXT por demonstrativo), FRE (ZIP com TXT por tabela); DFP a confirmar na Rodada 3 |
| Auditoria cruzada de §9 vs transformações aplicadas | `[ABERTO]` | Validação efetiva só com reader implementado — Rodada 3 |
| `vl_conta` em casos limítrofes (negativos, NA, escala mista) | `[ABERTO]` | Dependente de reader implementado — Rodada 3 |
| Defeitos de qualidade conhecidos da CVM | `[ADIÇÃO 2.6]` | Documentados em naming doc §11.5 (BEL em texto livre; CEPs sem zero à esquerda; campos com Descrição/Domínio vazios no META) — vinheta dedicada na Rodada 3 |
| Precisão numérica de `VL_CONTA` (decimal(29,10) vs R double) | `[ADIÇÃO 2.6]` | Documentado em naming doc §11.5; validação empírica na Rodada 3 antes de decidir entre `bit64::integer64`, `decimal64`-like, ou perda documentada |

---

## 6. Pendências e tarefas para a Rodada 3

Plano de ação ordenado por dependência. Cada item é tarefa nomeada com
âmbito definido; não há placeholder genérico.

1. **Snapshot completo do dicionário CVM**. Gerar programaticamente os
   ~72 YAMLs restantes (CAD-companhias já entregue; ITR-bpa_con já
   entregue como template; FRE-administrador_membro_conselho_fiscal já
   entregue como template; faltam 18 tabelas ITR, 18 tabelas DFP +
   header, 35 tabelas FRE-detail + 1 FRE-header). Pré-requisito de
   quase todos os itens seguintes.

2. **Travar nome canônico-PT da tabela de cabeçalho ITR/DFP**. Única
   decisão de naming que permaneceu aberta após a Rodada 2.6. O
   arquivo CVM (`itr_cia_aberta_<ano>.csv` sem sufixo de demonstração)
   não sugere termo natural em PT. Candidatos identificados sem
   decisão: `cabecalho`, `formulario`, `protocolo`, `submissao`. Item
   pequeno, mas precisa preceder a implementação do reader para evitar
   retrabalho. Recomendação editorial: subsessão temática rápida ou
   resolução inline antes da Rodada 3.

3. **Formato do snapshot de dicionário CVM**. Decidir entre
   `inst/extdata/cvm_dictionary_snapshot.csv`, Parquet, ou RDS (o
   naming doc mantém o nome em aberto). Estrutura interna: tabela
   longa com chave composta `dataset` + `table` + `column` e as 7
   colunas do schema de `cvm_dictionary()` (§7.5 do naming doc).
   Considerações: tamanho em disco do CRAN (5 MB de hard limit em
   `inst/extdata`), velocidade de leitura, compatibilidade com `arrow`
   e `duckdb` do stack do pacote.

4. **Formato do snapshot de codelists empíricas**. Chave composta
   `dataset` + `table` + `column` (vide §4.5). Schema mínimo:
   `dataset`, `table`, `column`, `value`, `frequency` (opcional),
   `first_seen_year`, `last_seen_year`. Mesma decisão de formato do
   item 3 — provavelmente acompanha.

5. **Implementação do reader**. Função interna que respeita todas as
   regras do YAML refinado: distinção `cvm_archive_url_pattern` vs
   `cvm_file_url_pattern`; interpolação `{year}`; abertura de ZIP
   sob demanda; aplicação automática de `Date` por inspeção do
   snapshot de dicionário; aplicação das ações de `transformations`
   na ordem declarada; força character para identificadores conforme
   §4.7; validação contra `expected_field_count` no início da
   leitura. Saída: tibble com os 5 atributos canônicos (§5 naming
   doc).

6. **Workflow GitHub Action para atualização periódica**. Detecção
   de mudança não-anunciada de schema CVM via comparação do
   `expected_field_count` entre snapshots; atualização do snapshot
   de dicionário e de codelists; bump automático de YAMLs quando
   mudança detectada. Periodicidade alinhada com o gatilho ETL já
   travado na Rodada 1 (terças 07:00 UTC, event-driven via hash).

7. **Validação empírica em casos limítrofes**. Itens marcados
   `[ABERTO]` em §11.5 do naming doc: `VL_CONTA` em
   `decimal(29,10)` vs R double (testar com valores reais
   extremos da base); defeitos de qualidade conhecidos da CVM (BEL
   em texto livre, CEPs sem zero à esquerda, campos com META
   parcial); cross-tab `vl_conta` × `ordem_exerc` com NA/negativos
   em escala mista entre linhas de uma mesma tabela.

Itens 1–4 são pré-requisitos do item 5. Item 6 depende de 1 e 3.
Item 7 depende de 5 estar minimamente funcional.

---

## 7. Pergunta acionável para o mantenedor

Próximo passo da Rodada 3 — escolher uma opção:

(a) **Seguir para a Rodada 3 plena**: scaffolding do pacote
(DESCRIPTION, NEWS, estrutura de diretórios, renv, CI workflows) +
geração programática dos ~72 YAMLs restantes a partir de inspeção
em lote do Portal CVM, em sequência.

(b) **Subsessão temática 3.0 dedicada** ao item 2 acima (travar nome
canônico-PT do header ITR/DFP) e aos itens 3 e 4 (formato e estrutura
dos snapshots de dicionário e de codelists), antes da Rodada 3
propriamente dita. Tira do caminho crítico três decisões de design
pequenas mas com consequências em cascata.

(c) **Revisar este documento primeiro** — apontar correções,
omissões, ou solicitar mais detalhe em alguma seção antes de avançar.

Qual?
