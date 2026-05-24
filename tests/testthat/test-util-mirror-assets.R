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
    url = sprintf("https://example.test/%s", c(
      "bpa-ind-2023", "bpa-ind-2024", "bpa-con-2024",
      "bpp-ind-2024", "sub-2024", "hash"
    )),
    size_bytes = c(1000L, 1100L, 1200L, 900L, 800L, 200L)
  )
}

test_that("filter_mirror_assets returns single (table, year, variant)", {
  inv <- sample_inventory()
  out <- cvmdata:::filter_mirror_assets(
    inv, table = "bpa", years = 2024L, report_type = "ind"
  )
  expect_equal(nrow(out), 1L)
  expect_identical(out$year, 2024L)
  expect_identical(out$report_type, "ind")
  expect_identical(out$table, "bpa")
})

test_that("filter_mirror_assets keeps multiple years", {
  inv <- sample_inventory()
  out <- cvmdata:::filter_mirror_assets(
    inv, table = "bpa", years = c(2023L, 2024L), report_type = "ind"
  )
  expect_equal(nrow(out), 2L)
  expect_setequal(out$year, c(2023L, 2024L))
})

test_that("filter_mirror_assets honours years = NULL", {
  inv <- sample_inventory()
  out <- cvmdata:::filter_mirror_assets(
    inv, table = "bpa", years = NULL, report_type = "ind"
  )
  expect_equal(nrow(out), 2L)
})

test_that("filter_mirror_assets honours report_type = NULL", {
  inv <- sample_inventory()
  out <- cvmdata:::filter_mirror_assets(
    inv, table = "bpa", years = 2024L, report_type = NULL
  )
  # ind + con for 2024
  expect_equal(nrow(out), 2L)
  expect_setequal(out$report_type, c("ind", "con"))
})

test_that("filter_mirror_assets excludes hash sidecar implicitly", {
  inv <- sample_inventory()
  out <- cvmdata:::filter_mirror_assets(
    inv, table = "submissao", years = 2024L, report_type = NULL
  )
  expect_equal(nrow(out), 1L)
  expect_identical(out$table, "submissao")
})

test_that("filter_mirror_assets returns 0 rows when no match", {
  inv <- sample_inventory()
  out <- cvmdata:::filter_mirror_assets(
    inv, table = "bpa", years = 1999L, report_type = "ind"
  )
  expect_equal(nrow(out), 0L)
})

test_that("filter_mirror_assets handles empty inventory", {
  inv <- tibble::tibble(
    name = character(0L), url = character(0L), size_bytes = integer(0L)
  )
  out <- cvmdata:::filter_mirror_assets(
    inv, table = "bpa", years = 2024L, report_type = "ind"
  )
  expect_equal(nrow(out), 0L)
  expect_true(all(c("table", "year", "report_type") %in% names(out)))
})

# mirror_list_assets ------------------------------------------------------

# Build a fake GitHub API response with the given asset names. Sizes
# and URLs are synthetic.
fake_github_release <- function(asset_names,
                                base = "https://example.test") {
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
    cvmdata:::mirror_list_assets("dfp_test1", refresh = TRUE)
  )
  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 3L)
  expect_identical(attr(out, "release_tag"), "mirror-dfp_test1-latest")
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
      cvmdata:::mirror_list_assets("dfp_test2", refresh = TRUE)
      cvmdata:::mirror_list_assets("dfp_test2")
      cvmdata:::mirror_list_assets("dfp_test2")
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
      cvmdata:::mirror_list_assets("nope_dataset", refresh = TRUE)
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
      cvmdata:::mirror_list_assets("net_fail_dataset", refresh = TRUE)
    ),
    class = "cvmdata_error_http"
  )
})

test_that("mirror_list_assets attaches source_hash attribute", {
  cvmdata:::mirror_assets_cache_clear()
  body <- fake_github_release(c(
    "companhias__part-0.parquet", "__source_hash.json"
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
    cvmdata:::mirror_list_assets("dfp_test_hash", refresh = TRUE)
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
    cvmdata:::mirror_list_assets("dfp_test_no_hash", refresh = TRUE)
  )
  expect_true(is.na(attr(out, "source_hash")))
})

test_that("mirror_release_tag returns the canonical tag", {
  expect_identical(cvmdata:::mirror_release_tag("dfp"),
                   "mirror-dfp-latest")
})
