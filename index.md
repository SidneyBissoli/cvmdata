# cvmdata

`cvmdata` provides a tidy API to the open data published by the
Brazilian Securities and Exchange Commission (CVM — Comissão de Valores
Mobiliários). The first release covers the core publicly-traded-company
datasets: company registry (`cad`), quarterly financial statements
(`itr`), annual financial statements (`dfp`) and the reference form
(`fre`), the latter including ESG/governance tables on board diversity,
compensation and shareholder structure.

The package preserves table names, column names, categorical values and
free text in Portuguese exactly as CVM publishes them. Function names,
arguments and metadata attributes follow English-language rOpenSci and
tidyverse conventions.

## Installation

`cvmdata` is not yet on CRAN. The development version can be installed
from GitHub:

``` r

# install.packages("pak")
pak::pak("SidneyBissoli/cvmdata")
```

## Quick start

``` r

library(cvmdata)

# Fetch the full company registry (single snapshot, no temporal partitioning)
companies <- cad_fetch()
```

## Data provenance

Data is fetched from the official CVM Open Data Portal
(<https://dados.cvm.gov.br/>). A package-managed mirror on GitHub
Releases serves as automatic fallback when an upstream file becomes
unavailable. Every returned tibble carries provenance attributes
(`source`, `fetched_at`, `dataset`, `table`, `package_version`).

## License

MIT © Sidney da Silva Pereira Bissoli.
