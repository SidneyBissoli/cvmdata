# Look up the CVM-published dictionary for a table

Returns the dictionary metadata (field names, descriptions, domain, data
type, size/precision/scale) for a single `(dataset, table)` pair,
sourced from the snapshot embedded under
`inst/extdata/cvm_dictionary_snapshot.csv`. The snapshot is built
offline from the CVM META resources by
`data-raw/build-dictionary-snapshot.R`.

## Usage

``` r
cvm_dictionary(dataset, table, group = NULL)
```

## Arguments

- dataset:

  Short dataset id (e.g. `"dfp"`).

- table:

  Table name within the dataset (e.g. `"bpa"`).

- group:

  Optional CKAN group slug (e.g. `"companhias"`). When `NULL` (default)
  the function resolves by uniqueness across the embedded snapshot. From
  v0.4 onward, datasets may exist in more than one group; in that case
  omitting `group` aborts with `cvmdata_error_input_ambiguous`.

## Value

A tibble with one row per column of the table, columns `campo`
(snake-case name matching
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)
output), `campo_original` (field name as published by CVM in the META,
preserving the original casing), `descricao`, `dominio`, `tipo_dados`,
`tamanho`, `precisao`, `scale`.

## Details

Tables whose META is not published by CVM (`meta_status: missing` in the
schema YAML) return rows with `NA` in every metadata column except
`campo`/`campo_original` (sourced from the YAML's
`expected_field_names`). In that case the returned tibble carries an
attribute `meta_status = "missing"`.

## See also

[`cvm_tables()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_tables.md)

Other discovery:
[`cvm_codelist()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_codelist.md),
[`cvm_dataset_years()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dataset_years.md),
[`cvm_datasets()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_datasets.md),
[`cvm_tables()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_tables.md)

## Examples

``` r
cvm_dictionary("dfp", "bpa")
#> # A tibble: 14 × 8
#>    campo      campo_original descricao dominio tipo_dados tamanho precisao scale
#>    <chr>      <chr>          <chr>     <chr>   <chr>        <int>    <int> <int>
#>  1 cd_conta   CD_CONTA       Código d… Numéri… varchar         18       NA    NA
#>  2 cd_cvm     CD_CVM         Código C… Numéri… char             6       NA    NA
#>  3 cnpj_cia   CNPJ_CIA       CNPJ da … Alfanu… varchar         20       NA    NA
#>  4 denom_cia  DENOM_CIA      Nome emp… Alfanu… varchar        100       NA    NA
#>  5 ds_conta   DS_CONTA       Descriçã… Alfanu… varchar        100       NA    NA
#>  6 dt_fim_ex… DT_FIM_EXERC   Data fim… AAAA-M… date            10       NA    NA
#>  7 dt_refer   DT_REFER       Data de … AAAA-M… date            10       NA    NA
#>  8 escala_mo… ESCALA_MOEDA   Escala m… Alfanu… varchar        100       NA    NA
#>  9 grupo_dfp  GRUPO_DFP      Nome e n… Alfanu… varchar        206       NA    NA
#> 10 moeda      MOEDA          Moeda     Alfanu… varchar        100       NA    NA
#> 11 ordem_exe… ORDEM_EXERC    Ordem do… Alfanu… varchar          9       NA    NA
#> 12 st_conta_… ST_CONTA_FIXA  Indica s… S/N     varchar          1       NA    NA
#> 13 versao     VERSAO         Versão d… Numéri… smallint        NA        5     0
#> 14 vl_conta   VL_CONTA       Valor da… Numéri… decimal         NA       29    10
cvm_dictionary("fre", "empregado_PCD")
#> # A tibble: 10 × 8
#>    campo      campo_original descricao dominio tipo_dados tamanho precisao scale
#>    <chr>      <chr>          <chr>     <chr>   <chr>        <int>    <int> <int>
#>  1 cnpj_comp… CNPJ_Companhia NA        NA      NA              NA       NA    NA
#>  2 data_refe… Data_Referenc… NA        NA      NA              NA       NA    NA
#>  3 versao     Versao         NA        NA      NA              NA       NA    NA
#>  4 id_docume… ID_Documento   NA        NA      NA              NA       NA    NA
#>  5 nome_comp… Nome_Companhia NA        NA      NA              NA       NA    NA
#>  6 codigo_po… Codigo_Posicao NA        NA      NA              NA       NA    NA
#>  7 posicao    Posicao        NA        NA      NA              NA       NA    NA
#>  8 quantidad… Quantidade_PCD NA        NA      NA              NA       NA    NA
#>  9 quantidad… Quantidade_Na… NA        NA      NA              NA       NA    NA
#> 10 quantidad… Quantidade_Se… NA        NA      NA              NA       NA    NA
```
