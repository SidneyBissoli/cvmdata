# data-raw

Scripts used to build artefacts under `inst/extdata/` — the CVM
dictionary snapshot (`cvm_dictionary_snapshot.csv`), the empirical
codelists snapshot (`cvm_codelists_snapshot.csv`) and the hash
inventories used by the periodic update workflow.

The schema YAMLs under `inst/extdata/schemas/` are **not** built here:
they are hand-written and are the source of truth. The dictionary
snapshot is derived from them (`build-dictionary-snapshot.R` follows
each YAML's `cvm_dictionary_url`, and copies `expected_field_names`
for tables with `meta_status: missing`). The contract between the two
is pinned by `tests/testthat/test-schema-snapshot-consistency.R`.

This directory is excluded from the package tarball via `.Rbuildignore`.
