# rOpenSci pre-submission inquiry — draft

> **Status (2026-05-28): rascunho desatualizado — NÃO usar/postar como
> está.** Este texto é da época do v0.1.0 e descreve a API antiga, com
> `cvm_fetch()` unificado como entry point. A arquitetura mudou desde
> então: passou a 5 fetchers por contrato de dado (`issuer_fetch()`,
> `fund_fetch()`, `agent_fetch()`, `offering_fetch()`, `event_fetch()`),
> com `cvm_fetch()` e `cad_fetch()` removidos sem wrapper. Ver `NEWS.md`
> e `data-raw/decisions/cvmdata_arquitetura_grupos_decisao_v2.md`.
> **Nota de 2026-10-19:** a arquitetura mudou de novo — voltou a uma
> função única, `cvm_fetch()`, com assinatura nova (`cnpj`/`ticker`,
> `year` ou `from`/`to`, `basis`); os 5 fetchers são história. Ver
> `data-raw/decisions/cvmdata_v0-3_funcao_unica_decisao.md`. Este draft
> continua desatualizado e será reescrito do zero.
>
> Por decisão de timing de 2026-05-28, a submissão ao rOpenSci foi
> adiada para o **fim do ciclo de desenvolvimento** (após v1.0, com os
> 5 fetchers funcionais e os 18 grupos cobertos). Este draft será
> **reescrito do zero** nessa ocasião, refletindo a cobertura completa
> (18 grupos, 54 datasets na contagem do CKAN de 2026-10-16). A entrada
> no CRAN permanece acoplada ao aceite rOpenSci. Sequenciamento
> canônico: `ROADMAP.md`, seção "Fim do ciclo — submissão rOpenSci,
> CRAN e publicação".
>
> **Nota de 2026-11-02:** as duas seções que a revisão de desenho de
> 2026-10-21 apontou como inexistentes já estão escritas com a
> arquitetura atual e podem ser aproveitadas na reescrita: *Are there
> other R packages that accomplish the same thing?* (sobreposição,
> conferida no código dos pacotes) e *Why the mirror is the default
> source* (proveniência, longevidade, bus factor). O resto do texto
> continua desatualizado.

Draft for the issue to be opened at
<https://github.com/ropensci/software-review/issues/new/choose>
(template "Pre-Submission Inquiry"). Not posted yet — review,
adjust, and post when ready.

Items marked `<!-- TODO -->` need verification before posting:

- Versions and status of `GetDFPData2` and `GetFREData` (checked
  2026-11-02; recheck before posting).
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

<!-- Conferido em 2026-11-02 no código-fonte dos tarballs do CRAN
(GetDFPData2 0.6.5, GetFREData 1.1.0) e nos arquivos do CRAN para os
pacotes arquivados. Reconferir versões e datas antes de postar. -->

Two packages on CRAN, both by Marcelo Perlin and colleagues, read the
same CVM portal:

- **`GetDFPData2`** (0.6.5, June 2026): annual statements (DFP:
  `BPA`, `BPP`, `DRE`, `DFC_MD`, `DFC_MI`, `DMPL`, `DVA`) from 2010,
  plus the company register and the B3 tickers taken from the FCA.
  It has ITR code, but no exported ITR function.
- **`GetFREData`** (1.1.0, August 2026): every table of the yearly
  Reference Form (FRE) archive, from 2010.

Their predecessors `GetDFPData` and `GetITRData`, which scraped the
B3 and RAD interfaces and renamed columns to English, are archived on
CRAN (2026 and 2019). `BrasilMF`, which read some CVM registers, was
archived in 2020. We found no other R package that reads the CVM open
data, and none in rOpenSci (`rb3` covers the B3 exchange, not the
CVM).

What the packages share: both current packages download from
`dados.cvm.gov.br`, keep CVM column names (`GetDFPData2` in the
original upper case, `GetFREData` in Portuguese snake_case, as
`cvmdata` does), and cache the downloaded files locally. A user who
needs the DFP of a list of companies by CVM code, or one FRE table
for a few years, is well served by them.

Where `cvmdata` differs, by design rather than by degree:

1. **Filing versions.** The CVM files hold resubmissions. Neither
   package resolves them: `GetDFPData2` keeps `VERSAO` as a column
   and every delivery the file holds. `cvmdata` keeps the current
   filing by delivery date and document id (the version number alone
   is not a key: measured cases have two "version 1" filings), lists
   every delivery in `submissao`, removes statements the CVM file
   holds twice (884 cases in DFP/ITR 2010–2026), and returns the
   replaced filings through `cvm_versions()`.
2. **Both readings of an exercise.** `GetDFPData2` keeps one of the
   two `ORDEM_EXERC` columns of each file. `cvmdata` returns the file
   as published or, with `reading`, the original and the restated
   figures of the same exercise side by side.
3. **Values.** `cvmdata` applies `ESCALA_MOEDA` and returns amounts in
   reais; `GetDFPData2` returns the scale as a column, so units differ
   across companies. `GetFREData` turns identifier columns (`id_*`,
   `versao`) into numbers, which drops leading zeros; `cvmdata`
   keeps every identifier as character.
4. **Validation against the CVM dictionary.** Every `cvmdata` table
   is checked against the CVM `META` file (column count and names) on
   every read, and the package ships the dictionary and the code lists
   (`cvm_dictionary()`, `cvm_codelist()`).
5. **Coverage and selection.** One function, `cvm_fetch()`, reads DFP,
   ITR, FRE, FCA, CAD, CGVN, VLMO and IPE, selecting companies by CNPJ
   or by B3 ticker (including tickers of delisted companies), by year
   or by a window of reference dates. The other packages select by CVM
   code only.
6. **Reproducibility.** A dated, checksummed parquet mirror (see *Why
   the mirror is the default source*); the other packages cache the
   portal's current files, which the CVM overwrites in place.

The packages coexist without name collisions, and we would be glad to
point users of either toward the other where it fits better.

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
  a `source` argument with two values: `"mirror"` (the default,
  parquet via DuckDB, ~30× faster than HTTP for full years) and
  `"cvm"` (live HTTP against `dados.cvm.gov.br`). Precedence:
  explicit argument > `options(cvmdata.source)` > built-in default.
  The chosen source is attached to every returned tibble as the
  `source` attribute for downstream auditability. Why the default is
  the mirror, and what that costs, is the next section.

### Why the mirror is the default source

The default reads parquet files that the maintainer's ETL publishes
in GitHub Releases, not the regulator's portal. We know this is the
choice reviewers will question first, so here is what it rests on and
what guards it.

**Why a mirror at all.** The CVM publishes most datasets as one ZIP
per year of semicolon-separated Latin-1 CSVs; a single table of a
single company means downloading and parsing the whole year's
archive. The mirror stores the same tables,
already parsed and typed, partitioned by table, basis and year, so a
call reads only the partitions it needs (~30× faster for full years).
It also does something the portal cannot: the portal overwrites its
files in place, while the mirror keeps dated snapshots (below), so a
result can be reproduced as of a given date.

**Provenance.** The mirror is not a second source of truth. It is
built by the package's own reader, in strict mode, from the CVM files
(`inst/etl/`, run weekly by `.github/workflows/etl-mirror.yaml`), and
the reader aborts on any column the CVM renames or adds, so a change
upstream stops the publication instead of entering it silently. Every
tibble carries `source`, `fetched_at` and, under a pinned date, the
`release` it came from. `source = "cvm"` reads the portal directly
with the same parser and returns the same columns, so any result can
be checked against the regulator in one argument.

**Integrity.** Each release has a sidecar with the SHA-256 and size of
every parquet file; the client checks both on download and on cache
reuse, and discards a file that does not match
(`cvmdata_error_http_integrity`) rather than reading it.

**Reproducibility over time.** Besides the rolling
`mirror-<group>-<dataset>-latest` release, every run that changes data
creates `mirror-<group>-<dataset>-snapshot-<date>` holding only the
partitions that changed, plus a sidecar mapping every partition to the
snapshot that holds its bytes (~60 MB/week measured, ~3.5 GB/year).
Snapshots are never deleted. `cvm_release_set("2026-10-27")` pins a
session to the latest snapshot on or before that date. Filings the CVM
later replaced are kept in a per-partition history asset, read by
`cvm_versions()`.

**Longevity and bus factor.** The risk is real: today the releases
live under the maintainer's personal GitHub account and a single
maintainer runs the ETL. What limits it now:

- `source = "cvm"` never depends on the mirror; if the mirror
  disappears, `cvm_source_set("cvm")` keeps every call working,
  only slower.
- The ETL is part of the package and needs nothing but a GitHub
  token: a fork can rebuild and republish the whole mirror with the
  same workflow.
- An external monitor checks every week, without credentials, that the
  latest filing on the CVM portal is also in the mirror, and raises an
  alert after 7 days of lag or if a release stops opening anonymously.

<!-- Decisões do dono, 2026-11-02: (1) sem organização no GitHub —
projeto pessoal, nada a transferir por ora; (2) segundo host só se o
tamanho inviabilizar o GitHub, e então Cloudflare; (3) DOI por
snapshot datado: adotado (item no ROADMAP). Não prometer além disso. -->

What we plan, and what we do not:

- **A DOI for each quarterly edition.** Four times a year (the first
  weekly round of January, April, July and October) the whole mirror
  as it stood on that day — every dataset, the superseded versions,
  the column dictionary, the licence and the checksums — is deposited
  on Zenodo as one version of a single record, so a paper can cite the
  exact data it used and the data outlive the GitHub repository. The
  robot prepares the deposit after a 14-day grace period and verifies
  it (every partition against the mirror's digests, row counts against
  the previous edition, a read-back of the draft); the maintainer
  publishes it by hand. The weekly snapshots keep serving the dates in
  between, without a DOI. First edition: January 2027.
  <!-- Reescrever no presente, com o DOI do registro, quando a
  primeira edição estiver publicada. -->
- **No transfer to an organisation.** `cvmdata` is a personal
  project, and we will not claim an institutional home it does not
  have. The guarantees above are the ones that hold for a single
  maintainer: the official source is always one argument away, and
  anyone can rebuild the mirror.
- **Storage stays on GitHub Releases** while the mirror fits there
  (~3.5 GB/year of new partitions, measured). If its size ever made
  GitHub impractical, the parquet files would move to Cloudflare
  object storage. The client already locates every partition through
  the sidecar, so the move would change how download URLs are built,
  not the package API.

**Precedent.** Data packages on CRAN already serve preprocessed data
from GitHub Releases: `geobr` (v2) and `censobr` (IPEA) download
parquet files from `github.com/ipea/*_prep_data/releases`, `geobr`
with the IPEA server as a second host, and `capesR` reads from Hugging
Face with a checksum index shipped in the package. None of them offers
the official source as an alternative backend; `cvmdata` does. We
found no CRAN or rOpenSci policy on mirrors as such; what CRAN asks
(fail with an informative message, a small managed cache under
`tools::R_user_dir()`, https, a licence for the data downloaded) is
met. The CVM publishes these datasets under the ODbL, and the mirror
is redistributed under the same licence.
- **Coverage roadmap.** v0.1 covers the four core
  publicly-traded-company datasets. v0.2+ adds investment funds
  (ICVM 555), real-estate funds (FII), FIDCs, foreign issuers and
  exempt-securities filings — all scoped, all using the same
  `cvm_fetch(dataset, table, ...)` entry point.

## Confirmations

- [ ] [Package fits within scope](https://devguide.ropensci.org/policies.html#aims-and-scope)
      (data extraction primary, data munging secondary).
- [ ] No major overlap with existing rOpenSci packages.
      Overlap with CRAN packages (`GetDFPData2` and `GetFREData`) is
      documented above and is partial: same portal, different
      treatment of filing versions, values and identifiers, broader
      coverage, and a reproducible mirror.
- [ ] CRAN-ready (`R CMD check --as-cran`): 0/0/0 local; CRAN
      submission will follow rOpenSci acceptance, per the rOpenSci
      workflow.
