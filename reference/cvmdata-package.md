# cvmdata: Tidy Access to Brazilian CVM Open Data

Provides a tidy API to the open data published by the Brazilian
Securities and Exchange Commission ('CVM' - Comissao de Valores
Mobiliarios) on listed companies: the company register, annual and
quarterly financial statements, the reference form, the registration
form, the corporate governance code report, insider trading positions,
share buyback programmes and the index of periodic filings. Resolves
resubmitted filings, returns the original and the restated figures of a
fiscal year, applies the currency scale and checks every file against
the regulator's data dictionary. Column names, table names, categorical
values and free text are preserved in Portuguese as published by 'CVM';
function names, arguments and metadata attributes are in English. By
default data is read from a weekly refreshed 'Parquet' mirror maintained
by the package author in 'GitHub' Releases, with dated snapshots; the
official portal can be read directly instead. The mirror carries data
about companies; the tables that describe natural persons are read from
the portal.

## See also

Useful links:

- <https://github.com/SidneyBissoli/cvmdata>

- <https://sidneybissoli.github.io/cvmdata/>

- Report bugs at <https://github.com/SidneyBissoli/cvmdata/issues>

## Author

**Maintainer**: Sidney da Silva Pereira Bissoli <sbissoli76@gmail.com>
([ORCID](https://orcid.org/0009-0001-0442-3700))

Authors:

- Sidney da Silva Pereira Bissoli <sbissoli76@gmail.com>
  ([ORCID](https://orcid.org/0009-0001-0442-3700))
