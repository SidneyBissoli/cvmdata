# End-to-end tests for issuer_fetch() against the v0.2 IPE dataset
# (Informacoes Periodicas e Eventuais — the manifest of every periodic
# and eventual document a company filed with the CVM). Mocks the HTTP
# layer with httr2::with_mocked_responses + a local fixture ZIP,
# matching the pattern used for CGVN/VLMO/FCA/DFP/ITR/FRE.
#
# IPE is the simplest v0.2 surface: a single-table manifest, no
# submissao, Codigo_CVM native (CD_CVM filters match directly, with no
# submissao bridge), event-per-row (no dedup by version), Link_Download
# returned as a plain URL (OCR / PDF download out of scope).

# Helpers ----------------------------------------------------------------

local_prepare_ipe_cache <- function(envir = parent.frame()) {
  cache_root <- withr::local_tempdir(.local_envir = envir)
  withr::local_options(
    cvmdata.cache_dir = cache_root,
    .local_envir = envir
  )
  # The ticker lookup table is session-cached; clear it so each test
  # reads from this test's freshly-staged fixtures.
  cvmdata:::ticker_lookup_cache_clear()
  withr::defer(cvmdata:::ticker_lookup_cache_clear(), envir = envir)
  raw_dir <- file.path(cache_root, "raw", "companhias", "ipe", "2024")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  file.copy(
    test_path("fixtures", "ipe_cia_aberta_2024.zip"),
    file.path(raw_dir, "ipe_cia_aberta_2024.zip")
  )
  saveRDS(
    list(
      etag = "\"fixture-etag\"",
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = "2026-05-19T00:00:00.000Z"
    ),
    file.path(raw_dir, "ipe_cia_aberta_2024.zip.etag.rds")
  )
  cache_root
}

# Stage the FCA fixture into an existing cache root so the B3 ticker
# lookup (fca/valor_mobiliario) resolves offline against it.
stage_fca_into_cache <- function(cache_root) {
  raw_dir <- file.path(cache_root, "raw", "companhias", "fca", "2024")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  file.copy(
    test_path("fixtures", "fca_cia_aberta_2024.zip"),
    file.path(raw_dir, "fca_cia_aberta_2024.zip")
  )
  saveRDS(
    list(
      etag = "\"fixture-etag\"",
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = "2026-05-19T00:00:00.000Z"
    ),
    file.path(raw_dir, "fca_cia_aberta_2024.zip.etag.rds")
  )
  invisible(cache_root)
}

fresh_head_response <- function() {
  httr2::response(
    status_code = 200L,
    headers = list(
      "ETag" = "\"fixture-etag\"",
      "Last-Modified" = "Mon, 19 May 2026 00:00:00 GMT"
    )
  )
}

# Tracer -------------------------------------------------------------

test_that("issuer_fetch IPE tracer returns cvm_tbl", {
  skip_if_not_installed("httptest2")
  local_prepare_ipe_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("ipe", "ipe", year = 2024L, source = "cvm")
  )

  expect_s3_class(result, "cvm_tbl")
  expect_s3_class(result, "tbl_df")
  expect_identical(attr(result, "source"), "cvm")
  expect_identical(attr(result, "group"), "companhias")
  expect_identical(attr(result, "dataset"), "ipe")
  expect_identical(attr(result, "table"), "ipe")
  expect_true(nrow(result) > 0L)
  expect_identical(ncol(result), 13L)
  # FRE-detail-like convention with Codigo_CVM native in the header.
  expect_true(all(c("cnpj_companhia", "data_referencia", "codigo_cvm",
                    "categoria", "protocolo_entrega", "versao",
                    "link_download") %in% names(result)))
  expect_type(result$cnpj_companhia, "character")
  expect_type(result$codigo_cvm, "character")
  expect_type(result$protocolo_entrega, "character")
  expect_type(result$link_download, "character")
  expect_s3_class(result$data_referencia, "Date")
})

# Filtering by issuer -------------------------------------------------

test_that("issuer_fetch IPE filters by CNPJ via cnpj_companhia", {
  skip_if_not_installed("httptest2")
  local_prepare_ipe_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("ipe", "ipe", issuer = "00.000.000/0001-91",
                 year = 2024L, source = "cvm")
  )
  expect_true(nrow(result) > 0L)
  expect_true(all(result$cnpj_companhia == "00.000.000/0001-91"))
})

test_that("IPE supports slicing the returned tibble by Categoria", {
  # The recommended pattern for the manifest: fetch, then dplyr::filter
  # on `categoria`. "Fato Relevante" is present for the fixture pair.
  skip_if_not_installed("httptest2")
  skip_if_not_installed("dplyr")
  local_prepare_ipe_cache()

  out <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("ipe", "ipe", year = 2024L, source = "cvm")
  )
  fr <- dplyr::filter(out, categoria == "Fato Relevante")
  expect_true(nrow(fr) > 0L)
  expect_true(all(fr$categoria == "Fato Relevante"))
})

# CD_CVM lookup is direct (Codigo_CVM is native; no submissao) --------

test_that("IPE resolves CD_CVM directly, padded and unpadded", {
  skip_if_not_installed("httptest2")
  local_prepare_ipe_cache()

  padded <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("ipe", "ipe", issuer = "001023",
                 year = 2024L, source = "cvm")
  )
  expect_true(nrow(padded) > 0L)
  expect_true(all(padded$cnpj_companhia == "00.000.000/0001-91"))

  unpadded <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("ipe", "ipe", issuer = "1023",
                 year = 2024L, source = "cvm")
  )
  expect_identical(nrow(unpadded), nrow(padded))
})

test_that("IPE CD_CVM lookup does not go through submissao", {
  # IPE carries codigo_cvm natively, so the resolver must NOT emit the
  # "Resolving CD_CVM ... via submissao" message (IPE has no submissao).
  skip_if_not_installed("httptest2")
  local_prepare_ipe_cache()

  expect_no_message(
    httr2::with_mocked_responses(
      function(req) fresh_head_response(),
      issuer_fetch("ipe", "ipe", issuer = "001023",
                   year = 2024L, source = "cvm")
    ),
    message = "via .*submissao"
  )
})

# No dedup by version (event-per-row manifest) ------------------------

test_that("ipe/ipe declares no keep_latest_version", {
  # The manifest is event-per-row: re-submissions and distinct VERSAO of
  # the same document must all survive. The schema declares no
  # transformation, so apply_schema_transformations is a no-op. Contrast
  # with a submissao schema, which keeps only the highest version.
  schema <- load_schema("ipe", "ipe")
  expect_length(schema$transformations, 0L)

  df <- data.frame(
    cnpj_companhia = rep("00.000.000/0001-91", 3L),
    data_referencia = as.Date(rep("2024-03-31", 3L)),
    categoria = rep("Fato Relevante", 3L),
    protocolo_entrega = c("A1", "A2", "A3"),
    versao = c(1L, 2L, 3L),
    stringsAsFactors = FALSE
  )
  out <- cvmdata:::apply_schema_transformations(df, schema)
  expect_equal(nrow(out), 3L)
  expect_setequal(out$versao, c(1L, 2L, 3L))

  # Sanity: a deduping schema WOULD collapse the same rows to the latest
  # version, proving the difference is the missing transform.
  sub_schema <- load_schema("vlmo", "submissao")
  collapsed <- cvmdata:::apply_schema_transformations(df, sub_schema)
  expect_equal(nrow(collapsed), 1L)
  expect_identical(collapsed$versao, 3L)
})

# Ticker lookup (bonus from Sessao 12: fires for any dataset) ---------

test_that("IPE resolves a B3 ticker to its issuer via fca", {
  skip_if_not_installed("httptest2")
  cache_root <- local_prepare_ipe_cache()
  stage_fca_into_cache(cache_root)

  # BBAS3 is BCO BRASIL's ticker in the FCA fixture's valor_mobiliario;
  # the lookup resolves it to the CNPJ, which then matches the IPE rows.
  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("ipe", "ipe", issuer = "BBAS3",
                 year = 2024L, source = "cvm")
  )
  expect_true(nrow(result) > 0L)
  expect_true(all(result$cnpj_companhia == "00.000.000/0001-91"))
})

# report_type rejection ----------------------------------------------

test_that("report_type aborts for ipe/ipe", {
  skip_if_not_installed("httptest2")
  local_prepare_ipe_cache()
  expect_error(
    httr2::with_mocked_responses(
      function(req) fresh_head_response(),
      issuer_fetch("ipe", "ipe", year = 2024L,
                   source = "cvm", report_type = "ind")
    ),
    class = "cvmdata_error_input"
  )
})

# Schema + discovery -------------------------------------------------

test_that("load_schema accepts the IPE YAML", {
  s <- load_schema("ipe", "ipe")
  expect_s3_class(s, "cvm_table_schema")
  expect_identical(s$temporal_partitioning, "yearly")
  expect_equal(s$first_year, 2021)
  expect_equal(s$expected_field_count, 13)
  expect_identical(s$cvm_file_pattern, "ipe_cia_aberta_{year}.csv")
  # Flat .txt META (no zip): the URL has no `#entry` fragment.
  expect_false(grepl("#", s$cvm_dictionary_url, fixed = TRUE))
  # Event-per-row: no transformations declared.
  expect_length(s$transformations, 0L)
})

test_that("cvm_datasets includes ipe", {
  expect_true("ipe" %in% cvm_datasets())
  expect_true("ipe" %in% cvm_datasets(group = "companhias"))
})

test_that("cvm_tables('ipe') lists the single manifest table", {
  expect_setequal(cvm_tables("ipe"), "ipe")
})

test_that("cvm_dataset_years('ipe') includes 2024", {
  skip_if_not_installed("httptest2")
  # Mock the CVM directory listing so year discovery is offline.
  listing_html <- paste0(
    "<a href='ipe_cia_aberta_2021.zip'>ipe_cia_aberta_2021.zip</a>",
    "<a href='ipe_cia_aberta_2024.zip'>ipe_cia_aberta_2024.zip</a>"
  )
  rm(
    list = ls(cvmdata:::.year_listing_cache),
    envir = cvmdata:::.year_listing_cache
  )
  listing_response <- function(req) {
    httr2::response(
      status_code = 200L,
      headers = list("Content-Type" = "text/html"),
      body = charToRaw(listing_html)
    )
  }
  years <- httr2::with_mocked_responses(
    listing_response,
    cvm_dataset_years("ipe")
  )
  expect_true(2024L %in% years)
  rm(
    list = ls(cvmdata:::.year_listing_cache),
    envir = cvmdata:::.year_listing_cache
  )
})

# Dictionary (snapshot-dependent) ------------------------------------
# Requires `data-raw/build-dictionary-snapshot.R --write` to have been
# re-run with the IPE schema in place.

test_that("cvm_dictionary('ipe', 'ipe') returns 13 rows", {
  dict <- cvm_dictionary("ipe", "ipe")
  expect_s3_class(dict, "tbl_df")
  expect_equal(nrow(dict), 13L)
  expect_true("codigo_cvm" %in% dict$campo)
  expect_true("link_download" %in% dict$campo)
})
