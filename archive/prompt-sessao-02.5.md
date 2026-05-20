# Prompt — Rodada 2.5: Naming unificado e dicionário de dados

## Contexto

Esta é a Rodada 2.5 do projeto `cvmdata`. As Rodadas 1 e 2 estão
concluídas; o plano arquitetural está travado em
`cvmdata_rodada2_plano_arquitetural.md`. Esta sessão é uma das três
pendências decisórias antes da implementação (Rodada 3).

Os arquivos travados disponíveis no projeto são:

- `cvmdata_rodada1_fechamento.md` — decisões macro (não reabrir)
- `cvmdata_rodada2_plano_arquitetural.md` — plano técnico (não reabrir
  decisões estruturais)
- Custom instructions do projeto (idioma, tom, convenções de código,
  arquitetura multi-classe)

## Escopo desta sessão

Decidir o naming canônico em snake_case inglês para:

1. **Nomes finais das tabelas FRE** (36 tabelas, categorizadas A-J no
   plano). Algumas têm tradução ambígua do português; precisamos
   decidir caso a caso entre tradução literal e tradução informativa.
2. **Nomes finais das tabelas ITR/DFP** (19 tabelas cada, espelhadas
   entre os dois datasets). Decidir abreviações vs expansão (`bpa_con`
   vs `balance_sheet_assets_consolidated`).
3. **Coluna padronizada de período**: `period_end_date` vs
   `reference_date` vs `as_of_date` vs `period`. Decidir uma e aplicar
   em todos os datasets.
4. **Convenção de naming para colunas de moeda**: sufixo `_brl` para
   reais; tratamento de DRE em milhares (`_brl_thousands` vs converter
   para reais inteiros no transform).
5. **Política de naming para abreviações CVM** (`dpc`, `dva`, `dmpl`,
   `bpa`, `bpp`, `dfc`, `dre`, `dra`): manter sigla ou expandir?
   Decidir critério geral.
6. **Nomes dos argumentos públicos** das funções fetch. O plano usa
   `entities`, `years`, `quarters`, `table`, `dataset`, `source`,
   `on_error`, `validate`. Confirmar ou ajustar.

## Pendência adicional incorporada nesta sessão

7. **Função de dicionário de dados** — `cvm_dictionary()` ou
   equivalente. A CVM publica dicionários de metadados (arquivos
   `meta_*.csv` dentro dos ZIPs). Como renomeamos colunas, o usuário
   precisa de uma ponte explícita entre nome tidy e nome CVM original.
   Decidir:
   - Assinatura da função (`cvm_dictionary(dataset, table)`?
     `dictionary(...)`? `column_map()`?)
   - Formato do retorno (tibble com colunas
     `tidy_name`/`cvm_name`/`description_en`/`description_pt`/`type`?)
   - Onde mora o dado fonte (YAMLs de schema já têm `cvm` e `tidy`;
     adicionar `description_en` e `description_pt`?)
   - Se o pacote também expõe o dicionário em português via
     `cvm_dictionary(..., lang = "pt-BR")`.
   - Se há uma função paralela para listar tabelas
     (`cvm_tables(dataset)`) e datasets (`cvm_datasets()`).

## Método sugerido

1. **Disparar pesquisa avançada no início da sessão** investigando
   convenções de naming em pacotes CRAN análogos. Alvos sugeridos:
   `tidycensus` (variáveis ACS com codes técnicos vs nomes humanos),
   `microdatasus` (variáveis DATASUS com siglas vs expansão),
   `GetDFPData2` (precedente direto, mesmo domínio CVM),
   `WDI`/`wbstats` (Banco Mundial, mesma classe de problema),
   `tradestatistics`, `nasapower`. Buscar:
   - Como tratam abreviações técnicas do dado fonte
   - Se expõem dicionário e como
   - Convenções para colunas de moeda e período
   - Argumentos típicos em funções de download
2. **Decidir por categoria, não por item.** Para FRE, definir 3-4
   regras de naming (e.g., "ações afirmativas como `directors_X`",
   "remuneração como `compensation_X`") e aplicar consistentemente.
3. **Produzir entregável persistente**:
   `cvmdata_rodada2-5_naming_unificado.md` em
   `/mnt/user-data/outputs/`, com tabelas completas de
   nome-CVM → nome-tidy para todas as colunas das 74 tabelas
   (19 ITR + 19 DFP + 36 FRE + CAD).
4. **Produzir YAMLs de schema** prontos para implementação em
   `/mnt/user-data/outputs/schemas/` (CAD + amostra de 2-3 tabelas
   ITR/FRE como prova de conceito). Os demais podem ser gerados
   programaticamente na Rodada 3 a partir das tabelas de mapeamento.

## Restrições

- Nomes em **inglês**, snake_case, sem caracteres especiais.
- Nomes ≤30 caracteres preferencialmente; permitir até 40 quando
  expansão melhorar clareza substancialmente.
- Manter `cnpj`, `cvm_code`, `b3_ticker` como identifiers — já
  travados na Rodada 2.
- Sem prefixo de tabela em nomes de coluna (`bpa_account_code` é
  redundante; usar `account_code`); o contexto vem do nome da tabela
  e da função fetch.
- Compatibilidade com arquitetura multi-classe: nomes que vão
  reaparecer em fundos (e.g., `period_end_date`, `cnpj`) devem ser
  decididos pensando em todas as classes, não só companhias.

## O que esta sessão NÃO decide

- Estrutura de diretórios (travada na Rodada 2)
- Assinatura genérica de `fetch_cvm()` (travada)
- Política de cache (travada)
- Decisões editoriais do mantenedor (vão para Rodada 2.6)
- Cobertura pré-2010 (vai para Rodada 2.7)

## Entregáveis ao fim da sessão

1. `cvmdata_rodada2-5_naming_unificado.md` com:
   - Decisões de naming categorizadas
   - Tabela completa CVM→tidy para CAD, ITR (19 tabelas), DFP
     (19 tabelas), FRE (36 tabelas)
   - Especificação completa da função `cvm_dictionary()` e auxiliares
     (`cvm_tables()`, `cvm_datasets()`)
   - Justificativa para escolhas controversas
2. `cvmdata_rodada2-5_schemas/` com YAMLs prova-de-conceito de
   CAD + 2-3 tabelas representativas de ITR e FRE
3. Lista atualizada de pendências para 2.6 e 2.7

## Tom e padrões

Seguir as Custom Instructions do projeto: tom direto, sem fluff;
verificação empírica preferida; alternativas com prós/contras
quando relevante; sem reabrir decisões travadas; comentários de
código e identificadores em inglês.
