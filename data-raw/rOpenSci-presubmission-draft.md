# rOpenSci pre-submission inquiry — draft

Draft for the issue to be opened at
<https://github.com/ropensci/software-review/issues/new/choose>
(template "Pre-Submission Inquiry"). Not posted yet — review,
adjust, and post when ready.

Items marked `<!-- TODO -->` need verification before posting:

- Exact current names of comparable CRAN packages by Marcelo
  Perlin (`GetDFPData2`, `GetFREData`, `GetITRData`) — confirm
  none was renamed/archived since this draft was written.
- Test count "590+" — confirm via
  `devtools::test()` or `length(testthat::test_dir("tests/testthat"))`.

---

## Package: cvmdata

`cvmdata` provides a tidy R API to the open data published by the
Brazilian Securities and Exchange Commission (CVM), covering core
publicly-traded-company datasets with a unified `cvm_fetch()` entry
point, an HTTP-with-cache backend against `dados.cvm.gov.br`, and a
parquet mirror in GitHub Releases refreshed weekly for
reproducibility.

- Public repo: <https://github.com/SidneyBissoli/cvmdata>
- pkgdown site: <https://sidneybissoli.github.io/cvmdata/>
- Released v0.1.0 on 2026-05-24 (covers `cad`, `dfp`, `itr`, `fre` —
  the four core publicly-traded-company datasets).
- License: MIT.

## Which rOpenSci scope categories does the package fit?

Primary: **data extraction** — programmatic, reproducible access to
governmental open data published by a national securities regulator.

Secondary: **data munging** — schema-driven cleanup of categorical
encoding (ISO-8859-1 → UTF-8), date conversion guided by the
official CVM data dictionary, scale normalization for monetary
values (`vl_conta × escala_moeda`), and version-deduplication of
resubmitted regulatory filings.

## Statement of need

### What problem does it solve?

The Brazilian Securities and Exchange Commission (CVM) publishes
yearly bulk dumps of regulatory filings on the open-data portal at
`dados.cvm.gov.br`. These datasets are the primary source for
empirical research in Brazilian finance, accounting and corporate
governance — they contain every annual (DFP) and quarterly (ITR)
financial statement, every reference form (FRE) including
governance, remuneration and ESG-adjacent disclosures, plus the
live company registry (CAD). They are also the only
government-grade source for investigative data journalism on
listed companies in Brazil.

Today these data are typically accessed via ad-hoc scrapers, Excel
import scripts, or copy-pasted CSVs. Existing R packages on CRAN
(see comparables below) cover overlapping datasets but scrape the
B3-mirrored interface of these same data and rename CVM columns to
English. There is no R package that:

1. Reads directly from the CVM open-data portal — the regulatory
   primary source — without an intermediate mirror outside the
   regulator's control.
2. Preserves CVM's published column names, table names, categorical
   values and free text in Portuguese. Fidelity matters when the
   downstream user is a Brazilian researcher cross-referencing CVM
   publications, accounting standards (CPC/IFRS-BR), and academic
   literature.
3. Offers byte-identical reproducibility through a parquet mirror
   refreshed on a published schedule, content-addressed by a
   SHA-256 hash sidecar, with a documented dual-backend contract
   (live CVM HTTP vs. archived parquet).

`cvmdata` fills these gaps.

### Who is the target audience?

- Academic researchers in Brazilian finance, accounting, corporate
  governance, and empirical economics. Typical use cases include
  cross-sectional regressions on financial ratios, governance event
  studies, ESG and remuneration disclosure research, and time-series
  panels of regulated entities.
- Data journalists covering listed companies, corporate scandals,
  governance issues, and equity ownership.
- Market analysts and quant practitioners building fundamental
  databases.
- Educators in finance and accounting using real Brazilian data
  in coursework.

### Are there other R packages that accomplish the same thing?

The closest comparables on CRAN are the `Get*Data` family by
Marcelo Perlin: **`GetDFPData2`**, **`GetFREData`**, and
**`GetITRData`** <!-- TODO: confirm current names/statuses before
posting -->. They cover overlapping datasets but:

- Source data from the B3 mirror, not the CVM open-data portal
  directly.
- Rename CVM columns to English and re-shape tables into
  package-specific conventions, breaking traceability to CVM
  publications and to the official CVM data dictionary.
- Have no mirror layer for reproducibility — they hit the upstream
  source on every call, and historical results are not
  reconstructible byte-for-byte from a published archive.

`cvmdata` complements rather than replaces them: users who prefer
the existing English-renamed B3 interface will continue to use
Perlin's family. Users who need fidelity to the CVM source, broader
dataset coverage (CAD registry, full FRE detail tables including
the eight tables for which CVM does not publish a META schema), or
reproducibility through a versioned parquet mirror will find
`cvmdata` a better fit. The two ecosystems coexist with no
namespace or function-name collisions.

Outside this Brazilian niche, `cvmdata`'s design borrows patterns
from the rOpenSci data-extraction family — single fetch verb,
tidy output with attached metadata, configurable cache,
dual-backend fallback with explicit precedence — rather than
overlapping in scope.

## Technical state

- v0.1.0 released 2026-05-24.
- CI: R-CMD-check matrix on Ubuntu devel/release/oldrel-1, macOS
  release, Windows release — green via
  `.github/workflows/R-CMD-check.yaml`.
- Test coverage ≥ 90% via `covr`/codecov.
- ~590 unit tests <!-- TODO: confirm exact count --> in
  `tests/testthat/`. All HTTP traffic is mocked via `httptest2` and
  `httr2::with_mocked_responses()` — no test reaches the live CVM
  portal or the GitHub Releases mirror.
- Documentation: an intro vignette (`cvmdata.Rmd`, CRAN-safe via
  `eval = interactive()`) and five long-form articles
  (`cvm-fetch.Rmd`, `itr-dfp.Rmd`, `fre.Rmd`, `cvm-defects.Rmd`,
  `cache-and-mirror.Rmd`). Articles that need data read
  pre-computed RDS bundles from `inst/extdata/vignette-data/`.
- pkgdown site published at
  <https://sidneybissoli.github.io/cvmdata/>.
- `R CMD check --as-cran` clean locally; win-builder R-devel
  resubmission pending after May 2026 doc fixes.

## Other relevant context

- **Bilingual API surface, by design.** Function names, arguments,
  metadata attributes, error messages and roxygen docs are in
  English following rOpenSci and tidyverse conventions. Table
  names, column names, categorical values and free-text content
  are preserved in Portuguese exactly as published by CVM. The
  mismatch is deliberate: the package's audience is predominantly
  Portuguese-speaking, and fidelity to the regulatory source
  outweighs cosmetic uniformity. The convention is documented in
  the project's `CLAUDE.md` and in the README.
- **Dual-backend with explicit precedence.** `cvm_fetch()` exposes
  a `source` argument with two values: `"mirror"` (default since
  v0.1.0 — parquet via DuckDB, ~30× faster than HTTP for full
  years) and `"cvm"` (live HTTP against `dados.cvm.gov.br` for
  byte-level freshness). Precedence: explicit argument >
  `options(cvmdata.source)` > built-in default. The chosen source
  is attached to every returned tibble as the `source` attribute
  for downstream auditability.
- **Mirror reproducibility contract.** The parquet mirror is
  refreshed weekly via `.github/workflows/etl-mirror.yaml`. Each
  dataset release carries a SHA-256 hash sidecar
  (`__source_hash.json`) that the package uses to invalidate the
  local L3 parquet cache when the upstream source changes —
  content-addressed invalidation, no TTL.
- **Coverage roadmap.** v0.1 covers the four core
  publicly-traded-company datasets. v0.2+ adds investment funds
  (ICVM 555), real-estate funds (FII), FIDCs, foreign issuers and
  exempt-securities filings — all scoped, all using the same
  `cvm_fetch(dataset, table, ...)` entry point.

## Confirmations

- [ ] [Package fits within scope](https://devguide.ropensci.org/policies.html#aims-and-scope)
      (data extraction primary, data munging secondary).
- [ ] No major overlap with existing rOpenSci packages.
      Overlap with CRAN packages (`GetDFPData2` family by Marcelo
      Perlin) is documented above and is partial: distinct source,
      distinct API contract, distinct reproducibility guarantees.
- [ ] CRAN-ready (`R CMD check --as-cran`): 0/0/0 local; CRAN
      submission will follow rOpenSci acceptance, per the rOpenSci
      workflow.
