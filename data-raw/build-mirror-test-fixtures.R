# Build small fixtures used by tests/testthat/.
#
# Mirror fixtures (parquet, consumed by test-source-mirror-*.R):
#   tests/testthat/fixtures/mirror-cad-companhias.parquet
#     - the same 50-row CAD sample as cad_sample.csv after the package
#       transform pipeline (no transformations declared for CAD).
#   tests/testthat/fixtures/mirror-dfp-bpa-ind-2024.parquet
#     - a small subset of the DFP fixture: bpa ind 2024 after
#       apply_schema_transformations() (multiply_by_scale +
#       keep_latest_version).
#
# Raw ZIP fixtures (consumed by test-issuer-fetch-*.R via mocked HTTP +
# `local_prepare_*_cache()` helpers):
#   tests/testthat/fixtures/cgvn_cia_aberta_2024.zip
#     - subset of CGVN 2024 to BCO BRASIL + MAGAZINE LUIZA, repacked
#       to keep the fixture under 200 KB. Built on demand here because
#       v0.2 Sessao 10 introduced the dataset; pre-existing raw ZIPs
#       (dfp/itr/fre) were committed manually before this script
#       existed.
#
# Run with `Rscript data-raw/build-mirror-test-fixtures.R` from the
# package root. Idempotent — overwrites any pre-existing fixtures.
# CGVN raw-fixture step requires network access to the CVM portal.

stopifnot(requireNamespace("devtools", quietly = TRUE))
stopifnot(requireNamespace("DBI", quietly = TRUE))
stopifnot(requireNamespace("duckdb", quietly = TRUE))
stopifnot(requireNamespace("httr2", quietly = TRUE))
stopifnot(requireNamespace("jsonlite", quietly = TRUE))

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

# CGVN raw ZIP fixture (Sessao 10) ----------------------------------------
# Downloads the real 2024 ZIP from the CVM portal, filters submissao +
# praticas to BCO BRASIL + MAGAZINE LUIZA, repacks as a small fixture.
# Subset uses CNPJ_Companhia because the praticas CSV does not carry
# Codigo_CVM (lookup CD_CVM -> CNPJ would normally go through the
# submissao path; here we filter directly on CNPJ for fixture size).

build_cgvn_raw_fixture <- function() {
  cgvn_url <- paste0(
    "https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/CGVN/DADOS/",
    "cgvn_cia_aberta_2024.zip"
  )
  out_zip <- "tests/testthat/fixtures/cgvn_cia_aberta_2024.zip"
  out_meta <- paste0(out_zip, ".meta.json")

  # Companies kept in the subset (same pair used in DFP/ITR/FRE
  # fixtures for cross-test coherence).
  keep_cnpjs <- c("00.000.000/0001-91", "47.960.950/0001-21")
  keep_meta <- list(
    list(cd_cvm = "001023", cnpj_companhia = "00.000.000/0001-91",
         nome_empresarial = "BCO BRASIL S.A."),
    list(cd_cvm = "022470", cnpj_companhia = "47.960.950/0001-21",
         nome_empresarial = "MAGAZINE LUIZA S.A.")
  )

  stage <- tempfile("cgvn_fixture_")
  dir.create(stage, recursive = TRUE)
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)

  zip_local <- file.path(stage, "cgvn_cia_aberta_2024.zip")
  cat(sprintf("[cgvn] Downloading %s\n", cgvn_url))
  resp <- httr2::req_perform(
    httr2::req_timeout(httr2::request(cgvn_url), 300L)
  )
  writeBin(httr2::resp_body_raw(resp), zip_local)

  extract_dir <- file.path(stage, "extract")
  dir.create(extract_dir)
  utils::unzip(zip_local, exdir = extract_dir)

  subset_csv <- function(name, cnpj_col) {
    path <- file.path(extract_dir, name)
    if (!file.exists(path)) {
      stop(sprintf("Expected CSV not found in CGVN ZIP: %s", name))
    }
    # Read whole file as character to preserve every byte; filter; write
    # back with the same encoding/delimiter.
    raw <- readBin(path, "raw", n = file.info(path)$size)
    txt <- iconv(rawToChar(raw), from = "ISO-8859-1", to = "UTF-8")
    lines <- strsplit(txt, "\r?\n", perl = TRUE)[[1L]]
    header <- lines[1L]
    cols <- strsplit(header, ";", fixed = TRUE)[[1L]]
    idx <- which(tolower(cols) == cnpj_col)
    if (!length(idx)) {
      stop(sprintf("CNPJ column %s not found in %s", cnpj_col, name))
    }
    body <- lines[-1L]
    body <- body[nzchar(body)]
    fields <- strsplit(body, ";", fixed = TRUE)
    cnpjs <- vapply(fields, function(f) {
      if (length(f) >= idx) f[idx] else NA_character_
    }, character(1L))
    keep_mask <- cnpjs %in% keep_cnpjs
    kept <- c(header, body[keep_mask])
    out <- file.path(extract_dir, paste0("subset_", name))
    out_raw <- charToRaw(
      iconv(paste(kept, collapse = "\r\n"),
            from = "UTF-8", to = "ISO-8859-1")
    )
    writeBin(out_raw, out)
    list(path = out, n_rows = sum(keep_mask))
  }

  sub_info <- subset_csv("cgvn_cia_aberta_2024.csv", "cnpj_companhia")
  prat_info <- subset_csv("cgvn_cia_aberta_praticas_2024.csv",
                          "cnpj_companhia")

  # Repack: only the two filtered CSVs (renamed back to canonical).
  pack_dir <- file.path(stage, "pack")
  dir.create(pack_dir)
  file.copy(sub_info$path,
            file.path(pack_dir, "cgvn_cia_aberta_2024.csv"),
            overwrite = TRUE)
  file.copy(prat_info$path,
            file.path(pack_dir, "cgvn_cia_aberta_praticas_2024.csv"),
            overwrite = TRUE)

  if (file.exists(out_zip)) file.remove(out_zip)
  # zip writes relative to the pack_dir we cd into, so the zipfile arg
  # must be an absolute path before the with_dir; computing it after
  # with_dir would resolve it under pack_dir and silently fail on
  # Windows when intermediate parent dirs don't exist there.
  out_zip_abs <- file.path(
    normalizePath(dirname(out_zip), winslash = "/", mustWork = TRUE),
    basename(out_zip)
  )
  withr::with_dir(pack_dir, {
    utils::zip(
      zipfile = out_zip_abs,
      files = list.files("."),
      flags = "-q9X"
    )
  })

  meta <- list(
    source_url = cgvn_url,
    fetched_at = format(Sys.Date()),
    companies_included = keep_meta,
    files_included = c(
      "cgvn_cia_aberta_2024.csv",
      "cgvn_cia_aberta_praticas_2024.csv"
    ),
    notes = paste(
      "Subset filtered by CNPJ_Companhia (BCO BRASIL + MAGAZINE LUIZA).",
      "ISO-8859-1 encoding preserved.",
      "Built from the 2024 yearly archive (Sessao 10, v0.2).",
      "praticas keeps all 54 ID_Item rows per company per filing,",
      "covering the 4 valid Pratica_Adotada categories",
      "(Sim, Nao, Parcialmente, Nao se Aplica)."
    )
  )
  writeLines(
    jsonlite::toJSON(meta, pretty = TRUE, auto_unbox = TRUE),
    out_meta
  )

  cat(sprintf("[fixture] %s  %s bytes\n",
              out_zip, format(file.info(out_zip)$size)))
  cat(sprintf("[fixture] submissao subset: %d rows; praticas: %d rows\n",
              sub_info$n_rows, prat_info$n_rows))
  cat(sprintf("[fixture] %s\n", out_meta))
}

build_cgvn_raw_fixture()
