# End-to-end tests for cvm_fetch() against DFP, mocking the HTTP layer
# with httr2::with_mocked_responses + a local fixture ZIP.

# Helpers ----------------------------------------------------------------

# Pre-populate a tempdir cache with the DFP fixture ZIP and matching
# etag sidecar; redirect cvm_cache_root() at it.
local_prepare_dfp_cache <- function(envir = parent.frame()) {
  cache_root <- withr::local_tempdir(.local_envir = envir)
  withr::local_options(
    cvmdata.cache_dir = cache_root,
    .local_envir = envir
  )
  raw_dir <- file.path(cache_root, "raw", "dfp", "2024")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  file.copy(
    test_path("fixtures", "dfp_cia_aberta_2024.zip"),
    file.path(raw_dir, "dfp_cia_aberta_2024.zip")
  )
  saveRDS(
    list(
      etag = "\"fixture-etag\"",
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = "2026-05-19T00:00:00.000Z"
    ),
    file.path(raw_dir, "dfp_cia_aberta_2024.zip.etag.rds")
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

# Tracer test --------------------------------------------------------

test_that("cvm_fetch DFP BPA ind tracer returns cvm_tbl", {
  skip_if_not_installed("httptest2")
  local_prepare_dfp_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    cvm_fetch("dfp", "bpa",
              report_type = "ind", years = 2024, source = "cvm")
  )

  expect_s3_class(result, "cvm_tbl")
  expect_s3_class(result, "tbl_df")
  expect_identical(attr(result, "source"), "cvm")
  expect_identical(attr(result, "dataset"), "dfp")
  expect_identical(attr(result, "table"), "bpa")
  expect_true(nrow(result) > 0L)
  expect_true(all(c("cnpj_cia", "cd_cvm", "vl_conta") %in% names(result)))
  # multiply_by_scale + drop applied
  expect_false("escala_moeda" %in% names(result))
  expect_type(result$vl_conta, "double")
})

test_that("cvm_fetch DFP applies multiply_by_scale (MIL -> 1e3)", {
  skip_if_not_installed("httptest2")
  local_prepare_dfp_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    cvm_fetch("dfp", "bpa",
              report_type = "ind", years = 2024, source = "cvm",
              companies = "001023")
  )
  # BCO BRASIL Ativo Total ultimo exercicio ~ 2.4 trillion BRL
  ativo_total <- result[result$cd_conta == "1" &
                          result$ordem_exerc == "ÚLTIMO", "vl_conta",
                        drop = TRUE]
  expect_length(ativo_total, 1L)
  expect_gt(ativo_total, 1e12)   # > 1 trillion BRL
  expect_lt(ativo_total, 1e13)
})

test_that("cvm_fetch DFP filters by CD_CVM", {
  skip_if_not_installed("httptest2")
  local_prepare_dfp_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    cvm_fetch("dfp", "bpa",
              report_type = "ind", years = 2024, source = "cvm",
              companies = "001023")
  )
  expect_true(all(result$cd_cvm == "001023"))
})

test_that("cvm_fetch DFP filters by CD_CVM without zero-padding", {
  # Regression: filter_by_companies used sprintf("%06s", ...) which
  # pads with spaces, not zeros — so "1023" failed to match "009512".
  # Now uses formatC(..., width = 6, flag = "0", format = "d").
  skip_if_not_installed("httptest2")
  local_prepare_dfp_cache()

  unpadded <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    cvm_fetch("dfp", "bpa",
              report_type = "ind", years = 2024, source = "cvm",
              companies = "1023")
  )
  padded <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    cvm_fetch("dfp", "bpa",
              report_type = "ind", years = 2024, source = "cvm",
              companies = "001023")
  )
  expect_true(nrow(unpadded) > 0L)
  expect_true(all(unpadded$cd_cvm == "001023"))
  expect_identical(nrow(unpadded), nrow(padded))
})

test_that("cvm_fetch DFP filters by multiple unpadded CD_CVM (vector)", {
  skip_if_not_installed("httptest2")
  local_prepare_dfp_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    cvm_fetch("dfp", "bpa",
              report_type = "ind", years = 2024, source = "cvm",
              companies = c("1023", "999999"))
  )
  expect_true(nrow(result) > 0L)
  expect_true(all(result$cd_cvm == "001023"))
})

# Multi-match disambiguation (CLAUDE.md §2.7) ------------------------

# Helper: synthetic df with N distinct companies, all matched by `term`
multi_match_df <- function() {
  data.frame(
    cnpj_cia = c("00.000.000/0001-91", "47.960.950/0001-21"),
    cd_cvm = c("001023", "022470"),
    denom_cia = c("BCO BRASIL S.A.", "MAGAZINE LUIZA S.A."),
    stringsAsFactors = FALSE
  )
}

test_that("disambiguate_text_match aborts in batch on multiple matches", {
  df <- multi_match_df()
  hits <- c(TRUE, TRUE)
  expect_error(
    cvmdata:::disambiguate_text_match(
      df, hits, "sa", is_interactive = FALSE
    ),
    class = "cvmdata_error_input"
  )
})

test_that("disambiguate_text_match returns hits as-is on single match", {
  df <- multi_match_df()
  hits <- c(TRUE, FALSE)
  expect_identical(
    cvmdata:::disambiguate_text_match(
      df, hits, "brasil", is_interactive = FALSE
    ),
    hits
  )
})

test_that("disambiguate_text_match honours menu pick in interactive()", {
  df <- multi_match_df()
  hits <- c(TRUE, TRUE)
  # Pick option 1 (alphabetical order: BCO BRASIL is first).
  testthat::local_mocked_bindings(
    menu = function(choices, ...) 1L,
    .package = "utils"
  )
  out <- cvmdata:::disambiguate_text_match(
    df, hits, "sa", is_interactive = TRUE
  )
  expect_identical(out, c(TRUE, FALSE))
})

test_that("disambiguate_text_match keeps all when user picks 'All'", {
  df <- multi_match_df()
  hits <- c(TRUE, TRUE)
  # Last option is "All of the above" (n + 1 = 3 with 2 companies).
  testthat::local_mocked_bindings(
    menu = function(choices, ...) length(choices),
    .package = "utils"
  )
  out <- cvmdata:::disambiguate_text_match(
    df, hits, "sa", is_interactive = TRUE
  )
  expect_identical(out, c(TRUE, TRUE))
})

test_that("disambiguate_text_match aborts when user cancels", {
  df <- multi_match_df()
  hits <- c(TRUE, TRUE)
  testthat::local_mocked_bindings(
    menu = function(choices, ...) 0L,
    .package = "utils"
  )
  expect_error(
    cvmdata:::disambiguate_text_match(
      df, hits, "sa", is_interactive = TRUE
    ),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_fetch DFP filters by CNPJ", {
  skip_if_not_installed("httptest2")
  local_prepare_dfp_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    cvm_fetch("dfp", "bpa",
              report_type = "ind", years = 2024, source = "cvm",
              companies = "00000000000191")
  )
  expect_true(nrow(result) > 0L)
  expect_true(all(grepl("0001-91$", result$cnpj_cia)))
})

test_that("cvm_fetch DFP filters by textual search with abbrev map", {
  skip_if_not_installed("httptest2")
  local_prepare_dfp_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    cvm_fetch("dfp", "bpa",
              report_type = "ind", years = 2024, source = "cvm",
              companies = "banco brasil")
  )
  expect_true(nrow(result) > 0L)
  expect_true(all(grepl("BRASIL", result$denom_cia)))
})

# Latest-year fallback (CLAUDE.md §6 cvmdata_warn_year_fallback) -----

test_that("fetch_yearly_partitioned uses max year when no companies filter", {
  schema <- load_schema("dfp", "bpa")
  calls <- list()
  testthat::local_mocked_bindings(
    cvm_dataset_years = function(dataset, schema = NULL) {
      c(2024L, 2025L, 2026L)
    },
    fetch_one_year = function(schema, year, companies,
                              report_type, validate, ...) {
      calls[[length(calls) + 1L]] <<- year
      data.frame(cd_cvm = "x", stringsAsFactors = FALSE)
    }
  )
  out <- cvmdata:::fetch_yearly_partitioned(
    schema, "dfp", years = NULL, companies = NULL,
    report_type = "ind", validate = "skip"
  )
  expect_length(calls, 1L)
  expect_identical(calls[[1L]], 2026L)
  expect_equal(nrow(out), 1L)
})

test_that("fetch_yearly_partitioned falls back when max year empty", {
  schema <- load_schema("dfp", "bpa")
  calls <- integer(0L)
  testthat::local_mocked_bindings(
    cvm_dataset_years = function(dataset, schema = NULL) {
      c(2024L, 2025L, 2026L)
    },
    fetch_one_year = function(schema, year, companies,
                              report_type, validate, ...) {
      calls[[length(calls) + 1L]] <<- year
      if (year == 2026L) {
        data.frame(cd_cvm = character(0), stringsAsFactors = FALSE)
      } else {
        data.frame(cd_cvm = "001023", stringsAsFactors = FALSE)
      }
    }
  )
  expect_warning(
    out <- cvmdata:::fetch_yearly_partitioned(
      schema, "dfp", years = NULL, companies = "BCO BRASIL",
      report_type = "ind", validate = "skip"
    ),
    class = "cvmdata_warn_year_fallback"
  )
  expect_identical(calls, c(2026L, 2025L))
  expect_equal(nrow(out), 1L)
})

test_that("fetch_yearly_partitioned gives up after .latest_year_max_tries", {
  schema <- load_schema("dfp", "bpa")
  calls <- integer(0L)
  testthat::local_mocked_bindings(
    cvm_dataset_years = function(dataset, schema = NULL) {
      c(2020L, 2021L, 2022L, 2023L, 2024L, 2025L, 2026L)
    },
    fetch_one_year = function(schema, year, companies,
                              report_type, validate, ...) {
      calls[[length(calls) + 1L]] <<- year
      data.frame(cd_cvm = character(0), stringsAsFactors = FALSE)
    }
  )
  out <- suppressWarnings(cvmdata:::fetch_yearly_partitioned(
    schema, "dfp", years = NULL, companies = "DOES_NOT_EXIST",
    report_type = "ind", validate = "skip"
  ))
  # Tries exactly .latest_year_max_tries = 3 years (2026, 2025, 2024).
  expect_identical(calls, c(2026L, 2025L, 2024L))
  expect_equal(nrow(out), 0L)
})

test_that("fetch_yearly_partitioned with explicit years skips discovery", {
  schema <- load_schema("dfp", "bpa")
  discovery_called <- 0L
  fetch_calls <- integer(0L)
  testthat::local_mocked_bindings(
    cvm_dataset_years = function(dataset, schema = NULL) {
      discovery_called <<- discovery_called + 1L
      c(2024L)
    },
    fetch_one_year = function(schema, year, companies,
                              report_type, validate, ...) {
      fetch_calls[[length(fetch_calls) + 1L]] <<- year
      data.frame(cd_cvm = "x", year = year, stringsAsFactors = FALSE)
    }
  )
  out <- cvmdata:::fetch_yearly_partitioned(
    schema, "dfp", years = c(2022L, 2023L), companies = NULL,
    report_type = "ind", validate = "skip"
  )
  expect_identical(discovery_called, 0L)
  expect_identical(fetch_calls, c(2022L, 2023L))
  expect_equal(nrow(out), 2L)
})

# Schema validation --------------------------------------------------

test_that("cvm_fetch DFP requires report_type for tables with variants", {
  expect_error(
    cvm_fetch("dfp", "bpa", years = 2024, source = "cvm"),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_fetch DFP rejects report_type for tables without variants", {
  expect_error(
    cvm_fetch("dfp", "composicao_capital", years = 2024,
              source = "cvm", report_type = "ind"),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_fetch CAD rejects years argument", {
  expect_error(
    cvm_fetch("cad", "companhias", years = 2024, source = "cvm"),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_fetch rejects source = mirror (v0.1 stub)", {
  expect_error(
    cvm_fetch("cad", "companhias", source = "mirror"),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_fetch rejects unknown source value", {
  expect_error(
    cvm_fetch("cad", "companhias", source = "bogus"),
    class = "rlang_error"
  )
})

test_that("load_schema rejects mixed cvm_file_pattern + variants", {
  expect_error({
    bad <- list(
      dataset = "x", table = "y",
      cvm_archive_url_pattern = "https://example.com/x_{year}.zip",
      cvm_file_url_pattern = NULL,
      cvm_file_pattern = "x_{year}.csv",
      cvm_file_pattern_variants = list(
        ind = "x_ind_{year}.csv", con = "x_con_{year}.csv"
      ),
      temporal_partitioning = "yearly", first_year = 2010L
    )
    cvmdata:::validate_schema(bad, "x", "y")
  }, class = "cvmdata_error_internal")
})

test_that("load_schema rejects yearly schema lacking first_year", {
  expect_error({
    bad <- list(
      dataset = "x", table = "y",
      cvm_archive_url_pattern = "https://example.com/x_{year}.zip",
      cvm_file_url_pattern = NULL,
      cvm_file_pattern = "x_{year}.csv",
      temporal_partitioning = "yearly"
    )
    cvmdata:::validate_schema(bad, "x", "y")
  }, class = "cvmdata_error_internal")
})

test_that("load_schema accepts DFP bpa.yaml", {
  s <- load_schema("dfp", "bpa")
  expect_s3_class(s, "cvm_table_schema")
  expect_identical(s$temporal_partitioning, "yearly")
  expect_equal(s$first_year, 2010)
  expect_named(s$cvm_file_pattern_variants, c("ind", "con"))
})

# Discovery ----------------------------------------------------------

test_that("cvm_datasets lists cad and dfp", {
  ds <- cvm_datasets()
  expect_true(all(c("cad", "dfp") %in% ds))
})

test_that("cvm_tables('dfp') lists 11 conceptual tables", {
  tabs <- cvm_tables("dfp")
  expected <- c("bpa", "bpp", "composicao_capital", "dfc_md", "dfc_mi",
                "dmpl", "dra", "dre", "dva", "parecer", "submissao")
  expect_setequal(tabs, expected)
})

test_that("cvm_tables rejects unknown dataset", {
  expect_error(cvm_tables("does_not_exist"),
               class = "cvmdata_error_input")
})

test_that("cvm_dataset_years returns NA for non-yearly dataset", {
  expect_identical(cvm_dataset_years("cad"), NA_integer_)
})

# Transformations ----------------------------------------------------

test_that("scale_factor maps CVM labels", {
  expect_equal(cvmdata:::scale_factor("UNIDADE"), 1)
  expect_equal(cvmdata:::scale_factor("MIL"), 1e3)
  expect_equal(cvmdata:::scale_factor("MILHÃO"), 1e6)
  expect_equal(cvmdata:::scale_factor("BILHÃO"), 1e9)
  expect_equal(cvmdata:::scale_factor(c("MIL", "UNIDADE")), c(1e3, 1))
})

test_that("scale_factor rejects unknown label", {
  expect_error(cvmdata:::scale_factor("ZILHAO"),
               class = "cvmdata_error_parse")
})

test_that("keep_latest_version keeps max versao per (cnpj, dt_refer)", {
  df <- data.frame(
    cnpj_cia = c("A", "A", "A", "B"),
    dt_refer = as.Date(c("2024-12-31", "2024-12-31", "2024-12-31",
                          "2024-12-31")),
    versao = c(1L, 2L, 3L, 1L),
    payload = c("v1", "v2", "v3", "x")
  )
  schema <- list()
  out <- cvmdata:::tx_keep_latest_version(df, list(), schema)
  expect_equal(nrow(out), 2L)
  expect_setequal(out$payload, c("v3", "x"))
})

test_that("keep_latest_version is no-op without versao triple", {
  df <- data.frame(x = 1:3)
  out <- cvmdata:::tx_keep_latest_version(df, list(), list())
  expect_identical(out, df)
})

test_that("multiply_by_scale aborts when columns missing", {
  df <- data.frame(other = 1)
  schema <- list(dataset = "x", table = "y")
  tx <- list(column = "vl_conta", scale_column = "escala_moeda")
  expect_error(
    cvmdata:::tx_multiply_by_scale(df, tx, schema),
    class = "cvmdata_error_parse"
  )
})

test_that("apply_one_transformation aborts on unknown action", {
  expect_error(
    cvmdata:::apply_one_transformation(
      data.frame(), list(action = "bogus"), list()
    ),
    class = "cvmdata_error_internal"
  )
})

test_that("apply_one_transformation aborts on missing action", {
  expect_error(
    cvmdata:::apply_one_transformation(
      data.frame(), list(), list(dataset = "x", table = "y")
    ),
    class = "cvmdata_error_internal"
  )
})

test_that("apply_schema_transformations no-op when transformations empty", {
  df <- data.frame(a = 1:3)
  expect_identical(
    cvmdata:::apply_schema_transformations(df, list()),
    df
  )
})

test_that("get_yearly_csv downloads ZIP when cache is empty", {
  skip_if_not_installed("httptest2")
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  zip_bytes <- readBin(
    test_path("fixtures", "dfp_cia_aberta_2024.zip"),
    what = "raw",
    n = file.size(test_path("fixtures", "dfp_cia_aberta_2024.zip"))
  )
  schema <- load_schema("dfp", "bpa")
  call_count <- 0L
  mock_fn <- function(req) {
    call_count <<- call_count + 1L
    httr2::response(
      status_code = 200L,
      headers = list(
        "ETag" = "\"new\"",
        "Last-Modified" = "Mon, 19 May 2026 00:00:00 GMT"
      ),
      body = zip_bytes
    )
  }
  csv_path <- httr2::with_mocked_responses(
    mock_fn,
    source_cvm_http_get(schema, year = 2024L, report_type = "ind")
  )
  expect_true(file.exists(csv_path))
  expect_match(basename(csv_path), "BPA_ind_2024\\.csv$")
  expect_identical(call_count, 1L)
})

test_that("resolve_file_pattern rejects bad report_type", {
  schema <- load_schema("dfp", "bpa")
  expect_error(
    cvmdata:::resolve_file_pattern(schema, "xxx"),
    class = "cvmdata_error_input"
  )
})

test_that("resolve_file_pattern errors on missing report_type", {
  schema <- load_schema("dfp", "bpa")
  expect_error(
    cvmdata:::resolve_file_pattern(schema, NULL),
    class = "cvmdata_error_input"
  )
})

test_that("resolve_file_pattern returns scalar for non-variant tables", {
  schema <- load_schema("dfp", "composicao_capital")
  out <- cvmdata:::resolve_file_pattern(schema, NULL)
  expect_match(out, "composicao_capital_\\{year\\}\\.csv$")
})

test_that("cvm_dataset_years parses HTML listing for yearly dataset", {
  schema <- load_schema("dfp", "bpa")
  # Mock o HTTP listing
  fake_html <- paste(
    "<a href=\"dfp_cia_aberta_2010.zip\">x</a>",
    "<a href=\"dfp_cia_aberta_2011.zip\">x</a>",
    "<a href=\"dfp_cia_aberta_2024.zip\">x</a>",
    sep = "\n"
  )
  # clear cache
  rm(list = ls(cvmdata:::.year_listing_cache),
     envir = cvmdata:::.year_listing_cache)
  mock_listing <- function(req) {
    httr2::response(
      status_code = 200L,
      body = charToRaw(fake_html)
    )
  }
  years <- httr2::with_mocked_responses(
    mock_listing,
    cvm_dataset_years("dfp", schema = schema)
  )
  expect_identical(years, c(2010L, 2011L, 2024L))
})

test_that("read_cvm_csv 'warn' emits cvmdata_warn_validation", {
  raw <- list(
    dataset = "cad", table = "companhias",
    cvm_archive_url_pattern = NULL,
    cvm_file_url_pattern = "https://example.com/x.csv",
    cvm_file_pattern = "x.csv",
    encoding = "ISO-8859-1", delimiter = ";",
    temporal_partitioning = "none",
    meta_status = "missing",
    expected_field_names = c("missing_field_a", "missing_field_b"),
    expected_field_count = 47L
  )
  schema <- structure(raw, class = c("cvm_table_schema", "list"))
  expect_warning(
    read_cvm_csv(
      test_path("fixtures", "cad_sample.csv"),
      schema,
      validate = "warn"
    ),
    class = "cvmdata_warn_validation"
  )
})

test_that("validate_schema rejects bad meta_status", {
  bad <- list(
    dataset = "x", table = "y",
    cvm_archive_url_pattern = NULL,
    cvm_file_url_pattern = "https://example.com/x.csv",
    cvm_file_pattern = "x.csv",
    temporal_partitioning = "none",
    meta_status = "weird"
  )
  expect_error(
    cvmdata:::validate_schema(bad, "x", "y"),
    class = "cvmdata_error_internal"
  )
})

test_that("validate_schema rejects bad temporal_partitioning", {
  bad <- list(
    dataset = "x", table = "y",
    cvm_archive_url_pattern = NULL,
    cvm_file_url_pattern = "https://example.com/x.csv",
    cvm_file_pattern = "x.csv",
    temporal_partitioning = "monthly"
  )
  expect_error(
    cvmdata:::validate_schema(bad, "x", "y"),
    class = "cvmdata_error_internal"
  )
})

test_that("validate_schema rejects missing_meta without field_names", {
  bad <- list(
    dataset = "x", table = "y",
    cvm_archive_url_pattern = NULL,
    cvm_file_url_pattern = "https://example.com/x.csv",
    cvm_file_pattern = "x.csv",
    temporal_partitioning = "none",
    meta_status = "missing"
  )
  expect_error(
    cvmdata:::validate_schema(bad, "x", "y"),
    class = "cvmdata_error_internal"
  )
})

test_that("validate_schema rejects bad variant keys", {
  bad <- list(
    dataset = "x", table = "y",
    cvm_archive_url_pattern = "https://example.com/x_{year}.zip",
    cvm_file_url_pattern = NULL,
    cvm_file_pattern_variants = list(foo = "a", bar = "b"),
    temporal_partitioning = "yearly", first_year = 2010L
  )
  expect_error(
    cvmdata:::validate_schema(bad, "x", "y"),
    class = "cvmdata_error_internal"
  )
})

test_that("load_schema aborts for unknown table", {
  expect_error(
    load_schema("dfp", "does_not_exist"),
    class = "cvmdata_error_input"
  )
})
