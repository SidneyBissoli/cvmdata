# cvmdata v0.3 — função única `cvm_fetch()` — decisão

> **Sessões**: 2026-10-16 (decisão de arquitetura) e 2026-10-19
> (assinatura, implementação, PR #11).
> **Status**: **decisões fechadas**. Este documento **prevalece** sobre
> `cvmdata_arquitetura_grupos_decisao_v2.md` (2026-05-25) para a
> arquitetura da API; o v2 fica como histórico e continua valendo nas
> seções que ele próprio marca (§1.1, §3.2, §4.3, §4.6).
> **Fontes**: `ROADMAP.md` seção "v0.3 — função única", `CLAUDE.md`
> §2.1 e §2.7, `NEWS.md` 0.2.0.9000. Em caso de divergência, o
> `NEWS.md` descreve o que o pacote faz; este documento, por que.
> **Idioma**: PT-BR; identificadores de código em EN (CLAUDE.md §1).

---

## 1. Decisão de arquitetura (Sidney, 2026-10-16)

**Uma função pública serve qualquer conjunto.** A arquitetura de maio
(5 fetchers por contrato de dado: `issuer_fetch()`, `fund_fetch()`,
`agent_fetch()`, `offering_fetch()`, `event_fetch()`) foi reaberta e
substituída. O que distingue um grupo CKAN do outro (coluna que
identifica a entidade; granularidade anual, mensal, diária ou
instantânea) passa a viver no YAML de cada conjunto, não em funções
distintas. Os grupos planejados para v0.4–v0.8 (fundos, agentes,
ofertas, eventos) estendem `cvm_fetch()` pelos seus schemas.

Consequências imediatas (entregues em 2026-10-19):

- Os 4 skeletons (`fund_fetch()`, `agent_fetch()`, `offering_fetch()`,
  `event_fetch()`) e a classe `cvmdata_error_input_group` saíram
  (`⚠️ breaking` no NEWS).
- `issuer_fetch()` segue exportada como wrapper **deprecado**
  (`lifecycle::deprecate_warn("0.3.0")`; `lifecycle` em Imports), com o
  comportamento antigo intacto, até ser removida.
- `cvm_groups()` mantém a coluna `contract` como **mapa de
  planejamento** (chave de identidade e eixo temporal de cada grupo),
  não como promessa de função.

Nota de nome: `cvm_fetch()` já existiu na v0.1.0 e foi renomeada para
`issuer_fetch()` na Sessão 06 (v2 §5.3); o nome volta com semântica
nova.

## 2. Assinatura (Sidney, 2026-10-19)

```r
cvm_fetch(dataset, table, cnpj, ticker, year, from, to, basis, ...)
```

| Decisão | Escolha | Recusado |
|---|---|---|
| Nome | `cvm_fetch()` | — |
| Filtro de entidade | dois argumentos, `cnpj` (só CNPJ, com ou sem pontuação) e `ticker` (código B3 → CNPJ via `fca/valor_mobiliario`, lido do mesmo `source`); os dois se somam | código CVM (ninguém o conhece; o FRE nem tem a coluna; recusado inclusive como cortesia a quem migra do GetDFPData2); busca textual por nome; `cpf` (a CVM não publica CPF; cadastros PF só trazem nome — filtro de PF fica para a v0.7) |
| Período | `year` para anos inteiros (como antes) **ou** `from`/`to` com datas completas; os dois juntos = erro; a data que vale é a de **referência** do documento, não a de entrega | datas incompletas em `from`/`to` ("complexo, portanto pior") |
| `report_type` | renomeado para **`basis`**; valores `"ind"`, `"con"` ou `c("ind", "con")` (empilha); **sem padrão**; em tabela com divisão, `basis` ausente = erro pedindo a escolha; em tabela sem divisão, `basis` informado = erro; a coluna `basis` vem **sempre** nas tabelas com divisão, nos dois backends | `"con"` como padrão (35% das cias DFP 2023 só têm "ind" e sumiriam); os nomes `report_type` e `type_format` (comprimento), `scope`, `report`, `type`, `view` |

## 3. Decisões de rotina na implementação (2026-10-19, sem reabrir)

- `from`/`to` exigem os dois juntos.
- `cad` (tabela instantânea) com `year` ou `from`/`to` = erro.
- Busca textual por nome e CD_CVM não entraram: a assinatura fechada
  não tem argumento para elas; ficam só em `issuer_fetch()` deprecada.
  O cadastro `cvm_fetch("cad", "companhias")` é o lugar de resolver
  nome ou código → CNPJ.
- Ticker que mapeia para mais de um CNPJ segue o resolver atual
  (devolve todos).
- Implementação: `R/api-cvm-fetch.R` é uma casca de validação
  (`check_cnpj`, `check_ticker`, `check_period`, `check_basis`) sobre
  `issuer_fetch_internal()`, uma chamada por `basis`; filtro
  `from`/`to` pela data de referência depois da leitura. Testes em
  `tests/testthat/test-cvm-fetch.R`, com fixtures, sem rede.

## 4. O que fica do v2

| Seção do v2 | Status | Onde se apoia |
|---|---|---|
| §1.1 mapping grupo → contrato | válido como mapa de planejamento | `cvm_groups()` (`R/api-cvm-groups.R`) |
| §3.2 argumentos no singular | válido (`cnpj`, `ticker`, `year` aceitam vetor) | assinatura acima |
| §4.3 rename in-place do mirror | válido | `R/util-mirror-assets.R` |
| §4.6 atributo `group` no `cvm_tbl` | válido | `R/util-attrs.R` |
| §3.1, §3.3 (`date`/`date_range`), §3.9, §5 (Sessões 04–08) | superados / executados | este documento; `NEWS.md` |

## 5. Pendências abertas da v0.3

Vivem no `ROADMAP.md` (versões parte 1–3, deslistadas, alerta de
renome, resto de `companhias`); não duplicar status aqui.
