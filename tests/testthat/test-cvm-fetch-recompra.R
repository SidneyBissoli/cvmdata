# Tests for the recompra_acoes dataset (programas de recompra de acoes):
# the first dataset published as ONE ZIP without a year, and the first
# whose child tables (intermediarios, quantidades) carry no issuer
# column and reach the issuer through recompra_acoes (`issuer_via`).
# The fixture keeps the programs of BB + MGLU and the child rows of
# those programs (data-raw/build-mirror-test-fixtures.R, "recompra").

bb <- "00.000.000/0001-91"
mglu <- "47.960.950/0001-21"

# Stage the fixture ZIP where the static-archive path caches it: the
# dataset directory, without a year level.
local_prepare_recompra_cache <- function(envir = parent.frame()) {
  cache_root <- withr::local_tempdir(.local_envir = envir)
  withr::local_options(
    cvmdata.cache_dir = cache_root,
    lifecycle_verbosity = "quiet",
    .local_envir = envir
  )
  raw_dir <- file.path(cache_root, "raw", "companhias", "recompra_acoes")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  zip_name <- "cia_aberta_recompra_acoes.zip"
  file.copy(test_path("fixtures", zip_name), file.path(raw_dir, zip_name))
  saveRDS(
    list(
      etag = "\"fixture-etag\"",
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = "2026-05-19T00:00:00.000Z"
    ),
    file.path(raw_dir, paste0(zip_name, ".etag.rds"))
  )
  raw_dir
}

recompra_mirror_mock <- function() {
  fx <- function(t) {
    test_path("fixtures", sprintf("mirror-recompra_acoes-%s.parquet", t))
  }
  build_mock(lapply(
    c("recompra_acoes", "intermediarios", "quantidades"),
    function(t) list(name = sprintf("%s__part-0.parquet", t), parquet = fx(t))
  ))
}

# Source = cvm: the static ZIP ----------------------------------------------

test_that("the three tables read from the one ZIP without a year", {
  local_prepare_recompra_cache()
  progs <- with_fixture_http(
    cvm_fetch("recompra_acoes", "recompra_acoes", source = "cvm")
  )
  inter <- with_fixture_http(
    cvm_fetch("recompra_acoes", "intermediarios", source = "cvm")
  )
  qtd <- with_fixture_http(
    cvm_fetch("recompra_acoes", "quantidades", source = "cvm")
  )

  expect_s3_class(progs, "cvm_tbl")
  expect_identical(attr(progs, "group"), "companhias")
  expect_identical(attr(qtd, "table"), "quantidades")
  expect_identical(c(nrow(progs), nrow(inter), nrow(qtd)), c(14L, 52L, 14L))
  expect_identical(c(ncol(progs), ncol(inter), ncol(qtd)), c(11L, 3L, 5L))
  expect_type(progs$id_programa, "character")
  expect_type(inter$cnpj_intermediario, "character")
  expect_s3_class(progs$data_deliberacao, "Date")
  expect_type(qtd$quantidade_operacao, "double")
  expect_true(all(qtd$id_programa %in% progs$id_programa))
})

test_that("cnpj filters the main table directly", {
  local_prepare_recompra_cache()
  out <- with_fixture_http(
    cvm_fetch("recompra_acoes", "recompra_acoes", cnpj = bb, source = "cvm")
  )
  expect_gt(nrow(out), 0L)
  expect_identical(unique(out$cnpj_companhia), bb)
})

test_that("cnpj reaches the child tables through recompra_acoes", {
  local_prepare_recompra_cache()
  progs <- with_fixture_http(
    cvm_fetch("recompra_acoes", "recompra_acoes", cnpj = mglu, source = "cvm")
  )
  all_inter <- with_fixture_http(
    cvm_fetch("recompra_acoes", "intermediarios", source = "cvm")
  )
  inter <- with_fixture_http(
    cvm_fetch("recompra_acoes", "intermediarios", cnpj = mglu, source = "cvm")
  )

  expect_s3_class(inter, "cvm_tbl")
  expect_identical(attr(inter, "table"), "intermediarios")
  expect_gt(nrow(inter), 0L)
  expect_lt(nrow(inter), nrow(all_inter))
  expect_setequal(
    inter$id_programa,
    intersect(progs$id_programa, all_inter$id_programa)
  )
})

test_that("an issuer without programs yields zero child rows", {
  local_prepare_recompra_cache()
  out <- with_fixture_http(
    cvm_fetch(
      "recompra_acoes",
      "quantidades",
      cnpj = "33.000.167/0001-01",
      source = "cvm"
    )
  )
  expect_s3_class(out, "cvm_tbl")
  expect_identical(nrow(out), 0L)
  expect_identical(ncol(out), 5L)
})

test_that("year and from/to are refused on the non-yearly tables", {
  local_prepare_recompra_cache()
  expect_error(
    cvm_fetch("recompra_acoes", "quantidades", year = 2024, source = "cvm"),
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_fetch(
      "recompra_acoes",
      "recompra_acoes",
      from = "2020-01-01",
      to = "2020-12-31",
      source = "cvm"
    ),
    class = "cvmdata_error_input"
  )
})

test_that("a member missing from the static ZIP raises zip_member_missing", {
  local_prepare_recompra_cache()
  schema <- cvmdata:::load_schema("recompra_acoes", "quantidades")
  schema$cvm_file_pattern <- "cia_aberta_recompra_acoes_ausente.csv"
  expect_error(
    with_fixture_http(cvmdata:::source_cvm_http_get(schema)),
    class = "cvmdata_error_zip_member_missing"
  )
})

# Source = mirror -------------------------------------------------------------

test_that("cnpj reaches the child tables through the mirror too", {
  cvmdata:::mirror_assets_cache_clear()
  withr::local_options(
    cvmdata.cache_dir = withr::local_tempdir(),
    lifecycle_verbosity = "quiet"
  )
  mock <- recompra_mirror_mock()
  progs <- httr2::with_mocked_responses(
    mock,
    cvm_fetch("recompra_acoes", "recompra_acoes", cnpj = bb, source = "mirror")
  )
  qtd <- httr2::with_mocked_responses(
    mock,
    cvm_fetch("recompra_acoes", "quantidades", cnpj = bb, source = "mirror")
  )
  expect_identical(attr(qtd, "source"), "mirror")
  expect_gt(nrow(qtd), 0L)
  expect_true(all(qtd$id_programa %in% progs$id_programa))
})

# Schema and cache ------------------------------------------------------------

test_that("{year} in the archive URL must match the partitioning", {
  base <- cvmdata:::load_schema("recompra_acoes", "recompra_acoes")
  s <- unclass(base)
  s$cvm_archive_url_pattern <- "https://example.test/x_{year}.zip"
  expect_error(
    cvmdata:::validate_url_topology(s, "recompra_acoes", "recompra_acoes"),
    class = "cvmdata_error_internal"
  )
  y <- unclass(cvmdata:::load_schema("vlmo", "submissao"))
  y$cvm_archive_url_pattern <- "https://example.test/vlmo.zip"
  expect_error(
    cvmdata:::validate_url_topology(y, "vlmo", "submissao"),
    class = "cvmdata_error_internal"
  )
})

test_that("a malformed issuer_via is refused", {
  s <- unclass(cvmdata:::load_schema("recompra_acoes", "quantidades"))
  expect_no_error(
    cvmdata:::validate_issuer_via(s, "recompra_acoes", "quantidades")
  )
  s$issuer_via <- list(table = "recompra_acoes")
  expect_error(
    cvmdata:::validate_issuer_via(s, "recompra_acoes", "quantidades"),
    class = "cvmdata_error_internal"
  )
  s$issuer_via <- list(table = "quantidades", key = "id_programa")
  expect_error(
    cvmdata:::validate_issuer_via(s, "recompra_acoes", "quantidades"),
    class = "cvmdata_error_internal"
  )
})

test_that("the static ZIP and its extracted CSVs form one cache unit", {
  raw_dir <- local_prepare_recompra_cache()
  with_fixture_http(
    cvm_fetch("recompra_acoes", "quantidades", source = "cvm")
  )
  units <- cvmdata:::build_cache_units(dirname(dirname(raw_dir)))
  expect_length(units$units, 1L)
  expect_true(any(grepl("_quantidades\\.csv$", units$units[[1L]])))
  expect_true(any(grepl("\\.zip$", units$units[[1L]])))
})
