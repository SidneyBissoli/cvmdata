# Range of years available for a yearly-partitioned dataset

Discovers the years currently published for the dataset by reading the
CVM open-data directory listing. Returns an integer vector (sorted, no
gaps assumed). Caches the result for the duration of the R session to
avoid repeated HTTP calls.

## Usage

``` r
cvm_dataset_years(dataset, schema = NULL)
```

## Arguments

- dataset:

  Short dataset id.

- schema:

  Optional already-loaded schema (used internally by
  [`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)
  to avoid double-load). Users typically omit.

## Value

An integer vector of available years, or `NA_integer_`.

## Details

Returns `NA_integer_` for datasets whose tables are not
yearly-partitioned (e.g. `cad`).

## See also

Other discovery:
[`cvm_codelist()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_codelist.md),
[`cvm_datasets()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_datasets.md),
[`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md),
[`cvm_tables()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_tables.md)

## Examples

``` r
if (FALSE) { # interactive()
cvm_dataset_years("dfp")
}
```
