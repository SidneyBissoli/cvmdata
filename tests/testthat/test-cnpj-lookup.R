# cnpj_lookup(): find a company's CNPJ by name in the three cad
# registers. The matching is tested on hand-built registers (pure
# function `lookup_registers()`), the whole path on the cad fixtures
# read with source = "cvm" (see test-cvm-fetch-cad-registries.R).

register <- function(...) {
  cols <- list(...)
  n <- length(cols[[1]])
  defaults <- list(
    cnpj_cia = rep("00.000.000/0001-00", n),
    denom_social = rep("EMPRESA SA", n),
    denom_comerc = rep(NA_character_, n),
    cd_cvm = rep("1", n),
    sit = rep("ATIVO", n),
    dt_reg = rep(as.Date("2000-01-01"), n),
    dt_cancel = rep(as.Date(NA), n)
  )
  defaults[names(cols)] <- cols
  tibble::as_tibble(defaults)
}

test_that("words match in any order, ignoring case and accents", {
  regs <- list(
    companhias = register(
      cnpj_cia = c("1", "2", "3"),
      denom_social = c(
        "BANCO DO BRASIL S.A.",
        paste0("AES TIET", intToUtf8(0xCA), " ENERGIA S.A"),
        paste0("PETR", intToUtf8(0xD3), "LEO BRASILEIRO S.A. PETROBRAS")
      )
    )
  )
  expect_identical(lookup_registers(regs, "brasil banco")$cnpj_cia, "1")
  expect_identical(lookup_registers(regs, "tiete")$cnpj_cia, "2")
  expect_identical(
    lookup_registers(regs, paste0("Petr", intToUtf8(0xF3), "leo"))$cnpj_cia,
    "3"
  )
  expect_identical(lookup_registers(regs, "petroleo")$cnpj_cia, "3")
  expect_identical(lookup_registers(regs, "  brasil  ")$cnpj_cia, c("1", "3"))
  expect_identical(nrow(lookup_registers(regs, "banco petrobras")), 0L)
})

test_that("words are plain text, not regular expressions", {
  regs <- list(
    companhias = register(
      cnpj_cia = c("1", "2"),
      denom_social = c("ALFA S.A.", "ALFA SXA")
    )
  )
  expect_identical(lookup_registers(regs, "s.a.")$cnpj_cia, "1")
})

test_that("denom_comerc is searched too", {
  regs <- list(
    estrangeiras = register(
      cnpj = "9",
      denom_social = "BRAZIL FAST FOOD CORP.",
      denom_comerc = "BOB'S"
    )
  )
  regs$estrangeiras$cnpj_cia <- NULL
  out <- lookup_registers(regs, "bob's")
  expect_identical(out$cnpj_cia, "9")
  expect_identical(out$table, "estrangeiras")
})

test_that("repeats per market collapse; two registrations stay apart", {
  regs <- list(
    companhias = register(
      cnpj_cia = c("1", "1", "1"),
      denom_social = "ALFA SA",
      cd_cvm = c("10", "10", "20"),
      dt_reg = as.Date(c("2000-01-01", "2000-01-01", "2010-01-01"))
    )
  )
  out <- lookup_registers(regs, "alfa")
  expect_identical(nrow(out), 2L)
  expect_identical(out$cd_cvm, c("10", "20"))
})

test_that("active registrations come first", {
  regs <- list(
    companhias = register(
      cnpj_cia = c("1", "2", "3"),
      denom_social = c("ALFA A", "ALFA B", "ALFA C"),
      dt_cancel = as.Date(c("2015-01-01", NA, NA))
    )
  )
  out <- lookup_registers(regs, "alfa")
  expect_identical(out$cnpj_cia, c("2", "3", "1"))
  expect_named(
    out,
    c(
      "cnpj_cia",
      "denom_social",
      "denom_comerc",
      "cd_cvm",
      "sit",
      "dt_reg",
      "dt_cancel",
      "table"
    )
  )
})

test_that("name must be a single non-empty string", {
  for (bad in list(NULL, NA_character_, "", "  ", c("a", "b"), 1)) {
    expect_error(cnpj_lookup(bad), class = "cvmdata_error_input")
  }
})

test_that("cnpj_lookup() searches the three cad registers", {
  skip_if_not_installed("httptest2")
  root <- local_prepare_cad_cache()
  local_prepare_cad_cache(
    "cad_estrangeiras_sample.csv",
    "cad_cia_estrang.csv",
    cache_root = root
  )
  local_prepare_cad_cache(
    "cad_incentivadas_sample.csv",
    "cad_cia_incent.csv",
    cache_root = root
  )
  tiete <- with_fixture_http(cnpj_lookup("tiete", source = "cvm"))
  # Two companies, each published once per market: two rows.
  expect_setequal(
    tiete$cnpj_cia,
    c("04.128.563/0001-10", "02.998.609/0001-27")
  )
  expect_identical(nrow(tiete), 2L)
  expect_identical(unique(tiete$table), "companhias")
  expect_s3_class(tiete$dt_reg, "Date")

  # Foreign register, plain `cnpj` column; one row the CVM repeats.
  aura <- with_fixture_http(cnpj_lookup("aura minerals", source = "cvm"))
  expect_identical(aura$cnpj_cia, "07.857.093/0001-14")
  expect_identical(aura$table, "estrangeiras")

  # Incentive register, by the trade name.
  caropa <- with_fixture_http(cnpj_lookup("fazenda caropa", source = "cvm"))
  expect_identical(caropa$cnpj_cia, "04.132.437/0001-30")
  expect_identical(caropa$table, "incentivadas")

  expect_message(
    none <- with_fixture_http(cnpj_lookup("zzz nada", source = "cvm")),
    class = "cvmdata_message_no_match"
  )
  expect_identical(nrow(none), 0L)
})

test_that("the cnpj error of cvm_fetch() points to cnpj_lookup()", {
  expect_error(
    cvm_fetch("cad", "companhias", cnpj = "petrobras", source = "cvm"),
    "cnpj_lookup",
    class = "cvmdata_error_input"
  )
})
