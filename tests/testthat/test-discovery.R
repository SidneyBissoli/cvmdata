# Tests for cvm_datasets(), cvm_tables() and cvm_dictionary().

test_that("cvm_datasets returns the four covered datasets", {
  ds <- cvm_datasets()
  expect_setequal(ds, c("cad", "dfp", "fre", "itr"))
})

test_that("cvm_tables('fre') returns 36 tables", {
  expect_length(cvm_tables("fre"), 36L)
})

test_that("cvm_dictionary('dfp', 'bpa') returns parsed rows", {
  d <- cvm_dictionary("dfp", "bpa")
  expect_s3_class(d, "tbl_df")
  expect_named(
    d,
    c("column", "campo", "descricao", "dominio", "tipo_dados",
      "tamanho", "precisao", "scale")
  )
  expect_gt(nrow(d), 0L)
  expect_true(all(!is.na(d$tipo_dados)))
  expect_true(any(d$tipo_dados == "date"))
  expect_null(attr(d, "meta_status"))
})

test_that("cvm_dictionary('fre', 'auditor') returns 18 rows with tipo_dados", {
  d <- cvm_dictionary("fre", "auditor")
  expect_identical(nrow(d), 18L)
  expect_true(all(!is.na(d$tipo_dados)))
  expect_null(attr(d, "meta_status"))
})

test_that("cvm_dictionary('fre', 'empregado_PCD') flags meta_status:missing", {
  d <- cvm_dictionary("fre", "empregado_PCD")
  expect_gt(nrow(d), 0L)
  expect_true(all(is.na(d$tipo_dados)))
  expect_true(all(is.na(d$descricao)))
  expect_true(all(is.na(d$tamanho)))
  expect_identical(attr(d, "meta_status"), "missing")
})

test_that("cvm_dictionary errors on unknown dataset", {
  expect_error(
    cvm_dictionary("nope", "bpa"),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_dictionary errors on unknown table in known dataset", {
  expect_error(
    cvm_dictionary("dfp", "no_such_table"),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_dictionary errors on non-string arguments", {
  expect_error(cvm_dictionary(NULL, "bpa"), class = "cvmdata_error_input")
  expect_error(cvm_dictionary("dfp", NULL), class = "cvmdata_error_input")
  expect_error(cvm_dictionary("", "bpa"), class = "cvmdata_error_input")
  expect_error(cvm_dictionary(c("a", "b"), "c"), class = "cvmdata_error_input")
})
