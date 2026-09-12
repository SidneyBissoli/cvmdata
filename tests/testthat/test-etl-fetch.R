# Tests for inst/etl/01-fetch-cvm.R. Sources the script with the
# testing guard so the helpers are loaded but the CLI driver does not
# fire. No test touches the network: `fetch_one` is exercised against a
# mocked `issuer_fetch`.
#
# What is being pinned here is the circuit breaker added after the
# 2026-09-08 mirror run, where the `fre` job logged "0 ok / 612 failed"
# — every one a TCP connect timeout to the portal — and took 5 h 51 min
# to give up, just short of GitHub's 6 h job ceiling.

load_etl_fetcher <- function() {
  # Prefer the installed copy (`<libpath>/cvmdata/etl/`) under
  # R CMD check; fall back to the source tree under devtools::test().
  installed <- system.file("etl", "01-fetch-cvm.R", package = "cvmdata")
  script <- if (nzchar(installed)) {
    installed
  } else {
    normalizePath(test_path("..", "..", "inst", "etl", "01-fetch-cvm.R"),
                  winslash = "/")
  }
  withr::local_options(cvmdata.etl_testing = TRUE,
                       .local_envir = parent.frame())
  sys.source(script, envir = parent.frame())
}

# --- fetch_breaker_tripped ----------------------------------------------

test_that("the breaker stays open while nothing has been fetched yet", {
  load_etl_fetcher()
  expect_false(fetch_breaker_tripped(0L, 7L, limit = 8L))
  expect_true(fetch_breaker_tripped(0L, 8L, limit = 8L))
  expect_true(fetch_breaker_tripped(0L, 612L, limit = 8L))
})

test_that("one success keeps the breaker from ever tripping", {
  load_etl_fetcher()
  # The whole point of the `n_ok == 0` condition: once the portal has
  # answered once, a long run of failures is data-shaped (that table
  # does not exist that year), which stage 02 tolerates by design.
  expect_false(fetch_breaker_tripped(1L, 100L, limit = 8L))
})

test_that("the streak limit comes from the option, not a literal", {
  load_etl_fetcher()
  withr::local_options(cvmdata.etl_transport_streak = 2L)
  expect_identical(fetch_transport_streak_limit(), 2L)
  expect_true(fetch_breaker_tripped(0L, 2L))
  expect_false(fetch_breaker_tripped(0L, 1L))
})

test_that("the default streak limit is 8", {
  load_etl_fetcher()
  withr::local_options(cvmdata.etl_transport_streak = NULL)
  expect_identical(fetch_transport_streak_limit(), 8L)
})

# --- fetch_one ----------------------------------------------------------

test_that("fetch_one reports a transport failure as transport", {
  load_etl_fetcher()
  local_mocked_bindings(
    issuer_fetch = function(...) {
      rlang::abort(
        "HTTP GET failed",
        class = c("cvmdata_error_http_transport", "cvmdata_error_http",
                  "cvmdata_error")
      )
    }
  )
  out <- suppressMessages(fetch_one("fre", "acao_entregue", 2010L, NULL))
  expect_false(out$ok)
  expect_true(out$transport)
})

test_that("fetch_one does not call an HTTP status a transport failure", {
  load_etl_fetcher()
  local_mocked_bindings(
    issuer_fetch = function(...) {
      rlang::abort(
        "HTTP GET failed",
        class = c("cvmdata_error_http", "cvmdata_error")
      )
    }
  )
  out <- suppressMessages(fetch_one("fre", "acao_entregue", 2010L, NULL))
  expect_false(out$ok)
  expect_false(out$transport)
})

test_that("fetch_one reports a missing ZIP member as non-transport", {
  load_etl_fetcher()
  # A detail table absent from that year's ZIP is the benign case the
  # ETL has always tolerated; it must never feed the breaker.
  local_mocked_bindings(
    issuer_fetch = function(...) {
      rlang::abort(
        "CSV not found inside ZIP",
        class = c("cvmdata_error_zip_member_missing", "cvmdata_error_parse",
                  "cvmdata_error")
      )
    }
  )
  out <- suppressMessages(fetch_one("fre", "acao_entregue", 2010L, NULL))
  expect_false(out$ok)
  expect_false(out$transport)
})

test_that("fetch_all stops the walk once the breaker trips", {
  load_etl_fetcher()
  withr::local_options(cvmdata.etl_transport_streak = 3L)
  seen <- 0L
  # `fetch_all` resolves `fetch_one` lexically in the environment the
  # script was sourced into, which is this test's frame — so a plain
  # assignment here is the mock.
  fetch_one <- function(dataset, tbl, year, report_type) {
    seen <<- seen + 1L
    list(ok = FALSE, transport = TRUE)
  }
  out <- suppressMessages(
    fetch_all("fre", "acao_entregue", 2010:2025)
  )
  expect_true(out$tripped)
  # 16 years were on offer; the breaker cut the walk at the third.
  expect_identical(seen, 3L)
  expect_identical(out$n_fail, 3L)
  expect_identical(out$n_transport, 3L)
})

test_that("fetch_all walks every pair when the portal answers", {
  load_etl_fetcher()
  withr::local_options(cvmdata.etl_transport_streak = 3L)
  fetch_one <- function(dataset, tbl, year, report_type) {
    list(ok = TRUE, transport = FALSE)
  }
  out <- suppressMessages(fetch_all("fre", "acao_entregue", 2010:2025))
  expect_false(out$tripped)
  expect_identical(out$n_ok, 16L)
  expect_identical(out$n_fail, 0L)
})

test_that("fetch_all never trips after something has come through", {
  load_etl_fetcher()
  withr::local_options(cvmdata.etl_transport_streak = 3L)
  # First year succeeds, every later one fails at the transport level:
  # the long streak that follows is not enough, because the portal has
  # demonstrably answered this runner.
  n <- 0L
  fetch_one <- function(dataset, tbl, year, report_type) {
    n <<- n + 1L
    if (n == 1L) list(ok = TRUE, transport = FALSE) else
      list(ok = FALSE, transport = TRUE)
  }
  out <- suppressMessages(fetch_all("fre", "acao_entregue", 2010:2025))
  expect_false(out$tripped)
  expect_identical(out$n_ok, 1L)
  expect_identical(out$n_fail, 15L)
})

test_that("fetch_all counts both report_type variants of a table", {
  load_etl_fetcher()
  fetch_one <- function(dataset, tbl, year, report_type) {
    list(ok = TRUE, transport = FALSE)
  }
  # `bpa` is one of the tables published in `ind` and `con` flavours, so
  # a single year is two fetches, not one.
  skip_if_not("bpa" %in% mirror_variant_tables)
  out <- suppressMessages(fetch_all("dfp", "bpa", 2024L))
  expect_identical(out$n_ok, 2L)
})

test_that("fetch_one reports success and carries year = NA through", {
  load_etl_fetcher()
  seen <- NULL
  local_mocked_bindings(
    issuer_fetch = function(dataset, table, year = NULL,
                            report_type = NULL, ...) {
      seen <<- list(year = year, report_type = report_type)
      tibble::tibble(x = 1L)
    }
  )
  out <- fetch_one("cad", "companhias", NA_integer_, NULL)
  expect_true(out$ok)
  expect_false(out$transport)
  # Non-yearly datasets (CAD) pass year = NA in the loop and must reach
  # issuer_fetch as NULL, its own "latest published" sentinel.
  expect_null(seen$year)
  expect_null(seen$report_type)
})
