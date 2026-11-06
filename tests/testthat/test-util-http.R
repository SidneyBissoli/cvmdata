# Tests for R/util-http.R, the retry policy of every network request of
# the package (decision of 2026-11-05).
#
# httr2 answers a mocked request before its retry loop runs (measured:
# `with_mocked_responses()` returns the first response), so what is
# pinned here is the rule (which failures are tried again), that every
# request of the package carries it, and what the final error says. The
# waiting itself is httr2's.

# The condition httr2 raises for a response of `status`.
http_condition <- function(status) {
  httr2::with_mocked_responses(
    function(req) httr2::response(status),
    tryCatch(
      httr2::req_perform(httr2::request("https://example.test/x")),
      error = identity
    )
  )
}

test_that("only a failure of the server or of the connection is retried", {
  transient <- function(status) {
    cvmdata:::http_is_transient(httr2::response(status))
  }
  expect_true(all(vapply(
    c(429L, 500L, 502L, 503L, 504L),
    transient,
    logical(1L)
  )))
  # the package's own doing: the same request brings the same answer
  expect_false(any(vapply(
    c(400L, 401L, 403L, 404L, 410L, 422L),
    transient,
    logical(1L)
  )))
  expect_false(transient(200L))
})

test_that("the policy is four attempts, failures of the connection included", {
  req <- cvmdata:::req_retry_transient(httr2::request("https://example.test"))
  expect_identical(req$policies$retry_max_tries, 4L)
  expect_true(req$policies$retry_on_failure)
  expect_true(req$policies$retry_is_transient(httr2::response(504L)))
  expect_false(req$policies$retry_is_transient(httr2::response(404L)))
})

test_that("the final error says it was retried only when it was", {
  expect_true(cvmdata:::http_failed_transiently(http_condition(504L)))
  expect_false(cvmdata:::http_failed_transiently(http_condition(404L)))
  expect_true(cvmdata:::http_failed_transiently(503L))
  expect_false(cvmdata:::http_failed_transiently(403L))
  no_response <- structure(
    class = c("httr2_failure", "httr2_error", "error", "condition"),
    list(message = "Could not resolve host")
  )
  expect_true(cvmdata:::http_failed_transiently(no_response))
  # an error of the package's own code never reaches the policy
  expect_false(cvmdata:::http_failed_transiently(simpleError("a bug")))

  hint <- cvmdata:::http_retry_hint(http_condition(504L))
  expect_named(hint, "i")
  expect_match(hint, "each of 4 attempts")
  expect_null(cvmdata:::http_retry_hint(http_condition(404L)))
})

# Runs `code` with every request answered by `respond(req)` and returns
# the retry policy each requested URL carried.
policies_seen <- function(respond, code) {
  seen <- list()
  httr2::with_mocked_responses(
    function(req) {
      seen[[req$url]] <<- req$policies
      respond(req)
    },
    code
  )
  seen
}

expect_policy <- function(seen, pattern) {
  hit <- grep(pattern, names(seen), fixed = TRUE)
  expect_length(hit, 1L)
  pol <- seen[[hit]]
  expect_identical(pol$retry_max_tries, 4L)
  expect_true(pol$retry_on_failure)
  expect_true(pol$retry_is_transient(httr2::response(504L)))
}

test_that("the mirror's listing, index and download carry the policy", {
  mirror_assets_cache_clear()
  release <- list(
    tag_name = "mirror-test-latest",
    assets = list(
      list(
        name = "cia__part-0.parquet",
        browser_download_url = "https://example.test/cia__part-0.parquet",
        size = 3L
      ),
      list(
        name = "__source_hash.json",
        browser_download_url = "https://example.test/__source_hash.json",
        size = 10L
      )
    )
  )
  dest <- withr::local_tempfile(fileext = ".parquet")
  seen <- policies_seen(
    function(req) {
      if (grepl("api.github.com", req$url, fixed = TRUE)) {
        return(httr2::response_json(body = release))
      }
      if (grepl("__source_hash.json", req$url, fixed = TRUE)) {
        return(httr2::response_json(body = list(hash = "abc")))
      }
      httr2::response(200L, body = as.raw(1:3))
    },
    {
      cvmdata:::mirror_list_assets("companhias", "http_policy", refresh = TRUE)
      cvmdata:::mirror_download_asset(
        "https://example.test/cia__part-0.parquet",
        dest
      )
    }
  )
  expect_policy(seen, "api.github.com")
  expect_policy(seen, "__source_hash.json")
  expect_policy(seen, "cia__part-0.parquet")
  expect_identical(readBin(dest, "raw", 3L), as.raw(1:3))
})

test_that("the CVM listing, HEAD and GET carry the policy", {
  dir_url <- "https://example.test/http-policy/DADOS/"
  url <- "https://example.test/http-policy/file.zip"
  dest <- withr::local_tempfile(fileext = ".zip")
  seen <- policies_seen(
    function(req) {
      if (identical(req$url, dir_url)) {
        return(httr2::response(200L, body = charToRaw("x_2024.zip")))
      }
      httr2::response(200L, body = as.raw(1:3))
    },
    {
      cvmdata:::get_years_from_listing(dir_url, "x_(\\d{4})\\.zip")
      cvmdata:::download_with_etag(url, dest)
    }
  )
  expect_policy(seen, dir_url)
  expect_policy(seen, url)

  # a cached copy past its TTL is revalidated with a HEAD first
  methods <- character()
  httr2::with_mocked_responses(
    function(req) {
      methods <<- c(methods, req$method %||% "GET")
      expect_identical(req$policies$retry_max_tries, 4L)
      httr2::response(200L, body = as.raw(1:3))
    },
    withr::with_options(
      list(cvmdata.cache_ttl_seconds = 0),
      cvmdata:::download_with_etag(url, dest)
    )
  )
  expect_identical(methods[[1L]], "HEAD")
})

test_that("a download that fails transiently says it was retried", {
  dest <- withr::local_tempfile(fileext = ".parquet")
  fetch <- function(status) {
    httr2::with_mocked_responses(
      function(req) httr2::response(status),
      cvmdata:::mirror_download_asset("https://example.test/a.parquet", dest)
    )
  }
  expect_error(fetch(504L), "each of 4 attempts", class = "cvmdata_error_http")
  err <- expect_error(fetch(404L), class = "cvmdata_error_http")
  expect_no_match(conditionMessage(err), "attempts")
})
