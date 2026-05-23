# Set the active cvmdata source backend

Configures the option `cvmdata.source`, which becomes the default for
subsequent
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
calls that do not pass `source` explicitly. The argument passed to
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
always wins over the option.

## Usage

``` r
cvm_source_set(source)
```

## Arguments

- source:

  One of `"cvm"` (CVM Open Data Portal) or `"mirror"` (parquet via
  DuckDB; available from Phase F).

## Value

The chosen source, invisibly.

## See also

[`cvm_source_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_get.md)

Other source:
[`cvm_source_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_get.md)

## Examples

``` r
if (FALSE) { # interactive()
cvm_source_set("cvm")
}
```
