# Prompt — Rodada 2.6 (continuação): documento de acompanhamento

## Como usar este prompt

Cole o conteúdo abaixo (a partir da linha "INÍCIO DO PROMPT") em uma
nova conversa do projeto `cvmdata` no claude.ai. Antes de colar, anexe
ao chat os seguintes arquivos como **anexos da mensagem**:

1. `cvmdata_rodada2-5_naming_unificado.md` — versão atualizada após
   refinamentos da Rodada 2.6 (a que tem o bloco "Refinamentos
   incrementais — Rodada 2.6" no cabeçalho).
2. `cad/companhias.yaml` — primeiro YAML produzido na Rodada 2.6.
3. `itr/bpa_con.yaml` — segundo YAML produzido na Rodada 2.6.
4. `fre/administrador_membro_conselho_fiscal.yaml` — terceiro YAML
   produzido na Rodada 2.6.

Os arquivos do projeto (Custom Instructions, plano arquitetural,
fechamento da Rodada 1) já estarão acessíveis via Project Knowledge.

---

INÍCIO DO PROMPT

## Contexto

Esta é a continuação da Rodada 2.6 do projeto `cvmdata`. A primeira
metade da rodada (verificação empírica e produção dos três YAMLs de
schema-template) foi executada em sessão anterior e entregou:

- 3 YAMLs em `inst/extdata/schemas/<dataset>/<tabela>.yaml`
- Naming doc atualizado com 7 refinamentos incrementais

Os YAMLs e o naming doc atualizado estão **anexados a esta sessão**.
Leia-os antes de qualquer outra coisa.

Esta segunda metade da rodada produz **um único entregável**:

> `cvmdata_rodada2-6_schemas.md` — documento de acompanhamento que
> consolida o que foi feito, decidido, resolvido e o que permanece
> pendente.

Nada além disso. Sem reabrir naming. Sem revisar YAMLs. Sem antecipar
Rodada 3.

## Entrega obrigatória

Arquivo único `/mnt/user-data/outputs/cvmdata_rodada2-6_schemas.md`,
em português brasileiro, com a seguinte estrutura. Cada seção é
obrigatória, mesmo que curta.

### Estrutura

```
# Rodada 2.6 — Schemas de prova de conceito

> Cabeçalho metadata: data de fechamento, versão, status (travado),
> documentos predecessores e sucessores.

## 1. Resumo executivo
## 2. Entregáveis produzidos
   ### 2.1 YAMLs (3 arquivos)
   ### 2.2 Naming doc — refinamentos incrementais aplicados
## 3. Verificação empírica realizada
   ### 3.1 Topologia de download por dataset
   ### 3.2 Encoding e delimitador (todos os 3 datasets verificados)
   ### 3.3 Inspeção dos dicionários CVM
   ### 3.4 Inspeção amostral dos CSVs
## 4. Decisões pontuais novas tomadas na Rodada 2.6
   ### 4.1 Nome do YAML FRE — `administrador_membro_conselho_fiscal`
   ### 4.2 Heterogeneidade de naming FRE-detail — preservação estrita
   ### 4.3 CD_CVM definitivamente character
   ### 4.4 Codelists não vêm do META — vêm da varredura empírica do CSV
   ### 4.5 Codelist é (tabela, coluna), não coluna
   ### 4.6 `convert_to_date` automático — fora do domínio de `action`
   ### 4.7 Aviso geral: `Tipo Dados` do META CVM não é confiável para identificadores
## 5. Resolução de pendências §11 do naming doc
   ### 5.1 Resolvidas integralmente
   ### 5.2 Resolvidas parcialmente
   ### 5.3 Adições novas
   ### 5.4 Permanecem para Rodada 3
## 6. Pendências e tarefas para a Rodada 3
## 7. Pergunta acionável para o mantenedor
```

### Conteúdo prescrito por seção

**§1 Resumo executivo** — Até 12 linhas. O que era a Rodada 2.6, o que
mudou, qual o status (travado/incremental/aberto).

**§2.1 YAMLs** — Listar os 3 caminhos relativos, com uma frase de uma
linha caracterizando cada um (CAD = caso simples sem transformações;
ITR/BPA = caso intermediário com `multiply_by_scale` + `drop`;
FRE/administrador... = caso categórico). Não reproduzir o conteúdo dos
YAMLs no documento; eles falam por si.

**§2.2 Refinamentos no naming doc** — Lista numerada dos 7 refinamentos
aplicados. Cada item: seção afetada, o que mudou em uma linha. Não
discutir; só inventariar. O detalhe está no naming doc.

**§3 Verificação empírica realizada** — Estruturado como dump de fatos
verificados, não como narrativa. Use tabelas e bullets. Cobertura
mínima:

- §3.1 Topologia de download: tabela com colunas `dataset` |
  `cvm_archive_url_pattern` | `cvm_file_url_pattern` |
  `cvm_file_pattern` | `cvm_dictionary_url`. Três linhas (uma por
  tabela verificada).
- §3.2 Encoding/delimitador: confirmados como `ISO-8859-1` e `;` em
  todos os 3 datasets.
- §3.3 Inspeção dos dicionários: forma do META CVM (bloco com `Campo:`
  / `Descrição:` / `Domínio:` / `Tipo Dados:` / `Tamanho:` /
  `Precisão:` / `Scale:`); contagem de campos por tabela (CAD: 46;
  ITR/BPA: 14; FRE/administrador_membro_conselho_fiscal: 21);
  observação de que CVM não enumera codelists ricas no META.
- §3.4 Inspeção amostral dos CSVs: cabeçalho real, format de células
  para `CD_CVM`, `VERSAO`, dates, valores categóricos. Para BPA:
  cross-tab `ORDEM_EXERC × ESCALA_MOEDA` em 2024 mostrou
  apenas `(ÚLTIMO/PENÚLTIMO) × (MIL/UNIDADE)` — sem `MILHÃO`/`BILHÃO`
  empíricos (verificado também em 2018).

**§4 Decisões pontuais** — Cada subseção curta (4-8 linhas). Para cada
uma: o achado empírico que motivou, a alternativa rejeitada (1 linha),
a decisão final. Refletir o que está no naming doc atualizado.

**§5 Resolução de pendências §11** — Tabela compacta com 3 colunas:
`item` | `status pós-2.6` | `nota`. Mapear linha por linha os bullets
do §11 do naming doc. Use os labels `[RESOLVIDO 2.6]`, `[PARCIAL 2.6]`,
`[ADIÇÃO 2.6]`, `[ABERTO]` exatamente como aparecem no naming doc
atualizado.

**§6 Pendências para Rodada 3** — Lista organizada das pendências
remanescentes. Não duplicar o que está em §11 do naming doc;
sintetizar como **plano de ação** ordenado por dependência. Itens
mínimos que devem aparecer:

1. Gerar programaticamente os ~72 YAMLs restantes a partir do snapshot
   de dicionário CVM (todos os 3 datasets v0.1 + DFP).
2. Travar nome canônico-PT do arquivo `itr_cia_aberta_<ano>.csv`
   (cabeçalho ITR) e do equivalente DFP — única decisão de naming que
   ficou aberta após Rodada 2.6.
3. Definir formato do snapshot de dicionário CVM
   (`inst/extdata/cvm_dictionary_snapshot.csv` ou Parquet/RDS) e
   estrutura interna.
4. Definir formato do snapshot de codelists empíricas (chave composta
   `dataset` + `table` + `column`).
5. Implementar reader que respeita as regras do YAML refinado (incluindo
   conversão automática de date a partir do dicionário).
6. Workflow GitHub Action para atualização periódica do snapshot de
   dicionário/codelists e detecção de mudança não-anunciada de schema
   CVM (uso de `expected_field_count`).
7. Casos limítrofes de `VL_CONTA` em precisão decimal (`decimal(29,10)`
   vs `double` R) e defeitos de qualidade conhecidos da CVM (BEL,
   CEPs sem zero à esquerda).

**§7 Pergunta acionável** — Uma única pergunta de múltipla escolha ao
mantenedor: pode seguir para Rodada 3 (scaffolding + implementação),
fazer subsessão temática extra (e qual), ou revisar este documento
primeiro.

## Restrições

- **Não reabrir naming**. As 26 decisões da Rodada 2.5 e os 7
  refinamentos da Rodada 2.6 estão travados.
- **Não reescrever YAMLs**. Eles estão entregues e validados.
- **Não duplicar conteúdo do naming doc**. Sintetize, referencie,
  pontue. Documentos curtos > documentos extensos com redundância.
- **Não inventar verificação empírica adicional**. Tudo que entrou no
  naming doc atualizado já foi verificado. Não fazer novos
  `web_fetch`/`bash` exceto para conferência pontual se necessário.
- **Idioma do documento**: português brasileiro (documento de
  planejamento).
- **Idioma de identificadores citados**: como vêm do naming doc
  (mistura controlada PT/EN conforme régua §0 do naming).
- **Sem emojis**, sem fluff, sem reverência. Tom da custom instruction
  do projeto.
- **Sem placeholder do tipo `[TODO]` ou `[a definir]`**. Se algo está
  aberto, vai para §6 como tarefa nomeada da Rodada 3.

## Método

Esta sessão é **síntese**, não verificação. O trabalho empírico foi
feito. Sua tarefa é organizar e documentar.

Fluxo recomendado:

1. Ler o naming doc anexado (especialmente o changelog Rodada 2.6
   no cabeçalho, §3.0, §7.2, §7.2.1, §7.3 e todo §11).
2. Ler os três YAMLs anexados.
3. Confirmar entendimento com o mantenedor em uma frase curta.
4. Produzir o documento em uma única passagem.
5. Apresentar via `present_files` e abrir a §7 (pergunta acionável).

## Entrega esperada

- 1 arquivo markdown em `/mnt/user-data/outputs/cvmdata_rodada2-6_schemas.md`
- Apresentado com `present_files`.
- Mensagem de fechamento curta, com a pergunta de §7 acima.

FIM DO PROMPT — não adicione nada depois desta linha.
