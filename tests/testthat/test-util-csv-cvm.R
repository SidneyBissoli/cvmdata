# Tests for the CSV reader (R/util-csv-cvm.R), in particular
# .identifier_patterns coverage. These guard against the regression
# where suffixed identifier columns (CPF_Auditor, Codigo_CVM_Auditor)
# fell into readr::col_guess() and lost leading zeros.

write_csv_iso <- function(text) {
  path <- withr::local_tempfile(
    fileext = ".csv",
    .local_envir = parent.frame()
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
    campo = c("cnpj_cia", "vencimento", "outro"),
    campo_original = c("CNPJ_CIA", "Vencimento", "OUTRO"),
    descricao = NA_character_,
    dominio = NA_character_,
    tipo_dados = c("varchar", "date", "varchar"),
    tamanho = NA_integer_,
    precisao = NA_integer_,
    scale = NA_integer_
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
    dataset = "stub",
    table = "stub",
    delimiter = ";",
    encoding = "ISO-8859-1",
    expected_field_count = 3L,
    meta_status = "available"
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
    campo = c("cnpj_cia", "dt_pseudo"),
    campo_original = c("CNPJ_CIA", "DT_PSEUDO"),
    descricao = NA_character_,
    dominio = NA_character_,
    tipo_dados = c("varchar", "varchar"),
    tamanho = NA_integer_,
    precisao = NA_integer_,
    scale = NA_integer_
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
    dataset = "stub",
    table = "stub",
    delimiter = ";",
    encoding = "ISO-8859-1",
    expected_field_count = 2L,
    meta_status = "available"
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
    dataset = "fre",
    table = "stub_missing",
    delimiter = ";",
    encoding = "ISO-8859-1",
    expected_field_count = 3L,
    meta_status = "missing",
    expected_field_names = c(
      "CNPJ_Companhia",
      "Data_Inventada",
      "OUTRO"
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

test_that("a table with META takes its column names from the dictionary", {
  # Until 2026-10-25 only the 8 META-less tables had their names checked.
  schema <- load_schema("dfp", "bpa")
  expect_null(schema$expected_field_names)
  expect_setequal(
    expected_field_names(schema),
    c(
      "CD_CONTA",
      "CD_CVM",
      "CNPJ_CIA",
      "DENOM_CIA",
      "DS_CONTA",
      "DT_FIM_EXERC",
      "DT_REFER",
      "ESCALA_MOEDA",
      "GRUPO_DFP",
      "MOEDA",
      "ORDEM_EXERC",
      "ST_CONTA_FIXA",
      "VERSAO",
      "VL_CONTA"
    )
  )
  # a META-less table keeps the names of its YAML
  fre <- load_schema("fre", "empregado_PCD")
  expect_identical(
    expected_field_names(fre),
    as.character(fre$expected_field_names)
  )
  # a synthetic schema names no table: nothing to compare
  expect_null(expected_field_names(minimal_schema(3L)))
})

test_that("a column renamed at the same count is refused, in any order", {
  schema <- load_schema("dfp", "bpa")
  names <- expected_field_names(schema)
  row <- paste(rep("", length(names)), collapse = ";")
  # the dictionary's names in another order: accepted
  ok <- write_csv_iso(paste(paste(rev(names), collapse = ";"), row, sep = "\n"))
  expect_no_error(read_cvm_csv(ok, schema, validate = "strict"))
  # one renamed, same count: refused in strict, warned in warn
  renamed <- sub("VL_CONTA", "VALOR_CONTA", names, fixed = TRUE)
  bad <- write_csv_iso(paste(paste(renamed, collapse = ";"), row, sep = "\n"))
  expect_error(
    read_cvm_csv(bad, schema, validate = "strict"),
    class = "cvmdata_error_parse"
  )
  err <- tryCatch(
    read_cvm_csv(bad, schema, validate = "strict"),
    cvmdata_error_parse = conditionMessage
  )
  expect_match(err, "vl_conta", fixed = TRUE)
  expect_match(err, "valor_conta", fixed = TRUE)
  expect_warning(
    read_cvm_csv(bad, schema, validate = "warn"),
    class = "cvmdata_warn_validation"
  )
  expect_no_warning(read_cvm_csv(bad, schema, validate = "skip"))
})

test_that("a quote in the text is a character, not a field delimiter", {
  # FRE 2024 (2026-10-25): a text starting with `"` swallowed the next
  # lines into one field; five tables lost 2,803 rows, two silently.
  csv <- paste(
    "ID_X;TEXTO;OUTRO",
    "1;\"Banco X\" S.A. assina o contrato;a",
    "2;texto comum;b",
    "3;outro \"trecho;c",
    "4;fim;d",
    sep = "\n"
  )
  df <- read_cvm_csv(write_csv_iso(csv), minimal_schema(3L), "strict")
  expect_identical(nrow(df), 4L)
  expect_identical(df$id_x, c("1", "2", "3", "4"))
  expect_identical(df$texto[1], "\"Banco X\" S.A. assina o contrato")
  expect_identical(df$outro, c("a", "b", "c", "d"))
})

test_that("a column guessed over every row keeps a late value", {
  # readr guessed over 1,000 rows: a column empty there became logical
  # and a later value NA (fre/transacao_parte_relacionada, 2010-2026)
  n <- 1500L
  vals <- c(rep("", n - 1L), "42.5")
  csv <- paste(c("A;B", paste(seq_len(n), vals, sep = ";")), collapse = "\n")
  df <- expect_no_warning(
    read_cvm_csv(write_csv_iso(csv), minimal_schema(2L), "strict")
  )
  expect_identical(nrow(df), n)
  expect_identical(df$b[n], 42.5)
})

test_that("a text column of the dictionary is read as character", {
  fake_dict <- tibble::tibble(
    campo = c("documento", "telefone", "valor"),
    campo_original = c("DOCUMENTO", "TELEFONE", "VALOR"),
    descricao = NA_character_,
    dominio = NA_character_,
    tipo_dados = c("varchar", "char", "decimal"),
    tamanho = NA_integer_,
    precisao = NA_integer_,
    scale = NA_integer_
  )
  local_mocked_bindings(
    cvm_dictionary = function(dataset, table) fake_dict,
    .package = "cvmdata"
  )
  csv <- paste(
    "DOCUMENTO;TELEFONE;VALOR",
    ";0113333444;1.5",
    "11.442.516/0001-02;;2",
    sep = "\n"
  )
  schema <- list(
    dataset = "stub",
    table = "stub",
    delimiter = ";",
    encoding = "ISO-8859-1",
    expected_field_count = 3L,
    meta_status = "available"
  )
  df <- read_cvm_csv(write_csv_iso(csv), schema, validate = "strict")
  expect_type(df$documento, "character")
  expect_identical(df$documento[2], "11.442.516/0001-02")
  expect_identical(df$telefone[1], "0113333444")
  expect_type(df$valor, "double")
})
