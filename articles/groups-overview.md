# Groups overview: the 18 CKAN groups and 5 fetcher contracts

The CVM publishes its open data in **18 thematic groups** on the CKAN
portal at `<https://dados.cvm.gov.br/group/>`. `cvmdata` collapses those
18 groups into **5 data-contract fetchers** based on the kind of
identity key (issuer CNPJ, fund CNPJ, registered agent CPF/CNPJ,
public-offering number, regulatory event ID), the temporal granularity
(annual, quarterly, monthly, ad-hoc), and the typical use case. The full
rationale is in
`data-raw/decisions/cvmdata_arquitetura_grupos_decisao_v2.md`; this
article is the navigation map.

In v0.1.0.9000, only the `companhias` group is functionally implemented
(via
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md));
the four remaining fetchers are exported as skeletons that abort with
`cvmdata_error_input_group` when called, with a pointer back to the
roadmap. They are documented now so the upcoming rOpenSci submission
reviews the complete API surface ahead of incremental data
implementation.

``` r

library(cvmdata)
```

## The 18 groups

``` r

cvm_groups()
#> # A tibble: 18 × 3
#>    group                               n_datasets contract
#>    <chr>                                    <int> <chr>   
#>  1 administradores                              2 agent   
#>  2 agentes-autonomos                            1 agent   
#>  3 agentes-fiduciarios                          1 agent   
#>  4 atividade-sancionadora                       1 event   
#>  5 atos-declaratorios                           1 event   
#>  6 auditores                                    1 agent   
#>  7 companhias                                  12 issuer  
#>  8 consultores-de-valores-mobiliarios           1 agent   
#>  9 coordenadores-de-ofertas                     1 agent   
#> 10 emissores-de-cepac                           1 issuer  
#> 11 fundos-de-investimento                      22 fund    
#> 12 fundos-de-investimento-imobiliarios          4 fund    
#> 13 fundos-estruturados                         10 fund    
#> 14 investidores-nao-residentes                  1 agent   
#> 15 ofertas-publicas                             2 offering
#> 16 participantes-intermediarios                 1 agent   
#> 17 plataformas-de-crowdfunding                  1 offering
#> 18 securitizadoras                              4 issuer
```

The `n_datasets` column counts datasets published by CVM, not the count
currently implemented in the package. The `contract` column names the
fetcher that does (or will) cover the group.

``` r

g <- cvm_groups()
split(g$group, g$contract)
#> $agent
#> [1] "administradores"                    "agentes-autonomos"                 
#> [3] "agentes-fiduciarios"                "auditores"                         
#> [5] "consultores-de-valores-mobiliarios" "coordenadores-de-ofertas"          
#> [7] "investidores-nao-residentes"        "participantes-intermediarios"      
#> 
#> $event
#> [1] "atividade-sancionadora" "atos-declaratorios"    
#> 
#> $fund
#> [1] "fundos-de-investimento"              "fundos-de-investimento-imobiliarios"
#> [3] "fundos-estruturados"                
#> 
#> $issuer
#> [1] "companhias"         "emissores-de-cepac" "securitizadoras"   
#> 
#> $offering
#> [1] "ofertas-publicas"            "plataformas-de-crowdfunding"
```

## issuer_fetch() — fully implemented in v0.1

Covers **issuers** of securities: companies (`companhias`),
securitisation vehicles (`securitizadoras`), and CEPAC issuers
(`emissores-de-cepac`). v0.1 shipped the four core `companhias`
datasets: `cad`, `dfp`, `itr`, `fre`. v0.1.0.9000 added `cgvn`
(Brazilian Corporate Governance Code informe) and `vlmo` (securities
traded and held by insiders) toward v0.2; `fca` and `ipe` land in
subsequent v0.1.0.9000 sessions.

The identity key is CNPJ + denomination (plus `CD_CVM` for
companhias-style issuers). The temporal axis is annual (with quarterly
via ITR) and the `report_type` argument selects individual/consolidated
variants for accounting tables.

``` r

# Companies registry (no time partitioning, no report_type)
issuers <- issuer_fetch("cad", "companhias")

# DFP balance sheet, individual, latest year, one issuer
bb <- issuer_fetch(
  "dfp", "bpa",
  issuer = "BCO BRASIL",
  year = 2024,
  report_type = "ind"
)
```

[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)
is the only fetcher with a real implementation in v0.1.0.9000. The four
below export the same shape as skeletons.

## fund_fetch() — investment funds (v0.4–v0.6)

Covers the three fund groups: `fundos-de-investimento` (ICVM 555, 22
datasets), `fundos-de-investimento-imobiliarios` (FII, 4 datasets), and
`fundos-estruturados` (FIP, FIDC, FAPI, 10 datasets). The identity key
is the fund’s CNPJ; the temporal axis is monthly or quarterly depending
on the dataset. `date` is the singular for pointwise reference dates;
`date_range` does not apply here.

``` r

# Will abort in v0.1.0.9000 with cvmdata_error_input_group:
# fund_fetch("fi-cad", "registro", fund = "00.000.000/0001-91")
```

## agent_fetch() — registered agents (v0.7)

Covers the eight agent-registry groups: `administradores`,
`agentes-autonomos`, `agentes-fiduciarios`, `auditores`,
`consultores-de-valores-mobiliarios`, `coordenadores-de-ofertas`,
`participantes-intermediarios`, and `investidores-nao-residentes`.
Identity keys range from CPF (individual autonomous agents) through CNPJ
(broker-dealers, audit firms) to dataset-specific registration numbers.
`as_of` selects a snapshot date for cadastral views.

``` r

# Will abort in v0.1.0.9000 with cvmdata_error_input_group:
# agent_fetch("administradores", "registro", as_of = Sys.Date())
```

## offering_fetch() — public offerings (v0.7)

Covers `ofertas-publicas` and `plataformas-de-crowdfunding` (Resolução
CVM 88). The identity key is `numero_oferta`; `date_range` is the window
operator (offerings cluster around events, ranges are the natural
slice). Crowdfunding is treated as a public offering subtype because,
under CVM 88, it is structurally an offering dispensed from registration
and intermediated by a platform.

``` r

# Will abort in v0.1.0.9000 with cvmdata_error_input_group:
# offering_fetch(
#   "ofertas-publicas", "ofertas",
#   date_range = as.Date(c("2024-01-01", "2024-12-31"))
# )
```

## event_fetch() — regulatory events (v0.8)

Covers `atividade-sancionadora` (sanctioning proceedings) and
`atos-declaratorios` (declaratory acts from the CVM directorate).
Identity key is the process ID or act ID; `date_range` is the natural
slice for audit / monitoring use cases.

``` r

# Will abort in v0.1.0.9000 with cvmdata_error_input_group:
# event_fetch(
#   "atividade-sancionadora", "processos",
#   date_range = as.Date(c("2023-01-01", Sys.Date()))
# )
```

## Discovery functions accept `group`

When the same `(dataset, table)` pair lives in more than one group (a
v0.4+ possibility once `fund` datasets enter), the discovery functions
resolve by uniqueness when `group` is omitted, and abort with
`cvmdata_error_input_ambiguous` when it cannot disambiguate. Pass
`group` explicitly to skip the lookup:

``` r

cvm_datasets(group = "companhias")
#> [1] "cad"  "cgvn" "dfp"  "fre"  "itr"  "vlmo"
cvm_tables("dfp", group = "companhias")
#>  [1] "bpa"                "bpp"                "composicao_capital"
#>  [4] "dfc_md"             "dfc_mi"             "dmpl"              
#>  [7] "dra"                "dre"                "dva"               
#> [10] "parecer"            "submissao"
```

The `group` argument is optional on
[`cvm_datasets()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_datasets.md),
[`cvm_tables()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_tables.md),
[`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md),
[`cvm_codelist()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_codelist.md),
and
[`cvm_dataset_years()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dataset_years.md).
The returned `cvm_tbl` from any fetcher also carries `group` as a
provenance attribute (`attr(x, "group")`), and `print.cvm_tbl()` renders
it in the header.
