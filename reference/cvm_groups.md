# List the CVM CKAN groups

Returns the 18 thematic groups published by the CVM Open Data Portal
(`<https://dados.cvm.gov.br/group/>`), each with the number of datasets
the portal exposes for it and the canonical `cvmdata` fetcher contract
that covers it.

## Usage

``` r
cvm_groups()
```

## Value

A tibble with 18 rows, sorted alphabetically by `group`. Columns:

- `group` (character) – the CKAN slug (e.g. `"companhias"`,
  `"fundos-de-investimento"`).

- `n_datasets` (integer) – count of datasets the CVM portal publishes
  under this group.

- `contract` (character) – one of `"issuer"`, `"fund"`, `"agent"`,
  `"offering"`, `"event"`. Identifies the `cvmdata` fetcher that covers
  (or will cover) the group.

## Details

v0.1.0.9000 implements only the `companhias` group (via
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md));
the remaining 17 rows document the planned v0.2-v0.8 coverage so users
can navigate the universe of CVM data before the corresponding fetchers
ship. Calls to the four non-`issuer` fetchers in v0.1.0.9000 abort with
`cvmdata_error_input_group`; see
[`fund_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/fund_fetch.md),
[`agent_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/agent_fetch.md),
[`offering_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/offering_fetch.md)
and
[`event_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/event_fetch.md).

The `n_datasets` column reports the totals published by CVM, not the
count currently implemented in the package. The mapping between groups
and contracts is fixed for the lifetime of v0.1.x; see
`data-raw/decisions/cvmdata_arquitetura_grupos_decisao_v2.md` for the
rationale.

## See also

[`cvm_datasets()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_datasets.md),
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)

Other discovery:
[`cvm_codelist()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_codelist.md),
[`cvm_dataset_years()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dataset_years.md),
[`cvm_datasets()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_datasets.md),
[`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md),
[`cvm_tables()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_tables.md)

## Examples

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

# All groups served by issuer_fetch()
g <- cvm_groups()
g[g$contract == "issuer", ]
#> # A tibble: 3 × 3
#>   group              n_datasets contract
#>   <chr>                   <int> <chr>   
#> 1 companhias                 12 issuer  
#> 2 emissores-de-cepac          1 issuer  
#> 3 securitizadoras             4 issuer  
```
