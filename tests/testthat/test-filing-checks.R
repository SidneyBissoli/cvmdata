# Filing order and fetch-time filing checks. Rows reproduce the real
# CVM records measured on 2026-10-18 (DFP 2023 and 2024 index files,
# BPA_ind 2023/2024), trimmed to the columns that matter.

travessia_submissao <- function() {
  tibble::tibble(
    cnpj_cia = "43.335.774/0001-86",
    dt_refer = as.Date("2024-12-31"),
    versao = c("1", "2", "1"),
    denom_cia = "TRAVESSIA SECURITIZADORA DE CRÉDITOS MERCANTIS VI S.A.",
    cd_cvm = "026824",
    categ_doc = "DFP",
    id_doc = c("146055", "146255", "151243"),
    dt_receb = as.Date(c("2025-03-31", "2025-04-08", "2025-08-14"))
  )
}

trv_submissao <- function() {
  tibble::tibble(
    cnpj_cia = "40.997.635/0001-20",
    dt_refer = as.Date("2023-12-31"),
    versao = c("1", "1"),
    denom_cia = "TRV XLIII SECURITIZADORA DE CREDITOS MERCANTIS S.A.",
    cd_cvm = "026239",
    categ_doc = "DFP",
    id_doc = c("135670", "135158"),
    dt_receb = as.Date(c("2024-04-12", "2024-03-26"))
  )
}

trv_bpa <- function() {
  one <- tibble::tibble(
    cnpj_cia = "40.997.635/0001-20",
    dt_refer = as.Date("2023-12-31"),
    versao = "1",
    denom_cia = "TRV XLIII SECURITIZADORA DE CREDITOS MERCANTIS S.A.",
    cd_cvm = "026239",
    ordem_exerc = c("ÚLTIMO", "PENÚLTIMO"),
    dt_fim_exerc = as.Date(c("2023-12-31", "2022-12-31")),
    cd_conta = "1",
    ds_conta = "Ativo Total",
    vl_conta = c(127621000, 106772000)
  )
  rbind(one, one)
}

# keep_latest_version ------------------------------------------------

test_that("keep_latest_version keeps the last delivery, not the top versao", {
  out <- cvmdata:::tx_keep_latest_version(
    travessia_submissao(),
    tx = list(action = "keep_latest_version"),
    schema = list(dataset = "dfp", table = "submissao")
  )
  expect_identical(nrow(out), 1L)
  expect_identical(out$id_doc, "151243")
  expect_identical(out$versao, "1")
})

test_that("keep_latest_version breaks a versao tie by delivery", {
  out <- cvmdata:::tx_keep_latest_version(
    trv_submissao(),
    tx = list(action = "keep_latest_version"),
    schema = list(dataset = "dfp", table = "submissao")
  )
  expect_identical(nrow(out), 1L)
  expect_identical(out$id_doc, "135670")
})

test_that("keep_latest_version keeps every row of the chosen filing", {
  df <- tibble::tibble(
    cnpj_companhia = "00.000.000/0001-91",
    data_referencia = as.Date("2024-01-01"),
    versao = c("1", "1", "2", "2"),
    id_documento = c("10", "10", "20", "20"),
    nome = c("a", "b", "a", "b")
  )
  out <- cvmdata:::tx_keep_latest_version(df, list(), list())
  expect_identical(out$id_documento, c("20", "20"))
  expect_identical(out$nome, c("a", "b"))
})

test_that("keep_latest_version orders receipt times within a day", {
  df <- tibble::tibble(
    cnpj_companhia = "x",
    data_referencia = "2024-12-31",
    versao = c("2", "1"),
    data_entrega = c("2025-05-01 09:00:00", "2025-05-01 17:30:00"),
    protocolo_entrega = c("A1", "A2")
  )
  out <- cvmdata:::tx_keep_latest_version(df, list(), list())
  expect_identical(out$protocolo_entrega, "A2")
})

# Duplicate and conflicting filings -----------------------------------

test_that("identical rows of a doubled filing are dropped with a warning", {
  expect_snapshot(
    out <- cvmdata:::drop_duplicate_filings(trv_bpa(), "cnpj_cia", "dt_refer")
  )
  expect_identical(nrow(out), 2L)
  expect_identical(out$vl_conta, c(127621000, 106772000))
})

test_that("duplicate warning carries its class", {
  expect_warning(
    cvmdata:::drop_duplicate_filings(trv_bpa(), "cnpj_cia", "dt_refer"),
    class = "cvmdata_warn_duplicate_filing"
  )
})

test_that("copies that differ in vl_conta are kept and flagged", {
  df <- trv_bpa()
  df$vl_conta[3:4] <- c(1, 2)
  expect_warning(
    out <- cvmdata:::drop_duplicate_filings(df, "cnpj_cia", "dt_refer"),
    class = "cvmdata_warn_conflicting_filing"
  )
  expect_identical(nrow(out), 4L)
})

test_that("a clean table passes untouched", {
  df <- trv_bpa()[1:2, ]
  expect_no_warning(
    out <- cvmdata:::drop_duplicate_filings(df, "cnpj_cia", "dt_refer")
  )
  expect_identical(out, df)
})

# Stale filings -------------------------------------------------------

travessia_bpa_v2 <- function() {
  tibble::tibble(
    cnpj_cia = "43.335.774/0001-86",
    dt_refer = as.Date("2024-12-31"),
    versao = "2",
    denom_cia = "TRAVESSIA SECURITIZADORA DE CRÉDITOS MERCANTIS VI S.A.",
    cd_cvm = "026824",
    ordem_exerc = "ÚLTIMO",
    dt_fim_exerc = as.Date("2024-12-31"),
    cd_conta = "1",
    ds_conta = "Ativo Total",
    vl_conta = 31159000
  )
}

# The mocked index is the raw `submissao`, every delivery listed, as the
# pipeline returns it since the schema stopped collapsing it: the check
# must pick the last delivery of each filing key by itself.
test_that("a table behind the latest delivery is flagged", {
  local_mocked_bindings(
    issuer_fetch_internal = function(...) travessia_submissao()
  )
  expect_snapshot(
    out <- cvmdata:::check_filings(
      travessia_bpa_v2(),
      schema = list(),
      dataset = "dfp",
      table = "bpa",
      year = 2024L,
      source = "cvm",
      validate = "strict"
    )
  )
  expect_identical(out, travessia_bpa_v2())
})

test_that("stale warning carries its class", {
  local_mocked_bindings(
    issuer_fetch_internal = function(...) travessia_submissao()
  )
  expect_warning(
    cvmdata:::check_filings(
      travessia_bpa_v2(),
      schema = list(),
      dataset = "dfp",
      table = "bpa",
      year = NULL,
      source = "cvm",
      validate = "strict"
    ),
    class = "cvmdata_warn_stale_filing"
  )
})

# MAGAZINE LUIZA ITR 2024-06-30 as the CVM index lists it: version 1
# (2024-08-08) before version 2 (2024-08-09). The statement CSV holds
# version 2. Matching the table against the first row of the index
# would flag the current filing as stale.
mglu_submissao <- function() {
  tibble::tibble(
    cnpj_cia = "47.960.950/0001-21",
    dt_refer = as.Date("2024-06-30"),
    versao = c("1", "2"),
    denom_cia = "MAGAZINE LUIZA S.A.",
    cd_cvm = "022470",
    categ_doc = "ITR",
    id_doc = c("140630", "140658"),
    dt_receb = as.Date(c("2024-08-08", "2024-08-09"))
  )
}

test_that("the stale check uses the last delivery, not the first row", {
  local_mocked_bindings(
    issuer_fetch_internal = function(...) mglu_submissao()
  )
  bpa <- travessia_bpa_v2()
  bpa$cnpj_cia <- "47.960.950/0001-21"
  bpa$dt_refer <- as.Date("2024-06-30")
  bpa$denom_cia <- "MAGAZINE LUIZA S.A."
  expect_no_warning(
    out <- cvmdata:::check_filings(
      bpa,
      schema = list(),
      dataset = "itr",
      table = "bpa",
      year = 2024L,
      source = "cvm",
      validate = "strict"
    )
  )
  expect_identical(out, bpa)
})

test_that("an unreachable filing index skips the stale check", {
  local_mocked_bindings(
    issuer_fetch_internal = function(...) {
      cvmdata:::cvmdata_abort("boom", class = "cvmdata_error_http")
    }
  )
  expect_no_warning(
    cvmdata:::check_filings(
      travessia_bpa_v2(),
      schema = list(),
      dataset = "dfp",
      table = "bpa",
      year = 2024L,
      source = "cvm",
      validate = "strict"
    )
  )
})

test_that("check_filings is off under options(cvmdata.check_filings = FALSE)", {
  withr::local_options(cvmdata.check_filings = FALSE)
  local_mocked_bindings(
    issuer_fetch_internal = function(...) stop("must not be called")
  )
  df <- trv_bpa()
  expect_identical(
    cvmdata:::check_filings(
      df,
      schema = list(),
      dataset = "dfp",
      table = "bpa",
      year = 2023L,
      source = "cvm",
      validate = "strict"
    ),
    df
  )
})

test_that("check_filings leaves submissao alone", {
  df <- trv_submissao()
  expect_identical(
    cvmdata:::check_filings(
      df,
      schema = list(),
      dataset = "dfp",
      table = "submissao",
      year = 2023L,
      source = "cvm",
      validate = "strict"
    ),
    df
  )
})
