# End-to-end tests for issuer_fetch() against the v0.2 VLMO dataset
# (valores mobiliarios negociados e detidos por insiders). Mocks the
# HTTP layer with httr2::with_mocked_responses + a local fixture ZIP,
# matching the pattern used for CGVN/DFP/ITR/FRE.
#
# Table naming: the CVM detail CSV is "...con..." (consolidado), but
# "con" is a reserved device name on Windows/OneDrive, so the package
# table is `consolidado`. The schema's cvm_file_pattern still points at
# the real file vlmo_cia_aberta_con_{year}.csv.

# Helpers ----------------------------------------------------------------

local_prepare_vlmo_cache <- function(envir = parent.frame()) {
  cache_root <- withr::local_tempdir(.local_envir = envir)
  withr::local_options(
    cvmdata.cache_dir = cache_root,
    .local_envir = envir
  )
  raw_dir <- file.path(cache_root, "raw", "companhias", "vlmo", "2024")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  file.copy(
    test_path("fixtures", "vlmo_cia_aberta_2024.zip"),
    file.path(raw_dir, "vlmo_cia_aberta_2024.zip")
  )
  saveRDS(
    list(
      etag = "\"fixture-etag\"",
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = "2026-05-19T00:00:00.000Z"
    ),
    file.path(raw_dir, "vlmo_cia_aberta_2024.zip.etag.rds")
  )
  cache_root
}

fresh_head_response <- function() {
  httr2::response(
    status_code = 200L,
    headers = list(
      "ETag" = "\"fixture-etag\"",
      "Last-Modified" = "Mon, 19 May 2026 00:00:00 GMT"
    )
  )
}

# Tracer -------------------------------------------------------------

test_that("issuer_fetch VLMO submissao tracer returns cvm_tbl", {
  skip_if_not_installed("httptest2")
  local_prepare_vlmo_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("vlmo", "submissao",
                 year = 2024L, source = "cvm")
  )

  expect_s3_class(result, "cvm_tbl")
  expect_s3_class(result, "tbl_df")
  expect_identical(attr(result, "source"), "cvm")
  expect_identical(attr(result, "group"), "companhias")
  expect_identical(attr(result, "dataset"), "vlmo")
  expect_identical(attr(result, "table"), "submissao")
  expect_true(nrow(result) > 0L)
  # FRE-detail-like convention with Codigo_CVM in the header.
  expect_true(all(c("cnpj_companhia", "data_referencia", "versao",
                    "codigo_cvm") %in% names(result)))
  expect_identical(ncol(result), 12L)
  expect_type(result$cnpj_companhia, "character")
  expect_type(result$codigo_cvm, "character")
  expect_s3_class(result$data_referencia, "Date")
})

test_that("issuer_fetch VLMO consolidado tracer returns cvm_tbl", {
  skip_if_not_installed("httptest2")
  local_prepare_vlmo_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("vlmo", "consolidado",
                 year = 2024L, source = "cvm")
  )

  expect_s3_class(result, "cvm_tbl")
  expect_identical(attr(result, "table"), "consolidado")
  expect_true(nrow(result) > 0L)
  expect_identical(ncol(result), 17L)
  expect_true(all(c("cnpj_companhia", "data_referencia", "versao",
                    "tipo_cargo", "data_movimentacao", "quantidade",
                    "preco_unitario", "volume") %in% names(result)))
  # consolidado does not carry codigo_cvm natively (CVM design).
  expect_false("codigo_cvm" %in% names(result))
  expect_s3_class(result$data_movimentacao, "Date")
  expect_true(is.numeric(result$quantidade))
  expect_true(is.numeric(result$preco_unitario))
  expect_true(is.numeric(result$volume))
})

# Filtering by issuer -------------------------------------------------

test_that("issuer_fetch VLMO filters by CNPJ via cnpj_companhia", {
  skip_if_not_installed("httptest2")
  local_prepare_vlmo_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("vlmo", "consolidado",
                 issuer = "00.000.000/0001-91",
                 year = 2024L, source = "cvm")
  )
  expect_true(nrow(result) > 0L)
  expect_true(all(result$cnpj_companhia == "00.000.000/0001-91"))
})

test_that("issuer_fetch VLMO resolves CD_CVM via submissao for consolidado", {
  # consolidado does not carry codigo_cvm; the lookup must read
  # vlmo/submissao for the same year and map CD_CVM -> CNPJ. This
  # exercises the cdcvm_col() generalization shipped in Sessao 10.
  skip_if_not_installed("httptest2")
  local_prepare_vlmo_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("vlmo", "consolidado",
                 issuer = "001023",
                 year = 2024L, source = "cvm")
  )
  expect_true(nrow(result) > 0L)
  expect_true(all(result$cnpj_companhia == "00.000.000/0001-91"))
})

test_that("VLMO CD_CVM resolution accepts unpadded input", {
  skip_if_not_installed("httptest2")
  local_prepare_vlmo_cache()

  out_padded <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("vlmo", "consolidado",
                 issuer = "001023", year = 2024L, source = "cvm")
  )
  out_unpadded <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("vlmo", "consolidado",
                 issuer = "1023", year = 2024L, source = "cvm")
  )
  expect_identical(nrow(out_padded), nrow(out_unpadded))
})

# No dedup by version (event-per-row table) ---------------------------

test_that("vlmo/consolidado declares no keep_latest_version", {
  # consolidado is event-per-row: distinct movements filed under
  # different VERSAO for the same (cnpj, data_referencia) must all
  # survive. The schema declares no transformation, so
  # apply_schema_transformations is a no-op. Contrast with the
  # submissao schema, which keeps only the highest version.
  schema <- load_schema("vlmo", "consolidado")
  expect_length(schema$transformations, 0L)

  df <- data.frame(
    cnpj_companhia = rep("00.000.000/0001-91", 3L),
    data_referencia = as.Date(rep("2024-03-31", 3L)),
    versao = c(1L, 2L, 3L),
    tipo_movimentacao = c("Compra", "Venda", "Compra à vista"),
    quantidade = c(100, 200, 300),
    stringsAsFactors = FALSE
  )
  out <- cvmdata:::apply_schema_transformations(df, schema)
  expect_equal(nrow(out), 3L)
  expect_setequal(out$versao, c(1L, 2L, 3L))

  # Sanity: the submissao schema WOULD collapse the same rows to the
  # latest version, proving the difference is the missing transform.
  sub_schema <- load_schema("vlmo", "submissao")
  collapsed <- cvmdata:::apply_schema_transformations(df, sub_schema)
  expect_equal(nrow(collapsed), 1L)
  expect_identical(collapsed$versao, 3L)
})

# Schema + discovery -------------------------------------------------

test_that("load_schema accepts VLMO YAMLs", {
  sub <- load_schema("vlmo", "submissao")
  expect_s3_class(sub, "cvm_table_schema")
  expect_identical(sub$temporal_partitioning, "yearly")
  expect_equal(sub$first_year, 2018)
  expect_equal(sub$expected_field_count, 12)
  expect_identical(sub$cvm_file_pattern, "vlmo_cia_aberta_{year}.csv")
  expect_true(any(vapply(
    sub$transformations,
    function(t) identical(t$action, "keep_latest_version"),
    logical(1L)
  )))

  con <- load_schema("vlmo", "consolidado")
  expect_equal(con$expected_field_count, 17)
  # CVM file is named "...con..."; package table is "consolidado".
  expect_identical(
    con$cvm_file_pattern, "vlmo_cia_aberta_con_{year}.csv"
  )
  expect_length(con$transformations, 0L)
})

test_that("cvm_datasets includes vlmo", {
  expect_true("vlmo" %in% cvm_datasets())
  expect_true("vlmo" %in% cvm_datasets(group = "companhias"))
})

test_that("cvm_tables('vlmo') lists submissao + consolidado", {
  expect_setequal(cvm_tables("vlmo"), c("submissao", "consolidado"))
})

test_that("report_type aborts for VLMO tables without variants", {
  skip_if_not_installed("httptest2")
  local_prepare_vlmo_cache()
  expect_error(
    httr2::with_mocked_responses(
      function(req) fresh_head_response(),
      issuer_fetch("vlmo", "consolidado",
                   year = 2024L, source = "cvm", report_type = "ind")
    ),
    class = "cvmdata_error_input"
  )
})

# Dictionary + codelist (snapshot-dependent) --------------------------
# These require `data-raw/build-dictionary-snapshot.R --write` and
# `build-codelists-snapshot.R --write` to have been re-run with the
# VLMO schemas in place.

test_that("cvm_dictionary('vlmo', 'submissao') returns 12 rows", {
  dict <- cvm_dictionary("vlmo", "submissao")
  expect_s3_class(dict, "tbl_df")
  expect_equal(nrow(dict), 12L)
  expect_true("cnpj_companhia" %in% dict$campo)
})

test_that("cvm_dictionary('vlmo', 'consolidado') returns 17 rows", {
  dict <- cvm_dictionary("vlmo", "consolidado")
  expect_equal(nrow(dict), 17L)
  expect_true("data_movimentacao" %in% dict$campo)
})

test_that("cvm_codelist for VLMO tipo_cargo lists the 5 categories", {
  cl <- cvm_codelist("vlmo", "consolidado", "tipo_cargo")
  # Empirical verification §12.2: 5 valid categories. Accents come
  # straight from CVM; expect_setequal tolerates ordering.
  expect_setequal(
    cl$value,
    c("Conselho de Administração ou Vinculado",
      "Conselho Fiscal ou Vinculado",
      "Controlador ou Vinculado",
      "Diretor ou Vinculado",
      "Órgão Estatutário ou Vinculado")
  )
})
