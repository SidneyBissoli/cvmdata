# Prompt — Sessão 3 do Claude Code: schemas e tracer ITR

## Como usar este prompt

Este prompt é o ponto de entrada de **uma janela de contexto limpa**.
Você não precisa do histórico das sessões anteriores: tudo o que é
necessário está em `CLAUDE.md`, `ROADMAP.md`, no estado atual do
código e nos YAMLs DFP que servem de molde.

## 1. Leitura obrigatória (nesta ordem)

1. `CLAUDE.md` — contexto persistente do projeto. Régua de idioma,
   naming, schema YAML, política do reader, hierarquia de condições,
   estrutura de diretórios, comandos comuns. **Leia tudo.**
2. `ROADMAP.md` — estado por fase. A Sessão 02 deixou a Fase D com
   DFP entregue e ITR como próximo item na lista da Sessão 03.
3. `inst/extdata/schemas/dfp/` (11 YAMLs) — moldes que você vai
   adaptar para ITR. Em particular leia `bpa.yaml` (tabela com
   variantes ind/con), `composicao_capital.yaml` e `submissao.yaml`
   (tabelas sem variantes), e `parecer.yaml`.
4. `R/api-cvm-fetch.R`, `R/schema-load.R`, `R/source-cvm-http.R` —
   o pipeline genérico que você NÃO vai tocar nesta sessão. Leia o
   suficiente para saber que ITR vai funcionar "de graça" assim que
   os YAMLs estiverem corretos.
5. `tests/testthat/test-cvm-fetch.R` — testes do DFP (referência
   para o estilo dos testes ITR que você vai adicionar).

Não leia `cvmdata_*.md` (documentos canônicos das rodadas) a menos
que precise auditar algum detalhe específico que o CLAUDE.md não
cobre. O CLAUDE.md já consolidou o essencial.

## 2. Escopo desta sessão

**Entregar ITR ponta-a-ponta.** Onze YAMLs ITR + fixture + tracer +
testes de discovery + atualizações documentais. Nada de FRE, nada de
cache público, nada de snapshot de dicionário — esses são itens
próprios e ficam para sessões posteriores.

ITR é estruturalmente o mesmo problema que DFP: as 11 tabelas
conceituais são as mesmas (`submissao`, `bpa`, `bpp`, `dre`, `dra`,
`dfc_md`, `dfc_mi`, `dmpl`, `dva`, `composicao_capital`, `parecer`),
o pipeline `cvm_fetch_internal()` é agnóstico ao dataset, as
transformações declaradas no YAML (`multiply_by_scale`, `drop`,
`keep_latest_version`) já funcionam. O que muda:

- URL: `DFP` → `ITR` no path do portal.
- `first_year`: `2010` (DFP) → `2011` (ITR).
- Frequência: ITR é trimestral, então `dt_refer` varia dentro do ano.
- `expected_field_count` e `expected_field_names` precisam de
  re-verificação empírica — o META do ITR pode divergir do DFP em
  detalhes (ex.: campo de versão, ordenação).

## 3. Tarefas em ordem

### Tarefa 1 — Verificação empírica do portal ITR

Antes de copiar qualquer YAML, confirme empiricamente as invariantes
que o YAML vai declarar. Faça isso UMA vez por tabela:

1. Baixe um ZIP anual (escolha `2024`):
   `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/ITR/DADOS/itr_cia_aberta_2024.zip`
2. Liste o conteúdo. Confirme que os CSVs seguem o padrão
   `itr_cia_aberta_<TABELA>_<variant?>_2024.csv`.
3. Para cada CSV-alvo, leia o header e conte os campos. Anote
   `expected_field_count` e `expected_field_names`.
4. Verifique a URL do META:
   `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/ITR/META/meta_itr_cia_aberta_txt.zip`
   e o nome do META por tabela dentro do ZIP (mesmo padrão `meta_*`).

Use `httr2` direto (não há helper público para isso ainda). Cache
o ZIP num tempdir para não repetir downloads.

Reporte ao Sidney a tabela com 11 linhas: tabela, n_fields,
variantes encontradas (ind/con/nenhuma), meta_url confirmada.
Espere validação antes de prosseguir para a Tarefa 2.

### Tarefa 2 — Gerar os 11 YAMLs ITR

Para cada tabela, copie o YAML DFP equivalente para
`inst/extdata/schemas/itr/<tabela>.yaml` e aplique substituições
mecânicas:

- `dataset: dfp` → `dataset: itr`
- `dfp_cia_aberta_` → `itr_cia_aberta_` (em URLs e file patterns)
- `/DOC/DFP/` → `/DOC/ITR/` (URLs)
- `first_year: 2010` → `first_year: 2011`
- `expected_field_count`: substituir pelo valor real observado na
  Tarefa 1.
- Comentários do header: adaptar (DFP anual → ITR trimestral).

As `transformations:` permanecem idênticas — `multiply_by_scale` e
`keep_latest_version` aplicam igual em ITR. Se a auditoria empírica
revelar que alguma tabela ITR não tem `vl_conta` ou `escala_moeda`,
ajuste apenas para essa tabela.

Não exporte novas funções. Não toque em `R/`. Se um YAML precisar de
ajuste estrutural que o schema atual não suporta, **pare e pergunte**
em vez de inventar campos novos.

### Tarefa 3 — Fixture ITR

Crie `tests/testthat/fixtures/itr_cia_aberta_2024.zip` análogo ao
fixture DFP. Critério: ZIP pequeno (~50KB total) contendo CSVs
filtrados para 2-3 companhias (uma que já é conhecida no fixture DFP
— BCO BRASIL `001023` — para reuso de helper). Inclua pelo menos:

- `itr_cia_aberta_2024.csv` (submissão)
- `itr_cia_aberta_BPA_ind_2024.csv`
- Um CSV sem variantes (ex.: `composicao_capital`)

Tamanho total <100KB. Construa o fixture programaticamente via
script efêmero — não commite o script, só o ZIP final. Adicione
metadado de origem em `tests/testthat/fixtures/itr_cia_aberta_2024.zip.meta.json`
seguindo o padrão atual (procure por arquivos `.meta.json` se existir;
se não, crie o padrão: campo `source_url`, `fetched_at`,
`companies_included`).

### Tarefa 4 — Testes ITR

Em `tests/testthat/test-cvm-fetch.R`, adicione (não substitua):

- Helper `local_prepare_itr_cache()` análogo a
  `local_prepare_dfp_cache()`.
- Tracer test: `cvm_fetch("itr", "bpa", report_type = "ind",
  years = 2024, source = "cvm")` — espera `cvm_tbl`, atributos,
  `vl_conta` numeric (multiply_by_scale aplicado).
- 1-2 testes de discovery: `cvm_datasets()` agora inclui `"itr"`;
  `cvm_tables("itr")` retorna as 11 tabelas esperadas.

Não duplique a bateria inteira do DFP. Confie no pipeline genérico:
se DFP passa todos os testes e ITR usa o mesmo pipeline, basta 1-2
testes representativos para ITR mais os de discovery.

### Tarefa 5 — Documentação

- `NEWS.md`: bullet sob `# cvmdata (development version)` — `* Add
  ITR (quarterly financial statements) coverage: 11 schemas mirroring
  DFP.`
- `ROADMAP.md`: marca os itens de ITR da Sessão 03 como `[x]`. Se
  houve descobertas empíricas que merecem nota (ex.: ITR usa campo X
  que DFP não usa), registre como sub-item.
- `CLAUDE.md`: se algo estrutural mudou (improvável), atualize. Caso
  contrário, não toque.

### Tarefa 6 — Commit

Antes de cada commit, rode:

```
Rscript -e "lintr::lint_package()"      # deve retornar character(0)
Rscript -e "devtools::test()"            # tudo verde
Rscript -e "devtools::check()"           # 0 errors, 0 warnings,
                                         # 0 notes (exceto "time" cosmética)
```

Sequência sugerida:
1. Commit dos 11 YAMLs + fixture: `feat(itr): add 11 schemas + fixture`.
2. Commit dos testes + docs: `test(itr): add tracer + discovery tests`.
   (Se preferir um commit só, agrupe — Sidney aceita ambas as formas.)

## 4. O que esta sessão NÃO faz

- **Nada de FRE.** 36 YAMLs, 8 com `meta_status: missing`. Sessão
  03.2 ou 04.
- **Não toque** em `R/api-cvm-fetch.R`, `R/source-cvm-http.R`,
  `R/schema-load.R`, `R/transform-schema.R`, `R/discovery.R`. O
  pipeline já está estabilizado pela Sessão 02 + hotfixes. Se algum
  YAML ITR exigir mudança no pipeline, **pare e pergunte**.
- Não implemente `cvm_dictionary()`, `cvm_cache_*()` público,
  `cnpj_format()`, ou qualquer item da Fase E não-ITR.
- Não implemente mirror parquet (Fase F).
- Não reabra decisões travadas no CLAUDE.md ou no ROADMAP. Se acha
  que precisa rever, pergunte antes.

## 5. Gate por commit (não-negociável)

Cada commit deve deixar o pacote:

- `devtools::check()` → 0 errors, 0 warnings (NOTE cosmética de
  "unable to verify current time" aceita).
- `devtools::test()` → todos passam.
- `lintr::lint_package()` → `character(0)`.
- Cobertura ≥85% (alvo da Fase D atual; gate sobe para 90% na
  Fase E).

Se um commit deixaria o pacote vermelho, divida em commits menores.

## 6. Comunicação

Comunicação com Sidney em **português brasileiro**, tom direto.
Régua completa no CLAUDE.md.

Para descobertas empíricas durante a Tarefa 1 (n_fields, variantes
por tabela), apresente em tabela markdown e espere validação antes
de gerar os YAMLs. Para o resto, siga o fluxo normal: execute,
reporte, commit quando autorizado.

## 7. Ao terminar

Reporte:

- Resumo (1-2 parágrafos): o que foi entregue.
- Output da linha "Status" de `devtools::check()`.
- Cobertura: output de `covr::package_coverage()`.
- Decisões pendentes que apareceram (se houver).
- Sugestão de próxima sessão (provável: 03.2 FRE — 36 YAMLs +
  política de `meta_status: missing` exercitada de verdade).

Pergunta acionável final: "Pode prosseguir para Sessão 03.2 (FRE)?"
