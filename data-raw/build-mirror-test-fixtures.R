# Build small parquet fixtures used by tests/testthat/test-source-mirror-*.R.
#
# Outputs:
#   tests/testthat/fixtures/mirror-cad-companhias.parquet
#     - the same 50-row CAD sample as cad_sample.csv after the package
#       transform pipeline (no transformations declared for CAD).
#   tests/testthat/fixtures/mirror-dfp-bpa-ind-2024.parquet
#     - a small subset of the DFP fixture: bpa ind 2024 after
#       apply_schema_transformations() (multiply_by_scale +
#       keep_latest_version).
#
# Run with `Rscript data-raw/build-mirror-test-fixtures.R` from the
# package root. Idempotent — overwrites any pre-existing fixtures.

stopifnot(requireNamespace("devtools", quietly = TRUE))
stopifnot(requireNamespace("DBI", quietly = TRUE))
stopifnot(requireNamespace("duckdb", quietly = TRUE))

devtools::load_all(quiet = TRUE)
options(cvmdata.cache_dir = file.path(tempdir(), "cvmdata-build-fixtures"))

write_parquet_via_duckdb <- function(df, path) {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbWriteTable(con, "t", df, overwrite = TRUE)
  DBI::dbExecute(
    con,
    sprintf(
      "COPY (SELECT * FROM t) TO '%s' (FORMAT 'parquet', COMPRESSION 'snappy')",
      gsub("\\\\", "/", path, fixed = FALSE)
    )
  )
  invisible(path)
}

# CAD ---------------------------------------------------------------------

cad_schema <- cvmdata:::load_schema("cad", "companhias")
cad_df <- cvmdata:::read_cvm_csv(
  "tests/testthat/fixtures/cad_sample.csv",
  cad_schema,
  validate = "skip"
)
cad_df <- cvmdata:::apply_schema_transformations(cad_df, cad_schema)

cad_out <- "tests/testthat/fixtures/mirror-cad-companhias.parquet"
write_parquet_via_duckdb(cad_df, cad_out)
cat(sprintf("[fixture] %s  %d rows, %s bytes\n",
            cad_out, nrow(cad_df), format(file.info(cad_out)$size)))

# DFP BPA ind 2024 --------------------------------------------------------

dfp_schema <- cvmdata:::load_schema("dfp", "bpa")
# Stage the fixture ZIP into a fake cache, then run the package
# pipeline against it so the resulting parquet matches what the ETL
# would publish (post-transformations, no companies filter).
fixt_zip <- "tests/testthat/fixtures/dfp_cia_aberta_2024.zip"
cache_root <- file.path(tempdir(), "cvmdata-build-fixtures-cache")
raw_dir <- file.path(cache_root, "raw", "dfp", "2024")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
file.copy(fixt_zip, file.path(raw_dir, basename(fixt_zip)),
          overwrite = TRUE)
saveRDS(
  list(
    etag = '"fixture-etag"',
    last_modified = "Mon, 19 May 2026 00:00:00 GMT",
    fetched_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
  ),
  file.path(raw_dir, paste0(basename(fixt_zip), ".etag.rds"))
)
withr::with_options(
  list(
    cvmdata.cache_dir = cache_root,
    cvmdata.cache_ttl_seconds = Inf
  ),
  {
    bpa <- issuer_fetch("dfp", "bpa",
                     report_type = "ind", year = 2024, source = "cvm")
  }
)
# Strip the cvm_tbl class + provenance attrs so the parquet body is a
# plain table — the mirror reader reattaches its own attrs from the
# parsed asset name.
attr(bpa, "source") <- NULL
attr(bpa, "fetched_at") <- NULL
attr(bpa, "dataset") <- NULL
attr(bpa, "table") <- NULL
attr(bpa, "package_version") <- NULL
class(bpa) <- setdiff(class(bpa), "cvm_tbl")

bpa_out <- "tests/testthat/fixtures/mirror-dfp-bpa-ind-2024.parquet"
write_parquet_via_duckdb(bpa, bpa_out)
cat(sprintf("[fixture] %s  %d rows, %s bytes\n",
            bpa_out, nrow(bpa), format(file.info(bpa_out)$size)))
