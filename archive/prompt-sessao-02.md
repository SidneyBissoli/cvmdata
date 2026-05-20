# Prompt — Rodada 2 do pacote R `cvmdata`

## CONTEXTO HERDADO DA RODADA 1

Esta é a Rodada 2 de um projeto de longo prazo: construção de um pacote
R chamado `cvmdata`. O pacote será publicado no CRAN e tem como
objetivo de longo prazo ser uma API tidy para **todo o universo de
dados abertos publicados pela CVM** (Comissão de Valores Mobiliários),
em qualquer classe de entidade regulada — companhias abertas, fundos
de investimento (ICVM 555), fundos de investimento imobiliário (FII),
fundos de investimento em direitos creditórios (FIDC), fundos
estruturados, companhias estrangeiras, emissores. O escopo será
incremental por versões.

O autor é Sidney da Silva Pereira Bissoli — mantenedor do pacote 
`educabR` no CRAN, com experiência prévia em desenvolvimento de pacotes 
R envolvendo dados públicos brasileiros.

A Rodada 1 (sessão anterior) cobriu seis sub-rodadas de verificação
empírica e travou todas as decisões de escopo, fonte de dados,
arquitetura macro e estratégia operacional. O fechamento dessa rodada
foi salvo em arquivo persistente do projeto:

**Antes de fazer qualquer outra coisa, leia este arquivo agora**:
`/mnt/project/cvmdata_rodada1_fechamento.md` ou
`/mnt/user-data/uploads/cvmdata_rodada1_fechamento.md` (o usuário deve
ter colocado uma cópia em uma dessas pastas; se não estiver, peça ao
usuário para anexar).

Esse arquivo contém o resumo executivo de TODAS as decisões já
travadas: nome do pacote, visão de longo prazo (universo completo CVM),
escopo v0.1/v0.2/v0.3/v0.4+, arquitetura de fontes (CVM primária +
mirror GitHub Releases secundário), estratégia ETL, padrão de API
(Padrão C híbrido), pendências para a Rodada 2.

NÃO QUESTIONE as decisões da Rodada 1. Elas vieram de 6 sub-rodadas de
investigação empírica (incluindo execução de R em sandbox, scraping de
endpoints B3 e RAD para verificação, inspeção de pacotes Python
concorrentes, análise de termos de uso, e medição empírica do Portal
CVM). Reabrir essas decisões consome a sessão sem produzir resultado.

## ESCOPO DESTA SESSÃO

Produzir UM ÚNICO DOCUMENTO markdown completo, salvo em
`/mnt/user-data/outputs/cvmdata_rodada2_plano_arquitetural.md`,
contendo o **plano arquitetural completo** do pacote `cvmdata`.

O documento deve ter entre 15 e 30 mil palavras. Não economize espaço —
mas também não infle artificialmente. Cada seção deve ser COMPLETA o
suficiente para guiar a construção, sem deixar buracos que exigiriam
"depois eu decido".

### IMPORTANTE: arquitetura multi-classe

Embora a v0.1 cubra apenas companhias abertas, o plano arquitetural
deve prever desde o início suporte multi-classe (fundos, FII, FIDC,
etc.). Decisões de design que travem o pacote em uma única classe
devem ser rejeitadas. Estrutura de diretórios, API, schemas, cache e
ETL devem ser pensados como **plataforma para múltiplas classes de
entidades**, com a v0.1 implementando apenas uma classe como prova de
conceito.

## ESTRUTURA OBRIGATÓRIA DO DOCUMENTO

Use exatamente estas 12 seções, nesta ordem:

### 1. Sumário Executivo

Visão de 1 página do plano. Para alguém que abre o documento, deve
permitir decidir se este é o pacote certo para o problema dele.

### 2. Arquitetura de Pacote

- Estrutura de diretórios (`R/`, `tests/`, `vignettes/`, `data-raw/`,
  `inst/`, `man/`, `pkgdown/`, `.github/workflows/`)
  - Organização por classe de entidade quando fizer sentido
    (`R/companies/`, `R/funds/`, etc.) ou por função (`R/api/`,
    `R/schemas/`, `R/cache/`)? Decidir e justificar.
- Sistema de classes: justificar S3 vs S4 vs R6 (a escolha deve ser S3
  por aderência ao tidyverse, mas justifique)
- Dependências: lista completa em `Imports`, `Suggests`, `Depends`,
  `LinkingTo`. Para cada uma, justifique. Priorize tidyverse + arrow +
  duckdb. Minimizar dependências externas.
- Namespace strategy: o que exportar, o que manter interno
- Padrão de nomeação de arquivos R/ (um arquivo por família de
  funções?)
- Padrão de comentários em código: inglês, estilo roxygen2

### 3. Design da API Pública

Operacionalizar o **Padrão C híbrido** decidido na Rodada 1, com
extensão para múltiplas classes de entidades:

```r
# Espinha dorsal multi-classe
fetch_cvm(dataset, table = NULL, entities = NULL, period = NULL, ...)

# Aliases tipados v0.1 (companhias)
fetch_itr(table, companies, years, ...)
fetch_dfp(table, companies, years, ...)
fetch_fre(table, companies, years, ...)
fetch_cad(companies, ...)

# Aliases tipados v0.4+ (fundos, ilustrativo)
fetch_fii(table, funds, dates, ...)
fetch_fidc(table, funds, dates, ...)
```

Decisões a fechar nesta seção:
- Assinatura COMPLETA de cada função pública (todos os argumentos,
  defaults, tipos)
- Como `fetch_cvm()` dispatch interno reconhece a classe (companhia vs
  fundo) a partir do `dataset` argument
- Comportamento de retorno (tibble com atributos? lista? data.frame?)
- Tratamento de argumentos vazios/`NULL` (retornar tudo? erro?)
- Validação de inputs: companies aceita CD_CVM numérico, ticker B3,
  CNPJ? Funds aceita CNPJ? Como detecta automaticamente?
- Funções auxiliares: `list_datasets(class = NULL)`,
  `list_tables(dataset)`, `cvm_metadata()`, `cvm_cache_clear()`,
  `cvm_source_info()`
- Atributos de saída: `source` (cvm/mirror), `fetched_at`, `n_entities`,
  `class` (companies/funds/etc.)
- Tratamento de erros: mensagens em inglês (porque vão para o CRAN),
  códigos, `rlang::abort()`?

**Não decida nomes finais ainda** — usuário pediu subsessão dedicada
para isso depois. Mas deixe a ESTRUTURA da API definida (quantas
funções, quais argumentos, qual dispatch interno, como expande para
classes futuras).

### 4. Schemas Tidy de Saída

Para cada um dos datasets do v0.1 (`cad`, `itr`, `dfp`, `fre`),
documentar:

- Lista completa de tabelas internas no ZIP CVM
- Para cada tabela: schema CVM original (colunas, tipos, encoding) →
  schema tidy de saída (colunas em snake_case em inglês, decisão
  CRAN-aderente)
- Regras de transformação (parsing de datas; valores monetários;
  codes hierárquicos como CD_CONTA "3.01.01")
- Tratamento de VERSAO (reapresentações)
- Tratamento de ORDEM_EXERC (ÚLTIMO / PENÚLTIMO → current / previous?)
- Tratamento do "4º trimestre ausente" no ITR
- ESCALA_MOEDA (MIL → multiplicar VL_CONTA × 1000?)

Para o FRE especificamente, dada sua complexidade (36 tabelas),
categorize:
- Tabelas financeiras (capital_social, distribuicao_capital, etc.)
- Tabelas de governança (administradores, comitês, auditor)
- Tabelas ESG (gênero, raça, PCD, remuneração, faixa etária)
- Tabelas de relacionamentos (relacao_familiar, relacao_subordinacao)
- Tabelas de valores mobiliários (titular_valor_mobiliario,
  outro_valor_mobiliario)

Definir também o **modelo de schemas extensível** para classes futuras:
como adicionar schemas de FII, FIDC etc. sem refatorar a estrutura.

### 5. Estratégia de Cache

- Cache de quê? (ZIP CVM bruto? CSVs descompactados? Parquet
  transformado? resultado de query?)
- Onde armazenar? (`tools::R_user_dir("cvmdata", "cache")` segue
  padrão CRAN policy)
- Política de invalidação (TTL? hash? manual via `cvm_cache_clear()`?)
- Backend: `cachem`? Arquivos diretos? DuckDB local?
- Tamanho máximo do cache (importante para CRAN policy — limite
  padrão tipicamente 100 MB)
- Integração com o mirror remoto: fallback hierárquico (cache local →
  mirror → CVM direta)
- Como escala para múltiplas classes (fundos podem gerar volume muito
  maior que companhias)

### 6. Pipeline ETL do Mirror (GitHub Actions)

- Workflow YAML completo (não pseudocódigo — YAML pronto pra colar)
- Gatilho: `cron: '0 7 * * 2'` (terças 07:00 UTC = 04:00 BRT)
- Etapas: HEAD HTTP em todos ZIPs → comparar hash → download
  condicional → conversão Parquet → validação pointblank → upload
  Release → notificação
- Estrutura do release: nome (`snapshot-YYYY-MM-DD`), assets,
  descrição
- Rollback: se validação falhar, NÃO publicar; abrir issue automática
- Compatibilidade de versões: como saber qual release o pacote
  consome em uma versão dada
- Configuração de secrets necessários (GH_TOKEN)
- Custo estimado (free tier comporta v0.1; reavaliar v0.4+ com
  fundos)

### 7. Validation Gates com pointblank

Onde inserir pointblank:
- (a) No ETL: gates antes de publicar Release (schema, NA inesperados,
  ranges, foreign keys entre tabelas)
- (b) No pacote: validação dos dados ao baixar do mirror antes de
  retornar ao usuário
- (c) Em testes: snapshot tests comparando outputs

Para cada gate, especificar:
- Quais asserções (`col_is_character`, `rows_distinct`,
  `col_vals_in_set`, etc.)
- Threshold de tolerância (`warn_on_fail`, `stop_on_fail`)
- Comportamento em caso de falha
- Logging

### 8. Estratégia de Testes

- testthat 3.x (justificar)
- Tipos de teste: unitários, snapshot, integration (com CVM real),
  validation (pointblank)
- `skip_on_cran()` para testes que precisam de rede
- Cobertura mínima esperada (90%? 95%?)
- `covr` + Codecov
- Fixtures: tabelas pequenas em `tests/testthat/fixtures/`
- Estratégia para testar o mirror sem rodar o ETL real

### 9. CI/CD e Qualidade de Código

- GitHub Actions workflows:
  - `R-CMD-check.yaml`: matriz (R devel, release, oldrel × Ubuntu,
    macOS, Windows)
  - `test-coverage.yaml`: covr + Codecov upload
  - `lint.yaml`: lintr + styler check
  - `pkgdown.yaml`: deploy automático em gh-pages
  - `etl-mirror.yaml`: o pipeline ETL definido na Seção 6
- Pre-commit hooks (opcional)
- Convenção de versionamento: SemVer (0.1.0 → 0.2.0 → 1.0.0)
- Branching: trunk-based ou GitFlow?
- Política de PRs (mesmo sendo solo)

### 10. Documentação

- README.md (inglês): estrutura completa, badges, exemplos rápidos
- README.pt-BR.md (opcional, português): versão complementar para
  comunidade R brasileira
- NEWS.md (inglês): formato seguindo padrão CRAN
- DESCRIPTION (inglês): campos obrigatórios, palavras-chave
- Vignettes planejadas para v0.1 (em inglês como padrão CRAN; podem
  ter versão complementar em PT-BR):
  - `vignette("cvmdata")` — introdução geral
  - `vignette("itr-dfp")` — demonstrações financeiras
  - `vignette("fre")` — formulário de referência (com ênfase ESG)
  - `vignette("cache-and-mirror")` — entendendo as fontes
  - `vignette("roadmap")` — planejamento v0.2/v0.3/v0.4+
- roxygen2: padrões de documentação de funções (com exemplos rodáveis)
- pkgdown: estrutura do site, organização de reference

### 11. Roadmap de Implementação (alto nível, sem checklist)

NÃO faça checklist nesta rodada — fica para sessão dedicada após
aprovação do plano. Mas estabeleça macro-fases:

- Fase A: scaffolding (estrutura multi-classe, deps, CI/CD)
- Fase B: cadastro (`cad`) — função mais simples, prova de conceito
- Fase C: ITR — feature core
- Fase D: DFP — espelhamento do ITR
- Fase E: FRE — maior complexidade (36 tabelas)
- Fase F: integração mirror + ETL
- Fase G: testes integrados, validation, refinamento
- Fase H: documentação, vignettes
- Fase I: submissão CRAN v0.1
- Fase J+: roadmap v0.2 (FCA, VLMO, CGVN, IPE)
- Fase K+: roadmap v0.3 (eventos, estrangeiras)
- Fase L+: roadmap v0.4+ (fundos — primeira classe nova)

Para cada fase, estimar duração relativa e dependências.

### 12. Riscos, Premissas e Decisões Pendentes

- Lista de premissas técnicas (CVM mantém schema; GitHub mantém
  Releases gratuitos; CRAN aceita pacote com dependência externa de
  dados)
- Lista de riscos com mitigação (mudança de schema CVM →
  versionamento; CVM remover anos antigos → mirror; ETL falhar
  silenciosamente → monitoramento; expansão para fundos pode estourar
  free tier → reavaliar)
- Lista das decisões que ainda precisam ser tomadas:
  - Naming detalhado de funções (subsessão dedicada)
  - Idioma de nomes de colunas tidy (decidida: inglês snake_case por
    CRAN policy)
  - Licença final (sugestão MIT)
  - Outras que aparecerem durante a redação

---

## INSTRUÇÕES DE EXECUÇÃO

- Idioma do documento de planejamento: português brasileiro
- Idioma de todos os exemplos de código, nomes de função, identificadores,
  schemas, e textos que viram parte do pacote: inglês
- Tom: profissional rigoroso, sem fluff, sem pedidos de desculpas
- Código R em todos os exemplos (não pseudocódigo) — fully qualified
  namespaces (`dplyr::filter`, `readr::read_csv2`, etc.)
- Pipe operator: `|>` (não `%>%`)
- Comentários em código: inglês
- Para cada decisão arquitetural: apresentar 2-3 alternativas,
  prós/contras, e RECOMENDAR uma. Justificar a recomendação.
- Não invente; se não souber, declare "decisão pendente para
  [seção/fase]"
- Não use linguagem de marketing ("revolucionário", "fácil",
  "intuitivo")
- Não termine com "este plano é flexível e pode ser ajustado" — termine
  com pendências concretas

## ENTREGÁVEIS DESTA SESSÃO

1. Arquivo:
   `/mnt/user-data/outputs/cvmdata_rodada2_plano_arquitetural.md`
2. Resumo de 200 palavras na resposta do chat indicando:
   - Tamanho final do documento (linhas, palavras)
   - Lista das decisões importantes registradas
   - Lista das pendências que sobraram para Rodada 2.5 ou Rodada 3
3. Confirmação da próxima sessão: Rodada 2.5 = naming de funções; ou
   Rodada 3 = roadmap-checklist navegável

## AO TERMINAR

Pergunte ao usuário se ele quer:
(a) revisar o plano antes de seguir → próxima sessão revisa o markdown
(b) seguir direto para Rodada 2.5 (naming de funções)
(c) seguir direto para Rodada 3 (checklist de implementação)

---

FIM DO PROMPT — não adicione nada depois desta linha.
