# Regression tests for the Session 06 rename (cad_fetch removed,
# companies -> issuer, years -> year) and for the v0.3 deprecation of
# issuer_fetch() in favour of cvm_fetch(). The orchestration paths are
# covered by test-issuer-fetch-yearly.R and test-issuer-fetch-cad.R;
# this file pins down the deprecation surface.

# Setup -----------------------------------------------------------------

local_prepare_cad_cache <- function(envir = parent.frame()) {
  cache_root <- withr::local_tempdir(.local_envir = envir)
  withr::local_options(
    cvmdata.cache_dir = cache_root,
    lifecycle_verbosity = "quiet",
    .local_envir = envir
  )
  raw_dir <- file.path(cache_root, "raw", "companhias", "cad")
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

test_that("issuer_fetch is deprecated in favour of cvm_fetch", {
  skip_if_not_installed("httptest2")
  local_prepare_cad_cache()
  withr::local_options(lifecycle_verbosity = "warning")
  lifecycle::expect_deprecated(
    httr2::with_mocked_responses(
      function(req) fresh_head_response(),
      issuer_fetch("cad", "companhias", source = "cvm")
    ),
    regexp = "cvm_fetch"
  )
})

test_that("cad_fetch is no longer exported", {
  expect_false(exists(
    "cad_fetch",
    mode = "function",
    envir = asNamespace("cvmdata"),
    inherits = FALSE
  ))
})

test_that("issuer_fetch(years = ...) aborts with a migration hint", {
  withr::local_options(lifecycle_verbosity = "quiet")
  expect_error(
    issuer_fetch("cad", "companhias", years = 2024),
    class = "cvmdata_error_input"
  )
  expect_error(
    issuer_fetch("cad", "companhias", years = 2024),
    regexp = "year"
  )
})

test_that("issuer_fetch(companies = ...) aborts with a migration hint", {
  withr::local_options(lifecycle_verbosity = "quiet")
  expect_error(
    issuer_fetch("cad", "companhias", companies = "BCO BRASIL"),
    class = "cvmdata_error_input"
  )
  expect_error(
    issuer_fetch("cad", "companhias", companies = "BCO BRASIL"),
    regexp = "issuer"
  )
})

test_that("issuer_fetch rejects unknown extra arguments via ...", {
  withr::local_options(lifecycle_verbosity = "quiet")
  expect_error(
    issuer_fetch("cad", "companhias", bogus = 1),
    class = "cvmdata_error_input"
  )
})

test_that("issuer_fetch accepts a vector via the singular `issuer` arg", {
  skip_if_not_installed("httptest2")
  local_prepare_cad_cache()
  full <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("cad", "companhias", source = "cvm")
  )
  skip_if(nrow(full) < 2L, "fixture too small for vector smoke test")
  picks <- utils::head(full$cd_cvm, 2L)
  filtered <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch(
      "cad",
      "companhias",
      issuer = picks,
      source = "cvm"
    )
  )
  expect_true(all(filtered$cd_cvm %in% picks))
  expect_gte(nrow(filtered), length(picks))
})
