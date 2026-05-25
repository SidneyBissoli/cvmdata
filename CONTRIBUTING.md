# Contributing to cvmdata

Thank you for considering a contribution to **cvmdata**. This document
covers how to file an issue, set up a development environment, run the
quality gate, and propose changes (including new dataset schemas).

By participating in this project you agree to abide by its [Code of
Conduct](https://sidneybissoli.github.io/cvmdata/CODE_OF_CONDUCT.md).

## Reporting issues

- Please file issues at
  <https://github.com/SidneyBissoli/cvmdata/issues>.
- Before opening a new issue, search existing ones (open and closed) to
  avoid duplicates.
- For bug reports, include a minimal reproducible example using
  [reprex](https://reprex.tidyverse.org/). Mention the CVM dataset and
  table involved
  (e.g. `issuer_fetch("dfp", "bpa", report_type = "ind", ...)`), the
  value of `getOption("cvmdata.source")` and the output of
  [`sessionInfo()`](https://rdrr.io/r/utils/sessionInfo.html).
- For feature requests, describe the use case and how the proposed API
  would fit the existing surface. Cross-cutting design changes are best
  discussed in an issue before a PR.

## Submitting a pull request

1.  **Fork** the repository and create a branch off `main`:
    `git checkout -b your-topic`.
2.  **Match the project conventions**: snake_case function and argument
    names; the native pipe `|>`; tidyverse style; fully-qualified
    namespaces
    ([`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html),
    [`httr2::request()`](https://httr2.r-lib.org/reference/request.html));
    messages via `cli::cli_*`. Strings preserved from the CVM portal
    (table names, column names, categorical values) stay in Portuguese;
    everything else (function names, arguments, messages, documentation)
    is in English.
3.  **Run the quality gate locally** (see next section) before pushing.
4.  **Open a pull request** against `main`. The PR description should
    summarise the change, list user-visible effects, and link any
    related issue.

Small typo fixes and documentation tweaks are welcome and do not require
an issue first.

## Development setup

Clone your fork, then from the package root:

``` r

# install dependencies (Imports + Suggests)
devtools::install_dev_deps()

# load the package without installing
devtools::load_all()
```

The package targets R (\>= 4.1) and uses `testthat` 3.x with edition 3.
A C/C++ toolchain is **not** required.

Fixtures used by the test suite live under `tests/testthat/fixtures/`
(small CSV/ZIP samples with a `.meta.json` file recording origin). No
test in `tests/testthat/` hits the CVM portal; networked integration
tests are gated by `Sys.getenv("CVMDATA_RUN_INTEGRATION") == "true"`.

## Quality gate

Every commit on `main` (and every PR) must pass the following checks
locally before review:

``` r

# 0 errors, 0 warnings, 0 notes (a single "unable to verify current
# time" note is tolerated)
devtools::check()

# all tests must pass (487+ as of v0.0.0.9000)
devtools::test()

# lintr must return character(0)
lintr::lint_package()

# coverage target is >= 90%
covr::package_coverage()

# pkgdown site must build cleanly; deep-dive articles call the CVM
# portal and need network access
pkgdown::build_site()
```

These commands are also enforced in CI (`R-CMD-check.yaml`, `lint.yaml`,
`test-coverage.yaml`, `pkgdown.yaml` under `.github/workflows/`). PRs
that break any of them will be requested to fix the regression before
merge.

## Adding or modifying a schema YAML

Each table is described by a YAML file under
`inst/extdata/schemas/<dataset>/<table>.yaml`. The schema drives
download, parsing, validation and transformation in
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md).
Minimum required fields:

``` yaml
dataset: <dataset>
table: <table>

# exactly one of the next two must be non-null
cvm_archive_url_pattern: <ZIP URL with {year} when applicable>
cvm_file_url_pattern: <direct CSV URL or null>

cvm_file_pattern: "<CSV filename inside the archive>"
cvm_dictionary_url: "<META URL, or null when meta_status: missing>"

meta_status: available     # or "missing" when CVM publishes no META
encoding: ISO-8859-1
delimiter: ";"

temporal_partitioning: none   # or "yearly"
first_year: <int when yearly>

expected_field_count: <int>
expected_field_names:         # mandatory when meta_status: missing
  - <field 1>
  - <field 2>

transformations: []           # see below
```

Accepted `action` values in `transformations`:

- `multiply_by_scale` — multiply a column by a scale column (requires
  `scale_column:`).
- `drop` — remove a column from the returned tibble.
- `keep_latest_version` — keep only the highest `versao` per
  identifier/date key.

When proposing a brand-new dataset, please also:

- Add a small fixture (`tests/testthat/fixtures/<dataset>_*.zip` or
  `.csv`, with a `.meta.json` recording origin).
- Add a mocked test under `tests/testthat/test-<dataset>*.R` (use
  [`httr2::with_mocked_responses()`](https://httr2.r-lib.org/reference/with_mocked_responses.html)).
- Extend `inst/extdata/cvm_dictionary_snapshot.csv` via
  `data-raw/build-dictionary-snapshot.R` and rerun
  `data-raw/build-codelists-snapshot.R` if categorical columns appear.

## Project goals

The intermediate target is acceptance via [rOpenSci
software-review](https://github.com/ropensci/software-review); CRAN
follows acceptance. Design decisions that would not survive rOpenSci
review are unlikely to land.

## Acknowledgements

Thank you for contributing. Issues and PRs of any size are appreciated.
