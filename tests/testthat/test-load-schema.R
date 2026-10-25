# Tests for load_schema() and its validation invariants.

test_that("load_schema('cad', 'companhias') returns a cvm_table_schema", {
  schema <- load_schema("cad", "companhias")
  expect_s3_class(schema, "cvm_table_schema")
  expect_identical(schema$dataset, "cad")
  expect_identical(schema$table, "companhias")
  expect_identical(schema$temporal_partitioning, "none")
  expect_identical(schema$encoding, "ISO-8859-1")
  expect_identical(schema$delimiter, ";")
  expect_identical(schema$expected_field_count, 47L)
  expect_true(nzchar(schema$cvm_file_url_pattern))
  expect_true(is.null(schema$cvm_archive_url_pattern))
})

test_that("load_schema errors on unknown dataset/table", {
  expect_error(
    load_schema("does_not_exist", "companhias"),
    class = "cvmdata_error_input"
  )
  expect_error(
    load_schema("cad", "does_not_exist"),
    class = "cvmdata_error_input"
  )
})

test_that("schema with both URLs non-null is rejected", {
  yaml_path <- withr::local_tempfile(fileext = ".yaml")
  yaml::write_yaml(
    list(
      dataset = "x",
      table = "y",
      cvm_archive_url_pattern = "https://example.com/x.zip",
      cvm_file_url_pattern = "https://example.com/x.csv",
      cvm_file_pattern = "x.csv",
      encoding = "ISO-8859-1",
      delimiter = ";",
      temporal_partitioning = "none",
      expected_field_count = 1L,
      transformations = list()
    ),
    yaml_path
  )
  raw <- yaml::read_yaml(yaml_path)
  expect_error(
    validate_schema(raw, "x", "y"),
    class = "cvmdata_error_internal"
  )
})

test_that("schema with both URLs null is rejected", {
  raw <- list(
    dataset = "x",
    table = "y",
    cvm_archive_url_pattern = NULL,
    cvm_file_url_pattern = NULL,
    cvm_file_pattern = "x.csv",
    encoding = "ISO-8859-1",
    delimiter = ";",
    temporal_partitioning = "none",
    expected_field_count = 1L,
    transformations = list()
  )
  expect_error(
    validate_schema(raw, "x", "y"),
    class = "cvmdata_error_internal"
  )
})

test_that("meta_status: missing without expected_field_names is rejected", {
  raw <- list(
    dataset = "fre",
    table = "administrador_PCD",
    cvm_archive_url_pattern = "https://example.com/x.zip",
    cvm_file_url_pattern = NULL,
    cvm_file_pattern = "x_{year}.csv",
    cvm_dictionary_url = NULL,
    meta_status = "missing",
    encoding = "ISO-8859-1",
    delimiter = ";",
    temporal_partitioning = "yearly",
    first_year = 2023L,
    expected_field_count = 10L,
    transformations = list()
  )
  expect_error(
    validate_schema(raw, "fre", "administrador_PCD"),
    class = "cvmdata_error_internal"
  )
})

test_that("meta_status: missing with cvm_dictionary_url is rejected", {
  raw <- list(
    dataset = "fre",
    table = "administrador_PCD",
    cvm_archive_url_pattern = "https://example.com/x.zip",
    cvm_file_url_pattern = NULL,
    cvm_file_pattern = "x_{year}.csv",
    cvm_dictionary_url = "https://example.com/meta.txt",
    meta_status = "missing",
    encoding = "ISO-8859-1",
    delimiter = ";",
    temporal_partitioning = "yearly",
    first_year = 2023L,
    expected_field_count = 10L,
    expected_field_names = c("a", "b"),
    transformations = list()
  )
  expect_error(
    validate_schema(raw, "fre", "administrador_PCD"),
    class = "cvmdata_error_internal"
  )
})

test_that("invalid meta_status value is rejected", {
  raw <- list(
    dataset = "x",
    table = "y",
    cvm_archive_url_pattern = NULL,
    cvm_file_url_pattern = "https://example.com/x.csv",
    cvm_file_pattern = "x.csv",
    meta_status = "partial",
    encoding = "ISO-8859-1",
    delimiter = ";",
    temporal_partitioning = "none",
    expected_field_count = 1L,
    transformations = list()
  )
  expect_error(
    validate_schema(raw, "x", "y"),
    class = "cvmdata_error_internal"
  )
})

test_that("empty_from must be an integer year after first_year", {
  raw <- list(
    dataset = "x",
    table = "y",
    cvm_archive_url_pattern = NULL,
    cvm_file_url_pattern = "https://example.com/x_{year}.csv",
    cvm_file_pattern = "x_{year}.csv",
    encoding = "ISO-8859-1",
    delimiter = ";",
    temporal_partitioning = "yearly",
    first_year = 2010L,
    expected_field_count = 1L,
    transformations = list()
  )
  ok <- raw
  ok$empty_from <- 2024L
  ok$empty_reason <- "the block was revoked"
  expect_no_error(validate_schema(ok, "x", "y"))

  before_first <- raw
  before_first$empty_from <- 2010L
  expect_error(
    validate_schema(before_first, "x", "y"),
    regexp = "empty_from",
    class = "cvmdata_error_internal"
  )

  not_a_year <- raw
  not_a_year$empty_from <- "2024"
  expect_error(
    validate_schema(not_a_year, "x", "y"),
    regexp = "empty_from",
    class = "cvmdata_error_internal"
  )

  bad_reason <- ok
  bad_reason$empty_reason <- c("two", "strings")
  expect_error(
    validate_schema(bad_reason, "x", "y"),
    regexp = "empty_reason",
    class = "cvmdata_error_internal"
  )
})

test_that("fca/departamento_acionistas declares empty_from 2024", {
  schema <- load_schema("fca", "departamento_acionistas")
  expect_identical(as.integer(schema$empty_from), 2024L)
  expect_match(schema$empty_reason, "Resolucao CVM 59/2021")
})

test_that("invalid temporal_partitioning is rejected", {
  raw <- list(
    dataset = "x",
    table = "y",
    cvm_archive_url_pattern = NULL,
    cvm_file_url_pattern = "https://example.com/x.csv",
    cvm_file_pattern = "x.csv",
    encoding = "ISO-8859-1",
    delimiter = ";",
    temporal_partitioning = "monthly",
    expected_field_count = 1L,
    transformations = list()
  )
  expect_error(
    validate_schema(raw, "x", "y"),
    class = "cvmdata_error_internal"
  )
})

# load_schema(group = ...) ----------------------------------------------

test_that("load_schema loads with explicit group = 'companhias'", {
  schema <- load_schema("cad", "companhias", group = "companhias")
  expect_s3_class(schema, "cvm_table_schema")
  expect_identical(schema$dataset, "cad")
  expect_identical(schema$table, "companhias")
})

test_that("load_schema with unknown explicit group aborts", {
  expect_error(
    load_schema("cad", "companhias", group = "fundos-de-investimento"),
    class = "cvmdata_error_input"
  )
})

test_that("load_schema rejects malformed group arg", {
  expect_error(
    load_schema("cad", "companhias", group = ""),
    class = "cvmdata_error_input"
  )
  expect_error(
    load_schema("cad", "companhias", group = c("a", "b")),
    class = "cvmdata_error_input"
  )
  expect_error(
    load_schema("cad", "companhias", group = 42),
    class = "cvmdata_error_input"
  )
})

test_that("load_schema aborts cvmdata_error_input_ambiguous", {
  fixture_root <- testthat::test_path("fixtures", "schemas-ambiguous")
  withr::local_options(cvmdata.schema_root = fixture_root)
  # The schema_tree cache is keyed by the resolved root path so the
  # fixture root gets a fresh entry; no need to clear globally.
  err <- expect_error(
    load_schema("fakedata", "faketable"),
    class = "cvmdata_error_input_ambiguous"
  )
  # Ambiguity must also inherit from cvmdata_error_input.
  expect_s3_class(err, "cvmdata_error_input")
})

test_that("load_schema with explicit group bypasses ambiguity", {
  fixture_root <- testthat::test_path("fixtures", "schemas-ambiguous")
  withr::local_options(cvmdata.schema_root = fixture_root)
  schema <- load_schema("fakedata", "faketable", group = "g1")
  expect_s3_class(schema, "cvm_table_schema")
  expect_identical(schema$dataset, "fakedata")
  expect_match(schema$cvm_file_url_pattern, "g1")
})

test_that("load_schema reads UTF-8 comments under LC_CTYPE=C", {
  # Regression for the bug where yaml::read_yaml(path) delegated to an
  # internal readLines() whose encoding follows the active locale.
  # Under LC_CTYPE="C", multibyte UTF-8 bytes in schema comments
  # ("Demonstração", "Exercício") were rejected as invalid input and
  # the file silently truncated, leaving validate_url_topology() to
  # abort with "Got archive=, file=" — both URLs empty even though the
  # YAML on disk declared cvm_archive_url_pattern. The fix in
  # read_schema_yaml() opens file(encoding = "UTF-8") explicitly.
  withr::local_locale(c(LC_CTYPE = "C"))
  skip_if(
    !identical(Sys.getlocale("LC_CTYPE"), "C"),
    "LC_CTYPE=C not honoured on this platform"
  )

  schema <- load_schema("dfp", "dre")
  expect_s3_class(schema, "cvm_table_schema")
  expect_match(schema$cvm_archive_url_pattern, "^https://")
  expect_named(schema$cvm_file_pattern_variants, c("ind", "con"))
})
