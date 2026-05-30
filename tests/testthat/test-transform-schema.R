# Defensive-guard tests for R/transform-schema.R. The happy paths are
# exercised end-to-end via test-cvm-fetch.R against the DFP/FRE
# fixtures; the abort branches require synthetic malformed
# transformations because every YAML shipped in inst/extdata/schemas/
# declares well-formed `column` / `scale_column`.

test_that("tx_multiply_by_scale aborts when column/scale_column missing", {
  schema <- list(dataset = "synth", table = "x")
  df <- data.frame(vl = 1:3, esc = c("MIL", "MIL", "MIL"))
  expect_error(
    cvmdata:::tx_multiply_by_scale(
      df, tx = list(action = "multiply_by_scale"), schema = schema
    ),
    class = "cvmdata_error_internal"
  )
  expect_error(
    cvmdata:::tx_multiply_by_scale(
      df,
      tx = list(action = "multiply_by_scale", column = "vl"),
      schema = schema
    ),
    class = "cvmdata_error_internal"
  )
})

test_that("tx_multiply_by_scale aborts when columns absent from tibble", {
  schema <- list(dataset = "synth", table = "x")
  df <- data.frame(vl = 1:3, esc = c("MIL", "MIL", "MIL"))
  expect_error(
    cvmdata:::tx_multiply_by_scale(
      df,
      tx = list(
        action = "multiply_by_scale",
        column = "not_a_col",
        scale_column = "esc"
      ),
      schema = schema
    ),
    class = "cvmdata_error_parse"
  )
})

test_that("tx_multiply_by_scale no-ops on a 0-row tibble", {
  # CVM publishes header-only CSVs for the current, not-yet-filed year
  # of annual financial tables. readr then guesses a non-numeric type
  # for vl_conta, and `vl_conta * factors` used to abort with
  # "non-numeric argument to binary operator". An empty table has
  # nothing to scale: the transform must return it unchanged.
  schema <- list(dataset = "dfp", table = "dfc_md")
  tx <- list(
    action = "multiply_by_scale",
    column = "vl_conta",
    scale_column = "escala_moeda"
  )
  # vl_conta typed as character (the worst case readr produces) to prove
  # the guard fires before the arithmetic, not because of luck with types.
  empty <- data.frame(
    vl_conta = character(0L),
    escala_moeda = character(0L),
    stringsAsFactors = FALSE
  )
  out <- cvmdata:::tx_multiply_by_scale(empty, tx, schema)
  expect_identical(nrow(out), 0L)
  expect_true(all(c("vl_conta", "escala_moeda") %in% names(out)))
})

test_that("tx_drop aborts when column key is missing", {
  schema <- list(dataset = "synth", table = "x")
  df <- data.frame(a = 1:3, b = 4:6)
  expect_error(
    cvmdata:::tx_drop(
      df, tx = list(action = "drop"), schema = schema
    ),
    class = "cvmdata_error_internal"
  )
})

test_that("tx_keep_latest_version is a no-op when cnpj/date column absent", {
  # Tibble has `versao` but no cnpj_cia / cnpj_companhia and no
  # dt_refer / data_referencia → function must return the input
  # untouched (line 152 in transform-schema.R).
  df <- tibble::tibble(versao = c("1", "2"), payload = c("a", "b"))
  out <- cvmdata:::tx_keep_latest_version(
    df, tx = list(action = "keep_latest_version"),
    schema = list(dataset = "synth", table = "x")
  )
  expect_identical(out, df)
})

test_that("tx_keep_latest_version is a no-op when versao column absent", {
  df <- tibble::tibble(cnpj_cia = "x", dt_refer = "2024-12-31")
  out <- cvmdata:::tx_keep_latest_version(
    df, tx = list(action = "keep_latest_version"),
    schema = list(dataset = "synth", table = "x")
  )
  expect_identical(out, df)
})

test_that("apply_one_transformation aborts on unknown action", {
  schema <- list(dataset = "synth", table = "x")
  df <- data.frame(a = 1:3)
  expect_error(
    cvmdata:::apply_one_transformation(
      df, tx = list(action = "obliterate"), schema = schema
    ),
    class = "cvmdata_error_internal"
  )
})

test_that("apply_one_transformation aborts when action is NULL", {
  schema <- list(dataset = "synth", table = "x")
  df <- data.frame(a = 1:3)
  expect_error(
    cvmdata:::apply_one_transformation(
      df, tx = list(column = "a"), schema = schema
    ),
    class = "cvmdata_error_internal"
  )
})

test_that("scale_factor aborts on unknown scale label", {
  expect_error(
    cvmdata:::scale_factor(c("MIL", "QUINTILHAO")),
    class = "cvmdata_error_parse"
  )
})

test_that("scale_factor returns NA for NA input without aborting", {
  out <- cvmdata:::scale_factor(c("MIL", NA))
  expect_equal(out, c(1e3, NA_real_))
})
