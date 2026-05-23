# End-to-end tests for cad_fetch(), mocking the HTTP layer with
# httptest2 + a local fixture.

# Setup -----------------------------------------------------------------

# Pre-populate a tempdir cache with the fixture and a matching etag
# sidecar, then point cvm_cache_root() at it via the
# `cvmdata.cache_dir` option. Returns the prepared cache root.
local_prepare_cache <- function(envir = parent.frame()) {
  cache_root <- withr::local_tempdir(.local_envir = envir)
  withr::local_options(
    cvmdata.cache_dir = cache_root,
    .local_envir = envir
  )
  raw_dir <- file.path(cache_root, "raw", "cad")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  file.copy(
    test_path("fixtures", "cad_sample.csv"),
    file.path(raw_dir, "cad_cia_aberta.csv")
  )
  saveRDS(
    list(
      etag = "\"fixture-etag\"",
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = "2026-05-19T00:00:00.000Z"
    ),
    file.path(raw_dir, "cad_cia_aberta.csv.etag.rds")
  )
  cache_root
}

# Build a mocked httr2 HEAD response carrying the same ETag the cache
# sidecar holds, so that the source layer considers the cache fresh
# and avoids the GET.
fresh_head_response <- function() {
  httr2::response(
    status_code = 200L,
    headers = list(
      "ETag" = "\"fixture-etag\"",
      "Last-Modified" = "Mon, 19 May 2026 00:00:00 GMT"
    )
  )
}

# Tests -----------------------------------------------------------------

test_that("cad_fetch() returns a cvm_tbl with provenance attributes", {
  skip_if_not_installed("httptest2")
  local_prepare_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    cad_fetch()
  )

  expect_s3_class(result, "cvm_tbl")
  expect_s3_class(result, "tbl_df")
  expect_identical(attr(result, "source"), "cvm")
  expect_identical(attr(result, "dataset"), "cad")
  expect_identical(attr(result, "table"), "companhias")
  expect_s3_class(attr(result, "fetched_at"), "POSIXct")
  expect_match(
    attr(result, "package_version"),
    "^[0-9]+\\.[0-9]+\\.[0-9]+(\\.[0-9]+)?$"
  )
})

test_that("cad_fetch() returns identifier columns as character", {
  skip_if_not_installed("httptest2")
  local_prepare_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    cad_fetch()
  )

  expect_true("cnpj_cia" %in% names(result))
  expect_true("cd_cvm" %in% names(result))
  expect_type(result$cnpj_cia, "character")
  expect_type(result$cd_cvm, "character")
  expect_true(any(grepl(
    "^[0-9]{2}\\.[0-9]{3}\\.[0-9]{3}/[0-9]{4}-[0-9]{2}$",
    result$cnpj_cia
  )))
})

test_that("cad_fetch() parses date columns as Date", {
  skip_if_not_installed("httptest2")
  local_prepare_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    cad_fetch()
  )

  date_cols <- grep("^dt_", names(result), value = TRUE)
  expect_true(length(date_cols) > 0L)
  for (col in date_cols) {
    expect_s3_class(result[[col]], "Date")
  }
})

test_that("cad_fetch() applies the snake_case column rename", {
  skip_if_not_installed("httptest2")
  local_prepare_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    cad_fetch()
  )

  expect_true(all(names(result) == tolower(names(result))))
  expect_false(any(grepl("[A-Z]", names(result))))
})

test_that("cad_fetch() filters by cd_cvm in `companies`", {
  skip_if_not_installed("httptest2")
  local_prepare_cache()

  full <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    cad_fetch()
  )
  pick <- full$cd_cvm[1L]

  filtered <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    cad_fetch(companies = pick)
  )

  expect_true(nrow(filtered) >= 1L)
  expect_true(all(filtered$cd_cvm == pick))
})

test_that("cad_fetch() rejects unsupported source values cleanly", {
  # "mirror" is in the documented domain but not implemented yet —
  # cvmdata_error_internal, not cvmdata_error_input.
  expect_error(
    cad_fetch(source = "mirror"),
    class = "cvmdata_error_internal"
  )
  expect_error(
    cad_fetch(source = "bogus"),
    class = "rlang_error"
  )
})

test_that("read_cvm_csv on fixture honours expected_field_count", {
  schema <- load_schema("cad", "companhias")
  df <- read_cvm_csv(
    test_path("fixtures", "cad_sample.csv"),
    schema,
    validate = "strict"
  )
  expect_identical(ncol(df), schema$expected_field_count)
  expect_gt(nrow(df), 0L)
})

test_that("validate = 'strict' aborts on field-count mismatch", {
  raw <- list(
    dataset = "cad", table = "companhias",
    cvm_archive_url_pattern = NULL,
    cvm_file_url_pattern = "https://example.com/x.csv",
    cvm_file_pattern = "x.csv",
    encoding = "ISO-8859-1", delimiter = ";",
    temporal_partitioning = "none",
    expected_field_count = 999L,
    transformations = list()
  )
  schema <- structure(raw, class = c("cvm_table_schema", "list"))
  expect_error(
    read_cvm_csv(
      test_path("fixtures", "cad_sample.csv"),
      schema,
      validate = "strict"
    ),
    class = "cvmdata_error_parse"
  )
})

test_that("validate = 'warn' warns on field-count mismatch", {
  raw <- list(
    dataset = "cad", table = "companhias",
    cvm_archive_url_pattern = NULL,
    cvm_file_url_pattern = "https://example.com/x.csv",
    cvm_file_pattern = "x.csv",
    encoding = "ISO-8859-1", delimiter = ";",
    temporal_partitioning = "none",
    expected_field_count = 999L,
    transformations = list()
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

test_that("source_cvm_http_get downloads when cache is empty", {
  skip_if_not_installed("httptest2")
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  csv_bytes <- readBin(
    test_path("fixtures", "cad_sample.csv"),
    what = "raw",
    n = file.size(test_path("fixtures", "cad_sample.csv"))
  )
  schema <- load_schema("cad", "companhias")

  call_count <- 0L
  mock_fn <- function(req) {
    call_count <<- call_count + 1L
    httr2::response(
      status_code = 200L,
      headers = list(
        "ETag" = "\"first-download\"",
        "Last-Modified" = "Mon, 19 May 2026 00:00:00 GMT"
      ),
      body = csv_bytes
    )
  }

  csv_path <- httr2::with_mocked_responses(
    mock_fn,
    source_cvm_http_get(schema)
  )

  expect_true(file.exists(csv_path))
  expect_true(file.exists(paste0(csv_path, ".etag.rds")))
  meta <- readRDS(paste0(csv_path, ".etag.rds"))
  expect_identical(meta$etag, "\"first-download\"")
  expect_identical(call_count, 1L)
})

test_that("source_cvm_http_get re-downloads when ETag changes", {
  skip_if_not_installed("httptest2")
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  raw_dir <- file.path(cache_root, "raw", "cad")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  file.copy(
    test_path("fixtures", "cad_sample.csv"),
    file.path(raw_dir, "cad_cia_aberta.csv")
  )
  saveRDS(
    list(
      etag = "\"old-etag\"",
      last_modified = "Mon, 01 Jan 2020 00:00:00 GMT"
    ),
    file.path(raw_dir, "cad_cia_aberta.csv.etag.rds")
  )

  csv_bytes <- readBin(
    test_path("fixtures", "cad_sample.csv"),
    what = "raw",
    n = file.size(test_path("fixtures", "cad_sample.csv"))
  )
  call_count <- 0L
  mock_fn <- function(req) {
    call_count <<- call_count + 1L
    httr2::response(
      status_code = 200L,
      headers = list(
        "ETag" = "\"new-etag\"",
        "Last-Modified" = "Mon, 19 May 2026 00:00:00 GMT"
      ),
      body = csv_bytes
    )
  }

  schema <- load_schema("cad", "companhias")
  csv_path <- httr2::with_mocked_responses(
    mock_fn,
    source_cvm_http_get(schema)
  )

  meta <- readRDS(paste0(csv_path, ".etag.rds"))
  expect_identical(meta$etag, "\"new-etag\"")
  expect_identical(call_count, 2L)
})

test_that("source_cvm_http_get requires year for yearly schema", {
  schema <- list(
    dataset = "dfp", table = "bpa",
    cvm_archive_url_pattern = "https://example.com/x_{year}.zip",
    cvm_file_url_pattern = NULL,
    cvm_file_pattern = "x_{year}.csv",
    temporal_partitioning = "yearly", first_year = 2010L,
    encoding = "ISO-8859-1", delimiter = ";",
    expected_field_count = 14L,
    transformations = list()
  )
  class(schema) <- c("cvm_table_schema", "list")
  expect_error(
    source_cvm_http_get(schema),
    class = "cvmdata_error_internal"
  )
})

test_that("print.cvm_tbl emits provenance lines", {
  schema <- load_schema("cad", "companhias")
  df <- read_cvm_csv(
    test_path("fixtures", "cad_sample.csv"),
    schema,
    validate = "skip"
  )
  result <- cvm_attach_metadata(
    df, source = "portal",
    dataset = "cad", table = "companhias"
  )
  msg <- capture.output(
    print(result),
    type = "message"
  )
  msg_text <- paste(msg, collapse = "\n")
  expect_match(msg_text, "source")
  expect_match(msg_text, "fetched_at")
  expect_match(msg_text, "dataset")
  expect_match(msg_text, "table")
})

test_that("validate = 'skip' suppresses mismatch errors", {
  raw <- list(
    dataset = "cad", table = "companhias",
    cvm_archive_url_pattern = NULL,
    cvm_file_url_pattern = "https://example.com/x.csv",
    cvm_file_pattern = "x.csv",
    encoding = "ISO-8859-1", delimiter = ";",
    temporal_partitioning = "none",
    expected_field_count = 999L,
    transformations = list()
  )
  schema <- structure(raw, class = c("cvm_table_schema", "list"))
  expect_no_error(
    read_cvm_csv(
      test_path("fixtures", "cad_sample.csv"),
      schema,
      validate = "skip"
    )
  )
})
