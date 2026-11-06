# Tests for R/util-mirror-assets.R. Parser + filter logic are pure
# (no I/O). The GitHub API inventory is exercised with httr2 mocked
# responses; tests never touch the network.

# parse_mirror_asset_name -------------------------------------------------

test_that("parse_mirror_asset_name decodes CAD (no partition)", {
  out <- cvmdata:::parse_mirror_asset_name("companhias__part-0.parquet")
  expect_identical(out$table, "companhias")
  expect_true(is.na(out$report_type))
  expect_true(is.na(out$year))
})

test_that("parse_mirror_asset_name decodes yearly-only (sanitised)", {
  out <- cvmdata:::parse_mirror_asset_name(
    "submissao__year.2024__part-0.parquet"
  )
  expect_identical(out$table, "submissao")
  expect_identical(out$year, 2024L)
  expect_true(is.na(out$report_type))
})

test_that("parse_mirror_asset_name decodes yearly-only (raw =)", {
  out <- cvmdata:::parse_mirror_asset_name(
    "submissao__year=2024__part-0.parquet"
  )
  expect_identical(out$year, 2024L)
})

test_that("parse_mirror_asset_name decodes variant + yearly (sanitised)", {
  out <- cvmdata:::parse_mirror_asset_name(
    "bpa__report_type.ind__year.2024__part-0.parquet"
  )
  expect_identical(out$table, "bpa")
  expect_identical(out$report_type, "ind")
  expect_identical(out$year, 2024L)
})

test_that("parse_mirror_asset_name decodes variant + yearly (raw =)", {
  out <- cvmdata:::parse_mirror_asset_name(
    "bpa__report_type=ind__year=2024__part-0.parquet"
  )
  expect_identical(out$report_type, "ind")
  expect_identical(out$year, 2024L)
})

test_that("parse_mirror_asset_name returns NULL for hash sidecar", {
  expect_null(cvmdata:::parse_mirror_asset_name("__source_hash.json"))
})

test_that("parse_mirror_asset_name aborts on non-parquet name", {
  expect_error(
    cvmdata:::parse_mirror_asset_name("README.md"),
    class = "cvmdata_error_parse"
  )
})

test_that("parse_mirror_asset_name aborts on missing part-N suffix", {
  expect_error(
    cvmdata:::parse_mirror_asset_name("bpa__year.2024.parquet"),
    class = "cvmdata_error_parse"
  )
})

test_that("parse_mirror_asset_name tags current and history assets", {
  current <- cvmdata:::parse_mirror_asset_name(
    "dre__report_type.con__year.2023__part-0.parquet"
  )
  expect_identical(current$kind, "current")
  history <- cvmdata:::parse_mirror_asset_name(
    "dre__report_type.con__year.2023__history.parquet"
  )
  expect_identical(
    history,
    list(table = "dre", report_type = "con", year = 2023L, kind = "history")
  )
  raw <- cvmdata:::parse_mirror_asset_name(
    "dre__report_type=con__year=2023__history.parquet"
  )
  expect_identical(raw$kind, "history")
})

test_that("parse_mirror_asset_name aborts on unknown partition key", {
  expect_error(
    cvmdata:::parse_mirror_asset_name(
      "bpa__quarter.Q1__part-0.parquet"
    ),
    class = "cvmdata_error_parse"
  )
})

test_that("parse_mirror_asset_name aborts on non-integer year", {
  expect_error(
    cvmdata:::parse_mirror_asset_name(
      "bpa__year.abcd__part-0.parquet"
    ),
    class = "cvmdata_error_parse"
  )
})

test_that("parse_mirror_asset_name aborts on malformed segment", {
  expect_error(
    cvmdata:::parse_mirror_asset_name(
      "bpa__noequalshere__part-0.parquet"
    ),
    class = "cvmdata_error_parse"
  )
})

# filter_mirror_assets ----------------------------------------------------

sample_inventory <- function() {
  tibble::tibble(
    name = c(
      "bpa__report_type.ind__year.2023__part-0.parquet",
      "bpa__report_type.ind__year.2024__part-0.parquet",
      "bpa__report_type.con__year.2024__part-0.parquet",
      "bpp__report_type.ind__year.2024__part-0.parquet",
      "submissao__year.2024__part-0.parquet",
      "__source_hash.json"
    ),
    url = sprintf(
      "https://example.test/%s",
      c(
        "bpa-ind-2023",
        "bpa-ind-2024",
        "bpa-con-2024",
        "bpp-ind-2024",
        "sub-2024",
        "hash"
      )
    ),
    size_bytes = c(1000L, 1100L, 1200L, 900L, 800L, 200L)
  )
}

test_that("filter_mirror_assets returns single (table, year, variant)", {
  inv <- sample_inventory()
  out <- cvmdata:::filter_mirror_assets(
    inv,
    table = "bpa",
    year = 2024L,
    report_type = "ind"
  )
  expect_equal(nrow(out), 1L)
  expect_identical(out$year, 2024L)
  expect_identical(out$report_type, "ind")
  expect_identical(out$table, "bpa")
})

test_that("filter_mirror_assets keeps multiple years", {
  inv <- sample_inventory()
  out <- cvmdata:::filter_mirror_assets(
    inv,
    table = "bpa",
    year = c(2023L, 2024L),
    report_type = "ind"
  )
  expect_equal(nrow(out), 2L)
  expect_setequal(out$year, c(2023L, 2024L))
})

test_that("filter_mirror_assets honours year = NULL", {
  inv <- sample_inventory()
  out <- cvmdata:::filter_mirror_assets(
    inv,
    table = "bpa",
    year = NULL,
    report_type = "ind"
  )
  expect_equal(nrow(out), 2L)
})

test_that("filter_mirror_assets honours report_type = NULL", {
  inv <- sample_inventory()
  out <- cvmdata:::filter_mirror_assets(
    inv,
    table = "bpa",
    year = 2024L,
    report_type = NULL
  )
  # ind + con for 2024
  expect_equal(nrow(out), 2L)
  expect_setequal(out$report_type, c("ind", "con"))
})

test_that("filter_mirror_assets excludes hash sidecar implicitly", {
  inv <- sample_inventory()
  out <- cvmdata:::filter_mirror_assets(
    inv,
    table = "submissao",
    year = 2024L,
    report_type = NULL
  )
  expect_equal(nrow(out), 1L)
  expect_identical(out$table, "submissao")
})

test_that("filter_mirror_assets returns 0 rows when no match", {
  inv <- sample_inventory()
  out <- cvmdata:::filter_mirror_assets(
    inv,
    table = "bpa",
    year = 1999L,
    report_type = "ind"
  )
  expect_equal(nrow(out), 0L)
})

test_that("filter_mirror_assets keeps the history assets only on request", {
  assets <- tibble::tibble(
    name = c(
      "dre__report_type.con__year.2023__part-0.parquet",
      "dre__report_type.con__year.2023__history.parquet",
      "dre__report_type.ind__year.2023__part-0.parquet"
    ),
    url = paste0("https://example.test/", name),
    size_bytes = c(10L, 20L, 30L)
  )
  current <- cvmdata:::filter_mirror_assets(
    assets,
    table = "dre",
    year = 2023L,
    report_type = "con"
  )
  expect_identical(current$kind, "current")
  both <- cvmdata:::filter_mirror_assets(
    assets,
    table = "dre",
    year = 2023L,
    report_type = "con",
    kind = c("current", "history")
  )
  expect_identical(both$kind, c("current", "history"))
  expect_identical(both$year, c(2023L, 2023L))
})

test_that("mirror_l3_path places the history asset next to the current one", {
  withr::local_options(cvmdata.cache_dir = withr::local_tempdir())
  current <- cvmdata:::mirror_l3_path("dfp", "dre", 2023L, "con")
  history <- cvmdata:::mirror_l3_path("dfp", "dre", 2023L, "con", "history")
  expect_identical(dirname(current), dirname(history))
  expect_identical(basename(current), "part-0.parquet")
  expect_identical(basename(history), "history.parquet")
})

test_that("filter_mirror_assets handles empty inventory", {
  inv <- tibble::tibble(
    name = character(0L),
    url = character(0L),
    size_bytes = integer(0L)
  )
  out <- cvmdata:::filter_mirror_assets(
    inv,
    table = "bpa",
    year = 2024L,
    report_type = "ind"
  )
  expect_equal(nrow(out), 0L)
  expect_true(all(c("table", "year", "report_type") %in% names(out)))
})

# mirror_list_assets ------------------------------------------------------

# Build a fake GitHub API response with the given asset names. Sizes
# and URLs are synthetic.
fake_github_release <- function(asset_names, base = "https://example.test") {
  list(
    tag_name = "mirror-test-latest",
    assets = lapply(asset_names, function(n) {
      list(
        name = n,
        browser_download_url = sprintf("%s/%s", base, n),
        size = nchar(n) * 10L
      )
    })
  )
}

test_that("mirror_list_assets parses a GitHub release JSON", {
  cvmdata:::mirror_assets_cache_clear()
  body <- fake_github_release(c(
    "bpa__report_type.ind__year.2024__part-0.parquet",
    "submissao__year.2024__part-0.parquet",
    "__source_hash.json"
  ))
  mock <- function(req) {
    if (grepl("api.github.com", req$url, fixed = TRUE)) {
      return(httr2::response_json(
        status_code = 200L,
        body = body
      ))
    }
    if (grepl("__source_hash.json", req$url)) {
      return(httr2::response_json(
        status_code = 200L,
        body = list(hash = "abc123", components = list())
      ))
    }
    httr2::response(404L)
  }
  out <- httr2::with_mocked_responses(
    mock,
    cvmdata:::mirror_list_assets("companhias", "dfp_test1", refresh = TRUE)
  )
  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 3L)
  expect_identical(
    attr(out, "release_tag"),
    "mirror-companhias-dfp_test1-latest"
  )
})

test_that("mirror_list_assets caches per session", {
  cvmdata:::mirror_assets_cache_clear()
  body <- fake_github_release("companhias__part-0.parquet")
  n_calls <- 0L
  mock <- function(req) {
    n_calls <<- n_calls + 1L
    if (grepl("api.github.com", req$url, fixed = TRUE)) {
      return(httr2::response_json(status_code = 200L, body = body))
    }
    httr2::response(404L)
  }
  httr2::with_mocked_responses(
    mock,
    {
      cvmdata:::mirror_list_assets("companhias", "dfp_test2", refresh = TRUE)
      cvmdata:::mirror_list_assets("companhias", "dfp_test2")
      cvmdata:::mirror_list_assets("companhias", "dfp_test2")
    }
  )
  # Only the first call (refresh = TRUE) hits the API. The release
  # has no __source_hash.json so no second GET happens.
  expect_equal(n_calls, 1L)
})

test_that("mirror_list_assets aborts on HTTP 404", {
  cvmdata:::mirror_assets_cache_clear()
  mock <- function(req) {
    httr2::response(status_code = 404L, body = "Not Found")
  }
  expect_error(
    httr2::with_mocked_responses(
      mock,
      cvmdata:::mirror_list_assets("companhias", "nope_dataset", refresh = TRUE)
    ),
    class = "cvmdata_error_http"
  )
})

test_that("mirror_list_assets aborts on network failure", {
  cvmdata:::mirror_assets_cache_clear()
  mock <- function(req) stop("simulated DNS error")
  expect_error(
    httr2::with_mocked_responses(
      mock,
      cvmdata:::mirror_list_assets(
        "companhias",
        "net_fail_dataset",
        refresh = TRUE
      )
    ),
    class = "cvmdata_error_http"
  )
})

test_that("mirror_list_assets attaches source_hash attribute", {
  cvmdata:::mirror_assets_cache_clear()
  body <- fake_github_release(c(
    "companhias__part-0.parquet",
    "__source_hash.json"
  ))
  mock <- function(req) {
    if (grepl("api.github.com", req$url, fixed = TRUE)) {
      return(httr2::response_json(status_code = 200L, body = body))
    }
    if (grepl("__source_hash.json", req$url)) {
      return(httr2::response_json(
        status_code = 200L,
        body = list(hash = "deadbeef", components = list())
      ))
    }
    httr2::response(404L)
  }
  out <- httr2::with_mocked_responses(
    mock,
    cvmdata:::mirror_list_assets("companhias", "dfp_test_hash", refresh = TRUE)
  )
  expect_identical(attr(out, "source_hash"), "deadbeef")
})

test_that("mirror_list_assets returns NA hash when sidecar absent", {
  cvmdata:::mirror_assets_cache_clear()
  body <- fake_github_release("companhias__part-0.parquet")
  mock <- function(req) {
    if (grepl("api.github.com", req$url, fixed = TRUE)) {
      return(httr2::response_json(status_code = 200L, body = body))
    }
    httr2::response(404L)
  }
  out <- httr2::with_mocked_responses(
    mock,
    cvmdata:::mirror_list_assets(
      "companhias",
      "dfp_test_no_hash",
      refresh = TRUE
    )
  )
  expect_true(is.na(attr(out, "source_hash")))
})

# A release that publishes a sidecar, with the sidecar answered by
# `sidecar(req)` and every request counted in the caller's `n_calls`.
unread_mock <- function(sidecar, count = function() NULL) {
  body <- fake_github_release(c(
    "companhias__part-0.parquet",
    "__source_hash.json"
  ))
  function(req) {
    count()
    if (grepl("api.github.com", req$url, fixed = TRUE)) {
      return(httr2::response_json(status_code = 200L, body = body))
    }
    sidecar(req)
  }
}

test_that("a sidecar that cannot be read is a warning, never silence", {
  cvmdata:::mirror_assets_cache_clear()
  n_calls <- 0L
  mock <- unread_mock(
    function(req) httr2::response(504L),
    function() n_calls <<- n_calls + 1L
  )
  list_it <- function() {
    cvmdata:::mirror_list_assets("companhias", "unread_504")
  }
  w <- expect_warning(
    out <- httr2::with_mocked_responses(mock, list_it()),
    class = "cvmdata_warn_sidecar_unread"
  )
  msg <- conditionMessage(w)
  expect_match(msg, "HTTP 504", fixed = TRUE)
  expect_match(msg, "each of 4 attempts", fixed = TRUE)
  expect_match(msg, "not verified", fixed = TRUE)
  # the inventory still comes, without the digests
  expect_identical(nrow(out), 2L)
  expect_true(is.na(attr(out, "source_hash")))
  expect_identical(attr(out, "sidecar_unread"), "HTTP 504")

  # cached meanwhile: no request, no second warning
  expect_no_warning(httr2::with_mocked_responses(mock, list_it()))
  expect_identical(n_calls, 2L)

  # once the wait is over the next call asks again, and a sidecar that
  # now answers is read without a word
  key <- cvmdata:::.mirror_cache_key("companhias", "unread_504")
  cache <- cvmdata:::.mirror_assets_cache
  stale <- cache[[key]]
  attr(stale, "sidecar_tried_at") <- Sys.time() - 3600
  assign(key, stale, envir = cache)
  healed <- unread_mock(function(req) {
    httr2::response_json(body = list(hash = "abc123"))
  })
  expect_no_warning(
    out <- httr2::with_mocked_responses(healed, list_it())
  )
  expect_identical(attr(out, "source_hash"), "abc123")
  expect_null(attr(out, "sidecar_unread"))
})

test_that("a sidecar that is not there does not blame the server", {
  cvmdata:::mirror_assets_cache_clear()
  w <- expect_warning(
    httr2::with_mocked_responses(
      unread_mock(function(req) httr2::response(404L)),
      cvmdata:::mirror_list_assets("companhias", "unread_404")
    ),
    class = "cvmdata_warn_sidecar_unread"
  )
  expect_match(conditionMessage(w), "HTTP 404", fixed = TRUE)
  expect_no_match(conditionMessage(w), "attempts")

  # a release that publishes no sidecar at all is not a failure
  cvmdata:::mirror_assets_cache_clear()
  body <- fake_github_release("companhias__part-0.parquet")
  expect_no_warning(httr2::with_mocked_responses(
    function(req) httr2::response_json(status_code = 200L, body = body),
    cvmdata:::mirror_list_assets("companhias", "no_sidecar")
  ))
})

test_that("a pinned date with an unread sidecar names the real cause", {
  cvmdata:::mirror_assets_cache_clear()
  err <- expect_error(
    httr2::with_mocked_responses(
      unread_mock(function(req) httr2::response(503L)),
      cvmdata:::mirror_list_assets(
        "companhias",
        "unread_pinned",
        release = "2026-10-27"
      )
    ),
    class = "cvmdata_error_http"
  )
  # until 2026-11-05 this read "has no dated snapshots yet"
  expect_no_match(conditionMessage(err), "no dated snapshots")
  expect_match(conditionMessage(err), "lists the dated", fixed = TRUE)
  expect_match(conditionMessage(err), "HTTP 503", fixed = TRUE)
  expect_match(conditionMessage(err), "each of 4 attempts", fixed = TRUE)
})

test_that("the API listing blames the tag only when the tag is the suspect", {
  cvmdata:::mirror_assets_cache_clear()
  listing <- function(status, dataset) {
    expect_error(
      httr2::with_mocked_responses(
        function(req) httr2::response(status),
        cvmdata:::mirror_list_assets("companhias", dataset, refresh = TRUE)
      ),
      class = "cvmdata_error_http"
    )
  }
  down <- conditionMessage(listing(503L, "api_503"))
  expect_match(down, "each of 4 attempts", fixed = TRUE)
  expect_no_match(down, "may not exist")
  missing <- conditionMessage(listing(404L, "api_404"))
  expect_match(missing, "may not exist", fixed = TRUE)
  expect_no_match(missing, "attempts")
})

test_that("mirror_release_tag returns the canonical tag", {
  expect_identical(
    cvmdata:::mirror_release_tag("companhias", "dfp"),
    "mirror-companhias-dfp-latest"
  )
})
