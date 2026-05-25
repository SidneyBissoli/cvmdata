# Package index

## Fetchers

Functions to retrieve any CVM open-data table covered by the package.

- [`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)
  : Fetch a CVM open-data table for an issuer dataset

## Cache

Inspect and manage the on-disk cache of downloaded artifacts. The TTL
window for HTTP revalidation is configurable via the
`cvmdata.cache_ttl_seconds` option (default 30 days).

- [`cvm_cache_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_path.md)
  : Path to the cvmdata cache directory
- [`cvm_cache_set_path()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_set_path.md)
  : Set the cvmdata cache directory
- [`cvm_cache_info()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_info.md)
  : Inventory of files in the cvmdata cache
- [`cvm_cache_clear()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_clear.md)
  : Clear cached files

## Source backend

Configure which backend
[`issuer_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/issuer_fetch.md)
queries (direct CVM portal or the parquet mirror published in GitHub
Releases).

- [`cvm_source_get()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_get.md)
  : Get the active cvmdata source backend
- [`cvm_source_set()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_source_set.md)
  : Set the active cvmdata source backend

## Discovery

Browse the datasets, tables, dictionaries and code lists carried by the
package.

- [`cvm_datasets()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_datasets.md)
  : List datasets covered by the package
- [`cvm_tables()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_tables.md)
  : List the tables published in a dataset
- [`cvm_dictionary()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dictionary.md)
  : Look up the CVM-published dictionary for a table
- [`cvm_codelist()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_codelist.md)
  : Look up the codelist for a categorical column
- [`cvm_dataset_years()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_dataset_years.md)
  : Range of years available for a yearly-partitioned dataset

## Utilities

CNPJ formatting helpers.

- [`cnpj_clean()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_clean.md)
  : Strip punctuation from a CNPJ vector
- [`cnpj_format()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_format.md)
  : Format a CNPJ vector with the canonical punctuation
