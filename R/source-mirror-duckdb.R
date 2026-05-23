# Mirror backend (Phase F of the roadmap).
#
# The real implementation queries parquet snapshots in GitHub Releases
# via DuckDB HTTP range requests with year-partition filter pushdown,
# so that `cvm_fetch(dataset, table, years = 2020:2024, companies = ...)`
# downloads only the bytes that satisfy the predicate.
#
# Until that work lands (Sessão 3.13), `source = "mirror"` aborts with
# an actionable instruction. Keeping the entry point in its own file
# means the eventual implementation drops in without touching the
# dispatch site in `cvm_fetch_internal()` more than once.

# Internal: dispatch entry point for the mirror backend.
# Signature mirrors `source_cvm_http_get()` so the future swap is local.
source_mirror_duckdb_get <- function(schema, year = NULL, ...) {
  cvmdata_abort(
    c(
      "{.code source = \"mirror\"} is not available in this release.",
      "i" = paste(
        "Run {.run cvm_source_set(\"cvm\")} or pass",
        "{.code source = \"cvm\"} explicitly until the GitHub Releases",
        "parquet mirror ships in {.pkg cvmdata} v0.1.0."
      )
    ),
    class = "cvmdata_error_input"
  )
}
