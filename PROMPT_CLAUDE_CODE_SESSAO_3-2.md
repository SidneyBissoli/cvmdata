# Prompt — Sessão 3.2 do Claude Code: schemas e tracer FRE

## Como usar este prompt

Este prompt é o ponto de entrada de **uma janela de contexto limpa**.
Você não precisa do histórico das sessões anteriores: tudo o que é
necessário está em `CLAUDE.md`, `ROADMAP.md`, no estado atual do código
e nos YAMLs DFP/ITR que servem de molde.

## 1. Leitura obrigatória (nesta ordem)

1.  `CLAUDE.md` — contexto persistente do projeto. Régua de idioma,
    naming (incluindo §2.2 que descreve **explicitamente como FRE-detail
    usa convenção diferente**: `cnpj_companhia`, `data_referencia`,
    `nome_companhia`, `versao`, `id_documento`, **sem `cd_cvm`**),
    schema YAML, política do reader com `meta_status: missing`,
    hierarquia de condições, estrutura de diretórios. Atenção também à
    §2.7 que foi atualizada com a política
    `resolve_cd_cvm_via_submissao`.
2.  `ROADMAP.md` — estado por fase. A Sessão 03 (ITR) está marcada como
    `[~]` parcial; FRE é o item pendente que fecha a Fase D.
3.  `inst/extdata/schemas/dfp/` e `inst/extdata/schemas/itr/` (11+11
    YAMLs) — moldes para os YAMLs FRE com META disponível. Em particular
    leia `submissao.yaml` (vai ter equivalente FRE) e `bpa.yaml` (para
    ver o padrão de `transformations:`).
4.  `R/api-cvm-fetch.R`, `R/schema-load.R`, `R/source-cvm-http.R`,
    `R/util-csv-cvm.R` — pipeline genérico, parser de YAML, downloader,
    e reader. **Você provavelmente vai precisar tocar em alguns deles**
    nesta sessão (vide §3 abaixo). Leia tudo, especialmente
    `filter_by_companies` + `match_by_cnpj` +
    `resolve_cd_cvm_via_submissao` em `R/api-cvm-fetch.R`.
5.  `tests/testthat/test-cvm-fetch.R` — testes do DFP (Sessão 02), ITR
    (Sessão 03), e do hotfix de resolução CD_CVM via submissao. São
    referência para o estilo dos testes FRE que você vai adicionar.

Não leia `cvmdata_*.md` (documentos canônicos das rodadas) a menos que
precise auditar algum detalhe específico que o CLAUDE.md não cobre.

## 2. Estado pós-Sessão 03 (contexto, não-acionável)

- **Sessão 03**: ITR ponta-a-ponta. 11 YAMLs em
  `inst/extdata/schemas/itr/`, fixture
  `tests/testthat/fixtures/itr_cia_aberta_2024.zip` (6.94 KB), tracer +
  discovery em `test-cvm-fetch.R`. ITR é simétrico a DFP (mesmo schema,
  só muda URL/year). Commits `afb23de` + `b9eeafb`.
- **Hotfix pós-Sessão 03 (commit `6d75baf`)**: tabelas sem `cd_cvm`
  nativo (`composicao_capital`, `parecer` em ITR/DFP) retornavam tibble
  vazio silenciosamente quando o usuário passava CD_CVM. Implementado
  `resolve_cd_cvm_via_submissao()` em `R/api-cvm-fetch.R`: lê
  `<dataset>/submissao` do mesmo year, faz lookup CD_CVM → CNPJ, filtra
  por CNPJ. CD_CVMs ausentes na submissao daquele ano abortam com
  `cvmdata_error_input`. Política simétrica: CD_CVM funciona em qualquer
  tabela do dataset. CLAUDE.md §2.7 atualizado.
- **Hotfix pós-Sessão 03 (commit `3e689f8`)**: busca textual com zero
  matches retornava tibble vazio silenciosamente; agora aborta com
  `cvmdata_error_input` no primeiro termo sem match.
- **Gate atual**: `devtools::check()` 0E/0W/0N; `devtools::test()` 85/85
  passing;
  [`lintr::lint_package()`](https://lintr.r-lib.org/reference/lint.html)
  clean; cobertura **86.66%**.

## 3. Escopo desta sessão

**Entregar FRE ponta-a-ponta.** 36 YAMLs (1 header `submissao` + 35
detail tables), incluindo 8 detail tables com `meta_status: missing` que
pela primeira vez exercitam de verdade a política do reader da Rodada
3.0.2. Fixture + tracer + testes de discovery + testes dos três modos de
`validate:` (`strict` / `warn` / `skip`) contra um YAML real com
`meta_status: missing`.

FRE é o **primeiro dataset que NÃO é estruturalmente igual aos
anteriores**. Diferenças que você vai encontrar (e algumas precisarão de
ajuste no pipeline em R/):

### 3.1 Naming inconsistente entre header e detail

Pela §2.2 do CLAUDE.md:

- `fre/submissao` usa convenção CAD/ITR/DFP: `cnpj_cia`, `dt_refer`,
  `versao`, `denom_cia`, `cd_cvm`, …
- `fre/<detail>` usa: `cnpj_companhia`, `data_referencia`,
  `nome_companhia`, `versao`, `id_documento`. **Sem `cd_cvm`** em
  nenhuma detail table.

Implicações para o pipeline:

- **`match_by_cnpj()`** em `R/api-cvm-fetch.R` hoje só olha `cnpj_cia`.
  Para FRE-detail vai precisar olhar `cnpj_companhia` também. **Você vai
  precisar tocar em R/.**
- **Resolução CD_CVM → CNPJ via submissao** já assume `submissao` tem
  `cd_cvm` e `cnpj_cia`. Confirme empiricamente que FRE/submissao tem
  esses dois campos. O lookup devolve `cnpj_cia`, que precisa casar com
  `cnpj_companhia` na detail. Pode ser que sirva sem mudança (o CNPJ é o
  mesmo número, só o nome da coluna muda). Mas confirme.
- **`classify_company_tokens()`** continua igual.
- **Regra de identificadores → character** (CLAUDE.md §2.4) já lista
  `cnpj_companhia`. Não toque, mas confirme que o reader força para
  character.

### 3.2 Política do reader com `meta_status: missing`

Pela CLAUDE.md §8, 8 tabelas FRE têm `meta_status: missing`:

- `administrador_PCD`
- `empregado_PCD`
- `empregado_local_declaracao_genero`
- `empregado_local_declaracao_raca`
- `empregado_posicao_declaracao_genero`
- `empregado_posicao_declaracao_raca`
- `empregado_posicao_faixa_etaria`
- `empregado_posicao_local`

YAMLs dessas 8 devem:

- `meta_status: missing`
- `cvm_dictionary_url: null`
- **Obrigatório**: `expected_field_names: [...]` com o cabeçalho real do
  CSV (validar empiricamente).

O reader (`R/util-csv-cvm.R`) já tem o esqueleto para os três modos
(`validate ∈ c("strict", "warn", "skip")`). Mas a Sessão 02 documentou:
“modo `strict` em `meta_status: missing` ainda não exercitado por nenhum
YAML real”. Esta sessão é onde isso muda.

Espere bugs no reader quando você exercitar pela primeira vez — política
nova encontrando dados reais costuma revelar canto-cases.

### 3.3 Heterogeneidade entre 35 detail tables

Diferente de DFP/ITR (que têm 11 tabelas todas com schema parecido), FRE
tem 35 detail tables com layouts MUITO diferentes uns dos outros:
declarações em prosa, tabelas de cargos, listas de remuneração,
demografia de empregados, etc. Cada uma tem seu próprio
`expected_field_count` e seu próprio set de transformações (ou nenhuma).

**Não copie cegamente o template de DFP.** Audite cada CSV
individualmente. Algumas detail tables podem ter:

- Sem `vl_conta` / `escala_moeda` (não financeiras) → nenhuma
  `multiply_by_scale`.
- Com colunas de data não-óbvias → confirme `tipo_dados = "date"` no
  META quando disponível.
- Encoding ou delimiter eventualmente diferentes (improvável, mas
  audite).

## 4. Tarefas em ordem

### Tarefa 1 — Auditoria empírica do portal FRE

Análoga à Sessão 03 mas com escopo maior (36 CSVs em vez de 19).

1.  Baixe o ZIP anual de 2024:
    `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/FRE/DADOS/fre_cia_aberta_2024.zip`
    (URL provável; **confirme**).
2.  Liste o conteúdo. Confirme padrão de naming dos CSVs.
3.  Para cada CSV: leia o header, conte os campos, anote os nomes.
4.  Baixe o META:
    `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/FRE/META/meta_fre_cia_aberta_txt.zip`
    (URL provável; **confirme**). Liste o conteúdo — quais 8 tabelas
    detail **não** têm META.
5.  Confirme empiricamente `first_year` do FRE (FRE foi instituído pela
    Instrução CVM 480/2009 — primeiros documentos entregues em 2010 ou
    2011). Use HEAD probing decrescente.

Reporte ao Sidney em **tabela markdown com 36 linhas**: nome da tabela
conceitual, nome do CSV, `expected_field_count`, `meta_status`
(`available` ou `missing`). Espere validação antes de prosseguir.

### Tarefa 2 — Gerar os 36 YAMLs FRE

Em `inst/extdata/schemas/fre/<tabela>.yaml`:

- 1 YAML para `submissao` (estrutura paralela a DFP/ITR).
- 27 YAMLs para detail tables com `meta_status: available`.
- 8 YAMLs para detail tables com `meta_status: missing` (preencher
  `expected_field_names` com o header real do CSV).

Substituições mecânicas (comparado a um YAML DFP/ITR de molde):

- `dataset: dfp|itr` → `dataset: fre`
- URLs `/DOC/DFP/` → `/DOC/FRE/`, `dfp_cia_aberta_` → `fre_cia_aberta_`
- `first_year`: o valor empírico da Tarefa 1
- `expected_field_count`: o valor empírico por tabela
- `transformations`: avaliar caso a caso. **NÃO** assuma
  `multiply_by_scale`/`drop escala_moeda` — só aplica em tabelas com
  `VL_CONTA` + `ESCALA_MOEDA`. Maioria das FRE detail provavelmente não
  tem.
- `keep_latest_version`: aplicar em quase todas (manter a versão mais
  recente por `(cnpj_companhia, data_referencia)`). **Confirme** se a
  chave de agrupamento de `keep_latest_version` precisa de ajuste no R/
  (hoje `tx_keep_latest_version` agrupa por `cnpj_cia + dt_refer`). Se
  sim, **pare e proponha** antes de mexer.

### Tarefa 3 — Eventuais ajustes em R/ para suportar FRE

Se a Tarefa 2 revelar que o pipeline em R/ precisa entender naming
FRE-detail (`cnpj_companhia` em vez de `cnpj_cia`, `data_referencia` em
vez de `dt_refer`), faça o mínimo necessário:

- `match_by_cnpj()` em `R/api-cvm-fetch.R`: testar tanto `cnpj_cia`
  quanto `cnpj_companhia`.
- `tx_keep_latest_version()` em `R/transform-schema.R`: aceitar
  agrupamento por `(cnpj_companhia, data_referencia)` quando essas
  colunas estiverem presentes em vez do par cnpj_cia/dt_refer.
- `resolve_cd_cvm_via_submissao()` em `R/api-cvm-fetch.R`: confirme se o
  CNPJ devolvido da submissao (`cnpj_cia`) é o mesmo formato do CNPJ da
  detail (`cnpj_companhia`). Se sim, nada a fazer. Se não, ajustar a
  comparação.

**Princípio**: ajuste com cirurgia. Não generalize prematuramente. Se
algum ponto exige mudança estrutural maior do que duas linhas, **pare e
proponha 2-3 alternativas** com pró/contra ao Sidney.

### Tarefa 4 — Fixture FRE 2024

Crie `tests/testthat/fixtures/fre_cia_aberta_2024.zip`. Critérios:

- 2-3 companhias (incluir BCO BRASIL `001023` / CNPJ
  `00.000.000/0001-91` para reuso de helpers DFP/ITR).
- Subset mínimo de CSVs que cubra: `submissao`, 1 detail com META
  disponível, 1 detail com `meta_status: missing`. (3 CSVs no mínimo;
  mais se necessário para os testes da Tarefa 5.)
- Tamanho total \<100 KB.
- Construa programaticamente via script efêmero. **Não commite o
  script**, só o ZIP final + `.meta.json` (padrão do fixture ITR).

### Tarefa 5 — Testes FRE

Em `tests/testthat/test-cvm-fetch.R`, adicione (não substitua):

- Helper `local_prepare_fre_cache()` análogo a
  `local_prepare_itr_cache`.
- Tracer test:
  `cvm_fetch("fre", "<detail_com_meta>", companies = "BCO BRASIL", years = 2024L, source = "cvm")`
  — espera `cvm_tbl`, atributos corretos, `cnpj_companhia` como
  character.
- Discovery:
  [`cvm_datasets()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_datasets.md)
  agora inclui `"fre"`; `cvm_tables("fre")` retorna as 36 tabelas
  esperadas.
- Teste do branch `meta_status: missing` em modo `strict`: deve
  funcionar quando o CSV bate `expected_field_names`; deve abortar com
  `cvmdata_error_parse` quando não bate.
- Teste do mesmo branch em modo `warn`: emite `cvmdata_warn_validation`
  e entrega o tibble.
- Teste do modo `skip`: silencioso.
- Se você mexeu em `match_by_cnpj` (Tarefa 3): teste que CNPJ filtra
  corretamente uma detail FRE que usa `cnpj_companhia`.
- Se você mexeu em `tx_keep_latest_version` (Tarefa 3): teste que versão
  é mantida corretamente quando a chave de agrupamento é
  `(cnpj_companhia, data_referencia)`.

### Tarefa 6 — Documentação

- `NEWS.md`: bullet sob `# cvmdata 0.0.0.9000` —
  `* Add FRE (annual reference form) coverage: 36 schemas including 8 with meta_status: missing.`
  - outro bullet listando qualquer mudança em R/ que tenha precisado.
- `ROADMAP.md`: marca itens FRE como `[x]` na Sessão 03; se houver
  ajustes em R/, registre sub-itens explicando o que mudou e porquê.
- `CLAUDE.md`: se algum ajuste estrutural alterou a régua atual,
  atualize a seção correspondente (§2.2 ou §2.7). Caso contrário, não
  toque.

### Tarefa 7 — Commit

Antes de cada commit, rode:

    Rscript -e "lintr::lint_package()"      # deve retornar character(0)
    Rscript -e "devtools::test()"            # tudo verde
    Rscript -e "devtools::check()"           # 0 errors, 0 warnings,
                                             # 0 notes (exceto "time" cosmética)

Sequência sugerida:

1.  Commit dos 36 YAMLs + fixture:
    `feat(fre): add 36 schemas + fixture`.
2.  Se houve ajustes em R/:
    `fix(api): support FRE-detail naming (cnpj_companhia/data_referencia)`
    (ou similar).
3.  Commit dos testes + docs:
    `test(fre): add tracer + meta_status: missing branch tests`.

(Sidney aceita commits agrupados se preferir, desde que cada commit
deixe o pacote verde no gate.)

## 5. O que esta sessão NÃO faz

- **Não implemente snapshot de dicionário**
  (`cvm_dictionary_snapshot.csv`). Item separado da Fase C.
- **Não substitua a heurística de Date** em `read_cvm_csv()` pela regra
  canônica baseada no snapshot. Dependente do snapshot acima.
- **Não implemente
  [`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md)**,
  `cvm_cache_*()` público, ou qualquer item da Fase E não-FRE.
- **Não implemente mirror parquet** (Fase F).
- **Não reabra decisões travadas** no CLAUDE.md ou no ROADMAP. Se acha
  que precisa rever, pergunte antes.
- **Não generalize prematuramente** o pipeline para “dataset com naming
  alternativo”. Faça o mínimo cirúrgico para FRE funcionar agora;
  refatoração estrutural para v0.2+.

## 6. Gate por commit (não-negociável)

Cada commit deve deixar o pacote:

- `devtools::check()` → 0 errors, 0 warnings (NOTE cosmética de “unable
  to verify current time” aceita).
- `devtools::test()` → todos passam.
- [`lintr::lint_package()`](https://lintr.r-lib.org/reference/lint.html)
  → `character(0)`.
- Cobertura ≥85% (gate atual; gate sobe para 90% na Fase E).

Se um commit deixaria o pacote vermelho, divida em commits menores ou
ajuste o escopo.

## 7. Comunicação

Comunicação com Sidney em **português brasileiro**, tom direto. Régua
completa no CLAUDE.md.

Apresente em tabela markdown qualquer descoberta empírica relevante
(Tarefa 1 obrigatoriamente) e espere validação antes de gerar YAMLs.
Para mudanças em R/ (Tarefa 3), apresente 2-3 alternativas com
pró/contra antes de mexer. Para o resto, siga o fluxo normal: execute,
reporte, commit quando autorizado.

## 8. Ao terminar

Reporte:

- Resumo (1-2 parágrafos): o que foi entregue.
- Output da linha “Status” de `devtools::check()`.
- Cobertura: output de
  [`covr::package_coverage()`](http://covr.r-lib.org/reference/package_coverage.md).
- Mudanças estruturais em R/ (se houve), com diff summary.
- Decisões pendentes que apareceram (se houver).
- Sugestão de próxima sessão (provável: 03.3 / 04 — snapshot de
  dicionário, ou `cvm_cache_*` pública, ou início da Fase F mirror).

Pergunta acionável final: “Pode prosseguir para \[próxima sessão\]?”

## Anexo — Pendências de cobertura que ficaram pós-Sessão 03

Não são escopo desta sessão, mas se quiser fechar de carona em commits
pequenos sem perder tempo:

- `R/api-cvm-fetch.R` está em 94.92%. Branch não coberto:
  `resolve_cd_cvm_via_submissao()` quando o dataset não tem submissao
  (caso teórico, não acontece em ITR/DFP/FRE). Cobrir exigiria um
  fixture com dataset sintético sem submissao — provavelmente não vale o
  esforço agora.
- `R/discovery.R` em 59.77% e `R/source-cvm-http.R` em 62.41% seguem
  como áreas baixas, herdadas da Sessão 02. Cobrir essas é trabalho para
  a Fase E (subir cobertura para ≥90%).
