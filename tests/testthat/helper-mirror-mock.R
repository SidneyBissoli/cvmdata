# Shared mock of the GitHub Releases mirror for tests that exercise
# `source = "mirror"` (test-source-mirror-duckdb.R, test-cvm-fetch.R).
# The API listing and the asset downloads both go through httr2, so a
# single `httr2::with_mocked_responses()` handler covers both; parquet
# bytes come from local fixtures under tests/testthat/fixtures/.

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
build_mock <- function(
  entries,
  hash = NA_character_,
  base = "https://example.test"
) {
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
      hit$parquet,
      what = "raw",
      n = file.info(hit$parquet)$size
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
