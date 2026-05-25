# Cache and mirror backend

`cvmdata` ships two interchangeable backends behind
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)
and a multi-layer disk cache that both backends share. This article
walks through the contract, the pipeline that keeps the mirror fresh,
and the workflows for switching between backends, inspecting the cache,
and tuning the TTL and eviction options.

``` r

library(cvmdata)
```

## Reference: backends and caches

### Source backends

| Backend | What it queries | When to prefer it |
|----|----|----|
| `"mirror"` | Parquet snapshots in GitHub Releases, queried via DuckDB. | Default from v0.1.0. ~30× faster on yearly bundles; staleness bounded by the weekly refresh window vs. CVM live. |
| `"cvm"` | The CVM Open Data Portal over HTTP (`dados.cvm.gov.br`). | Highest freshness — bytes are direct from the regulator. Opt in when you need the latest publication within the refresh window. |

The active backend is selected at three precedence levels: an explicit
`source = ...` argument to
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)
wins over the option `cvmdata.source` (set via
[`cvm_source_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_set.md)),
which in turn wins over the built-in default returned by
[`cvm_source_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_get.md).

### Cache layers

| Layer | Location | Content | Invalidation |
|----|----|----|----|
| L1 | `<cache>/raw/<dataset>/[<year>/]` | Raw CVM CSV (CAD) or yearly ZIPs (DFP/ITR/FRE) + extracted CSVs, with `*.etag.rds` sidecars. | HTTP HEAD with ETag / Last-Modified, throttled by `options(cvmdata.cache_ttl_seconds)` (default 30 days). |
| L3 | `<cache>/parquet/<dataset>/<table>/[report_type=R/]year=Y/part-0.parquet` | Parquet downloaded from the mirror. | Content-addressed via the `__source_hash.json` sidecar — the whole dataset tree is evicted when the upstream hash changes. |
| L4 | In-session memory. | Planned for v0.2. | — |

[`cvm_cache_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_path.md)
returns the cache root;
[`cvm_cache_set_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_set_path.md)
relocates it;
[`cvm_cache_info()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_info.md)
lists every artifact with its size, ETag and timestamps;
[`cvm_cache_clear()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_clear.md)
evicts (with `what` of `"all"`, `"raw"`, or `"parquet"`).

``` r

cvm_cache_path()
#> [1] "/home/runner/.cache/R/cvmdata"
cvm_source_get()
#> [1] "mirror"
```

## Mirror pipeline validation

Every weekly mirror publish runs a hybrid validation step
(`inst/etl/02b-validate.R`) between parquet generation and upload. The
checks are split into two tiers: *hard* failures block the publish (the
matrix job exits 1 and the previous mirror release stays in place),
*soft* failures emit a warning and let the publish proceed. The
validation markdown report is uploaded as a workflow artifact so
post-hoc inspection is always available, regardless of outcome.

| Check | Severity | Applies to |
|----|----|----|
| Parquet file exists | hard | Every (table, year, report_type) implied by the schema |
| Parquet readable by `arrow` | hard | Every produced parquet |
| `n_rows > 0` | hard | Every produced parquet |
| Identifier column (`cnpj_cia` / `cnpj_companhia`) is character | hard | Tables that carry one |
| `vl_conta` is numeric | hard | Tables that declare `multiply_by_scale` |
| Identifier values match the CVM CNPJ regex | soft | Tables with `cnpj_cia` / `cnpj_companhia` |
| `cd_cvm` values are all-digits | soft | Tables with `cd_cvm` |
| `dt_refer` / `data_referencia` within `[first_year, today + 1y]` | soft | Tables with a publish-date column |

The hybrid scope follows the decisions of session 3.14: universal
invariants live in code (no per-dataset YAMLs), hard checks bound the
worst case (empty / unreadable / wrong-type), soft checks bound the
content noise the CVM occasionally publishes. New checks land in the
same script; documenting them here is the rOpenSci-auditable surface.

## Workflow 1 — Working with the mirror (default)

From v0.1.0 the mirror is the default backend, so
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)
routes every call through DuckDB without further configuration. The
snippet below makes the choice explicit (helpful in scripts that may
inherit a different session option) and exercises both the cold and warm
cache paths:

``` r

# Make the choice explicit (a no-op when the option is already unset
# from the built-in default).
cvm_source_set("mirror")

# First call: the mirror's release inventory is fetched once via the
# GitHub REST API, parquet assets are downloaded into the L3 cache, and
# DuckDB reads them from disk.
bb_bpa_mirror <- issuer_fetch(
  "dfp", "bpa",
  report_type = "ind",
  issuer = "1023",
  year = 2024
)

# Second call: the L3 cache short-circuits the download; the API
# inventory is reused from the session cache; only DuckDB runs.
issuer_fetch(
  "dfp", "bpa",
  report_type = "ind",
  issuer = "1023",
  year = 2024
)
```

The argument `source = ...` to
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)
always overrides the option, so a single call can fall back to the CVM
portal without disturbing the session-wide setting:

``` r

# Persisted setting is "mirror"; this one call still queries CVM live.
issuer_fetch(
  "dfp", "bpa",
  report_type = "ind",
  issuer = "1023",
  year = 2024,
  source      = "cvm"
)
```

## Workflow 2 — CVM vs Mirror equivalence

The mirror backend returns tibbles that are column- and type-equivalent
to the CVM HTTP path on the common columns. The mirror additionally
attaches two partition columns (`year`, `report_type`) reattached from
the asset filename — they are not present on the CVM path because the
CVM CSV does not carry them. The table below was captured by
`data-raw/validate-mirror-end-to-end.R`, which runs the same four calls
through both backends and compares schemas:

``` r

cmp <- readRDS(system.file(
  "extdata", "vignette-data", "cache-and-mirror",
  "cvm-vs-mirror.rds",
  package = "cvmdata"
))
knitr::kable(cmp)
```

| chamada | n_rows_cvm | n_rows_mirror | colunas_iguais | tipos_iguais | cvm_only | mirror_only |
|:---|---:|---:|:---|:---|:---|:---|
| cad/companhias | 2673 | 2673 | TRUE | TRUE |  |  |
| dfp/bpa ind 2024 | 94515 | 94515 | FALSE | TRUE |  | report_type,year |
| itr/dre con (latest) | 27962 | 27904 | FALSE | TRUE |  | report_type,year |
| fre/posicao_acionaria 2024 (PETROBRAS) | 26 | 26 | FALSE | TRUE |  | year |

Small `nrow` differences (e.g. ITR’s `~0.2%`) are the expected staleness
window between the weekly cron and the live CVM portal — every Tuesday
at 04:00 BRT the mirror refreshes; chamadas during the rest of the week
may see CVM rows the mirror has not yet snapshotted. This is feature,
not bug: the mirror is a snapshot.

## Workflow 3 — Inspecting and clearing the cache

[`cvm_cache_info()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_info.md)
walks the cache and returns one row per artifact:

``` r

info <- cvm_cache_info()
info

# Total bytes across all listed artifacts:
attr(info, "total_size_bytes")
```

[`cvm_cache_clear()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_clear.md)
accepts a `what` argument scoping the eviction to L1 (`"raw"`), L3
(`"parquet"`), or both (`"all"`). The L3 mode evicts by dataset because
the partition layout nests year under table:

``` r

# Drop the mirror's local parquet copy for DFP only.
cvm_cache_clear(what = "parquet", dataset = "dfp", confirm = FALSE)

# Reset everything (raw + parquet).
cvm_cache_clear(what = "all", confirm = FALSE)
```

In interactive sessions `confirm = TRUE` (the default) prompts via
[`utils::askYesNo()`](https://rdrr.io/r/utils/askYesNo.html); batch
scripts must pass `confirm = FALSE`.

## Workflow 4 — TTL and LRU eviction

Two options shape the cache’s behaviour beyond explicit clears:

- `cvmdata.cache_ttl_seconds` (default `2592000`, i.e. 30 days) controls
  how often the L1 cache revalidates against CVM with an HTTP HEAD
  request. Set to `0` to revalidate on every call and to `Inf` to skip
  revalidation entirely until manual clear.
- `cvmdata.cache_max_size_mb` (default `100`) caps the size of L1. When
  total size exceeds 90% of the limit, the next download evicts the
  oldest units until the cache drops to 80% of the limit. Setting the
  option to `0`, a negative value, or `Inf` disables the eviction
  engine. The L3 mirror cache is content-addressed and not subject to
  size-based eviction.

``` r

# Force revalidation on every L1 hit.
options(cvmdata.cache_ttl_seconds = 0)

# Cap L1 at 250 MiB; LRU kicks in past 225 MiB and stops at 200 MiB.
options(cvmdata.cache_max_size_mb = 250)

# Subscribe to eviction notifications even in non-interactive runs.
options(cvmdata.cache_warn_evictions = TRUE)
```

Eviction emits the `cvmdata_warn_eviction` warning class (interactive
sessions get it for free; batch jobs honour the `cache_warn_evictions`
option). The aggregated message reports how many units were removed and
how much disk it freed.

## Where to read next

- **issuer-fetch** — argument-level deep dive on
  [`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md),
  including `issuer` / `year` / `report_type` / `validate` / `on_error`.
- **itr-dfp** — end-to-end workflows on annual and quarterly financial
  statements.
- **cvm-defects** — known CVM publication quirks and how the package
  handles each one.
