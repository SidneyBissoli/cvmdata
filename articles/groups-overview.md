# Groups overview: the 18 CKAN groups and the single fetcher

The CVM publishes its open data in **18 thematic groups** on the CKAN
portal at `<https://dados.cvm.gov.br/group/>`. `cvmdata` serves every
group through **one function**,
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md):
the dataset’s schema YAML tells the package which columns identify the
entity (issuer CNPJ today; fund CNPJ, registered-agent id, offering
number or event id as those groups arrive) and how the data is
partitioned in time, so the same arguments work across groups. The
decision for the single function is in
`data-raw/decisions/cvmdata_v0-3_funcao_unica_decisao.md`; the group
taxonomy and its contracts come from
`data-raw/decisions/cvmdata_arquitetura_grupos_decisao_v2.md` §1.1 (the
rest of that document is historical); this article is the navigation
map.

Today only the `companhias` group is implemented. The others are
scheduled on the roadmap (funds from v0.4, agents and public offerings
in v0.7, regulatory events in v0.8) and will extend
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
through their own schemas, not through new fetchers.

\
[`library`](https://rdrr.io/r/base/library.html)`(`[`cvmdata`](https://github.com/SidneyBissoli/cvmdata)`)`

## The 18 groups

\
[`cvm_groups`](https://sidneybissoli.github.io/cvmdata/reference/cvm_groups.md)`(``)`\
`#> ``# A tibble: 18 × 3`\
`#>    group                               n_datasets contract`\
`#>    ``<chr>``                                    ``<int>`` ``<chr>``   `\
`#> `` 1`` administradores                              2 agent   `\
`#> `` 2`` agentes-autonomos                            1 agent   `\
`#> `` 3`` agentes-fiduciarios                          1 agent   `\
`#> `` 4`` atividade-sancionadora                       1 event   `\
`#> `` 5`` atos-declaratorios                           1 event   `\
`#> `` 6`` auditores                                    1 agent   `\
`#> `` 7`` companhias                                  12 issuer  `\
`#> `` 8`` consultores-de-valores-mobiliarios           1 agent   `\
`#> `` 9`` coordenadores-de-ofertas                     1 agent   `\
`#> ``10`` emissores-de-cepac                           1 issuer  `\
`#> ``11`` fundos-de-investimento                      22 fund    `\
`#> ``12`` fundos-de-investimento-imobiliarios          4 fund    `\
`#> ``13`` fundos-estruturados                         10 fund    `\
`#> ``14`` investidores-nao-residentes                  1 agent   `\
`#> ``15`` ofertas-publicas                             2 offering`\
`#> ``16`` participantes-intermediarios                 1 agent   `\
`#> ``17`` plataformas-de-crowdfunding                  1 offering`\
`#> ``18`` securitizadoras                              4 issuer`

The `n_datasets` column counts datasets published by CVM, not the count
currently implemented in the package. The `contract` column is a
planning map: it names the kind of entity each group is keyed on
(`issuer`, `fund`, `agent`, `offering`, `event`), which is what decides
how
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
will identify rows once the group ships.

\
`g`` ``<-`` `[`cvm_groups`](https://sidneybissoli.github.io/cvmdata/reference/cvm_groups.md)`(``)`\
[`split`](https://rdrr.io/r/base/split.html)`(``g``$``group``, ``g``$``contract``)`\
`#> $agent`\
`#> [1] "administradores"                    "agentes-autonomos"                 `\
`#> [3] "agentes-fiduciarios"                "auditores"                         `\
`#> [5] "consultores-de-valores-mobiliarios" "coordenadores-de-ofertas"          `\
`#> [7] "investidores-nao-residentes"        "participantes-intermediarios"      `\
`#> `\
`#> $event`\
`#> [1] "atividade-sancionadora" "atos-declaratorios"    `\
`#> `\
`#> $fund`\
`#> [1] "fundos-de-investimento"              "fundos-de-investimento-imobiliarios"`\
`#> [3] "fundos-estruturados"                `\
`#> `\
`#> $issuer`\
`#> [1] "companhias"         "emissores-de-cepac" "securitizadoras"   `\
`#> `\
`#> $offering`\
`#> [1] "ofertas-publicas"            "plataformas-de-crowdfunding"`

## Issuers — implemented

Covers **issuers** of securities: companies (`companhias`),
securitisation vehicles (`securitizadoras`), and CEPAC issuers
(`emissores-de-cepac`). v0.1 shipped the four core `companhias`
datasets: `cad`, `dfp`, `itr`, `fre`. v0.2 added `cgvn` (Brazilian
Corporate Governance Code informe), `vlmo` (securities traded and held
by insiders), `fca` (registration form, which also backs the B3 ticker
lookup) and `ipe` (manifest of periodic and eventual documents) — eight
`companhias` datasets in all.

The identity key is the issuer’s CNPJ, selected with `cnpj` or, through
the registration form, with a B3 `ticker`. The temporal axis is annual
(with quarterly via ITR), selected with `year` or a `from`/`to` window
on the reference date, and the `basis` argument selects
individual/consolidated variants for accounting tables.

\
`# Companies registry (no time partitioning, no basis)`\
`issuers`` ``<-`` `[`cvm_fetch`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)`(``"cad"``, ``"companhias"``)`\
\
`# DFP balance sheet, individual, one year, one issuer`\
`bb`` ``<-`` `[`cvm_fetch`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)`(`\
`  ``"dfp"``, ``"bpa"``,`\
`  cnpj ``=`` ``"00.000.000/0001-91"``,`\
`  year ``=`` ``2024``,`\
`  basis ``=`` ``"ind"`\
`)`

## Funds, agents, offerings, events — on the roadmap

- **Funds** (v0.4–v0.6): `fundos-de-investimento` (ICVM 555),
  `fundos-de-investimento-imobiliarios` (FII) and `fundos-estruturados`
  (FIP, FIDC, FAPI). Keyed on the fund’s CNPJ; monthly or quarterly
  depending on the dataset.
- **Registered agents** (v0.7): the eight agent-registry groups, from
  `administradores` to `investidores-nao-residentes`. Keys range from
  CNPJ (broker-dealers, audit firms) to dataset-specific registration
  numbers; the CVM publishes no CPF, so a filter for natural persons is
  still an open decision.
- **Public offerings** (v0.7): `ofertas-publicas` and
  `plataformas-de-crowdfunding` (Resolução CVM 88). Keyed on the
  offering number; a date window is the natural slice.
- **Regulatory events** (v0.8): `atividade-sancionadora` and
  `atos-declaratorios`. Keyed on the process or act id.

Each of these lands as schema YAMLs under the group’s slug; the
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
signature does not change.

## Discovery functions accept `group`

When the same `(dataset, table)` pair lives in more than one group (a
v0.4+ possibility once `fund` datasets enter), the discovery functions
resolve by uniqueness when `group` is omitted, and abort with
`cvmdata_error_input_ambiguous` when it cannot disambiguate. Pass
`group` explicitly to skip the lookup:

\
[`cvm_datasets`](https://sidneybissoli.github.io/cvmdata/reference/cvm_datasets.md)`(``group ``=`` ``"companhias"``)`\
`#> [1] "cad"  "cgvn" "dfp"  "fca"  "fre"  "ipe"  "itr"  "vlmo"`\
[`cvm_tables`](https://sidneybissoli.github.io/cvmdata/reference/cvm_tables.md)`(``"dfp"``, group ``=`` ``"companhias"``)`\
`#>  [1] "bpa"                "bpp"                "composicao_capital"`\
`#>  [4] "dfc_md"             "dfc_mi"             "dmpl"              `\
`#>  [7] "dra"                "dre"                "dva"               `\
`#> [10] "parecer"            "submissao"`

The `group` argument is optional on
[`cvm_datasets()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_datasets.md),
[`cvm_tables()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_tables.md),
[`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md),
[`cvm_codelist()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_codelist.md),
and
[`cvm_dataset_years()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dataset_years.md).
The returned `cvm_tbl` from
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
also carries `group` as a provenance attribute (`attr(x, "group")`), and
`print.cvm_tbl()` renders it in the header.
