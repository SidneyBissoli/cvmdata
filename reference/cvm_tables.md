# List the tables published in a dataset

List the tables published in a dataset

## Usage

``` r
cvm_tables(dataset, group = NULL)
```

## Arguments

- dataset:

  Short dataset id (e.g. `"dfp"`).

- group:

  Optional CKAN group slug (e.g. `"companhias"`). When `NULL` (default),
  the function resolves the group by uniqueness across the installed
  schema tree; when a dataset slug occurs in more than one group (a
  v0.4+ possibility), omitting `group` aborts with
  `cvmdata_error_input_ambiguous`.

## Value

A character vector of table names, sorted alphabetically.

## See also

Other discovery:
[`cvm_codelist()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_codelist.md),
[`cvm_dataset_years()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dataset_years.md),
[`cvm_datasets()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_datasets.md),
[`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md),
[`cvm_groups()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_groups.md)

## Examples

``` r
cvm_tables("dfp")
#>  [1] "bpa"                "bpp"                "composicao_capital"
#>  [4] "dfc_md"             "dfc_mi"             "dmpl"              
#>  [7] "dra"                "dre"                "dva"               
#> [10] "parecer"            "submissao"         
cvm_tables("dfp", group = "companhias")
#>  [1] "bpa"                "bpp"                "composicao_capital"
#>  [4] "dfc_md"             "dfc_mi"             "dmpl"              
#>  [7] "dra"                "dre"                "dva"               
#> [10] "parecer"            "submissao"         
```
