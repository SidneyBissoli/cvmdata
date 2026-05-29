# End-to-end tests for issuer_fetch() against the v0.2 CGVN dataset
# (codigo brasileiro de governanca corporativa). Mocks the HTTP layer
# with httr2::with_mocked_responses + a local fixture ZIP, matching
# the pattern used for DFP/ITR/FRE in test-issuer-fetch-yearly.R.

# Helpers ----------------------------------------------------------------

local_prepare_cgvn_cache <- function(envir = parent.frame()) {
  cache_root <- withr::local_tempdir(.local_envir = envir)
  withr::local_options(
    cvmdata.cache_dir = cache_root,
    .local_envir = envir
  )
  raw_dir <- file.path(cache_root, "raw", "companhias", "cgvn", "2024")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  file.copy(
    test_path("fixtures", "cgvn_cia_aberta_2024.zip"),
    file.path(raw_dir, "cgvn_cia_aberta_2024.zip")
  )
  saveRDS(
    list(
      etag = "\"fixture-etag\"",
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = "2026-05-19T00:00:00.000Z"
    ),
    file.path(raw_dir, "cgvn_cia_aberta_2024.zip.etag.rds")
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

test_that("issuer_fetch CGVN submissao tracer returns cvm_tbl", {
  skip_if_not_installed("httptest2")
  local_prepare_cgvn_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("cgvn", "submissao",
                 year = 2024L, source = "cvm")
  )

  expect_s3_class(result, "cvm_tbl")
  expect_s3_class(result, "tbl_df")
  expect_identical(attr(result, "source"), "cvm")
  expect_identical(attr(result, "group"), "companhias")
  expect_identical(attr(result, "dataset"), "cgvn")
  expect_identical(attr(result, "table"), "submissao")
  expect_true(nrow(result) > 0L)
  # FRE-detail convention: cnpj_companhia / data_referencia.
  expect_true(all(c("cnpj_companhia", "data_referencia", "versao",
                    "codigo_cvm") %in% names(result)))
  expect_type(result$cnpj_companhia, "character")
  expect_type(result$codigo_cvm, "character")
  expect_s3_class(result$data_referencia, "Date")
})

test_that("issuer_fetch CGVN praticas tracer returns cvm_tbl", {
  skip_if_not_installed("httptest2")
  local_prepare_cgvn_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("cgvn", "praticas",
                 year = 2024L, source = "cvm")
  )

  expect_s3_class(result, "cvm_tbl")
  expect_identical(attr(result, "table"), "praticas")
  expect_true(nrow(result) > 0L)
  expect_true(all(c("cnpj_companhia", "data_referencia", "versao",
                    "id_item", "pratica_adotada") %in% names(result)))
  # praticas does not carry codigo_cvm natively (CGVN design).
  expect_false("codigo_cvm" %in% names(result))
  # id_item is the per-practice identifier; must be character to
  # preserve the canonical "N.N.N" formatting.
  expect_type(result$id_item, "character")
})

# Filtering by issuer -------------------------------------------------

test_that("issuer_fetch CGVN filters by CNPJ via cnpj_companhia", {
  skip_if_not_installed("httptest2")
  local_prepare_cgvn_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("cgvn", "praticas",
                 issuer = "00.000.000/0001-91",
                 year = 2024L, source = "cvm")
  )
  expect_true(nrow(result) > 0L)
  expect_true(all(result$cnpj_companhia == "00.000.000/0001-91"))
})

test_that("issuer_fetch CGVN resolves CD_CVM via submissao for praticas", {
  # praticas does not carry codigo_cvm; the lookup must read
  # cgvn/submissao for the same year and map CD_CVM -> CNPJ. CGVN
  # publishes Codigo_CVM unpadded ("1023"), so the resolver exercises
  # both ends of the formatC zero-padding path.
  skip_if_not_installed("httptest2")
  local_prepare_cgvn_cache()

  result <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("cgvn", "praticas",
                 issuer = "001023",
                 year = 2024L, source = "cvm")
  )
  expect_true(nrow(result) > 0L)
  expect_true(all(result$cnpj_companhia == "00.000.000/0001-91"))
})

test_that("CGVN CD_CVM resolution accepts unpadded input", {
  skip_if_not_installed("httptest2")
  local_prepare_cgvn_cache()

  out_padded <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("cgvn", "praticas",
                 issuer = "001023", year = 2024L, source = "cvm")
  )
  out_unpadded <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch("cgvn", "praticas",
                 issuer = "1023", year = 2024L, source = "cvm")
  )
  expect_identical(nrow(out_padded), nrow(out_unpadded))
})

# Schema + discovery -------------------------------------------------

test_that("load_schema accepts CGVN YAMLs", {
  sub <- load_schema("cgvn", "submissao")
  expect_s3_class(sub, "cvm_table_schema")
  expect_identical(sub$temporal_partitioning, "yearly")
  expect_equal(sub$first_year, 2021)
  expect_equal(sub$expected_field_count, 12)
  expect_identical(sub$cvm_file_pattern, "cgvn_cia_aberta_{year}.csv")

  prat <- load_schema("cgvn", "praticas")
  expect_equal(prat$expected_field_count, 11)
  expect_identical(
    prat$cvm_file_pattern, "cgvn_cia_aberta_praticas_{year}.csv"
  )
  # keep_latest_version with extra id_item key.
  txs <- prat$transformations
  expect_true(any(vapply(
    txs, function(t) identical(t$action, "keep_latest_version"),
    logical(1L)
  )))
  klv <- Filter(
    function(t) identical(t$action, "keep_latest_version"), txs
  )[[1L]]
  expect_identical(klv$keys, "id_item")
})

test_that("cvm_datasets includes cgvn", {
  expect_true("cgvn" %in% cvm_datasets())
  expect_true("cgvn" %in% cvm_datasets(group = "companhias"))
})

test_that("cvm_tables('cgvn') lists submissao + praticas", {
  expect_setequal(cvm_tables("cgvn"), c("submissao", "praticas"))
})

# keep_latest_version with extra keys --------------------------------

test_that("keep_latest_version composes (cnpj, date, id_item) for CGVN", {
  # Synthetic: id_item 1.1.1 has a revision (versao 1 + 2), id_items
  # 2.2.2 and 3.3.3 only filed versao 1. Without the extra key the
  # group-max-versao mask drops every versao=1 row — including the
  # un-revised items — collapsing the four rows to one and silently
  # losing two distinct practices. With keys=id_item, each item keeps
  # its own latest, and all three survive.
  df <- data.frame(
    cnpj_companhia = rep("00.000.000/0001-91", 4L),
    data_referencia = as.Date(rep("2024-12-31", 4L)),
    versao = c(1L, 2L, 1L, 1L),
    id_item = c("1.1.1", "1.1.1", "2.2.2", "3.3.3"),
    pratica_adotada = c("Sim", "Sim", "Nao", "Parcialmente"),
    stringsAsFactors = FALSE
  )
  schema <- list(dataset = "cgvn", table = "praticas")

  out_no_key <- cvmdata:::tx_keep_latest_version(
    df, list(action = "keep_latest_version"), schema
  )
  expect_equal(nrow(out_no_key), 1L)
  expect_identical(out_no_key$id_item, "1.1.1")

  out_with_key <- cvmdata:::tx_keep_latest_version(
    df,
    list(action = "keep_latest_version", keys = "id_item"),
    schema
  )
  expect_equal(nrow(out_with_key), 3L)
  expect_setequal(out_with_key$id_item, c("1.1.1", "2.2.2", "3.3.3"))
  # 1.1.1 keeps versao 2; 2.2.2 and 3.3.3 keep their lone versao 1.
  out_with_key <- out_with_key[order(out_with_key$id_item), ]
  expect_identical(out_with_key$versao, c(2L, 1L, 1L))
})

test_that("keep_latest_version aborts on missing extra key", {
  df <- data.frame(
    cnpj_companhia = "00.000.000/0001-91",
    data_referencia = as.Date("2024-12-31"),
    versao = 1L,
    stringsAsFactors = FALSE
  )
  schema <- list(dataset = "cgvn", table = "praticas")
  expect_error(
    cvmdata:::tx_keep_latest_version(
      df,
      list(action = "keep_latest_version", keys = "id_item"),
      schema
    ),
    class = "cvmdata_error_internal"
  )
})

# identifier_columns helper -------------------------------------------

test_that("identifier_columns classifies prefix + exact-match names", {
  positives <- c(
    "cnpj_cia", "cnpj_companhia", "cnpj_escriturador",
    "cpf_auditor", "cpf_responsavel_tecnico",
    "codigo_cvm", "codigo_cvm_auditor", "codigo_negociacao",
    "cd_cvm", "cep",
    "ddi_telefone", "ddd_telefone",
    "id_documento", "id_item", "id_doc",
    "protocolo_entrega",
    "caixa_postal", "tel", "versao",
    # case insensitivity
    "CNPJ_CIA", "Codigo_CVM"
  )
  negatives <- c(
    "denom_cia", "nome_companhia", "categoria",
    "vl_conta", "ordem_exerc",
    "telefone",          # not exact-match `tel`; not in v0.1/v0.2 schemas
    "data_referencia", "dt_refer",
    "principio", "capitulo", "explicacao",
    "pratica_adotada", "pratica_recomendada",
    "categ_doc"          # categ_doc is not an identifier (codelist)
  )
  out_pos <- cvmdata:::identifier_columns(positives)
  out_neg <- cvmdata:::identifier_columns(negatives)
  failed_pos <- positives[!out_pos]
  failed_neg <- negatives[out_neg]
  expect_identical(failed_pos, character(0L),
                   info = "positives misclassified")
  expect_identical(failed_neg, character(0L),
                   info = "negatives misclassified")
})

# Dictionary + codelist (snapshot-dependent) --------------------------
# These require `data-raw/build-dictionary-snapshot.R --write` and
# `build-codelists-snapshot.R --write` to have been re-run with the
# CGVN schemas in place.

test_that("cvm_dictionary('cgvn', 'submissao') returns 12 rows", {
  dict <- cvm_dictionary("cgvn", "submissao")
  expect_s3_class(dict, "tbl_df")
  expect_equal(nrow(dict), 12L)
  expect_true("cnpj_companhia" %in% dict$campo)
})

test_that("cvm_dictionary('cgvn', 'praticas') returns 11 rows", {
  dict <- cvm_dictionary("cgvn", "praticas")
  expect_equal(nrow(dict), 11L)
  expect_true("id_item" %in% dict$campo)
})

test_that("cvm_codelist for CGVN Pratica_Adotada lists the 4 categories", {
  cl <- cvm_codelist("cgvn", "praticas", "pratica_adotada")
  # Empirical verification §12.3: Sim / Nao / Parcialmente / Nao se Aplica.
  # Accents come straight from CVM; expect_setequal tolerates ordering.
  expect_setequal(
    cl$value,
    c("Sim", "Não", "Parcialmente", "Não se Aplica")
  )
})
