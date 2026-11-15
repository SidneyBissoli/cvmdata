# Data licence and attribution

The code of the `cvmdata` package is released under the MIT licence (see
[`LICENSE.md`](https://github.com/SidneyBissoli/cvmdata/blob/main/LICENSE.md)).
The **data** the package serves is not the package’s own and has a
licence of its own.

## Source

Every table served by `cvmdata` originates from the Open Data Portal of
the Comissão de Valores Mobiliários (CVM), the Brazilian Securities and
Exchange Commission: <https://dados.cvm.gov.br/>. The package either
reads the portal directly (`source = "cvm"`) or reads a mirror of it
(`source = "mirror"`, the default).

## Licence of the data

The CVM publishes every dataset the package covers under the **Open Data
Commons Open Database License (ODbL) v1.0**:
<https://opendatacommons.org/licenses/odbl/1-0/>. The licence is
declared per dataset on the portal (field “Licença” of each dataset
page; `license_id: odc-odbl` in the CKAN API). Checked on 2026-10-24 for
the eight datasets the package covers: `cia_aberta-cad`,
`cia_aberta-doc-fca`, `cia_aberta-doc-dfp`, `cia_aberta-doc-itr`,
`cia_aberta-doc-fre`, `cia_aberta-doc-cgvn`, `cia_aberta-doc-vlmo` and
`cia_aberta-doc-ipe`.

## The mirror is a derivative database

The Parquet files published in this repository’s GitHub Releases (tags
`mirror-<group>-<dataset>-latest`) are produced from the CVM CSV files
by the ETL under `inst/etl/`: the content is the CVM’s, re-encoded
(UTF-8), typed according to the CVM’s own data dictionary and
partitioned by year. They are a *derivative database* in the terms of
the ODbL and are redistributed **under the same licence, ODbL v1.0**, as
the licence requires.

Attribution for the mirror and for anything you derive from it:

> Contains data from the Comissão de Valores Mobiliários (CVM) Open Data
> Portal, <https://dados.cvm.gov.br/>, made available under the Open
> Data Commons Open Database License (ODbL) v1.0. Mirrored and converted
> to Parquet by the `cvmdata` R package,
> <https://github.com/SidneyBissoli/cvmdata>.

## Personal data

The mirror carries data about companies, not about people. The tables in
which the CVM describes natural persons are not redistributed: in the
FRE, `administrador_membro_conselho_fiscal`, `membro_comite`,
`relacao_familiar`, `relacao_subordinacao`, `responsavel`,
`auditor_responsavel`, `posicao_acionaria`,
`posicao_acionaria_classe_acao`, `transacao_parte_relacionada`,
`administrador_declaracao_genero`, `administrador_declaracao_raca` and
`administrador_PCD`; in the FCA, `dri`. The package reads them from the
CVM, on the user’s machine. In the tables that stay, the columns that
name a person are left out (the officer in charge in the `cad`, the
contact of `fca/departamento_acionistas`, the technical lead in
`fca/auditor`), a row of an auditor who is a natural person is left out,
every CPF that a text mentions is masked as `***.456.789-**`, and the
columns of e-mail, telephone and fax are not carried. The five workforce
tables that count employees by race, gender or disability come without
the companies that, in a year, have a group of fewer than 10 people or a
group in which everybody declared the same category, so totals computed
from them are lower than the CVM’s.

A text about a company (an auditor’s report, the subject of a filing, a
note) may still mention somebody by name. That is personal data under
the Brazilian LGPD (Lei 13.709/2018) wherever you read it from: its open
publication does not free you from respecting the purpose of the
disclosure.

A person so mentioned can ask to leave the mirror: the name then reads
`[omitido a pedido do titular]` wherever a text of the mirror mentions
it. The file of the CVM is not changed by this.

**The ODbL does not license the personal data.** The licence governs the
rights over the database and says so itself (section 2.4): “The
individual items of the Contents contained in this Database may be
covered by other rights, including copyright, patent, data protection,
privacy, or personality rights, and this License does not cover any
rights (other than Database Rights or in contract) in individual
Contents contained in the Database.” What you do with the names and the
other personal data in these tables is your own processing of personal
data: you answer for it under the law that applies to you (in Brazil,
the LGPD), and the permissions listed below do not extend to it.

If a text of the mirror mentions you, the privacy notice says who
answers for it and how to ask for your name to be removed:
[`PRIVACY.md`](https://sidneybissoli.github.io/cvmdata/PRIVACY.md),
[`PRIVACY.pt-BR.md`](https://sidneybissoli.github.io/cvmdata/PRIVACY.pt-BR.md).

## What this means for you

In short (the licence text prevails):

- You may use, copy, redistribute and adapt the data, including
  commercially.
- You must attribute the CVM as the source and keep the licence notice
  when you redistribute the data or a database derived from it.
- A database you derive from it and publicly redistribute must be
  offered under the ODbL as well. Works *produced* from the data
  (charts, papers, models, aggregates that are not themselves a
  database) are not bound by that clause, but must carry the notice.
- You may not impose technological restrictions on the data beyond those
  of the licence.

The package does not alter any value published by the CVM. Every tibble
it returns carries provenance attributes (`source`, `fetched_at`,
`group`, `dataset`, `table`, `package_version`) so that the origin of
each result can be audited.
