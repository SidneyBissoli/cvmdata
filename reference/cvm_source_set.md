# Set the active cvmdata source backend

Configures the option `cvmdata.source`, which becomes the default for
subsequent
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)
calls that do not pass `source` explicitly. The argument passed to
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)
always wins over the option.

## Usage

``` r
cvm_source_set(source)
```

## Arguments

- source:

  One of `"mirror"` (parquet via DuckDB; default from v0.1.0) or `"cvm"`
  (CVM Open Data Portal).

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
