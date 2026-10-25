# Shared mock of the GitHub Releases mirror for tests that exercise
# `source = "mirror"` (test-source-mirror-duckdb.R, test-cvm-fetch.R,
# test-mirror-snapshot.R). The API listing and the asset downloads both
# go through httr2, so a single `httr2::with_mocked_responses()` handler
# covers both; parquet bytes come from local fixtures under
# tests/testthat/fixtures/.

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

# SHA-256 of a fixture, as the ETL would publish it in the sidecar's
# `files` map.
fixture_sha256 <- function(path) {
  unname(tools::sha256sum(path))
}

# The partition path the ETL writes for an asset name (the inverse of
# the `__` / `.` encoding), so a sidecar's `data`, `files` and
# `releases` maps can be keyed the way the ETL keys them.
asset_rel <- function(name) {
  rel <- gsub("__", "/", name, fixed = TRUE)
  rel <- sub("report_type.", "report_type=", rel, fixed = TRUE)
  sub("year.", "year=", rel, fixed = TRUE)
}

# `files` map of a sidecar for the entries that have a fixture, keyed by
# partition path.
fixture_files_map <- function(entries) {
  out <- list()
  for (e in entries) {
    if (!is.null(e$parquet) && !grepl("__history", e$name, fixed = TRUE)) {
      out[[asset_rel(e$name)]] <- list(
        sha256 = fixture_sha256(e$parquet),
        size = file.info(e$parquet)$size
      )
    }
  }
  out
}

# Build a mock that:
#   - Returns the fake release JSON for the API URL.
#   - Returns parquet bytes (or 404) for asset GETs, whether the URL is
#     the fake `base` of the API listing or a snapshot download URL
#     (`.../releases/download/<tag>/<name>`).
#   - Returns a fake __source_hash.json body when one is requested.
#   - `skips`: optional data frame (table, year, report_type, reason)
#     carried by the fake `__source_hash.json` as the ETL's skip manifest.
#   - `sidecar`: optional list of further fields of the `-latest` sidecar
#     (`snapshot`, `snapshots`, `releases`, `files`, `data`), as the ETL
#     writes them since the dated snapshots.
#   - `snapshots`: optional named list, tag -> sidecar body, served for
#     `.../releases/download/<tag>/__source_hash.json`.
#   - `files`: when TRUE, the `-latest` sidecar carries a `files` map
#     with the real sha256 and size of every entry that has a fixture.
#   - `snapshot_assets`: optional named list, tag -> entries, the assets
#     served for `.../releases/download/<tag>/<name>` (the bytes of that
#     snapshot); a tag absent here falls back to `entries`.
build_mock <- function(
  entries,
  hash = NA_character_,
  base = "https://example.test",
  skips = NULL,
  sidecar = NULL,
  snapshots = NULL,
  files = FALSE,
  snapshot_assets = NULL
) {
  # The client only fetches the sidecar when the listing names it: a
  # mock with a hash lists it unless the test already did.
  listed <- vapply(entries, function(e) e$name, character(1L))
  if (!is.na(hash) && !"__source_hash.json" %in% listed) {
    entries <- c(entries, list(list(name = "__source_hash.json")))
  }
  body <- fake_release(entries, base = base)
  latest_sidecar <- mock_latest_sidecar(hash, skips, sidecar, files, entries)
  function(req) {
    if (grepl("api.github.com", req$url, fixed = TRUE)) {
      return(httr2::response_json(status_code = 200L, body = body))
    }
    name <- basename(req$url)
    tag <- if (grepl("/releases/download/", req$url, fixed = TRUE)) {
      basename(dirname(req$url))
    } else {
      NA_character_
    }
    if (identical(name, "__source_hash.json")) {
      return(mock_serve_sidecar(tag, snapshots, latest_sidecar))
    }
    pool <- if (!is.na(tag) && !is.null(snapshot_assets[[tag]])) {
      snapshot_assets[[tag]]
    } else {
      entries
    }
    mock_serve_asset(name, pool)
  }
}

# The `-latest` sidecar body, or NULL when the mock publishes none.
mock_latest_sidecar <- function(hash, skips, sidecar, files, entries) {
  if (is.na(hash)) {
    return(NULL)
  }
  out <- list(hash = hash, components = list())
  if (!is.null(skips)) {
    out$skips <- skips
  }
  if (isTRUE(files)) {
    out$files <- fixture_files_map(entries)
  }
  for (field in names(sidecar)) {
    out[[field]] <- sidecar[[field]]
  }
  out
}

# A sidecar GET: the snapshot's manifest when the URL names a snapshot
# tag the mock knows, 404 for a snapshot it does not, else `-latest`'s.
mock_serve_sidecar <- function(tag, snapshots, latest_sidecar) {
  if (!is.na(tag) && !is.null(snapshots[[tag]])) {
    return(httr2::response_json(status_code = 200L, body = snapshots[[tag]]))
  }
  if (!is.na(tag) && grepl("-snapshot-", tag, fixed = TRUE)) {
    return(httr2::response(404L))
  }
  if (is.null(latest_sidecar)) {
    return(httr2::response(404L))
  }
  httr2::response_json(status_code = 200L, body = latest_sidecar)
}

# An asset GET: the fixture bytes of the entry with that name, or 404.
mock_serve_asset <- function(name, pool) {
  hit <- NULL
  for (e in pool) {
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

# Path helpers — keep the test names short.
cad_fx <- function() test_path("fixtures", "mirror-cad-companhias.parquet")
dfp_fx <- function() test_path("fixtures", "mirror-dfp-bpa-ind-2024.parquet")
