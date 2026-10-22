# Tests for cvm_fetch(), the single public fetcher (v0.3). The HTTP
# layer is mocked with httr2::with_mocked_responses() + local fixture
# ZIPs staged in a tempdir cache (same pattern as the issuer_fetch
# tests); the mirror path reuses the GitHub mock of helper-mirror-mock.R.

# Helpers ----------------------------------------------------------------

# Stage one or more dataset fixture ZIPs (year 2024 by default; the
# DFP also ships a 2025 fixture) in a tempdir cache with matching etag
# sidecars, and redirect cvm_cache_root() at it.
local_prepare_cvm_cache <- function(
  datasets,
  years = 2024L,
  envir = parent.frame()
) {
  cache_root <- withr::local_tempdir(.local_envir = envir)
  withr::local_options(
    cvmdata.cache_dir = cache_root,
    .local_envir = envir
  )
  cvmdata:::ticker_lookup_cache_clear()
  withr::defer(cvmdata:::ticker_lookup_cache_clear(), envir = envir)
  for (ds in datasets) {
    for (yr in years) {
      raw_dir <- file.path(cache_root, "raw", "companhias", ds, yr)
      dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
      zip_name <- sprintf("%s_cia_aberta_%d.zip", ds, as.integer(yr))
      file.copy(
        test_path("fixtures", zip_name),
        file.path(raw_dir, zip_name)
      )
      saveRDS(
        list(
          etag = "\"fixture-etag\"",
          last_modified = "Mon, 19 May 2026 00:00:00 GMT",
          fetched_at = "2026-05-19T00:00:00.000Z"
        ),
        file.path(raw_dir, paste0(zip_name, ".etag.rds"))
      )
    }
  }
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

with_fixture_http <- function(expr) {
  httr2::with_mocked_responses(function(req) fresh_head_response(), expr)
}

# Pin the years the CVM "publishes" for every yearly dataset, so the
# ticker lookup (all FCA years from 2018) and the restated reading (the
# following year's file) only ask for files the fixtures provide.
local_published_years <- function(
  years = c(2024L, 2025L),
  envir = parent.frame()
) {
  testthat::local_mocked_bindings(
    cvm_dataset_years = function(dataset, group = NULL, schema = NULL) years,
    .env = envir
  )
}

# Stage the CAD fixture as the cached `cad_cia_aberta.csv` with a fresh
# etag sidecar (same pattern as test-issuer-fetch-cad.R).
local_prepare_cad_cache <- function(envir = parent.frame()) {
  cache_root <- withr::local_tempdir(.local_envir = envir)
  withr::local_options(cvmdata.cache_dir = cache_root, .local_envir = envir)
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

bb_cnpj <- "00.000.000/0001-91" # BCO BRASIL S.A.
mglu_cnpj <- "47960950000121" # MAGAZINE LUIZA S.A.

# Tracer -------------------------------------------------------------

test_that("cvm_fetch DFP BPA by CNPJ returns a cvm_tbl with a basis column", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache("dfp")

  result <- with_fixture_http(
    cvm_fetch(
      "dfp",
      "bpa",
      cnpj = bb_cnpj,
      year = 2024,
      basis = "ind",
      source = "cvm"
    )
  )

  expect_s3_class(result, "cvm_tbl")
  expect_identical(attr(result, "source"), "cvm")
  expect_identical(attr(result, "group"), "companhias")
  expect_identical(attr(result, "dataset"), "dfp")
  expect_identical(attr(result, "table"), "bpa")
  expect_true(nrow(result) > 0L)
  expect_true(all(result$cnpj_cia == bb_cnpj))
  expect_true("basis" %in% names(result))
  expect_identical(unique(result$basis), "ind")
  expect_false("report_type" %in% names(result))
  expect_false("escala_moeda" %in% names(result))
})

test_that("cvm_fetch accepts CNPJ with or without punctuation", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache("dfp")

  punctuated <- with_fixture_http(
    cvm_fetch(
      "dfp",
      "bpa",
      cnpj = bb_cnpj,
      year = 2024,
      basis = "ind",
      source = "cvm"
    )
  )
  digits <- with_fixture_http(
    cvm_fetch(
      "dfp",
      "bpa",
      cnpj = cnpj_clean(bb_cnpj),
      year = 2024,
      basis = "ind",
      source = "cvm"
    )
  )
  expect_identical(nrow(punctuated), nrow(digits))
  expect_identical(punctuated$vl_conta, digits$vl_conta)
})

test_that("cvm_fetch with several CNPJs keeps every requested issuer", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache("dfp")

  result <- with_fixture_http(
    cvm_fetch(
      "dfp",
      "bpa",
      cnpj = c(bb_cnpj, mglu_cnpj),
      year = 2024,
      basis = "ind",
      source = "cvm"
    )
  )
  expect_setequal(unique(result$cd_cvm), c("001023", "022470"))
})

test_that("cvm_fetch without cnpj returns every issuer", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache("dfp")

  result <- with_fixture_http(
    cvm_fetch("dfp", "bpa", year = 2024, basis = "ind", source = "cvm")
  )
  expect_true(length(unique(result$cnpj_cia)) >= 2L)
})

# basis --------------------------------------------------------------

test_that("cvm_fetch basis = c('ind', 'con') stacks both variants", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache("dfp")

  both <- with_fixture_http(
    cvm_fetch(
      "dfp",
      "bpa",
      cnpj = bb_cnpj,
      year = 2024,
      basis = c("ind", "con"),
      source = "cvm"
    )
  )
  ind <- with_fixture_http(
    cvm_fetch(
      "dfp",
      "bpa",
      cnpj = bb_cnpj,
      year = 2024,
      basis = "ind",
      source = "cvm"
    )
  )
  con <- with_fixture_http(
    cvm_fetch(
      "dfp",
      "bpa",
      cnpj = bb_cnpj,
      year = 2024,
      basis = "con",
      source = "cvm"
    )
  )
  expect_s3_class(both, "cvm_tbl")
  expect_setequal(unique(both$basis), c("ind", "con"))
  expect_identical(nrow(both), nrow(ind) + nrow(con))
  expect_identical(sum(both$basis == "ind"), nrow(ind))
  expect_identical(sum(both$basis == "con"), nrow(con))
  expect_identical(attr(both, "table"), "bpa")
})

test_that("cvm_fetch requires basis on tables with the ind/con split", {
  local_prepare_cvm_cache("dfp")
  err <- expect_error(
    cvm_fetch("dfp", "bpa", year = 2024, source = "cvm"),
    class = "cvmdata_error_input"
  )
  expect_match(conditionMessage(err), "requires `basis`")
  expect_match(conditionMessage(err), "ind")
  expect_match(conditionMessage(err), "con")
})

test_that("cvm_fetch rejects basis on tables without the split", {
  local_prepare_cvm_cache("dfp")
  expect_error(
    cvm_fetch(
      "dfp",
      "composicao_capital",
      year = 2024,
      basis = "ind",
      source = "cvm"
    ),
    regexp = "no individual/consolidated split",
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_fetch("cad", "companhias", basis = "con", source = "cvm"),
    regexp = "no individual/consolidated split",
    class = "cvmdata_error_input"
  )
})

test_that("cvm_fetch rejects an unknown basis value", {
  local_prepare_cvm_cache("dfp")
  expect_error(
    cvm_fetch(
      "dfp",
      "bpa",
      year = 2024,
      basis = "consolidated",
      source = "cvm"
    ),
    regexp = "must be",
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_fetch("dfp", "bpa", year = 2024, basis = character(0L), source = "cvm"),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_fetch via mirror renames the leaked report_type to basis", {
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)

  entries <- list(
    list(
      name = "bpa__report_type=ind__year=2024__part-0.parquet",
      parquet = dfp_fx()
    )
  )
  result <- httr2::with_mocked_responses(
    build_mock(entries),
    cvm_fetch("dfp", "bpa", year = 2024, basis = "ind", source = "mirror")
  )
  expect_s3_class(result, "cvm_tbl")
  expect_identical(attr(result, "source"), "mirror")
  expect_true(nrow(result) > 0L)
  expect_true("basis" %in% names(result))
  expect_identical(unique(result$basis), "ind")
  expect_false("report_type" %in% names(result))
})

# cnpj validation ----------------------------------------------------

test_that("cvm_fetch rejects a CVM code passed as cnpj", {
  local_prepare_cvm_cache("dfp")
  err <- expect_error(
    cvm_fetch(
      "dfp",
      "bpa",
      cnpj = "1023",
      year = 2024,
      basis = "ind",
      source = "cvm"
    ),
    class = "cvmdata_error_input"
  )
  expect_match(conditionMessage(err), "accepts only CNPJ")
  expect_match(conditionMessage(err), "1023")
})

test_that("cvm_fetch rejects a company name passed as cnpj", {
  local_prepare_cvm_cache("dfp")
  expect_error(
    cvm_fetch(
      "dfp",
      "bpa",
      cnpj = "BCO BRASIL",
      year = 2024,
      basis = "ind",
      source = "cvm"
    ),
    regexp = "accepts only CNPJ",
    class = "cvmdata_error_input"
  )
})

test_that("cvm_fetch rejects a numeric cnpj", {
  local_prepare_cvm_cache("dfp")
  expect_error(
    cvm_fetch(
      "dfp",
      "bpa",
      cnpj = 191,
      year = 2024,
      basis = "ind",
      source = "cvm"
    ),
    regexp = "character vector",
    class = "cvmdata_error_input"
  )
})

test_that("cvm_fetch with a CNPJ absent from the table returns zero rows", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache("dfp")
  result <- with_fixture_http(
    cvm_fetch(
      "dfp",
      "bpa",
      cnpj = "11.111.111/0001-11",
      year = 2024,
      basis = "ind",
      source = "cvm"
    )
  )
  expect_s3_class(result, "cvm_tbl")
  expect_identical(nrow(result), 0L)
  expect_true("basis" %in% names(result))
})

# ticker -------------------------------------------------------------

test_that("cvm_fetch resolves a ticker to its CNPJ via fca", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache(c("dfp", "fca"))
  local_published_years(2024L)

  by_ticker <- with_fixture_http(
    cvm_fetch(
      "dfp",
      "bpa",
      ticker = "bbas3",
      year = 2024,
      basis = "ind",
      source = "cvm"
    )
  )
  by_cnpj <- with_fixture_http(
    cvm_fetch(
      "dfp",
      "bpa",
      cnpj = bb_cnpj,
      year = 2024,
      basis = "ind",
      source = "cvm"
    )
  )
  expect_true(nrow(by_ticker) > 0L)
  expect_identical(by_ticker$vl_conta, by_cnpj$vl_conta)
  expect_true(all(by_ticker$cnpj_cia == bb_cnpj))
})

test_that("cvm_fetch combines cnpj and ticker", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache(c("dfp", "fca"))
  local_published_years(2024L)

  result <- with_fixture_http(
    cvm_fetch(
      "dfp",
      "bpa",
      cnpj = bb_cnpj,
      ticker = "MGLU3",
      year = 2024,
      basis = "ind",
      source = "cvm"
    )
  )
  expect_setequal(unique(result$cd_cvm), c("001023", "022470"))
})

test_that("cvm_fetch aborts on a ticker absent from fca", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache(c("dfp", "fca"))
  local_published_years(2024L)
  expect_error(
    with_fixture_http(
      cvm_fetch(
        "dfp",
        "bpa",
        ticker = "XXXX3",
        year = 2024,
        basis = "ind",
        source = "cvm"
      )
    ),
    regexp = "not found.*any year",
    class = "cvmdata_error_input"
  )
})

# The lookup unions every FCA year from 2018 on; these tests feed the
# session cache directly so the resolver's rules are exercised without
# a multi-year fixture.
local_ticker_lut <- function(lut, years, envir = parent.frame()) {
  cvmdata:::ticker_lookup_cache_clear()
  withr::defer(cvmdata:::ticker_lookup_cache_clear(), envir = envir)
  attr(lut, "years") <- years
  assign(
    "fca_valor_mobiliario_cvm_all",
    lut,
    envir = cvmdata:::.ticker_lookup_cache
  )
}

test_that("ticker resolution finds a code that only older FCA files carry", {
  local_ticker_lut(
    data.frame(
      ticker = c("GOLL4", "PETR4", "PETR4"),
      cnpj_companhia = c(
        "06.164.253/0001-87",
        "33.000.167/0001-01",
        "33.000.167/0001-01"
      ),
      year = c(2019L, 2019L, 2024L),
      stringsAsFactors = FALSE
    ),
    years = c(2019L, 2024L)
  )
  expect_identical(
    cvmdata:::resolve_ticker_all_years("goll4", source = "cvm"),
    "06.164.253/0001-87"
  )
  expect_identical(
    cvmdata:::resolve_ticker_all_years(c("PETR4", "GOLL4"), source = "cvm"),
    c("33.000.167/0001-01", "06.164.253/0001-87")
  )
})

test_that("ticker resolution aborts when a code maps to two issuers", {
  local_ticker_lut(
    data.frame(
      ticker = c("ABCD3", "ABCD3"),
      cnpj_companhia = c("11.111.111/0001-11", "22.222.222/0001-22"),
      year = c(2018L, 2024L),
      stringsAsFactors = FALSE
    ),
    years = c(2018L, 2024L)
  )
  expect_error(
    cvmdata:::resolve_ticker_all_years("ABCD3", source = "cvm"),
    regexp = "more than one issuer",
    class = "cvmdata_error_input"
  )
})

test_that("ticker resolution names the years searched when a code is absent", {
  local_ticker_lut(
    data.frame(
      ticker = "PETR4",
      cnpj_companhia = "33.000.167/0001-01",
      year = 2024L,
      stringsAsFactors = FALSE
    ),
    years = c(2018L, 2024L)
  )
  expect_error(
    cvmdata:::resolve_ticker_all_years("XXXX3", source = "cvm"),
    regexp = "2018-2024",
    class = "cvmdata_error_input"
  )
})

# as_of ----------------------------------------------------------------

# cad_sample.csv: 50 rows, 41 cancelled, 3 CNPJs repeated by tp_merc;
# 11.396.633/0001-87 registered 2010-03-08 and cancelled 2015-12-18.
test_that("cvm_fetch as_of keeps the registrations in force on the date", {
  skip_if_not_installed("httptest2")
  local_prepare_cad_cache()
  all_rows <- with_fixture_http(
    cvm_fetch("cad", "companhias", source = "cvm")
  )
  at <- as.Date("2012-12-31")
  u2012 <- with_fixture_http(
    cvm_fetch("cad", "companhias", as_of = at, source = "cvm")
  )
  expect_s3_class(u2012, "cvm_tbl")
  expect_identical(names(u2012), names(all_rows))
  expect_true(nrow(u2012) > 0L && nrow(u2012) < nrow(all_rows))
  expect_true(all(u2012$dt_reg <= at))
  expect_true(all(is.na(u2012$dt_cancel) | u2012$dt_cancel > at))
  expect_identical(
    nrow(u2012),
    sum(
      all_rows$dt_reg <= at &
        (is.na(all_rows$dt_cancel) | all_rows$dt_cancel > at)
    )
  )
  # The 2010-2015 registration is in the 2012 universe with today's
  # row (already cancelled), and out of the 2016 one.
  reg_2010 <- "11.396.633/0001-87"
  expect_true(reg_2010 %in% u2012$cnpj_cia)
  expect_identical(
    unique(u2012$sit[u2012$cnpj_cia == reg_2010]),
    "CANCELADA"
  )
  u2016 <- with_fixture_http(
    cvm_fetch("cad", "companhias", as_of = "2016-12-31", source = "cvm")
  )
  expect_false(reg_2010 %in% u2016$cnpj_cia)
})

test_that("cvm_fetch as_of rejects non-registry tables and partial dates", {
  expect_error(
    cvm_fetch("dfp", "bpa", year = 2024, basis = "ind", as_of = "2015-12-31"),
    regexp = "not a registry",
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_fetch("cad", "companhias", as_of = "2015", source = "cvm"),
    regexp = "complete date",
    class = "cvmdata_error_input"
  )
})

test_that("filter_as_of places rows by registration and cancellation", {
  schema <- cvmdata:::load_schema("cad", "companhias")
  df <- data.frame(
    cnpj_cia = c("a", "b", "c", "d"),
    dt_reg = as.Date(c("2010-01-01", "2010-01-01", "2016-01-01", NA)),
    dt_cancel = as.Date(c(NA, "2015-06-30", NA, NA)),
    stringsAsFactors = FALSE
  )
  at <- as.Date("2015-12-31")
  expect_identical(cvmdata:::filter_as_of(df, at, schema)$cnpj_cia, "a")
  expect_identical(
    cvmdata:::filter_as_of(df, as.Date("2015-06-30"), schema)$cnpj_cia,
    "a"
  )
  expect_identical(
    cvmdata:::filter_as_of(df, as.Date("2015-06-29"), schema)$cnpj_cia,
    c("a", "b")
  )
  expect_identical(cvmdata:::filter_as_of(df, NULL, schema), df)
})

test_that("cvm_fetch rejects a ticker that is not a B3 code", {
  local_prepare_cvm_cache("dfp")
  expect_error(
    cvm_fetch(
      "dfp",
      "bpa",
      ticker = "00000000000191",
      year = 2024,
      basis = "ind",
      source = "cvm"
    ),
    regexp = "B3 trading code",
    class = "cvmdata_error_input"
  )
})

# year vs from/to ----------------------------------------------------

test_that("cvm_fetch rejects year together with from/to", {
  local_prepare_cvm_cache("dfp")
  expect_error(
    cvm_fetch(
      "dfp",
      "bpa",
      year = 2024,
      from = "2024-01-01",
      to = "2024-12-31",
      basis = "ind",
      source = "cvm"
    ),
    regexp = "not both",
    class = "cvmdata_error_input"
  )
})

test_that("cvm_fetch requires from and to together", {
  local_prepare_cvm_cache("dfp")
  expect_error(
    cvm_fetch("dfp", "bpa", from = "2024-01-01", basis = "ind", source = "cvm"),
    regexp = "given together",
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_fetch("dfp", "bpa", to = "2024-12-31", basis = "ind", source = "cvm"),
    regexp = "given together",
    class = "cvmdata_error_input"
  )
})

test_that("cvm_fetch rejects incomplete or invalid dates", {
  local_prepare_cvm_cache("dfp")
  for (bad in list("2024", "2024-06", "31/12/2024", 2024L)) {
    expect_error(
      cvm_fetch(
        "dfp",
        "bpa",
        from = bad,
        to = "2024-12-31",
        basis = "ind",
        source = "cvm"
      ),
      regexp = "complete date",
      class = "cvmdata_error_input"
    )
  }
  expect_error(
    cvm_fetch(
      "dfp",
      "bpa",
      from = "2024-02-30",
      to = "2024-12-31",
      basis = "ind",
      source = "cvm"
    ),
    regexp = "valid calendar date",
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_fetch(
      "dfp",
      "bpa",
      from = "2024-12-31",
      to = "2024-01-01",
      basis = "ind",
      source = "cvm"
    ),
    regexp = "must not be later",
    class = "cvmdata_error_input"
  )
})

test_that("cvm_fetch rejects from/to on a snapshot table", {
  local_prepare_cvm_cache("dfp")
  expect_error(
    cvm_fetch(
      "cad",
      "companhias",
      from = "2024-01-01",
      to = "2024-12-31",
      source = "cvm"
    ),
    regexp = "single snapshot",
    class = "cvmdata_error_input"
  )
})

test_that("cvm_fetch from/to filters by the document reference date", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache("dfp")

  # The 2024 fixture carries filings referenced 2024-12-31 only.
  hit <- with_fixture_http(
    cvm_fetch(
      "dfp",
      "bpa",
      cnpj = bb_cnpj,
      from = "2024-12-01",
      to = "2024-12-31",
      basis = "ind",
      source = "cvm"
    )
  )
  whole_year <- with_fixture_http(
    cvm_fetch(
      "dfp",
      "bpa",
      cnpj = bb_cnpj,
      year = 2024,
      basis = "ind",
      source = "cvm"
    )
  )
  expect_identical(nrow(hit), nrow(whole_year))
  expect_true(all(hit$dt_refer >= as.Date("2024-12-01")))

  miss <- with_fixture_http(
    cvm_fetch(
      "dfp",
      "bpa",
      cnpj = bb_cnpj,
      from = "2024-01-01",
      to = "2024-06-30",
      basis = "ind",
      source = "cvm"
    )
  )
  expect_s3_class(miss, "cvm_tbl")
  expect_identical(nrow(miss), 0L)
})

test_that("cvm_fetch accepts Date objects for from/to", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache("dfp")
  result <- with_fixture_http(
    cvm_fetch(
      "dfp",
      "bpa",
      cnpj = bb_cnpj,
      from = as.Date("2024-07-01"),
      to = as.Date("2024-12-31"),
      basis = "ind",
      source = "cvm"
    )
  )
  expect_true(nrow(result) > 0L)
})

test_that("cvm_fetch rejects year on a snapshot table", {
  local_prepare_cvm_cache("dfp")
  expect_error(
    cvm_fetch("cad", "companhias", year = 2024, source = "cvm"),
    regexp = "not yearly-partitioned",
    class = "cvmdata_error_input"
  )
})

# Pure helpers -------------------------------------------------------

test_that("check_period derives the yearly files from the window", {
  schema <- cvmdata:::load_schema("dfp", "bpa")
  period <- cvmdata:::check_period(
    NULL,
    "2022-06-30",
    "2024-03-31",
    schema
  )
  expect_identical(period$year, 2022:2024)
  expect_identical(period$from, as.Date("2022-06-30"))
  expect_identical(period$to, as.Date("2024-03-31"))

  plain <- cvmdata:::check_period(2023L, NULL, NULL, schema)
  expect_identical(plain$year, 2023L)
  expect_null(plain$from)
})

# reading --------------------------------------------------------------

# The DFP fixtures cover 2024 and 2025 for BCO BRASIL + MAGAZINE LUIZA,
# so the 2025 file is the "following year" of exercise 2024. Measured
# on the real files (2026-10-20): BB consolidated restates 12 BPA
# accounts of 2024, BB individual carries the 2024 comparative as
# zeros, MAGAZINE LUIZA restates nothing. `local_published_years()` (top
# of the file) pins the published years.

fetch_bpa <- function(...) {
  with_fixture_http(cvm_fetch("dfp", "bpa", source = "cvm", ...))
}

ultimo <- "ÚLTIMO"
penultimo <- "PENÚLTIMO"

test_that("cvm_fetch rejects reading on a table without ordem_exerc", {
  expect_error(
    cvm_fetch("dfp", "composicao_capital", year = 2024, reading = "original"),
    regexp = "exercise order",
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_fetch("cad", "companhias", reading = "original"),
    regexp = "exercise order",
    class = "cvmdata_error_input"
  )
})

test_that("cvm_fetch rejects an unknown reading value", {
  expect_error(
    cvm_fetch("dfp", "bpa", year = 2024, basis = "ind", reading = "latest"),
    regexp = "must be",
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_fetch("dfp", "bpa", year = 2024, basis = "ind", reading = TRUE),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_fetch without reading returns the file as published", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache("dfp", years = 2024:2025)

  literal <- fetch_bpa(cnpj = bb_cnpj, year = 2024, basis = "ind")
  expect_false("reading" %in% names(literal))
  expect_setequal(unique(literal$ordem_exerc), c(ultimo, penultimo))
})

test_that("reading = 'original' keeps the ULTIMO rows of the exercise year", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache("dfp", years = 2024:2025)
  local_published_years()

  literal <- fetch_bpa(cnpj = bb_cnpj, year = 2024, basis = "ind")
  original <- fetch_bpa(
    cnpj = bb_cnpj,
    year = 2024,
    basis = "ind",
    reading = "original"
  )
  expect_s3_class(original, "cvm_tbl")
  expect_identical(nrow(original), sum(literal$ordem_exerc == ultimo))
  expect_identical(unique(original$reading), "original")
  expect_identical(unique(original$ordem_exerc), ultimo)
  expect_identical(unique(format(original$dt_refer, "%Y")), "2024")
  expect_identical(unique(original$basis), "ind")
  expect_identical(names(original)[length(names(original))], "reading")
})

test_that("reading = 'restated' reads the following year's PENULTIMO rows", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache("dfp", years = 2024:2025)
  local_published_years()

  original <- fetch_bpa(
    cnpj = bb_cnpj,
    year = 2024,
    basis = "con",
    reading = "original"
  )
  restated <- fetch_bpa(
    cnpj = bb_cnpj,
    year = 2024,
    basis = "con",
    reading = "restated"
  )
  expect_identical(unique(restated$reading), "restated")
  expect_identical(unique(restated$ordem_exerc), penultimo)
  expect_identical(unique(format(restated$dt_refer, "%Y")), "2025")
  expect_identical(unique(format(restated$dt_fim_exerc)), "2024-12-31")
  expect_identical(nrow(restated), nrow(original))
  # BB consolidated restated its 2024 non-current assets (1.02) in the
  # 2025 filing; total assets (1) stayed.
  v <- function(df, conta) df$vl_conta[df$cd_conta == conta]
  expect_true(v(restated, "1.02") != v(original, "1.02"))
  expect_identical(v(restated, "1"), v(original, "1"))
})

test_that("a restated figure is zero where no comparative was filed", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache("dfp", years = 2024:2025)
  local_published_years()

  # Banks adopted CMN Resolution 4,966 in 2025 and presented no 2024
  # comparative on the individual basis: the CVM file carries zeros,
  # and so does the restated reading; the package does not patch it.
  both <- fetch_bpa(
    cnpj = bb_cnpj,
    year = 2024,
    basis = "ind",
    reading = c("original", "restated")
  )
  total <- both[both$cd_conta == "1", ]
  expect_identical(total$reading, c("original", "restated"))
  expect_true(total$vl_conta[total$reading == "original"] > 0)
  expect_identical(total$vl_conta[total$reading == "restated"], 0)

  # MAGAZINE LUIZA restated nothing: the two readings agree account by
  # account.
  mglu <- fetch_bpa(
    cnpj = mglu_cnpj,
    year = 2024,
    basis = "ind",
    reading = c("original", "restated")
  )
  o <- mglu[mglu$reading == "original", c("cd_conta", "vl_conta")]
  r <- mglu[mglu$reading == "restated", c("cd_conta", "vl_conta")]
  expect_identical(nrow(o), nrow(r))
  expect_identical(
    o$vl_conta[order(o$cd_conta)],
    r$vl_conta[order(r$cd_conta)]
  )
})

test_that("reading stacks the readings in the order requested", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache("dfp", years = 2024:2025)
  local_published_years()

  original <- fetch_bpa(
    cnpj = bb_cnpj,
    year = 2024,
    basis = "ind",
    reading = "original"
  )
  restated <- fetch_bpa(
    cnpj = bb_cnpj,
    year = 2024,
    basis = "ind",
    reading = "restated"
  )
  both <- fetch_bpa(
    cnpj = bb_cnpj,
    year = 2024,
    basis = "ind",
    reading = c("original", "restated")
  )
  reversed <- fetch_bpa(
    cnpj = bb_cnpj,
    year = 2024,
    basis = "ind",
    reading = c("restated", "original")
  )
  expect_identical(nrow(both), nrow(original) + nrow(restated))
  expect_identical(unique(both$reading), c("original", "restated"))
  expect_identical(unique(reversed$reading), c("restated", "original"))
  expect_identical(nrow(reversed), nrow(both))
})

test_that("reading with both bases labels every row", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache("dfp", years = 2024:2025)
  local_published_years()

  out <- fetch_bpa(
    cnpj = bb_cnpj,
    year = 2024,
    basis = c("ind", "con"),
    reading = c("original", "restated")
  )
  expect_setequal(unique(out$basis), c("ind", "con"))
  expect_setequal(unique(out$reading), c("original", "restated"))
  counts <- table(out$basis, out$reading)
  expect_true(all(counts > 0L))
})

test_that("no restated reading when the following file is unpublished", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache("dfp", years = 2024:2025)
  local_published_years(c(2024L, 2025L))

  expect_message(
    both <- fetch_bpa(
      cnpj = bb_cnpj,
      year = 2025,
      basis = "ind",
      reading = c("original", "restated")
    ),
    regexp = "not published yet"
  )
  expect_identical(unique(both$reading), "original")
  expect_true(nrow(both) > 0L)

  expect_message(
    none <- fetch_bpa(
      cnpj = bb_cnpj,
      year = 2025,
      basis = "ind",
      reading = "restated"
    ),
    regexp = "not published yet"
  )
  expect_identical(nrow(none), 0L)
  expect_true("reading" %in% names(none))

  # Two exercises, one of them with a following file: the message
  # names only the one without it, and rows come only for the other.
  expect_message(
    span <- fetch_bpa(
      cnpj = bb_cnpj,
      year = 2024:2025,
      basis = "ind",
      reading = "restated"
    ),
    regexp = "2025"
  )
  expect_identical(unique(format(span$dt_fim_exerc)), "2024-12-31")
})

test_that("year = NULL with reading resolves the latest year as usual", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache("dfp", years = 2024:2025)
  local_published_years(c(2024L, 2025L))

  expect_message(
    out <- fetch_bpa(
      cnpj = bb_cnpj,
      basis = "ind",
      reading = c("original", "restated")
    ),
    regexp = "not published yet"
  )
  expect_identical(unique(format(out$dt_refer, "%Y")), "2025")
  expect_identical(unique(out$reading), "original")
})

test_that("from/to with reading windows on the exercise end", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache("dfp", years = 2024:2025)
  local_published_years()

  out <- fetch_bpa(
    cnpj = bb_cnpj,
    from = "2024-01-01",
    to = "2024-12-31",
    basis = "con",
    reading = c("original", "restated")
  )
  # The restated rows are dated 2025 (dt_refer) but describe exercise
  # 2024 (dt_fim_exerc): the window keeps them.
  expect_setequal(unique(out$reading), c("original", "restated"))
  expect_identical(unique(format(out$dt_fim_exerc)), "2024-12-31")
  expect_setequal(unique(format(out$dt_refer, "%Y")), c("2024", "2025"))
})

test_that("reading works on the mirror backend", {
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)

  entries <- list(
    list(
      name = "bpa__report_type=ind__year=2024__part-0.parquet",
      parquet = dfp_fx()
    ),
    list(
      name = "bpa__report_type=ind__year=2025__part-0.parquet",
      parquet = test_path("fixtures", "mirror-dfp-bpa-ind-2025.parquet")
    )
  )
  both <- httr2::with_mocked_responses(
    build_mock(entries),
    cvm_fetch(
      "dfp",
      "bpa",
      cnpj = bb_cnpj,
      year = 2024,
      basis = "ind",
      reading = c("original", "restated"),
      source = "mirror"
    )
  )
  expect_s3_class(both, "cvm_tbl")
  expect_identical(attr(both, "source"), "mirror")
  expect_setequal(unique(both$reading), c("original", "restated"))
  expect_identical(
    unique(format(both$dt_refer[both$reading == "restated"], "%Y")),
    "2025"
  )
  expect_identical(unique(format(both$dt_fim_exerc)), "2024-12-31")

  # The 2026 asset is not in the inventory: exercise 2025 has no
  # restated reading on the mirror either.
  expect_message(
    latest <- httr2::with_mocked_responses(
      build_mock(entries),
      cvm_fetch(
        "dfp",
        "bpa",
        cnpj = bb_cnpj,
        year = 2025,
        basis = "ind",
        reading = c("original", "restated"),
        source = "mirror"
      )
    ),
    regexp = "not published yet"
  )
  expect_identical(unique(latest$reading), "original")
})

# dots ---------------------------------------------------------------

test_that("cvm_fetch rejects unknown arguments", {
  expect_error(
    cvm_fetch("dfp", "bpa", issuer = "1023", year = 2024, basis = "ind"),
    regexp = "Unknown argument",
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_fetch("dfp", "bpa", report_type = "ind", year = 2024),
    regexp = "Unknown argument",
    class = "cvmdata_error_input"
  )
})
