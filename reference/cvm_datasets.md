# List datasets covered by the package

Returns the dataset identifiers (e.g. `"cad"`, `"dfp"`) currently
covered. Discovered from the schemas installed under
`inst/extdata/schemas/<group>/<dataset>/`.

## Usage

``` r
cvm_datasets()
```

## Value

A character vector of dataset ids, sorted alphabetically.

## See also

Other discovery:
[`cvm_codelist()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_codelist.md),
[`cvm_dataset_years()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dataset_years.md),
[`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md),
[`cvm_tables()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_tables.md)

## Examples

``` r
cvm_datasets()
#> [1] "cad" "dfp" "fre" "itr"
```
