# Tests for inst/etl/util-rad.R and the pure helpers of
# inst/etl/04-rad-fetch.R: reading a DFP/ITR document of the CVM RAD into
# the package's tables (Part 3b of the versions work, 2026-10).
#
# Pinned here, against five real documents trimmed to a few accounts
# (data-raw/build-rad-test-fixtures.R): both XML layouts, DFP and ITR,
# individual and consolidated; the three number spellings; accounts
# without a description are dropped; only ÚLTIMO and PENÚLTIMO survive;
# the first-quarter duplicate periods collapse into the accumulated
# column; the DMPL labels are positional; the queue, the state and the
# merge into the history asset.

load_etl_rad <- function() {
  for (pkg in c("xml2", "digest", "arrow", "jsonlite", "dplyr")) {
    skip_if_not_installed(pkg)
  }
  env <- parent.frame()
  withr::local_options(cvmdata.etl_testing = TRUE, .local_envir = env)
  scripts <- c(
    "00-config.R",
    "util-hash.R",
    "util-history.R",
    "util-rad.R",
    "04-rad-fetch.R"
  )
  for (script in scripts) {
    installed <- system.file("etl", script, package = "cvmdata")
    path <- if (nzchar(installed)) {
      installed
    } else {
      normalizePath(
        test_path("..", "..", "inst", "etl", script),
        winslash = "/"
      )
    }
    sys.source(path, envir = env)
  }
}

rad_fx <- function(name) {
  test_path("fixtures", paste0(name, ".zip"))
}

filing_row <- function(cnpj, dt_refer, versao, denom, cd_cvm, id_doc) {
  data.frame(
    cnpj_cia = cnpj,
    dt_refer = as.Date(dt_refer),
    versao = versao,
    denom_cia = denom,
    cd_cvm = cd_cvm,
    id_doc = id_doc,
    dt_receb = as.Date(dt_refer) + 60,
    superseded_at = "2025-04-01",
    superseded_by_versao = "2",
    stringsAsFactors = FALSE
  )
}

ultimo <- "ÚLTIMO"
penultimo <- "PENÚLTIMO"

test_that("the three number spellings parse; anything else is NA", {
  load_etl_rad()
  x <- c(
    "14.410",
    "-4.996",
    "1.234.567",
    "31159,0000000000",
    "0,00635",
    "-0,00528",
    "1.234,5",
    "29547.0000000000",
    "",
    "0",
    "12.5",
    "abc"
  )
  expect_equal(
    rad_parse_number(x),
    c(
      14410,
      -4996,
      1234567,
      31159,
      0.00635,
      -0.00528,
      1234.5,
      29547,
      0,
      0,
      NA,
      NA
    )
  )
  expect_identical(rad_scale_factor("2"), 1e3)
  expect_identical(rad_scale_factor("1"), 1)
  expect_true(is.na(rad_scale_factor("7")))
})

test_that("ordem_exerc follows the end date of the period", {
  load_etl_rad()
  refer <- as.Date("2024-09-30")
  fim <- as.Date(c(
    "2024-09-30",
    "2023-12-31",
    "2023-09-30",
    "2022-12-31",
    "2024-12-31"
  ))
  expect_identical(
    rad_ordem(fim, refer),
    c(ultimo, penultimo, penultimo, NA, NA)
  )
  expect_identical(rad_format_cnpj("43335774000186"), "43.335.774/0001-86")
  expect_identical(rad_format_cd_cvm("26824"), "026824")
})

test_that("new layout DFP: package columns, two exercises, index identity", {
  load_etl_rad()
  f <- filing_row(
    "43.335.774/0001-86",
    "2024-12-31",
    "1",
    "TRAVESSIA SECURITIZADORA DE CRÉDITOS MERCANTIS VI S.A.",
    "026824",
    "151243"
  )
  r <- rad_read_zip(rad_fx("rad_dfp_2024_151243"), f)
  expect_identical(r$problems, character())
  expect_identical(r$meta$layout, "new")
  expect_identical(r$meta$dataset, "dfp")
  expect_identical(r$meta$escala, "2")
  expect_identical(r$meta$versao_doc, "1")
  expect_match(r$meta$xml_hash, "^[0-9a-f]{64}$")
  expect_setequal(
    names(r$tables),
    c(
      "bpa/ind",
      "bpp/ind",
      "dre/ind",
      "dra/ind",
      "dfc_mi/ind",
      "dmpl/ind",
      "dva/ind"
    )
  )
  bpa <- r$tables[["bpa/ind"]]
  expect_identical(names(bpa), rad_table_columns("bpa"))
  expect_identical(names(r$tables[["dre/ind"]]), rad_table_columns("dre"))
  expect_identical(names(r$tables[["dmpl/ind"]]), rad_table_columns("dmpl"))
  expect_s3_class(bpa$dt_refer, "Date")
  expect_s3_class(bpa$dt_fim_exerc, "Date")
  expect_type(bpa$vl_conta, "double")
  expect_type(bpa$versao, "character")
  expect_identical(unique(bpa$cnpj_cia), "43.335.774/0001-86")
  expect_identical(unique(bpa$denom_cia), f$denom_cia)
  expect_identical(unique(bpa$cd_cvm), "026824")
  expect_identical(unique(bpa$moeda), "REAL")
  expect_identical(
    unique(bpa$grupo_dfp),
    "DF Individual - Balanço Patrimonial Ativo"
  )
  expect_setequal(unique(bpa$ordem_exerc), c(ultimo, penultimo))
  total <- bpa[bpa$cd_conta == "1", ]
  expect_identical(total$vl_conta[total$ordem_exerc == ultimo], 14410000)
  expect_identical(total$vl_conta[total$ordem_exerc == penultimo], 21340000)
  expect_identical(
    total$dt_fim_exerc[total$ordem_exerc == ultimo],
    as.Date("2024-12-31")
  )
  expect_identical(unique(total$st_conta_fixa), "S")
  # accounts without a description are not in the CSV
  expect_false(any(bpa$ds_conta == ""))
  expect_false("1.01.01.01" %in% bpa$cd_conta)
  dre <- r$tables[["dre/ind"]]
  expect_identical(
    unique(dre$dt_ini_exerc[dre$ordem_exerc == ultimo]),
    as.Date("2024-01-01")
  )
  # per-share accounts keep their fixed parents with value 0
  expect_true("3.99" %in% dre$cd_conta)
  expect_identical(
    unique(dre$st_conta_fixa[grepl("^3\\.99", dre$cd_conta)]),
    "N"
  )
  expect_identical(unique(dre$vl_conta[dre$cd_conta == "3.99"]), 0)
  dmpl <- r$tables[["dmpl/ind"]]
  expect_identical(
    unique(dmpl$coluna_df),
    rad_dmpl_labels[1:6]
  )
  saldo <- dmpl[dmpl$cd_conta == "5.01" & dmpl$ordem_exerc == ultimo, ]
  expect_identical(saldo$vl_conta[saldo$coluna_df == rad_dmpl_labels[1]], 1000)
  expect_identical(
    unique(r$tables[["dfc_mi/ind"]]$grupo_dfp),
    "DF Individual - Demonstração do Fluxo de Caixa (Método Indireto)"
  )
})

test_that("new layout ITR: four DRE periods, per-share decimals, empty con", {
  load_etl_rad()
  f <- filing_row(
    "02.796.775/0001-40",
    "2024-09-30",
    "1",
    "GAMA PARTICIPACOES S.A.",
    "017965",
    "143043"
  )
  r <- rad_read_zip(rad_fx("rad_itr_2024_143043"), f)
  expect_identical(r$problems, character())
  expect_identical(r$meta$dataset, "itr")
  expect_false(any(grepl("/con$", names(r$tables))))
  bpa <- r$tables[["bpa/ind"]]
  expect_identical(
    sort(unique(bpa$dt_fim_exerc)),
    as.Date(c("2023-12-31", "2024-09-30"))
  )
  expect_identical(
    bpa$vl_conta[bpa$cd_conta == "1" & bpa$ordem_exerc == ultimo],
    997000
  )
  dre <- r$tables[["dre/ind"]]
  periods <- unique(dre[, c("ordem_exerc", "dt_ini_exerc", "dt_fim_exerc")])
  expect_identical(nrow(periods), 4L)
  expect_identical(
    periods$dt_ini_exerc[
      periods$ordem_exerc == penultimo &
        periods$dt_fim_exerc == as.Date("2023-09-30")
    ],
    as.Date(c("2023-07-01", "2023-01-01"))
  )
  on <- dre[dre$cd_conta == "3.99.01.01", ]
  expect_equal(
    on$vl_conta[
      on$ordem_exerc == ultimo & on$dt_ini_exerc == as.Date("2024-07-01")
    ],
    6.35
  )
  expect_equal(
    on$vl_conta[
      on$ordem_exerc == ultimo & on$dt_ini_exerc == as.Date("2024-01-01")
    ],
    -26.76
  )
  expect_equal(
    on$vl_conta[
      on$ordem_exerc == penultimo & on$dt_ini_exerc == as.Date("2023-07-01")
    ],
    21.47
  )
  dfc <- r$tables[["dfc_mi/ind"]]
  expect_identical(
    sort(unique(dfc$dt_ini_exerc)),
    as.Date(c("2023-01-01", "2024-01-01"))
  )
  expect_identical(
    sort(unique(dfc$dt_fim_exerc)),
    as.Date(c("2023-09-30", "2024-09-30"))
  )
  dmpl <- r$tables[["dmpl/ind"]]
  expect_identical(
    sort(unique(dmpl$dt_fim_exerc)),
    as.Date(c("2023-09-30", "2024-09-30"))
  )
})

test_that("old layout DFP: dot-decimal numbers, direct cash flow", {
  load_etl_rad()
  f <- filing_row(
    "00.866.577/0001-80",
    "2011-12-31",
    "1",
    "SAUIPE SA",
    "015261",
    "15513"
  )
  r <- rad_read_zip(rad_fx("rad_dfp_2011_15513"), f)
  expect_identical(r$problems, character())
  expect_identical(r$meta$layout, "old")
  expect_identical(r$meta$dataset, "dfp")
  expect_true("dfc_md/ind" %in% names(r$tables))
  expect_false("dfc_mi/ind" %in% names(r$tables))
  bpa <- r$tables[["bpa/ind"]]
  expect_identical(names(bpa), rad_table_columns("bpa"))
  expect_setequal(unique(bpa$ordem_exerc), c(ultimo, penultimo))
  expect_identical(
    bpa$vl_conta[bpa$cd_conta == "1" & bpa$ordem_exerc == ultimo],
    29547000
  )
  expect_identical(
    bpa$vl_conta[bpa$cd_conta == "1" & bpa$ordem_exerc == penultimo],
    24693000
  )
  expect_false(as.Date("2009-12-31") %in% bpa$dt_fim_exerc)
  dmpl <- r$tables[["dmpl/ind"]]
  expect_identical(unique(dmpl$coluna_df), rad_dmpl_labels[1:6])
  saldo <- dmpl[dmpl$cd_conta == "5.01" & dmpl$ordem_exerc == penultimo, ]
  expect_identical(
    saldo$vl_conta[saldo$coluna_df == rad_dmpl_labels[1]],
    47142000
  )
  expect_identical(
    saldo$vl_conta[saldo$coluna_df == rad_dmpl_labels[4]],
    -56944000
  )
  expect_identical(unique(saldo$dt_ini_exerc), as.Date("2010-01-01"))
})

test_that("old layout ITR, first quarter: duplicate periods collapse", {
  load_etl_rad()
  f <- filing_row(
    "02.162.616/0001-94",
    "2012-03-31",
    "1",
    "UPTICK PARTICIPACOES SA",
    "016624",
    "17509"
  )
  r <- rad_read_zip(rad_fx("rad_itr_2012_17509"), f)
  expect_identical(r$problems, character())
  expect_identical(r$meta$dataset, "itr")
  dre <- r$tables[["dre/ind"]]
  periods <- unique(dre[, c("ordem_exerc", "dt_ini_exerc", "dt_fim_exerc")])
  expect_identical(nrow(periods), 2L)
  expect_identical(
    as.integer(table(dre$cd_conta)),
    rep(2L, length(unique(dre$cd_conta)))
  )
  expect_identical(
    sort(unique(dre$dt_fim_exerc)),
    as.Date(c("2011-03-31", "2012-03-31"))
  )
  bpa <- r$tables[["bpa/ind"]]
  expect_identical(
    bpa$vl_conta[bpa$cd_conta == "1" & bpa$ordem_exerc == ultimo],
    76902000
  )
  expect_identical(
    bpa$vl_conta[bpa$cd_conta == "1" & bpa$ordem_exerc == penultimo],
    72916000
  )
  expect_identical(
    bpa$dt_fim_exerc[bpa$cd_conta == "1" & bpa$ordem_exerc == penultimo],
    as.Date("2011-12-31")
  )
  expect_true("dfc_mi/ind" %in% names(r$tables))
  dmpl <- r$tables[["dmpl/ind"]]
  saldo <- dmpl[dmpl$cd_conta == "5.01" & dmpl$ordem_exerc == ultimo, ]
  expect_identical(
    saldo$vl_conta[saldo$coluna_df == rad_dmpl_labels[6]],
    70365000
  )
})

test_that("old layout with consolidated: DMPL labels are positional", {
  load_etl_rad()
  f <- filing_row(
    "92.702.067/0001-96",
    "2011-12-31",
    "1",
    "BCO ESTADO DO RIO GRANDE DO SUL S.A.",
    "001210",
    "14281"
  )
  r <- rad_read_zip(rad_fx("rad_dfp_2011_14281"), f)
  expect_identical(r$problems, character())
  expect_true(all(
    c("bpa/ind", "bpa/con", "dre/con", "dmpl/con") %in% names(r$tables)
  ))
  expect_identical(
    unique(r$tables[["bpa/con"]]$grupo_dfp),
    "DF Consolidado - Balanço Patrimonial Ativo"
  )
  ind <- r$tables[["dmpl/ind"]]
  expect_identical(unique(ind$coluna_df), rad_dmpl_labels[1:7])
  saldo <- ind[ind$cd_conta == "5.01" & ind$ordem_exerc == penultimo, ]
  # the seventh column of the individual DMPL is labelled as the CSV does
  expect_identical(
    saldo$vl_conta[saldo$coluna_df == rad_dmpl_labels[7]],
    3408462000
  )
  expect_identical(
    saldo$vl_conta[saldo$coluna_df == rad_dmpl_labels[4]],
    808138000
  )
  con <- r$tables[["dmpl/con"]]
  expect_identical(unique(con$coluna_df), rad_dmpl_labels)
  saldo <- con[con$cd_conta == "5.01" & con$ordem_exerc == penultimo, ]
  expect_identical(
    saldo$vl_conta[saldo$coluna_df == rad_dmpl_labels[8]],
    3533276000
  )
  expect_identical(
    saldo$vl_conta[saldo$coluna_df == rad_dmpl_labels[3]],
    808138000
  )
})

test_that("old layout of a bank: nine consolidated DMPL columns", {
  load_etl_rad()
  # Banrisul DFP 2021 v1 (id 111777), set aside on 2026-10-23 as
  # "dmpl/con: 9 DMPL columns": the old layout stopped at the eight
  # labels, but a bank's consolidated DMPL carries the three-way equity
  # split in columns 7-9, already in the converter's order (controlling,
  # non-controlling, consolidated), the ninth without label. Measured
  # against the DFP 2021 CSV (the v2): the 2020 opening balances of the
  # consolidated DMPL agree in all nine columns, the individual in all
  # seven. This v1 has no consolidated DMPL for 2021 at all (periods 2
  # and 3 only), which is the document's doing, not the reader's.
  f <- filing_row(
    "92.702.067/0001-96",
    "2021-12-31",
    "1",
    "BCO ESTADO DO RIO GRANDE DO SUL S.A.",
    "001210",
    "111777"
  )
  r <- rad_read_zip(rad_fx("rad_dfp_2021_111777"), f)
  expect_identical(r$problems, character())
  expect_false(r$index_mismatch)
  ind <- r$tables[["dmpl/ind"]]
  expect_identical(unique(ind$coluna_df), rad_dmpl_labels[1:7])
  saldo <- ind[ind$cd_conta == "5.01" & ind$ordem_exerc == penultimo, ]
  expect_identical(
    saldo$vl_conta[saldo$coluna_df == rad_dmpl_labels[7]],
    7792367000
  )
  con <- r$tables[["dmpl/con"]]
  expect_identical(unique(con$coluna_df), c(rad_dmpl_labels, NA))
  expect_identical(unique(con$ordem_exerc), penultimo)
  saldo <- con[con$cd_conta == "5.01", ]
  expect_identical(
    saldo$vl_conta[saldo$coluna_df %in% rad_dmpl_labels[1:3]],
    c(5200000000, 4511000, 2773279000)
  )
  expect_identical(
    saldo$vl_conta[saldo$coluna_df %in% rad_dmpl_labels[7:8]],
    c(7804535000, 1995000)
  )
  expect_identical(saldo$vl_conta[is.na(saldo$coluna_df)], 7806530000)
  # the unlabelled ninth column is the sum of the two before it
  expect_identical(
    sum(saldo$vl_conta[saldo$coluna_df %in% rad_dmpl_labels[7:8]]),
    saldo$vl_conta[is.na(saldo$coluna_df)]
  )
})

test_that("a text node above libxml2's 10 MB limit is read whole", {
  load_etl_rad()
  # the embedded PDF of a RAD document is one base64 text node; five
  # DFP 2025 documents of 2026-10-20 (e.g. REVEE, id 155949) carry one
  # above 10 MB, which libxml2 2.9 refuses as "Extra content at the end
  # of the document" and libxml2 2.12 truncates with a warning
  path <- withr::local_tempfile(fileext = ".xml")
  blob <- strrep("QUJD", 2750000L) # 11 MB of base64
  writeLines(
    c(
      "<?xml version=\"1.0\" encoding=\"utf-8\"?>",
      "<XmlDemonstracoesFinanceiras><DadosDFP><AnexosDocumento>",
      paste0("<ImagemObjetoArquivoPdf>", blob, "</ImagemObjetoArquivoPdf>"),
      "</AnexosDocumento><DataReferencia>31/12/2025</DataReferencia>",
      "</DadosDFP></XmlDemonstracoesFinanceiras>"
    ),
    path
  )
  doc <- expect_no_condition(rad_read_xml(path))
  expect_identical(
    nchar(xml_text1(doc, "./DadosDFP/AnexosDocumento/ImagemObjetoArquivoPdf")),
    11000000L
  )
  expect_identical(xml_text1(doc, "./DadosDFP/DataReferencia"), "31/12/2025")
})

test_that("new layout of a bank: DMPL columns follow the converter's order", {
  load_etl_rad()
  f <- filing_row(
    "28.127.603/0001-78",
    "2025-12-31",
    "1",
    "BANESTES S.A. - BCO EST ESPIRITO SANTO",
    "001155",
    "154846"
  )
  r <- rad_read_zip(rad_fx("rad_dfp_2025_154846"), f)
  expect_identical(r$problems, character())
  # individual: seven elements, `AjustesAvaliacaoPatrimonial` fourth, so
  # the CSV writes the adjustments under "Lucros ou Prejuízos Acumulados"
  # and the equity total under "Participação dos Não Controladores"
  ind <- r$tables[["dmpl/ind"]]
  expect_identical(unique(ind$coluna_df), rad_dmpl_labels[1:7])
  saldo <- ind[ind$cd_conta == "5.01" & ind$ordem_exerc == ultimo, ]
  expect_identical(
    saldo$vl_conta[saldo$coluna_df == rad_dmpl_labels[1]],
    1600000000
  )
  expect_identical(
    saldo$vl_conta[saldo$coluna_df == rad_dmpl_labels[4]],
    -31429000
  )
  expect_identical(
    saldo$vl_conta[saldo$coluna_df == rad_dmpl_labels[7]],
    2357214000
  )
  # consolidated: nine elements; the controlling shareholders' equity is
  # column 7, the non-controlling interest column 8 and the consolidated
  # total the unlabelled ninth, although the XML writes the total before
  # the non-controlling interest
  con <- r$tables[["dmpl/con"]]
  expect_identical(unique(con$coluna_df), c(rad_dmpl_labels, NA))
  saldo <- con[con$cd_conta == "5.01" & con$ordem_exerc == ultimo, ]
  expect_identical(
    saldo$vl_conta[which(saldo$coluna_df == rad_dmpl_labels[7])],
    2313548000
  )
  expect_identical(
    saldo$vl_conta[which(saldo$coluna_df == rad_dmpl_labels[8])],
    0
  )
  expect_identical(saldo$vl_conta[is.na(saldo$coluna_df)], 2313548000)
})

test_that("new layout, other bank template: DMPL columns follow the document", {
  load_etl_rad()
  f <- filing_row(
    "30.306.294/0001-45",
    "2025-12-31",
    "1",
    "BCO BTG PACTUAL S.A.",
    "022616",
    "154641"
  )
  r <- rad_read_zip(rad_fx("rad_dfp_2025_154641"), f)
  expect_identical(r$problems, character())
  # individual: seven elements in the document's order, `ReservasReavaliacao`
  # third and `AjustesAvaliacaoPatrimonial` AFTER `LucroPrejuizoAcumulado`,
  # the reverse of Banestes; the CSV follows the document, so the retained
  # earnings column carries the profit reserves and the equity column the
  # adjustments (measured against the DFP 2025 CSV, zero differences)
  ind <- r$tables[["dmpl/ind"]]
  expect_identical(unique(ind$coluna_df), rad_dmpl_labels[1:7])
  saldo <- ind[ind$cd_conta == "5.01" & ind$ordem_exerc == ultimo, ]
  expect_identical(
    saldo$vl_conta[saldo$coluna_df == rad_dmpl_labels[1]],
    15760364000
  )
  expect_identical(saldo$vl_conta[saldo$coluna_df == rad_dmpl_labels[3]], 0)
  expect_identical(
    saldo$vl_conta[saldo$coluna_df == rad_dmpl_labels[4]],
    40185539000
  )
  expect_identical(saldo$vl_conta[saldo$coluna_df == rad_dmpl_labels[5]], 0)
  expect_identical(
    saldo$vl_conta[saldo$coluna_df == rad_dmpl_labels[6]],
    1502059000
  )
  expect_identical(
    saldo$vl_conta[saldo$coluna_df == rad_dmpl_labels[7]],
    57466518000
  )
  # consolidated: the positional variant (`DadosContas`), eight fields
  con <- r$tables[["dmpl/con"]]
  expect_identical(unique(con$coluna_df), rad_dmpl_labels)
  saldo <- con[con$cd_conta == "5.01" & con$ordem_exerc == penultimo, ]
  expect_identical(
    saldo$vl_conta[saldo$coluna_df == rad_dmpl_labels[8]],
    56388167000
  )
})

test_that("an unmeasured DMPL element sets the document aside", {
  load_etl_rad()
  f <- filing_row(
    "30.306.294/0001-45",
    "2025-12-31",
    "1",
    "BCO BTG PACTUAL S.A.",
    "022616",
    "154641"
  )
  tmp <- withr::local_tempdir()
  utils::unzip(rad_fx("rad_dfp_2025_154641"), exdir = tmp)
  xml <- list.files(tmp, pattern = "DFP.*[.]xml$", full.names = TRUE)
  txt <- readLines(xml, encoding = "UTF-8", warn = FALSE)
  txt <- gsub("ReservasReavaliacao", "ReservasInventadas", txt, fixed = TRUE)
  writeLines(txt, xml, useBytes = TRUE)
  zip <- file.path(tmp, "154641.zip")
  withr::with_dir(tmp, utils::zip(zip, basename(xml), flags = "-q"))
  r <- rad_read_zip(zip, f)
  expect_match(r$problems, "dmpl/ind: unknown DMPL columns ReservasInventadas")
  expect_false("dmpl/ind" %in% names(r$tables))
})

test_that("a document that does not match its index row is set aside", {
  load_etl_rad()
  f <- filing_row(
    "00.000.000/0001-91",
    "2024-12-31",
    "1",
    "OUTRA",
    "000001",
    "151243"
  )
  r <- rad_read_zip(rad_fx("rad_dfp_2024_151243"), f)
  expect_length(r$problems, 1L)
  expect_match(r$problems, "cnpj in the document")
  # without an index row the identity comes from the document
  r <- rad_read_zip(rad_fx("rad_dfp_2024_151243"))
  expect_identical(r$problems, character())
  expect_identical(r$meta$cnpj_cia, "43.335.774/0001-86")
  expect_identical(r$meta$cd_cvm, "026824")
})

test_that("rad_compare tells identical tables from changed ones", {
  load_etl_rad()
  f <- filing_row(
    "00.866.577/0001-80",
    "2011-12-31",
    "1",
    "SAUIPE SA",
    "015261",
    "15513"
  )
  bpa <- rad_read_zip(rad_fx("rad_dfp_2011_15513"), f)$tables[["bpa/ind"]]
  expect_true(rad_compare(bpa, bpa)$ok)
  changed <- bpa
  changed$vl_conta[1] <- changed$vl_conta[1] + 1000
  cmp <- rad_compare(bpa, changed)
  expect_false(cmp$ok)
  expect_identical(nrow(cmp$value_diff), 1L)
  cmp <- rad_compare(bpa, bpa[-1, ])
  expect_identical(nrow(cmp$only_rad), 1L)
})

test_that("the queue holds the superseded deliveries, newest year first", {
  load_etl_rad()
  index <- data.frame(
    cnpj_cia = c("A", "A", "A", "B", "C", "C"),
    dt_refer = as.Date(c(
      "2024-12-31",
      "2024-12-31",
      "2024-12-31",
      "2024-12-31",
      "2023-12-31",
      "2023-12-31"
    )),
    versao = c("1", "2", "1", "1", "1", "2"),
    denom_cia = c("A", "A", "A", "B", "C", "C"),
    cd_cvm = "000001",
    id_doc = c("10", "11", "12", "20", "30", "31"),
    dt_receb = as.Date(c(
      "2025-03-01",
      "2025-03-10",
      "2025-08-01",
      "2025-03-01",
      "2024-03-01",
      "2024-03-05"
    )),
    stringsAsFactors = FALSE
  )
  state <- rad_empty_state("dfp")
  q <- rad_queue(index, state)
  expect_identical(q$id_doc, c("11", "10", "30"))
  expect_identical(q$superseded_at, c("2025-08-01", "2025-03-10", "2024-03-05"))
  expect_identical(q$superseded_by_versao, c("1", "2", "2"))
  state$done[["11"]] <- list(hash = "x")
  state$unread[["10"]] <- list(
    reason = "r",
    attempts = 3L,
    reader = rad_reader_id
  )
  expect_identical(rad_queue(index, state)$id_doc, "30")
  # the attempts of an earlier reader do not spend the document
  state$unread[["10"]]$reader <- "0ld"
  expect_identical(rad_queue(index, state)$id_doc, c("10", "30"))
  state$unread[["10"]]$reader <- NULL
  expect_identical(rad_queue(index, state)$id_doc, c("10", "30"))
  expect_identical(
    rad_queue(index, rad_empty_state("dfp"), year = 2023)$id_doc,
    "30"
  )
})

test_that("history rows carry the RAD columns and merge once per version", {
  load_etl_rad()
  f <- filing_row(
    "00.866.577/0001-80",
    "2011-12-31",
    "1",
    "SAUIPE SA",
    "015261",
    "15513"
  )
  r <- rad_read_zip(rad_fx("rad_dfp_2011_15513"), f)
  rows <- rad_history_rows(r$tables, f, r$meta)
  bpa <- rows[["bpa/ind"]]
  expect_identical(unique(bpa$superseded_at), "2025-04-01")
  expect_identical(unique(bpa$superseded_by_versao), "2")
  expect_identical(unique(bpa$history_source), "rad")
  expect_identical(unique(bpa$id_doc), "15513")
  expect_true(all(is.na(bpa$motivo_reapresentacao)))
  expect_identical(
    rad_history_rel("bpa/ind", as.Date("2011-12-31")),
    "bpa/report_type=ind/year=2011/history.parquet"
  )
  # first append
  m <- rad_merge_history(NULL, bpa)
  expect_identical(m$n_added, nrow(bpa))
  # the same document again adds nothing
  m2 <- rad_merge_history(m$history, bpa)
  expect_identical(m2$n_added, 0L)
  expect_identical(nrow(m2$history), nrow(bpa))
  # a mirror-path history without history_source is labelled, and a
  # version it already holds is not written twice
  prev <- bpa[, setdiff(
    names(bpa),
    c("history_source", "id_doc", "motivo_reapresentacao")
  )]
  m3 <- rad_merge_history(prev, bpa)
  expect_identical(unique(m3$history$history_source), "mirror")
  expect_identical(m3$n_skipped, nrow(bpa))
  other <- bpa
  other$versao <- "3"
  other$id_doc <- "99"
  m4 <- rad_merge_history(prev, other)
  expect_identical(m4$n_added, nrow(bpa))
  expect_setequal(unique(m4$history$history_source), c("mirror", "rad"))
})

test_that("the state round-trips and the unread list is legible", {
  load_etl_rad()
  state <- rad_empty_state("dfp")
  state <- rad_mark_unread(state, "77", "HTTP 500")
  state <- rad_mark_unread(state, "77", "HTTP 500")
  expect_identical(state$unread[["77"]]$attempts, 2L)
  expect_identical(state$unread[["77"]]$reader, rad_reader_id)
  expect_match(rad_reader_id, "^[0-9a-f]{12}$")
  # a document refused by an earlier reader starts its attempts over
  state$unread[["77"]]$reader <- "0ld"
  state <- rad_mark_unread(state, "77", "HTTP 500")
  expect_identical(state$unread[["77"]]$attempts, 1L)
  state <- rad_mark_unread(state, "77", "HTTP 500")
  expect_identical(state$unread[["77"]]$attempts, 2L)
  state$done[["15513"]] <- list(hash = "abc", rows = 10L)
  path <- withr::local_tempfile(fileext = ".json")
  rad_write_state(state, path)
  back <- rad_read_state(path, "dfp")
  expect_identical(back$unread[["77"]]$attempts, 2L)
  expect_identical(back$done[["15513"]]$hash, "abc")
  index <- data.frame(
    cnpj_cia = "X",
    dt_refer = as.Date("2024-12-31"),
    versao = "1",
    denom_cia = "X SA",
    cd_cvm = "1",
    id_doc = "77",
    dt_receb = as.Date("2025-01-01"),
    stringsAsFactors = FALSE
  )
  tab <- rad_unread_table(back, index)
  expect_identical(tab$id_doc, "77")
  expect_identical(tab$denom_cia, "X SA")
  expect_identical(tab$reason, "HTTP 500")
  expect_identical(nrow(rad_unread_table(rad_empty_state("dfp"), index)), 0L)
})

test_that("the command line of stage 04 parses", {
  load_etl_rad()
  opts <- rad_parse_args(c(
    "--dataset",
    "itr",
    "--limit",
    "5",
    "--year",
    "2024",
    "--dry-run"
  ))
  expect_identical(opts$dataset, "itr")
  expect_identical(opts$limit, 5L)
  expect_identical(opts$year, 2024L)
  expect_true(opts$dry_run)
  expect_identical(opts$group, "companhias")
  expect_identical(rad_parse_args(character())$limit, 300L)
})

test_that("plain integers parse and free text follows the CVM converter", {
  load_etl_rad()
  expect_equal(
    rad_parse_number(c("1461169", "-73961", "   ")),
    c(1461169, -73961, 0)
  )
  expect_identical(
    rad_csv_text(c(
      "Outros créditos ",
      " Variação",
      "Ativo setorial \n",
      "Almoxarifado\n\n",
      "Depósitos\r\n",
      "x\ty"
    )),
    c(
      "Outros créditos",
      "Variação",
      "Ativo setorial ",
      "Almoxarifado",
      "Depósitos",
      "xy"
    )
  )
})

test_that("free text follows the Latin-1 CSV: dashes, tabs, 100 chars", {
  load_etl_rad()
  expect_identical(
    rad_csv_text(c(
      "Hedge – fluxo",
      "Provisões ambientais \t",
      "19\tProvisões",
      strrep("a", 120)
    )),
    c(
      "Hedge - fluxo",
      "Provisões ambientais ",
      "19Provisões",
      strrep("a", 100)
    )
  )
})

test_that("a checkpoint replaces the record of its own run, not another", {
  load_etl_rad()
  state <- rad_empty_state("dfp")
  state <- rad_record_run(state, list(at = "2026-11-01T02:00:00Z", read = 50L))
  state <- rad_record_run(state, list(at = "2026-11-01T02:00:00Z", read = 100L))
  expect_length(state$runs, 1L)
  expect_identical(state$runs[[1L]]$read, 100L)
  state <- rad_record_run(state, list(at = "2026-11-02T02:00:00Z", read = 10L))
  expect_length(state$runs, 2L)
  expect_identical(state$runs[[1L]]$at, "2026-11-02T02:00:00Z")
  expect_length(rad_record_run(state, list(at = "x"), keep = 2L)$runs, 2L)
})

# A refusal by the WAF is retried after a pause (decision of 2026-10-22:
# one refusal in a good run of 74 turned the job red, and the document
# downloaded whole hours later). The download is replaced below: the
# scripts are sourced into this environment, so a `rad_download` defined
# here is the one `rad_fetch_one()` finds.
waf_download <- function(answers, fixture) {
  tally <- new.env()
  tally$calls <- 0L
  download <- function(id_doc, dest, timeout = 180) {
    tally$calls <- tally$calls + 1L
    answer <- answers[[min(tally$calls, length(answers))]]
    if (identical(answer, "zip")) {
      file.copy(rad_fx(fixture), dest, overwrite = TRUE)
      return(list(
        ok = TRUE,
        status = 200L,
        bytes = file.size(dest),
        seconds = 1,
        error = NA_character_
      ))
    }
    if (identical(answer, "html")) {
      return(list(
        ok = FALSE,
        status = 200L,
        bytes = 1024,
        seconds = 1,
        error = "body is not a ZIP (WAF page?)"
      ))
    }
    if (identical(answer, "403")) {
      return(list(
        ok = FALSE,
        status = 403L,
        bytes = NA_real_,
        seconds = 1,
        error = "HTTP 403"
      ))
    }
    list(
      ok = FALSE,
      status = 500L,
      bytes = NA_real_,
      seconds = 1,
      error = "HTTP 500"
    )
  }
  list(download = download, calls = function() tally$calls)
}

test_that("one refusal by the WAF is retried and the document is read", {
  load_etl_rad()
  fake <- waf_download(c("html", "zip"), "rad_dfp_2024_151243")
  rad_download <- fake$download
  f <- filing_row(
    "43.335.774/0001-86",
    "2024-12-31",
    "1",
    "TRAVESSIA SECURITIZADORA DE CRÉDITOS MERCANTIS VI S.A.",
    "026824",
    "151243"
  )
  work <- withr::local_tempdir()
  expect_message(
    got <- rad_fetch_one(f, work, pause = 0),
    "refused by the RAD .*pausing 0s before try 2 of 3"
  )
  expect_true(got$ok)
  expect_false(got$waf)
  expect_identical(fake$calls(), 2L)
  expect_gt(got$done$rows, 0L)
})

test_that("a document refused every time stops the run as WAF", {
  load_etl_rad()
  fake <- waf_download(c("html", "403", "html"), "rad_dfp_2024_151243")
  rad_download <- fake$download
  f <- filing_row("A", "2024-12-31", "1", "A", "1", "1")
  work <- withr::local_tempdir()
  got <- suppressMessages(rad_fetch_one(f, work, pause = 0))
  expect_false(got$ok)
  expect_true(got$waf)
  expect_identical(fake$calls(), 3L)
  expect_match(got$note, "refused 3 times")
})

test_that("a failure that is not a refusal is not retried", {
  load_etl_rad()
  fake <- waf_download("500", "rad_dfp_2024_151243")
  rad_download <- fake$download
  f <- filing_row("A", "2024-12-31", "1", "A", "1", "1")
  work <- withr::local_tempdir()
  got <- rad_fetch_one(f, work, pause = 0)
  expect_false(got$ok)
  expect_false(got$waf)
  expect_identical(got$note, "HTTP 500")
  expect_identical(fake$calls(), 1L)
})

test_that("the queue stops on a persistent refusal, not on a transient one", {
  load_etl_rad()
  f <- filing_row(c("A", "B"), "2024-12-31", "1", c("A", "B"), "1", c("1", "2"))
  state <- rad_empty_state("dfp")
  seen <- new.env()
  seen$ids <- character()
  rad_fetch_one <- function(f, work, ...) {
    seen$ids <- c(seen$ids, f$id_doc)
    if (f$id_doc == "1") {
      list(ok = FALSE, waf = TRUE, note = "HTTP 403, refused 3 times")
    } else {
      list(ok = TRUE, waf = FALSE, note = "read", rows = list(), done = list())
    }
  }
  rad_crawl_delay <- 0
  run <- suppressMessages(rad_run_queue(
    f,
    state,
    withr::local_tempdir(),
    limit = 2L,
    minutes = 10,
    Sys.time()
  ))
  expect_identical(run$stopped, "waf")
  expect_identical(seen$ids, "1")
  expect_identical(run$failed, 1L)
  expect_identical(names(run$state$unread), "1")
})

# Every failure carries a kind, and only the reader's kind weighs on the
# failure rate (decision of 2026-10-23: a run of 16 stopped with one
# connection reset and one document whose cnpj differed from the index).
test_that("a download failure and a mismatched document are not the reader's", {
  load_etl_rad()
  work <- withr::local_tempdir()
  fake <- waf_download("500", "rad_dfp_2024_151243")
  rad_download <- fake$download
  got <- rad_fetch_one(filing_row("A", "2024-12-31", "1", "A", "1", "1"), work)
  expect_identical(got$kind, "download")
  # the ZIP arrives whole but is not the document the index describes
  fake <- waf_download("zip", "rad_dfp_2024_151243")
  rad_download <- fake$download
  f <- filing_row(
    "00.000.000/0001-91",
    "2024-12-31",
    "1",
    "OUTRA",
    "1",
    "151243"
  )
  got <- rad_fetch_one(f, work)
  expect_false(got$ok)
  expect_identical(got$kind, "document")
  expect_match(got$note, "cnpj in the document")
  # the right document, read whole
  f <- filing_row(
    "43.335.774/0001-86",
    "2024-12-31",
    "1",
    "TRAVESSIA SECURITIZADORA DE CRÉDITOS MERCANTIS VI S.A.",
    "026824",
    "151243"
  )
  got <- rad_fetch_one(f, work)
  expect_true(got$ok)
  expect_identical(got$kind, NA_character_)
})

test_that("a document the reader cannot make sense of is the reader's", {
  load_etl_rad()
  f <- filing_row(
    "30.306.294/0001-45",
    "2025-12-31",
    "1",
    "BCO BTG PACTUAL S.A.",
    "022616",
    "154641"
  )
  tmp <- withr::local_tempdir()
  utils::unzip(rad_fx("rad_dfp_2025_154641"), exdir = tmp)
  xml <- list.files(tmp, pattern = "DFP.*[.]xml$", full.names = TRUE)
  txt <- readLines(xml, encoding = "UTF-8", warn = FALSE)
  txt <- gsub("ReservasReavaliacao", "ReservasInventadas", txt, fixed = TRUE)
  writeLines(txt, xml, useBytes = TRUE)
  bad <- file.path(tmp, "bad.zip")
  withr::with_dir(tmp, utils::zip(bad, basename(xml), flags = "-q"))
  rad_download <- function(id_doc, dest, timeout = 180) {
    file.copy(bad, dest, overwrite = TRUE)
    list(
      ok = TRUE,
      status = 200L,
      bytes = 1,
      seconds = 1,
      error = NA_character_
    )
  }
  got <- rad_fetch_one(f, withr::local_tempdir())
  expect_false(got$ok)
  expect_identical(got$kind, "reader")
  expect_match(got$note, "unknown DMPL columns")
})

test_that("a ZIP that is not a DFP/ITR is set aside as a document", {
  load_etl_rad()
  # the ITR 2023 index lists id 132214 as one of the two deliveries of
  # Dibens Leasing for 2023-09-30 (the other, 132223, is the ITR); the
  # RAD serves an IPE under that number. Until 2026-10-23 the reader
  # crashed on its empty meta ("missing value where TRUE/FALSE needed")
  # and the failure was counted as the reader's.
  f <- filing_row(
    "65.654.303/0001-73",
    "2023-09-30",
    "1",
    "DIBENS LEASING S.A. - ARREND.MERCANTIL",
    "014214",
    "132214"
  )
  r <- expect_no_error(rad_read_zip(rad_fx("rad_ipe_2023_132214"), f))
  expect_identical(r$problems, "unknown XML root: Documento")
  expect_identical(r$kind, "document")
  expect_identical(r$tables, list())
  expect_false(r$index_mismatch)
  rad_download <- function(id_doc, dest, timeout = 180) {
    file.copy(rad_fx("rad_ipe_2023_132214"), dest, overwrite = TRUE)
    list(
      ok = TRUE,
      status = 200L,
      bytes = 1,
      seconds = 1,
      error = NA_character_
    )
  }
  got <- rad_fetch_one(f, withr::local_tempdir())
  expect_false(got$ok)
  expect_identical(got$kind, "document")
  expect_match(got$note, "unknown XML root: Documento")
})

# A stand-in for `rad_fetch_one()` that fails the documents named in
# `fails` (id_doc -> kind) and reads the others.
fetch_by_kind <- function(fails) {
  function(f, work, ...) {
    kind <- fails[[f$id_doc]]
    if (is.null(kind)) {
      list(
        ok = TRUE,
        waf = FALSE,
        kind = NA_character_,
        note = "read",
        rows = list(),
        done = list()
      )
    } else {
      list(ok = FALSE, waf = FALSE, kind = kind, note = paste("failed:", kind))
    }
  }
}

queue_of <- function(n) {
  ids <- as.character(seq_len(n))
  filing_row(ids, "2024-12-31", "1", ids, "1", ids)
}

test_that("download and document failures do not weigh on the failure rate", {
  load_etl_rad()
  rad_fetch_one <- fetch_by_kind(list("2" = "download", "3" = "document"))
  rad_crawl_delay <- 0
  rad_failure_floor <- 4L
  run <- suppressMessages(rad_run_queue(
    queue_of(6),
    rad_empty_state("dfp"),
    withr::local_tempdir(),
    limit = 6L,
    minutes = 10,
    Sys.time()
  ))
  expect_identical(run$stopped, NA_character_)
  expect_identical(run$attempted, 6L)
  expect_identical(run$failed, 2L)
  expect_identical(run$reader_failed, 0L)
  expect_identical(run$state$unread[["2"]]$kind, "download")
  expect_identical(run$state$unread[["3"]]$kind, "document")
  tab <- rad_unread_table(run$state, queue_of(6))
  expect_identical(tab$kind, c("download", "document"))
})

test_that("the reader's failures stop the run, but only past the floor", {
  load_etl_rad()
  rad_crawl_delay <- 0
  rad_fetch_one <- fetch_by_kind(list("2" = "reader", "4" = "reader"))
  # floor not reached: 2 of 6 (33%) is tolerated
  run <- suppressMessages(rad_run_queue(
    queue_of(6),
    rad_empty_state("dfp"),
    withr::local_tempdir(),
    limit = 6L,
    minutes = 10,
    Sys.time()
  ))
  expect_identical(run$stopped, NA_character_)
  expect_identical(run$reader_failed, 2L)
  # floor reached: the run stops at the failure that crosses the rate
  rad_failure_floor <- 4L
  msgs <- character()
  run <- withCallingHandlers(
    rad_run_queue(
      queue_of(6),
      rad_empty_state("dfp"),
      withr::local_tempdir(),
      limit = 6L,
      minutes = 10,
      Sys.time()
    ),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  expect_match(
    msgs,
    "the reader failed on 2 of 4 documents: stopping",
    all = FALSE
  )
  expect_identical(run$stopped, "failure-rate")
  expect_identical(run$attempted, 4L)
  # the tally of the earlier checkpoints counts: 5 of 50 plus one more
  rad_fetch_one <- fetch_by_kind(list("1" = "reader"))
  run <- suppressMessages(rad_run_queue(
    queue_of(3),
    rad_empty_state("dfp"),
    withr::local_tempdir(),
    limit = 3L,
    minutes = 10,
    Sys.time(),
    tally = list(attempted = 50L, failed = 7L, reader_failed = 5L)
  ))
  expect_identical(run$stopped, "failure-rate")
  expect_identical(run$attempted, 1L)
})
