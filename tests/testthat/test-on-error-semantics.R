# Tests for the `on_error` argument of cvm_fetch(). Alt 3a scope
# (Sessão 3.7): on_error governs HTTP failures in yearly-partitioned
# batches; parse/validation failures remain under `validate`; single-
# year requests, non-yearly tables, and the implicit fallback from
# `years = NULL` always abort on HTTP failure.

# Helpers -----------------------------------------------------------------

# Materialise a cache that pretends the DFP 2024 ZIP is already
# downloaded and within TTL — so the test only exercises the HTTP path
# for years OTHER than 2024.
local_dfp_cache_2024_fresh <- function(envir = parent.frame()) {
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
  saveRDS(
    list(
      etag = "\"FRESH\"",
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = format(
        Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"
      )
    ),
    file.path(raw_dir, "dfp_cia_aberta_2024.zip.etag.rds")
  )
  list(cache_root = cache_root, raw_dir = raw_dir)
}

# Partial-batch failure ---------------------------------------------------

test_that("on_error = 'warn' emits warning and returns surviving years", {
  local_dfp_cache_2024_fresh()
  mock <- function(req) {
    if (grepl("_2023\\.zip", req$url)) {
      stop("simulated 503 for 2023")
    }
    testthat::fail(
      sprintf("unexpected request: %s %s", req$method, req$url)
    )
  }
  result <- NULL
  expect_warning(
    result <- httr2::with_mocked_responses(
      mock,
      cvm_fetch("dfp", "bpa",
                report_type = "ind", years = c(2023L, 2024L),
                source = "cvm", on_error = "warn")
    ),
    class = "cvmdata_warn_partial_failure"
  )
  expect_s3_class(result, "cvm_tbl")
  expect_gt(nrow(result), 0L)
})

test_that("on_error = 'silent' returns surviving years without warning", {
  local_dfp_cache_2024_fresh()
  mock <- function(req) {
    if (grepl("_2023\\.zip", req$url)) {
      stop("simulated 503 for 2023")
    }
    testthat::fail(
      sprintf("unexpected request: %s %s", req$method, req$url)
    )
  }
  result <- NULL
  expect_no_warning(
    result <- httr2::with_mocked_responses(
      mock,
      cvm_fetch("dfp", "bpa",
                report_type = "ind", years = c(2023L, 2024L),
                source = "cvm", on_error = "silent")
    )
  )
  expect_s3_class(result, "cvm_tbl")
  expect_gt(nrow(result), 0L)
})

test_that("on_error = 'abort' (default) propagates HTTP error in batch", {
  local_dfp_cache_2024_fresh()
  mock <- function(req) {
    if (grepl("_2023\\.zip", req$url)) {
      stop("simulated 503 for 2023")
    }
    testthat::fail(
      sprintf("unexpected request: %s %s", req$method, req$url)
    )
  }
  expect_error(
    httr2::with_mocked_responses(
      mock,
      cvm_fetch("dfp", "bpa",
                report_type = "ind", years = c(2023L, 2024L),
                source = "cvm")
    ),
    class = "cvmdata_error_http"
  )
})

# Total batch failure -----------------------------------------------------

test_that("on_error = 'warn' aborts when every year in the batch fails", {
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  mock <- function(req) {
    stop("simulated total outage")
  }
  expect_error(
    httr2::with_mocked_responses(
      mock,
      cvm_fetch("dfp", "bpa",
                report_type = "ind", years = c(2022L, 2023L),
                source = "cvm", on_error = "warn")
    ),
    class = "cvmdata_error_http"
  )
})

test_that("on_error = 'silent' aborts when every year in the batch fails", {
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  mock <- function(req) {
    stop("simulated total outage")
  }
  expect_error(
    httr2::with_mocked_responses(
      mock,
      cvm_fetch("dfp", "bpa",
                report_type = "ind", years = c(2022L, 2023L),
                source = "cvm", on_error = "silent")
    ),
    class = "cvmdata_error_http"
  )
})

# Single-year and non-yearly: on_error has no parcial to return -----------

test_that("on_error = 'warn' aborts on single-year (no parcial)", {
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  mock <- function(req) {
    stop("simulated outage for 2024")
  }
  expect_error(
    httr2::with_mocked_responses(
      mock,
      cvm_fetch("dfp", "bpa",
                report_type = "ind", years = 2024L,
                source = "cvm", on_error = "warn")
    ),
    class = "cvmdata_error_http"
  )
})

test_that("on_error = 'warn' aborts on HTTP failure for non-yearly (CAD)", {
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  mock <- function(req) {
    stop("simulated outage for CAD CSV")
  }
  expect_error(
    httr2::with_mocked_responses(
      mock,
      cvm_fetch("cad", "companhias",
                source = "cvm", on_error = "warn")
    ),
    class = "cvmdata_error_http"
  )
})
