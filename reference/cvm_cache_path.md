# Path to the cvmdata cache directory

Returns the directory where downloaded CSV/ZIP artifacts are cached. The
default is the user-level cache slot from
[`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html), which can
be overridden by setting the option `cvmdata.cache_dir` (see
[`cvm_cache_set_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_set_path.md)).

## Usage

``` r
cvm_cache_path()
```

## Value

A character scalar with the absolute path.

## Details

Cached artifacts are revalidated against the CVM portal (HEAD with
ETag/Last-Modified) only after the freshness window expires. The window
is controlled by the option `cvmdata.cache_ttl_seconds` (default
`2592000`, i.e. 30 days); set it to `0` to revalidate on every call, or
to `Inf` to skip revalidation entirely until
[`cvm_cache_clear()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_clear.md)
is called.

Read-only: this function does not create the directory.

## See also

[`cvm_cache_set_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_set_path.md),
[`cvm_cache_info()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_info.md),
[`cvm_cache_clear()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_clear.md)

Other cache:
[`cvm_cache_clear()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_clear.md),
[`cvm_cache_info()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_info.md),
[`cvm_cache_set_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_set_path.md)

## Examples

``` r
cvm_cache_path()
#> [1] "/home/runner/.cache/R/cvmdata"
```
