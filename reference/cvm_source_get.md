# Get the active cvmdata source backend

Reads the option `cvmdata.source`, falling back to `"mirror"` (parquet
via DuckDB) when the option is unset.

## Usage

``` r
cvm_source_get()
```

## Value

A character scalar: `"mirror"` or `"cvm"`.

## Details

From v0.1.0 onward the built-in default is `"mirror"`: it ships the full
historical series for CAD, DFP, ITR and FRE as parquet assets on GitHub
Releases, refreshed weekly. The `"cvm"` backend, which reads the CVM
Open Data Portal directly, remains fully supported and can be selected
per call or persisted with
[`cvm_source_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_set.md).

## See also

[`cvm_source_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_set.md)

Other source:
[`cvm_source_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_set.md)

## Examples

``` r
cvm_source_get()
#> [1] "mirror"
```
