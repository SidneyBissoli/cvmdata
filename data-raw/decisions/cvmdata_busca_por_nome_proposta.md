# Proposta: achar o CNPJ de uma companhia pelo nome

Status: **primeira etapa APROVADA e implementada em 2026-11-16**
(decisão do dono na revisão humana: `cnpj_lookup()`, os três cadastros
do `cad`, nomes anteriores e coluna `ticker` para a segunda etapa).
Diferença do texto abaixo: a saída é um tibble simples, não um
`cvm_tbl` (§3.3), como as outras funções de descoberta
(`cvm_arguments()`); os atributos de proveniência de três tabelas não
cabem num `cvm_tbl` de uma tabela só.

## 1. Problema

`cvm_fetch()` seleciona a companhia só por `cnpj` ou `ticker`. O ticker
resolve as companhias listadas na B3, deslistadas incluídas, mas quem
procura uma companhia sem ticker (fechada, só com dívida, cancelada
antes de 2018) precisa do CNPJ, e quase ninguém o sabe de cabeça.

Hoje o caminho é uma receita que o usuário precisa conhecer:

```r
cad <- cvm_fetch("cad", "companhias")
cad[grepl("petrobras", cad$denom_social, ignore.case = TRUE), ]
```

Três defeitos: (a) a receita não aparece onde o usuário trava; o erro
de `check_cnpj()` (`R/api-cvm-fetch.R`) diz que nome não é aceito, mas
não diz onde achar o CNPJ; (b) `grepl()` não ignora acento ("PETROLEO"
não casa com "PETRÓLEO"); (c) a tabela repete a companhia por
`tp_merc` (107 registros), então a resposta vem com linhas duplicadas.

## 2. O que NÃO se reabre

A remoção de `issuer_fetch()` (2026-11-01, `NEWS.md`) continua valendo:
`cvm_fetch()` recebe só CNPJ ou ticker, não adivinha o tipo da entrada
e nunca abre `utils::menu()`. A proposta separa as duas etapas:
**descobrir** (função nova, devolve candidatos) e **buscar** (o
`cvm_fetch()` de sempre, com o CNPJ escolhido pelo usuário). É o mesmo
padrão de `cvm_datasets()` → `cvm_tables()` → `cvm_fetch()`.

Por que não um argumento `name` em `cvm_fetch()`, mesmo que aborte
quando o nome é ambíguo: (1) nome muda (BR Distribuidora → Vibra) e o
script deixa de ser reprodutível; o CNPJ não muda; (2) um nome parcial
casa com várias companhias, e a função teria que escolher ou perguntar;
(3) reabre a decisão de 2026-11-01.

## 3. Proposta

Uma função exportada, na família de utilidades de CNPJ:

```r
cnpj_lookup(name, source = NULL)
```

### 3.1 Nome da função

| Opção | Prós | Contras |
|---|---|---|
| **`cnpj_lookup()`** (recomendada) | Diz o que entrega; par natural de `cnpj_clean()` / `cnpj_format()`; `object_verb` como pede o rOpenSci; serve para fundos na v0.4 (fundo também tem CNPJ) | Devolve um tibble, não um vetor de CNPJs |
| `cvm_companies()` | Na família de descoberta (`cvm_tables()`...) | Amarrada ao grupo companhias; os fundos pediriam outra função, contra o espírito da função única |
| `cvm_company_search()` | Explícita | Longa; o mesmo problema de grupo |

### 3.2 Entrada

- `name`: string única, obrigatória, não vazia. Vetor de comprimento
  maior que 1 = `cvmdata_error_input` (uma busca por chamada; quem
  precisa de várias faz `lapply`).
- A busca é por **palavras**, sem regex: cada palavra de `name` precisa
  aparecer, em qualquer ordem, ignorando caixa e acento.
  `"banco brasil"` casa com `"BANCO DO BRASIL S.A."`; `"s.a."` não vira
  regex.
- Campos pesquisados: `denom_social` e `denom_comerc`.
- Acento: tabela fixa com `chartr()` (á→a, ç→c, ...). Sem dependência
  nova: o pacote não importa `stringi` e o `iconv(..., "ASCII//TRANSLIT")`
  dá resultados diferentes por sistema operacional.
- `source`: o mesmo de `cvm_fetch()` (espelho por padrão), lido pela
  opção da sessão e com o retrato de `cvm_release_set()`.

### 3.3 Saída

Um `cvm_tbl` com **uma linha por registro** `(cnpj_cia, cd_cvm)`, com
as repetições por `tp_merc` colapsadas (decisão do pacote: é uma
função de descoberta, não devolve tabela da CVM). Colunas, nos nomes
da CVM:

`cnpj_cia`, `denom_social`, `denom_comerc`, `cd_cvm`, `sit`, `dt_reg`,
`dt_cancel`, `table`

- `table` diz de qual cadastro veio (`companhias`, `estrangeiras`,
  `incentivadas`); nas duas últimas a coluna da CVM é `cnpj` e vira
  `cnpj_cia` aqui.
- Ordem: ativas primeiro (`dt_cancel` vazia), depois por `denom_social`.
- Canceladas **entram**: deslistada é justamente quem não tem ticker.
- Sem resultado: tibble de zero linhas + `cli_inform()` sugerindo menos
  palavras. Não é erro: uma busca vazia é resposta válida.
- Nunca escolhe, nunca pergunta, nunca abre menu.

### 3.4 Integração

- O erro de `check_cnpj()` ganha uma linha: "Look a company's CNPJ up
  with `cnpj_lookup()`".
- `?cvm_fetch` (parâmetro `cnpj`), README e vinheta mostram o fluxo
  `cnpj_lookup()` → `cvm_fetch(cnpj = ...)`.
- `@family` junto de `cnpj_clean()` / `cnpj_format()`.

## 4. Decisões em aberto (para o dono)

1. **Nome da função**: recomendo `cnpj_lookup()` (§3.1).
2. **Cadastros pesquisados**: recomendo os três do `cad` (`companhias`,
   `estrangeiras`, `incentivadas`), com a coluna `table`. Alternativa:
   só `companhias`, que é a tabela que alimenta DFP/ITR/FRE.
3. **Nomes anteriores**: `fca/geral` tem `nome_empresarial_anterior` e
   `data_nome_empresarial`; com eles, `"BR Distribuidora"` acharia a
   Vibra. Custa ler o `fca/geral` de todos os anos (como o resolvedor
   de ticker faz com `valor_mobiliario`). Recomendo **deixar para uma
   segunda etapa**: a primeira versão lê uma tabela só e já resolve a
   maior parte dos casos.
4. **Coluna `ticker`** na saída (códigos B3 do CNPJ, pela união dos
   anos do FCA, como `resolve_ticker_all_years()`): liga a busca ao
   argumento mais amigável. Custa a mesma leitura do FCA, mas ela já é
   cacheada na sessão. Recomendo **também na segunda etapa**, junto
   com os nomes anteriores, porque as duas leem o FCA.

## 5. Testes previstos

Sem rede, sobre `tests/testthat/fixtures/cad_sample.csv`:

- acento e caixa ("petroleo" acha "PETRÓLEO");
- várias palavras em qualquer ordem;
- colapso de `tp_merc` e preservação dos dois registros de um CNPJ com
  dois `cd_cvm`;
- canceladas presentes e ordenadas depois das ativas;
- zero resultados = tibble vazio + mensagem, sem erro;
- `name` ausente, vazio, `NA` ou com comprimento > 1 = `cvmdata_error_input`;
- `cnpj` de `estrangeiras`/`incentivadas` sai como `cnpj_cia`;
- a mensagem nova de `check_cnpj()` (snapshot).

## 6. Custo

Uma função de cerca de 60 linhas em `R/util-cnpj.R`, testes, documentação
e a linha no erro. Sem dependência nova, sem mudança no espelho ou no
ETL. Entra no `NEWS.md` como função nova (sem quebra de compatibilidade).
