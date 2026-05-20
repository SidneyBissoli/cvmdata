# Prompt — Sessão 1 do Claude Code: scaffolding inicial do `cvmdata`

## Como usar este prompt

## 1. Sobre você, Claude Code

Você está iniciando a implementação do pacote R `cvmdata`. Antes de
qualquer outra coisa, leia integralmente os seis documentos
canônicos abaixo, **nesta ordem**:

1. `cvmdata_projeto_instrucoes_customizadas-v02.md` — régua de
   idioma, tom, convenções de código. Você precisa internalizar
   isso antes de escrever uma linha.
2. `cvmdata_rodada1_fechamento.md` — escopo macro do pacote,
   versionamento (v0.1 → v1.0), fontes de dados, fora de escopo
   permanente.
3. `cvmdata_rodada2-5_naming_unificado-v03.md` — **naming canônico
   absoluto**. Quando qualquer outro documento divergir disto,
   este prevalece.
4. `cvmdata_rodada2-6_schemas.md` — estrutura dos YAMLs de schema
   por tabela; complementa o naming doc §7.
5. `cvmdata_rodada3-0_decisoes_pre_implementacao.md` — formato CSV
   para snapshots de dicionário e codelists; nome `submissao` para
   tabela de cabeçalho ITR/DFP/FRE.
6. `cvmdata_rodada3-0-2_politica_reader_sem_meta.md` — política do
   reader para 8 tabelas FRE sem META; refinamentos à hierarquia
   de classes de condição.

Em seguida, leia, com tratamento de **suporte arquitetural** (não
contrato canônico — pode divergir, neste caso prevalece o naming
v03):

7. `cvmdata_rodada2_arquitetura_estavel.md` — extrato curado do
   plano arquitetural da Rodada 2. Esse arquivo tem na cabeça uma
   tabela de mapeamento de nomes obsoletos → nomes canônicos atuais.
   Internalize essa tabela.

E examine, como exemplos vivos do schema YAML:

8. `schemas_proto/cad/companhias.yaml`
9. `schemas_proto/itr/bpa_con.yaml`
10. `schemas_proto/fre/administrador_membro_conselho_fiscal.yaml`

Esses três YAMLs são protótipos que servem de molde para os ~72
restantes. Eles foram escritos antes da Rodada 3.0.2 — quando você
gerar os demais YAMLs (na fase apropriada), aplique a nova régua
sobre `meta_status` (campo introduzido na 3.0.2; vide §4.1 do
documento).

A pasta `archive/` contém histórico de versões anteriores dos
documentos canônicos e prompts de sessões executadas. **Não leia
o conteúdo de `archive/`** a menos que você precise auditar um
trajeto editorial específico. Esses arquivos são propositalmente
arquivados e podem confundir.

## 2. Objetivos do projeto

- **Objetivo intermediário**: o pacote `cvmdata` ser aceito pela
  comunidade rOpenSci via processo formal de revisão em
  https://github.com/ropensci/software-review. A aceitação rOpenSci
  é o gate de qualidade que ancora todo o trabalho de codificação,
  testes e documentação.
- **Objetivo final**: aceitação no CRAN. A aceitação no rOpenSci
  precede e prepara a submissão CRAN; rOpenSci também submete o
  pacote ao CRAN em nome do mantenedor quando aceito, simplificando
  o processo.
- **Consequência**: um artigo no The R Journal sobre o pacote.
  Tratar como consequência da execução bem-feita das duas metas
  acima, não como meta separada.

Não desviar dessas metas. Decisões de design que não passem o
filtro "isso ajuda ou atrapalha a aceitação rOpenSci?" devem ser
rejeitadas, mesmo que pareçam interessantes.

## 3. Régua de trabalho

### 3.1 Padrão de desenvolvimento

Trabalhe em modo **tracer bullet**: implementar a função mais
simples ponta-a-ponta primeiro (`cad_fetch()` — CSV direto, sem
ZIP, sem variantes), validar o caminho completo (download → parse →
transform → tibble retornado com atributos → testes), e só então
expandir.

Não tente implementar o reader genérico (`cvm_fetch()`) antes de
ter `cad_fetch()` funcionando. Generalização vem depois de dois ou
três casos concretos exemplares.

### 3.2 Gate por commit

Cada commit deve deixar o pacote **verde no `devtools::check()`**.
Isso significa:

- `0 errors`, `0 warnings`. Notes aceitas apenas quando justificadas
  no `cran-comments.md` (ainda não existe nesta sessão; cria-se
  quando aparecer a primeira note).
- Todos os testes passando (`testthat`).
- Lint clean (`lintr::lint_package()` retorna character(0)).
- `pkgdown::build_site()` constrói sem erro (não precisa fazer todo
  commit — mas deve funcionar a qualquer momento).

Se um commit deixaria o pacote em estado vermelho, divida em
commits menores até que cada um isoladamente fique verde. Esse
gate é não-negociável.

### 3.3 Tom e comunicação com o mantenedor

Sidney é direto, técnico e rigoroso. Aplique a régua das custom
instructions:

- Tom profissional, sem fluff, sem reverência, sem puxa-saquismo.
- Quando ele perguntar problemas de algo, dizer diretamente. Se
  não houver, dizer isso explicitamente.
- Quando você identificar um problema, dizer; não esconder por
  diplomacia.
- Crítica construtiva é bem-vinda — ao código dele, à própria
  contribuição sua, e às fontes consultadas.
- Em decisões arquiteturais relevantes que não estão fechadas nos
  documentos canônicos: apresentar 2-3 alternativas com
  prós/contras, recomendar uma com justificativa, esperar
  aprovação.

### 3.4 Idioma

A régua do `cvmdata_projeto_instrucoes_customizadas-v02.md` é
absoluta. Em particular:

- Todo código R, comentário, identificador, mensagem, doc roxygen,
  README, NEWS, DESCRIPTION, workflow YAML em **inglês**.
- Nomes de tabela, nomes de coluna do tibble retornado, valores
  categóricos, texto livre **preservados em português como vêm da
  CVM** (snake_case minúsculo).
- Comunicação com Sidney em **português brasileiro**.

Em caso de dúvida sobre qualquer caso específico, consultar a
tabela §0.2 do naming doc v03.

## 4. Escopo desta sessão (Sessão 1)

Esta primeira sessão entrega **scaffolding completo do pacote +
implementação ponta-a-ponta de `cad_fetch()`**. Nada mais que
isso. O resto fica para sessões subsequentes.

### 4.1 Tarefas

**Tarefa 1 — Scaffolding (deve sair primeiro)**

1. Inicializar pacote com `usethis::create_package(".")` no
   diretório atual (`C:\Users\SIDNEY\OneDrive\programacao\R\packages\cvmdata`).
   - `Package: cvmdata`
   - `Type: Package`
   - `Version: 0.0.0.9000`
   - `Title: Tidy Access to Brazilian CVM Open Data`
   - `Description: <três a cinco frases em inglês descrevendo o
     pacote e seu escopo v0.1>`
   - `Authors@R: person("Sidney da Silva Pereira", "Bissoli",
     email = "<email a confirmar>", role = c("aut", "cre"),
     comment = c(ORCID = "<a confirmar>"))`
   - `License: MIT + file LICENSE` (criar via
     `usethis::use_mit_license("Sidney da Silva Pereira Bissoli")`).
   - `Depends: R (>= 4.1)` (para `|>` nativo).
   - `Imports:` deixar vazio nesta etapa; preencher conforme
     implementação avança.
   - `Suggests: testthat (>= 3.0.0), knitr, rmarkdown, covr, lintr,
     styler, pkgdown`.
   - `Config/testthat/edition: 3`.
   - `Encoding: UTF-8`.
   - `Roxygen: list(markdown = TRUE)`.
   - `RoxygenNote:` deixar o roxygen2 preencher.
   - `URL: https://github.com/sidneybissoli/cvmdata,
     https://sidneybissoli.github.io/cvmdata/` (ajustar usuário se
     necessário — Sidney confirma).
   - `BugReports: https://github.com/sidneybissoli/cvmdata/issues`.

   Pergunte a Sidney os campos a confirmar antes de gravar
   DESCRIPTION final.

2. Criar `.Rbuildignore` com:
   - `^.*\.Rproj$`
   - `^\.Rproj\.user$`
   - `^archive$`
   - `^schemas_proto$`
   - `^cvmdata_.*\.md$` (todos os documentos canônicos da
     planificação; não pertencem ao tarball)
   - `^cvmdata_rodada.*\.md$`
   - `^_pkgdown\.yml$`
   - `^docs$`
   - `^\.github$`
   - `^codecov\.yml$`
   - `^README\.Rmd$`
   - `^LICENSE\.md$`
   - `^cran-comments\.md$`
   - `^data-raw$`

3. Criar `.gitignore` adequado para R + Windows + RStudio.

4. Criar `NEWS.md` com header inicial:
   ```
   # cvmdata (development version)

   * Initial scaffolding.
   ```

5. Inicializar `roxygen2` via `devtools::document()`. Garante que
   `NAMESPACE` é gerado por roxygen e não editado manualmente.

6. Criar `README.Rmd` minimalista (será expandido depois). Deve
   incluir badges placeholder para R-CMD-check, codecov, CRAN
   status, lifecycle (experimental), e pkgdown. Use
   `usethis::use_lifecycle_badge("experimental")`. Gerar
   `README.md` via `devtools::build_readme()`.

7. Criar estrutura de diretórios conforme `cvmdata_rodada2_arquitetura_estavel.md`
   §2.1.3:
   - `R/api/`, `R/schemas/companies/`, `R/transform/`, `R/source/`,
     `R/dispatch/`, `R/validate/`, `R/utils/`.
   - `tests/testthat/` e `tests/testthat.R` via
     `usethis::use_testthat(3)`.
   - `inst/extdata/`.
   - `data-raw/`.

8. Criar `CLAUDE.md` na raiz do projeto consolidando o essencial
   dos seis documentos canônicos para que sessões futuras do
   Claude Code não precisem reler tudo. Tamanho alvo: 3-5 mil
   palavras. Estrutura mínima:
   - Régua de idioma (extraída do custom instructions v02).
   - Naming canônico crítico (de naming v03 §0-§3, §6-§7).
   - Convenções de código (tidyverse + `|>`, fully-qualified
     namespaces, lint).
   - Estrutura de diretórios (de arquitetura estável §2.1.3).
   - Sistema de classes S3 (de arquitetura estável §2.2).
   - Hierarquia de classes de condição (de naming v03 §6.1 com o
     refinamento da 3.0.2).
   - Schema dos YAMLs por tabela (de naming v03 §7.2 + 3.0.2 §4.1).
   - Política do reader em três modos `validate` (de 3.0.2 §3.3
     modificação 1).
   - Estratégia de cache (resumo de arquitetura estável §5).
   - Política de testes (resumo de arquitetura estável §8).

   O `CLAUDE.md` é seu material de contexto persistente. Cada
   sessão futura você lê o `CLAUDE.md` primeiro e os documentos
   canônicos só quando precisar de detalhe.

9. Criar `ROADMAP.md` enxuto na raiz (3-4 páginas) consolidando o
   §11 da arquitetura estável, com checkboxes ASCII por fase.
   Este será o documento que rastreia progresso da implementação
   sessão a sessão.

10. Criar workflow `.github/workflows/R-CMD-check.yaml` via
    `usethis::use_github_action("check-standard")`, ajustando
    a matriz para a configuração documentada em
    `cvmdata_rodada2_arquitetura_estavel.md` §9.2.

11. Commit inicial: `chore: initial scaffolding`. Pacote deve estar
    verde em `devtools::check()` nesse ponto.

**Tarefa 2 — `cad_fetch()` ponta-a-ponta**

Implementar a função alias mais simples do pacote como prova de
conceito da arquitetura. Razões para começar por aqui:

- CAD é CSV direto sem ZIP (topologia mais simples).
- Sem partição temporal — um arquivo único snapshotado.
- Sem transformações declaradas (vide `schemas_proto/cad/companhias.yaml`).
- META disponível (sem caso `meta_status: missing` para preocupar).

Componentes a implementar:

1. **YAML schema** em `inst/extdata/schemas/cad/companhias.yaml`,
   copiado de `schemas_proto/cad/companhias.yaml` (já validado
   empiricamente; sem alterações).

2. **Parser do YAML** em `R/schemas/load.R`:
   - `load_schema(dataset, table)` retorna objeto interno
     `cvm_table_schema` (lista nomeada com slots `dataset`,
     `table`, `cvm_archive_url_pattern`, `cvm_file_url_pattern`,
     `cvm_file_pattern`, `cvm_dictionary_url`, `encoding`,
     `delimiter`, `temporal_partitioning`, `first_year`,
     `expected_field_count`, `expected_field_names`,
     `meta_status`, `transformations`).
   - Validação: exatamente um de
     `cvm_archive_url_pattern`/`cvm_file_url_pattern` deve ser
     não-nulo. Quando `meta_status = missing`,
     `expected_field_names` deve estar presente. Erro via
     `cli::cli_abort()` com classe `cvmdata_error_internal`.

3. **HTTP source** em `R/source/source_cvm_http.R`:
   - `source_cvm_http_get(schema, ...)` — recebe schema, retorna
     caminho local do CSV baixado.
   - Para `temporal_partitioning: none` (caso CAD): baixa o CSV
     direto da URL.
   - Para `temporal_partitioning: yearly`: receberá `year` no
     argumento (ainda não implementado nesta sessão; pode lançar
     `cvmdata_error_internal` com mensagem "not implemented yet"
     se chamado para CAD não é o caso).
   - Cache em `tools::R_user_dir("cvmdata", which = "cache")`,
     subdir `raw/<dataset>/`.
   - Verificação ETag via HEAD HTTP antes de servir cache; se
     diferente, redownload.
   - Erros de rede: `cvmdata_error_http`.

4. **Reader / parser** em `R/utils/csv_cvm.R`:
   - `read_cvm_csv(path, schema)` — lê CSV com encoding
     `schema$encoding` e delimitador `schema$delimiter` via
     `readr::read_delim()`.
   - Aplica regra de identificadores: campos no domínio
     `c("cnpj_cia", "cd_cvm", "cep", "tel", "ddd_*", "cpf")`
     **forçados a character** mesmo quando o META declara numeric
     (vide naming doc §11.2, refinamento Rodada 2.6).
   - Conversão automática de datas: campos cujo `tipo_dados` no
     META é `"date"` viram `Date` automaticamente.
   - Valida `expected_field_count` contra ncol do CSV; divergência
     com `validate = "strict"` aborta com
     `cvmdata_error_parse`.

5. **Transform** em `R/transform/transform_cad.R`:
   - `transform_cad(df, schema)` — normalização de nomes para
     snake_case (`tolower()` no v0.1, já que CAD usa
     SCREAMING_SNAKE_CASE). Sem outras transformações declaradas
     no YAML.

6. **API** em `R/api/fetch_companies.R`:
   - `cad_fetch(companies = NULL, source = "auto", on_error =
     "abort", validate = "strict", ...)` — assinatura conforme
     naming doc §2.
   - Internamente chama `cvm_fetch_internal(dataset = "cad",
     table = "companhias", ...)`.
   - `cvm_fetch_internal()` é a função genérica não-exportada que
     orquestra: `load_schema()` → `source_cvm_http_get()` →
     `read_cvm_csv()` → `transform_cad()` → atribui atributos →
     retorna tibble com classe `cvm_tbl`.

7. **Atributos** em `R/utils/attrs.R`:
   - `cvm_attach_metadata(df, source, dataset, table)` — adiciona
     atributos `source`, `fetched_at`, `dataset`, `table`,
     `package_version` ao tibble retornado.
   - Classe `cvm_tbl` herdando de `tbl_df`, `tbl`, `data.frame`.

8. **Print method** em `R/utils/print_cvm_tbl.R`:
   - `print.cvm_tbl(x, ...)` — exibe linha extra com `source` e
     `fetched_at` antes do tibble normal. Vide arquitetura
     estável §2.2.

9. **Classes de condição** em `R/utils/errors.R`:
   - `cvmdata_abort(message, class = NULL, ...)` — wrapper de
     `cli::cli_abort()` que sempre adiciona `"cvmdata_error"` ao
     final do vetor de classes.
   - Análogo `cvmdata_warn()` para warnings.
   - Hierarquia conforme naming doc §6.1 atualizada pela 3.0.2:
     - `cvmdata_error_input`, `cvmdata_error_http`,
       `cvmdata_error_parse`, `cvmdata_error_meta_unavailable`,
       `cvmdata_error_internal`.
     - `cvmdata_warn_validation`, `cvmdata_warn_meta_unavailable`.

10. **Testes** em `tests/testthat/`:
    - `test-load-schema.R` — load_schema lê YAML corretamente;
      valida invariante de URLs; valida regra `meta_status:
      missing`.
    - `test-cad-fetch.R` — pelo menos 3-4 testes mockados via
      `httptest2`:
      - Retorna tibble com classe `cvm_tbl`.
      - Tem todas as colunas esperadas (subconjunto verificável
        via `expected_field_names` derivado do snapshot).
      - Tem atributos de proveniência.
      - `cnpj_cia` é character com pontuação.
      - `cd_cvm` é character.
    - **Não rodar testes contra CVM real** nesta sessão. Usar
      apenas mocks. Fixture do CAD em
      `tests/testthat/fixtures/cad_sample.csv` (50 linhas reais).

11. **Doc roxygen** completa para `cad_fetch()` conforme arquitetura
    estável §10.3 e o exemplo de `fetch_itr()` lá (adaptando para
    CAD).

12. **Vignette stub** `vignettes/cvmdata.Rmd` mínima: 1 parágrafo
    introdutório + 1 chunk usando `cad_fetch()` em modo
    `\dontrun{}` ou condicional a `interactive()`. Vignette
    completa fica para sessão futura.

13. **Atualizar `NEWS.md`** com bullet sob `# cvmdata
    (development version)`:
    - `* First implementation: `cad_fetch()` for the CAD registry.`

14. **Commit final**: `feat(cad): implement cad_fetch() end-to-end`.
    Pacote deve estar verde em `devtools::check()`.

### 4.2 O que esta sessão NÃO faz

- Não implementa `cvm_fetch()` genérico (vem em sessão futura,
  quando houver pelo menos 2 aliases para abstrair).
- Não implementa `itr_fetch()`, `dfp_fetch()`, `fre_fetch()`.
- Não implementa funções de descoberta (`cvm_datasets()`,
  `cvm_tables()`, `cvm_dictionary()`).
- Não implementa snapshot de dicionário ou de codelists.
- Não implementa workflow ETL do mirror.
- Não escreve as outras vignettes (`itr-dfp.Rmd`, `fre.Rmd`,
  `cache-and-mirror.Rmd`, `roadmap.Rmd`).
- Não gera os ~72 YAMLs restantes.
- Não cria o repositório GitHub (Sidney faz isso depois — apenas
  o diretório local).

Essas tarefas vão para sessões posteriores. Resista à tentação de
implementar mais por antecipação. Tracer bullet.

## 5. Restrições

- **Não reabrir decisões travadas**. As 26 decisões da Rodada 2.5,
  os 7 refinamentos da Rodada 2.6, as 3 decisões da Rodada 3.0 e
  os 4 da Rodada 3.0.2 estão travadas. Se você acha que uma
  decisão precisa ser revista, **pergunte ao Sidney** antes de
  agir, não unilateralmente.
- **Não inventar URLs, nomes de arquivos CVM, ou conteúdo de
  schemas**. Use os YAMLs já entregues em `schemas_proto/` ou,
  para schemas novos, pergunte antes de gerar.
- **Não usar `%>%`** — apenas `|>` (base R).
- **Não usar `paste()`/`paste0()`** quando `stringr::str_c()` for
  apropriado.
- **Fully-qualified namespaces** em todo código (`dplyr::filter()`,
  `readr::read_delim()`, etc.). Exceção: pipelines longos podem
  usar `@importFrom` no roxygen e bare names após primeira
  qualificação.
- **Não criar mais arquivos do que o necessário**. Resistir a
  proliferação de stubs vazios.

## 6. Método de trabalho

1. Leia os documentos canônicos (Seção 1 deste prompt).
2. Internalize a régua de idioma e o naming canônico.
3. Confirme com Sidney os campos do `DESCRIPTION` que precisam de
   input dele (email, ORCID, URL GitHub exata).
4. Execute Tarefa 1 (scaffolding). Antes do commit, rode
   `devtools::check()` e mostre o output para Sidney. Aprovação
   antes do commit.
5. Execute Tarefa 2 (`cad_fetch()`). Idem: `devtools::check()` +
   `testthat::test_local()` + lint clean antes do commit final.
6. Não inicie a próxima sessão sem confirmação explícita de
   Sidney que esta foi aceita.

## 7. Ao terminar

Reportar a Sidney em português:

- Resumo do que foi feito (1-2 parágrafos).
- Output de `devtools::check()` (linha "Status").
- Output de `covr::package_coverage()` (cobertura percentual).
- Lista das decisões pendentes que apareceram durante a
  implementação (se houver).
- Próximos passos sugeridos para a Sessão 2 (alta probabilidade:
  `itr_fetch()` + sua versão do ZIP-based pipeline + `cvm_fetch()`
  genérico).

Pergunta acionável final: "Pode prosseguir para Sessão 2?"

