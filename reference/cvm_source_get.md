# Get the active cvmdata source backend

Reads the option `cvmdata.source`, falling back to `"cvm"` (the direct
CVM Open Data Portal backend) when the option is unset.

## Usage

``` r
cvm_source_get()
```

## Value

A character scalar: `"cvm"` or `"mirror"`.

## Details

The built-in default is `"cvm"` in the v0.1 series; it transitions to
`"mirror"` in the release that ships the GitHub Releases parquet mirror
(Phase F of the roadmap). Persist a specific value with
[`cvm_source_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_set.md)
to make scripts robust against that flip.

## See also

[`cvm_source_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_set.md)

Other source:
[`cvm_source_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_set.md)

## Examples

``` r
cvm_source_get()
#> [1] "cvm"
```
