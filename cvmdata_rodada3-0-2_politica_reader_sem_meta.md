# Rodada 3.0.2 — Política do reader para tabelas com dados publicados mas sem META

> **Data de fechamento**: 2026-05-19 **Versão do documento**: v01
> **Status**: travado (incremental — não reabre decisões anteriores)
> **Idioma**: português brasileiro **Documento predecessor direto**:
> `cvmdata_rodada3-0_decisoes_pre_implementacao.md` (§2.1 e §6 item 8)
> **Documentos canônicos afetados**:
> `cvmdata_rodada2-5_naming_unificado-v03.md` (§7.2, §11.3, §11.5)
> **Documento sucessor**: subsessão dedicada (análoga à 3.0.1) para
> aplicar as atualizações de §6 deste documento ao naming doc.

------------------------------------------------------------------------

## 1. Resumo executivo

1.  **Defeito de cobertura permanente, não regressão**. Verificação
    empírica nesta sessão (FRE 2010-2026, ITR e DFP 2024, CAD) demonstra
    que as 8 tabelas órfãs do FRE-2024 são **novas** — apareceram em
    2023 e continuam sem META oficial em 2025, 2026, **e** no META FRE
    atualizado em 2026-05-17 (apenas dois dias antes desta sessão).
    Hipótese alternativa “regressão” (META existia e foi removido) está
    descartada pela evidência.
2.  **Apenas FRE apresenta o defeito**. ITR, DFP e CAD têm cobertura
    perfeita CSV ↔︎ META no release 2024. O problema é estrutural à
    gestão de schema do FRE (formulário que sofreu reformas profundas em
    2023 com tabelas de D&I/ESG novas mantidas sem dicionário).
3.  **Caso simétrico (META sem CSV) também existe — mas com semântica
    diferente**. Há 22 META no zip atual sem CSV correspondente no
    release 2024. **20 são tabelas legadas** (existiam em releases
    2010-2023, foram removidas em 2024); o META permanece útil para
    leitura desses releases antigos. **2 são fantasmas absolutos**
    (`empregado_declaracao_genero`, `empregado_declaracao_raca`) — não
    constam em nenhum release histórico, são resíduos de renomeação
    pré-publicação. Tratamento simétrico é cabível e diferente.
4.  **Recomendação: Opção A modificada**, não a forma preliminar
    registrada no §6 item 8 do fechamento da Rodada 3.0. Diferenças
    principais: (i) a política depende do valor de `validate`, não é um
    override transversal; (ii) usa classe de condição própria
    (`cvmdata_warn_meta_unavailable` e correspondente `cvmdata_error`),
    não reaproveita `cvmdata_error_parse`; (iii) introduz no YAML um
    campo `meta_status` explícito (em vez de `cvm_dictionary_url: null`
    ambíguo); (iv) preserva o princípio reitor “fica como vem da CVM” —
    **não** preenche descrições inventadas no snapshot de dicionário.
5.  **Workflow ETL precisa de mecanismo adicional para detectar
    aparecimento de novo META**. O hash-tracking atual (§3.5 do
    fechamento da Rodada 3.0) só detecta mudança em arquivos existentes;
    não detecta criação de `meta_*.txt` novo. Esta sessão propõe
    extensão.

------------------------------------------------------------------------

## 2. Q1 — Escopo empírico

Verificação realizada em 2026-05-19, ambiente bash com `curl`, `unzip` e
`iconv`. Cache de ZIPs em `/home/claude/cvm_audit/`. Arquivos
verificados listados nas subseções.

### 2.1 Q1.1 — O mesmo padrão ocorre em outros anos do FRE?

URLs baixadas e inspecionadas:

    https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/FRE/DADOS/fre_cia_aberta_{ano}.zip
    para ano ∈ {2010, 2011, 2012, 2015, 2020, 2021, 2022, 2023, 2024, 2025, 2026}

Contagem de CSVs por ano (após remover prefixo `fre_cia_aberta_` e
sufixo `_<ano>.csv`, sem distinguir variantes):

| Ano      | CSVs   |
|----------|--------|
| 2010     | 44     |
| 2011     | 44     |
| 2012     | 44     |
| 2015     | 44     |
| 2020     | 45     |
| 2021     | 45     |
| 2022     | 45     |
| **2023** | **56** |
| 2024     | 36     |
| 2025     | 36     |
| 2026     | 35     |

Salto estrutural em 2023 (45 → 56 tabelas) e em 2024 (56 → 36).
Hipótese: 2023 introduziu tabelas novas (incluindo as 8 órfãs) e manteve
as antigas em transição; 2024 consolidou o novo schema descartando as
legadas.

**Verificação da hipótese — diff schema 2010 vs 2024**:

- **25 tabelas em 2010 que não estão em 2024** (legadas removidas):
  `ativo_imobilizado`, `ativo_intangivel`, `auditor_responsavel`,
  `capital_social_aumento`, `capital_social_aumento_classe_acao`,
  `capital_social_desdobramento`,
  `capital_social_desdobramento_classe_acao`, `capital_social_reducao`,
  `capital_social_reducao_classe_acao`, `direito_acao`,
  `distribuicao_dividendos`, `distribuicao_dividendos_classe_acao`,
  `endividamento`, `grupo_economico_reestruturacao`,
  `historico_emissor`, `informacao_financeira`, `obrigacao`,
  `participacao_sociedade_valorizacao_acao`, `plano_recompra`,
  `plano_recompra_classe_acao`, `politica_negociacao`,
  `politica_negociacao_cargo`,
  `valor_mobiliario_tesouraria_movimentacao`,
  `valor_mobiliario_tesouraria_ultimo_exercicio`,
  `volume_valor_mobiliario`.
- **17 tabelas em 2024 que não estavam em 2010** (novas):
  `acao_entregue`, `administrador_PCD`,
  `administrador_declaracao_genero`, `administrador_declaracao_raca`,
  `empregado_PCD`, `empregado_local_declaracao_genero`,
  `empregado_local_declaracao_raca`, `empregado_local_faixa_etaria`,
  `empregado_posicao_declaracao_genero`,
  `empregado_posicao_declaracao_raca`, `empregado_posicao_faixa_etaria`,
  `empregado_posicao_local`, `mercado_estrangeiro`, `remuneracao_acao`,
  `remuneracao_variavel`, `titular_valor_mobiliario`, `titulo_exterior`.

**Resposta Q1.1**: o padrão “CSV sem META” do FRE-2024 reflete uma
**lacuna específica entre o schema vigente pós-2023 e o META oficial
publicado**. Não é fenômeno generalizado — é defeito localizado em um
subconjunto de tabelas ESG/D&I novas.

### 2.2 Q1.2 — Caso simétrico (META sem CSV) ocorre?

Comparação simétrica META FRE atual (2026-05-17) ↔︎ CSV FRE-2024:

- **8 CSV sem META** (já catalogados na Rodada 3.0; confirmado).
- **22 META sem CSV** (lista completa em §2.5 abaixo).

Cobertura histórica das 22 META-órfãs nos releases 2010-2026:

| META-órfã                                      | Anos com CSV       |
|------------------------------------------------|--------------------|
| `ativo_imobilizado`                            | 2010-2023          |
| `ativo_intangivel`                             | 2010-2023          |
| `auditor_responsavel`                          | 2010-2023          |
| `capital_social_aumento`                       | 2010-2023          |
| `capital_social_aumento_classe_acao`           | 2010-2022          |
| `capital_social_desdobramento`                 | 2010-2023          |
| `capital_social_desdobramento_classe_acao`     | 2010-2022          |
| `capital_social_reducao`                       | 2010-2023          |
| `capital_social_reducao_classe_acao`           | 2010-2022          |
| `direito_acao`                                 | 2010-2023          |
| `empregado_declaracao_genero`                  | **nunca**          |
| `empregado_declaracao_raca`                    | **nunca**          |
| `grupo_economico_reestruturacao`               | 2010-2015 (apenas) |
| `historico_emissor`                            | 2010-2023          |
| `participacao_sociedade_valorizacao_acao`      | 2010-2023          |
| `plano_recompra`                               | 2010-2023          |
| `plano_recompra_classe_acao`                   | 2010-2023          |
| `politica_negociacao`                          | 2010-2023          |
| `politica_negociacao_cargo`                    | 2010-2023          |
| `valor_mobiliario_tesouraria_movimentacao`     | 2010-2023          |
| `valor_mobiliario_tesouraria_ultimo_exercicio` | 2010-2015 (apenas) |
| `volume_valor_mobiliario`                      | 2010-2023          |

**Achado central** para o caso simétrico:

- **20 das 22 META-órfãs são tabelas legadas** com CSVs em releases
  passados. O META é semanticamente **necessário** para leitura desses
  releases históricos. A CVM agiu corretamente em mantê-los.
- **2 são fantasmas absolutos** (`empregado_declaracao_genero` e
  `empregado_declaracao_raca`). Verificação empírica em todos os 11 anos
  amostrados não encontrou nenhum CSV com esses nomes. Provável
  explicação: foram nomes propostos para tabelas que, antes da
  publicação, foram refatorados em `empregado_local_declaracao_*` e
  `empregado_posicao_declaracao_*` — confirmado por menção na própria
  documentação CVM (página do conjunto `cia_aberta-doc-fre` no Portal:
  “`fre_cia_aberta_empregado_posicao_declaracao_genero` (anteriormente:
  `fre_cia_aberta_empregado_declaracao_genero`)”). O META antigo
  permanece no zip como resíduo de versionamento mal gerenciado.

**Resposta Q1.2**: o caso simétrico existe em FRE com 22 ocorrências,
mas tem semântica heterogênea: 20 são úteis (cobertura histórica), 2 são
fantasmas. Tratamento simétrico é cabível mas diferente — desenvolvido
em §5.

### 2.3 Q1.3 — ITR e DFP apresentam o mesmo defeito?

Arquivos baixados em 2026-05-19:

- `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/ITR/DADOS/itr_cia_aberta_2024.zip`
- `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/ITR/META/meta_itr_cia_aberta_txt.zip`
- `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/DFP/DADOS/dfp_cia_aberta_2024.zip`
- `https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/DFP/META/meta_dfp_cia_aberta_txt.zip`

**ITR**: 19 CSVs (1 cabeçalho + 8 demonstrações × 2 variantes con/ind +
`composicao_capital` + `parecer`); após normalização por variante, **11
tabelas únicas**. META: 11 entries (1 cabeçalho + 8 demonstrações sem
variante + `composicao_capital` + `parecer`). **Cobertura perfeita CSV ↔︎
META; sem órfãos em nenhuma direção.**

**DFP**: estrutura idêntica ao ITR — 19 CSVs, 11 normalizados, 11 META.
**Cobertura perfeita.**

**Resposta Q1.3**: ITR e DFP **não apresentam o defeito**. Confirma
empiricamente que a pendência DFP marcada como “a confirmar na Rodada 3”
no §11.4 do naming doc (último bullet) está **resolvida**: estrutura
DFP/META é análoga a ITR/META em todos os aspectos verificados.

### 2.4 Q1.4 — CAD apresenta o mesmo defeito?

Arquivos baixados em 2026-05-19:

- `https://dados.cvm.gov.br/dados/CIA_ABERTA/CAD/DADOS/cad_cia_aberta.csv`
- `https://dados.cvm.gov.br/dados/CIA_ABERTA/CAD/META/meta_cad_cia_aberta.txt`

Cabeçalho do CSV: 47 campos. Campos no META (contagem de “Campo: X”): 47
campos. Comparação por nome de campo — 0 diferenças (interseção = união
= 47).

**Resposta Q1.4**: CAD não apresenta o defeito. CAD é estruturalmente
mais simples (CSV único, META único, sem ZIPs), e a manutenção da CVM
parece estar perfeitamente sincronizada.

### 2.5 Q1.5 — As 8 tabelas órfãs tiveram META em algum release histórico?

**Metodologia**: o Portal CVM **não versiona** o META FRE por ano —
existe apenas um único `meta_fre_cia_aberta.zip` no diretório
`/dados/CIA_ABERTA/DOC/FRE/META/`. Tentativas de URLs
`meta_fre_cia_aberta_<ano>.zip` retornam HTTP 404. Listagem direta do
diretório (verificada via web search) confirma:

    https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/FRE/META/
      meta_fre_cia_aberta.zip   (único arquivo)

Não há cobertura histórica oficial. A verificação direta de “tinha META
antes?” via Portal não é possível. Wayback Machine está bloqueado pela
política de egress do ambiente sandbox.

**Verificação indireta** (mais forte que mera ausência de cobertura
histórica):

1.  As 8 tabelas órfãs **só aparecem nos releases 2023, 2024, 2025 e
    2026** (verificado em todos os 11 anos amostrados — vide §2.1). Não
    existiam em releases anteriores.
2.  O META FRE atual foi atualizado em **2026-05-17** (header HTTP
    `Last-Modified`), **apenas dois dias antes** desta sessão. A CVM
    está ativamente mantendo o arquivo.
3.  Apesar de 3 anos de existência operacional dos CSVs (2023, 2024,
    2025, 2026) e de atualização ativa do META, **as 8 tabelas órfãs
    continuam sem dicionário**.

**Resposta Q1.5**: a hipótese “regressão” (META existia e foi removido)
está **descartada**. A interpretação correta é **incompletude permanente
desde origem**: a CVM introduziu tabelas novas em 2023 e nunca publicou
o META correspondente, mesmo com 3 anos transcorridos e revisões ativas
do arquivo. O defeito tem caráter **estrutural e duradouro**, não
transitório.

Implicação para política do reader: não faz sentido tratar o caso como
“esperar a CVM corrigir em breve”. Política deve assumir convivência
permanente com o defeito, com mecanismo de detecção caso a CVM
**eventualmente** publique o META (não-trivial — vide §4.3).

### 2.6 Achado adicional não previsto no prompt — anomalia de nomenclatura no META FRE

Inspeção do `meta_fre_cia_aberta.zip` revelou uma entrada com nome fora
do padrão: `fre_cia_aberta_empregado_local_faixa_etaria.txt` (sem o
prefixo `meta_`). Inspeção do conteúdo confirma que é META de fato
(formato bloco com `Campo:`, `Descrição:`, `Domínio:`, `Tipo Dados:`,
etc.). Cobre a tabela `empregado_local_faixa_etaria`, que **existe nos
CSVs de 2023-2026** (não está entre as 8 órfãs).

**Implicação para o reader**: a lógica de resolução de URL de dicionário
(`cvm_dictionary_url: archive.zip#entry.txt`) **não pode assumir** que
entries dentro do `meta_fre_cia_aberta.zip` seguem sempre o padrão
`meta_fre_cia_aberta_<table>.txt`. A entrada anômala demonstra que
existe pelo menos um caso em que o nome no zip é
`fre_cia_aberta_<table>.txt` (sem o prefixo `meta_`).

Decisão **menor** (consequência direta desta sessão): nos YAMLs que
referenciam essa tabela, declarar `cvm_dictionary_url` com o nome exato
da entrada (`#fre_cia_aberta_empregado_local_faixa_etaria.txt`, sem
`meta_`); o reader copia literalmente o sufixo após `#` sem tentar
normalizar.

Esse achado **não está no escopo principal** desta sessão, mas é
registrado por ter sido detectado durante a verificação empírica e por
afetar a geração programática dos YAMLs da Rodada 3 plena.

------------------------------------------------------------------------

## 3. Q2 — Alternativas de design

### 3.1 Critérios de decisão

Cinco critérios listados no prompt + um adicional identificado durante a
redação (critério 6):

1.  **Coerência com princípio reitor “fica como vem da CVM, é decisão do
    pacote o que não vem”** (§0.1 do naming doc).
2.  **Coerência com semântica de `validate`** (§2.2 do naming doc) e
    `on_error` (§2.1).
3.  **Custo de manutenção contínua** (defeitos da CVM mudam release a
    release).
4.  **Risco de mascarar defeitos novos** (false negatives).
5.  **Experiência do usuário** em casos comuns vs casos limítrofes.
6.  **(adicional)** **Coerência com `validate = "strict"`** — a Opção A
    preliminar emite warning independentemente do valor de `validate`, o
    que pode violar o contrato declarado de `strict` (“divergência
    aborta com `cvmdata_error_parse`”). Critério separado porque o
    critério 2 é mais geral; este é específico ao caso `strict`.

### 3.2 Tabela comparativa

Convenção: `(+)` favorável; `(−)` desfavorável; `(±)`
neutro/condicional.

| Critério | A — Permissiva c/ warning | B — Permissiva s/ alarme | C — Exclusão v0.1 | D — META manual |
|----|----|----|----|----|
| 1\. Princípio reitor “fica como vem” | (+) Reflete fielmente o estado da CVM (META ausente é fato) | (+) Idem A | (+) Modo mais purista — pacote só toca o que tem META | **(−)** Viola: assume autoridade que o pacote não tem para inventar descrição CVM-like |
| 2\. Coerência com `validate`/`on_error` | (±) Coerente se o warning depende de `validate`; incoerente se transversal | (−) Sob `validate = "strict"`, expectativa do usuário (“tudo validado”) é violada silenciosamente | (+) Não se aplica — fluxo nunca chega a `validate` (erro precoce em `cvm_fetch`) | (+) Reader trata como tabela normal; `validate` opera sobre o META manual |
| 3\. Custo de manutenção contínua | (+) Baixo: política única, sem conteúdo manual | (+) Idem A | (+) Mínimo: pacote ignora as tabelas | **(−)** Alto: precisa atualizar META manual quando schema muda; arbitrar conflitos se CVM finalmente publicar META oficial |
| 4\. Risco de mascarar defeitos novos | (+) Warning sinaliza para usuário e mantenedor | **(−)** Defeito invisível: se CVM publicar META, pacote não detecta automaticamente | (+) Erro explícito força usuário a procurar; mantenedor está consciente | (±) META manual mascara: usuário e workflow de monitoramento perdem o sinal de “META oficial ausente” |
| 5\. UX casos comuns vs limítrofes | (+) Casos comuns inalterados; caso limítrofe leva warning único e informativo | (+) Casos comuns e limítrofes uniformes | **(−)** Casos limítrofes (`cvm_fetch("fre", "administrador_PCD")`) viram erro inesperado para usuário iniciante | (+) Casos limítrofes idênticos a comuns; UX melhor |
| 6\. Coerência com `validate = "strict"` | (+) **Se** decisão for “strict aborta com `cvmdata_error_meta_unavailable`”; (−) se preliminar (sempre warn) for adotada literalmente | (+) Nominalmente preservado (nada warns nem aborta) | (+) Strict desnecessário — `cvm_fetch` já rejeita antes | (+) Strict opera sobre META manual; resposta coerente com o que está declarado |

**Síntese**: nenhuma opção é Pareto-dominante. Mas D acumula objeções em
dois critérios estruturais (1 e 3); B acumula em dois critérios
operacionais (4 e 6); C acumula no critério 5. Opção A, **se qualificada
para depender de `validate`**, satisfaz todos os critérios sem violação
significativa.

### 3.3 Recomendação: Opção A modificada

**Decisão**: adotar Opção A, com três modificações sobre a forma
preliminar registrada em §6 item 8 do fechamento da Rodada 3.0.

**Modificação 1 — Política depende de `validate`, não é override
transversal**.

| `validate` | Tabela com META | Tabela sem META |
|----|----|----|
| `"strict"` | Valida; divergência aborta com `cvmdata_error_parse` | **Aborta** com `cvmdata_error_meta_unavailable` |
| `"warn"` | Valida; divergência gera warning | Não valida (não há contra o que); emite `cvmdata_warn_meta_unavailable` informativo; entrega tibble |
| `"skip"` | Pula validação | Pula validação **silenciosamente** (sem warning, já que usuário pediu skip) |

Justificativa: o contrato de `strict` (§2.2 do naming doc) é
“divergência aborta”. META ausente é um defeito de validação tão sério
quanto divergência — talvez mais (não há nem como começar a validar).
Strict deve abortar, com mensagem clara sobre a causa e sugestão de usar
`validate = "warn"` para forçar leitura.

**Modificação 2 — Classe de condição própria, não reaproveitar
`cvmdata_error_parse`**.

Hierarquia adicionada à §6.1 do naming doc:

    cvmdata_error
    ├── cvmdata_error_input
    ├── cvmdata_error_http
    ├── cvmdata_error_parse
    ├── cvmdata_error_meta_unavailable    ⟵ novo (modo strict)
    └── cvmdata_error_internal

    cvmdata_warn                            ⟵ novo (pai genérico de warnings)
    ├── cvmdata_warn_validation             ⟵ novo (modo warn com META presente mas divergente)
    └── cvmdata_warn_meta_unavailable       ⟵ novo (modo warn sem META)

Justificativa: META ausente **não é** parse error (não falhou parser). É
**ausência de informação para validar**. Reusar `cvmdata_error_parse`
confunde semanticamente — usuário com
`tryCatch(cvmdata_error_parse = ...)` capturaria os dois casos
heterogêneos. Classes separadas permitem captura específica.

A criação de `cvmdata_warn` como pai genérico de warnings (espelhando
`cvmdata_error`) é refinamento incremental ao §6.1 do naming doc. Sem
ela, a hierarquia de warnings ficaria órfã.

**Modificação 3 — Campo `meta_status` explícito no YAML, em vez de
`cvm_dictionary_url: null` ambíguo**.

Forma preliminar (Rodada 3.0):

``` yaml
cvm_dictionary_url: null
expected_field_count: 10
```

Problema: `null` é ambíguo. Pode significar “URL não definida ainda”
(estado transitório do YAML em desenvolvimento), “URL não aplicável”
(temporal_partitioning = none e o META é único), ou “META não existe”
(caso desta sessão). O reader precisa distinguir.

Forma proposta:

``` yaml
cvm_dictionary_url: null
meta_status: missing      # explícito: META oficial CVM não publicado
expected_field_count: 10
expected_field_names:
  - CNPJ_Companhia
  - Data_Referencia
  - Versao
  - ID_Documento
  - Nome_Companhia
  - Orgao_Administracao
  - Quantidade_PCD
  - Quantidade_Nao_PCD
  - Quantidade_Sem_Resposta
  - Nao_Aplicavel
```

Domínio fechado de `meta_status`:

| Valor | Significado |
|----|----|
| `available` (default; pode ser omitido) | META oficial CVM existe e está em `cvm_dictionary_url` |
| `missing` | META oficial CVM não publicado (caso desta sessão) |

`expected_field_names` é campo novo, adicionado especificamente para
tabelas com `meta_status: missing`: como não há META oficial para
validar nomes de campos, o reader compara nomes do CSV contra esta lista
(derivada de varredura empírica do release).

Para tabelas com `meta_status: available`, `expected_field_names` é
**opcional** (e tipicamente omitido — o reader extrai a lista do META
oficial). Defesa em profundidade equivalente a `expected_field_count`.

**Modificação 4 — Snapshot de dicionário: nada de descrição inventada**.

Em §3.3 do fechamento da Rodada 3.0, o snapshot tem 10 colunas, das
quais 7 vêm do dicionário CVM. Para as 8 tabelas órfãs:

- `dataset`, `table`, `column`: preenchidos normalmente (chaves).
- `campo`: preenchido com nome original CVM extraído do cabeçalho do CSV
  (ex.: `"Quantidade_PCD"`).
- `descricao`, `dominio`, `tipo_dados`, `tamanho`, `precisao`, `scale`:
  **todos `NA`** — preservando o princípio reitor “fica como vem da
  CVM”. O pacote não inventa o que a CVM não publicou.

Coluna adicional **opcional** no snapshot:

| Coluna | Tipo | Notas |
|----|----|----|
| `meta_status` | character | `"available"` (default) ou `"missing"`; ajuda usuários de [`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md) a entender por que `descricao` é NA |

Adicional consistente com a forma definida em §3.3 do fechamento da
Rodada 3.0 (snapshot tem 10 colunas; este adiciona uma 11ª opcional).

------------------------------------------------------------------------

## 4. Q3 — Consequências em cascata

### 4.1 Q3.1 — Estrutura do YAML por tabela

**Refinamentos a §7.2 do naming doc**:

- Adicionar campo `meta_status` com domínio `{available, missing}`
  (default `available`). Quando `missing`:
  - `cvm_dictionary_url` deve ser `null`.
  - `expected_field_count` é **obrigatório** (não é mais opcional).
  - `expected_field_names` é **obrigatório** (lista de strings com nomes
    empíricos das colunas do CSV).
- Adicionar campo `expected_field_names: list[str]` ao schema do YAML,
  com a regra acima.
- Atualizar a invariante “exatamente um de `cvm_archive_url_pattern` ou
  `cvm_file_url_pattern` é não-nulo” para incluir a nota: “essa
  invariante é independente de `meta_status` — o **dado** existe e
  precisa ser baixável; apenas o META é que pode faltar”.

Exemplo completo de YAML para tabela órfã (`administrador_PCD`):

``` yaml
dataset: fre
table: administrador_PCD
cvm_archive_url_pattern: "https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/FRE/DADOS/fre_cia_aberta_{year}.zip"
cvm_file_url_pattern: null
cvm_file_pattern: "fre_cia_aberta_administrador_PCD_{year}.csv"
cvm_dictionary_url: null
meta_status: missing
encoding: ISO-8859-1
delimiter: ";"
temporal_partitioning: yearly
first_year: 2023
expected_field_count: 10
expected_field_names:
  - CNPJ_Companhia
  - Data_Referencia
  - Versao
  - ID_Documento
  - Nome_Companhia
  - Orgao_Administracao
  - Quantidade_PCD
  - Quantidade_Nao_PCD
  - Quantidade_Sem_Resposta
  - Nao_Aplicavel
transformations: []
```

### 4.2 Q3.2 — Schema do `cvm_dictionary_snapshot.csv`

Refinamentos a §7.5 do naming doc e §3.3 do fechamento da Rodada 3.0:

- Adicionar coluna **opcional** `meta_status` ao schema do snapshot (11ª
  coluna).
- Quando `meta_status = "missing"`: `descricao`, `dominio`,
  `tipo_dados`, `tamanho`, `precisao`, `scale` ficam `NA`. `campo` é
  preenchido com nome original do cabeçalho do CSV.
- Função
  [`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md)
  retorna esses registros normalmente — o usuário vê `descricao = NA` e
  (se examinar o snapshot direto) vê `meta_status = "missing"`.

Decisão menor sobre exibição:
[`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md)
pode emitir uma mensagem informativa única (via
[`cli::cli_inform()`](https://cli.r-lib.org/reference/cli_abort.html),
sujeita a `cvmdata.verbosity`) quando a tabela consultada tem
`meta_status = "missing"`:

    i META oficial CVM not published for table {.val administrador_PCD};
      showing field names from CSV header. Descriptions unavailable.

Em inglês conforme convenção §6.2.

### 4.3 Q3.3 — Workflow ETL

**Problema identificado nesta sessão (não previsto na Rodada 3.0)**: o
hash-tracking definido em §3.5 do fechamento da Rodada 3.0
(`SHA-256 de cada meta_*.txt baixado`) compara hashes de arquivos
**existentes**. Não detecta **aparecimento de novo `meta_*.txt`** —
exatamente o evento que precisaria ser detectado se a CVM um dia
publicar o META para as tabelas órfãs.

Extensão proposta ao workflow:

1.  **Antes de hashear**, listar entries do `meta_fre_cia_aberta.zip`
    atual e comparar com a lista do run anterior (armazenada em
    `data-raw/dictionary_entry_inventory.json`, novo arquivo).
2.  Se a lista de entries mudou:
    - Novas entradas em relação ao run anterior → log destacado no PR
      (“New META entries detected: …; check if any orphan table now has
      META”).
    - Entradas removidas → log de remoção (precisa atenção: o META pode
      ter sido removido com remoção de tabela; mas pode também ser
      regressão acidental).
3.  Após confirmação manual no PR, se uma das 8 tabelas órfãs ganhou
    META:
    - Trocar `meta_status: missing` por `meta_status: available` no
      YAML.
    - Preencher `cvm_dictionary_url`.
    - Remover `expected_field_names` (passa a ser derivado do META).
    - Re-popular linhas correspondentes no
      `cvm_dictionary_snapshot.csv`.

Esse fluxo é **manual sob revisão humana via PR** — coerente com a
filosofia já travada na Rodada 3.0 (“defesa em profundidade contra
mudanças silenciosas no schema CVM”).

Localização do novo arquivo: `data-raw/dictionary_entry_inventory.json`
(arquivo JSON com lista plana de entries por release; rastreado por git
como o `dictionary_hashes.json` existente).

### 4.4 Q3.4 — Mensagens cli

Texto exato dos warnings e errors (em inglês, conforme §6.2):

**Para `validate = "strict"` chamando tabela com
`meta_status: missing`** — `cvmdata_error_meta_unavailable`:

    ✖ Cannot validate table {.val administrador_PCD}: official CVM dictionary not published.
    ℹ Use {.code validate = "warn"} to read without validation,
      or {.code validate = "skip"} to suppress this check entirely.

**Para `validate = "warn"` chamando tabela com `meta_status: missing`**
— `cvmdata_warn_meta_unavailable`:

    ! Reading table {.val administrador_PCD} without dictionary validation:
      official CVM META not published.
    ℹ Field names verified against {.code expected_field_names} in package schema
      ({.val 10} columns).

**Para `validate = "skip"`**: nenhuma mensagem (usuário pediu skip).

**Para `cvm_dictionary("fre", "administrador_PCD")`** (informativo,
emitido por
[`cli::cli_inform()`](https://cli.r-lib.org/reference/cli_abort.html) —
respeita `cvmdata.verbosity`):

    ℹ Dictionary for table {.val administrador_PCD}: official CVM META not published.
    ℹ Showing field names extracted from CSV header; descriptions unavailable.

Símbolos cli `x`, `!`, `i` seguindo convenção §6.2.

### 4.5 Q3.5 — Vinheta de defeitos conhecidos

Refinamentos ao item `[ADIÇÃO 2.6]` de §11.5 do naming doc:

Adicionar nova subseção dentro da vinheta planejada com título:

> **Tabelas FRE sem dicionário oficial CVM**

Conteúdo proposto (em PT, vinheta complementar `cvmdata-pt-BR.Rmd`):

> Oito tabelas do FRE são publicadas pela CVM sem dicionário oficial
> (META). São tabelas introduzidas na reforma do Formulário de
> Referência de 2023 (Resolução CVM nº 80/22, principalmente itens 7.1D
> e 10.1A do Anexo C — D&I no nível de administradores e empregados):
>
> - `administrador_PCD`
> - `empregado_PCD`
> - `empregado_local_declaracao_genero`
> - `empregado_local_declaracao_raca`
> - `empregado_posicao_declaracao_genero`
> - `empregado_posicao_declaracao_raca`
> - `empregado_posicao_faixa_etaria`
> - `empregado_posicao_local`
>
> Estado em \[data da release do pacote\]: a CVM atualiza o arquivo
> `meta_fre_cia_aberta.zip` ativamente (última atualização verificada em
> 2026-05-17), mas as 8 tabelas continuam sem META publicado desde sua
> introdução em 2023.
>
> O pacote `cvmdata` lê normalmente os dados dessas tabelas. Sob
> `validate = "warn"` (padrão equivalente quando não-strict), o reader
> emite um warning informativo a cada leitura. Sob
> `validate = "strict"`, o reader aborta com classe
> `cvmdata_error_meta_unavailable` — use `validate = "warn"` para forçar
> leitura, ou consulte o cabeçalho do CSV para confirmar estrutura.
>
> [`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md)
> para essas tabelas retorna nomes de campo extraídos do cabeçalho do
> CSV, mas com `descricao`, `tipo_dados` e demais metadados oficiais
> ausentes (NA). Não inventamos descrições ausentes — o pacote preserva
> o princípio “se vem da CVM, fica como na CVM; se não vem, não
> inventamos”.
>
> Caso a CVM venha a publicar o dicionário dessas tabelas em release
> futuro, o pacote detecta automaticamente no workflow ETL semanal e
> abre PR para revisão; até lá, o estado permanece como descrito.

Em paralelo à vinheta de defeitos conhecidos, adicionar entrada no
README.md (inglês) com versão curta apontando para a vinheta.

### 4.6 Q3.6 — Política de remoção de tabelas órfãs

Caso futuro: a CVM publica META para uma ou mais das 8 tabelas órfãs.

Pipeline de detecção e migração:

1.  **Detecção**: extensão do workflow ETL descrita em §4.3.
2.  **Migração automática (proposta do bot)**:
    - Bot abre PR com:
      - YAML alterado (troca `meta_status: missing` por `available`;
        preenche `cvm_dictionary_url`; remove `expected_field_names`).
      - Linhas regeneradas no `cvm_dictionary_snapshot.csv`.
      - Linha em `NEWS.md` registrando a mudança.
      - Atualização da vinheta de defeitos conhecidos (remove a tabela
        da lista).
3.  **Revisão humana obrigatória** — coerente com filosofia de defesa em
    profundidade.
4.  **Validação cruzada**: após merge, o reader sob
    `validate = "strict"` deixa de abortar para essa tabela; testes de
    regressão precisam refletir a mudança (esperar tibble entregue com
    sucesso, sem `cvmdata_error_meta_unavailable`).

Caso inverso (CVM remove META de uma tabela que tinha): o bot detecta e
abre PR com a migração reversa. Esse caso é mais sério — pode indicar
uma regressão da CVM que precisa de atenção do mantenedor.

------------------------------------------------------------------------

## 5. Q4 — Política simétrica (META sem CSV)

### 5.1 Caracterização do caso simétrico

22 META no zip atual sem CSV correspondente no release 2024. Subdividido
em §2.2:

**Subgrupo 5.1.A — 20 META de tabelas legadas (legítimo)**

Tabelas que existiram em releases 2010-2023 e foram removidas em 2024
(`ativo_imobilizado`, `direito_acao`, `politica_negociacao`, etc.). O
META permanece útil para leitura de **releases históricos**.

**Subgrupo 5.1.B — 2 META fantasmas (resíduo de versionamento)**

`empregado_declaracao_genero` e `empregado_declaracao_raca` — nunca
apareceram em nenhum CSV (verificado em 2010-2026). Foram nomes
abandonados na refatoração que produziu as variantes `_local_` e
`_posicao_`.

### 5.2 Política para subgrupo 5.1.A — tabelas legadas

**Decisão**: tabelas legadas que não estão no escopo da v0.1 **não
recebem YAML** no pacote. O escopo da v0.1 é o release vigente (com
expansão temporal a partir do `first_year` declarado por tabela ativa),
não a totalidade histórica de tabelas que já existiram no FRE.

Justificativa:

- Coerente com a régua do escopo v0.1 fixada na Rodada 1 (companhias
  abertas — datasets ativos).
- Implicação operacional: usuário que tente
  `cvm_fetch("fre", "ativo_imobilizado")` recebe `cvmdata_error_input`
  (“table not found in dataset”) — não erro de META.
- Caso de uso “leitura de release histórico” (ex.: pesquisa longitudinal
  2010-2023 do `ativo_imobilizado`) **pode** ser considerado em v0.2+.
  Decisão de incluir ou não depende de evidência empírica de demanda.

Não-decisão registrada explicitamente: este documento **não** decide
sobre incluir tabelas legadas no v0.2+. Apenas posiciona o caso fora de
v0.1.

### 5.3 Política para subgrupo 5.1.B — fantasmas absolutos

**Decisão**: `empregado_declaracao_genero` e `empregado_declaracao_raca`
não recebem YAML no pacote em nenhuma versão. Aparecem na lista de
defeitos conhecidos da vinheta com contexto:

> O `meta_fre_cia_aberta.zip` contém dois dicionários sem CSV
> correspondente em nenhum release histórico verificado:
> `empregado_declaracao_genero` e `empregado_declaracao_raca`. São
> resíduos da refatoração do FRE em 2023, em que tabelas planejadas com
> esses nomes foram subdivididas em variantes `_local_` e `_posicao_`
> antes da publicação efetiva. Sem dados correspondentes, são inúteis
> para qualquer caso de uso e o `cvmdata` os ignora.

Implicação operacional: o snapshot de dicionário **não tem entradas**
para essas duas tabelas (nem com `meta_status: missing`, nem com
`available`). Não existe tabela para o pacote — não existe coluna no
snapshot.

### 5.4 Detecção futura

Workflow ETL (com extensão descrita em §4.3) detecta também: - Se um CSV
correspondente a `empregado_declaracao_genero` ou
`empregado_declaracao_raca` aparecer em release futuro (improvável mas
registrado): bot abre PR para incluir as tabelas conforme política
normal (vide §4.3). - Se META correspondente a tabela legada ressurgir
no escopo v0.1 (CVM ressuscita `ativo_imobilizado` na DRE corrente, por
exemplo — cenário fantasioso, registrado por completude): bot abre PR
para inclusão.

------------------------------------------------------------------------

## 6. Atualizações requeridas em documentos canônicos

Lista de refinamentos a aplicar em sessão de edição dedicada (análoga à
Rodada 3.0.1, não executada nesta sessão).

### 6.1 Refinamentos a aplicar no naming doc (`cvmdata_rodada2-5_naming_unificado-v03.md`)

1.  **Cabeçalho** — adicionar nova entrada no bloco de refinamentos
    incrementais:

    > ### Refinamentos incrementais — Rodada 3.0.2 (2026-05-19)
    >
    > Subsessão temática que fechou política do reader para tabelas FRE
    > com dados publicados mas sem META. Documento de fechamento:
    > `cvmdata_rodada3-0-2_politica_reader_sem_meta.md`. Decisões
    > incrementais; não reabrem rodadas anteriores.
    >
    > - §6.1 (hierarquia de condições): introdução de
    >   `cvmdata_error_meta_unavailable` (sob `cvmdata_error`) e da
    >   subárvore `cvmdata_warn` com filhos `cvmdata_warn_validation` e
    >   `cvmdata_warn_meta_unavailable`. Vide §3.3 (modificação 2) do
    >   fechamento da 3.0.2.
    > - §7.2 (estrutura YAML): adicionado campo `meta_status` com
    >   domínio fechado `{available, missing}` (default `available`);
    >   adicionado campo `expected_field_names: list[str]` exigido
    >   quando `meta_status: missing`. Vide §3.3 (modificação 3) e §4.1
    >   do fechamento da 3.0.2.
    > - §7.5 (schema do
    >   [`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md)):
    >   adicionada coluna opcional `meta_status` (11ª coluna), com
    >   domínio `{available, missing}`. Vide §3.3 (modificação 4) e §4.2
    >   do fechamento da 3.0.2.
    > - §11.3, último bullet (8 tabelas FRE sem META): de `[ADIÇÃO 3.0]`
    >   (diretriz preliminar) → **`[RESOLVIDO 3.0.2]`** com política
    >   consolidada.
    > - §11.4 — DFP/META “a confirmar na Rodada 3” (último bullet, antes
    >   desta sessão): de `[PARCIAL 2.6]` → **`[RESOLVIDO 3.0.2]`**
    >   (DFP/META análogo a ITR/META; sem órfãos).
    > - §11.5 (defeitos conhecidos da CVM): adicionada subseção formal
    >   sobre tabelas sem META oficial. Vide §4.5 do fechamento da
    >   3.0.2.

2.  **§6.1 (hierarquia de classes de condição)** — substituir bloco
    atual por:

        cvmdata_error                          (pai genérico de erros)
        ├── cvmdata_error_input                (argumento inválido)
        ├── cvmdata_error_http                 (falha de rede/HTTP)
        ├── cvmdata_error_parse                (falha de parse / validação)
        ├── cvmdata_error_meta_unavailable     (META oficial não publicado;
        │                                      strict mode)
        └── cvmdata_error_internal             (qualquer outro)

        cvmdata_warn                           (pai genérico de warnings)
        ├── cvmdata_warn_validation            (divergência no warn mode)
        └── cvmdata_warn_meta_unavailable      (META oficial ausente,
                                               warn mode)

3.  **§2.2 (semântica de `validate`)** — adicionar coluna ou linha sobre
    tabelas com `meta_status: missing`:

    | Valor | Comportamento (tabela com META) | Comportamento (tabela sem META) |
    |----|----|----|
    | `"strict"` | Valida; divergência → `cvmdata_error_parse` | Aborta com `cvmdata_error_meta_unavailable` |
    | `"warn"` | Valida; divergência → `cvmdata_warn_validation` | Emite `cvmdata_warn_meta_unavailable` e entrega tibble |
    | `"skip"` | Pula validação | Pula validação (silencioso) |

4.  **§7.2 (estrutura YAML)** — incluir os campos novos no bloco YAML
    canônico e adicionar nota:

    ``` yaml
    meta_status: available  # ou: missing
    expected_field_count: <int>
    expected_field_names:   # opcional quando meta_status: available
      - <field 1>           # obrigatório quando meta_status: missing
      - <field 2>
    ```

    > **Nota — `meta_status`** \[Rodada 3.0.2\]: quando `available`
    > (default), o reader extrai os campos esperados do META declarado
    > em `cvm_dictionary_url`; `expected_field_names` é opcional. Quando
    > `missing`, `cvm_dictionary_url` deve ser `null`,
    > `expected_field_names` é obrigatório, e o reader usa essa lista
    > para validar o cabeçalho do CSV. Política completa em
    > `cvmdata_rodada3-0-2_politica_reader_sem_meta.md`.

5.  **§7.5 (schema do
    [`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md))**
    — adicionar 11ª linha à tabela:

    Coluna \| Tipo \| Origem CVM \|  
    … \| … \| … \|  
    `meta_status` \| character \| Não vem da CVM; gerado pelo pacote
    (“available” ou “missing”) \|

6.  **§11.1, segundo bullet** (tabelas FRE) — atualizar contagem: “22
    tabelas-fantasma do META” pode ser preservado, mas o texto abaixo
    dele deve receber pointer para §5 deste documento (que especifica
    como o pacote trata cada subgrupo).

7.  **§11.3, último bullet** — substituir `[ADIÇÃO 3.0]` por
    `[RESOLVIDO 3.0.2]` e remover diretriz preliminar; adicionar
    referência a este documento como autoridade.

8.  **§11.4, último bullet** (DFP/META “a confirmar na Rodada 3”) —
    marcar `[RESOLVIDO 3.0.2]` e adicionar: “verificação empírica
    2026-05-19 confirmou que `meta_dfp_cia_aberta_txt.zip` é
    estruturalmente idêntico a `meta_itr_cia_aberta_txt.zip` (mesmas 11
    entradas: 1 cabeçalho + 8 demonstrações + composicao_capital +
    parecer); sem órfãos CSV↔︎META”.

9.  **§11.5** — adicionar bullet `[ADIÇÃO 3.0.2]`:

    > **Tabelas FRE sem dicionário oficial CVM**. Oito tabelas
    > publicadas pela CVM desde 2023 sem META correspondente, mesmo após
    > 3 anos de atualização ativa do `meta_fre_cia_aberta.zip`. Política
    > completa do reader em
    > `cvmdata_rodada3-0-2_politica_reader_sem_meta.md`. Conteúdo da
    > vinheta de defeitos conhecidos especificado em §4.5 do mesmo
    > documento.

10. **§11.5** — adicionar bullet `[ADIÇÃO 3.0.2]` adicional:

    > **Anomalia de nomenclatura no META FRE**. O
    > `meta_fre_cia_aberta.zip` contém uma entrada com nome fora do
    > padrão: `fre_cia_aberta_empregado_local_faixa_etaria.txt` (sem o
    > prefixo `meta_`). Lógica de resolução de
    > `cvm_dictionary_url: archive.zip#entry.txt` deve aceitar
    > literalmente o sufixo após `#`, sem normalização. Vide §2.6 do
    > fechamento da Rodada 3.0.2.

### 6.2 Atualizações no fechamento da Rodada 3.0

Item 8 do §6 (lista de pendências e tarefas remanescentes) deve ser
marcado como **`[RESOLVIDO 3.0.2]`** com referência a este documento.

A diretriz preliminar do item 8 (linhas que descrevem
“`cvmdata_error_parse` rebaixado a
[`cli::cli_warn()`](https://cli.r-lib.org/reference/cli_abort.html) …”)
é **substituída integralmente** pela política refinada em §3.3 deste
documento (modificações 1-4). O fechamento da Rodada 3.0 fica como está
(não se edita um documento travado retroativamente); a referência
cruzada documenta o trajeto.

------------------------------------------------------------------------

## 7. Pendências e tarefas remanescentes para Rodada 3 plena

Atualização incremental da §6 do fechamento da Rodada 3.0. Itens desta
tabela referem-se à enumeração desse documento.

| Item original (§6 da 3.0) | Status pós-3.0.2 | Nota |
|----|----|----|
| 1\. Snapshot completo do dicionário CVM (~72 YAMLs restantes) | refinado | Schema dos YAMLs agora inclui campos `meta_status` e `expected_field_names` (§4.1). Geração programática deve gerar diferenciadamente para 8 tabelas órfãs |
| 2\. Travar nome canônico-PT da tabela de cabeçalho ITR/DFP | sem mudança | RESOLVIDO 3.0 |
| 3\. Formato do snapshot de dicionário CVM | refinado | Schema ganha coluna opcional `meta_status` (11ª; §4.2) |
| 4\. Formato do snapshot de codelists empíricas | sem mudança | RESOLVIDO 3.0 |
| 5\. Implementação do reader | refinado | Reader precisa implementar três caminhos de tratamento conforme `validate` × `meta_status` (§3.3 modificação 1, tabela em §4.1 do fechamento 3.0.2) |
| 6\. Workflow GitHub Action para atualização periódica | refinado | Agora inclui também rastreio de inventário de entries do zip de META (§4.3), além do hash existente. Novo arquivo `data-raw/dictionary_entry_inventory.json` |
| 7\. Validação empírica em casos limítrofes | sem mudança | Itens marcados `[ABERTO]` na §11.5 do naming doc |
| 8\. Política do reader para tabelas FRE com dados mas sem META | **RESOLVIDO 3.0.2** | Política completa neste documento |

Itens novos identificados nesta sessão:

9.  **\[NOVO 3.0.2\]** **Subsessão dedicada à atualização do naming
    doc**. Aplicação dos refinamentos listados em §6.1 deste documento
    ao `cvmdata_rodada2-5_naming_unificado-v03.md`, gerando versão v04.
    Análoga em método à Rodada 3.0.1. Sem novas decisões; pura edição
    editorial. Estimativa: 45-60 minutos.

10. **\[NOVO 3.0.2\]** **Reflexo no documento canônico da Rodada 2.6
    (`cvmdata_rodada2-6_schemas.md`)**. Os três YAMLs exemplares
    entregues naquela sessão (CAD/companhias, ITR/BPA, FRE/
    administrador_membro_conselho_fiscal) não têm `meta_status`
    declarado — quando aplicada a nova régua, todos devem receber
    `meta_status: available` (explícito ou implícito por default).
    Decidir nesta subsessão de edição: tornar explícito ou usar default.
    Recomendação: usar default (menos verboso), e tornar
    `meta_status: missing` o único valor obrigatório a aparecer no YAML.

11. **\[NOVO 3.0.2\]** **Anomalia de nomenclatura no META FRE** (§2.6).
    Não é pendência crítica — apenas requer que o reader aceite
    literalmente o sufixo após `#` em `cvm_dictionary_url`, sem
    normalização. Importante registrar para evitar regressão posterior
    em refactor.

Dependências atualizadas:

- Item 1 (geração YAMLs) agora depende também do schema novo de
  `meta_status` (§4.1) e da lista `expected_field_names` para as 8
  tabelas órfãs (já catalogada em §3.3 deste documento).
- Item 5 (reader) depende do schema novo de YAMLs (item 1), da
  hierarquia de condições refinada (§6.1 do naming doc atualizada no
  item novo 9), e da tabela de comportamento `validate × meta_status`
  (§4.1 deste documento).
- Item 6 (workflow) depende do novo arquivo
  `data-raw/dictionary_entry_inventory.json`.
- Item 9 destrava item 10.

------------------------------------------------------------------------

## 8. Pergunta acionável para o mantenedor

Próximo passo — escolher uma opção:

**(a)** Seguir para a **subsessão dedicada à atualização do naming doc**
(item 9 novo da §7 acima). Sessão curta de edição editorial para aplicar
§6.1 deste documento ao `cvmdata_rodada2-5_naming_unificado-v03.md`,
gerando v04 e tirando a inconsistência documental do caminho crítico
**antes** da Rodada 3 plena. Análoga à 3.0.1 em método.

**(b)** Seguir direto para a **Rodada 3 plena** (scaffolding +
implementação em Claude Code) com este documento como referência. A
edição do naming doc fica para algum momento da Rodada 3 — pode ser no
início ou em paralelo. As decisões consolidadas em §3.3 e §4 deste
documento são suficientes para destravar a geração dos YAMLs e a
implementação do reader sem esperar o naming doc atualizado, **mas**
gera risco de inconsistência documental durante a Rodada 3.

**(c)** Subsessão temática adicional **antes** da Rodada 3 plena. Temas
levantados durante esta sessão que poderiam merecer foco isolado: - (c1)
Política do pacote para **releases históricos do FRE** (tabelas legadas
no subgrupo 5.1.A) — decisão de incluir em v0.2+ ou nunca. Não bloqueia
v0.1, mas pode ser interessante pré-decidir para alinhar arquitetura. -
(c2) Decisão sobre `cvm_normalize_keys()` utilitária (§3.0 do naming doc
menciona deferimento para v0.2+; pode ser revisitado agora que o caso de
uso fica mais claro com a inclusão das 8 tabelas órfãs no v0.1). - (c3)
Outro tema que o mantenedor identifique.

Qual?
