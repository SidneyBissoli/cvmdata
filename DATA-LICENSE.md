# Data licence and attribution

The code of the `cvmdata` package is released under the MIT licence (see
`LICENSE.md`). The **data** the package serves is not the package’s own
and has a licence of its own.

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

The mirror departs from the CVM in one respect. Full CPFs, birth dates
and contact data are not redistributed: every CPF is masked as
`***.456.789-**`, a foreign document in a CPF column becomes `***`,
`data_nascimento` becomes the year, in `ano_nascimento`, and the columns
of e-mail, telephone and fax (of people and of companies) and of the
street address of a person are left out. Three tables of the FRE are not
redistributed either: the counts of gender, race and disability
declarations of board members by body
(`administrador_declaracao_genero`, `administrador_declaracao_raca`,
`administrador_PCD`), which in a small or unanimous body tell the
declaration of each named member. The five workforce tables that count
employees by race, gender or disability come without the companies that,
in a year, have a group of fewer than 10 people or a group in which
everybody declared the same category, so totals computed from them are
lower than the CVM’s. Names and biographies stay as published. These are
personal data under the Brazilian LGPD (Lei 13.709/2018) wherever you
read them from: their open publication does not free you from respecting
the purpose of the disclosure.

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
