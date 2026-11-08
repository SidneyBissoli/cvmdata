# rOpenSci pre-submission inquiry — draft

> **Estado (2026-11-07): reescrito do zero para o escopo da submissão**
> (decisão do dono de 2026-11-06: o módulo de companhias, função única,
> 9 conjuntos). Segue os campos do modelo atual da issue
> ("Submit a presubmission inquiry",
> `ropensci/software-review/.github/ISSUE_TEMPLATE/B-submit-a-presubmission-inquiry.md`,
> lido em 2026-11-07), que agora tem duas seções que o rascunho antigo
> não tinha: ética/privacidade de dados e uso de IA generativa.
>
> **Antes de postar** (nada disto é opcional):
>
> 1. Release 0.3.0 cortada (FRE 2026, 25/11; os 85 lints antes) e o
>    campo `Description` do DESCRIPTION reescrito: o atual ainda diz
>    "first release covers cad, itr, dfp, fre" e "future releases".
>    O DESCRIPTION inteiro é colado na issue. O README tem o mesmo
>    defeito (cobertura de 4 conjuntos; comparação com `GetITRData`
>    e `GetDFPData2` diferente da desta issue) — consertar junto.
> 2. Confirmar que as fotos datadas antigas já foram limpas (seção *Ethics*).
> 3. Seção *Use of Generative AI*: o texto é do dono; o daqui é
>    rascunho com os fatos medidos. Ler e reescrever na primeira pessoa.
> 4. Reconferir os números marcados `<!-- medido em ... -->` (testes,
>    cobertura, tabelas, versões dos pacotes do Perlin).
> 5. Se a primeira edição do Zenodo já tiver saído, trocar o futuro
>    pelo DOI.

---

Submitting Author Name: Sidney da Silva Pereira Bissoli
Submitting Author Github Handle: <!--author1-->@SidneyBissoli<!--end-author1-->
Repository: <!--repourl-->https://github.com/SidneyBissoli/cvmdata<!--end-repourl-->
Submission type: <!--submission-type-->Pre-submission<!--end-submission-type-->
Language: <!--language-->en<!--end-language-->

---

-   Paste the full DESCRIPTION file inside a code block below:

```
<!-- TODO: colar o DESCRIPTION da 0.3.0 no momento de postar. -->
```

## Scope

**Data Lifecycle Packages**

- [x] data retrieval

- Explain how and why the package falls under these categories:

`cvmdata` retrieves the open data of the Brazilian Securities and
Exchange Commission (CVM, Comissão de Valores Mobiliários), the
regulator of the Brazilian capital market, and does the work that
stands between those files and an analysis: it resolves resubmitted
filings, separates the original and the restated figures of a fiscal
year, applies the currency scale, and checks every file against the
regulator's own data dictionary.

One area we are unsure of: to recover filings the regulator replaced
before our mirror started keeping them, the ETL parses the XML
documents of the CVM's filing archive (RAD) into the same tables as the
CSV. That reader lives in `inst/etl/`, not in the package API, so we
did not tick *data extraction*; we would welcome the editors' view.

-   Who is the target audience and what are scientific applications of this package?

Researchers in empirical finance, accounting and corporate governance
who work with Brazilian listed companies, and the data journalists and
analysts who cover them. The CVM files are the primary source for that
work: every annual (DFP) and quarterly (ITR) financial statement since
2010, the yearly reference form (FRE: governance, compensation,
ownership, board diversity), the registration form (FCA, which links B3
tickers to companies), the company register (CAD), the corporate
governance code report (CGVN), insider trading positions (VLMO),
share-buyback programmes, and the index of periodic and occasional
filings (IPE).

Typical applications are panels of financial ratios, event studies
around restatements, governance and compensation research, and
backtests that need the companies that left the exchange
(`cvm_fetch("cad", "companhias", as_of = "2015-12-31")` returns the
registrations in force on a date, survivorship-free). Two problems in
these data bias results without a word, and the package addresses them
by default:

- **Resubmissions.** A filing can be delivered several times, and the
  version number is not a key (we measured two "version 1" filings of
  the same document). `cvm_fetch()` returns the current filing by
  delivery date and document id; `cvm_versions()` returns every
  version, with the date it was superseded and the reason the company
  declared. About one superseded DFP/ITR version in twenty was filed in
  the wrong unit (R$ instead of R$ thousand) and replaced days later by
  the same figures a thousand times larger; `cvm_versions()` labels
  those (`scale_error`) so they are not read as restatements
  (353 + 28 of 6,825 superseded versions, DFP 2010–2025 and ITR
  2011–2026).
- **Restated comparatives.** Each yearly file carries the exercise it
  reports and the previous one as the company now presents it. With
  `reading = c("original", "restated")` the two figures of the same
  exercise come side by side (about a third of the DFP filers of 2023
  restated 2022).

-   Are there other R packages that accomplish the same thing? If so, how does yours differ or meet our criteria for best-in-category?

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

What the packages share: both download from `dados.cvm.gov.br`, keep
CVM column names (`GetDFPData2` in the original upper case,
`GetFREData` in Portuguese snake_case, as `cvmdata` does), and cache
the downloaded files locally. A user who needs the DFP of a list of
companies by CVM code, or one FRE table for a few years, is well
served by them.

Where `cvmdata` differs, by design rather than by degree:

1. **Filing versions.** Neither package resolves resubmissions:
   `GetDFPData2` keeps `VERSAO` as a column and every delivery the file
   holds. `cvmdata` keeps the current filing (above), lists every
   delivery in each dataset's `submissao` table, removes statements the
   CVM file holds twice (884 cases in DFP/ITR 2010–2026), and returns
   the replaced filings through `cvm_versions()`, including those
   recovered from the filing archive back to 2010.
2. **Both readings of an exercise.** `GetDFPData2` keeps one of the
   two `ORDEM_EXERC` values of each file; `cvmdata` returns the file as
   published or, with `reading`, both figures side by side.
3. **Values and identifiers.** `cvmdata` applies `ESCALA_MOEDA` and
   returns amounts in reais; `GetDFPData2` returns the scale as a
   column, so units differ across companies. `GetFREData` turns
   identifier columns (`id_*`, `versao`) into numbers, which drops
   leading zeros; `cvmdata` keeps every identifier as character.
4. **Validation against the CVM dictionary.** Every file is checked
   against the CVM `META` file (column count and names) on every read;
   a column the CVM renames stops the read with a classed error instead
   of entering the result. The package ships the dictionary and the
   code lists (`cvm_dictionary()`, `cvm_codelist()`).
5. **Coverage and selection.** One function, `cvm_fetch()`, reads nine
   datasets and 104 tables <!-- medido em 2026-11-07: cvm_tables() e o
   snapshot do dicionário --> (DFP, ITR, FRE, FCA, CAD, CGVN, VLMO,
   IPE, share buybacks), selecting companies by CNPJ or by B3 ticker
   (including tickers of delisted companies), by year or by a window of
   reference dates. The other packages select by CVM code only.
6. **Reproducibility.** A dated, checksummed mirror (see below); the
   other packages cache the portal's current files, which the CVM
   overwrites in place.

The packages coexist without name collisions, and we would be glad to
point users of either toward the other where it fits better.

-   (If applicable) Does your package comply with our guidance around _Ethics, Data Privacy and Human Subjects Research_?

The package reads only data the regulator publishes openly, under the
Open Database License, as part of its legal disclosure regime; it
collects nothing from users and does not link records across sources.

Some of those tables identify natural persons, and we want to state it
plainly. The CVM publishes, by legal duty, the name, the full CPF (the
Brazilian individual taxpayer number) and the birth date of board members,
fiscal council and committee members, investor-relations officers, audit
partners, individual shareholders above the disclosure threshold, and
relatives of directors.
<!-- medido em 2026-11-08: cerca de 557 mil valores em 13 colunas `cpf*`,
2.406 em 2 colunas `documento_*`, 2.364 biografias e outros
textos livres com CPF (201); 131.129 datas de nascimento em 2 tabelas -->

`cvmdata` treats its two sources differently, on purpose.
`source = "cvm"` returns what the regulator publishes. The mirror and its
Zenodo editions, which are public and permanent and which we redistribute
ourselves, keep what research needs and no more: every CPF, in the columns
that hold it and in free text, is masked as `***.456.789-**`, the way the
Federal Revenue publishes its own open CNPJ data; a foreign document in a
CPF column becomes `***`; and the birth date is reduced to the year. Names
stay, because the name is the content of the disclosure the regulation
requires, and the masked CPF plus the name still follow a person across
tables (FRE 2021-2025: no two different people merge). A guard stops any
publication, and any deposit, that still holds a full CPF or a birth date.
The reasoning follows the Brazilian LGPD (Lei 13.709/2018), art. 7,
paragraphs 3 and 4, and art. 10, paragraph 1; it is written down in
`data-raw/decisions/` in the repository. We are not lawyers, and we would
welcome the reviewers' view.

-   Any other questions or issues we should be aware of?:

**The default source is a mirror, not the regulator's portal.** We
expect this to be the first thing reviewers question, so here is what
it rests on.

*Why a mirror.* The CVM publishes most datasets as one ZIP per year of
semicolon-separated Latin-1 CSVs; one table of one company means
downloading and parsing the year's whole archive. The mirror stores the
same tables as parquet, already parsed and typed, partitioned by table,
basis and year, so a call reads only what it needs (about 30 times
faster for full years). It also keeps what the portal cannot: the CVM
overwrites its files in place, and the mirror keeps dated snapshots.

*Provenance.* The mirror is built weekly by the package's own reader,
in strict mode, from the CVM files (`inst/etl/`,
`.github/workflows/etl-mirror.yaml`); a renamed or added column stops
the publication. Every result carries `source`, `fetched_at` and, under
a pinned date, the `release` it came from. `source = "cvm"` reads the
portal with the same parser and returns the same columns, so any result
can be checked against the regulator by changing one argument.

*Integrity.* Each release has a sidecar with the SHA-256 and size of
every file; the client checks both on download and on cache reuse and
discards a file that does not match (`cvmdata_error_http_integrity`).

*Reproducibility over time.* Every run that changes data creates a
dated snapshot holding the partitions that changed, plus a sidecar
mapping every partition to the snapshot that holds its bytes (about
60 MB a week). Snapshots are never deleted;
`cvm_release_set("2026-10-27")` pins a session to the mirror as it
stood on that date. Superseded filings are kept in a per-partition
history asset, read by `cvm_versions()`.

*A DOI per quarterly edition.* Four times a year the whole mirror as
it stood that day (every dataset, the superseded versions, the
dictionary, the licence and the checksums) is deposited on Zenodo as a
new version of one record, so a paper can cite the exact data it used
and the data outlive the GitHub repository. The ETL prepares the
deposit after a 14-day grace period and verifies it (every file
against the mirror's digests, row counts against the previous edition,
a read-back of the draft); the maintainer publishes it by hand. The
pipeline passed a full rehearsal on the Zenodo sandbox; the first
edition is due in January 2027.

*Longevity and bus factor.* The releases live under the maintainer's
personal GitHub account and one person runs the ETL; we do not claim
an institutional home the project does not have. What limits the risk:
`source = "cvm"` never depends on the mirror; the ETL is part of the
package and needs only a GitHub token, so a fork can rebuild the whole
mirror; an external monitor checks every week, without credentials,
that the latest CVM filing is in the mirror and that the releases open
anonymously; and the Zenodo editions survive the repository. Storage
stays on GitHub Releases while it fits (about 3.5 GB a year of new
partitions); if it stopped fitting, the files would move to Cloudflare
object storage, which changes how URLs are built, not the API.

*Precedent.* CRAN packages already serve preprocessed data from GitHub
Releases: `geobr` (v2) and `censobr` (IPEA) download parquet files from
`github.com/ipea/*_prep_data/releases`, and `capesR` reads from Hugging
Face with a checksum index in the package. None offers the official
source as an alternative backend. We found no CRAN or rOpenSci policy
on mirrors as such; what CRAN asks (an informative failure, a small
managed cache under `tools::R_user_dir()`, https, a licence for the
data) is met, and the mirror is redistributed under the CVM's ODbL.

**Scope of this submission and what comes next.** The CVM catalogue has
18 groups; this submission covers one, `companhias` (listed companies),
completely. Funds, agents, offerings and enforcement will extend
`cvm_fetch()` through one YAML schema per table, with no new
functions; `cvm_groups()` already lists the plan. We chose to submit
the module that exists rather than wait for the whole catalogue.

**Language.** Function names, arguments, attributes, messages and
documentation are in English; table names, column names, categorical
values and free text stay in Portuguese exactly as the CVM publishes
them. The mismatch is deliberate: the audience reads Portuguese, and
the columns must match the regulator's dictionary, the accounting
standards and the literature.

**Technical state.** <!-- medido em 2026-11-07; reconferir na 0.3.0 -->
`pkgcheck()` passes (one failure fixed in November 2026; the remaining
notes are optional). R CMD check is clean on Ubuntu (devel, release,
oldrel-1), macOS and Windows; test coverage is 95%
<!-- Codecov 95,26 % em 2026-11-06; testes medidos em 2026-11-07:
3.568 expectativas, 696 blocos, 0 falhas, 1 pulada --> and the suite
has 3,568 expectations in 43 files, none of which touches the network (`httptest2` and mocked
`httr2` responses; integration tests behind an environment variable).
The pkgdown site has an introductory vignette and eight articles,
including one on the defects we found in the CVM files and how the
package handles each. Version 0.3.0 is the one submitted; the lifecycle
badge says *experimental*.

## Use of Generative AI

- [x] Generative AI tools were used to produce some of the material in this submission.

<!-- TODO (dono): rascunho com os fatos medidos em 2026-11-07;
reescrever na primeira pessoa e conferir cada afirmação sobre o seu
próprio papel. A política (blog da rOpenSci, 2026-02-26) pede: onde e
como a IA foi usada, link para o "agents.md" ou equivalente, e a
afirmação de que todo o material gerado foi revisado pelo autor. Os
editores podem perguntar se houve contribuição humana suficiente;
o que pesa: motivação, histórico de desenvolvimento, decisões de
desenho documentadas. -->

The package was developed with Claude Code (Anthropic) throughout: the
R code, the tests, the ETL, the documentation and the measurements
behind them were written in sessions where I set the task and the
design, and the model wrote and ran the code. Every commit since the
first one (May 2026) carries the co-author line; the instructions the
model works under are in [`CLAUDE.md`](https://github.com/SidneyBissoli/cvmdata/blob/main/CLAUDE.md),
which also documents the package's conventions.

My part: the scope, the API and every design decision, recorded with
alternatives and reasons in
[`data-raw/decisions/`](https://github.com/SidneyBissoli/cvmdata/tree/main/data-raw/decisions),
the `ROADMAP.md` and `NEWS.md` (for example: one fetch function instead
of five; `basis` with no default because a third of the issuers file
only individual statements; the mirror as default with the portal one
argument away; a DOI per quarterly edition rather than per snapshot;
what counts as a scale error). I reviewed every pull request before
merging it, and most decisions came from checking the data: the
figures quoted in this inquiry were measured on the CVM files, not
taken from the model's account of them.

Where reviewers may want to look harder: the tests were written by the
model, against fixtures cut from real CVM files; and the XML reader of
the filing archive (`inst/etl/util-rad.R`) was calibrated
account-by-account against 60 current filings, but covers two document
layouts that we know only from the documents we read.
