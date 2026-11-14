# Tests for inst/etl/util-snapshot.R, the dated snapshots of 03-publish.R
# (decision of 2026-10-25): which partitions go into today's snapshot,
# where every partition is said to live, and the file digests the client
# verifies downloads against.

load_etl_snapshot <- function() {
  skip_if_not_installed("digest")
  installed <- system.file("etl", "util-snapshot.R", package = "cvmdata")
  script <- if (nzchar(installed)) {
    installed
  } else {
    normalizePath(
      test_path("..", "..", "inst", "etl", "util-snapshot.R"),
      winslash = "/"
    )
  }
  sys.source(script, envir = parent.frame())
}

data_now <- list(
  "bpa/report_type=ind/year=2024/part-0.parquet" = "aaa",
  "bpa/report_type=ind/year=2025/part-0.parquet" = "bbb",
  "submissao/year=2025/part-0.parquet" = "ccc"
)

test_that("the first snapshot takes every partition", {
  load_etl_snapshot()
  expect_identical(snapshot_changed_partitions(NULL, data_now), names(data_now))
  # A sidecar written before the snapshots has no `releases` map: the
  # content may be unchanged, but nothing says where it lives.
  prev <- list(hash = "h", data = data_now)
  expect_identical(snapshot_changed_partitions(prev, data_now), names(data_now))
})

test_that("later snapshots take the new and the changed partitions", {
  load_etl_snapshot()
  tag_a <- "mirror-companhias-dfp-snapshot-2026-10-27"
  prev <- list(
    data = list(
      "bpa/report_type=ind/year=2024/part-0.parquet" = "aaa",
      "bpa/report_type=ind/year=2025/part-0.parquet" = "old",
      "parecer/year=2024/part-0.parquet" = "gone"
    ),
    releases = list(
      "bpa/report_type=ind/year=2024/part-0.parquet" = tag_a,
      "bpa/report_type=ind/year=2025/part-0.parquet" = tag_a,
      "parecer/year=2024/part-0.parquet" = tag_a
    ),
    snapshots = list("2026-10-27")
  )
  changed <- snapshot_changed_partitions(prev, data_now)
  expect_setequal(
    changed,
    c(
      "bpa/report_type=ind/year=2025/part-0.parquet",
      "submissao/year=2025/part-0.parquet"
    )
  )

  tag_b <- "mirror-companhias-dfp-snapshot-2026-11-03"
  releases <- snapshot_releases_map(prev, data_now, changed, tag_b)
  expect_named(releases, names(data_now))
  expect_identical(
    unname(unlist(releases)),
    c(tag_a, tag_b, tag_b)
  )
  # A partition the mirror no longer has leaves the map with it.
  expect_false("parecer/year=2024/part-0.parquet" %in% names(releases))

  expect_identical(
    snapshot_dates(prev, as.Date("2026-11-03")),
    c("2026-10-27", "2026-11-03")
  )
  # Same day twice (a retry) does not duplicate the date.
  expect_identical(
    snapshot_dates(prev, as.Date("2026-10-27")),
    "2026-10-27"
  )
  expect_identical(snapshot_dates(NULL, as.Date("2026-10-27")), "2026-10-27")
})

test_that("a partition without a pointer in the previous sidecar is re-sent", {
  load_etl_snapshot()
  prev <- list(
    data = data_now,
    releases = list(
      "bpa/report_type=ind/year=2024/part-0.parquet" = "t",
      "submissao/year=2025/part-0.parquet" = "t"
    )
  )
  expect_identical(
    snapshot_changed_partitions(prev, data_now),
    "bpa/report_type=ind/year=2025/part-0.parquet"
  )
})

test_that("file digests are keyed by partition path with the real sha256", {
  load_etl_snapshot()
  root <- withr::local_tempdir()
  rel <- "bpa/report_type=ind/year=2024/part-0.parquet"
  path <- file.path(root, rel)
  dir.create(dirname(path), recursive = TRUE)
  writeBin(as.raw(1:64), path)
  digests <- snapshot_file_digests(path, root)
  expect_named(digests, rel)
  expect_identical(digests[[rel]]$size, 64)
  expect_identical(
    digests[[rel]]$sha256,
    digest::digest(file = path, algo = "sha256")
  )
  expect_identical(digests[[rel]]$sha256, unname(tools::sha256sum(path)))
})

# The digests a dated sidecar publishes describe the bytes at the
# pointers, not the file rewritten locally (defect found 2026-11-07).
rel_2024 <- "bpa/year=2024/part-0.parquet"
rel_2025 <- "bpa/year=2025/part-0.parquet"

test_that("unchanged partitions keep the digest of the bytes they point to", {
  load_etl_snapshot()
  local <- list(
    "bpa/year=2024/part-0.parquet" = list(sha256 = "new-a", size = 11),
    "bpa/year=2025/part-0.parquet" = list(sha256 = "new-b", size = 22)
  )
  prev <- list(
    snapshot_files = list(
      "bpa/year=2024/part-0.parquet" = list(sha256 = "old-a", size = 10)
    )
  )
  out <- snapshot_pointer_digests(local, prev, changed = rel_2025)
  expect_identical(out[[rel_2024]]$sha256, "old-a")
  expect_identical(out[[rel_2024]]$size, 10)
  expect_identical(out[[rel_2025]]$sha256, "new-b")
  # the first snapshot changes every partition: nothing to carry over
  expect_identical(snapshot_pointer_digests(local, NULL, names(local)), local)
})

test_that("a sidecar without snapshot_files stops the run and names the fix", {
  load_etl_snapshot()
  local <- list("bpa/year=2024/part-0.parquet" = list(sha256 = "x", size = 1))
  prev <- list(releases = list("bpa/year=2024/part-0.parquet" = "old-tag"))
  expect_error(
    snapshot_pointer_digests(local, prev, changed = character()),
    "no `snapshot_files` entry for the unchanged partition bpa/year=2024"
  )
  expect_error(
    snapshot_pointer_digests(local, prev, changed = character()),
    "run inst/etl/repair-snapshot-digests.R"
  )
})

test_that("the repair rebuilds the files map from the bytes at the pointers", {
  load_etl_snapshot()
  sidecar <- list(
    snapshot = "2026-11-03",
    files = list(
      "bpa/year=2024/part-0.parquet" = list(sha256 = "local-a", size = 11),
      "bpa/year=2025/part-0.parquet" = list(sha256 = "local-b", size = 22)
    ),
    releases = list(
      "bpa/year=2024/part-0.parquet" = "snap-2026-10-27",
      "bpa/year=2025/part-0.parquet" = "snap-2026-11-03"
    )
  )
  stored <- list(
    "snap-2026-10-27|bpa/year=2024/part-0.parquet" = list(
      sha256 = "stored-a",
      size = 10
    ),
    "snap-2026-11-03|bpa/year=2025/part-0.parquet" = list(
      sha256 = "local-b",
      size = 22
    )
  )
  lookup <- function(tag, rel) stored[[paste(tag, rel, sep = "|")]]
  repaired <- snapshot_repair_files(sidecar, lookup)
  files <- repaired$sidecar$files
  expect_identical(repaired$fixed, rel_2024)
  expect_identical(files[[rel_2024]]$sha256, "stored-a")
  expect_identical(files[[rel_2024]]$size, 10)
  expect_identical(files[[rel_2025]]$sha256, "local-b")
  expect_identical(repaired$sidecar$releases, sidecar$releases)
  sidecar$releases[[rel_2025]] <- NULL
  expect_error(snapshot_repair_files(sidecar, lookup), "no release pointer")
})

# The repair rewrites a sidecar it read: a JSON null (a skip without
# report_type) must come out as null again, not as `{}` (2026-11-07:
# the first repair broke every client on the fre sidecars).
etl_script_path <- function(script) {
  installed <- system.file("etl", script, package = "cvmdata")
  if (nzchar(installed)) {
    return(installed)
  }
  normalizePath(test_path("..", "..", "inst", "etl", script), winslash = "/")
}

test_that("the repair writes a read sidecar back with its nulls", {
  load_etl_snapshot()
  skip_if_not_installed("jsonlite")
  withr::local_options(cvmdata.etl_testing = TRUE)
  env <- environment()
  scripts <- c("00-config.R", "util-release.R", "repair-snapshot-digests.R")
  for (script in scripts) {
    sys.source(etl_script_path(script), envir = env)
  }
  root <- withr::local_tempdir()
  original <- file.path(root, "in.json")
  writeLines(
    paste0(
      '{"skips":[{"table":"t","year":2026,"report_type":null,',
      '"reason":"absent"}],"snapshots":["2026-11-03"]}'
    ),
    original
  )
  sidecar <- jsonlite::read_json(original)
  out <- repair_write_sidecar(sidecar, file.path(root, "out", "sidecar.json"))
  text <- paste(readLines(out), collapse = "")
  expect_match(text, '"report_type":[[:space:]]*null')
  expect_false(grepl("{}", text, fixed = TRUE))
  back <- jsonlite::read_json(out)
  expect_null(back$skips[[1L]]$report_type)
})

test_that("a skip field read as an empty list becomes null again", {
  load_etl_snapshot()
  sidecar <- jsonlite::fromJSON(
    paste0(
      '{"skips":[{"table":"a","year":2026,"report_type":{},"reason":"absent"},',
      '{"table":"b","year":2025,"report_type":"ind","reason":"empty"}]}'
    ),
    simplifyVector = FALSE
  )
  out <- snapshot_normalise_skips(sidecar)
  expect_true(out$changed)
  expect_null(out$sidecar$skips[[1L]]$report_type)
  expect_identical(out$sidecar$skips[[2L]]$report_type, "ind")
  text <- jsonlite::toJSON(out$sidecar, auto_unbox = TRUE, null = "null")
  expect_match(as.character(text), '"report_type":null', fixed = TRUE)
  clean <- snapshot_normalise_skips(out$sidecar)
  expect_false(clean$changed)
  expect_false(snapshot_normalise_skips(list(skips = list()))$changed)
})

# The public URL of a release serves the old bytes for a few minutes
# after an asset is replaced (2026-11-14: the digest repair run right
# after the personal-data repair measured the old files and reported
# nothing to fix). A download is checked against the sha256 the API
# lists, and a stale copy is fetched again through the API.
load_etl_release <- function(env = parent.frame()) {
  withr::local_options(cvmdata.etl_testing = TRUE)
  for (script in c("00-config.R", "util-release.R")) {
    sys.source(etl_script_path(script), envir = env)
  }
}

test_that("the asset listing of a release becomes sha256 by name", {
  skip_if_not_installed("jsonlite")
  load_etl_release()
  json <- paste0(
    '{"assets":[',
    '{"name":"a.parquet","digest":"sha256:abc123","size":10},',
    '{"name":"old.parquet","digest":null,"size":20},',
    '{"name":"other.parquet","digest":"sha512:ffff","size":30}]}'
  )
  expect_identical(
    parse_asset_digests(json),
    c(
      "a.parquet" = "abc123",
      "old.parquet" = NA_character_,
      "other.parquet" = NA_character_
    )
  )
})

test_that("a stale public copy is fetched again through the API", {
  skip_if_not_installed("digest")
  load_etl_release()
  env <- environment()
  dir <- withr::local_tempdir()
  name <- "t__year.2024__part-0.parquet"
  fresh <- file.path(withr::local_tempdir(), "fresh.bin")
  writeBin(charToRaw("new bytes"), fresh)
  fresh_sha <- digest::digest(file = fresh, algo = "sha256")
  api_calls <- 0L
  env$download_release_asset <- function(tag, name, dir, attempts = 3L) {
    api_calls <<- api_calls + 1L
    file.copy(fresh, file.path(dir, name), overwrite = TRUE)
    file.path(dir, name)
  }
  stale <- function(req) {
    writeBin(charToRaw("old bytes"), file.path(dir, name))
    httr2::response(status_code = 200L, body = charToRaw("old bytes"))
  }
  httr2::with_mocked_responses(stale, {
    # no expectation: the public copy is taken as it comes
    plain <- download_public_asset("tag", name, dir)
    expect_identical(readBin(plain, "raw", 100L), charToRaw("old bytes"))
    expect_identical(api_calls, 0L)
    # an asset the API lists without a digest is not checked either
    download_public_asset("tag", name, dir, expect_sha256 = NA_character_)
    expect_identical(api_calls, 0L)
    expect_message(
      path <- download_public_asset(
        "tag",
        name,
        dir,
        expect_sha256 = fresh_sha
      ),
      "stale copy"
    )
    expect_identical(api_calls, 1L)
    expect_identical(readBin(path, "raw", 100L), charToRaw("new bytes"))
    # the API copy differing too is not something to carry on with
    expect_error(
      suppressMessages(
        download_public_asset("tag", name, dir, expect_sha256 = "0000")
      ),
      "does not have the sha256"
    )
  })
})
