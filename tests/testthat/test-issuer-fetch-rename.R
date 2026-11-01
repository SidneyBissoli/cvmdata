# Regression tests for the Session 06 rename (cad_fetch removed,
# companies -> issuer, years -> year) and for the removal of
# issuer_fetch() in favour of cvm_fetch() (2026-11-01). The
# orchestration paths are covered by test-issuer-fetch-yearly.R and
# test-issuer-fetch-cad.R; this file pins down the removed surface.

# Setup -----------------------------------------------------------------

local_prepare_cad_cache <- function(envir = parent.frame()) {
  cache_root <- withr::local_tempdir(.local_envir = envir)
  withr::local_options(
    cvmdata.cache_dir = cache_root,
    lifecycle_verbosity = "quiet",
    .local_envir = envir
  )
  raw_dir <- file.path(cache_root, "raw", "companhias", "cad")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  file.copy(
    test_path("fixtures", "cad_sample.csv"),
    file.path(raw_dir, "cad_cia_aberta.csv")
  )
  saveRDS(
    list(
      etag = "\"fixture-etag\"",
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = "2026-05-19T00:00:00.000Z"
    ),
    file.path(raw_dir, "cad_cia_aberta.csv.etag.rds")
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

# Tests -----------------------------------------------------------------

test_that("cad_fetch is no longer exported", {
  expect_false(exists(
    "cad_fetch",
    mode = "function",
    envir = asNamespace("cvmdata"),
    inherits = FALSE
  ))
})

test_that("issuer_fetch is gone, and so are its text and menu paths", {
  ns <- asNamespace("cvmdata")
  for (fn in c(
    "issuer_fetch",
    "disambiguate_text_match",
    "prompt_for_issuer_choice",
    "resolve_cd_cvm_via_submissao"
  )) {
    expect_false(exists(fn, mode = "function", envir = ns, inherits = FALSE))
  }
  expect_false("issuer_fetch" %in% getNamespaceExports(ns))
})

test_that("fetch engine accepts a vector via the singular `issuer` arg", {
  skip_if_not_installed("httptest2")
  local_prepare_cad_cache()
  full <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch_internal("cad", "companhias", source = "cvm")
  )
  skip_if(nrow(full) < 2L, "fixture too small for vector smoke test")
  picks <- utils::head(unique(full$cnpj_cia), 2L)
  filtered <- httr2::with_mocked_responses(
    function(req) fresh_head_response(),
    issuer_fetch_internal(
      "cad",
      "companhias",
      issuer = picks,
      source = "cvm"
    )
  )
  expect_true(all(filtered$cnpj_cia %in% picks))
  expect_gte(nrow(filtered), length(picks))
})

test_that("filter_by_issuer matches CNPJ only, in either CNPJ column", {
  cia <- data.frame(
    cnpj_cia = c("00.000.000/0001-91", "33.000.167/0001-01"),
    cd_cvm = c("001023", "009512")
  )
  # Punctuated or digits only; a CVM code is not a CNPJ and matches nothing.
  expect_identical(
    cvmdata:::filter_by_issuer(cia, "00000000000191")$cd_cvm,
    "001023"
  )
  expect_identical(
    cvmdata:::filter_by_issuer(cia, "33.000.167/0001-01")$cd_cvm,
    "009512"
  )
  expect_identical(nrow(cvmdata:::filter_by_issuer(cia, "001023")), 0L)

  fre <- data.frame(cnpj_companhia = "00.000.000/0001-91", x = 1L)
  expect_identical(nrow(cvmdata:::filter_by_issuer(fre, "00000000000191")), 1L)

  # A table without an issuer CNPJ column keeps no row.
  sem <- data.frame(x = 1:2)
  out <- cvmdata:::filter_by_issuer(sem, "00000000000191")
  expect_identical(nrow(out), 0L)
  expect_identical(names(out), "x")
})
