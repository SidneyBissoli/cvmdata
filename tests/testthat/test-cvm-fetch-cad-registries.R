# cvm_fetch() on the two other CVM registries of the cad dataset:
# cad/estrangeiras (foreign companies) and cad/incentivadas
# (tax-incentive companies). Both are one CSV, today's state of every
# registration, like cad/companhias, but the issuer column is plain
# `cnpj` (not `cnpj_cia`).
#
# Fixtures (tests/testthat/fixtures/*.meta.json):
# - cad_estrangeiras_sample.csv: the whole file of 2026-10-31, 27 rows.
# - cad_incentivadas_sample.csv: 35 of its 3570 rows, picked to cover
#   every non-cancelled SIT, three re-registered companies, empty
#   CD_CVM and cells with a double quote.

local_registries_cache <- function(envir = parent.frame()) {
  root <- local_prepare_cad_cache(
    "cad_estrangeiras_sample.csv",
    "cad_cia_estrang.csv",
    envir = envir
  )
  local_prepare_cad_cache(
    "cad_incentivadas_sample.csv",
    "cad_cia_incent.csv",
    cache_root = root,
    envir = envir
  )
}

test_that("cad lists the three registries", {
  expect_setequal(
    cvm_tables("cad"),
    c("companhias", "estrangeiras", "incentivadas")
  )
})

test_that("cad/estrangeiras reads the whole file as the CVM publishes it", {
  skip_if_not_installed("httptest2")
  local_registries_cache()
  x <- with_fixture_http(cvm_fetch("cad", "estrangeiras", source = "cvm"))
  expect_s3_class(x, "cvm_tbl")
  expect_identical(attr(x, "table"), "estrangeiras")
  expect_identical(dim(x), c(27L, 49L))
  expect_true(all(c("cnpj", "pais_origem", "cidade", "estado") %in% names(x)))
  expect_false(any(c("cnpj_cia", "tp_merc", "mun", "uf") %in% names(x)))
  expect_type(x$cnpj, "character")
  expect_type(x$cd_cvm, "character")
  expect_s3_class(x$dt_reg, "Date")
  expect_false(anyNA(x$cd_cvm))
  # One row appears twice verbatim: kept, as published.
  expect_identical(sum(duplicated(as.data.frame(x))), 1L)
  expect_true(all(is.na(x$dt_cancel) == (x$sit != "CANCELADA")))
})

test_that("cad/incentivadas keeps empty CVM codes and re-registrations", {
  skip_if_not_installed("httptest2")
  local_registries_cache()
  x <- with_fixture_http(cvm_fetch("cad", "incentivadas", source = "cvm"))
  expect_s3_class(x, "cvm_tbl")
  expect_identical(dim(x), c(35L, 47L))
  expect_true("st_cia_incent_reg" %in% names(x))
  expect_setequal(unique(x$st_cia_incent_reg), c("N", "S"))
  expect_identical(sum(is.na(x$cd_cvm)), 9L)
  # Cells with a double quote are read verbatim (quote = "").
  expect_true(any(grepl("\"", x$logradouro, fixed = TRUE)))
  # A cancellation date is not always paired with SIT == CANCELADA; the
  # one empty SIT reads as NA.
  expect_identical(sum(is.na(x$sit)), 1L)
  expect_identical(
    sum(!is.na(x$dt_cancel) & !x$sit %in% "CANCELADA"),
    4L
  )
})

test_that("cnpj filters the registries through their plain cnpj column", {
  skip_if_not_installed("httptest2")
  local_registries_cache()
  est <- with_fixture_http(
    cvm_fetch("cad", "estrangeiras", cnpj = "08943312000140", source = "cvm")
  )
  expect_identical(unique(est$cnpj), "08.943.312/0001-40")
  # A re-registered company returns both registrations.
  inc <- with_fixture_http(
    cvm_fetch(
      "cad",
      "incentivadas",
      cnpj = "04.132.437/0001-30",
      source = "cvm"
    )
  )
  expect_identical(nrow(inc), 2L)
  expect_identical(unique(inc$cnpj), "04.132.437/0001-30")
  # Absent CNPJ = zero rows, silently, as in every other table.
  none <- with_fixture_http(
    cvm_fetch("cad", "estrangeiras", cnpj = "00000000000191", source = "cvm")
  )
  expect_identical(nrow(none), 0L)
})

test_that("cnpj_col prefers the issuer column over plain cnpj", {
  # fre/participacao_sociedade carries the issuer (cnpj_companhia) and
  # the investee (cnpj).
  df <- data.frame(cnpj_companhia = "a", cnpj = "b")
  expect_identical(cvmdata:::cnpj_col(df), "cnpj_companhia")
  expect_identical(cvmdata:::cnpj_col(data.frame(cnpj = "b")), "cnpj")
  expect_null(cvmdata:::cnpj_col(data.frame(x = 1)))
})

test_that("as_of applies to the two registries", {
  skip_if_not_installed("httptest2")
  local_registries_cache()
  at <- as.Date("2015-12-31")
  for (tbl in c("estrangeiras", "incentivadas")) {
    all_rows <- with_fixture_http(cvm_fetch("cad", tbl, source = "cvm"))
    u <- with_fixture_http(cvm_fetch("cad", tbl, as_of = at, source = "cvm"))
    expect_identical(
      nrow(u),
      sum(
        all_rows$dt_reg <= at &
          (is.na(all_rows$dt_cancel) | all_rows$dt_cancel > at)
      )
    )
    expect_true(nrow(u) > 0L && nrow(u) < nrow(all_rows))
  }
})

test_that("the registries refuse year, from/to and basis like cad/companhias", {
  expect_error(
    cvm_fetch("cad", "estrangeiras", basis = "ind", source = "cvm"),
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_fetch(
      "cad",
      "incentivadas",
      from = "2020-01-01",
      to = "2020-12-31",
      source = "cvm"
    ),
    class = "cvmdata_error_input"
  )
})
