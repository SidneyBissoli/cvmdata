## Submission summary

First public release. The package is currently undergoing rOpenSci
software-review (pre-submission inquiry filed at
https://github.com/ropensci/software-review/issues/<N>) and CRAN
submission will follow the rOpenSci acceptance, per their workflow.

## Test environments

- Local Windows 11, R 4.5.3: 0 errors, 0 warnings, 0 notes.
- GitHub Actions matrix (Ubuntu devel/release/oldrel-1, macOS release,
  Windows release) via `.github/workflows/R-CMD-check.yaml`: all green.
- win-builder R-devel (`devtools::check_win_devel()`): <pending — fill
  after the build completes>.
- macOS-builder R-release (`devtools::check_mac_release()`): <pending>.

## R CMD check results

0 errors, 0 warnings, 0 notes.

## Reverse dependencies

First submission — no reverse dependencies.

## Notes

- All HTTP traffic in the test suite is mocked via `httptest2` and
  `httr2::with_mocked_responses()`; no test reaches the live CVM portal
  or the GitHub Releases mirror.
- Vignettes that would otherwise call out to the network are gated by
  `eval = interactive()`, or read pre-computed RDS bundles from
  `inst/extdata/vignette-data/`.
- The package keeps Portuguese column names, table names and
  categorical values as published by the regulator (CVM); function
  names, arguments and metadata attributes are in English following
  rOpenSci and tidyverse conventions. The mismatch is deliberate and
  documented in `CLAUDE.md` §1 and the README.
