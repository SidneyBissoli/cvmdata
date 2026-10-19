# Tests for inst/etl/util-hash.R, the change detection of 03-publish.R.
#
# Until 2026-10-19 the publish hash covered only the CVM dictionaries, so
# new data never reached the mirror while the dictionaries stayed put.
# What is pinned here: the hash follows the parquet CONTENT, and ignores
# the attributes that change on every run (`fetched_at`).

load_etl_hash <- function() {
  skip_if_not_installed("arrow")
  skip_if_not_installed("digest")
  installed <- system.file("etl", "util-hash.R", package = "cvmdata")
  script <- if (nzchar(installed)) {
    installed
  } else {
    normalizePath(
      test_path("..", "..", "inst", "etl", "util-hash.R"),
      winslash = "/"
    )
  }
  sys.source(script, envir = parent.frame())
}

write_part <- function(dir, rel, df, fetched_at) {
  path <- file.path(dir, rel)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  attr(df, "fetched_at") <- fetched_at
  arrow::write_parquet(df, path)
  path
}

bpa_rows <- function(vl = c(14410, 9000)) {
  data.frame(
    cnpj_cia = "43.335.774/0001-86",
    cd_conta = c("1", "1.01"),
    vl_conta = vl
  )
}

test_that("the same rows hash the same across runs", {
  load_etl_hash()
  root <- withr::local_tempdir()
  run1 <- file.path(root, "run1")
  run2 <- file.path(root, "run2")
  rel <- "bpa/report_type=ind/year=2024/part-0.parquet"
  p1 <- write_part(run1, rel, bpa_rows(), as.POSIXct("2026-06-09", "UTC"))
  p2 <- write_part(run2, rel, bpa_rows(), as.POSIXct("2026-10-19", "UTC"))

  h1 <- mirror_hash_parquets(p1, run1)
  h2 <- mirror_hash_parquets(p2, run2)
  expect_named(h1, rel)
  expect_identical(h1, h2)
})

test_that("a changed value changes the hash", {
  load_etl_hash()
  root <- withr::local_tempdir()
  rel <- "bpa/report_type=ind/year=2024/part-0.parquet"
  now <- as.POSIXct("2026-10-19", "UTC")
  old <- write_part(file.path(root, "a"), rel, bpa_rows(c(31159, 9000)), now)
  new <- write_part(file.path(root, "b"), rel, bpa_rows(c(14410, 9000)), now)

  expect_false(identical(
    mirror_hash_parquets(old, file.path(root, "a")),
    mirror_hash_parquets(new, file.path(root, "b"))
  ))
})

test_that("the publish hash moves with the data even when META does not", {
  load_etl_hash()
  # Each test sources the script afresh, so a plain reassignment is local.
  compute_meta_hash <- function(dataset) {
    list(hash = "same-meta", components = list(u = "same-meta"))
  }
  root <- withr::local_tempdir()
  rel <- "bpa/year=2024/part-0.parquet"
  now <- as.POSIXct("2026-10-19", "UTC")
  a <- write_part(file.path(root, "a"), rel, bpa_rows(c(31159, 9000)), now)
  b <- write_part(file.path(root, "b"), rel, bpa_rows(c(14410, 9000)), now)

  ha <- compute_source_hash("dfp", a, file.path(root, "a"))
  hb <- compute_source_hash("dfp", b, file.path(root, "b"))
  expect_identical(ha$meta_hash, hb$meta_hash)
  expect_false(identical(ha$hash, hb$hash))

  # A new year is a new partition: the hash moves too.
  c2025 <- write_part(
    file.path(root, "b"),
    "bpa/year=2025/part-0.parquet",
    bpa_rows(),
    now
  )
  hc <- compute_source_hash("dfp", c(b, c2025), file.path(root, "b"))
  expect_length(hc$data, 2L)
  expect_false(identical(hb$hash, hc$hash))
})

test_that("the hash is NA only with neither META nor parquets", {
  load_etl_hash()
  # Each test sources the script afresh, so a plain reassignment is local.
  compute_meta_hash <- function(dataset) {
    list(hash = NA_character_, components = list())
  }
  expect_true(is.na(compute_source_hash("ipe")$hash))

  root <- withr::local_tempdir()
  p <- write_part(
    root,
    "geral/year=2024/part-0.parquet",
    bpa_rows(),
    as.POSIXct("2026-10-19", "UTC")
  )
  expect_false(is.na(compute_source_hash("ipe", p, root)$hash))
})
