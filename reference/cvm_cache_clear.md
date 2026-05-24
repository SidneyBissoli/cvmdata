# Clear cached files

Deletes cached files selectively. `what = "all"` removes the entire
cache tree (everything under
[`cvm_cache_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_path.md));
`what = "raw"` removes only the raw download area (`<cache>/raw/`);
`what = "parquet"` removes only the L3 mirror cache
(`<cache>/parquet/`). When `dataset` (and optionally `year`) is
supplied, the scope is narrowed to the matching subtree under the chosen
area; passing `dataset` without an explicit `what` defaults to `"raw"`
for backwards compatibility.

## Usage

``` r
cvm_cache_clear(
  what = "all",
  dataset = NULL,
  year = NULL,
  confirm = interactive()
)
```

## Arguments

- what:

  One of `"all"`, `"raw"` or `"parquet"`. Default `"all"`.

- dataset:

  Optional dataset id (e.g. `"dfp"`). Restricts deletion to the matching
  `<cache>/<what>/<dataset>/` subtree.

- year:

  Optional integer year. Requires `dataset` to be non-`NULL`. Restricts
  deletion to the matching `year=<YYYY>/` slot (raw) or `year=<YYYY>/`
  slot (parquet).

- confirm:

  Logical scalar. When `TRUE`, asks for confirmation before deleting.
  Default: [`interactive()`](https://rdrr.io/r/base/interactive.html).

## Value

The number of files deleted, invisibly.

## Details

In interactive sessions the user is asked to confirm via
[`utils::askYesNo()`](https://rdrr.io/r/utils/askYesNo.html) before
deletion. In batch sessions the default (`confirm = interactive()`)
evaluates to `FALSE` and deletion proceeds silently — pass
`confirm = TRUE` explicitly to force a prompt.

## See also

Other cache:
[`cvm_cache_info()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_info.md),
[`cvm_cache_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_path.md),
[`cvm_cache_set_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_set_path.md)

## Examples

``` r
if (FALSE) { # interactive()
cvm_cache_clear(dataset = "dfp", year = 2024)
cvm_cache_clear(what = "raw")
}
```
