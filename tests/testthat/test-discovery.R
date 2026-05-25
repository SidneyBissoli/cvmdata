# Tests for cvm_datasets(), cvm_tables() and cvm_dictionary().

test_that("cvm_datasets returns the four covered datasets", {
  ds <- cvm_datasets()
  expect_setequal(ds, c("cad", "dfp", "fre", "itr"))
})

test_that("cvm_tables('fre') returns 36 tables", {
  expect_length(cvm_tables("fre"), 36L)
})

test_that("cvm_tables errors on non-string dataset arg", {
  expect_error(cvm_tables(123), class = "cvmdata_error_input")
  expect_error(cvm_tables(NULL), class = "cvmdata_error_input")
  expect_error(cvm_tables(""), class = "cvmdata_error_input")
  expect_error(cvm_tables(c("a", "b")), class = "cvmdata_error_input")
})

test_that("cvm_tables errors on unknown dataset", {
  expect_error(cvm_tables("not_a_real_dataset_xyz"),
               class = "cvmdata_error_input")
})

test_that("cvm_dictionary('dfp', 'bpa') returns parsed rows", {
  d <- cvm_dictionary("dfp", "bpa")
  expect_s3_class(d, "tbl_df")
  expect_named(
    d,
    c("campo", "campo_original", "descricao", "dominio", "tipo_dados",
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

test_that("cvm_codelist error message lists available codelist columns", {
  # cnpj_cia is in cad/companhias dictionary but is an identifier, so
  # the abort fires from the "is not a codelist" branch with the list
  # of codelist columns available for the table.
  expect_error(
    cvm_codelist("cad", "companhias", "cnpj_cia"),
    regexp = "is not a codelist"
  )
})

test_that("cvm_codelist 'unknown column' lists codelist columns", {
  # cad/companhias has codelist columns (sit, tp_merc, …); an unknown
  # column should abort with "Unknown column" plus the list of
  # codelist columns available.
  expect_error(
    cvm_codelist("cad", "companhias", "no_such_column_xyz"),
    regexp = "Unknown column"
  )
})

test_that("cvm_codelist 'is not a codelist' tolerates table with zero codes", {
  # fre/empregado_PCD has meta_status: missing — placeholder
  # dictionary rows exist but the table contributes zero rows to the
  # codelists snapshot. Asserts the "No codelist columns" branch.
  expect_error(
    cvm_codelist("fre", "empregado_PCD", "posicao"),
    regexp = "No codelist columns"
  )
})

test_that("cvm_codelist 'Unknown column' tolerates table with zero codes", {
  expect_error(
    cvm_codelist("fre", "empregado_PCD", "no_such_column_xyz"),
    regexp = "No codelist columns"
  )
})

# cvm_dictionary(group = ...) -------------------------------------------

test_that("cvm_dictionary accepts explicit group = 'companhias'", {
  d <- cvm_dictionary("dfp", "bpa", group = "companhias")
  expect_s3_class(d, "tbl_df")
  expect_gt(nrow(d), 0L)
  expect_named(
    d,
    c("campo", "campo_original", "descricao", "dominio", "tipo_dados",
      "tamanho", "precisao", "scale")
  )
})

test_that("cvm_dictionary with unknown group aborts cvmdata_error_input", {
  expect_error(
    cvm_dictionary("dfp", "bpa", group = "fundos-de-investimento"),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_dictionary rejects malformed group arg", {
  expect_error(
    cvm_dictionary("dfp", "bpa", group = ""),
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_dictionary("dfp", "bpa", group = c("a", "b")),
    class = "cvmdata_error_input"
  )
})

# cvm_codelist(group = ...) ---------------------------------------------

test_that("cvm_codelist accepts explicit group = 'companhias'", {
  cl <- cvm_codelist("cad", "companhias", "sit", group = "companhias")
  expect_s3_class(cl, "tbl_df")
  expect_named(cl, "value")
  expect_gte(nrow(cl), 2L)
})

test_that("cvm_codelist with unknown group aborts cvmdata_error_input", {
  expect_error(
    cvm_codelist("cad", "companhias", "sit",
                 group = "fundos-de-investimento"),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_codelist rejects malformed group arg", {
  expect_error(
    cvm_codelist("cad", "companhias", "sit", group = ""),
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_codelist("cad", "companhias", "sit", group = c("a", "b")),
    class = "cvmdata_error_input"
  )
})

# cvm_dataset_years() ----------------------------------------------------

test_that("cvm_dataset_years returns NA for non-yearly dataset", {
  # CAD is temporal_partitioning: none. The discovery helper must
  # gracefully return NA_integer_, not abort.
  expect_identical(cvm_dataset_years("cad"), NA_integer_)
})

test_that("cvm_dataset_years aborts when archive_url_pattern is NULL", {
  # Synthetic yearly schema missing the URL pattern.
  schema <- list(
    dataset = "synth",
    table = "x",
    temporal_partitioning = "yearly",
    cvm_archive_url_pattern = NULL
  )
  expect_error(
    cvm_dataset_years("synth", schema = schema),
    class = "cvmdata_error_internal"
  )
})

test_that("cvm_dataset_years aborts on HTTP failure for directory listing", {
  # Bypass the year-listing cache so the mock is exercised.
  rlang::env_unbind(
    cvmdata:::.year_listing_cache,
    nms = rlang::env_names(cvmdata:::.year_listing_cache)
  )
  mock <- function(req) stop("simulated DNS error")
  expect_error(
    httr2::with_mocked_responses(
      mock,
      cvm_dataset_years("dfp")
    ),
    class = "cvmdata_error_http"
  )
})

test_that("cvm_dataset_years aborts when the listing has no year matches", {
  rlang::env_unbind(
    cvmdata:::.year_listing_cache,
    nms = rlang::env_names(cvmdata:::.year_listing_cache)
  )
  mock <- function(req) {
    httr2::response(
      status_code = 200L,
      headers = list("Content-Type" = "text/html"),
      body = charToRaw("<html><body>no archives here</body></html>")
    )
  }
  expect_error(
    httr2::with_mocked_responses(
      mock,
      cvm_dataset_years("dfp")
    ),
    class = "cvmdata_error_http"
  )
})

test_that("cvm_dataset_years session cache short-circuits the second call", {
  rlang::env_unbind(
    cvmdata:::.year_listing_cache,
    nms = rlang::env_names(cvmdata:::.year_listing_cache)
  )
  calls <- 0L
  mock <- function(req) {
    calls <<- calls + 1L
    httr2::response(
      status_code = 200L,
      headers = list("Content-Type" = "text/html"),
      body = charToRaw(
        "<a href=\"dfp_cia_aberta_2024.zip\">2024</a>"
      )
    )
  }
  first <- httr2::with_mocked_responses(
    mock,
    cvm_dataset_years("dfp")
  )
  expect_identical(first, 2024L)
  expect_identical(calls, 1L)
  # Second call must NOT hit the mock — the listing cache returns the
  # memoized vector for the same directory URL.
  second <- cvm_dataset_years("dfp")
  expect_identical(second, 2024L)
  expect_identical(calls, 1L)
})
