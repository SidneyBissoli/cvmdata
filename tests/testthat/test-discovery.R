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

test_that("cvm_codelist returns categorical values for cad/companhias/sit", {
  cl <- cvm_codelist("cad", "companhias", "sit")
  expect_s3_class(cl, "tbl_df")
  expect_named(cl, "value")
  expect_gte(nrow(cl), 2L)
  expect_true("ATIVO" %in% cl$value)
  expect_true("CANCELADA" %in% cl$value)
})

test_that("cvm_codelist returns S/N for dfp/bpa/st_conta_fixa", {
  cl <- cvm_codelist("dfp", "bpa", "st_conta_fixa")
  expect_setequal(cl$value, c("S", "N"))
})

test_that("cvm_codelist errors on identifier columns (not a codelist)", {
  # cnpj_cia exists in cad/companhias dictionary but is an identifier,
  # so it must not be in the codelists snapshot.
  expect_error(
    cvm_codelist("cad", "companhias", "cnpj_cia"),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_codelist errors on unknown dataset / table / column", {
  expect_error(
    cvm_codelist("nope", "companhias", "sit"),
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_codelist("cad", "no_such_table", "sit"),
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_codelist("cad", "companhias", "no_such_column_xyz"),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_codelist errors on non-string arguments", {
  expect_error(
    cvm_codelist(NULL, "companhias", "sit"),
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_codelist("cad", NULL, "sit"),
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_codelist("cad", "companhias", NULL),
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_codelist(c("a", "b"), "x", "y"),
    class = "cvmdata_error_input"
  )
})
