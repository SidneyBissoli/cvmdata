# Tests for inst/etl/02b-validate.R. Sources the script with the
# testing guard so the functions are loaded but the CLI driver does
# not fire. Both `arrow` and `pointblank` live in Suggests, so the
# whole file skips when either is missing (which happens on minimal
# R-CMD-check installs of the package).

skip_if_not_installed("arrow")
skip_if_not_installed("pointblank")
skip_if_not_installed("jsonlite")

# Source the helpers from the ETL script. The script uses paths
# relative to the package root (`source("inst/etl/00-config.R")`), so
# the working directory has to move up out of tests/testthat/ first.
load_etl_validator <- function() {
  # Prefer the installed copy (`<libpath>/cvmdata/etl/`) under
  # R CMD check; fall back to the source tree under devtools::test().
  installed <- system.file("etl", "02b-validate.R", package = "cvmdata")
  script <- if (nzchar(installed)) {
    installed
  } else {
    normalizePath(test_path("..", "..", "inst", "etl", "02b-validate.R"),
                  winslash = "/")
  }
  withr::local_options(cvmdata.etl_testing = TRUE,
                       .local_envir = parent.frame())
  sys.source(script, envir = parent.frame())
}

cad_fx <- function() test_path("fixtures", "mirror-cad-companhias.parquet")

# --- validate_parquet_path ----------------------------------------------

test_that("validate_parquet_path builds Hive-style locations", {
  load_etl_validator()
  expect_identical(
    validate_parquet_path("/tmp/w", "companhias", "cad", "companhias",
                          NA, NULL),
    file.path("/tmp/w", "out", "parquet",
              "companhias", "cad", "companhias", "part-0.parquet")
  )
  expect_identical(
    validate_parquet_path("/tmp/w", "companhias", "dfp", "bpa",
                          2024L, "ind"),
    file.path("/tmp/w", "out", "parquet",
              "companhias", "dfp", "bpa",
              "report_type=ind", "year=2024", "part-0.parquet")
  )
})

# --- validate_one_parquet ----------------------------------------------

test_that("validate_one_parquet passes on a clean CAD fixture", {
  load_etl_validator()
  hints <- validate_schema_hints("cad", "companhias")
  result <- validate_one_parquet(cad_fx(), "cad", "companhias", hints)
  expect_s3_class(result, "tbl_df")
  expect_true(all(result$status == "pass"))
  expect_true(all(c("parquet_exists", "parquet_readable",
                    "n_rows > 0") %in% result$check))
})

test_that("validate_one_parquet returns hard fail when file missing", {
  load_etl_validator()
  hints <- validate_schema_hints("cad", "companhias")
  result <- validate_one_parquet(
    "/this/does/not/exist.parquet", "cad", "companhias", hints
  )
  expect_equal(nrow(result), 1L)
  expect_identical(result$check, "parquet_exists")
  expect_identical(result$severity, "hard")
  expect_identical(result$status, "fail")
})

test_that("validate_one_parquet returns hard fail on empty parquet", {
  load_etl_validator()
  hints <- validate_schema_hints("cad", "companhias")
  tmp <- tempfile(fileext = ".parquet")
  empty <- tibble::tibble(
    cnpj_cia = character(0L),
    cd_cvm = character(0L)
  )
  arrow::write_parquet(empty, tmp)
  result <- validate_one_parquet(tmp, "cad", "companhias", hints)
  expect_identical(
    result$status[result$check == "n_rows > 0"], "fail"
  )
  expect_true(all(result$severity[result$status == "fail"] == "hard"))
})

test_that("validate_one_parquet flags soft fail on bad CNPJ format", {
  load_etl_validator()
  hints <- validate_schema_hints("cad", "companhias")
  tmp <- tempfile(fileext = ".parquet")
  bad <- tibble::tibble(
    cnpj_cia = c("00.000.000/0001-91", "not-a-cnpj"),
    cd_cvm = c("1023", "abc"),
    denom_cia = c("BCO BRASIL", "FAKE")
  )
  arrow::write_parquet(bad, tmp)
  result <- validate_one_parquet(tmp, "cad", "companhias", hints)
  # Synthetic checks pass.
  syn <- result[result$check %in%
                  c("parquet_exists", "parquet_readable", "n_rows > 0"), ]
  expect_true(all(syn$status == "pass"))
  # Hard col_is_character passes (cnpj_cia is character).
  hard_fail <- result[result$severity == "hard" & result$status == "fail", ]
  expect_equal(nrow(hard_fail), 0L)
  # Soft checks catch the bad cnpj and the non-digit cd_cvm.
  soft_fail <- result[result$severity == "soft" & result$status == "fail", ]
  expect_true(nrow(soft_fail) >= 2L)
})

# --- empty-upstream manifest (legitimately 0-row years) ----------------

test_that("validate_tuple_key collapses NA/NULL year and report_type", {
  load_etl_validator()
  expect_identical(
    validate_tuple_key("departamento_acionistas", 2024L, NULL),
    "departamento_acionistas|2024|"
  )
  expect_identical(
    validate_tuple_key("bpa", 2024L, "ind"),
    "bpa|2024|ind"
  )
  expect_identical(
    validate_tuple_key("companhias", NA, NA),
    "companhias||"
  )
})

test_that("validate_skip_set returns empty without a manifest", {
  load_etl_validator()
  expect_length(validate_skip_set("fca", withr::local_tempdir()), 0L)
})

test_that("validate_skip_set parses the stage-02 manifest with reasons", {
  load_etl_validator()
  workspace <- withr::local_tempdir()
  skip_dir <- file.path(workspace, "out", "skip")
  dir.create(skip_dir, recursive = TRUE)
  jsonlite::write_json(
    data.frame(
      table = c("departamento_acionistas", "composicao_capital"),
      year = c(2024L, 2015L),
      report_type = c(NA_character_, NA_character_),
      reason = c("empty", "absent"),
      stringsAsFactors = FALSE
    ),
    file.path(skip_dir, "fca.json"),
    auto_unbox = TRUE, na = "null"
  )
  skip <- validate_skip_set("fca", workspace)
  k_empty <- validate_tuple_key("departamento_acionistas", 2024L, NULL)
  k_absent <- validate_tuple_key("composicao_capital", 2015L, NULL)
  expect_identical(skip[[k_empty]], "empty")
  expect_identical(skip[[k_absent]], "absent")
})

test_that("missing parquet is a soft pass when skipped (empty / absent)", {
  load_etl_validator()
  hints <- validate_schema_hints("fca", "departamento_acionistas")
  for (reason in c("empty", "absent")) {
    result <- validate_one_parquet(
      "/this/does/not/exist.parquet", "fca", "departamento_acionistas",
      hints, skip_reason = reason
    )
    expect_equal(nrow(result), 1L)
    expect_identical(result$check, sprintf("upstream_%s", reason))
    expect_identical(result$severity, "soft")
    expect_identical(result$status, "pass")
  }
})

test_that("missing parquet stays a hard fail when not skipped", {
  # Same missing path, skip_reason = NULL (the default) — the
  # pre-existing contract for genuinely absent files must be preserved.
  load_etl_validator()
  hints <- validate_schema_hints("fca", "departamento_acionistas")
  result <- validate_one_parquet(
    "/this/does/not/exist.parquet", "fca", "departamento_acionistas",
    hints
  )
  expect_identical(result$check, "parquet_exists")
  expect_identical(result$severity, "hard")
  expect_identical(result$status, "fail")
})

# --- validate_dataset end-to-end ---------------------------------------

test_that("validate_dataset reports pass for a clean CAD workspace", {
  load_etl_validator()
  workspace <- withr::local_tempdir()
  dest_dir <- file.path(
    workspace, "out", "parquet", "companhias", "cad", "companhias"
  )
  dir.create(dest_dir, recursive = TRUE)
  file.copy(cad_fx(), file.path(dest_dir, "part-0.parquet"))

  results <- validate_dataset("companhias", "cad", workspace)
  expect_equal(nrow(results), 1L)
  expect_identical(results$status, "pass")
  expect_equal(results$hard_failed, 0L)
  expect_equal(results$soft_failed, 0L)
})

test_that("validate_dataset reports hard_fail for missing parquet", {
  load_etl_validator()
  workspace <- withr::local_tempdir()
  # Note: nothing copied; validate_dataset expects companhias to be present.
  results <- validate_dataset("companhias", "cad", workspace)
  expect_identical(results$status, "hard_fail")
  expect_true(results$hard_failed >= 1L)
})

test_that("validate_write_report writes a markdown summary", {
  load_etl_validator()
  workspace <- withr::local_tempdir()
  dest_dir <- file.path(
    workspace, "out", "parquet", "companhias", "cad", "companhias"
  )
  dir.create(dest_dir, recursive = TRUE)
  file.copy(cad_fx(), file.path(dest_dir, "part-0.parquet"))

  results <- validate_dataset("companhias", "cad", workspace)
  report_dir <- file.path(workspace, "out", "validation")
  out_path <- validate_write_report(results, "cad", report_dir)
  expect_true(file.exists(out_path))
  content <- readLines(out_path)
  expect_true(any(grepl("ETL validation report: cad", content,
                        fixed = TRUE)))
  expect_true(any(grepl("PASS", content)))
})
