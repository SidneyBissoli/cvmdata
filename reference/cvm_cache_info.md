# Inventory of files in the cvmdata cache

Lists every artifact currently stored under `<cache>/raw/`, with size,
modification time and ETag metadata when available. Both upstream
artifacts (CSV directos for non-partitioned datasets, ZIPs for yearly
datasets) and CSVs extracted from those ZIPs appear as separate rows;
the sidecar `*.etag.rds` files themselves are excluded from the listing
(their content surfaces in the `etag` and `last_modified` columns).

## Usage

``` r
cvm_cache_info()
```

## Value

A tibble with one row per cached file, sorted by `group` then `dataset`
then `file`. Columns: `group` (character), `dataset` (character), `file`
(basename), `path` (absolute), `size_bytes` (integer), `mtime`
(POSIXct), `etag` (character; `NA` when absent), `last_modified`
(character; `NA` when absent). The tibble has an attribute
`total_size_bytes` (numeric scalar) with the total bytes counted toward
the cache size limit. Returns a zero-row tibble with the same schema
(and `total_size_bytes = 0`) when the cache is empty.

## Details

Extracted CSVs have no sidecar of their own — the freshness of the
parent ZIP covers them — so they appear with `etag = NA_character_` and
`last_modified = NA_character_`.

The returned tibble carries an attribute `total_size_bytes` with the sum
of `size_bytes`, useful for comparing against the eviction limit set via
`options(cvmdata.cache_max_size_mb)` (default 100 MiB). When the total
exceeds 90% of the limit, the next download triggers LRU eviction of the
oldest year directories (yearly datasets) or artifact+sidecar pairs
(non-partitioned). See
[`cvm_cache_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_path.md)
for the option's semantics.

## See also

Other cache:
[`cvm_cache_clear()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_clear.md),
[`cvm_cache_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_path.md),
[`cvm_cache_set_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_set_path.md)

## Examples

``` r
cvm_cache_info()
#> # A tibble: 0 × 8
#> # ℹ 8 variables: group <chr>, dataset <chr>, file <chr>, path <chr>,
#> #   size_bytes <int>, mtime <dttm>, etag <chr>, last_modified <chr>
```
