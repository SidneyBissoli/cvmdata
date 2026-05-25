# Reference Form (FRE)

The **Formulário de Referência** (FRE) is the annual reference form
filed by every publicly-traded company in Brazil. It bundles governance,
executive compensation, capital structure, related-party transactions,
employment, and ESG/diversity disclosures into a single 35-table
dataset, plus the `submissao` header — 36 tables in total.

Two quirks set FRE apart from ITR/DFP and are worth surfacing up-front:

- FRE detail tables use a different header convention from CAD/ITR/DFP:
  `cnpj_companhia`, `data_referencia`, `nome_companhia` (no `cd_cvm`
  column in the detail rows).
  [`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
  smooths over this — CD_CVM filters resolve via the dataset’s
  `submissao` and the user-facing interface stays identical.
- Eight tables in FRE ship **without published META** (CVM never
  released the dictionary file). The package declares them with
  `meta_status: missing` and requires `validate = "warn"` or `"skip"` to
  read them.

``` r

library(cvmdata)
```

## Reference: 36 tables, by theme

| Theme | Tables |
|----|----|
| Header | `submissao` |
| Audit | `auditor`, `responsavel` |
| Capital structure | `capital_social`, `capital_social_classe_acao`, `capital_social_titulo_conversivel`, `distribuicao_capital`, `distribuicao_capital_classe_acao`, `acao_entregue`, `outro_valor_mobiliario`, `mercado_estrangeiro`, `titulo_exterior` |
| Ownership | `posicao_acionaria`, `posicao_acionaria_classe_acao`, `titular_valor_mobiliario`, `participacao_sociedade`, `transacao_parte_relacionada` |
| Board & committees | `administrador_membro_conselho_fiscal`, `membro_comite`, `relacao_familiar`, `relacao_subordinacao` |
| Diversity (board) | `administrador_declaracao_genero`, `administrador_declaracao_raca`, `administrador_PCD` |
| Compensation | `remuneracao_total_orgao`, `remuneracao_variavel`, `remuneracao_acao`, `remuneracao_maxima_minima_media` |
| Diversity (workforce) | `empregado_PCD`✱, `empregado_local_declaracao_genero`✱, `empregado_local_declaracao_raca`✱, `empregado_local_faixa_etaria`, `empregado_posicao_declaracao_genero`✱, `empregado_posicao_declaracao_raca`✱, `empregado_posicao_faixa_etaria`✱, `empregado_posicao_local`✱ |

✱ — `meta_status: missing`: dictionary not published by CVM; reader
requires `validate = "warn"` or `"skip"`.

Use `cvm_tables("fre")` for the full list and
`cvm_dictionary("fre", "<table>")` for per-column metadata. Tables
marked ✱ return rows with `NA` in every dictionary column except
`campo`/`campo_original` (which come from the YAML’s
`expected_field_names`) and carry an attribute
`meta_status = "missing"`.

## Workflow 1 — Audit and ESG/PCD disclosures for one issuer

Goal: pull the audit firm history and the PCD (*Pessoa com Deficiência*)
employment counts for **BCO BRASIL S.A.** (CD_CVM `1023`), reference
year 2024.

### The audit firm

``` r

auditor <- cvm_fetch(
  "fre", "auditor",
  companies = "1023",
  years     = 2024
)
#> ℹ Resolving CD_CVM 1023 via "fre"/submissao for 2024 (table "auditor" does not
#>   carry `cd_cvm`).
auditor
#> ℹ source: "mirror" | fetched_at: 2026-05-25 02:09:07.722672
#> ℹ dataset: "fre" | table: "auditor"
#> # A tibble: 2 × 19
#>   cnpj_companhia   data_referencia versao id_documento nome_companhia id_auditor
#>   <chr>            <date>          <chr>  <chr>        <chr>               <dbl>
#> 1 00.000.000/0001… 2024-12-31      14     147862       BCO BRASIL S.…     131376
#> 2 00.000.000/0001… 2024-12-31      14     147862       BCO BRASIL S.…     131377
#> # ℹ 13 more variables: auditor <chr>, cpf_auditor <chr>, cnpj_auditor <chr>,
#> #   codigo_cvm_auditor <chr>, tipo_origem_auditor <chr>,
#> #   data_inicio_contratacao <date>, data_fim_contratacao <date>,
#> #   data_inicio_prestacao_servico <date>, servico_contratado <chr>,
#> #   remuneracao_auditor <chr>, justificativa_substituicao <chr>,
#> #   razao_apresentada <chr>, year <int>
```

Notice the header columns: `cnpj_companhia`, `data_referencia`,
`nome_companhia` (no `cd_cvm`). The package looked up CNPJ for CD_CVM
`1023` through `fre/submissao` of the same year, then filtered on CNPJ.
`keep_latest_version` has already de-duplicated re-filings.

### PCD employment counts (table without published META)

`empregado_PCD` is one of the eight FRE tables that CVM never released a
dictionary for. With the default `validate = "strict"` the package
refuses to read it:

``` r

cvm_fetch("fre", "empregado_PCD",
          companies = "1023", years = 2024)
#> ℹ Resolving CD_CVM 1023 via "fre"/submissao for 2024 (table "empregado_PCD"
#>   does not carry `cd_cvm`).
#> ℹ source: "mirror" | fetched_at: 2026-05-25 02:09:08.065425
#> ℹ dataset: "fre" | table: "empregado_PCD"
#> # A tibble: 0 × 11
#> # ℹ 11 variables: cnpj_companhia <chr>, data_referencia <date>, versao <chr>,
#> #   id_documento <chr>, nome_companhia <chr>, codigo_posicao <dbl>,
#> #   posicao <chr>, quantidade_pcd <dbl>, quantidade_nao_pcd <dbl>,
#> #   quantidade_sem_resposta <dbl>, year <int>
```

The reader expects the user to opt in by relaxing validation. With
`validate = "warn"` the package emits `cvmdata_warn_meta_unavailable`
and returns the tibble; with `validate = "skip"` it runs silently:

``` r

pcd <- cvm_fetch(
  "fre", "empregado_PCD",
  companies = "1023",
  years     = 2024,
  validate  = "warn"
)
#> ℹ Resolving CD_CVM 1023 via "fre"/submissao for 2024 (table "empregado_PCD"
#>   does not carry `cd_cvm`).
pcd
#> ℹ source: "mirror" | fetched_at: 2026-05-25 02:09:08.237165
#> ℹ dataset: "fre" | table: "empregado_PCD"
#> # A tibble: 0 × 11
#> # ℹ 11 variables: cnpj_companhia <chr>, data_referencia <date>, versao <chr>,
#> #   id_documento <chr>, nome_companhia <chr>, codigo_posicao <dbl>,
#> #   posicao <chr>, quantidade_pcd <dbl>, quantidade_nao_pcd <dbl>,
#> #   quantidade_sem_resposta <dbl>, year <int>
```

`cvm_dictionary("fre", "empregado_PCD")` returns the column list (from
the YAML’s `expected_field_names`) with `NA` in every metadata column —
by design, because the package never invents content the CVM did not
publish.

## Workflow 2 — Shareholder positions (cap table)

Goal: extract the top shareholders of BCO BRASIL recorded in the 2024
FRE filing.

``` r

posicao <- cvm_fetch(
  "fre", "posicao_acionaria",
  companies = "1023",
  years     = 2024
)
#> ℹ Resolving CD_CVM 1023 via "fre"/submissao for 2024 (table "posicao_acionaria"
#>   does not carry `cd_cvm`).

# Columns covering shareholder identity and stake:
cols <- intersect(
  c("acionista", "cpf_cnpj_acionista",
    "percentual_total_acoes_circulacao",
    "percentual_acao_ordinaria_circulacao"),
  names(posicao)
)
posicao[, c("nome_companhia", "data_referencia", cols)]
#> ℹ source: "mirror" | fetched_at: 2026-05-25 02:09:08.700065
#> ℹ dataset: "fre" | table: "posicao_acionaria"
#> # A tibble: 5 × 6
#>   nome_companhia  data_referencia acionista                   cpf_cnpj_acionista
#>   <chr>           <date>          <chr>                       <chr>             
#> 1 BCO BRASIL S.A. 2024-12-31      Ministério da Economia / S… 00.394.460/0001-41
#> 2 BCO BRASIL S.A. 2024-12-31      Ações Tesouraria            NA                
#> 3 BCO BRASIL S.A. 2024-12-31      Outros                      NA                
#> 4 BCO BRASIL S.A. 2024-12-31      Ações Tesouraria            NA                
#> 5 BCO BRASIL S.A. 2024-12-31      Outros                      NA                
#> # ℹ 2 more variables: percentual_total_acoes_circulacao <dbl>,
#> #   percentual_acao_ordinaria_circulacao <dbl>
```

The same approach works for `posicao_acionaria_classe_acao` (one row per
share class held), `capital_social` (issued and paid-in capital totals),
and `distribuicao_capital` (treasury and free-float breakdown).

## A note on the workforce-diversity bundle

The eight workforce-diversity tables (PCD, race, gender, age, location,
by position and by site) share both the header convention
(`cnpj_companhia` / `data_referencia` / `nome_companhia`) and — in seven
of them — the absence of published META. They are intentionally kept in
the package: research on diversity outcomes in publicly-traded firms is
a heavy use case, and the snapshot a user gets here is the same one a
CVM auditor sees. `validate = "warn"` plus the `expected_field_names`
declared in each YAML guard against silent schema drift.

## Where to read next

- **cvm-fetch** — `companies` / `years` / `validate` semantics in full.
- **itr-dfp** — financial statements; same package, different table
  semantics.
- **cvm-defects** — why eight FRE tables lack META, plus the broader
  list of CVM publication quirks the package handles.
