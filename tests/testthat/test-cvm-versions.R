# Tests for cvm_versions(). The mirror path reuses the GitHub mock of
# helper-mirror-mock.R with the dfp/dre con 2023 fixtures: the current
# asset and the history asset of the partition, cut to PETROBRAS
# (versions 1 and 2) and BRASKEM (versions 1, 2 and 3) and to four
# accounts. The CVM path reads the ITR 2024 fixture ZIP staged by
# helper-cvm-cache.R, whose BPA ind CSV still carries versions 1 and 2
# of MAGAZINE LUIZA's filing.

dre_current_fx <- function() {
  test_path("fixtures", "mirror-dfp-dre-con-2023.parquet")
}
dre_history_fx <- function() {
  test_path("fixtures", "mirror-dfp-dre-con-2023-history.parquet")
}
petr_cnpj <- "33.000.167/0001-01"
brkm_cnpj <- "42.150.391/0001-70"
ultimo <- paste0(intToUtf8(0x00DA), "LTIMO")

# Stage a tempdir cache and build the GitHub mock of the dre con 2023
# partition, with or without its history asset.
local_mirror_dre <- function(history = TRUE, envir = parent.frame()) {
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir(.local_envir = envir)
  withr::local_options(cvmdata.cache_dir = cache_root, .local_envir = envir)
  entries <- list(
    list(
      name = "dre__report_type.con__year.2023__part-0.parquet",
      parquet = dre_current_fx()
    )
  )
  if (history) {
    entries <- c(
      entries,
      list(list(
        name = "dre__report_type.con__year.2023__history.parquet",
        parquet = dre_history_fx()
      ))
    )
  }
  build_mock(entries)
}

versions_of <- function(df, cnpj) {
  sort(unique(df$versao[df$cnpj_cia == cnpj]))
}

# Mirror ---------------------------------------------------------------

test_that("cvm_versions via mirror returns every version, with the columns", {
  mock <- local_mirror_dre()
  out <- httr2::with_mocked_responses(
    mock,
    cvm_versions("dfp", "dre", year = 2023, basis = "con")
  )
  expect_s3_class(out, "cvm_tbl")
  expect_identical(attr(out, "source"), "mirror")
  expect_identical(attr(out, "dataset"), "dfp")
  expect_identical(attr(out, "table"), "dre")
  expect_identical(nrow(out), 40L)
  expect_identical(
    utils::tail(names(out), 6L),
    c(
      "basis",
      "superseded_at",
      "superseded_by_versao",
      "history_source",
      "id_doc",
      "motivo_reapresentacao"
    )
  )
  expect_false("report_type" %in% names(out))
  expect_s3_class(out$superseded_at, "Date")
  expect_identical(versions_of(out, brkm_cnpj), c("1", "2", "3"))
  expect_identical(versions_of(out, petr_cnpj), c("1", "2"))
})

test_that("the current version is marked and the superseded ones are dated", {
  mock <- local_mirror_dre()
  out <- httr2::with_mocked_responses(
    mock,
    cvm_versions("dfp", "dre", year = 2023, basis = "con")
  )
  current <- out[out$history_source == "current", ]
  expect_identical(versions_of(current, brkm_cnpj), "3")
  expect_identical(versions_of(current, petr_cnpj), "2")
  expect_true(all(is.na(current$superseded_at)))
  expect_true(all(is.na(current$superseded_by_versao)))
  expect_true(all(is.na(current$id_doc)))
  expect_true(all(is.na(current$motivo_reapresentacao)))

  old <- out[out$history_source != "current", ]
  expect_true(all(old$history_source == "rad"))
  expect_false(anyNA(old$superseded_at))
  expect_false(anyNA(old$id_doc))
  brkm_old <- unique(old[
    old$cnpj_cia == brkm_cnpj,
    c("versao", "superseded_at", "superseded_by_versao")
  ])
  expect_identical(brkm_old$versao, c("1", "2"))
  expect_identical(
    brkm_old$superseded_at,
    as.Date(c("2024-05-14", "2024-07-01"))
  )
  expect_identical(brkm_old$superseded_by_versao, c("2", "3"))
  motivo <- unique(old$motivo_reapresentacao[
    old$cnpj_cia == brkm_cnpj & old$versao == "2"
  ])
  expect_match(motivo, "escala R\\$ mil")
  petr_old <- unique(old[
    old$cnpj_cia == petr_cnpj,
    c("versao", "superseded_at", "superseded_by_versao")
  ])
  expect_identical(petr_old$versao, "1")
  expect_identical(petr_old$superseded_at, as.Date("2024-03-25"))
  expect_identical(petr_old$superseded_by_versao, "2")
})

test_that("the figures of every version are returned as filed", {
  mock <- local_mirror_dre()
  out <- httr2::with_mocked_responses(
    mock,
    cvm_versions("dfp", "dre", year = 2023, basis = "con")
  )
  net <- out[out$cd_conta == "3.11" & out$ordem_exerc == ultimo, ]
  brkm <- net[net$cnpj_cia == brkm_cnpj, ]
  expect_identical(brkm$versao, c("1", "2", "3"))
  expect_identical(brkm$vl_conta, c(-4530000, -4890000000, -4890000000))
  petr <- net[net$cnpj_cia == petr_cnpj, ]
  expect_identical(petr$versao, c("1", "2"))
  expect_identical(petr$vl_conta, c(125166000000, 125166000000))
})

test_that("cvm_versions filters by cnpj and orders by document and version", {
  mock <- local_mirror_dre()
  out <- httr2::with_mocked_responses(
    mock,
    cvm_versions(
      "dfp",
      "dre",
      cnpj = "42150391000170",
      year = 2023,
      basis = "con"
    )
  )
  expect_identical(nrow(out), 24L)
  expect_true(all(out$cnpj_cia == brkm_cnpj))
  expect_false(is.unsorted(as.integer(out$versao)))
  expect_identical(out$basis, rep("con", 24L))
})

test_that("a partition with no history asset gives only the current version", {
  mock <- local_mirror_dre(history = FALSE)
  out <- httr2::with_mocked_responses(
    mock,
    cvm_versions("dfp", "dre", year = 2023, basis = "con")
  )
  expect_identical(nrow(out), 16L)
  expect_true(all(out$history_source == "current"))
  expect_true(all(is.na(out$superseded_at)))
  expect_s3_class(out$superseded_at, "Date")
  expect_true(all(c("id_doc", "motivo_reapresentacao") %in% names(out)))
})

test_that("cvm_fetch keeps ignoring the history asset", {
  mock <- local_mirror_dre()
  out <- httr2::with_mocked_responses(
    mock,
    cvm_fetch("dfp", "dre", year = 2023, basis = "con")
  )
  expect_identical(nrow(out), 16L)
  expect_false(any(c("superseded_at", "history_source") %in% names(out)))
  expect_identical(versions_of(out, brkm_cnpj), "3")
})

# Validation -----------------------------------------------------------

test_that("cvm_versions refuses the row filters of cvm_fetch by name", {
  expect_snapshot(error = TRUE, {
    cvm_versions("dfp", "dre", year = 2023, basis = "con", reading = "original")
  })
  expect_error(
    cvm_versions(
      "dfp",
      "dre",
      basis = "con",
      from = "2023-01-01",
      to = "2023-12-31"
    ),
    class = "cvmdata_error_input"
  )
  expect_error(
    cvm_versions("dfp", "dre", basis = "con", as_of = "2023-12-31"),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_versions rejects unknown arguments", {
  expect_snapshot(error = TRUE, {
    cvm_versions("dfp", "dre", basis = "con", report_type = "con")
  })
})

test_that("cvm_versions rejects a table without version history", {
  expect_snapshot(error = TRUE, {
    cvm_versions("dfp", "submissao", year = 2023)
  })
  expect_error(
    cvm_versions("cad", "companhias"),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_versions requires basis on the split tables", {
  expect_error(
    cvm_versions("dfp", "dre", year = 2023),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_versions refuses a year the table is not published for", {
  expect_error(
    cvm_versions("dfp", "composicao_capital", year = 2015),
    class = "cvmdata_error_input"
  )
})

# CVM ------------------------------------------------------------------

test_that("cvm_versions via cvm reads the yearly file and says it is partial", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache("itr")

  expect_message(
    out <- with_fixture_http(
      cvm_versions(
        "itr",
        "bpa",
        year = 2024,
        basis = "ind",
        source = "cvm"
      )
    ),
    "complete history is on the mirror"
  )
  expect_s3_class(out, "cvm_tbl")
  expect_identical(attr(out, "source"), "cvm")
  expect_identical(
    utils::tail(names(out), 6L),
    c(
      "basis",
      "superseded_at",
      "superseded_by_versao",
      "history_source",
      "id_doc",
      "motivo_reapresentacao"
    )
  )
  expect_s3_class(out$superseded_at, "Date")
  # The fixture carries one version per document (MAGAZINE LUIZA filed
  # the second quarter as version 2 and the others as version 1): every
  # row is the current one.
  expect_true(all(out$history_source == "current"))
  expect_true(all(is.na(out$superseded_by_versao)))
  mglu <- out[out$cnpj_cia == "47.960.950/0001-21", ]
  expect_identical(
    unique(mglu[, c("dt_refer", "versao")])$versao,
    c("1", "2", "1")
  )
})

test_that("cvm_versions via cvm matches cvm_fetch on the current version", {
  skip_if_not_installed("httptest2")
  local_prepare_cvm_cache("itr")

  versions <- suppressMessages(with_fixture_http(
    cvm_versions(
      "itr",
      "bpa",
      cnpj = mglu_cnpj,
      year = 2024,
      basis = "ind",
      source = "cvm"
    )
  ))
  current <- with_fixture_http(
    cvm_fetch(
      "itr",
      "bpa",
      cnpj = mglu_cnpj,
      year = 2024,
      basis = "ind",
      source = "cvm"
    )
  )
  kept <- versions[versions$history_source == "current", names(current)]
  expect_identical(nrow(kept), nrow(current))
  key <- function(df) order(df$dt_refer, df$cd_conta, df$ordem_exerc)
  expect_identical(kept[key(kept), ]$vl_conta, current[key(current), ]$vl_conta)
})

test_that("mark_versions tells the current filing of a CSV from the old ones", {
  # Two versions of one document (the second delivered last), one
  # version of another; the CSV carries neither receipt date nor
  # document id, so the rank falls back to `versao`.
  df <- tibble::tibble(
    cnpj_cia = c(rep("11.111.111/0001-11", 4L), rep("22.222.222/0001-22", 2L)),
    dt_refer = as.Date("2023-12-31"),
    versao = c("1", "1", "2", "2", "1", "1"),
    cd_conta = c("3.01", "3.11", "3.01", "3.11", "3.01", "3.11"),
    vl_conta = c(1, 2, 10, 20, 100, 200)
  )
  out <- cvmdata:::mark_versions(
    df[c(3L, 1L, 5L, 4L, 2L, 6L), ],
    tx = list(action = "keep_latest_version"),
    source = "cvm"
  )
  expect_identical(
    names(out),
    c(names(df), cvmdata:::.version_columns)
  )
  expect_identical(out$versao, c("1", "1", "2", "2", "1", "1"))
  expect_identical(
    out$history_source,
    c("cvm", "cvm", "current", "current", "current", "current")
  )
  expect_identical(
    out$superseded_by_versao,
    c("2", "2", NA, NA, NA, NA)
  )
  expect_true(all(is.na(out$superseded_at)))
  expect_s3_class(out$superseded_at, "Date")
})

test_that("mark_versions keeps the mirror's marks and adds the current one", {
  df <- tibble::tibble(
    cnpj_cia = "11.111.111/0001-11",
    dt_refer = as.Date("2023-12-31"),
    versao = c("2", "1"),
    vl_conta = c(10, 1),
    superseded_at = c(NA, "2024-03-25"),
    superseded_by_versao = c(NA, "2"),
    history_source = c(NA, "rad"),
    id_doc = c(NA, "134555"),
    motivo_reapresentacao = NA_character_
  )
  out <- cvmdata:::mark_versions(
    df,
    tx = list(action = "keep_latest_version"),
    source = "mirror"
  )
  expect_identical(out$versao, c("1", "2"))
  expect_identical(out$history_source, c("rad", "current"))
  expect_identical(out$superseded_at, as.Date(c("2024-03-25", NA)))
})

# Remaining branches ---------------------------------------------------

test_that("cvm_versions resolves a ticker and stacks both bases", {
  cvmdata:::mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir()
  withr::local_options(cvmdata.cache_dir = cache_root)
  # The consolidated fixture stands in for the individual asset too.
  mock <- build_mock(list(
    list(
      name = "dre__report_type.con__year.2023__part-0.parquet",
      parquet = dre_current_fx()
    ),
    list(
      name = "dre__report_type.con__year.2023__history.parquet",
      parquet = dre_history_fx()
    ),
    list(
      name = "dre__report_type.ind__year.2023__part-0.parquet",
      parquet = dre_current_fx()
    )
  ))
  local_mocked_bindings(
    resolve_ticker_all_years = function(tickers, source = "cvm") petr_cnpj
  )
  out <- httr2::with_mocked_responses(
    mock,
    cvm_versions(
      "dfp",
      "dre",
      ticker = "PETR4",
      year = 2023,
      basis = c("ind", "con")
    )
  )
  expect_true(all(out$cnpj_cia == petr_cnpj))
  expect_identical(sum(out$basis == "ind"), 8L)
  expect_identical(sum(out$basis == "con"), 16L)
  expect_true(all(out$history_source[out$basis == "ind"] == "current"))
  expect_identical(utils::tail(names(out), 5L), cvmdata:::.version_columns)
})

test_that("fetch_versions_cvm handles a table without yearly files", {
  schema <- cvmdata:::load_schema("cad", "companhias")
  expect_error(
    cvmdata:::fetch_versions_cvm(schema, NULL, 2024L, NULL, "strict", "abort"),
    class = "cvmdata_error_input"
  )
  local_prepare_cad_cache()
  out <- with_fixture_http(
    cvmdata:::fetch_versions_cvm(schema, NULL, NULL, NULL, "skip", "abort")
  )
  expect_true(nrow(out) > 0L)
  expect_true("cnpj_cia" %in% names(out))
})

test_that("mark_versions copes with empty, keyless and unversioned frames", {
  tx <- list(action = "keep_latest_version")
  empty <- cvmdata:::mark_versions(
    tibble::tibble(cnpj_cia = character(), versao = character()),
    tx,
    "cvm"
  )
  expect_identical(nrow(empty), 0L)
  expect_identical(
    utils::tail(names(empty), 5L),
    cvmdata:::.version_columns
  )
  keyless <- cvmdata:::mark_versions(
    tibble::tibble(versao = c("2", "1"), vl_conta = c(2, 1)),
    tx,
    "cvm"
  )
  expect_identical(keyless$versao, c("1", "2"))
  expect_true(all(keyless$history_source == "current"))
  unversioned <- cvmdata:::mark_versions(
    tibble::tibble(cnpj_cia = "x", dt_refer = as.Date("2023-12-31"), v = 1),
    tx,
    "cvm"
  )
  expect_identical(unversioned$history_source, "current")
})
