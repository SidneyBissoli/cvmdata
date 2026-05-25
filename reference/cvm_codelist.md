# Look up the codelist for a categorical column

Returns the set of categorical values observed for a single
`(dataset, table, column)` triple, sourced from the snapshot embedded
under `inst/extdata/cvm_codelists_snapshot.csv`. The snapshot is built
offline by `data-raw/build-codelists-snapshot.R` from the CVM open-data
CSVs.

## Usage

``` r
cvm_codelist(dataset, table, column)
```

## Arguments

- dataset:

  Short dataset id (e.g. `"cad"`).

- table:

  Table name within the dataset (e.g. `"companhias"`).

- column:

  Snake-case column name (e.g. `"sit"`).

## Value

A tibble with one row per categorical value, sorted alphabetically.
Column: `value` (character).

## Details

Inclusion criteria for the snapshot (see CLAUDE.md §9.2): columns whose
dictionary `dominio` enumerates values (e.g. `S/N`, `PF/PJ`), and
`varchar` columns with `tamanho < 200` and at most 50 distinct values
observed in the latest available year.

## See also

[`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md)

Other discovery:
[`cvm_dataset_years()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dataset_years.md),
[`cvm_datasets()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_datasets.md),
[`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md),
[`cvm_tables()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_tables.md)

## Examples

``` r
cvm_codelist("cad", "companhias", "sit")
#> # A tibble: 3 × 1
#>   value                    
#>   <chr>                    
#> 1 ATIVO                    
#> 2 CANCELADA                
#> 3 SUSPENSO(A) - DECISÃO ADM
```
