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

test_that("issuer_fetch CAD returns a cvm_tbl via mirror", {
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)

  entries <- list(
    list(name = "companhias__part-0.parquet", parquet = cad_fx())
  )
  mock <- build_mock(entries)

  result <- httr2::with_mocked_responses(
    mock,
    issuer_fetch("cad", "companhias", source = "mirror")
  )
  expect_s3_class(result, "cvm_tbl")
  expect_true(nrow(result) > 0L)
  expect_identical(attr(result, "source"), "mirror")
  expect_identical(attr(result, "dataset"), "cad")
  expect_identical(attr(result, "table"), "companhias")
})

# DFP BPA ind 2024 (yearly + variant) -------------------------------------

test_that("issuer_fetch DFP BPA ind 2024 returns rows via mirror", {
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
    issuer_fetch("dfp", "bpa", report_type = "ind",
              year = 2024L, source = "mirror")
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

test_that("issuer_fetch DFP BPA mirror honours companies filter (CD_CVM)", {
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
    issuer_fetch("dfp", "bpa", report_type = "ind",
              year = 2024L, issuer = "1023",  # BCO BRASIL
              source = "mirror")
  )
  expect_s3_class(result, "cvm_tbl")
  expect_true(nrow(result) > 0L)
  cd <- unique(as.integer(result$cd_cvm))
  expect_identical(cd, 1023L)
})

# Latest year resolution --------------------------------------------------

test_that("issuer_fetch concatenates multiple years from mirror", {
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
    issuer_fetch("dfp", "bpa", report_type = "ind",
              year = c(2023L, 2024L), source = "mirror")
  )
  expect_true(nrow(result) > 0L)
  expect_setequal(unique(result$year), c(2023L, 2024L))
})

test_that("issuer_fetch aborts when no asset matches with year =NULL", {
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  # Inventory has bpa but caller asks for bpp; default years path
  # walks resolve_mirror_years() into its zero-rows abort.
  entries <- list(list(
    name = "bpa__report_type.ind__year.2024__part-0.parquet",
    parquet = dfp_fx()
  ))
  mock <- build_mock(entries)
  expect_error(
    httr2::with_mocked_responses(
      mock,
      issuer_fetch("dfp", "bpp", report_type = "ind", source = "mirror")
    ),
    class = "cvmdata_error_input"
  )
})

test_that("mirror aborts cleanly on HTTP 500 for an asset GET", {
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  entries <- list(list(
    name = "bpa__report_type.ind__year.2024__part-0.parquet",
    parquet = dfp_fx()
  ))
  mock <- function(req) {
    if (grepl("api.github.com", req$url, fixed = TRUE)) {
      return(httr2::response_json(
        status_code = 200L, body = fake_release(entries)
      ))
    }
    httr2::response(status_code = 500L, body = "Server Error")
  }
  expect_error(
    httr2::with_mocked_responses(
      mock,
      issuer_fetch("dfp", "bpa", report_type = "ind",
                year = 2024L, source = "mirror")
    ),
    class = "cvmdata_error_http"
  )
})

test_that("mirror short-circuits when hash matches sidecar", {
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  entries <- list(
    list(
      name = "bpa__report_type.ind__year.2024__part-0.parquet",
      parquet = dfp_fx()
    ),
    list(name = "__source_hash.json", parquet = NULL)
  )
  hash <- list(value = "stable-hash")
  asset_calls <- 0L
  mock <- function(req) {
    if (grepl("api.github.com", req$url, fixed = TRUE)) {
      return(httr2::response_json(
        status_code = 200L, body = fake_release(entries)
      ))
    }
    if (grepl("__source_hash.json", req$url)) {
      return(httr2::response_json(
        status_code = 200L,
        body = list(hash = hash$value, components = list())
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
      issuer_fetch("dfp", "bpa", report_type = "ind", year = 2024L,
                source = "mirror")
      cvmdata:::mirror_assets_cache_clear()
      # Second call: sidecar matches, L3 retained, no asset re-fetch.
      issuer_fetch("dfp", "bpa", report_type = "ind", year = 2024L,
                source = "mirror")
    }
  )
  expect_equal(asset_calls, 1L)
})

test_that("issuer_fetch resolves year =NULL to latest mirror year", {
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
    issuer_fetch("dfp", "bpa", report_type = "ind", source = "mirror")
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
      issuer_fetch("dfp", "bpp", report_type = "ind",
                year = 2024L, source = "mirror")
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
      issuer_fetch("dfp", "bpa", report_type = "ind",
                year = 1990L, source = "mirror")
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
      issuer_fetch("dfp", "bpa", year = 2024L, source = "mirror")
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
      issuer_fetch("cad", "companhias", report_type = "ind",
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
      issuer_fetch("cad", "companhias", year = 2024L, source = "mirror")
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
      issuer_fetch("dfp", "bpa", report_type = "ind",
                year = 2024L, source = "mirror")
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
      issuer_fetch("dfp", "bpa", report_type = "ind", year = 2024L,
                source = "mirror")
      issuer_fetch("dfp", "bpa", report_type = "ind", year = 2024L,
                source = "mirror")
    }
  )
  # The asset is downloaded only once; the second call reads from L3.
  expect_equal(asset_calls, 1L)
})

# L3 hash invalidation ----------------------------------------------------

# Mock that always serves the same parquet body and returns a
# configurable hash from the API.
make_hash_mock <- function(entries, hash_holder) {
  function(req) {
    if (grepl("api.github.com", req$url, fixed = TRUE)) {
      return(httr2::response_json(
        status_code = 200L, body = fake_release(entries)
      ))
    }
    if (grepl("__source_hash.json", req$url)) {
      return(httr2::response_json(
        status_code = 200L,
        body = list(hash = hash_holder$value, components = list())
      ))
    }
    body_raw <- readBin(
      dfp_fx(), what = "raw", n = file.info(dfp_fx())$size
    )
    httr2::response(
      status_code = 200L,
      headers = list("Content-Type" = "application/octet-stream"),
      body = body_raw
    )
  }
}

test_that("L3 sidecar is created on first fetch with a known hash", {
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  entries <- list(
    list(
      name = "bpa__report_type.ind__year.2024__part-0.parquet",
      parquet = dfp_fx()
    ),
    list(name = "__source_hash.json", parquet = NULL)
  )
  hash <- list(value = "abc-first")
  httr2::with_mocked_responses(
    make_hash_mock(entries, hash),
    issuer_fetch("dfp", "bpa", report_type = "ind",
              year = 2024L, source = "mirror")
  )
  sidecar <- file.path(cache_root, "parquet", "companhias", "dfp",
                       "__source_hash.json")
  expect_true(file.exists(sidecar))
  expect_identical(readLines(sidecar), "abc-first")
})

test_that("L3 cache evicts the dataset tree when the hash changes", {
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  entries <- list(
    list(
      name = "bpa__report_type.ind__year.2024__part-0.parquet",
      parquet = dfp_fx()
    ),
    list(name = "__source_hash.json", parquet = NULL)
  )
  hash <- list(value = "v1")
  asset_calls <- 0L
  mock <- function(req) {
    if (grepl("api.github.com", req$url, fixed = TRUE)) {
      return(httr2::response_json(
        status_code = 200L, body = fake_release(entries)
      ))
    }
    if (grepl("__source_hash.json", req$url)) {
      return(httr2::response_json(
        status_code = 200L,
        body = list(hash = hash$value, components = list())
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
    issuer_fetch("dfp", "bpa", report_type = "ind", year = 2024L,
              source = "mirror")
  )
  expect_equal(asset_calls, 1L)

  # Flip the upstream hash and bust the session cache. The next call
  # must evict the L3 tree and redownload.
  hash$value <- "v2"
  cvmdata:::mirror_assets_cache_clear()
  httr2::with_mocked_responses(
    mock,
    issuer_fetch("dfp", "bpa", report_type = "ind", year = 2024L,
              source = "mirror")
  )
  expect_equal(asset_calls, 2L)
  sidecar <- file.path(cache_root, "parquet", "companhias", "dfp",
                       "__source_hash.json")
  expect_identical(readLines(sidecar), "v2")
})

test_that("L3 cache is left alone when current hash is NA", {
  # Pre-populate the L3 with a sidecar carrying some hash. A release
  # that does not publish __source_hash.json (NA on the client side)
  # must not evict.
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  dataset_root <- file.path(
    cache_root, "parquet", "companhias", "dfp"
  )
  dir.create(dataset_root, recursive = TRUE)
  writeLines("legacy-hash", file.path(dataset_root, "__source_hash.json"))

  entries <- list(list(
    name = "bpa__report_type.ind__year.2024__part-0.parquet",
    parquet = dfp_fx()
  ))
  mock <- build_mock(entries)  # no __source_hash.json asset
  httr2::with_mocked_responses(
    mock,
    issuer_fetch("dfp", "bpa", report_type = "ind", year = 2024L,
              source = "mirror")
  )
  expect_identical(
    readLines(file.path(dataset_root, "__source_hash.json")),
    "legacy-hash"
  )
})

# cvm_cache_clear(what = "parquet") --------------------------------------

test_that("cvm_cache_clear what = parquet drops the L3 tree only", {
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  # Seed both layers.
  raw_dir <- file.path(cache_root, "raw", "companhias", "dfp", "2024")
  dir.create(raw_dir, recursive = TRUE)
  writeLines("a", file.path(raw_dir, "marker.txt"))
  parquet_dir <- file.path(
    cache_root, "parquet", "companhias", "dfp", "bpa",
    "report_type=ind", "year=2024"
  )
  dir.create(parquet_dir, recursive = TRUE)
  writeLines("b", file.path(parquet_dir, "part-0.parquet"))

  cvm_cache_clear(what = "parquet", confirm = FALSE)

  expect_false(dir.exists(file.path(cache_root, "parquet")))
  expect_true(file.exists(file.path(raw_dir, "marker.txt")))
})

test_that("cvm_cache_clear what = parquet scoped by dataset", {
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  for (ds in c("dfp", "itr")) {
    dir.create(
      file.path(cache_root, "parquet", "companhias", ds),
      recursive = TRUE
    )
    writeLines(
      ds,
      file.path(cache_root, "parquet", "companhias", ds, "x.txt")
    )
  }
  cvm_cache_clear(what = "parquet", dataset = "dfp", confirm = FALSE)
  expect_false(dir.exists(
    file.path(cache_root, "parquet", "companhias", "dfp")
  ))
  expect_true(dir.exists(
    file.path(cache_root, "parquet", "companhias", "itr")
  ))
})

test_that("cvm_cache_clear rejects year with what = parquet", {
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  expect_error(
    cvm_cache_clear(what = "parquet", dataset = "dfp", year = 2024L,
                    confirm = FALSE),
    class = "cvmdata_error_input"
  )
})
