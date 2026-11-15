# Get the mirror snapshot the package reads

Reads the option `cvmdata.mirror_release`, falling back to `"latest"`
when the option is unset. The value says which copy of the parquet
mirror `source = "mirror"` reads:

- `"latest"`: the release `mirror-<group>-<dataset>-latest`, rewritten
  in place by the weekly ETL. The default.

- A complete date, `"YYYY-MM-DD"`: the mirror as it was on that day. The
  package resolves it to the most recent dated snapshot published on or
  before the date and reads every partition from the release that holds
  it, so the same date always returns the same bytes. A date earlier
  than the first snapshot of a dataset is an error that names the
  earliest date available.

Dated snapshots exist from 2026-10-27 on. Every tibble read from the
mirror carries the release it came from in the attribute `release` (see
[cvm_tbl](https://sidneybissoli.github.io/cvmdata/reference/cvm_tbl.md)).
[`cvm_versions()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_versions.md)
under a pinned date drops the history rows superseded after that date,
so its result is the set of versions known on that day.

## Usage

``` r
cvm_release_get()
```

## Value

A character scalar: `"latest"` or a date as `"YYYY-MM-DD"`.

## See also

[`cvm_release_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_release_set.md),
[`cvm_source_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_get.md)

Other source:
[`cvm_release_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_release_set.md),
[`cvm_source_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_get.md),
[`cvm_source_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_set.md)

## Examples

``` r
cvm_release_get()
#> [1] "latest"
```
