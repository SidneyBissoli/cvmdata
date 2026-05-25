# Clear cached files

Deletes cached files selectively. `what = "all"` removes the entire
cache tree (everything under
[`cvm_cache_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_path.md));
`what = "raw"` removes only the raw download area (`<cache>/raw/`);
`what = "parquet"` removes only the L3 mirror cache
(`<cache>/parquet/`). When `group`, `dataset` (and optionally `year`)
are supplied, the scope is narrowed to the matching subtree under the
chosen area; passing `group` or `dataset` without an explicit `what`
defaults to `"raw"` for backwards compatibility.

## Usage

``` r
cvm_cache_clear(
  what = "all",
  dataset = NULL,
  group = NULL,
  year = NULL,
  confirm = interactive()
)
```

## Arguments

- what:

  One of `"all"`, `"raw"` or `"parquet"`. Default `"all"`.

- dataset:

  Optional dataset id (e.g. `"dfp"`). Restricts deletion to the matching
  `<cache>/<what>/<group>/<dataset>/` subtree.

- group:

  Optional CKAN group slug (e.g. `"companhias"`). Restricts deletion to
  the matching `<cache>/<what>/<group>/` subtree. When omitted but
  `dataset` is supplied, the group is inferred from the dataset lookup.

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

Filter precedence: `what = "all"` wipes everything ignoring the other
filters; otherwise the path is composed as
`<cache>/<what>/<group>/<dataset>/<year>/`, with each level becoming
optional from right to left. `year` requires `dataset`; `dataset` may be
supplied without `group` (the group is inferred via the v0.1.0.9000
lookup table). `group` may be supplied alone to wipe a whole group at
once.

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
cvm_cache_clear(group = "companhias", what = "raw")
cvm_cache_clear(what = "raw")
}
```
