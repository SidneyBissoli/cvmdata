# cvm_versions refuses the row filters of cvm_fetch by name

    Code
      cvm_versions("dfp", "dre", year = 2023, basis = "con", reading = "original")
    Condition
      Error in `check_versions_dots()`:
      ! `cvm_versions()` does not take `reading`.
      i `reading`, `from`/`to` and `as_of` select rows of the current reading in `cvm_fetch()`; `cvm_versions()` returns every version of the documents of `year` instead.

# cvm_versions rejects unknown arguments

    Code
      cvm_versions("dfp", "dre", basis = "con", report_type = "con")
    Condition
      Error in `check_versions_dots()`:
      ! Unknown argument: `report_type`.
      i `cvm_versions()` selects issuers with `cnpj` or `ticker`, the period with `year` and the statement basis with `basis`.

# cvm_versions rejects a table without version history

    Code
      cvm_versions("dfp", "submissao", year = 2023)
    Condition
      Error in `check_versioned_table()`:
      ! Table "dfp"/"submissao" has no version history: it returns every row the CVM publishes.
      i `cvm_versions()` applies to the tables that keep a single filing per document, such as the DFP and ITR statements; use `cvm_fetch()` for this one.

