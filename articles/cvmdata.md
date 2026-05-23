# Introduction to cvmdata

`cvmdata` provides a tidy API to the open data published by the
Brazilian Securities and Exchange Commission (CVM — *Comissão de Valores
Mobiliários*). The package fetches official CSV releases from the CVM
portal at <https://dados.cvm.gov.br/>, parses them respecting the
upstream encoding (ISO-8859-1) and the published field conventions, and
returns tibbles whose table names, column names and categorical values
are preserved in Portuguese exactly as published by CVM. Function names,
arguments and metadata attributes are in English, following rOpenSci and
tidyverse conventions.

This first vignette demonstrates the simplest entry point —
[`cad_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cad_fetch.md),
which returns the current snapshot of the *Cadastro de Companhias
Abertas* (registry of publicly-traded companies). Because this call hits
the live CVM portal, the chunk runs only in interactive sessions.

``` r

library(cvmdata)
library(dplyr)

companies <- cad_fetch()
glimpse(companies)
```

Every tibble returned by a `cvmdata` fetcher carries five provenance
attributes — `source`, `fetched_at`, `dataset`, `table` and
`package_version` — which are displayed when the tibble is printed.

Subsequent releases will add vignettes covering the quarterly and annual
financial statements (`itr`, `dfp`), the reference form (`fre`,
including ESG/governance tables), and the cache/mirror architecture.
