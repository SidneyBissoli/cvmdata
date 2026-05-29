# End-to-end tests for issuer_fetch() against the v0.2 FCA dataset
# (Formulario Cadastral). Mocks the HTTP layer with
# httr2::with_mocked_responses + a local fixture ZIP, matching the
# pattern used for CGVN/VLMO/DFP/ITR/FRE.
#
# FCA is the largest v0.2 surface: 10 tables (1 classic submissao + 9
# FRE-detail), a B3 ticker lookup via fca/valor_mobiliario, and a
# table (departamento_acionistas) that ships header-only from 2024 on.

# Helpers ----------------------------------------------------------------

local_prepare_fca_cache <- function(envir = parent.frame()) {
  cache_root <- withr::local_tempdir(.local_envir = envir)
  withr::local_options(
    cvmdata.cache_dir = cache_root,
    .local_envir = envir
  )
  # The ticker lookup table is session-cached; clear it so each test
  # reads from this test's freshly-staged fixture.
  cvmdata:::ticker_lookup_cache_clear()
  withr::defer(cvmdata:::ticker_lookup_cache_clear(), envir = envir)
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
  cache_root
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

test_that("issuer_fetch FCA submissao tracer returns cvm_tbl", {
  skip_if_not_installed("httptest2")
  local_prepare_fca_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("fca", "submissao", year = 2024L, source = "cvm")
  )

  expect_s3_class(result, "cvm_tbl")
  expect_identical(attr(result, "group"), "companhias")
  expect_identical(attr(result, "dataset"), "fca")
  expect_identical(attr(result, "table"), "submissao")
  expect_true(nrow(result) > 0L)
  # Classic convention, identical to ITR/DFP/FRE submissao.
  expect_true(all(c("cnpj_cia", "dt_refer", "versao", "cd_cvm",
                    "denom_cia") %in% names(result)))
  expect_identical(ncol(result), 9L)
  expect_type(result$cnpj_cia, "character")
  expect_type(result$cd_cvm, "character")
  expect_s3_class(result$dt_refer, "Date")
})

test_that("issuer_fetch FCA detail tracers return FRE-detail shape", {
  skip_if_not_installed("httptest2")
  local_prepare_fca_cache()

  for (tb in c("geral", "valor_mobiliario", "endereco")) {
    result <- httr2::with_mocked_responses(
      function(req) fresh_head_response(),
      issuer_fetch("fca", tb, year = 2024L, source = "cvm")
    )
    expect_s3_class(result, "cvm_tbl")
    expect_identical(attr(result, "table"), tb)
    expect_true(nrow(result) > 0L)
    expect_true(all(c("cnpj_companhia", "data_referencia", "versao",
                      "nome_empresarial") %in% names(result)))
    expect_type(result$cnpj_companhia, "character")
    expect_s3_class(result$data_referencia, "Date")
    # FRE-detail tables do not carry cd_cvm.
    expect_false("cd_cvm" %in% names(result))
  }
})

test_that("FCA valor_mobiliario carries the ticker column", {
  skip_if_not_installed("httptest2")
  local_prepare_fca_cache()

  vm <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("fca", "valor_mobiliario", year = 2024L, source = "cvm")
  )
  expect_identical(ncol(vm), 18L)
  expect_true("codigo_negociacao" %in% names(vm))
  # Forced to character via the ^codigo_ identifier prefix.
  expect_type(vm$codigo_negociacao, "character")
  expect_s3_class(vm$data_fim_negociacao, "Date")
})

# Filtering by issuer -------------------------------------------------

test_that("issuer_fetch FCA filters a detail by CNPJ", {
  skip_if_not_installed("httptest2")
  local_prepare_fca_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("fca", "geral", issuer = "00.000.000/0001-91",
                 year = 2024L, source = "cvm")
  )
  expect_true(nrow(result) > 0L)
  expect_true(all(result$cnpj_companhia == "00.000.000/0001-91"))
})

test_that("FCA resolves CD_CVM via submissao for a detail table", {
  # The bridge under test is new to FCA: submissao is CLASSIC
  # (cnpj_cia) while the detail is FRE-detail (cnpj_companhia). The
  # resolver must read fca/submissao, map CD_CVM -> cnpj_cia, and match
  # that CNPJ against the detail's cnpj_companhia column.
  skip_if_not_installed("httptest2")
  local_prepare_fca_cache()

  padded <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("fca", "endereco", issuer = "001023",
                 year = 2024L, source = "cvm")
  )
  expect_true(nrow(padded) > 0L)
  expect_true(all(padded$cnpj_companhia == "00.000.000/0001-91"))

  unpadded <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("fca", "endereco", issuer = "1023",
                 year = 2024L, source = "cvm")
  )
  expect_identical(nrow(unpadded), nrow(padded))
})

# Ticker lookup -------------------------------------------------------

test_that("FCA resolves a B3 ticker to its issuer CNPJ", {
  skip_if_not_installed("httptest2")
  local_prepare_fca_cache()

  # BBAS3 is BCO BRASIL's ticker in the fixture's valor_mobiliario.
  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("fca", "geral", issuer = "BBAS3",
                 year = 2024L, source = "cvm")
  )
  expect_true(nrow(result) > 0L)
  expect_true(all(result$cnpj_companhia == "00.000.000/0001-91"))
})

test_that("FCA ticker lookup is case-insensitive", {
  skip_if_not_installed("httptest2")
  local_prepare_fca_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("fca", "geral", issuer = "bbas3",
                 year = 2024L, source = "cvm")
  )
  expect_true(all(result$cnpj_companhia == "00.000.000/0001-91"))
})

test_that("unknown ticker aborts with cvmdata_error_input", {
  skip_if_not_installed("httptest2")
  local_prepare_fca_cache()

  expect_error(
    httr2::with_mocked_responses(
      function(req) fresh_head_response(),
      issuer_fetch("fca", "geral", issuer = "ZZZZ9",
                   year = 2024L, source = "cvm")
    ),
    class = "cvmdata_error_input"
  )
})

# Issuer-token routing ------------------------------------------------

test_that("classify_issuer_tokens routes ticker vs CD_CVM vs CNPJ", {
  cls <- cvmdata:::classify_issuer_tokens(c(
    "PETR4", "BBDC11", "ITSA4F",      # tickers
    "1023", "001023",                  # CD_CVM
    "00.000.000/0001-91",              # CNPJ
    "BCO BRASIL"                       # free text
  ))
  expect_identical(
    cls$is_ticker,
    c(TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, FALSE)
  )
  expect_identical(
    cls$is_cdcvm,
    c(FALSE, FALSE, FALSE, TRUE, TRUE, FALSE, FALSE)
  )
  expect_identical(
    cls$is_cnpj,
    c(FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, FALSE)
  )
  expect_identical(
    cls$is_text,
    c(FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE)
  )
  # A numeric CD_CVM is never captured as a ticker, and a ticker is
  # never captured as CD_CVM: the four masks partition the input.
  expect_true(all(
    cls$is_ticker + cls$is_cdcvm + cls$is_cnpj + cls$is_text == 1L
  ))
})

# Empty table tolerance ----------------------------------------------

test_that("departamento_acionistas returns 0 rows without aborting", {
  # Empty upstream from 2024 on (verificacao empirica §12.1): the CSV
  # ships a valid 23-field header and no data rows. The reader must
  # tolerate nrow == 0L in every validate mode.
  skip_if_not_installed("httptest2")
  local_prepare_fca_cache()

  for (mode in c("strict", "warn", "skip")) {
    result <- httr2::with_mocked_responses(
      function(req) fresh_head_response(),
      issuer_fetch("fca", "departamento_acionistas",
                   year = 2024L, source = "cvm", validate = mode)
    )
    expect_s3_class(result, "cvm_tbl")
    expect_identical(nrow(result), 0L)
    expect_identical(ncol(result), 23L)
  }
})

# report_type rejection ----------------------------------------------

test_that("report_type aborts for FCA tables without variants", {
  skip_if_not_installed("httptest2")
  local_prepare_fca_cache()
  expect_error(
    httr2::with_mocked_responses(
      function(req) fresh_head_response(),
      issuer_fetch("fca", "submissao", year = 2024L,
                   source = "cvm", report_type = "ind")
    ),
    class = "cvmdata_error_input"
  )
})

# Schema + discovery -------------------------------------------------

test_that("load_schema accepts the 10 FCA YAMLs", {
  expected <- c(
    submissao = 9, auditor = 15, canal_divulgacao = 7,
    departamento_acionistas = 23, dri = 26, endereco = 21,
    escriturador = 24, geral = 26, pais_estrangeiro_negociacao = 7,
    valor_mobiliario = 18
  )
  for (tb in names(expected)) {
    s <- load_schema("fca", tb)
    expect_s3_class(s, "cvm_table_schema")
    expect_identical(s$temporal_partitioning, "yearly")
    expect_equal(s$first_year, 2021)
    expect_equal(s$expected_field_count, unname(expected[[tb]]))
  }
  # submissao keeps the classic file pattern (no detail infix).
  expect_identical(
    load_schema("fca", "submissao")$cvm_file_pattern,
    "fca_cia_aberta_{year}.csv"
  )
})

test_that("cvm_datasets includes fca", {
  expect_true("fca" %in% cvm_datasets())
  expect_true("fca" %in% cvm_datasets(group = "companhias"))
})

test_that("cvm_tables('fca') lists the 10 tables", {
  expect_setequal(
    cvm_tables("fca"),
    c("submissao", "auditor", "canal_divulgacao",
      "departamento_acionistas", "dri", "endereco", "escriturador",
      "geral", "pais_estrangeiro_negociacao", "valor_mobiliario")
  )
})

test_that("cvm_dataset_years('fca') includes 2024", {
  skip_if_not_installed("httptest2")
  # Mock the CVM directory listing so year discovery is offline.
  listing_html <- paste0(
    "<a href='fca_cia_aberta_2021.zip'>fca_cia_aberta_2021.zip</a>",
    "<a href='fca_cia_aberta_2024.zip'>fca_cia_aberta_2024.zip</a>"
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
    cvm_dataset_years("fca")
  )
  expect_true(2024L %in% years)
  rm(
    list = ls(cvmdata:::.year_listing_cache),
    envir = cvmdata:::.year_listing_cache
  )
})

# Dictionary (snapshot-dependent) ------------------------------------
# Requires `data-raw/build-dictionary-snapshot.R --write` to have been
# re-run with the FCA schemas in place.

test_that("cvm_dictionary('fca', 'submissao') returns 9 rows", {
  dict <- cvm_dictionary("fca", "submissao")
  expect_s3_class(dict, "tbl_df")
  expect_equal(nrow(dict), 9L)
  expect_true("cnpj_cia" %in% dict$campo)
})

test_that("cvm_dictionary('fca', 'valor_mobiliario') returns 18 rows", {
  dict <- cvm_dictionary("fca", "valor_mobiliario")
  expect_equal(nrow(dict), 18L)
  expect_true("codigo_negociacao" %in% dict$campo)
})

test_that("cvm_dictionary('fca', 'departamento_acionistas') = 23 rows", {
  dict <- cvm_dictionary("fca", "departamento_acionistas")
  expect_equal(nrow(dict), 23L)
})
