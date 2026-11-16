# Which arguments of `cvm_fetch()` a table takes

[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
serves every table with one signature, but not every argument applies to
every table: `basis` is required for the statements published both
individual and consolidated and refused everywhere else, `as_of` only
applies to a registry, `year` not to a single snapshot.
`cvm_arguments()` says, for one table, which of these arguments are
required, which are optional and which are not allowed, with the values
each one takes.

## Usage

``` r
cvm_arguments(dataset, table, group = NULL)
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

A tibble with one row per argument of
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
that selects rows (`dataset` and `table` are always required and not
listed):

- `argument`: the argument name.

- `status`: `"required"`, `"optional"` or `"not allowed"`.

- `values`: the values it takes for this table, or `NA` when it is not
  allowed. For `year`, the years the table is published as the package
  knows them; the latest year is found when reading.

## Details

The answer is read from the same table schemas that
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
checks its arguments against, so the two never disagree: an argument
marked `"not allowed"` aborts
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
with `cvmdata_error_input`, and a `"required"` one left out does too.
The function reads only the installed schemas and needs no internet.

## See also

[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md),
section "Arguments by table", for the same rules across every table.

Other discovery:
[`cvm_codelist()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_codelist.md),
[`cvm_dataset_years()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dataset_years.md),
[`cvm_datasets()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_datasets.md),
[`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md),
[`cvm_groups()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_groups.md),
[`cvm_tables()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_tables.md)

## Examples

``` r
# A statement: `basis` is required
cvm_arguments("dfp", "bpa")
#> # A tibble: 10 × 3
#>    argument status      values                                                  
#>    <chr>    <chr>       <chr>                                                   
#>  1 cnpj     optional    "CNPJ, with or without punctuation"                     
#>  2 ticker   optional    "B3 ticker, e.g. \"PETR4\""                             
#>  3 year     optional    "2010 onwards; NULL = latest year"                      
#>  4 from     optional    "full date (\"YYYY-MM-DD\"); `from` and `to` together, …
#>  5 to       optional    "full date (\"YYYY-MM-DD\"); `from` and `to` together, …
#>  6 as_of    not allowed  NA                                                     
#>  7 basis    required    "\"ind\" = parent company only; \"con\" = consolidated …
#>  8 reading  optional    "\"original\" = as first published; \"restated\" = as s…
#>  9 source   optional    "\"mirror\", \"cvm\"; NULL = session default"           
#> 10 on_error optional    "\"abort\", \"warn\""                                   

# The registry: no `year`, but `as_of`
cvm_arguments("cad", "companhias")
#> # A tibble: 10 × 3
#>    argument status      values                                       
#>    <chr>    <chr>       <chr>                                        
#>  1 cnpj     optional    "CNPJ, with or without punctuation"          
#>  2 ticker   optional    "B3 ticker, e.g. \"PETR4\""                  
#>  3 year     not allowed  NA                                          
#>  4 from     not allowed  NA                                          
#>  5 to       not allowed  NA                                          
#>  6 as_of    optional    "full date (\"YYYY-MM-DD\")"                 
#>  7 basis    not allowed  NA                                          
#>  8 reading  not allowed  NA                                          
#>  9 source   optional    "\"mirror\", \"cvm\"; NULL = session default"
#> 10 on_error optional    "\"abort\", \"warn\""                        

# Only the required ones
args <- cvm_arguments("dfp", "dre")
args[args$status == "required", ]
#> # A tibble: 1 × 3
#>   argument status   values                                                      
#>   <chr>    <chr>    <chr>                                                       
#> 1 basis    required "\"ind\" = parent company only; \"con\" = consolidated grou…
```
