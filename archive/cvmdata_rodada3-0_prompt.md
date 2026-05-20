# Prompt — Rodada 3.0: decisões pré-implementação

## Como usar este prompt

Cole o conteúdo abaixo (a partir da linha "INÍCIO DO PROMPT") em uma
conversa nova do projeto `cvmdata` no claude.ai. Antes de colar, anexe
ao chat os seguintes arquivos como **anexos da mensagem**:

1. `cvmdata_rodada2-5_naming_unificado-v02.md` — naming doc canônico
   atualizado (com bloco "Refinamentos incrementais — Rodada 2.6" no
   cabeçalho).
2. `cvmdata_rodada2-6_schemas.md` — fechamento da Rodada 2.6, com o
   plano de ação para a Rodada 3 e a pergunta acionável que motivou
   esta subsessão.

Os demais arquivos do projeto (Custom Instructions, plano arquitetural,
fechamento da Rodada 1, YAMLs de prova de conceito) ficam acessíveis
via Project Knowledge — não precisam ser anexados.

**A sessão exige ambiente com ferramentas de execução ativas**
(`web_fetch` e `bash` em particular), porque P1 requer inspeção
empírica direta dos arquivos do Portal de Dados Abertos CVM. Confirme
que o ambiente está habilitado antes de colar.

---

INÍCIO DO PROMPT

## Contexto

Esta é a Rodada 3.0 do projeto `cvmdata` — subsessão temática de
decisões pré-implementação. A Rodada 2.6 fechou com plano de ação
para a Rodada 3 e pergunta acionável; o mantenedor optou pela
alternativa (b): resolver três decisões pequenas mas com consequências
em cascata antes do scaffolding pleno.

Esta não é a Rodada 3. A Rodada 3 (scaffolding + implementação +
geração programática dos ~72 YAMLs restantes) vem depois e exigirá
ambiente Claude Code, não chat.

Esta é decisão de design. Sem implementação de código. Sem geração de
schemas em lote. Sem reabertura de naming já travado.

## Documentos a consultar antes de qualquer outra coisa

Anexos a esta sessão (foco direto):

- `cvmdata_rodada2-5_naming_unificado-v02.md` — em particular §11
  (pendências empíricas) e §3.0 (caveat de naming FRE-detail).
- `cvmdata_rodada2-6_schemas.md` — em particular §6 (plano de ação
  para a Rodada 3) e §7 (pergunta acionável que motivou esta sessão).

Project Knowledge (consultar quando relevante):

- `cvmdata_projeto_instrucoes_customizadas-v02.md`
- `fechamento-rodada-01.md`
- `cvmdata_rodada2_plano_arquitetural-v02.md`
- `schema_cad_companhias.yaml`,
  `schema_itr_bpa_con.yaml`,
  `schema_fre_administrador_membro_conselho_fiscal.yaml`

## Escopo: três decisões

### P1 — Nome canônico-PT da tabela de cabeçalho ITR/DFP

Única decisão de naming aberta após a Rodada 2.6. O arquivo CVM
`itr_cia_aberta_<ano>.csv` (sem sufixo de demonstração) é o
"cabeçalho" do formulário ITR — contém metadados da submissão, não
linhas de demonstração financeira. Equivalente existe no DFP.

**Verificação empírica obrigatória**:

- Baixar `itr_cia_aberta_<ano>.zip` (ano recente; 2024 ou 2025) do
  Portal CVM.
- Inspecionar o CSV-header isoladamente (separado das tabelas
  BPA/BPP/DRE etc., que já foram inspecionadas na Rodada 2.6).
- Listar todas as colunas do CSV-header. Hipótese a confirmar:
  `CNPJ_CIA`, `DT_REFER`, `VERSAO`, `DENOM_CIA`, `CD_CVM`,
  `CATEG_DOC`, `ID_DOC`, `DT_RECEB`, `LINK_DOC`.
- Repetir verificação para `dfp_cia_aberta_<ano>.zip` para confirmar
  paralelismo ITR/DFP.
- Verificar se o FRE-header (`fre_cia_aberta_<ano>.csv`) tem
  estrutura equivalente e se merece o mesmo nome tidy.

**Candidatos identificados na Rodada 2.6** (não exaustivos; novos
candidatos bem-vindos com justificativa): `cabecalho`, `formulario`,
`protocolo`, `submissao`.

**Critérios de decisão**:

- Coerência com o conteúdo factual do CSV (após verificação).
- Paralelismo ITR/DFP/FRE-header (preferencialmente mesmo nome em
  todos os datasets onde o conceito se aplica).
- Snake_case minúsculo em PT (régua §0 do naming doc).
- Distinguibilidade do termo "header" usado informalmente no plano
  arquitetural (que aqui é apenas referência conceitual, não nome
  de tabela).

**Saída esperada**: nome único travado, com decisão explícita sobre
aplicabilidade a FRE-header.

### P2 — Formato do snapshot de dicionário CVM

O snapshot é o arquivo único embarcado no pacote em
`inst/extdata/cvm_dictionary_snapshot.<ext>` que alimenta
`cvm_dictionary(dataset, table)`. A **estrutura interna** já está
definida no naming doc (§7.5 e §11): tabela longa com chave composta
`dataset` + `table` + `column` e as 7 colunas do schema oficial CVM
(`campo`, `descricao`, `dominio`, `tipo_dados`, `tamanho`,
`precisao`, `scale`). Não está em discussão a estrutura — está em
discussão o **formato de serialização**.

**Alternativas a avaliar**:

- **CSV** (`.csv` UTF-8). Legível, versionável em Git com diffs
  inteligíveis, sem dependência adicional. Leitura mais lenta
  (~50-200ms para o snapshot estimado).
- **Parquet** (`.parquet`). Binário, comprimido, leitura rápida
  (<20ms). Exige `arrow` em `Imports:` (já está no stack travado da
  Rodada 1/2). Diffs em Git ininteligíveis.
- **RDS** (`.rds`). Binário, padrão R, sem dependência adicional.
  Diffs ininteligíveis. Levemente acoplado a versões de R
  (geralmente retrocompatível).

**Critérios de decisão**:

- Tamanho final em `inst/extdata` (CRAN policy: pacote total <5MB
  sem pedido de exceção; <10MB com pedido). Snapshot estimado em
  ~10k linhas × 9 colunas; provavelmente <500KB em CSV, <100KB em
  Parquet/RDS.
- Velocidade de carregamento (`cvm_dictionary()` é função de
  descoberta interativa; aceitável até ~100ms).
- Versionabilidade em Git (relevante para revisão humana de
  atualizações futuras do snapshot via PR).
- Coerência com stack já travado.

**Decisões aninhadas a tomar junto**:

- Nome final do arquivo (`cvm_dictionary_snapshot.<ext>` é a forma
  proposta — confirmar ou ajustar).
- Localização final em `inst/extdata/` (raiz ou subpasta).
- Política de atualização: o workflow ETL da Rodada 1 (terças
  07:00 UTC, event-driven via hash) regenera o snapshot — qual é o
  trigger exato de mudança? Comparação de hash dos arquivos
  `meta_*.txt` do Portal CVM?

**Saída esperada**: formato escolhido + justificativa de
trade-offs + decisões aninhadas resolvidas.

### P3 — Formato do snapshot de codelists empíricas

Schema base definido no fechamento da Rodada 2.6 (§6 item 4): chave
composta `dataset` + `table` + `column` + colunas adicionais. Codelists
**vêm de varredura empírica do CSV**, não do META — vide §4.4 do
fechamento da 2.6.

**Decisões a tomar**:

- **Formato de serialização**: mesmas alternativas de P2 (CSV,
  Parquet, RDS). Pode ser igual a P2 por consistência ou diferente
  com justificativa.
- **Campos do schema**:
  - Obrigatórios: `dataset` (chr), `table` (chr), `column` (chr),
    `value` (chr — valor categórico em PT como vem da CVM).
  - Opcionais a decidir: `frequency` (int) — quantas ocorrências na
    varredura; útil para usuário identificar valores raros mas custoso
    de gerar/manter. `first_seen_year`, `last_seen_year` (int) —
    detecta valores deprecated; mais custoso ainda. Decisão
    custo-benefício.
- **Estratégia de geração**: varredura empírica completa da série
  histórica disponível ou apenas snapshot pontual do ano mais recente?
  Trade-off: completude vs custo de manutenção do workflow ETL.

**Critérios de decisão**: idênticos aos de P2 para formato, mais
decisão sobre custo-benefício de incluir campos opcionais.

**Saída esperada**: formato + schema final (com obrigatórios e
opcionais explicitados) + estratégia de geração.

## Entrega obrigatória

Arquivo único
`/mnt/user-data/outputs/cvmdata_rodada3-0_decisoes_pre_implementacao.md`,
em português brasileiro, com a seguinte estrutura. Cada seção é
obrigatória, mesmo que curta.

```
# Rodada 3.0 — Decisões pré-implementação

> Cabeçalho metadata: data de fechamento, versão, status (travado),
> documentos predecessores e sucessores.

## 1. Resumo executivo
## 2. P1 — Nome canônico-PT do header ITR/DFP
   ### 2.1 Verificação empírica realizada
   ### 2.2 Alternativas avaliadas
   ### 2.3 Decisão e justificativa
   ### 2.4 Aplicabilidade a FRE-header
## 3. P2 — Formato do snapshot de dicionário CVM
   ### 3.1 Critérios de decisão
   ### 3.2 Alternativas avaliadas
   ### 3.3 Estrutura interna (referência ao §7.5/§11 do naming doc)
   ### 3.4 Decisão e justificativa
   ### 3.5 Decisões aninhadas (nome do arquivo, localização,
   trigger de atualização)
## 4. P3 — Formato do snapshot de codelists empíricas
   ### 4.1 Critérios de decisão
   ### 4.2 Alternativas avaliadas
   ### 4.3 Schema final (obrigatórios e opcionais)
   ### 4.4 Estratégia de geração
   ### 4.5 Decisão e justificativa
## 5. Atualizações requeridas no naming doc
   ### 5.1 Refinamentos incrementais a aplicar
   ### 5.2 Itens §11 a marcar como [RESOLVIDO 3.0]
## 6. Pendências e tarefas remanescentes para Rodada 3 plena
## 7. Pergunta acionável para o mantenedor
```

### Conteúdo prescrito por seção

**§1 Resumo executivo** — Até 10 linhas. O que se resolveu, qual o
status (travado), o que isso destrava para a Rodada 3 plena.

**§2-§4** — Para cada decisão: verificação empírica conduzida (com
URLs e achados quando aplicável; em P1 isso é obrigatório),
alternativas avaliadas com prós/contras balanceados, decisão final
com justificativa rastreável aos critérios.

**§5 Atualizações no naming doc** — Lista numerada de refinamentos a
adicionar ao naming doc (não executar a atualização nesta sessão; só
documentar o que deve mudar e onde). Marcar explicitamente quais
bullets de §11 do naming doc passam para `[RESOLVIDO 3.0]`.

**§6 Pendências para Rodada 3 plena** — Sintetizar o que da §6 do
fechamento da Rodada 2.6 segue aberto após esta sessão. Não duplicar
o que está lá; apenas atualizar status (resolvido / sem mudança /
refinado).

**§7 Pergunta acionável** — Múltipla escolha:
(a) Seguir para Rodada 3 plena (scaffolding + implementação em
    Claude Code) com naming doc atualizado em seguida pelo
    mantenedor.
(b) Atualizar o naming doc com os refinamentos da Rodada 3.0 antes
    de qualquer codificação (sessão dedicada curta de edição).
(c) Subsessão temática adicional (qual?).

## Restrições

- **Não reabrir naming já travado**. As 26 decisões da Rodada 2.5 e
  os 7 refinamentos da Rodada 2.6 estão travados. A Rodada 3.0 só
  adiciona — não revisa.
- **Não reescrever YAMLs**. Os 3 templates da Rodada 2.6 estão
  validados.
- **Não gerar código de implementação**. Esta sessão é decisão de
  design, não scaffolding nem reader.
- **Verificação empírica obrigatória para P1**. Inspecionar o CSV
  CVM diretamente, não inferir. Para P2/P3, raciocínio sobre
  trade-offs é suficiente; micro-benchmark é desejável mas opcional.
- **Idioma do documento**: português brasileiro.
- **Idioma de identificadores citados**: como vêm do naming doc
  (mistura controlada PT/EN conforme régua §0).
- **Sem emojis**, sem fluff, sem reverência.
- **Sem placeholder do tipo `[TODO]` ou `[a definir]`**. Se algo
  permanece aberto, vai para §6 como tarefa nomeada da Rodada 3
  plena.

## Método

1. Ler o fechamento da Rodada 2.6 anexado (especialmente §6 e §7).
2. Ler o §11 do naming doc anexado.
3. P1: baixar o ZIP do ITR e do DFP recentes; inspecionar o CSV-
   header; decidir nome. Confirmar paralelismo. Verificar
   pertinência ao FRE-header.
4. P2: raciocínio sobre trade-offs CSV/Parquet/RDS; micro-benchmark
   opcional se ambiente permitir (gerar piloto de 1-2 datasets,
   medir tamanho e tempo de leitura).
5. P3: análoga a P2, com discussão adicional sobre campos opcionais
   e estratégia de geração.
6. Produzir o documento em uma única passagem.
7. Apresentar via `present_files` e abrir a §7 (pergunta acionável).

## Entrega esperada

- 1 arquivo markdown em
  `/mnt/user-data/outputs/cvmdata_rodada3-0_decisoes_pre_implementacao.md`
- Apresentado com `present_files`.
- Mensagem de fechamento curta, com a pergunta acionável de §7.

FIM DO PROMPT — não adicione nada depois desta linha.
