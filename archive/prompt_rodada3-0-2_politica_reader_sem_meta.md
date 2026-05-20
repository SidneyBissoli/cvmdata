# Prompt — Rodada 3.0.2: Política do reader para tabelas com dados publicados mas sem META

## Como usar este prompt

Cole o conteúdo abaixo (a partir da linha "INÍCIO DO PROMPT") em uma
conversa nova do projeto `cvmdata` no claude.ai. Antes de colar,
anexe ao chat os seguintes arquivos como **anexos da mensagem**:

1. `cvmdata_rodada3-0_decisoes_pre_implementacao.md` — contém em §6
   item 8 a diretriz preliminar a refinar.
2. `cvmdata_rodada2-5_naming_unificado-v03.md` — naming doc canônico
   atualizado; §11.3 (último bullet) e §11.5 documentam defeitos
   conhecidos da CVM e devem ser atualizados ao final desta sessão.

Os demais documentos (Custom Instructions, fechamento da Rodada 1,
plano arquitetural, fechamento da Rodada 2.6, fechamento da Rodada
2.5/v03) ficam acessíveis via Project Knowledge.

**A sessão exige ferramentas de execução**: `web_fetch` para baixar
ZIPs do Portal CVM e `bash` para extrair, contar arquivos e comparar
listas. Habilitar ambos.

---

INÍCIO DO PROMPT

## Contexto

Esta é a Rodada 3.0.2 do projeto `cvmdata` — subsessão temática
dedicada a fechar uma política de design que ficou aberta no
fechamento da Rodada 3.0 (§6 item 8): **como o reader deve se
comportar quando uma tabela CVM tem dados publicados (CSV no ZIP
de DADOS) mas não tem META correspondente no ZIP de META**.

A Rodada 3.0 detectou empiricamente em 2026-05-19 oito casos no
FRE-2024:

- `administrador_PCD`
- `empregado_PCD`
- `empregado_local_declaracao_genero`
- `empregado_local_declaracao_raca`
- `empregado_posicao_declaracao_genero`
- `empregado_posicao_declaracao_raca`
- `empregado_posicao_faixa_etaria`
- `empregado_posicao_local`

A diretriz preliminar registrada em §6 item 8 do fechamento da
Rodada 3.0 propõe: leitura sem validação contra META, com warning
informativo via `cli::cli_warn()`; `cvm_dictionary_url: null` no
YAML; `expected_field_count` derivado de contagem empírica do CSV;
entradas no `cvm_dictionary_snapshot.csv` com `descricao = NA` para
todas as colunas.

Esta sessão **valida ou refina** essa diretriz com base em:
(i) varredura empírica adicional para entender o escopo real do
problema (não apenas FRE-2024); (ii) consideração de alternativas
de design; (iii) consequências em cascata para o resto do pacote.

## Documentos a consultar antes de qualquer outra coisa

Anexos a esta sessão:

- `cvmdata_rodada3-0_decisoes_pre_implementacao.md` — §6 item 8
  (diretriz preliminar) e §2.1 (achado empírico original).
- `cvmdata_rodada2-5_naming_unificado-v03.md` — §11.3 (último
  bullet) e §11.5 (defeitos conhecidos da CVM) — onde a decisão
  desta sessão deve aterrissar.

Project Knowledge (referência):

- `cvmdata_projeto_instrucoes_customizadas-v02.md` (régua de idioma
  e tom).
- `cvmdata_rodada1_fechamento.md` (escopo macro, fora de escopo
  permanente).
- `cvmdata_rodada2_plano_arquitetural-v02.md` (estrutura de
  classes de condição, semântica de `validate` e `on_error`).
- `cvmdata_rodada2-6_schemas.md` (princípios de schema, três YAMLs
  exemplares já produzidos).

## Escopo: questões a responder

### Q1 — Escopo real do problema (verificação empírica)

A Rodada 3.0 verificou apenas FRE-2024. Antes de travar política,
verificar:

**Q1.1** O mesmo padrão (CSV sem META) ocorre em **outros anos
do FRE** (mínimo: amostragem em 2020, 2015, 2011)?

**Q1.2** O padrão simétrico (META sem CSV) também ocorre? Em FRE
ou em outros datasets do escopo v0.1 (ITR, DFP, CAD)?

**Q1.3** ITR e DFP apresentam o mesmo defeito? (Spot check em
releases recentes e antigos.)

**Q1.4** CAD apresenta o mesmo defeito? (CAD é mais simples — um
META por arquivo principal — mas vale verificar tabelas auxiliares.)

**Q1.5** Para as 8 tabelas-órfãs documentadas, há **algum**
release histórico em que essas tabelas tinham META correspondente?
Hipótese a testar: META foi removido em algum momento; tabelas
existiam antes com dicionário e ficaram órfãs após reformulação
do FRE.

A verificação empírica destas perguntas é o trabalho central desta
sessão. Sem ela, qualquer política fica em base frágil.

### Q2 — Alternativas de design

Avaliar pelo menos as 3 opções abaixo (apresentar como tabela de
prós/contras conforme convenção do projeto):

**Opção A — Leitura permissiva com warning** (diretriz preliminar
da Rodada 3.0).
- Reader lê o CSV; valida contagem de campos contra
  `expected_field_count` derivado de contagem empírica; emite
  warning informativo sobre ausência de META.
- Snapshot de dicionário tem entradas para essas tabelas com
  `descricao = NA`, `dominio = NA`, `tipo_dados = NA`, `tamanho`
  igual ao maior valor observado empiricamente (ou NA), demais
  metadados NA.

**Opção B — Leitura permissiva sem alarme**.
- Reader lê o CSV sem warning; trata META ausente como caso
  normal documentado em vinheta.
- Snapshot de dicionário tem entradas mínimas: apenas `campo` (do
  cabeçalho do CSV).

**Opção C — Exclusão do escopo v0.1**.
- Tabelas sem META não entram na v0.1; podem entrar em v0.2+
  quando (a) a CVM publicar o META, ou (b) o pacote tiver uma
  utilitária `cvm_register_external_dictionary()` para o usuário
  fornecer dicionário manualmente.
- Reader retorna erro `cvmdata_error_internal` se chamado para
  essas tabelas (mensagem clara: "tabela X publicada pela CVM mas
  sem META; suporte planejado para v0.2+").

**Opção D — Dicionário manual mantido pelo pacote**.
- Mantenedor escreve à mão (com base em inspeção empírica do CSV
  e do site da CVM) um META artesanal para cada tabela órfã,
  versionado em `inst/extdata/meta_manual/`.
- Reader trata essas tabelas como tabelas normais; snapshot de
  dicionário tem entradas completas mas com flag
  `meta_origem = "manual"` ou similar.

Critérios de decisão a aplicar:
- Coerência com princípio reitor "fica como vem da CVM, é decisão
  do pacote o que não vem" (§0.1 do naming doc).
- Coerência com semântica de `validate` (§2.2 do naming doc) e
  `on_error` (§2.1).
- Custo de manutenção contínua (defeitos da CVM mudam release a
  release).
- Risco de mascarar defeitos novos (false negatives).
- Experiência do usuário em casos comuns vs casos limítrofes.

### Q3 — Consequências em cascata

Para a opção recomendada, mapear consequências em:

**Q3.1** Estrutura do YAML por tabela (§7.2 do naming doc):
campos a adicionar/permitir-nulo (`cvm_dictionary_url`,
`expected_field_count`).

**Q3.2** Schema do `cvm_dictionary_snapshot.csv` (§3.3 do
fechamento da Rodada 3.0 e §7.5 do naming doc): se entradas com
metadados NA são aceitas, ou se precisa de coluna adicional
(`meta_origem`, `meta_status`, etc.).

**Q3.3** Workflow ETL (§3.5 do fechamento da Rodada 3.0):
hash-tracking precisa rodar nesse caso? Como detectar quando a
CVM finalmente publica META para uma tabela órfã?

**Q3.4** Mensagens cli: texto exato dos warnings, em inglês,
seguindo convenção §6.2 do naming doc.

**Q3.5** Vinheta de defeitos conhecidos (planejada em §11.5 do
naming doc, [ADIÇÃO 2.6]): seção dedicada a este caso, com lista
empírica nominal.

**Q3.6** Política de remoção de tabelas órfãs: se a CVM publicar
META para uma das 8 tabelas em release futuro, o pacote deve
detectar e migrar para tratamento normal? Como?

### Q4 — Política simétrica (META sem CSV)

Se Q1.2 confirmar que o caso simétrico existe, propor política
análoga. Se Q1.2 retornar zero casos, registrar formalmente e
fechar a pendência.

## Entrega obrigatória

Arquivo único
`/mnt/user-data/outputs/cvmdata_rodada3-0-2_politica_reader_sem_meta.md`,
em português brasileiro, estruturado em seções análogas às do
fechamento da Rodada 3.0:

1. **Resumo executivo** (3-5 bullets).
2. **Q1 — Escopo empírico** (subseções por sub-questão; tabelas e
   URLs verificadas; achados textuais).
3. **Q2 — Alternativas de design** (tabela de prós/contras; opção
   recomendada com justificativa rastreável aos critérios listados
   no prompt).
4. **Q3 — Consequências em cascata** (uma subseção por sub-questão
   acima).
5. **Q4 — Política simétrica** (se aplicável, ou registro de
   não-aplicabilidade).
6. **Atualizações requeridas em documentos canônicos** — lista de
   alterações a aplicar no naming doc (§11.3 último bullet, §11.5,
   eventuais novas notas em §7.2/§7.5) em sessão de edição
   dedicada análoga à Rodada 3.0.1.
7. **Pendências e tarefas remanescentes para Rodada 3 plena**
   (atualização incremental ao §6 do fechamento da Rodada 3.0).
8. **Pergunta acionável para o mantenedor** (próximo passo).

Tom e estilo idênticos aos do fechamento da Rodada 3.0.

## Restrições

- **Decisões anteriores travadas não se reabrem**. Rodadas 1, 2,
  2.5, 2.6, 3.0 permanecem como estão. Esta sessão fecha apenas a
  questão da política do reader para tabelas órfãs.
- **Verificação empírica é o método central**. Inferência baseada
  em documentação secundária não substitui inspeção direta dos
  arquivos do Portal CVM.
- **Honestidade epistêmica**: se uma sub-questão de Q1 não puder
  ser respondida nesta sessão (ex.: arquivos do Portal CVM
  indisponíveis no momento), registrar a limitação explicitamente e
  propor decisão condicional ou diferimento para sessão futura.
- **Sem ferramentas de execução para resposta sem dados empíricos**:
  caso `web_fetch` falhe ou caso o ambiente bash não tenha capacidade
  de extrair os ZIPs necessários, registrar a falha como limitação
  da sessão e tomar a melhor decisão possível com os dados que a
  Rodada 3.0 já produziu (FRE-2024 apenas).
- **Sem emojis, sem fluff, sem reverência**. Tom técnico, direto.
- **Idioma**: português brasileiro no documento; identificadores e
  mensagens cli em inglês.

## Método

1. Ler `cvmdata_rodada3-0_decisoes_pre_implementacao.md` §2.1 e §6
   item 8.
2. Ler `cvmdata_rodada2-5_naming_unificado-v03.md` §7.2, §7.5,
   §11.3 (último bullet), §11.5 (defeitos conhecidos).
3. Verificação empírica:
   a. Baixar `fre_cia_aberta_<ano>.zip` e
      `meta_fre_cia_aberta.zip` para 3 anos (2024, 2015, 2011);
      listar CSVs e META; comparar conjuntos.
   b. Baixar `itr_cia_aberta_2024.zip` e
      `meta_itr_cia_aberta_txt.zip`; comparar.
   c. Baixar `dfp_cia_aberta_2024.zip` e o META do DFP; comparar.
   d. Baixar `cad_cia_aberta.zip` e o META do CAD; comparar.
   e. Para as 8 tabelas órfãs do FRE-2024, verificar se aparecem
      em release histórico do FRE com META correspondente.
4. Análise de alternativas (Q2) — apresentar tabela completa.
5. Mapear consequências (Q3) sub-questão a sub-questão.
6. Tratar política simétrica (Q4).
7. Escrever documento de fechamento conforme estrutura acima.
8. Salvar como
   `/mnt/user-data/outputs/cvmdata_rodada3-0-2_politica_reader_sem_meta.md`.
9. Apresentar via `present_files`.
10. Mensagem de fechamento curta: resumo executivo + pergunta
    acionável.

## Entrega esperada

- 1 arquivo markdown em
  `/mnt/user-data/outputs/cvmdata_rodada3-0-2_politica_reader_sem_meta.md`.
- Apresentado com `present_files`.
- Mensagem de fechamento com resumo (3-5 bullets) e pergunta
  acionável sobre próximo passo.

FIM DO PROMPT — não adicione nada depois desta linha.
