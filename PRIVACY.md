# Privacy notice of the cvmdata data mirror

This notice is for the people whose names appear in the data the
`cvmdata` package mirrors: directors, fiscal council members, committee
members, investor relations officers, auditors, shareholders and other
people named in the forms that listed companies file with the Brazilian
Securities and Exchange Commission (Comissão de Valores Mobiliários,
CVM). It says what the mirror holds about you, why, for how long and how
to ask for that to change.

Version of 14 November 2026. The Portuguese version
([`PRIVACY.pt-BR.md`](PRIVACY.pt-BR.md)) prevails.

## Who answers for the mirror

The mirror is kept by a private person, with no economic purpose:

- **Responsible for the mirror** (controller, in the sense of art. 5, VI,
  of the Brazilian data protection law, Lei 13.709/2018, the LGPD, and
  also the data protection officer of its art. 41): Sidney da Silva
  Pereira Bissoli.
- **Contact:** <sbissoli76@gmail.com>.

The mirror is not the CVM's and does not speak for it. The CVM remains
responsible for its Open Data Portal, <https://dados.cvm.gov.br/>.

## What the mirror is and where the data comes from

The CVM publishes as open data the forms that listed companies must
file. `cvmdata` is an R package that reads that data. To make reads fast
and reproducible, the package keeps a copy converted to Parquet: the
mirror. Nothing is collected from you or from any other source:
everything comes from the CVM portal.

The mirror lives in two places, both open to anybody:

- **GitHub Releases** of <https://github.com/SidneyBissoli/cvmdata>,
  refreshed every week, with dated snapshots that let the mirror be read
  as it was on a past date.
- **Zenodo**, <https://zenodo.org/>, where quarterly editions will be
  deposited with a permanent identifier (DOI), so that a study can cite
  exactly the data it used.

Both services store files outside Brazil. Zenodo states that files are
kept in CERN data centres, "primarily Geneva, with replicas in Budapest".
GitHub states that it stores and processes data "in a variety of
locations, including your local region, the United States". Read in the
policies of both services on 14 November 2026.

## Which personal data the mirror holds

- **Name**, as the CVM publishes it.
- **Masked CPF** (the Brazilian taxpayer number), as `***.456.789-**`.
  The full number is not held.
- **Year of birth.** The full date is not held.
- **Position, body, election, investiture and term dates, profession**
  and the other fields of the form about the office held.
- **Professional experience and declarations** the form requires, in the
  text the company filed.
- **Shareholdings and relationships** (family, subordination, related
  parties) declared in the forms.
- **City, state and country** of whoever is named as responsible or as a
  contact.

## What the mirror does not hold

The mirror takes out, of what the CVM publishes, what the purpose below
does not need:

- the full CPF and any other identity document;
- the full birth date;
- e-mail, telephone and fax, of people and of companies;
- the street address of people;
- the counts of race, gender and disability declarations of the members
  of each management body (three whole tables);
- in the counts of race, gender and disability of employees, the
  companies in which a group has fewer than 10 people or in which
  everybody declared the same category.

Whoever reads the data straight from the CVM portal, with or without the
package, gets what the CVM publishes. This notice is about the mirror
only.

## What the data is used for

Research, teaching and public scrutiny of the governance of Brazilian
listed companies: who runs and oversees them, for how long, with what
background and with which ties.

That is not the original purpose of the disclosure. The CVM rule has
companies disclose information "useful for the assessment of the
securities" they issue, "to the whole market" (Resolução CVM 80, arts.
17 and 18; our translation), and asks in the reference form for the name,
birth date, profession, CPF, position, terms, professional experience
and convictions of each director and fiscal council member (Annex C,
item 7.3). The study of governance is a new purpose, which the person
responsible understands to be compatible with the original one, under
art. 7, § 7, of the LGPD.

The mirror is not used for decisions about people, advertising,
profiling or the sale of data.

## On what ground

The person responsible understands the processing to rest on legitimate
interest (LGPD, art. 7, IX), his own and that of the researchers who use
the data, over publicly accessible data, whose use must consider "the
purpose, the good faith and the public interest that justified making it
available" (art. 7, § 3), limited to what is strictly necessary (art.
10, § 1). The assessment behind that choice is recorded, in Portuguese,
in
[`data-raw/decisions/cvmdata_lgpd_legitimo_interesse.md`](data-raw/decisions/cvmdata_lgpd_legitimo_interesse.md).

## For how long

- **Current copy:** rebuilt every week from the CVM portal. What the CVM
  corrects or withdraws changes in the current copy at the following
  weekly refresh.
- **Dated snapshots:** keep the mirror as it was on each date, so that
  published results can be reproduced. They have no expiry.
- **Zenodo editions:** Zenodo retains items "for the lifetime of the
  repository". After 30 days from publication it deletes a record only
  "in duly justified cases, such as copyright infringement or exposure
  of personal data", on request to its support; a page with the citation
  stays in its place (read in the Zenodo help and policies on 14 November
  2026). The person responsible commits to making that request when a
  data subject's request is well founded.

## Your rights and how to exercise them

The LGPD (art. 18) gives you the right to ask the person responsible, at
any time and at no cost, for:

- confirmation that the mirror processes data about you;
- access to that data;
- correction of incomplete, inaccurate or outdated data;
- anonymisation, blocking or deletion of data that is unnecessary,
  excessive or processed against the law;
- information on whom the data is shared with;
- to object to the processing, if you understand it breaches the law
  (art. 18, § 2).

**How to ask:** write to <sbissoli76@gmail.com> with your name as it
appears in the forms, the company and what you are asking for. Do not
send your CPF number or a copy of a document in the first message; if it
is necessary to confirm that the request is yours, the way to do it will
be agreed in the reply.

**Deadlines:** a simplified confirmation as soon as possible; the
complete statement within 15 days of the request (art. 19).

**Limits you should know:**

- The data originates in the form filed with the CVM. An error in the
  form is corrected at the source, by the company; the mirror follows
  the correction.
- Files already downloaded by third parties are out of reach.
- Requests are handled by the procedure recorded, in Portuguese, in
  [`data-raw/decisions/cvmdata_lgpd_pedidos_de_titular.md`](data-raw/decisions/cvmdata_lgpd_pedidos_de_titular.md).

You may also petition the Brazilian data protection authority, the
Autoridade Nacional de Proteção de Dados (art. 18, § 1):
<https://www.gov.br/anpd/>.

## Changes to this notice

Changes are published in this file, with the date at the top, and
recorded in the history of the repository.
