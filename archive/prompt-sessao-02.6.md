# Prompt — Rodada 2.6: YAMLs de schema como prova de conceito

## Contexto

Esta é a Rodada 2.6 do projeto `cvmdata`. A Rodada 2.5 fechou todas as
decisões de naming e está documentada em
`cvmdata_rodada2-5_naming_unificado.md`. Esta subsessão produz os
**YAMLs de schema** previstos no prompt original da Rodada 2.5 (seção
"Entregáveis ao fim da sessão", item 2) e que foram deliberadamente
diferidos para sessão dedicada por demandarem verificação empírica nos
arquivos CVM.

Esta é subsessão temática, paralela à Rodada 2.5. Rodada 3
(scaffolding + implementação) vem depois.

## Documentos de referência (já nos arquivos do projeto)

Leia-os antes de fazer qualquer outra coisa:

- `cvmdata_projeto_instrucoes_customizadas.md` — instruções do projeto,
  régua de idioma, convenções de código (versão atualizada
  pós-Rodada 2.5)
- `fechamento-rodada-01.md` — decisões macro travadas
- `cvmdata_rodada2_plano_arquitetural.md` — plano técnico (com Seção 0
  apontando para o documento de naming canônico)
- `cvmdata_rodada2-5_naming_unificado.md` — **documento canônico de
  naming**; prevalece sobre o plano arquitetural em caso de conflito

## Escopo desta sessão

Produzir 3 YAMLs de schema completos, prontos para servirem de
template para os ~75 YAMLs restantes que serão gerados
programaticamente na Rodada 3:

1. **`cad/companhias.yaml`** — uma tabela do dataset CAD (Cadastro de
   companhias abertas). Caso mais simples; serve como prova de conceito
   da estrutura mínima sem transformações complexas.
2. **`itr/bpa_con.yaml`** — Balanço Patrimonial Ativo consolidado do
   ITR. Caso intermediário; contém a transformação `vl_conta` ×
   `escala_moeda` e remoção de `escala_moeda`, conforme §9 do
   documento de naming.
3. **`fre/orgao_administracao.yaml`** — Órgão de Administração do FRE.
   Caso de tabela FRE com colunas categóricas (codelist em
   `governing_body` análogo, valores em PT preservados como vêm da
   CVM).

Os três YAMLs são exemplares representativos:

- CAD = um arquivo, sem complicações
- ITR/BPA = tabela contábil com transformação que altera forma
- FRE = tabela com codelist categórica

A geração programática dos ~75 YAMLs restantes a partir do snapshot
de dicionário CVM fica para Rodada 3.

## Régua de idioma vigente (resumo; ver §0 do documento de naming)

- Funções, argumentos, atributos de tibble, classes de condição,
  options, nomes de arquivo e pasta, comentários, README, NEWS,
  DESCRIPTION, mensagens: **inglês**.
- Nomes de tabelas, nomes de colunas nos tibbles retornados,
  colunas-meta de funções de descoberta, valores categóricos, texto
  livre: **português** (snake_case minúsculo; preservar como vem da
  CVM).
- Princípio reitor: se vem da CVM, fica como na CVM (apenas com
  normalização tipográfica).

## Estrutura mínima do YAML (vide §7.2 do documento de naming)

```yaml
# inst/extdata/schemas/<dataset>/<table>.yaml
dataset: <dataset>
table: <table>
cvm_file_pattern: "<padrão de nome do arquivo CVM, com {year} interpolável>"
cvm_dictionary_url: "<URL do META_*.txt no portal CVM>"
encoding: ISO-8859-1
delimiter: ";"

# Seção opcional; presente apenas em tabelas com transformações
transformations:
  - column: <coluna>
    action: <ação>
    note: "<justificativa>"
```

Domínio de `action` definido em §7.3 do documento de naming:
`multiply_by_scale`, `drop`, `convert_to_date`, `keep_latest_version`.
Caso a verificação empírica revele necessidade de ações adicionais
(ex.: parsing de datas em formato não-ISO, normalização de strings),
incluir nesta sessão a definição do novo `action` antes de usar no
YAML — e atualizar o documento de naming na seção §7.3 como adição
incremental documentada.

## Método obrigatório: verificação empírica

Esta sessão **exige verificação empírica** nos arquivos CVM. Diferente
da Rodada 2.5 (raciocínio puro sobre decisões), aqui não se inventa
valor que possa ser verificado. Antes de escrever cada YAML:

### Passo 1 — Localizar arquivo CVM correspondente

Para cada uma das três tabelas, identificar empiricamente:

- URL exata do dataset no portal de Dados Abertos CVM
  (`dados.cvm.gov.br`)
- Nome do arquivo ZIP que contém o CSV (ex.:
  `cad_cia_aberta.zip`, `itr_cia_aberta_2024.zip`,
  `fre_cia_aberta_2024.zip`)
- Nome do arquivo CSV dentro do ZIP, com padrão para `{year}` quando
  aplicável (ex.: `itr_cia_aberta_BPA_con_2024.csv`)
- URL do arquivo de dicionário (`META_*.txt`) correspondente à tabela

Usar `web_fetch` ou `web_search` ativamente para validar URLs. Se uma
URL não for verificável, marcar `[NÃO VERIFICADO]` ao lado e listar na
pendência.

### Passo 2 — Inspeção do dicionário CVM

Para cada uma das três tabelas, **fazer download e inspecionar** o
arquivo `META_*.txt` correspondente. Extrair literalmente:

- Lista completa de campos (`campo`)
- Descrição em PT (`descricao`)
- Tipo de dados (`tipo_dados`)
- Domínio (`dominio`) — codelist quando aplicável
- Tamanho (`tamanho`)
- Precisão (`precisao`) — para campos numéricos
- Escala (`scale`) — para campos numéricos

Esses dados **não vão no YAML mínimo** (o snapshot de dicionário vive
separado, conforme §7.4 do documento de naming), mas são necessários
para:

- Validar nomes de campo e gerar a versão snake_case minúsculo do nome
  bruto CVM
- Identificar quais campos requerem transformação documentada no YAML
- Resolver pendências empíricas §11.2 (`cd_cvm` admite zeros à
  esquerda? `versao` tem formato não-numérico?)

### Passo 3 — Inspeção amostral do CSV

Para cada tabela, baixar amostra pequena do CSV correspondente
(primeiras N linhas suficientes para verificar). Validar:

- Encoding real do arquivo (presumivelmente ISO-8859-1; confirmar)
- Delimitador real (presumivelmente `;`; confirmar)
- Que os campos batem com o `META_*.txt`
- Conteúdo concreto de algumas colunas (especialmente `cd_cvm`,
  `versao`, valores categóricos que aparecerão como codelist)

Sem essa validação, o YAML é inferência. Com ela, é fato.

### Passo 4 — Decisões pontuais à medida que aparecerem

Pequenas decisões de naming podem aparecer durante a verificação
(nomes individuais das colunas em snake_case quando o CVM bruto tem
abreviações inconsistentes; tratamento de caracteres especiais; etc.).
Tratá-las uma a uma com o mantenedor, mesmo método da Rodada 2.5:
script visual quando aplicável, decisão registrada explicitamente.

### Passo 5 — Resolução de pendências §11 do documento de naming

Algumas pendências da §11 do documento de naming canônico devem ser
resolvidas nesta sessão à medida que o passo 2 e 3 forneçam evidência
empírica:

- §11.1 — nome do arquivo de cabeçalho ITR/DFP (descoberta empírica)
- §11.2 — `cd_cvm` admite zeros à esquerda? `versao` em formato
  inesperado?
- §11.3 — codelist completa de colunas categóricas das três tabelas
  escolhidas (decisão sobre se vai para dicionário-snapshot ou para
  YAML)
- §11.4 — URL exata do dicionário CVM por tabela; padrão exato de
  `cvm_file_pattern`

Resolução parcial é aceitável: registrar o que foi resolvido e o que
permanece pendente para Rodada 3.

## Decisões de design adicionais que podem aparecer

Algumas decisões podem emergir durante a sessão e não estão fechadas
em §7 do documento de naming. Cada uma deve ser tratada com o método
da Rodada 2.5 (script visual quando aplicável, alternativas com
prós/contras, recomendação fundamentada, decisão do mantenedor):

- Formato exato do snapshot de dicionário CVM
  (`inst/extdata/cvm_dictionary_snapshot.csv`? Parquet? RDS? YAML
  único?)
- Estrutura interna do snapshot (uma linha por (dataset, tabela,
  campo)? Aninhado por tabela?)
- Estratégia para versionamento do snapshot (a CVM pode mudar
  dicionário; como detectar mudança e atualizar?)
- Política para `convert_to_date`: já é default? Precisa estar
  declarado no YAML ou é regra hardcoded?
- Como o YAML lida com campos do dicionário CVM que não aparecem no
  CSV (campos opcionais ou obsoletos)
- Tratamento de codelists que mudam ao longo dos anos (compatibilidade
  retroativa)

Não inventar respostas. Quando incerto, declarar pendência.

## Restrições

- **Não inventar URLs, nomes de arquivo CVM, nem conteúdo de
  dicionário CVM.** Tudo verificado via `web_fetch`/`web_search` ou
  marcado explicitamente como `[NÃO VERIFICADO]` com listagem em
  pendências.
- **Não traduzir nomes de tabela, nomes de coluna ou valores de
  célula que vêm da CVM** (régua canônica). Apenas normalização
  tipográfica para snake_case minúsculo.
- **Comentários internos dos YAMLs em inglês** (régua de idioma —
  arquivos do projeto em EN).
- **Conteúdo factual dos YAMLs reflete o CVM real**, não suposição.
- Não reabrir decisões da Rodada 1 ou da Rodada 2.5 sem evidência
  nova substancial. As 26 decisões de naming estão travadas.

## Entregáveis ao fim da sessão

1. **3 arquivos YAML** em `/mnt/user-data/outputs/schemas/`:
   - `cad/companhias.yaml`
   - `itr/bpa_con.yaml`
   - `fre/orgao_administracao.yaml`

2. **Documento de acompanhamento** em
   `/mnt/user-data/outputs/cvmdata_rodada2-6_schemas.md` contendo:
   - Resumo do que foi verificado empiricamente vs o que ficou
     pendente
   - Decisões pontuais novas tomadas durante a sessão (com link às
     novas seções do documento de naming, se houver)
   - Resolução parcial das pendências §11 do documento de naming
   - Lista atualizada de pendências para Rodada 3
   - Eventual proposta de adição/refinamento ao documento de naming
     canônico (sem reabertura de decisão travada — apenas
     incrementos)

3. **Atualização incremental** do `cvmdata_rodada2-5_naming_unificado.md`
   quando emergirem refinamentos compatíveis (novos `action` aceitos
   em `transformations`, refinamento de tipos pós-verificação
   empírica, etc.). Marcar incrementos como tal; não reabrir decisões
   já fechadas.

## Tom e padrões

Seguir as Custom Instructions do projeto:

- Tom direto, sem fluff.
- Verificação empírica preferida sobre documentação secundária.
- Quando há ferramentas (`web_fetch`, `bash_tool`, `web_search`),
  usá-las ativamente em vez de inferir.
- Honestidade técnica acima de evitar fricção.
- Alternativas com prós/contras quando relevante.
- Sem reabrir decisões travadas.
- Comentários de código e identificadores em inglês.
- Para qualquer decisão emergente, método visual (script R executável
  no RStudio) quando ajudar — método validado na Rodada 2.5.

## O que esta sessão NÃO faz

- Não gera os ~75 YAMLs restantes (fica para Rodada 3, programaticamente).
- Não implementa código R do pacote (Rodada 3).
- Não decide nada sobre scaffolding, CI, testes (Rodada 3).
- Não reabre as 26 decisões travadas da Rodada 2.5.
- Não muda a régua geral de idioma (§0 do documento de naming).

## Ao terminar

Pergunte ao usuário se ele quer:

(a) Revisar os YAMLs antes de seguir → próxima sessão revisa e ajusta.
(b) Seguir direto para Rodada 3 (scaffolding + implementação).
(c) Fazer outra subsessão temática pendente antes da Rodada 3 (se
    houver — verificar se sobrou algo de fora do escopo de
    naming/schemas).

---

FIM DO PROMPT — não adicione nada depois desta linha.
