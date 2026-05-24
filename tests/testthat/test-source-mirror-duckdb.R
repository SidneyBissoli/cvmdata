# Tests for R/source-mirror-duckdb.R. The GitHub API is mocked via
# httr2::with_mocked_responses(); parquet I/O happens against local
# fixtures under tests/testthat/fixtures/mirror-*.parquet.
#
# The download path also goes through httr2 (the `browser_download_url`
# of an asset), so a single mock covers both the API listing and the
# binary fetch.

# Helpers -----------------------------------------------------------------

# Fake release body for the GitHub API. Each entry describes one asset:
#   name      : asset filename as it would appear on the release
#   parquet   : optional local path to a parquet fixture; when provided,
#               a GET to the asset's browser_download_url returns its
#               raw bytes. When NULL, the GET 404s.
fake_release <- function(entries, base = "https://example.test") {
  list(
    tag_name = "mirror-test-latest",
    assets = lapply(entries, function(e) {
      list(
        name = e$name,
        browser_download_url = sprintf("%s/%s", base, e$name),
        size = if (!is.null(e$parquet)) file.info(e$parquet)$size else 0L
      )
    })
  )
}

# Build a mock that:
#   - Returns the fake release JSON for the API URL.
#   - Returns parquet bytes (or 404) for asset GETs.
#   - Returns a fake __source_hash.json body when one is requested.
build_mock <- function(entries, hash = NA_character_,
                       base = "https://example.test") {
  body <- fake_release(entries, base = base)
  function(req) {
    if (grepl("api.github.com", req$url, fixed = TRUE)) {
      return(httr2::response_json(status_code = 200L, body = body))
    }
    name <- basename(req$url)
    if (identical(name, "__source_hash.json")) {
      if (is.na(hash)) {
        return(httr2::response(404L))
      }
      return(httr2::response_json(
        status_code = 200L,
        body = list(hash = hash, components = list())
      ))
    }
    hit <- NULL
    for (e in entries) {
      if (identical(e$name, name)) {
        hit <- e
        break
      }
    }
    if (is.null(hit) || is.null(hit$parquet)) {
      return(httr2::response(404L))
    }
    body_raw <- readBin(
      hit$parquet, what = "raw", n = file.info(hit$parquet)$size
    )
    httr2::response(
      status_code = 200L,
      headers = list("Content-Type" = "application/octet-stream"),
      body = body_raw
    )
  }
}

# Path helpers — keep the test names short.
cad_fx <- function() test_path("fixtures", "mirror-cad-companhias.parquet")
dfp_fx <- function() test_path("fixtures", "mirror-dfp-bpa-ind-2024.parquet")

# CAD (no partition) ------------------------------------------------------

test_that("cvm_fetch CAD returns a cvm_tbl via mirror", {
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)

  entries <- list(
    list(name = "companhias__part-0.parquet", parquet = cad_fx())
  )
  mock <- build_mock(entries)

  result <- httr2::with_mocked_responses(
    mock,
    cvm_fetch("cad", "companhias", source = "mirror")
  )
  expect_s3_class(result, "cvm_tbl")
  expect_true(nrow(result) > 0L)
  expect_identical(attr(result, "source"), "mirror")
  expect_identical(attr(result, "dataset"), "cad")
  expect_identical(attr(result, "table"), "companhias")
})

# DFP BPA ind 2024 (yearly + variant) -------------------------------------

test_that("cvm_fetch DFP BPA ind 2024 returns rows via mirror", {
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)

  entries <- list(
    list(
      name = "bpa__report_type.ind__year.2024__part-0.parquet",
      parquet = dfp_fx()
    ),
    list(
      name = "bpa__report_type.con__year.2024__part-0.parquet",
      parquet = NULL  # exists in inventory but not under test
    )
  )
  mock <- build_mock(entries)

  result <- httr2::with_mocked_responses(
    mock,
    cvm_fetch("dfp", "bpa", report_type = "ind",
              years = 2024L, source = "mirror")
  )
  expect_s3_class(result, "cvm_tbl")
  expect_true(nrow(result) > 0L)
  expect_true("year" %in% names(result))
  expect_true("report_type" %in% names(result))
  expect_true(all(result$year == 2024L))
  expect_true(all(result$report_type == "ind"))
  expect_identical(attr(result, "source"), "mirror")
})

# Filter by company (CD_CVM) ----------------------------------------------

test_that("cvm_fetch DFP BPA mirror honours companies filter (CD_CVM)", {
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)

  entries <- list(list(
    name = "bpa__report_type.ind__year.2024__part-0.parquet",
    parquet = dfp_fx()
  ))
  mock <- build_mock(entries)

  result <- httr2::with_mocked_responses(
    mock,
    cvm_fetch("dfp", "bpa", report_type = "ind",
              years = 2024L, companies = "1023",  # BCO BRASIL
              source = "mirror")
  )
  expect_s3_class(result, "cvm_tbl")
  expect_true(nrow(result) > 0L)
  cd <- unique(as.integer(result$cd_cvm))
  expect_identical(cd, 1023L)
})

# Latest year resolution --------------------------------------------------

test_that("cvm_fetch resolves years=NULL to latest mirror year", {
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)

  entries <- list(
    list(
      name = "bpa__report_type.ind__year.2023__part-0.parquet",
      parquet = dfp_fx()
    ),
    list(
      name = "bpa__report_type.ind__year.2024__part-0.parquet",
      parquet = dfp_fx()
    )
  )
  mock <- build_mock(entries)

  result <- httr2::with_mocked_responses(
    mock,
    cvm_fetch("dfp", "bpa", report_type = "ind", source = "mirror")
  )
  expect_true(all(result$year == 2024L))
})

# Errors ------------------------------------------------------------------

test_that("mirror aborts when no asset matches (table absent)", {
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)

  entries <- list(list(
    name = "bpa__report_type.ind__year.2024__part-0.parquet",
    parquet = dfp_fx()
  ))
  mock <- build_mock(entries)

  expect_error(
    httr2::with_mocked_responses(
      mock,
      cvm_fetch("dfp", "bpp", report_type = "ind",
                years = 2024L, source = "mirror")
    ),
    class = "cvmdata_error_input"
  )
})

test_that("mirror aborts when no asset matches (year absent)", {
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)

  entries <- list(list(
    name = "bpa__report_type.ind__year.2024__part-0.parquet",
    parquet = dfp_fx()
  ))
  mock <- build_mock(entries)

  expect_error(
    httr2::with_mocked_responses(
      mock,
      cvm_fetch("dfp", "bpa", report_type = "ind",
                years = 1990L, source = "mirror")
    ),
    class = "cvmdata_error_input"
  )
})

test_that("mirror aborts when report_type missing for variant table", {
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  entries <- list(list(
    name = "bpa__report_type.ind__year.2024__part-0.parquet",
    parquet = dfp_fx()
  ))
  mock <- build_mock(entries)
  expect_error(
    httr2::with_mocked_responses(
      mock,
      cvm_fetch("dfp", "bpa", years = 2024L, source = "mirror")
    ),
    class = "cvmdata_error_input"
  )
})

test_that("mirror aborts when report_type passed to non-variant table", {
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  entries <- list(list(
    name = "companhias__part-0.parquet",
    parquet = cad_fx()
  ))
  mock <- build_mock(entries)
  expect_error(
    httr2::with_mocked_responses(
      mock,
      cvm_fetch("cad", "companhias", report_type = "ind",
                source = "mirror")
    ),
    class = "cvmdata_error_input"
  )
})

test_that("mirror aborts when years passed to non-yearly table", {
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  entries <- list(list(
    name = "companhias__part-0.parquet",
    parquet = cad_fx()
  ))
  mock <- build_mock(entries)
  expect_error(
    httr2::with_mocked_responses(
      mock,
      cvm_fetch("cad", "companhias", years = 2024L, source = "mirror")
    ),
    class = "cvmdata_error_input"
  )
})

test_that("mirror aborts cleanly on HTTP 404 for an asset GET", {
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)

  # Listed in the inventory but the GET 404s.
  entries <- list(list(
    name = "bpa__report_type.ind__year.2024__part-0.parquet",
    parquet = NULL
  ))
  mock <- build_mock(entries)
  expect_error(
    httr2::with_mocked_responses(
      mock,
      cvm_fetch("dfp", "bpa", report_type = "ind",
                years = 2024L, source = "mirror")
    ),
    class = "cvmdata_error_http"
  )
})

# L3 cache reuse ----------------------------------------------------------

test_that("mirror reuses the L3 cache on a second call", {
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)

  entries <- list(list(
    name = "bpa__report_type.ind__year.2024__part-0.parquet",
    parquet = dfp_fx()
  ))

  asset_calls <- 0L
  mock <- function(req) {
    if (grepl("api.github.com", req$url, fixed = TRUE)) {
      return(httr2::response_json(
        status_code = 200L, body = fake_release(entries)
      ))
    }
    asset_calls <<- asset_calls + 1L
    body_raw <- readBin(
      dfp_fx(), what = "raw", n = file.info(dfp_fx())$size
    )
    httr2::response(
      status_code = 200L,
      headers = list("Content-Type" = "application/octet-stream"),
      body = body_raw
    )
  }
  httr2::with_mocked_responses(
    mock,
    {
      cvm_fetch("dfp", "bpa", report_type = "ind", years = 2024L,
                source = "mirror")
      cvm_fetch("dfp", "bpa", report_type = "ind", years = 2024L,
                source = "mirror")
    }
  )
  # The asset is downloaded only once; the second call reads from L3.
  expect_equal(asset_calls, 1L)
})
