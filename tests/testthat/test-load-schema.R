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
      dataset = "x", table = "y",
      cvm_archive_url_pattern = "https://example.com/x.zip",
      cvm_file_url_pattern = "https://example.com/x.csv",
      cvm_file_pattern = "x.csv",
      encoding = "ISO-8859-1", delimiter = ";",
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
    dataset = "x", table = "y",
    cvm_archive_url_pattern = NULL,
    cvm_file_url_pattern = NULL,
    cvm_file_pattern = "x.csv",
    encoding = "ISO-8859-1", delimiter = ";",
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
    dataset = "fre", table = "administrador_PCD",
    cvm_archive_url_pattern = "https://example.com/x.zip",
    cvm_file_url_pattern = NULL,
    cvm_file_pattern = "x_{year}.csv",
    cvm_dictionary_url = NULL,
    meta_status = "missing",
    encoding = "ISO-8859-1", delimiter = ";",
    temporal_partitioning = "yearly", first_year = 2023L,
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
    dataset = "fre", table = "administrador_PCD",
    cvm_archive_url_pattern = "https://example.com/x.zip",
    cvm_file_url_pattern = NULL,
    cvm_file_pattern = "x_{year}.csv",
    cvm_dictionary_url = "https://example.com/meta.txt",
    meta_status = "missing",
    encoding = "ISO-8859-1", delimiter = ";",
    temporal_partitioning = "yearly", first_year = 2023L,
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
    dataset = "x", table = "y",
    cvm_archive_url_pattern = NULL,
    cvm_file_url_pattern = "https://example.com/x.csv",
    cvm_file_pattern = "x.csv",
    meta_status = "partial",
    encoding = "ISO-8859-1", delimiter = ";",
    temporal_partitioning = "none",
    expected_field_count = 1L,
    transformations = list()
  )
  expect_error(
    validate_schema(raw, "x", "y"),
    class = "cvmdata_error_internal"
  )
})

test_that("invalid temporal_partitioning is rejected", {
  raw <- list(
    dataset = "x", table = "y",
    cvm_archive_url_pattern = NULL,
    cvm_file_url_pattern = "https://example.com/x.csv",
    cvm_file_pattern = "x.csv",
    encoding = "ISO-8859-1", delimiter = ";",
    temporal_partitioning = "monthly",
    expected_field_count = 1L,
    transformations = list()
  )
  expect_error(
    validate_schema(raw, "x", "y"),
    class = "cvmdata_error_internal"
  )
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
