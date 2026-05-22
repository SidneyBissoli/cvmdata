# Tests for the CSV reader (R/util-csv-cvm.R), in particular
# .identifier_patterns coverage. These guard against the regression
# where suffixed identifier columns (CPF_Auditor, Codigo_CVM_Auditor)
# fell into readr::col_guess() and lost leading zeros.

write_csv_iso <- function(text) {
  path <- withr::local_tempfile(
    fileext = ".csv", .local_envir = parent.frame()
  )
  writeBin(charToRaw(text), path)
  path
}

minimal_schema <- function(field_count) {
  list(
    dataset = "test",
    table = "test",
    delimiter = ";",
    encoding = "ISO-8859-1",
    expected_field_count = field_count
  )
}

test_that("CPF_Auditor with leading zeros is read as character", {
  csv <- paste(
    "CNPJ_Companhia;CPF_Auditor;Nome",
    "00.000.000/0001-91;01234567890;ALPHA",
    "11.111.111/0001-11;00098765432;BETA",
    sep = "\n"
  )
  path <- write_csv_iso(csv)
  df <- read_cvm_csv(path, minimal_schema(3L), validate = "strict")
  expect_type(df$cpf_auditor, "character")
  expect_identical(df$cpf_auditor, c("01234567890", "00098765432"))
})

test_that("Codigo_CVM_Auditor with leading zeros is read as character", {
  csv <- paste(
    "CNPJ_Companhia;Codigo_CVM_Auditor;Nome",
    "00.000.000/0001-91;000418;ALPHA",
    "11.111.111/0001-11;001023;BETA",
    sep = "\n"
  )
  path <- write_csv_iso(csv)
  df <- read_cvm_csv(path, minimal_schema(3L), validate = "strict")
  expect_type(df$codigo_cvm_auditor, "character")
  expect_identical(df$codigo_cvm_auditor, c("000418", "001023"))
})

test_that("FRE/auditor fixture: cpf/codigo_cvm columns are character", {
  zip_path <- test_path("fixtures", "fre_cia_aberta_2024.zip")
  stage <- withr::local_tempdir()
  utils::unzip(zip_path, exdir = stage)
  csv_path <- file.path(stage, "fre_cia_aberta_auditor_2024.csv")
  expect_true(file.exists(csv_path))

  schema <- load_schema("fre", "auditor")
  df <- read_cvm_csv(csv_path, schema, validate = "skip")

  expect_true("cpf_auditor" %in% names(df))
  expect_true("codigo_cvm_auditor" %in% names(df))
  expect_type(df$cpf_auditor, "character")
  expect_type(df$codigo_cvm_auditor, "character")
  expect_type(df$cnpj_auditor, "character")
})
