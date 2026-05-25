# Unit tests for the internal cache_migrate_v0_1_to_v0_2() helper.
# All tests isolate the user's real cache via
# withr::local_options(cvmdata.cache_dir = tempdir()) and redirect the
# config log to a tempdir to keep the test run hermetic.

# Helpers ----------------------------------------------------------------

# Redirect both the cache root and the config-log path. Returns the
# cache_root path. Use this at the top of every test that touches the
# migrate helper so the audit log does not leak into the developer's
# real `tools::R_user_dir("cvmdata", "config")`.
local_migrate_env <- function(envir = parent.frame()) {
  cache_root <- withr::local_tempdir(.local_envir = envir)
  withr::local_options(
    cvmdata.cache_dir = cache_root,
    .local_envir = envir
  )
  log_dir <- withr::local_tempdir(.local_envir = envir)
  withr::local_envvar(
    R_USER_CONFIG_DIR = log_dir,
    .local_envir = envir
  )
  cache_root
}

# Plant a v0.1-layout artifact under `<cache>/raw/<dataset>/...`.
plant_v0_1_raw_artifact <- function(cache_root, dataset, content = "x") {
  dir <- file.path(cache_root, "raw", dataset)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(content, file.path(dir, sprintf("%s_payload.csv", dataset)))
  saveRDS(
    list(
      etag = sprintf("\"%s-etag\"", dataset),
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = "2026-05-19T00:00:00.000Z"
    ),
    file.path(dir, sprintf("%s_payload.csv.etag.rds", dataset))
  )
  invisible(dir)
}

# Plant a v0.1-layout parquet artifact under
# `<cache>/parquet/<dataset>/<table>/...`.
plant_v0_1_parquet_artifact <- function(cache_root, dataset, table,
                                        year = 2024) {
  dir <- file.path(
    cache_root, "parquet", dataset, table,
    sprintf("year=%d", year)
  )
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  writeBin(as.raw(c(0x50, 0x41, 0x52, 0x31)),
           file.path(dir, "part-0.parquet"))
  invisible(dir)
}

# Cenario (a) — cache empty -----------------------------------------------

test_that("migrate is a no-op when the cache root does not exist", {
  ghost <- file.path(withr::local_tempdir(), "does-not-exist")
  withr::local_options(cvmdata.cache_dir = ghost)
  result <- cache_migrate_v0_1_to_v0_2()
  expect_identical(result$moved, character(0L))
})

test_that("migrate is a no-op when the cache root has no v0.1 layout", {
  local_migrate_env()
  result <- cache_migrate_v0_1_to_v0_2()
  expect_identical(result$moved, character(0L))
})

test_that("migrate is a no-op on a fresh v0.1.0.9000 layout", {
  cache_root <- local_migrate_env()
  new_dir <- file.path(cache_root, "raw", "companhias", "cad")
  dir.create(new_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines("payload", file.path(new_dir, "cad_payload.csv"))
  result <- cache_migrate_v0_1_to_v0_2()
  expect_identical(result$moved, character(0L))
  expect_true(file.exists(file.path(new_dir, "cad_payload.csv")))
})

# Cenario (b) — v0.1 cache only -------------------------------------------

test_that("migrate moves v0.1 raw subtrees under <group>/<dataset>/", {
  cache_root <- local_migrate_env()
  plant_v0_1_raw_artifact(cache_root, "cad")
  plant_v0_1_raw_artifact(cache_root, "dfp")
  result <- cache_migrate_v0_1_to_v0_2()
  expect_length(result$moved, 2L)
  expect_true(dir.exists(
    file.path(cache_root, "raw", "companhias", "cad")
  ))
  expect_true(dir.exists(
    file.path(cache_root, "raw", "companhias", "dfp")
  ))
  expect_false(dir.exists(file.path(cache_root, "raw", "cad")))
  expect_false(dir.exists(file.path(cache_root, "raw", "dfp")))
  expect_true(file.exists(file.path(
    cache_root, "raw", "companhias", "cad", "cad_payload.csv"
  )))
})

test_that("migrate also moves parquet subtrees", {
  cache_root <- local_migrate_env()
  plant_v0_1_parquet_artifact(cache_root, "dfp", "bpa", year = 2024)
  result <- cache_migrate_v0_1_to_v0_2()
  expect_length(result$moved, 1L)
  expect_true(file.exists(file.path(
    cache_root, "parquet", "companhias", "dfp", "bpa",
    "year=2024", "part-0.parquet"
  )))
  expect_false(dir.exists(file.path(cache_root, "parquet", "dfp")))
})

# Cenario (c) — mixed cache -----------------------------------------------

test_that("migrate handles mixed v0.1 + v0.1.0.9000 layouts", {
  cache_root <- local_migrate_env()
  # v0.1 leftover for one dataset:
  plant_v0_1_raw_artifact(cache_root, "cad")
  # v0.1.0.9000 already-migrated for another:
  new_dir <- file.path(cache_root, "raw", "companhias", "dfp", "2024")
  dir.create(new_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines("payload", file.path(new_dir, "dfp_payload.csv"))
  result <- cache_migrate_v0_1_to_v0_2()
  expect_length(result$moved, 1L)
  expect_true(file.exists(file.path(
    cache_root, "raw", "companhias", "cad", "cad_payload.csv"
  )))
  expect_true(file.exists(file.path(new_dir, "dfp_payload.csv")))
})

# Cenario (d) — conflict --------------------------------------------------

test_that("migrate aborts before moving when a destination conflicts", {
  cache_root <- local_migrate_env()
  plant_v0_1_raw_artifact(cache_root, "cad")
  # Plant a same-name destination so the v0.1 → v0.1.0.9000 move would
  # collide.
  conflict_dir <- file.path(cache_root, "raw", "companhias", "cad")
  dir.create(conflict_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines("conflict", file.path(conflict_dir, "blocker.txt"))
  expect_error(
    cache_migrate_v0_1_to_v0_2(),
    class = "cvmdata_error_internal"
  )
  # v0.1 subtree must remain untouched (transactional pre-flight):
  expect_true(file.exists(file.path(
    cache_root, "raw", "cad", "cad_payload.csv"
  )))
})

# Cenario (e) — idempotency -----------------------------------------------

test_that("migrate is idempotent across repeated calls", {
  cache_root <- local_migrate_env()
  plant_v0_1_raw_artifact(cache_root, "fre")
  first <- cache_migrate_v0_1_to_v0_2()
  expect_length(first$moved, 1L)
  second <- cache_migrate_v0_1_to_v0_2()
  expect_identical(second$moved, character(0L))
  # A third call is still cheap:
  third <- cache_migrate_v0_1_to_v0_2()
  expect_identical(third$moved, character(0L))
})

# Cenario (f) — read-only / unwritable cache root -------------------------

test_that("migrate aborts with cvmdata_error_internal on read-only root", {
  skip_on_os("windows") # POSIX chmod semantics are not portable
  cache_root <- local_migrate_env()
  plant_v0_1_raw_artifact(cache_root, "cad")
  Sys.chmod(cache_root, "0555")
  withr::defer(Sys.chmod(cache_root, "0755"))
  expect_error(
    cache_migrate_v0_1_to_v0_2(),
    class = "cvmdata_error_internal"
  )
  # v0.1 subtree must remain untouched:
  expect_true(file.exists(file.path(
    cache_root, "raw", "cad", "cad_payload.csv"
  )))
})

# Audit log ---------------------------------------------------------------

test_that("migrate appends an entry to the audit log on every move", {
  cache_root <- local_migrate_env()
  plant_v0_1_raw_artifact(cache_root, "cad")
  result <- cache_migrate_v0_1_to_v0_2()
  expect_true(file.exists(result$log_path))
  entries <- readRDS(result$log_path)
  expect_length(entries, 1L)
  expect_identical(entries[[1L]]$cache_root, cache_root)
  expect_length(entries[[1L]]$moved, 1L)
  # A second migration on a fresh v0.1 plant adds another entry:
  plant_v0_1_raw_artifact(cache_root, "dfp")
  cache_migrate_v0_1_to_v0_2()
  entries2 <- readRDS(result$log_path)
  expect_length(entries2, 2L)
})

test_that("migrate tolerates a corrupt audit log", {
  cache_root <- local_migrate_env()
  log_path <- cache_migrate_log_path()
  ensure_dir(dirname(log_path))
  writeBin(as.raw(c(0xDE, 0xAD, 0xBE, 0xEF)), log_path)
  plant_v0_1_raw_artifact(cache_root, "cad")
  expect_no_error(cache_migrate_v0_1_to_v0_2())
  entries <- readRDS(log_path)
  expect_length(entries, 1L)
})

# Bad input ---------------------------------------------------------------

test_that("migrate returns a no-op for malformed cache_root", {
  expect_identical(
    cache_migrate_v0_1_to_v0_2(NULL)$moved, character(0L)
  )
  expect_identical(
    cache_migrate_v0_1_to_v0_2(NA_character_)$moved, character(0L)
  )
  expect_identical(
    cache_migrate_v0_1_to_v0_2("")$moved, character(0L)
  )
  expect_identical(
    cache_migrate_v0_1_to_v0_2(c("a", "b"))$moved, character(0L)
  )
})
