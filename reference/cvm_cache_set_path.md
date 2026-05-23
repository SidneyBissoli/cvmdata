# Set the cvmdata cache directory

Configures the option `cvmdata.cache_dir` so that subsequent downloads
land at `path`. The directory is created (recursively) if it does not
exist, and writeability is verified before the option is committed.

## Usage

``` r
cvm_cache_set_path(path)
```

## Arguments

- path:

  Character scalar with the desired cache directory.

## Value

The normalized path, invisibly.

## See also

[`cvm_cache_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_path.md)

Other cache:
[`cvm_cache_clear()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_clear.md),
[`cvm_cache_info()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_info.md),
[`cvm_cache_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_path.md)

## Examples

``` r
if (FALSE) { # interactive()
cvm_cache_set_path(tempfile("cvmdata-"))
}
```
