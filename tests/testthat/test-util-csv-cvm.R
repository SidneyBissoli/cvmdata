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

test_that("snapshot declares non-date `vencimento` => Date column", {
  # Snapshot declares `vencimento` (no dt_/data_ prefix) as date. The
  # canonical lookup must promote it over the name-based heuristic,
  # which would otherwise leave it to col_guess.
  fake_dict <- tibble::tibble(
    campo          = c("cnpj_cia", "vencimento", "outro"),
    campo_original = c("CNPJ_CIA", "Vencimento", "OUTRO"),
    descricao      = NA_character_,
    dominio        = NA_character_,
    tipo_dados     = c("varchar", "date", "varchar"),
    tamanho        = NA_integer_,
    precisao       = NA_integer_,
    scale          = NA_integer_
  )
  local_mocked_bindings(
    cvm_dictionary = function(dataset, table) fake_dict,
    .package = "cvmdata"
  )

  csv <- paste(
    "CNPJ_CIA;Vencimento;OUTRO",
    "00.000.000/0001-91;2024-12-31;text",
    sep = "\n"
  )
  path <- write_csv_iso(csv)
  schema <- list(
    dataset = "stub", table = "stub",
    delimiter = ";", encoding = "ISO-8859-1",
    expected_field_count = 3L, meta_status = "available"
  )
  df <- read_cvm_csv(path, schema, validate = "strict")
  expect_s3_class(df$vencimento, "Date")
})

test_that("snapshot declares dt_/data_ as non-date => not parsed as Date", {
  # Snapshot declares `dt_pseudo` as varchar despite the dt_ prefix.
  # The legacy heuristic would force col_date and fail to parse the
  # non-ISO content; the snapshot must take precedence and let col_guess
  # decide. Values are deliberately non-ISO so the test does not depend
  # on readr's guesser preferring character over Date.
  fake_dict <- tibble::tibble(
    campo          = c("cnpj_cia", "dt_pseudo"),
    campo_original = c("CNPJ_CIA", "DT_PSEUDO"),
    descricao      = NA_character_,
    dominio        = NA_character_,
    tipo_dados     = c("varchar", "varchar"),
    tamanho        = NA_integer_,
    precisao       = NA_integer_,
    scale          = NA_integer_
  )
  local_mocked_bindings(
    cvm_dictionary = function(dataset, table) fake_dict,
    .package = "cvmdata"
  )

  csv <- paste(
    "CNPJ_CIA;DT_PSEUDO",
    "00.000.000/0001-91;rotulo_nao_data",
    "11.111.111/0001-11;outro_rotulo",
    sep = "\n"
  )
  path <- write_csv_iso(csv)
  schema <- list(
    dataset = "stub", table = "stub",
    delimiter = ";", encoding = "ISO-8859-1",
    expected_field_count = 2L, meta_status = "available"
  )
  df <- read_cvm_csv(path, schema, validate = "strict")
  expect_type(df$dt_pseudo, "character")
  expect_identical(
    df$dt_pseudo,
    c("rotulo_nao_data", "outro_rotulo")
  )
})

test_that("meta_status:missing falls back to dt_/data_ heuristic", {
  csv <- paste(
    "CNPJ_Companhia;Data_Inventada;OUTRO",
    "00.000.000/0001-91;2024-01-15;text",
    sep = "\n"
  )
  path <- write_csv_iso(csv)
  schema <- list(
    dataset = "fre", table = "stub_missing",
    delimiter = ";", encoding = "ISO-8859-1",
    expected_field_count = 3L, meta_status = "missing",
    expected_field_names = c(
      "CNPJ_Companhia", "Data_Inventada", "OUTRO"
    )
  )
  df <- read_cvm_csv(path, schema, validate = "skip")
  expect_s3_class(df$data_inventada, "Date")
})

test_that("synthetic schema without dataset/table uses heuristic", {
  csv <- paste(
    "CNPJ_CIA;dt_synthetic;OUTRO",
    "00.000.000/0001-91;2024-01-15;text",
    sep = "\n"
  )
  path <- write_csv_iso(csv)
  df <- read_cvm_csv(path, minimal_schema(3L), validate = "skip")
  expect_s3_class(df$dt_synthetic, "Date")
})
