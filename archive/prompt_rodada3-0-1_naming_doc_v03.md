# Prompt — Rodada 3.0.1: Atualização editorial do naming doc para v03

## Como usar este prompt

Cole o conteúdo abaixo (a partir da linha "INÍCIO DO PROMPT") em uma
conversa nova do projeto `cvmdata` no claude.ai. Antes de colar, anexe
ao chat os seguintes arquivos como **anexos da mensagem**:

1. `cvmdata_rodada2-5_naming_unificado-v02.md` — naming doc canônico
   atualizado (versão atual; vai ser substituído ao final desta sessão
   pela v03).
2. `cvmdata_rodada3-0_decisoes_pre_implementacao.md` — fechamento da
   Rodada 3.0, que contém em §5 as instruções editoriais exatas a
   aplicar.

Os demais arquivos do projeto (Custom Instructions, plano arquitetural,
fechamento da Rodada 1, fechamento da Rodada 2.6) ficam acessíveis via
Project Knowledge — não precisam ser anexados.

**A sessão não exige ferramentas de execução pesadas**. É edição
editorial. `web_fetch` e `bash` podem permanecer desabilitados.

---

INÍCIO DO PROMPT

## Contexto

Esta é a Rodada 3.0.1 do projeto `cvmdata` — subsessão de pura edição
editorial do naming doc. A Rodada 3.0 fechou três decisões de design
(P1: nome canônico `submissao`; P2: snapshot de dicionário em CSV;
P3: snapshot de codelists em CSV) e listou em §5 do documento de
fechamento os refinamentos exatos a aplicar ao naming doc.

Esta sessão executa essa lista. **Não toma novas decisões**. Não
reabre nada. Não verifica nada empiricamente. Apenas aplica os
refinamentos prescritos e materializa o naming doc v03.

A versão v02 será substituída pela v03 após esta sessão.

## Documentos a consultar antes de qualquer outra coisa

Anexos a esta sessão:

- `cvmdata_rodada2-5_naming_unificado-v02.md` — fonte que será
  editada.
- `cvmdata_rodada3-0_decisoes_pre_implementacao.md` — instruções
  editoriais em §5.1 e §5.2; conteúdo das decisões em §2/§3/§4.

Project Knowledge (referência apenas; não precisa abrir):

- `cvmdata_projeto_instrucoes_customizadas-v02.md` (régua de idioma e
  tom).
- `fechamento-rodada-01.md`, `cvmdata_rodada2_plano_arquitetural-v02.md`,
  `cvmdata_rodada2-6_schemas.md` (predecessores travados).

## Escopo: refinamentos a aplicar

A §5.1 da Rodada 3.0 lista 6 refinamentos numerados. A §5.2 da
Rodada 3.0 lista mudanças em §11 do naming doc. Esta sessão aplica
todos. Lista consolidada abaixo para conveniência operacional —
sempre verificar contra o documento de fechamento para o texto
exato:

### Refinamentos em §5.1

1. **Cabeçalho do documento** — adicionar bloco "Refinamentos
   incrementais — Rodada 3.0 (2026-05-19)" logo após o bloco
   existente da Rodada 2.6. Mesma estrutura de bullets curtos
   sumarizando cada decisão da Rodada 3.0 com referência à
   seção do documento de fechamento.
2. **§3 (Colunas-chave universais)** — adicionar nota explicando
   que a tabela canônica que contém as 5 colunas-chave + 4 colunas
   de metadados de submissão chama-se `submissao` em ITR, DFP e
   FRE.
3. **§4.1 (Tabelas ITR e DFP)** — adicionar linha
   `submissao` na tabela das 18 tabelas espelhadas; ajustar
   contagem total para 19 tabelas espelhadas + ainda 1 nota sobre
   pendência (que agora é histórica, não atual). Texto canônico da
   linha: `submissao` | "Registro de submissão do documento à CVM
   (metadados administrativos)" | "tabela de cabeçalho do
   formulário; nome decidido na Rodada 3.0 após verificação
   empírica".
4. **§4.2 (Tabelas FRE)** — substituir, na "Categoria A —
   Cabeçalho", o texto "a confirmar nome empírico" por `submissao`.
   Atualizar a observação sobre tabelas-fantasma de "14 a mais que
   CSVs no release 2024" para "22 a mais que CSVs no release 2024"
   (achado refinado em 2026-05-19 — vide §5.2 da Rodada 3.0). Total
   FRE: 36 tabelas reais (1 `submissao` + 35 detalhes).
5. **§7 (YAMLs de schema interno)** — adicionar nova subseção §7.8
   "Snapshot de codelists empíricas" com:
   - Formato: CSV UTF-8 com delimitador `,` em
     `inst/extdata/cvm_codelists_snapshot.csv`.
   - Schema obrigatório: 4 colunas (`dataset`, `table`, `column`,
     `value`).
   - Schema opcional incluído na v0.1: `first_seen_year` (integer).
   - Schema deferido para v0.2+: `frequency`, `last_seen_year`.
   - Estratégia de geração: varredura histórica completa com cache
     por hash do CSV.
   - Referência cruzada ao §4 da Rodada 3.0 para detalhamento e ao
     §4.4 / §4.5 do fechamento da Rodada 2.6 para princípio
     ("codelists vêm de varredura empírica, não do META";
     "codelist tem escopo (tabela, coluna), não coluna isolada").
6. **§7.4 (Dicionário CVM em snapshot separado)** — substituir o
   trecho "ou equivalente, formato final a decidir na Rodada 3"
   por "formato CSV UTF-8, delimitador `,`" com referência à §3.4
   do fechamento da Rodada 3.0.

### Mudanças em §11 (registro de pendências)

7. **§11.1, primeiro bullet** (nome canônico-PT do cabeçalho
   ITR/DFP): atualizar de `[RESOLVIDO 2.6]` com caveat "nome
   canônico-PT permanece a decidir" para `[RESOLVIDO 3.0]: tabela
   chama-se `submissao`; aplica-se também a FRE-header`. Manter o
   bullet (não remover) para preservar histórico.
8. **§11.4, primeiro bullet** (nome final do snapshot de
   dicionário): marcar como `[RESOLVIDO 3.0]:
   inst/extdata/cvm_dictionary_snapshot.csv em formato CSV UTF-8`.
9. **§11.4, segundo bullet** (workflow GitHub Action para
   atualização do snapshot): marcar como `[REFINADO 3.0]: trigger
   por hash dos meta_*.txt + abertura de PR para revisão humana;
   integrado ao workflow ETL existente (terças 07:00 UTC).
   Implementação no escopo da Rodada 3 plena`.
10. **§11.4, novo bullet [ADIÇÃO 3.0]**: snapshot de codelists
    empíricas — formato CSV em
    `inst/extdata/cvm_codelists_snapshot.csv`, schema mínimo de 4
    colunas + opcional `first_seen_year`, geração por varredura
    histórica completa com cache por hash. Referência cruzada à
    §4 da Rodada 3.0.
11. **§11.3 (Conteúdo), novo bullet [ADIÇÃO 3.0]**: descoberta
    empírica de 8 tabelas FRE com dados publicados mas sem META
    correspondente (`administrador_PCD`, `empregado_PCD`,
    `empregado_local_declaracao_genero`,
    `empregado_local_declaracao_raca`,
    `empregado_posicao_declaracao_genero`,
    `empregado_posicao_declaracao_raca`,
    `empregado_posicao_faixa_etaria`, `empregado_posicao_local`).
    Política do reader para esse caso fica para Rodada 3.0.2
    (subsessão temática dedicada).

### Mudanças de metadata

12. **Header do documento** — bumpar a versão do naming doc para
    v03; atualizar a data implícita (a versão v02 foi fechada em
    2026-05-18 com os refinamentos da Rodada 2.6; v03 fecha em
    2026-05-19 com os da Rodada 3.0). Manter "Status: travado.
    Não reabrir sem evidência substancial nova."

## Entrega obrigatória

Arquivo único
`/mnt/user-data/outputs/cvmdata_rodada2-5_naming_unificado-v03.md`,
em português brasileiro, contendo o naming doc v02 inteiro com os
12 refinamentos acima aplicados.

A estrutura e o tom permanecem idênticos aos da v02. Não há
reescrita estilística. Não há reorganização de seções. Apenas
inserções, substituições e marcações conforme listado.

## Restrições

- **Não tomar decisões novas**. Esta sessão é editorial. Todas as
  decisões já foram tomadas em rodadas anteriores e estão
  documentadas.
- **Não reabrir** decisões travadas. Nem da Rodada 1, nem da 2, nem
  da 2.5, nem da 2.6, nem da 3.0.
- **Não verificar empiricamente**. Os dados de verificação já estão
  no §2 do documento da Rodada 3.0; usar como fonte secundária se
  precisar do detalhe factual (ex.: número exato de campos).
- **Não criar conteúdo novo** além do prescrito em §5 da Rodada 3.0.
  Se ao aplicar um refinamento perceber inconsistência interna no
  documento, registrar como observação na mensagem de fechamento,
  não no próprio documento.
- **Preservar histórico**. Bullets de §11 marcados como `[RESOLVIDO
  2.6]` permanecem (com o label atualizado quando aplicável,
  conforme item 7). §10 (histórico das 26 decisões) permanece
  intacta.
- **Idioma**: português brasileiro no documento; identificadores em
  inglês ou PT conforme a régua de idioma já estabelecida.
- **Sem emojis**, sem fluff, sem reverência.

## Método

1. Ler `cvmdata_rodada3-0_decisoes_pre_implementacao.md` §5
   integralmente.
2. Ler `cvmdata_rodada2-5_naming_unificado-v02.md` inteiro para
   ter o contexto da forma atual.
3. Para cada refinamento numerado (1–12 acima), localizar a seção
   correspondente no naming doc v02 e aplicar a edição prescrita.
4. Após aplicar todos, fazer leitura corrida do v03 inteiro para
   verificar consistência interna (referências cruzadas, contagem
   de tabelas em §4.1 e §4.2, marcadores de status em §11).
5. Salvar como
   `/mnt/user-data/outputs/cvmdata_rodada2-5_naming_unificado-v03.md`.
6. Apresentar via `present_files`.
7. Mensagem de fechamento curta: lista numerada das 12 mudanças
   aplicadas + sinalização de qualquer inconsistência detectada na
   leitura corrida (se houver).

## Entrega esperada

- 1 arquivo markdown em
  `/mnt/user-data/outputs/cvmdata_rodada2-5_naming_unificado-v03.md`.
- Apresentado com `present_files`.
- Mensagem de fechamento listando as 12 mudanças aplicadas.

FIM DO PROMPT — não adicione nada depois desta linha.
