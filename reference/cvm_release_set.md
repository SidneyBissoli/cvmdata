# Pin the mirror to a dated snapshot

Sets the option `cvmdata.mirror_release`, which
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
and
[`cvm_versions()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_versions.md)
consult on every call with `source = "mirror"`. Pass a complete date to
read the mirror as it was on that day, or `"latest"` to follow the
weekly refresh again. The pin is a property of the session: set it once
at the top of a script and every read below it comes from the same
snapshot. It has no effect on `source = "cvm"`, which always reads the
portal live.

Switching snapshots re-downloads only the partitions whose bytes differ
between the two; the local cache verifies every parquet against the
SHA-256 the mirror publishes for it.

## Usage

``` r
cvm_release_set(release)
```

## Arguments

- release:

  `"latest"`, or a complete date as `"YYYY-MM-DD"` or a
  [Date](https://rdrr.io/r/base/Dates.html) of length one.

## Value

The chosen value, invisibly, as a character scalar.

## See also

[`cvm_release_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_release_get.md),
[`cvm_source_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_set.md)

Other source:
[`cvm_release_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_release_get.md),
[`cvm_source_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_get.md),
[`cvm_source_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_set.md)

## Examples

``` r
if (FALSE) { # interactive()
cvm_release_set("2026-11-01")
cvm_release_set("latest")
}
```
