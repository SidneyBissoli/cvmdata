# Pacote `cvmdata` — Fechamento da Rodada 1

Documento de referência consolidando todas as decisões da fase de
viabilidade e escopo, para uso na Rodada 2 (plano arquitetural completo).

---

## Identidade do pacote

- **Nome**: `cvmdata`
- **Verificação**: nome disponível no CRAN (HTTP 404 em
  `cran.r-project.org/web/packages/cvmdata/index.html` em 16/05/2026);
  zero conflito significativo em buscas GitHub.
- **Mantenedor**: Sidney da Silva Pereira Bissoli (mantenedor de `educabR` 
  no CRAN)
- **Linguagem do código**: R; comentários e identificadores em inglês
  (padrão CRAN)
- **Idioma de documentação primária**: inglês (CRAN policy)
- **Idioma de documentação complementar**: português brasileiro
  (vignette e README adicionais opcionais)
- **Licença**: a definir (sugestão: MIT, paralelo a `educabR`)

## Visão de longo prazo (escopo total)

O pacote `cvmdata` é uma API tidy para o **universo completo de dados
abertos publicados pela CVM** (Comissão de Valores Mobiliários), em
todas as classes de entidades reguladas.

Classes de entidades cobertas pela CVM no Portal de Dados Abertos
(verificado via inventário CKAN em 16/05/2026 e site oficial CVM):

- **Companhias Abertas** (`cia_aberta-*`) — 9 datasets
- **Fundos de Investimento ICVM 555** — informes diários, cadastrais,
  composição de carteira (CDA), extratos, etc.
- **Fundos de Investimento Imobiliário (FII)** — informes mensais,
  trimestrais, anuais, FII-doc-cda
- **Fundos de Investimento em Direitos Creditórios (FIDC)** —
  demonstrações financeiras, informe mensal
- **Fundos Estruturados** — balancete, demonstrações
- **Companhias Estrangeiras** e **Companhias Incentivadas** —
  informações cadastrais
- **Securitizadoras** (via Fundos.NET) — quando dados estruturados
  estiverem disponíveis
- **Emissores ICVM 555** — características, ativos em carteira

Esta visão de longo prazo determina o **nome do pacote** (`cvmdata`,
genérico) e a **arquitetura interna** (preparada para múltiplas classes
de dataset desde o início).

## Escopo por versão

O pacote será expandido por versões. A v0.1 cobre apenas **companhias
abertas** como prova de conceito e validação arquitetural; versões
subsequentes incorporam outras classes de entidades.

### v0.1 — Companhias Abertas, parte 1 (release inicial CRAN)

Datasets cobertos:
- `cad` — Informação Cadastral mestre (chave de junção)
- `itr` — Formulário de Informações Trimestrais (2011+)
- `dfp` — Formulário de Demonstrações Financeiras Padronizadas (2010+)
- `fre` — Formulário de Referência completo, incluindo as 36 tabelas
  internas, com destaque para o módulo ESG/governança (gênero/raça/PCD,
  remuneração, posição acionária)

### v0.2 — Companhias Abertas, parte 2

- `fca` — Formulário Cadastral histórico (complemento ao `cad`)
- `vlmo` — Valores Mobiliários Negociados e Detidos (insider trading)
- `cgvn` — Informe do Código de Governança (ICBGC)
- `ipe` — Informes Periódicos e Eventuais (manifesto apenas; sem OCR
  de PDFs)

### v0.3 — Companhias Abertas, parte 3 + Estrangeiras/Incentivadas

- `eventos_societarios` — Programa de Recompra de Ações e outros
  eventos especiais
- `cia_estrang-cad`, `cia_incent-cad` — cadastros de estrangeiras e
  incentivadas

### v0.4+ — Fundos de Investimento

A expansão para fundos exige decisões arquiteturais adicionais (escala
maior, datasets diários, granularidade diferente). Em rodada futura
quando v0.3 estiver estável.

Categorias previstas:
- Fundos ICVM 555 (cadastrais, informes diários, CDA)
- FII (Fundos de Investimento Imobiliário)
- FIDC (Fundos de Investimento em Direitos Creditórios)
- Fundos Estruturados

### Fora de escopo permanente

- OCR de PDFs IPE
- Scraping direto do RAD (`rad.cvm.gov.br`)
- Endpoints B3 (`sistemaswebb3-listados`)
- Acesso autenticado via Download Múltiplo CVM
- Dados de cotações (já cobertos por `rb3`)
- Dados não publicados oficialmente pela CVM (sites agregadores
  comerciais como Fundamentus, Status Invest, Investidor10)

## Posicionamento

API tidy para o universo de dados abertos publicados pela CVM, com
cobertura crescente de classes de entidades reguladas. Diferenciação
face ao ecossistema R atual:

- `GetDFPData2` (Perlin): cobre DFP de companhias abertas, função ITR
  não exportada, sem FRE/FCA/VLMO/CGVN/IPE, sem fundos
- `rb3`: cotações e curvas, sem dados regulatórios
- Pacotes específicos de fundos: fragmentados, sem padronização
- `microdatasus`: precedente metodológico (servidor próprio como
  mirror), domínio diferente

Nicho identificado a curto prazo: **dados ESG/governança estruturados**
da CVM (diversidade, gênero/raça/PCD em administradores e empregados,
remuneração, posição acionária) tabularmente acessíveis — ainda não
cobertos por ferramenta R alguma.

Posicionamento de longo prazo: ser **o** pacote R canônico para dados
regulatórios da CVM, em qualquer classe de entidade.

## Arquitetura de fontes

### Fonte primária

Portal de Dados Abertos da CVM (`dados.cvm.gov.br`).

- Acesso via HTTP direto aos ZIPs/CSVs em
  `dados.cvm.gov.br/dados/<TIPO>/`
- API CKAN para metadados:
  `dados.cvm.gov.br/api/3/action/package_show?id=<DATASET_ID>`
- Periodicidade declarada: semanal (companhias) / diária (alguns
  datasets de fundos)
- Política declarada: "últimos cinco anos" + "histórico (não sujeito à
  política de atualização)"
- Cobertura empírica para companhias abertas em 16/05/2026: ITR
  2011–2026 (16 anos), DFP 2010–2026 (17 anos)

### Fonte secundária (fallback automático)

Mirror próprio em GitHub Releases do repositório `cvmdata`.

- Formato de armazenamento: Parquet particionado por classe/dataset/ano
- Engine de query: DuckDB com leitura HTTP range requests
- Acionamento: fallback automático quando CVM retorna 404 (ano removido
  da política CVM)
- Transparência: cada chamada da API retorna atributo
  `attr(x, "source") = "cvm"` ou `"mirror"`

### ETL do mirror

- Trigger: GitHub Actions, cron `0 7 * * 2` (terças, 07:00 UTC = 04:00
  Brasília/DF)
- Lógica: HEAD HTTP em cada ZIP CVM; comparar `Last-Modified` ou
  `Content-Length` com snapshot anterior; rebuild apenas se mudou
- Output: Release `snapshot-YYYY-MM-DD` com Parquet de todos os datasets
  cobertos pela versão atual do pacote
- Validação pré-publicação: pointblank gates antes do upload
- Custo: dentro do free tier (~20 runs/mês × ~5 min na escala de v0.1)
- Escalabilidade para v0.4+ (fundos): reavaliar quando incluir fundos
  diários, que podem exigir frequência maior de ETL ou estratégia
  diferente

## API pública

### Padrão arquitetural escolhido: Padrão C (híbrido)

Função genérica como espinha dorsal:

```r
fetch_cvm(dataset, table = NULL, entities = NULL, years = NULL, ...)
```

Aliases tipados para datasets mais usados (a serem definidos em rodada
dedicada de naming):

```r
# Companhias abertas (v0.1)
fetch_itr(table, companies, years, ...)
fetch_dfp(table, companies, years, ...)
fetch_fre(table, companies, years, ...)
fetch_cad(companies, ...)

# Fundos (v0.4+, ilustrativo)
fetch_fii(table, funds, dates, ...)
fetch_fidc(table, funds, dates, ...)
```

Decisão pendente: detalhes finos de nomes, argumentos, defaults,
dispatch interno — a tratar em subsessão dedicada da Rodada 2 ou
Rodada 2.5.

A arquitetura interna deve ser **multi-classe desde o início**, mesmo
que v0.1 implemente apenas uma classe (companhias abertas). Isso evita
retrabalho no salto para v0.4+.

## Pendências para Rodada 2

1. Arquitetura interna completa: estrutura de diretórios, namespace,
   dependências, sistema de classes (S3 vs S4 vs R6) — pensar
   multi-classe desde o início
2. Design fino da API pública (operacionalizar Padrão C com extensão
   para múltiplas classes de entidades)
3. Schemas tidy de saída para todos os ~85 CSVs CVM da v0.1 (cad, itr,
   dfp, fre)
4. Estratégia de cache local (DuckDB embarcado, cachem, memoise?)
5. Pipeline ETL detalhado (workflow YAML, validação, hash, rollback)
6. Validation gates com pointblank (onde, quando, quais asserções)
7. Estratégia de testes (testthat, snapshot tests, integration tests)
8. CI/CD (R CMD check, lint, cobertura, pkgdown)
9. Documentação (roxygen2, vignettes, README, NEWS)
10. Roadmap-checklist navegável (em sessão dedicada após aprovação do
    plano)

## Formato da Rodada 2

- Entrega: arquivo markdown completo em `/mnt/user-data/outputs/`
- Tamanho esperado: 15–30 mil palavras
- Pós-entrega: revisão do usuário e abertura de questões em sessões
  subsequentes
- Roadmap-checklist em formato navegável: gerado em sessão dedicada
  após aprovação do plano

## Referências documentais usadas

- Resolução CVM nº 80/22 (regula entrega ITR/DFP/FRE)
- Ofício Circular Anual SEP/CVM 2025
- Portaria CVM/PTE/Nº 51 de 23/05/2024 (Plano de Dados Abertos)
- Manual Sistema de Envio de Informações Periódicas e Eventuais (CVM)
- Página oficial dataset ITR:
  `dados.cvm.gov.br/dataset/cia_aberta-doc-itr`
- Página oficial dataset DFP:
  `dados.cvm.gov.br/dataset/cia_aberta-doc-dfp`
- Termos de Uso CVMWEB (versão 10/08/2022)
- Inventário CKAN:
  `dados.cvm.gov.br/api/3/action/package_search?q=cia_aberta`
  (companhias)
- Página principal: `dados.cvm.gov.br/` (com links para fundos, FIIs,
  FIDCs, etc.)
