# Tests for R/util-mirror-assets.R. Parser + filter logic are pure
# (no I/O). The GitHub API inventory is exercised with httr2 mocked
# responses; tests never touch the network.

# parse_mirror_asset_name -------------------------------------------------

test_that("parse_mirror_asset_name decodes CAD (no partition)", {
  out <- parse_mirror_asset_name("companhias__part-0.parquet")
  expect_identical(out$table, "companhias")
  expect_true(is.na(out$report_type))
  expect_true(is.na(out$year))
})

test_that("parse_mirror_asset_name decodes yearly-only (sanitised)", {
  out <- parse_mirror_asset_name(
    "submissao__year.2024__part-0.parquet"
  )
  expect_identical(out$table, "submissao")
  expect_identical(out$year, 2024L)
  expect_true(is.na(out$report_type))
})

test_that("parse_mirror_asset_name decodes yearly-only (raw =)", {
  out <- parse_mirror_asset_name(
    "submissao__year=2024__part-0.parquet"
  )
  expect_identical(out$year, 2024L)
})

test_that("parse_mirror_asset_name decodes variant + yearly (sanitised)", {
  out <- parse_mirror_asset_name(
    "bpa__report_type.ind__year.2024__part-0.parquet"
  )
  expect_identical(out$table, "bpa")
  expect_identical(out$report_type, "ind")
  expect_identical(out$year, 2024L)
})

test_that("parse_mirror_asset_name decodes variant + yearly (raw =)", {
  out <- parse_mirror_asset_name(
    "bpa__report_type=ind__year=2024__part-0.parquet"
  )
  expect_identical(out$report_type, "ind")
  expect_identical(out$year, 2024L)
})

test_that("parse_mirror_asset_name returns NULL for hash sidecar", {
  expect_null(parse_mirror_asset_name("__source_hash.json"))
})

test_that("parse_mirror_asset_name aborts on non-parquet name", {
  expect_error(
    parse_mirror_asset_name("README.md"),
    class = "cvmdata_error_parse"
  )
})

test_that("parse_mirror_asset_name aborts on missing part-N suffix", {
  expect_error(
    parse_mirror_asset_name("bpa__year.2024.parquet"),
    class = "cvmdata_error_parse"
  )
})

test_that("parse_mirror_asset_name tags current and history assets", {
  current <- parse_mirror_asset_name(
    "dre__report_type.con__year.2023__part-0.parquet"
  )
  expect_identical(current$kind, "current")
  history <- parse_mirror_asset_name(
    "dre__report_type.con__year.2023__history.parquet"
  )
  expect_identical(
    history,
    list(table = "dre", report_type = "con", year = 2023L, kind = "history")
  )
  raw <- parse_mirror_asset_name(
    "dre__report_type=con__year=2023__history.parquet"
  )
  expect_identical(raw$kind, "history")
})

test_that("parse_mirror_asset_name aborts on unknown partition key", {
  expect_error(
    parse_mirror_asset_name(
      "bpa__quarter.Q1__part-0.parquet"
    ),
    class = "cvmdata_error_parse"
  )
})

test_that("parse_mirror_asset_name aborts on non-integer year", {
  expect_error(
    parse_mirror_asset_name(
      "bpa__year.abcd__part-0.parquet"
    ),
    class = "cvmdata_error_parse"
  )
})

test_that("parse_mirror_asset_name aborts on malformed segment", {
  expect_error(
    parse_mirror_asset_name(
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
  out <- filter_mirror_assets(
    inv,
    table = "bpa",
    year = 2024L,
    report_type = "ind"
  )
  expect_identical(nrow(out), 1L)
  expect_identical(out$year, 2024L)
  expect_identical(out$report_type, "ind")
  expect_identical(out$table, "bpa")
})

test_that("filter_mirror_assets keeps multiple years", {
  inv <- sample_inventory()
  out <- filter_mirror_assets(
    inv,
    table = "bpa",
    year = c(2023L, 2024L),
    report_type = "ind"
  )
  expect_identical(nrow(out), 2L)
  expect_setequal(out$year, c(2023L, 2024L))
})

test_that("filter_mirror_assets honours year = NULL", {
  inv <- sample_inventory()
  out <- filter_mirror_assets(
    inv,
    table = "bpa",
    year = NULL,
    report_type = "ind"
  )
  expect_identical(nrow(out), 2L)
})

test_that("filter_mirror_assets honours report_type = NULL", {
  inv <- sample_inventory()
  out <- filter_mirror_assets(
    inv,
    table = "bpa",
    year = 2024L,
    report_type = NULL
  )
  # ind + con for 2024
  expect_identical(nrow(out), 2L)
  expect_setequal(out$report_type, c("ind", "con"))
})

test_that("filter_mirror_assets excludes hash sidecar implicitly", {
  inv <- sample_inventory()
  out <- filter_mirror_assets(
    inv,
    table = "submissao",
    year = 2024L,
    report_type = NULL
  )
  expect_identical(nrow(out), 1L)
  expect_identical(out$table, "submissao")
})

test_that("filter_mirror_assets returns 0 rows when no match", {
  inv <- sample_inventory()
  out <- filter_mirror_assets(
    inv,
    table = "bpa",
    year = 1999L,
    report_type = "ind"
  )
  expect_identical(nrow(out), 0L)
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
  current <- filter_mirror_assets(
    assets,
    table = "dre",
    year = 2023L,
    report_type = "con"
  )
  expect_identical(current$kind, "current")
  both <- filter_mirror_assets(
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
  current <- mirror_l3_path("dfp", "dre", 2023L, "con")
  history <- mirror_l3_path("dfp", "dre", 2023L, "con", "history")
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
  out <- filter_mirror_assets(
    inv,
    table = "bpa",
    year = 2024L,
    report_type = "ind"
  )
  expect_identical(nrow(out), 0L)
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
  mirror_assets_cache_clear()
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
    mirror_list_assets("companhias", "dfp_test1", refresh = TRUE)
  )
  expect_s3_class(out, "tbl_df")
  expect_identical(nrow(out), 3L)
  expect_identical(
    attr(out, "release_tag"),
    "mirror-companhias-dfp_test1-latest"
  )
})

test_that("mirror_list_assets caches per session", {
  mirror_assets_cache_clear()
  body <- fake_github_release("companhias__part-0.parquet")
  tally <- new.env()
  tally$n_calls <- 0L
  mock <- function(req) {
    tally$n_calls <- tally$n_calls + 1L
    if (grepl("api.github.com", req$url, fixed = TRUE)) {
      return(httr2::response_json(status_code = 200L, body = body))
    }
    httr2::response(404L)
  }
  httr2::with_mocked_responses(
    mock,
    {
      mirror_list_assets("companhias", "dfp_test2", refresh = TRUE)
      mirror_list_assets("companhias", "dfp_test2")
      mirror_list_assets("companhias", "dfp_test2")
    }
  )
  # Only the first call (refresh = TRUE) goes out: the sidecar at the
  # release's download URL (404 here) and then the API listing, which
  # names no __source_hash.json, so no third GET happens.
  expect_identical(tally$n_calls, 2L)
})

test_that("mirror_list_assets aborts on HTTP 404", {
  mirror_assets_cache_clear()
  mock <- function(req) {
    httr2::response(status_code = 404L, body = "Not Found")
  }
  expect_error(
    httr2::with_mocked_responses(
      mock,
      mirror_list_assets("companhias", "nope_dataset", refresh = TRUE)
    ),
    class = "cvmdata_error_http"
  )
})

test_that("mirror_list_assets aborts on network failure", {
  mirror_assets_cache_clear()
  mock <- function(req) stop("simulated DNS error")
  expect_error(
    httr2::with_mocked_responses(
      mock,
      mirror_list_assets(
        "companhias",
        "net_fail_dataset",
        refresh = TRUE
      )
    ),
    class = "cvmdata_error_http"
  )
})

test_that("mirror_list_assets attaches source_hash attribute", {
  mirror_assets_cache_clear()
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
    mirror_list_assets("companhias", "dfp_test_hash", refresh = TRUE)
  )
  expect_identical(attr(out, "source_hash"), "deadbeef")
})

test_that("mirror_list_assets returns NA hash when sidecar absent", {
  mirror_assets_cache_clear()
  body <- fake_github_release("companhias__part-0.parquet")
  mock <- function(req) {
    if (grepl("api.github.com", req$url, fixed = TRUE)) {
      return(httr2::response_json(status_code = 200L, body = body))
    }
    httr2::response(404L)
  }
  out <- httr2::with_mocked_responses(
    mock,
    mirror_list_assets(
      "companhias",
      "dfp_test_no_hash",
      refresh = TRUE
    )
  )
  expect_true(is.na(attr(out, "source_hash")))
})

# A release that publishes a sidecar, with the sidecar answered by
# `sidecar(req)` and every request counted in the caller's `n_calls`.
# With `dataset`, the listing's URLs are the real download URLs of that
# release, as GitHub serves them.
unread_mock <- function(sidecar, count = function() NULL, dataset = NULL) {
  base <- if (is.null(dataset)) {
    "https://example.test"
  } else {
    dirname(mirror_download_url(
      mirror_release_tag("companhias", dataset),
      "x"
    ))
  }
  body <- fake_github_release(
    c("companhias__part-0.parquet", "__source_hash.json"),
    base = base
  )
  function(req) {
    count()
    if (grepl("api.github.com", req$url, fixed = TRUE)) {
      return(httr2::response_json(status_code = 200L, body = body))
    }
    sidecar(req)
  }
}

test_that("a sidecar that cannot be read is a warning, never silence", {
  mirror_assets_cache_clear()
  tally <- new.env()
  tally$n_calls <- 0L
  mock <- unread_mock(
    function(req) httr2::response(504L),
    function() tally$n_calls <- tally$n_calls + 1L,
    dataset = "unread_504"
  )
  list_it <- function() {
    mirror_list_assets("companhias", "unread_504")
  }
  w <- expect_warning(
    {
      out <- httr2::with_mocked_responses(mock, list_it())
    },
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

  # cached meanwhile: no request, no second warning; and the fallback to
  # the API did not ask again for the sidecar it had just failed to read
  # (the sidecar, then the listing: 2)
  expect_no_warning(httr2::with_mocked_responses(mock, list_it()))
  expect_identical(tally$n_calls, 2L)

  # once the wait is over the next call asks again, and a sidecar that
  # now answers is read without a word
  key <- .mirror_cache_key("companhias", "unread_504")
  cache <- .mirror_assets_cache
  stale <- cache[[key]]
  attr(stale, "sidecar_tried_at") <- Sys.time() - 3600
  assign(key, stale, envir = cache)
  healed <- unread_mock(function(req) {
    httr2::response_json(body = list(hash = "abc123"))
  })
  expect_no_warning(
    {
      out <- httr2::with_mocked_responses(healed, list_it())
    }
  )
  expect_identical(attr(out, "source_hash"), "abc123")
  expect_null(attr(out, "sidecar_unread"))
})

test_that("a sidecar that is not there does not blame the server", {
  mirror_assets_cache_clear()
  w <- expect_warning(
    httr2::with_mocked_responses(
      unread_mock(function(req) httr2::response(404L)),
      mirror_list_assets("companhias", "unread_404")
    ),
    class = "cvmdata_warn_sidecar_unread"
  )
  expect_match(conditionMessage(w), "HTTP 404", fixed = TRUE)
  expect_no_match(conditionMessage(w), "attempts")

  # a release that publishes no sidecar at all is not a failure
  mirror_assets_cache_clear()
  body <- fake_github_release("companhias__part-0.parquet")
  expect_no_warning(httr2::with_mocked_responses(
    function(req) httr2::response_json(status_code = 200L, body = body),
    mirror_list_assets("companhias", "no_sidecar")
  ))
})

test_that("a pinned date with an unread sidecar names the real cause", {
  mirror_assets_cache_clear()
  err <- expect_error(
    httr2::with_mocked_responses(
      unread_mock(function(req) httr2::response(503L)),
      mirror_list_assets(
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
  mirror_assets_cache_clear()
  listing <- function(status, dataset) {
    expect_error(
      httr2::with_mocked_responses(
        function(req) httr2::response(status),
        mirror_list_assets("companhias", dataset, refresh = TRUE)
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
    mirror_release_tag("companhias", "dfp"),
    "mirror-companhias-dfp-latest"
  )
})

# The -latest inventory from its sidecar (2026-11-18) --------------------

test_that("a sidecar with `files` lists -latest without the GitHub API", {
  mirror_assets_cache_clear()
  tag <- mirror_release_tag("companhias", "from_sidecar")
  sidecar <- list(
    hash = "abc123",
    snapshot = "2026-11-17",
    snapshots = list("2026-11-10", "2026-11-17"),
    files = list(
      "bpa/report_type=ind/year=2024/part-0.parquet" = list(
        sha256 = "s1",
        size = 10L
      ),
      "submissao/year=2024/part-0.parquet" = list(sha256 = "s2", size = 20L)
    ),
    history = list("bpa/report_type=ind/year=2024/history.parquet" = "h1")
  )
  tally <- new.env()
  tally$urls <- character(0L)
  mock <- function(req) {
    tally$urls <- c(tally$urls, req$url)
    if (identical(req$url, mirror_download_url(tag, "__source_hash.json"))) {
      return(httr2::response_json(body = sidecar))
    }
    httr2::response(500L)
  }
  out <- httr2::with_mocked_responses(
    mock,
    mirror_list_assets("companhias", "from_sidecar", refresh = TRUE)
  )
  expect_identical(tally$urls, mirror_download_url(tag, "__source_hash.json"))
  expect_identical(
    out$name,
    c(
      "bpa__report_type.ind__year.2024__part-0.parquet",
      "submissao__year.2024__part-0.parquet",
      "bpa__report_type.ind__year.2024__history.parquet"
    )
  )
  expect_identical(out$url, mirror_download_url(tag, out$name))
  expect_identical(out$sha256, c("s1", "s2", NA))
  expect_identical(out$size_bytes, c(10L, 20L, NA))
  expect_identical(attr(out, "source_hash"), "abc123")
  expect_identical(
    attr(out, "release_tag"),
    mirror_snapshot_tag("companhias", "from_sidecar", "2026-11-17")
  )
  expect_identical(attr(out, "snapshots"), c("2026-11-10", "2026-11-17"))
  expect_null(attr(out, "sidecar_unread"))
  # the history asset is read by cvm_versions(), never by cvm_fetch()
  current <- filter_mirror_assets(out, "bpa", 2024L, "ind")
  expect_identical(nrow(current), 1L)
  both <- filter_mirror_assets(
    out,
    "bpa",
    2024L,
    "ind",
    c("current", "history")
  )
  expect_identical(nrow(both), 2L)
})

test_that("an exhausted API rate limit says so, not that the tag is missing", {
  mirror_assets_cache_clear()
  withr::local_envvar(GITHUB_TOKEN = NA, GITHUB_PAT = NA)
  mock <- function(req) {
    if (grepl("api.github.com", req$url, fixed = TRUE)) {
      return(httr2::response(
        status_code = 403L,
        headers = list(
          "x-ratelimit-remaining" = "0",
          "x-ratelimit-reset" = "1795000000"
        )
      ))
    }
    httr2::response(404L)
  }
  err <- expect_error(
    httr2::with_mocked_responses(
      mock,
      mirror_list_assets("companhias", "rate_limited", refresh = TRUE)
    ),
    class = "cvmdata_error_http"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "rate limit", fixed = TRUE)
  expect_match(msg, "GITHUB_PAT", fixed = TRUE)
  expect_no_match(msg, "may not exist yet", fixed = TRUE)

  # a 403 with the limit still standing keeps the old hint
  mirror_assets_cache_clear()
  plain <- function(req) {
    httr2::response(if (grepl("api", req$url)) 403L else 404L)
  }
  err <- expect_error(
    httr2::with_mocked_responses(
      plain,
      mirror_list_assets("companhias", "forbidden", refresh = TRUE)
    ),
    class = "cvmdata_error_http"
  )
  expect_match(conditionMessage(err), "may not exist yet", fixed = TRUE)
})
