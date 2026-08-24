# Tests for R/source-cvm-http.R. These probe the branches not
# exercised indirectly by test-cad-fetch.R / test-cvm-fetch.R: ETag
# mismatch, missing cache-validators, HEAD/GET network failures,
# dispatch errors, and CSV-missing-from-ZIP. All HTTP is mocked via
# httr2::with_mocked_responses(); no test touches the network.

# Helpers ----------------------------------------------------------------

# Build a fresh cache root with the DFP fixture ZIP and a sidecar at
# `sidecar_meta` (default: empty etag = forces GET when HEAD says
# anything truthy).
local_dfp_cache_with_sidecar <- function(sidecar_meta = NULL,
                                         envir = parent.frame()) {
  cache_root <- withr::local_tempdir(.local_envir = envir)
  withr::local_options(
    cvmdata.cache_dir = cache_root,
    .local_envir = envir
  )
  raw_dir <- file.path(cache_root, "raw", "companhias", "dfp", "2024")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  file.copy(
    test_path("fixtures", "dfp_cia_aberta_2024.zip"),
    file.path(raw_dir, "dfp_cia_aberta_2024.zip")
  )
  if (!is.null(sidecar_meta)) {
    saveRDS(
      sidecar_meta,
      file.path(raw_dir, "dfp_cia_aberta_2024.zip.etag.rds")
    )
  }
  list(cache_root = cache_root, raw_dir = raw_dir)
}

# Read the fixture ZIP body as raw bytes so the GET mock can return it.
fixture_zip_body <- function() {
  path <- test_path("fixtures", "dfp_cia_aberta_2024.zip")
  readBin(path, what = "raw", n = file.info(path)$size)
}

# ETag mismatch triggers a GET --------------------------------------------

test_that("download_with_etag fires GET when HEAD ETag mismatches", {
  paths <- local_dfp_cache_with_sidecar(
    sidecar_meta = list(
      etag = "\"OLD-ETAG\"",
      last_modified = "Wed, 01 Jan 2020 00:00:00 GMT",
      fetched_at = "2020-01-01T00:00:00.000Z"
    )
  )

  # Replace the cached ZIP with a tiny dummy file so we can prove the
  # GET re-wrote it from the mock body (file size will jump back up to
  # the fixture's 38054 bytes).
  zip_path <- file.path(paths$raw_dir, "dfp_cia_aberta_2024.zip")
  writeBin(as.raw(c(0x00, 0x01, 0x02)), zip_path)
  expect_lt(file.info(zip_path)$size, 100L)

  fixture_body <- fixture_zip_body()
  mock <- function(req) {
    if (identical(req$method, "HEAD")) {
      httr2::response(
        status_code = 200L,
        headers = list(
          "ETag" = "\"NEW-ETAG\"",
          "Last-Modified" = "Mon, 19 May 2026 00:00:00 GMT"
        )
      )
    } else {
      httr2::response(
        status_code = 200L,
        headers = list(
          "ETag" = "\"NEW-ETAG\"",
          "Last-Modified" = "Mon, 19 May 2026 00:00:00 GMT"
        ),
        body = fixture_body
      )
    }
  }

  result <- httr2::with_mocked_responses(
    mock,
    issuer_fetch("dfp", "bpa",
              report_type = "ind", year = 2024, source = "cvm")
  )
  expect_s3_class(result, "cvm_tbl")
  expect_equal(file.info(zip_path)$size, length(fixture_body))
  updated <- readRDS(paste0(zip_path, ".etag.rds"))
  expect_identical(updated$etag, "\"NEW-ETAG\"")
})

# HEAD with no cache validators forces a GET ------------------------------

test_that("download_with_etag fires GET when HEAD lacks ETag/Last-Modified", {
  paths <- local_dfp_cache_with_sidecar(
    sidecar_meta = list(
      etag = "\"OLD-ETAG\"",
      last_modified = "Wed, 01 Jan 2020 00:00:00 GMT",
      fetched_at = "2020-01-01T00:00:00.000Z"
    )
  )
  zip_path <- file.path(paths$raw_dir, "dfp_cia_aberta_2024.zip")
  writeBin(as.raw(c(0x00, 0x01, 0x02)), zip_path)

  fixture_body <- fixture_zip_body()
  mock <- function(req) {
    if (identical(req$method, "HEAD")) {
      httr2::response(status_code = 200L, headers = list())
    } else {
      httr2::response(
        status_code = 200L,
        headers = list("ETag" = "\"FRESHLY-FETCHED\""),
        body = fixture_body
      )
    }
  }
  result <- httr2::with_mocked_responses(
    mock,
    issuer_fetch("dfp", "bpa",
              report_type = "ind", year = 2024, source = "cvm")
  )
  expect_s3_class(result, "cvm_tbl")
  updated <- readRDS(paste0(zip_path, ".etag.rds"))
  expect_identical(updated$etag, "\"FRESHLY-FETCHED\"")
})

# HEAD failure aborts cleanly ---------------------------------------------

test_that("download_with_etag aborts (cvmdata_error_http) on HEAD failure", {
  local_dfp_cache_with_sidecar(
    sidecar_meta = list(
      etag = "\"OLD\"",
      last_modified = NULL,
      fetched_at = "2020-01-01T00:00:00.000Z"
    )
  )
  mock <- function(req) {
    if (identical(req$method, "HEAD")) {
      stop("simulated DNS error")
    }
    httr2::response(200L)
  }
  expect_error(
    httr2::with_mocked_responses(
      mock,
      issuer_fetch("dfp", "bpa",
                report_type = "ind", year = 2024, source = "cvm")
    ),
    class = "cvmdata_error_http"
  )
})

# GET failure after a successful HEAD aborts cleanly ----------------------

test_that("download_with_etag aborts (cvmdata_error_http) on GET failure", {
  local_dfp_cache_with_sidecar(
    sidecar_meta = list(
      etag = "\"OLD\"",
      last_modified = NULL,
      fetched_at = "2020-01-01T00:00:00.000Z"
    )
  )
  mock <- function(req) {
    if (identical(req$method, "HEAD")) {
      httr2::response(
        status_code = 200L,
        headers = list("ETag" = "\"NEW-ETAG\"")
      )
    } else {
      stop("simulated connection reset")
    }
  }
  expect_error(
    httr2::with_mocked_responses(
      mock,
      issuer_fetch("dfp", "bpa",
                report_type = "ind", year = 2024, source = "cvm")
    ),
    class = "cvmdata_error_http"
  )
})

# Absent CSV inside the ZIP raises the dedicated subclass -----------------

test_that("absent CSV in the ZIP raises cvmdata_error_zip_member_missing", {
  # The dfp fixture ZIP carries bpa/composicao_capital/parecer/... but
  # not bpp. Requesting bpp/ind must abort with the dedicated subclass
  # (still a cvmdata_error_parse) so the ETL can classify it as a benign
  # "table absent that year" skip by class rather than message text.
  local_dfp_cache_with_sidecar(
    sidecar_meta = list(
      etag = "\"E\"", last_modified = NULL,
      fetched_at = "2020-01-01T00:00:00.000Z"
    )
  )
  mock <- function(req) {
    httr2::response(status_code = 200L, headers = list("ETag" = "\"E\""))
  }
  err <- tryCatch(
    httr2::with_mocked_responses(
      mock,
      issuer_fetch("dfp", "bpp",
                   report_type = "ind", year = 2024, source = "cvm")
    ),
    error = function(e) e
  )
  expect_s3_class(err, "cvmdata_error_zip_member_missing")
  # Backward compatible: still a parse error for existing handlers.
  expect_s3_class(err, "cvmdata_error_parse")
})

# Cold-start (no cache, no sidecar) goes straight to GET ------------------

test_that("download_with_etag fetches via GET when cache is empty", {
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  fixture_body <- fixture_zip_body()
  mock <- function(req) {
    expect_false(identical(req$method, "HEAD"))
    httr2::response(
      status_code = 200L,
      headers = list("ETag" = "\"COLD\""),
      body = fixture_body
    )
  }
  result <- httr2::with_mocked_responses(
    mock,
    issuer_fetch("dfp", "bpa",
              report_type = "ind", year = 2024, source = "cvm")
  )
  expect_s3_class(result, "cvm_tbl")
  zip_path <- file.path(
    cache_root, "raw", "companhias", "dfp", "2024",
    "dfp_cia_aberta_2024.zip"
  )
  expect_true(file.exists(zip_path))
  expect_equal(file.info(zip_path)$size, length(fixture_body))
})

# Dispatch errors ---------------------------------------------------------

test_that("source_cvm_http_get aborts when yearly schema gets year = NULL", {
  schema <- load_schema("dfp", "bpa")
  expect_error(
    cvmdata:::source_cvm_http_get(schema, year = NULL, report_type = "ind"),
    class = "cvmdata_error_internal"
  )
})

test_that("source_cvm_http_get aborts on unknown temporal_partitioning", {
  # Synthetic schema with a bogus partitioning value.
  schema <- list(
    dataset = "synth",
    table = "x",
    temporal_partitioning = "monthly",
    cvm_archive_url_pattern = NULL,
    cvm_file_url_pattern = NULL
  )
  expect_error(
    cvmdata:::source_cvm_http_get(schema, year = NULL, report_type = NULL),
    class = "cvmdata_error_internal"
  )
})

test_that("source_cvm_http_get aborts when simple schema has no file URL", {
  # Synthetic schema declaring `none` partitioning but with no file URL.
  schema <- list(
    dataset = "synth",
    table = "x",
    temporal_partitioning = "none",
    cvm_file_url_pattern = NULL,
    cvm_archive_url_pattern = NULL
  )
  expect_error(
    cvmdata:::source_cvm_http_get(schema, year = NULL, report_type = NULL),
    class = "cvmdata_error_internal"
  )
})

# report_type passed to simple (CAD-style) schema -------------------------

test_that("get_simple_csv aborts when report_type is supplied", {
  # CAD has temporal_partitioning: none. issuer_fetch_internal validates
  # report_type via arg_match0("ind", "con") before reaching the source;
  # the abort then fires at get_simple_csv().
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  expect_error(
    issuer_fetch("cad", "companhias",
              source = "cvm", report_type = "ind"),
    class = "cvmdata_error_input"
  )
})

# TTL gate -----------------------------------------------------------------

# Mock that fails the test if any HTTP call is performed. Used to prove
# the TTL shortcut bypasses both HEAD and GET.
no_http_mock <- function(req) {
  testthat::fail(
    sprintf("expected no HTTP call; got %s %s", req$method, req$url)
  )
}

test_that("download_with_etag skips HEAD when within TTL", {
  local_dfp_cache_with_sidecar(
    sidecar_meta = list(
      etag = "\"FRESH\"",
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = format(
        Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"
      )
    )
  )
  withr::local_options(cvmdata.cache_ttl_seconds = 30L * 24L * 3600L)

  result <- httr2::with_mocked_responses(
    no_http_mock,
    issuer_fetch("dfp", "bpa",
              report_type = "ind", year = 2024, source = "cvm")
  )
  expect_s3_class(result, "cvm_tbl")
})

test_that("download_with_etag triggers HEAD when fetched_at older than TTL", {
  local_dfp_cache_with_sidecar(
    sidecar_meta = list(
      etag = "\"FRESH\"",
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = "2020-01-01T00:00:00.000Z"
    )
  )
  withr::local_options(cvmdata.cache_ttl_seconds = 60L)

  head_called <- FALSE
  mock <- function(req) {
    if (identical(req$method, "HEAD")) {
      head_called <<- TRUE
      return(httr2::response(
        status_code = 200L,
        headers = list("ETag" = "\"FRESH\"")
      ))
    }
    testthat::fail("GET should not fire when HEAD matches cached ETag")
  }
  result <- httr2::with_mocked_responses(
    mock,
    issuer_fetch("dfp", "bpa",
              report_type = "ind", year = 2024, source = "cvm")
  )
  expect_true(head_called)
  expect_s3_class(result, "cvm_tbl")
})

test_that("cvmdata.cache_ttl_seconds = 0 forces HEAD on every call", {
  local_dfp_cache_with_sidecar(
    sidecar_meta = list(
      etag = "\"FRESH\"",
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = format(
        Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"
      )
    )
  )
  withr::local_options(cvmdata.cache_ttl_seconds = 0)

  head_called <- FALSE
  mock <- function(req) {
    if (identical(req$method, "HEAD")) {
      head_called <<- TRUE
      return(httr2::response(
        status_code = 200L,
        headers = list("ETag" = "\"FRESH\"")
      ))
    }
    testthat::fail("GET should not fire when HEAD matches cached ETag")
  }
  result <- httr2::with_mocked_responses(
    mock,
    issuer_fetch("dfp", "bpa",
              report_type = "ind", year = 2024, source = "cvm")
  )
  expect_true(head_called)
  expect_s3_class(result, "cvm_tbl")
})

test_that("cvmdata.cache_ttl_seconds = Inf disables HEAD with sidecar", {
  local_dfp_cache_with_sidecar(
    sidecar_meta = list(
      etag = "\"FRESH\"",
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = "2020-01-01T00:00:00.000Z"
    )
  )
  withr::local_options(cvmdata.cache_ttl_seconds = Inf)

  result <- httr2::with_mocked_responses(
    no_http_mock,
    issuer_fetch("dfp", "bpa",
              report_type = "ind", year = 2024, source = "cvm")
  )
  expect_s3_class(result, "cvm_tbl")
})

test_that("sidecar without fetched_at triggers HEAD even when TTL = Inf", {
  local_dfp_cache_with_sidecar(
    sidecar_meta = list(
      etag = "\"FRESH\"",
      last_modified = "Mon, 19 May 2026 00:00:00 GMT"
      # fetched_at deliberately absent (legacy sidecar)
    )
  )
  withr::local_options(cvmdata.cache_ttl_seconds = Inf)

  head_called <- FALSE
  mock <- function(req) {
    if (identical(req$method, "HEAD")) {
      head_called <<- TRUE
      return(httr2::response(
        status_code = 200L,
        headers = list("ETag" = "\"FRESH\"")
      ))
    }
    testthat::fail("GET should not fire when HEAD matches cached ETag")
  }
  result <- httr2::with_mocked_responses(
    mock,
    issuer_fetch("dfp", "bpa",
              report_type = "ind", year = 2024, source = "cvm")
  )
  expect_true(head_called)
  expect_s3_class(result, "cvm_tbl")
})

test_that("invalid cvmdata.cache_ttl_seconds falls back to HEAD", {
  local_dfp_cache_with_sidecar(
    sidecar_meta = list(
      etag = "\"FRESH\"",
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = format(
        Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"
      )
    )
  )
  withr::local_options(cvmdata.cache_ttl_seconds = "not-a-number")

  head_called <- FALSE
  mock <- function(req) {
    if (identical(req$method, "HEAD")) {
      head_called <<- TRUE
      return(httr2::response(
        status_code = 200L,
        headers = list("ETag" = "\"FRESH\"")
      ))
    }
    testthat::fail("GET should not fire when HEAD matches cached ETag")
  }
  result <- httr2::with_mocked_responses(
    mock,
    issuer_fetch("dfp", "bpa",
              report_type = "ind", year = 2024, source = "cvm")
  )
  expect_true(head_called)
  expect_s3_class(result, "cvm_tbl")
})

# CSV missing inside the ZIP ----------------------------------------------

test_that("get_yearly_csv aborts with parse error when CSV missing in ZIP", {
  # Fixture ZIP carries DMPL_ind but not DMPL_con. Asking for `con`
  # should reach `unzip()` -> no file extracted -> cvmdata_error_parse.
  paths <- local_dfp_cache_with_sidecar(
    sidecar_meta = list(
      etag = "\"fixture-etag\"",
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = "2026-05-19T00:00:00.000Z"
    )
  )
  mock <- function(req) {
    httr2::response(
      status_code = 200L,
      headers = list(
        "ETag" = "\"fixture-etag\"",
        "Last-Modified" = "Mon, 19 May 2026 00:00:00 GMT"
      )
    )
  }
  # utils::unzip() emits a warning ("requested file not found in the
  # zip file") *before* get_yearly_csv() checks file.exists() and
  # aborts. Swallow it so the test asserts only the abort class.
  expect_error(
    suppressWarnings(
      httr2::with_mocked_responses(
        mock,
        issuer_fetch("dfp", "dmpl",
                  report_type = "con", year = 2024, source = "cvm")
      )
    ),
    class = "cvmdata_error_parse"
  )
})
