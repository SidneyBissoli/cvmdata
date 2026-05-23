# Unit tests for the public cvm_cache_*() family. All tests run
# off-line and isolate the user's real cache via
# withr::local_options(cvmdata.cache_dir = tempdir()).

# Helpers ----------------------------------------------------------------

# Build a populated raw/ tree under a fresh tempdir cache root.
# Returns the cache root path. The fixture mirrors the on-disk layout
# created by R/source-cvm-http.R:
#   raw/cad/cad_cia_aberta.csv              (CSV directo + sidecar)
#   raw/cad/cad_cia_aberta.csv.etag.rds
#   raw/dfp/2024/dfp_cia_aberta_2024.zip    (ZIP yearly + sidecar)
#   raw/dfp/2024/dfp_cia_aberta_2024.zip.etag.rds
#   raw/dfp/2024/dfp_cia_aberta_bpa_con_2024.csv   (extracted, NO sidecar)
local_populated_cache <- function(envir = parent.frame()) {
  cache_root <- withr::local_tempdir(.local_envir = envir)
  withr::local_options(
    cvmdata.cache_dir = cache_root,
    .local_envir = envir
  )
  cad_dir <- file.path(cache_root, "raw", "cad")
  dir.create(cad_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines("a;b\n1;2", file.path(cad_dir, "cad_cia_aberta.csv"))
  saveRDS(
    list(
      etag = "\"cad-etag\"",
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = "2026-05-19T00:00:00.000Z"
    ),
    file.path(cad_dir, "cad_cia_aberta.csv.etag.rds")
  )
  dfp_dir <- file.path(cache_root, "raw", "dfp", "2024")
  dir.create(dfp_dir, recursive = TRUE, showWarnings = FALSE)
  writeBin(
    as.raw(c(0x50, 0x4B, 0x05, 0x06, rep(0L, 18L))),
    file.path(dfp_dir, "dfp_cia_aberta_2024.zip")
  )
  saveRDS(
    list(
      etag = "\"dfp-etag\"",
      last_modified = "Tue, 20 May 2026 00:00:00 GMT",
      fetched_at = "2026-05-20T00:00:00.000Z"
    ),
    file.path(dfp_dir, "dfp_cia_aberta_2024.zip.etag.rds")
  )
  writeLines(
    "CD_CVM;DT_FIM_EXERC;VL_CONTA\n1023;2024-12-31;100",
    file.path(dfp_dir, "dfp_cia_aberta_bpa_con_2024.csv")
  )
  cache_root
}

# cvm_cache_path() -------------------------------------------------------

test_that("cvm_cache_path() reads cvmdata.cache_dir option", {
  tmp <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = tmp)
  expect_identical(cvm_cache_path(), tmp)
})

test_that("cvm_cache_path() falls back to tools::R_user_dir()", {
  withr::local_options(cvmdata.cache_dir = NULL)
  expect_identical(
    cvm_cache_path(),
    tools::R_user_dir("cvmdata", which = "cache")
  )
})

test_that("cvm_cache_path() does not create the directory", {
  ghost <- file.path(withr::local_tempdir(), "does-not-exist-yet")
  withr::local_options(cvmdata.cache_dir = ghost)
  result <- cvm_cache_path()
  expect_identical(result, ghost)
  expect_false(dir.exists(ghost))
})

# cvm_cache_set_path() ---------------------------------------------------

test_that("cvm_cache_set_path() creates the dir and updates option", {
  withr::local_options(cvmdata.cache_dir = NULL)
  parent <- withr::local_tempdir()
  target <- file.path(parent, "newcache")
  expect_false(dir.exists(target))
  expect_message(
    out <- cvm_cache_set_path(target),
    "Cache directory set"
  )
  expect_true(dir.exists(target))
  expect_identical(getOption("cvmdata.cache_dir"), out)
  expect_identical(
    normalizePath(out, winslash = "/", mustWork = FALSE),
    normalizePath(target, winslash = "/", mustWork = FALSE)
  )
})

test_that("cvm_cache_set_path() aborts on non-character input", {
  expect_error(
    cvm_cache_set_path(123),
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_cache_set_path(c("a", "b")),
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_cache_set_path(""),
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_cache_set_path(NA_character_),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_cache_set_path() returns the path invisibly", {
  withr::local_options(cvmdata.cache_dir = NULL)
  target <- withr::local_tempdir()
  expect_invisible(suppressMessages(cvm_cache_set_path(target)))
})

test_that("cvm_cache_set_path() aborts when dir.create() fails", {
  # Place a regular file where the cache root should live, then try to
  # create a subdirectory inside it. dir.create() fails because the
  # parent path is not a directory.
  tmp <- withr::local_tempdir()
  blocker <- file.path(tmp, "blocker")
  writeLines("not a dir", blocker)
  expect_error(
    cvm_cache_set_path(file.path(blocker, "sub")),
    class = "cvmdata_error_internal"
  )
})

# cvm_cache_info() -------------------------------------------------------

test_that("cvm_cache_info() returns empty tibble when cache absent", {
  ghost <- file.path(withr::local_tempdir(), "no-cache-here")
  withr::local_options(cvmdata.cache_dir = ghost)
  out <- cvm_cache_info()
  expect_s3_class(out, "tbl_df")
  expect_named(
    out,
    c("dataset", "file", "path", "size_bytes", "mtime",
      "etag", "last_modified")
  )
  expect_identical(nrow(out), 0L)
})

test_that("cvm_cache_info() returns empty tibble with raw/ but no files", {
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  dir.create(file.path(cache_root, "raw"), recursive = TRUE)
  out <- cvm_cache_info()
  expect_identical(nrow(out), 0L)
})

test_that("cvm_cache_info() lists artifacts and excludes sidecars", {
  local_populated_cache()
  out <- cvm_cache_info()
  expect_identical(nrow(out), 3L)
  expect_setequal(
    out$file,
    c(
      "cad_cia_aberta.csv",
      "dfp_cia_aberta_2024.zip",
      "dfp_cia_aberta_bpa_con_2024.csv"
    )
  )
  expect_false(any(grepl("\\.etag\\.rds$", out$file)))
})

test_that("cvm_cache_info() fills etag/last_modified from sidecar", {
  local_populated_cache()
  out <- cvm_cache_info()
  cad_row <- out[out$file == "cad_cia_aberta.csv", ]
  expect_identical(cad_row$etag, "\"cad-etag\"")
  expect_identical(
    cad_row$last_modified, "Mon, 19 May 2026 00:00:00 GMT"
  )
  zip_row <- out[out$file == "dfp_cia_aberta_2024.zip", ]
  expect_identical(zip_row$etag, "\"dfp-etag\"")
})

test_that("cvm_cache_info() returns NA for extracted CSV (no sidecar)", {
  local_populated_cache()
  out <- cvm_cache_info()
  extracted <- out[out$file == "dfp_cia_aberta_bpa_con_2024.csv", ]
  expect_identical(extracted$etag, NA_character_)
  expect_identical(extracted$last_modified, NA_character_)
})

test_that("cvm_cache_info() returns rows sorted by dataset then file", {
  local_populated_cache()
  out <- cvm_cache_info()
  expect_identical(out$dataset, c("cad", "dfp", "dfp"))
  expect_identical(
    out$file,
    c(
      "cad_cia_aberta.csv",
      "dfp_cia_aberta_2024.zip",
      "dfp_cia_aberta_bpa_con_2024.csv"
    )
  )
})

test_that("cvm_cache_info() schema types are correct", {
  local_populated_cache()
  out <- cvm_cache_info()
  expect_type(out$dataset, "character")
  expect_type(out$file, "character")
  expect_type(out$path, "character")
  expect_type(out$size_bytes, "integer")
  expect_s3_class(out$mtime, "POSIXct")
  expect_type(out$etag, "character")
  expect_type(out$last_modified, "character")
})

test_that("cvm_cache_info() tolerates corrupt sidecar (returns NA)", {
  cache_root <- local_populated_cache()
  # Overwrite one sidecar with garbage that readRDS cannot parse.
  bad_sidecar <- file.path(
    cache_root, "raw", "cad", "cad_cia_aberta.csv.etag.rds"
  )
  writeBin(as.raw(c(0xDE, 0xAD, 0xBE, 0xEF)), bad_sidecar)
  out <- cvm_cache_info()
  cad_row <- out[out$file == "cad_cia_aberta.csv", ]
  expect_identical(cad_row$etag, NA_character_)
  expect_identical(cad_row$last_modified, NA_character_)
})

# cvm_cache_clear() ------------------------------------------------------

test_that("cvm_cache_clear(what='all') wipes the whole cache root", {
  cache_root <- local_populated_cache()
  result <- suppressMessages(
    cvm_cache_clear(what = "all", confirm = FALSE)
  )
  # 3 artifacts (cad.csv, dfp.zip, extracted CSV) + 2 sidecars
  # (extracted CSV has no sidecar of its own).
  expect_identical(result, 5L)
  expect_false(dir.exists(cache_root))
})

test_that("cvm_cache_clear(what='raw') wipes only raw/", {
  cache_root <- local_populated_cache()
  dir.create(file.path(cache_root, "future-layer"))
  writeLines("kept", file.path(cache_root, "future-layer", "x.txt"))
  result <- suppressMessages(
    cvm_cache_clear(what = "raw", confirm = FALSE)
  )
  expect_identical(result, 5L)
  expect_false(dir.exists(file.path(cache_root, "raw")))
  expect_true(file.exists(file.path(cache_root, "future-layer", "x.txt")))
})

test_that("cvm_cache_clear(dataset = ) restricts to one dataset", {
  cache_root <- local_populated_cache()
  result <- suppressMessages(
    cvm_cache_clear(dataset = "dfp", confirm = FALSE)
  )
  # zip + zip sidecar + extracted CSV (no sidecar for extracted).
  expect_identical(result, 3L)
  expect_false(
    dir.exists(file.path(cache_root, "raw", "dfp"))
  )
  expect_true(
    file.exists(
      file.path(cache_root, "raw", "cad", "cad_cia_aberta.csv")
    )
  )
})

test_that("cvm_cache_clear(dataset = , year = ) restricts to one year", {
  cache_root <- local_populated_cache()
  # Add a second year so we can prove only one is removed.
  dir_2023 <- file.path(cache_root, "raw", "dfp", "2023")
  dir.create(dir_2023, recursive = TRUE)
  writeLines("keep me", file.path(dir_2023, "dfp_cia_aberta_2023.zip"))
  result <- suppressMessages(
    cvm_cache_clear(
      dataset = "dfp", year = 2024L, confirm = FALSE
    )
  )
  expect_identical(result, 3L)
  expect_false(
    dir.exists(file.path(cache_root, "raw", "dfp", "2024"))
  )
  expect_true(
    file.exists(
      file.path(cache_root, "raw", "dfp", "2023",
                "dfp_cia_aberta_2023.zip")
    )
  )
})

test_that("cvm_cache_clear() aborts on unknown dataset", {
  local_populated_cache()
  expect_error(
    cvm_cache_clear(dataset = "nope", confirm = FALSE),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_cache_clear() aborts on unknown year", {
  local_populated_cache()
  expect_error(
    cvm_cache_clear(
      dataset = "dfp", year = 1999L, confirm = FALSE
    ),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_cache_clear() aborts when year supplied without dataset", {
  local_populated_cache()
  expect_error(
    cvm_cache_clear(year = 2024L, confirm = FALSE),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_cache_clear() aborts on bad what / year / confirm", {
  local_populated_cache()
  expect_error(
    cvm_cache_clear(what = "bogus", confirm = FALSE),
    class = "rlang_error" # rlang::arg_match0()
  )
  expect_error(
    cvm_cache_clear(
      dataset = "dfp", year = 2024.5, confirm = FALSE
    ),
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_cache_clear(confirm = NA),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_cache_clear() aborts on non-character dataset", {
  local_populated_cache()
  expect_error(
    cvm_cache_clear(dataset = 123, confirm = FALSE),
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_cache_clear(dataset = c("dfp", "cad"), confirm = FALSE),
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_cache_clear(dataset = "", confirm = FALSE),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_cache_clear() returns 0L silently when raw/ absent", {
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  result <- suppressMessages(
    cvm_cache_clear(what = "raw", confirm = FALSE)
  )
  expect_identical(result, 0L)
})

test_that("cvm_cache_clear() honors confirm = TRUE answer = yes", {
  local_populated_cache()
  testthat::local_mocked_bindings(
    askYesNo = function(...) TRUE,
    .package = "utils"
  )
  result <- suppressMessages(
    cvm_cache_clear(dataset = "cad", confirm = TRUE)
  )
  expect_identical(result, 2L)
})

test_that("cvm_cache_clear() honors confirm = TRUE answer = no", {
  cache_root <- local_populated_cache()
  testthat::local_mocked_bindings(
    askYesNo = function(...) FALSE,
    .package = "utils"
  )
  result <- suppressMessages(
    cvm_cache_clear(dataset = "cad", confirm = TRUE)
  )
  expect_identical(result, 0L)
  expect_true(
    file.exists(
      file.path(cache_root, "raw", "cad", "cad_cia_aberta.csv")
    )
  )
})
