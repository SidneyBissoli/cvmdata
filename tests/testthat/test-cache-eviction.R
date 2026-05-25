# Tests for the LRU eviction engine in R/cache.R. These are pure
# filesystem tests that build synthetic cache layouts under tempdir()
# and exercise `cache_enforce_limit()` directly; no HTTP is touched.
# The integration with `download_with_etag()` is exercised by
# test-cache-eviction-integration.R further below in the same file.

# Helpers ------------------------------------------------------------------

# Build a fresh cache root under tempdir() and route the package to it
# via `options(cvmdata.cache_dir)`. Returns the absolute path.
local_cache_dir <- function(envir = parent.frame()) {
  cache <- withr::local_tempdir(.local_envir = envir)
  withr::local_options(
    cvmdata.cache_dir = cache,
    .local_envir = envir
  )
  cache
}

# Materialise a yearly unit (ZIP + sidecar). The ZIP holds `size_bytes`
# raw bytes; mtime of both ZIP and sidecar is set to `mtime`. Returns
# the absolute path of the ZIP.
write_unit_yearly <- function(cache, dataset, year, size_bytes,
                              mtime = Sys.time()) {
  d <- file.path(
    cache, "raw", "companhias", dataset, as.character(year)
  )
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  zip <- file.path(d, sprintf("%s_cia_aberta_%d.zip", dataset, year))
  writeBin(raw(size_bytes), zip)
  saveRDS(
    list(
      etag = "\"synthetic\"",
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = format(mtime, "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
    ),
    paste0(zip, ".etag.rds")
  )
  Sys.setFileTime(zip, mtime)
  Sys.setFileTime(paste0(zip, ".etag.rds"), mtime)
  zip
}

# Materialise a non-partitioned unit (single CSV + sidecar) directly
# under <cache>/raw/<dataset>/.
write_unit_none <- function(cache, dataset, name, size_bytes,
                            mtime = Sys.time()) {
  d <- file.path(cache, "raw", "companhias", dataset)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  artifact <- file.path(d, name)
  writeBin(raw(size_bytes), artifact)
  saveRDS(
    list(
      etag = "\"synthetic\"",
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = format(mtime, "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
    ),
    paste0(artifact, ".etag.rds")
  )
  Sys.setFileTime(artifact, mtime)
  Sys.setFileTime(paste0(artifact, ".etag.rds"), mtime)
  artifact
}

# Below-90% guard ---------------------------------------------------------

test_that("cache below 90% of limit triggers no eviction", {
  cache <- local_cache_dir()
  withr::local_options(cvmdata.cache_max_size_mb = 1L)  # 1 MiB
  write_unit_yearly(cache, "dfp", 2023, 500L * 1024L)   # 500 KiB
  expect_equal(cache_enforce_limit(), 0L)
  expect_true(dir.exists(file.path(cache, "raw", "companhias", "dfp", "2023")))
})

# Above-90% triggers eviction down to <=80% ------------------------------

test_that("cache above 90% evicts oldest units until <=80% of limit", {
  cache <- local_cache_dir()
  withr::local_options(cvmdata.cache_max_size_mb = 1L)  # 1 MiB
  now <- Sys.time()
  # Four 300 KiB units = 1200 KiB total = 117% of 1 MiB.
  write_unit_yearly(cache, "dfp", 2020, 300L * 1024L, now - 4000)
  write_unit_yearly(cache, "dfp", 2021, 300L * 1024L, now - 3000)
  write_unit_yearly(cache, "dfp", 2022, 300L * 1024L, now - 2000)
  write_unit_yearly(cache, "dfp", 2023, 300L * 1024L, now - 1000)
  removed <- cache_enforce_limit()
  expect_gt(removed, 0L)
  expect_lte(cache_current_size_bytes(), 0.8 * 1024 * 1024)
  # Oldest gone, newest preserved.
  expect_false(dir.exists(file.path(cache, "raw", "companhias", "dfp", "2020")))
  expect_true(dir.exists(file.path(cache, "raw", "companhias", "dfp", "2023")))
})

# Atomic unit: ZIP + sidecar + extracted CSV(s) removed together ----------

test_that("yearly eviction removes ZIP + sidecar + extracted CSV together", {
  cache <- local_cache_dir()
  withr::local_options(cvmdata.cache_max_size_mb = 1L)
  now <- Sys.time()
  zip_old <- write_unit_yearly(
    cache, "dfp", 2020, 600L * 1024L, now - 3000
  )
  # Simulate a CSV extracted from the old ZIP. Same yearly dir, same
  # unit — must vanish together with the ZIP.
  csv_old <- file.path(dirname(zip_old), "bpa_ind_2020.csv")
  writeBin(raw(100L * 1024L), csv_old)
  Sys.setFileTime(csv_old, now - 2500)
  zip_new <- write_unit_yearly(
    cache, "dfp", 2024, 600L * 1024L, now - 1000
  )

  cache_enforce_limit()

  expect_false(file.exists(zip_old))
  expect_false(file.exists(paste0(zip_old, ".etag.rds")))
  expect_false(file.exists(csv_old))
  expect_false(dir.exists(file.path(cache, "raw", "companhias", "dfp", "2020")))
  expect_true(file.exists(zip_new))
})

test_that("non-partitioned eviction removes artifact + sidecar together", {
  cache <- local_cache_dir()
  withr::local_options(cvmdata.cache_max_size_mb = 1L)
  now <- Sys.time()
  old_csv <- write_unit_none(
    cache, "cad", "cad_old.csv", 600L * 1024L, now - 3000
  )
  new_csv <- write_unit_none(
    cache, "cad", "cad_new.csv", 600L * 1024L, now - 1000
  )

  cache_enforce_limit()

  expect_false(file.exists(old_csv))
  expect_false(file.exists(paste0(old_csv, ".etag.rds")))
  expect_true(file.exists(new_csv))
  # Parent directory survives because the newer unit still lives there.
  expect_true(dir.exists(file.path(cache, "raw", "companhias", "cad")))
})

# Limit sentinels: 0 / negative / Inf disable eviction --------------------

test_that("limit = 0, negative, or Inf disables eviction", {
  cache <- local_cache_dir()
  now <- Sys.time()
  write_unit_yearly(cache, "dfp", 2020, 600L * 1024L, now - 3000)
  write_unit_yearly(cache, "dfp", 2024, 600L * 1024L, now - 1000)
  for (val in list(0L, -1L, Inf)) {
    withr::local_options(cvmdata.cache_max_size_mb = val)
    expect_equal(cache_enforce_limit(), 0L)
    expect_true(dir.exists(file.path(
      cache, "raw", "companhias", "dfp", "2020"
    )))
    expect_true(dir.exists(file.path(
      cache, "raw", "companhias", "dfp", "2024"
    )))
  }
})

# Malformed limit falls back to default 100 MB ----------------------------

test_that("malformed cvmdata.cache_max_size_mb falls back to 100 MB default", {
  cache <- local_cache_dir()
  write_unit_yearly(cache, "dfp", 2024, 1024L)  # 1 KiB
  for (val in list("100", NA_real_, c(1L, 2L), NA, NA_integer_)) {
    withr::local_options(cvmdata.cache_max_size_mb = val)
    # Default = 100 MiB; 1 KiB is well below 90% → no eviction.
    expect_equal(cache_enforce_limit(), 0L)
    expect_true(file.exists(
      file.path(cache, "raw", "companhias", "dfp", "2024",
                "dfp_cia_aberta_2024.zip")
    ))
  }
})

# Orphan sidecar: ignored in accounting, not removed by eviction ----------

test_that("orphan sidecar is ignored in size accounting and not removed", {
  cache <- local_cache_dir()
  withr::local_options(cvmdata.cache_max_size_mb = 1L)
  d <- file.path(cache, "raw", "companhias", "dfp", "2020")
  dir.create(d, recursive = TRUE)
  orphan <- file.path(d, "missing.zip.etag.rds")
  saveRDS(
    list(
      etag = "\"x\"",
      last_modified = NULL,
      fetched_at = "2024-01-01T00:00:00.000Z"
    ),
    orphan
  )

  expect_equal(cache_current_size_bytes(), 0)
  expect_equal(cache_enforce_limit(), 0L)
  expect_true(file.exists(orphan))
})

# Self-protection: the just-written file is never evicted -----------------

test_that("cache_enforce_limit protects the just-written dest_path", {
  cache <- local_cache_dir()
  # Tight limit so a single ZIP exceeds it on its own.
  withr::local_options(cvmdata.cache_max_size_mb = 0.01)  # ~10 KiB
  now <- Sys.time()
  write_unit_yearly(cache, "dfp", 2020, 5L * 1024L, now - 2000)
  new_zip <- write_unit_yearly(cache, "dfp", 2024, 50L * 1024L, now)

  cache_enforce_limit(protect = new_zip)

  expect_true(file.exists(new_zip))
  expect_false(file.exists(
    file.path(cache, "raw", "companhias", "dfp", "2020",
              "dfp_cia_aberta_2020.zip")
  ))
})

# Empty / missing cache: no-op --------------------------------------------

test_that("cache_enforce_limit is a no-op on empty cache", {
  cache <- local_cache_dir()
  withr::local_options(cvmdata.cache_max_size_mb = 1L)
  expect_equal(cache_enforce_limit(), 0L)
  expect_equal(cache_current_size_bytes(), 0)
})

test_that("cache_enforce_limit is a no-op when cache dir is missing", {
  withr::local_options(
    cvmdata.cache_dir = file.path(tempdir(), "nonexistent-cvmdata-cache")
  )
  withr::local_options(cvmdata.cache_max_size_mb = 1L)
  expect_equal(cache_enforce_limit(), 0L)
  expect_equal(cache_current_size_bytes(), 0)
})

# cvmdata_warn_eviction surfaces removal counts when opted in ------------

test_that("cache_enforce_limit emits cvmdata_warn_eviction when opted in", {
  cache <- local_cache_dir()
  withr::local_options(
    cvmdata.cache_max_size_mb = 1L,
    cvmdata.cache_warn_evictions = TRUE
  )
  now <- Sys.time()
  write_unit_yearly(cache, "dfp", 2020, 600L * 1024L, now - 4000)
  write_unit_yearly(cache, "dfp", 2024, 600L * 1024L, now - 1000)
  expect_warning(
    cache_enforce_limit(),
    class = "cvmdata_warn_eviction"
  )
})

test_that("cache_enforce_limit stays silent when warn opt-out is FALSE", {
  cache <- local_cache_dir()
  withr::local_options(
    cvmdata.cache_max_size_mb = 1L,
    cvmdata.cache_warn_evictions = FALSE
  )
  now <- Sys.time()
  write_unit_yearly(cache, "dfp", 2020, 600L * 1024L, now - 4000)
  write_unit_yearly(cache, "dfp", 2024, 600L * 1024L, now - 1000)
  expect_silent(cache_enforce_limit())
})

test_that("cache_enforce_limit default is silent under non-interactive tests", {
  # testthat sessions are non-interactive; the default
  # (`interactive()`) evaluates to FALSE, so no warning.
  cache <- local_cache_dir()
  withr::local_options(cvmdata.cache_max_size_mb = 1L)
  now <- Sys.time()
  write_unit_yearly(cache, "dfp", 2020, 600L * 1024L, now - 4000)
  write_unit_yearly(cache, "dfp", 2024, 600L * 1024L, now - 1000)
  expect_silent(cache_enforce_limit())
})

test_that("invalid cache_warn_evictions option falls back to default", {
  cache <- local_cache_dir()
  withr::local_options(
    cvmdata.cache_max_size_mb = 1L,
    cvmdata.cache_warn_evictions = "yes"
  )
  now <- Sys.time()
  write_unit_yearly(cache, "dfp", 2020, 600L * 1024L, now - 4000)
  write_unit_yearly(cache, "dfp", 2024, 600L * 1024L, now - 1000)
  # Test session is non-interactive → default FALSE → silent.
  expect_silent(cache_enforce_limit())
})

# total_size_bytes attribute on cvm_cache_info() --------------------------

test_that("cvm_cache_info() carries total_size_bytes attribute", {
  cache <- local_cache_dir()
  # Empty cache: attribute is 0.
  info_empty <- cvm_cache_info()
  expect_equal(attr(info_empty, "total_size_bytes"), 0)
  expect_equal(nrow(info_empty), 0L)

  # Populated cache: attribute equals cache_current_size_bytes().
  write_unit_yearly(cache, "dfp", 2024, 100L * 1024L)
  info <- cvm_cache_info()
  expect_equal(
    attr(info, "total_size_bytes"),
    cache_current_size_bytes()
  )
  expect_gt(attr(info, "total_size_bytes"), 0)
})

# Integration: trigger fires via download_with_etag() ---------------------

test_that("download_with_etag triggers eviction after a real write", {
  cache <- local_cache_dir()
  now <- Sys.time()
  # Pre-seed an old unit large enough that the 38 KiB fixture pushes
  # the total past the 90% threshold and triggers eviction.
  old_zip <- write_unit_yearly(
    cache, "dfp", 2020, 950L * 1024L, now - 5000
  )

  # Tight limit so the new download forces eviction of the 2020 unit.
  withr::local_options(cvmdata.cache_max_size_mb = 1L)  # 1 MiB

  fixture_path <- test_path("fixtures", "dfp_cia_aberta_2024.zip")
  fixture_body <- readBin(
    fixture_path, what = "raw", n = file.info(fixture_path)$size
  )
  mock <- function(req) {
    httr2::response(
      status_code = 200L,
      headers = list("ETag" = "\"FRESH-FROM-MOCK\""),
      body = fixture_body
    )
  }
  result <- httr2::with_mocked_responses(
    mock,
    cvm_fetch(
      "dfp", "bpa",
      report_type = "ind", years = 2024, source = "cvm"
    )
  )
  expect_s3_class(result, "cvm_tbl")
  # The 2020 unit should be gone (oldest, evicted to make room).
  expect_false(file.exists(old_zip))
  expect_false(dir.exists(file.path(cache, "raw", "companhias", "dfp", "2020")))
  # The just-downloaded 2024 ZIP must survive.
  expect_true(file.exists(
    file.path(cache, "raw", "companhias", "dfp", "2024",
                "dfp_cia_aberta_2024.zip")
  ))
})
