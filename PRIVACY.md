# Privacy notice of the cvmdata data mirror

The `cvmdata` mirror holds data about listed companies, not about
people. This notice is for anyone who still finds their own name
mentioned in a text of the mirror, and says how to ask for it to be
removed.

Version of 15 November 2026. If this text and the Portuguese version
([`PRIVACY.pt-BR.md`](https://sidneybissoli.github.io/cvmdata/PRIVACY.pt-BR.md))
differ, the Portuguese version prevails.

## Who answers for the mirror

The mirror is maintained by a natural person, with no economic purpose:

- **Person responsible for the mirror:** Sidney da Silva Pereira
  Bissoli.
- **Contact:** <sbissoli76@gmail.com>.

The mirror does not belong to the CVM and does not speak for it. The CVM
remains responsible for its Open Data Portal,
<https://dados.cvm.gov.br/>.

## What the mirror is

The Brazilian Securities Commission (Comissão de Valores Mobiliários,
CVM) publishes as open data the forms that listed companies must file.
`cvmdata` is an R package that reads those data. To make reading fast
and reproducible, the package keeps a copy converted to the Parquet
format: the mirror. Everything comes from the CVM portal; nothing is
collected from you or from any other source.

The mirror exists in two places, both open to anyone:

- **GitHub Releases** of the repository
  <https://github.com/SidneyBissoli/cvmdata>, refreshed every week, with
  dated snapshots that let the mirror be read as it stood on a past
  date.
- **Zenodo**, <https://zenodo.org/>, where quarterly editions will be
  deposited with a permanent identifier (DOI).

Both services store files outside Brazil. Zenodo states that files are
kept in CERN data centres, “primarily Geneva, with replicas in
Budapest”. GitHub states that it stores and processes data “in a variety
of locations, including your local region, the United States”. Read in
the policies of both services on 14 November 2026.

## What the mirror does not hold

Since 15 November 2026 the mirror does not carry the tables in which the
CVM describes people:

- board members, fiscal council members and committee members;
- family and subordination ties of board members;
- shareholders and related parties;
- the people who sign the form, the investor relations officer and the
  technical lead of the audit;
- the counts of race, gender and disability declarations of the members
  of each governing body.

In the tables about the company, the columns that name a person are left
out (the officer in charge in the register, the contact person, the
technical lead), and so are e-mails, telephones and faxes, and the row
of an auditor who is a natural person. In the counts of race, gender and
disability of employees, the companies in which a group has fewer than
10 people, or in which everybody declared the same category, are left
out.

Whoever reads that information with the package receives it straight
from the CVM portal, on their own computer. That reading does not go
through the mirror, and this notice does not cover it.

## What may remain about you

A text about the company may mention a person by name: the auditor’s
report, a statement by the officers, the subject of a notice, a remark.
The mirror copies those texts as the CVM publishes them, with one
difference: a CPF number (the Brazilian individual taxpayer number) that
appears in a text is masked (`***.456.789-**`).

The mirror does not gather what is said about a person, and is not used
for decisions about people, advertising, profiling or the sale of data.

## On what ground

The texts serve research, teaching and the public scrutiny of listed
companies. The person responsible understands that the mention of a name
inside them rests on legitimate interest (Lei 13.709/2018, the LGPD,
art. 7, IX), over publicly accessible data, whose use must consider “the
purpose, the good faith and the public interest that justified making it
available” (art. 7, § 3; our translation). Articles read on 14 November
2026.

## How to ask for your name to be removed

Write to <sbissoli76@gmail.com> giving your name as it appears in the
texts and the company. Do not send your CPF number or a copy of a
document in the first message; if it is necessary to confirm that the
request is yours, the way to do so will be agreed in the reply.

Every request from somebody who shows to be the person, or their
representative, is honoured, with no need to give a reason. The name
then reads `[omitido a pedido do titular]` (“omitted at the request of
the data subject”) in the texts of the current copy of the mirror, at
the weekly refresh that follows the handling of the request.

You can also ask for confirmation that the mirror mentions your name and
for access to those passages (LGPD, art. 18). Confirmation is given as
soon as possible; the full answer, within 15 days of the request (art.
19).

**Limits you should know:**

- The original text remains on the CVM portal. A request about the
  origin is made to the company or to the CVM.
- **Dated snapshots and Zenodo editions already published may go on
  mentioning the name.** The mirror is maintained by one person, and
  this notice does not promise what that person may be unable to
  deliver. Dated snapshots can be rebuilt, but that is not automatic. On
  Zenodo, after 30 days from publication, removing a record is not up to
  the person responsible: it depends on a request to the service’s
  support, which accepts it only “in duly justified cases, such as
  copyright infringement or exposure of personal data” (read in the
  Zenodo help on 14 November 2026). The answer to your request will say
  what was done and what was not possible.
- Files already downloaded by third parties are beyond the reach of the
  person responsible.
- Requests are handled by the procedure recorded in
  [`data-raw/decisions/cvmdata_lgpd_pedidos_de_titular.md`](https://github.com/SidneyBissoli/cvmdata/blob/main/data-raw/decisions/cvmdata_lgpd_pedidos_de_titular.md)
  (in Portuguese).

You can also petition the Brazilian data protection authority, the
Autoridade Nacional de Proteção de Dados (art. 18, § 1):
<https://www.gov.br/anpd/>.

## Changes to this notice

Changes are published in this file, with the date at the top, and
recorded in the history of the repository.
