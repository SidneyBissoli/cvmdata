# Tests for inst/etl/util-gh.R: the publish waits out a spent GitHub API
# quota instead of leaving `-latest` half uploaded (2026-10-27: itr-latest
# had 200 of 296 assets replaced when the GITHUB_TOKEN quota ran out).

load_etl_gh <- function() {
  skip_if_not_installed("jsonlite")
  installed <- system.file("etl", "util-gh.R", package = "cvmdata")
  script <- if (nzchar(installed)) {
    installed
  } else {
    normalizePath(
      test_path("..", "..", "inst", "etl", "util-gh.R"),
      winslash = "/"
    )
  }
  sys.source(script, envir = parent.frame())
}

rate_limit_json <- function(remaining, reset) {
  sprintf(
    '{"resources": {"core": {"limit": 1000, "remaining": %s, "reset": %s}}}',
    remaining,
    reset
  )
}

test_that("quota_wait_seconds waits until the reset only when spent", {
  load_etl_gh()
  now <- as.POSIXct(1800000000, origin = "1970-01-01", tz = "UTC")
  expect_identical(
    quota_wait_seconds(rate_limit_json(0, 1800000600), now = now),
    605
  )
  expect_identical(
    quota_wait_seconds(rate_limit_json(12, 1800000600), now = now),
    0
  )
  # A reset already in the past still leaves the slack, never a negative.
  expect_identical(
    quota_wait_seconds(rate_limit_json(0, 1799999000), now = now),
    5
  )
})

test_that("quota_wait_seconds never stalls on an unreadable answer", {
  load_etl_gh()
  expect_identical(quota_wait_seconds(character()), 0)
  expect_identical(quota_wait_seconds("not json"), 0)
  expect_identical(quota_wait_seconds('{"resources": {}}'), 0)
})

test_that("gh_quota_aware runs the call again after waiting the quota", {
  load_etl_gh()
  # Both helpers resolve system2/wait_for_api_quota in the environment
  # the script was sourced into, this test's frame: plain assignments
  # here are the mocks.
  calls <- 0L
  system2 <- function(...) {
    calls <<- calls + 1L
    if (calls == 1L) 1L else 0L
  }
  waits <- 0L
  wait_for_api_quota <- function(...) {
    waits <<- waits + 1L
    TRUE
  }
  expect_identical(gh_quota_aware(c("release", "upload")), 0L)
  expect_identical(calls, 2L)
  expect_identical(waits, 1L)
})

test_that("gh_quota_aware returns other failures without waiting", {
  load_etl_gh()
  calls <- 0L
  system2 <- function(...) {
    calls <<- calls + 1L
    1L
  }
  wait_for_api_quota <- function(...) FALSE
  expect_identical(gh_quota_aware(c("release", "upload")), 1L)
  expect_identical(calls, 1L)
})

test_that("gh_quota_aware gives up after its quota waits", {
  load_etl_gh()
  calls <- 0L
  system2 <- function(...) {
    calls <<- calls + 1L
    1L
  }
  wait_for_api_quota <- function(...) TRUE
  expect_identical(gh_quota_aware(c("x"), quota_waits = 2L), 1L)
  expect_identical(calls, 3L)
})
