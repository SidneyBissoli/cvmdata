# Shared helpers for the tests that read the CVM fixture ZIPs through
# the HTTP backend (test-cvm-fetch.R, test-cvm-versions.R): a tempdir
# cache staged with the fixtures and their etag sidecars, a mocked HEAD
# that reports them fresh, and the CNPJs of the two issuers the
# fixtures keep.

# Stage one or more dataset fixture ZIPs (year 2024 by default; the
# DFP also ships a 2025 fixture) in a tempdir cache with matching etag
# sidecars, and redirect cvm_cache_root() at it.
local_prepare_cvm_cache <- function(
  datasets,
  years = 2024L,
  envir = parent.frame()
) {
  cache_root <- withr::local_tempdir(.local_envir = envir)
  withr::local_options(
    cvmdata.cache_dir = cache_root,
    .local_envir = envir
  )
  cvmdata:::ticker_lookup_cache_clear()
  withr::defer(cvmdata:::ticker_lookup_cache_clear(), envir = envir)
  for (ds in datasets) {
    for (yr in years) {
      raw_dir <- file.path(cache_root, "raw", "companhias", ds, yr)
      dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
      zip_name <- sprintf("%s_cia_aberta_%d.zip", ds, as.integer(yr))
      file.copy(
        test_path("fixtures", zip_name),
        file.path(raw_dir, zip_name)
      )
      saveRDS(
        list(
          etag = "\"fixture-etag\"",
          last_modified = "Mon, 19 May 2026 00:00:00 GMT",
          fetched_at = "2026-05-19T00:00:00.000Z"
        ),
        file.path(raw_dir, paste0(zip_name, ".etag.rds"))
      )
    }
  }
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

with_fixture_http <- function(expr) {
  httr2::with_mocked_responses(function(req) fresh_head_response(), expr)
}

# Pin the years the CVM "publishes" for every yearly dataset, so the
# ticker lookup (all FCA years from 2018) and the restated reading (the
# following year's file) only ask for files the fixtures provide.
local_published_years <- function(
  years = c(2024L, 2025L),
  envir = parent.frame()
) {
  testthat::local_mocked_bindings(
    cvm_dataset_years = function(dataset, group = NULL, schema = NULL) years,
    .env = envir
  )
}

# Stage the CAD fixture as the cached `cad_cia_aberta.csv` with a fresh
# etag sidecar (same pattern as test-issuer-fetch-cad.R).
local_prepare_cad_cache <- function(envir = parent.frame()) {
  cache_root <- withr::local_tempdir(.local_envir = envir)
  withr::local_options(cvmdata.cache_dir = cache_root, .local_envir = envir)
  raw_dir <- file.path(cache_root, "raw", "companhias", "cad")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  file.copy(
    test_path("fixtures", "cad_sample.csv"),
    file.path(raw_dir, "cad_cia_aberta.csv")
  )
  saveRDS(
    list(
      etag = "\"fixture-etag\"",
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = "2026-05-19T00:00:00.000Z"
    ),
    file.path(raw_dir, "cad_cia_aberta.csv.etag.rds")
  )
  cache_root
}

bb_cnpj <- "00.000.000/0001-91" # BCO BRASIL S.A.
mglu_cnpj <- "47960950000121" # MAGAZINE LUIZA S.A.
