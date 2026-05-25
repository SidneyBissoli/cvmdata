# Unit tests for the public cvm_source_*() family + the cvm_fetch()
# integration path (arg explicit > option > built-in default).

# cvm_source_get() -------------------------------------------------------

test_that("cvm_source_get() defaults to 'mirror' when option unset", {
  withr::local_options(cvmdata.source = NULL)
  expect_identical(cvm_source_get(), "mirror")
})

test_that("cvm_source_get() reflects cvmdata.source option override", {
  withr::local_options(cvmdata.source = "mirror")
  expect_identical(cvm_source_get(), "mirror")
})

test_that("cvm_source_get() does not validate the option value", {
  # `get` is a read-only accessor; if a user/script puts a bogus value
  # in the option, that's surfaced at the next `cvm_fetch()` via the
  # arg_match0 inside `cvm_fetch_internal()`. Asserting the leniency
  # explicitly so a future refactor doesn't silently start filtering.
  withr::local_options(cvmdata.source = "bogus")
  expect_identical(cvm_source_get(), "bogus")
})

# cvm_source_set() -------------------------------------------------------

test_that("cvm_source_set() updates the option to 'cvm'", {
  withr::local_options(cvmdata.source = NULL)
  expect_message(
    out <- cvm_source_set("cvm"),
    "Source backend set"
  )
  expect_identical(out, "cvm")
  expect_identical(getOption("cvmdata.source"), "cvm")
})

test_that("cvm_source_set() updates the option to 'mirror'", {
  withr::local_options(cvmdata.source = NULL)
  expect_message(
    out <- cvm_source_set("mirror"),
    "Source backend set"
  )
  expect_identical(out, "mirror")
  expect_identical(getOption("cvmdata.source"), "mirror")
})

test_that("cvm_source_set() returns the source invisibly", {
  withr::local_options(cvmdata.source = NULL)
  expect_invisible(suppressMessages(cvm_source_set("cvm")))
})

test_that("cvm_source_set() aborts on value outside the domain", {
  expect_error(
    cvm_source_set("bogus"),
    class = "rlang_error" # rlang::arg_match0()
  )
})

test_that("cvm_source_set() aborts on non-character / multi-element input", {
  expect_error(
    cvm_source_set(123),
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_source_set(NULL),
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_source_set(c("cvm", "mirror")),
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_source_set(NA_character_),
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_source_set(""),
    class = "cvmdata_error_input"
  )
})

# Integration with cvm_fetch() ------------------------------------------

# Helper: pre-populate a tempdir cache with the DFP fixture so the
# `source = "cvm"` path can resolve without touching the network.
local_prepare_dfp_cache <- function(envir = parent.frame()) {
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

test_that("cvm_fetch() reads cvmdata.source when arg is NULL (default)", {
  local_prepare_dfp_cache()
  withr::local_options(cvmdata.source = "cvm")
  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    cvm_fetch("dfp", "bpa",
              report_type = "ind", years = 2024)
  )
  expect_identical(attr(result, "source"), "cvm")
})

test_that("cvm_fetch() explicit source argument wins over option", {
  local_prepare_dfp_cache()
  # Option says mirror, arg says cvm — arg must win.
  withr::local_options(cvmdata.source = "mirror")
  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    cvm_fetch("dfp", "bpa",
              report_type = "ind", years = 2024,
              source = "cvm")
  )
  expect_identical(attr(result, "source"), "cvm")
})

# The `source = "mirror"` path (live since the mirror backend landed)
# is covered end-to-end in test-source-mirror-duckdb.R, which mocks the
# GitHub API and serves parquet fixtures locally. Here we only verify
# that arg-vs-option resolution feeds the right backend; the backend
# itself is exercised there.

test_that("cvm_fetch() aborts on source outside domain", {
  withr::local_options(cvmdata.source = NULL)
  expect_error(
    cvm_fetch("dfp", "bpa", source = "bogus"),
    class = "rlang_error"
  )
})
