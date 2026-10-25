# no-match error quotes the skip manifest when it covers the year

    Code
      httr2::with_mocked_responses(mock, issuer_fetch("dfp", "bpa", report_type = "ind",
        year = 2025L, source = "mirror"))
    Condition
      Error in `source_mirror_duckdb_get()`:
      ! No parquet assets match "dfp"/"bpa" in the mirror.
      i Searched release "mirror-companhias-dfp-latest" for `year = 2025` `report_type = "ind"`.
      i 2025 (ind): the CVM publishes the CSV with the header only (recorded by the mirror ETL as "empty").
      i Otherwise, the CVM may not publish the table for that year (a table can start later or stop earlier than its dataset), or the mirror may not have it yet; `source = "cvm"` reads the portal directly.

