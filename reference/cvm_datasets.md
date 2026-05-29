# List datasets covered by the package

Returns the dataset identifiers (e.g. `"cad"`, `"dfp"`) currently
covered. Discovered from the schemas installed under
`inst/extdata/schemas/<group>/<dataset>/`. When `group` is supplied,
restricts the result to datasets that live under that CKAN group;
otherwise returns every installed dataset across every group.

## Usage

``` r
cvm_datasets(group = NULL)
```

## Arguments

- group:

  Optional CKAN group slug (e.g. `"companhias"`). When `NULL` (default)
  returns datasets from every group. Unknown values abort with
  `cvmdata_error_input`.

## Value

A character vector of dataset ids, sorted alphabetically.

## See also

Other discovery:
[`cvm_codelist()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_codelist.md),
[`cvm_dataset_years()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dataset_years.md),
[`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md),
[`cvm_groups()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_groups.md),
[`cvm_tables()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_tables.md)

## Examples

``` r
cvm_datasets()
#> [1] "cad"  "cgvn" "dfp"  "fre"  "itr"  "vlmo"
cvm_datasets(group = "companhias")
#> [1] "cad"  "cgvn" "dfp"  "fre"  "itr"  "vlmo"
```
