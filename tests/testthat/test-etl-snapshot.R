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
  expect_identical(names(releases), names(data_now))
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
  expect_identical(names(digests), rel)
  expect_identical(digests[[rel]]$size, 64)
  expect_identical(
    digests[[rel]]$sha256,
    digest::digest(file = path, algo = "sha256")
  )
  expect_identical(digests[[rel]]$sha256, unname(tools::sha256sum(path)))
})
