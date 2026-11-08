# Tests for inst/etl/util-scale.R and the pure helpers of
# inst/etl/05-label-scale.R: the scale-error label of a superseded
# DFP/ITR version, judged over the whole document (decision of
# 2026-11-06; rule closed the same day).

load_etl_scale <- function() {
  for (pkg in c("xml2", "digest", "arrow", "jsonlite", "dplyr")) {
    skip_if_not_installed(pkg)
  }
  env <- parent.frame()
  withr::local_options(cvmdata.etl_testing = TRUE, .local_envir = env)
  scripts <- c(
    "00-config.R",
    "util-hash.R",
    "util-history.R",
    "util-release.R",
    "util-privacy.R",
    "util-rad.R",
    "util-scale.R",
    "04-rad-fetch.R",
    "05-label-scale.R"
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

ultimo <- paste0(intToUtf8(0x00DA), "LTIMO")
apenas <- "apenas erro de escala"
e_outras <- paste0("erro de escala e outras mudan", intToUtf8(0x00E7), "as")
sem <- "sem erro de escala"

# Rows of one statement of one version: `values` named by cd_conta.
statement_rows <- function(
  values,
  table = "bpa",
  report_type = "con",
  cnpj = "11.111.111/0001-11",
  dt_refer = "2023-12-31",
  versao = "1",
  ordem = ultimo,
  superseded_at = NA_character_,
  history_source = NA_character_,
  id_doc = NA_character_
) {
  n <- length(values)
  data.frame(
    cnpj_cia = rep(cnpj, n),
    dt_refer = rep(as.Date(dt_refer), n),
    versao = rep(versao, n),
    ordem_exerc = rep(ordem, n),
    dt_ini_exerc = rep(as.Date(NA), n),
    dt_fim_exerc = rep(as.Date(dt_refer), n),
    cd_conta = names(values),
    coluna_df = rep(NA_character_, n),
    vl_conta = unname(values),
    superseded_at = rep(superseded_at, n),
    history_source = rep(history_source, n),
    id_doc = rep(id_doc, n),
    table = rep(table, n),
    report_type = rep(report_type, n),
    stringsAsFactors = FALSE
  )
}

test_that("accounts are the ÚLTIMO rows, 3.99* left out, counted once", {
  load_etl_scale()
  df <- rbind(
    statement_rows(c("1" = 10, "1.01" = 4, "3.99.01.01" = 0.5)),
    statement_rows(c("1" = 9), ordem = "PENÚLTIMO"),
    statement_rows(c("1" = 10)), # a repeated row
    statement_rows(c("1" = NA_real_, "2" = 7), table = "bpp")
  )
  acc <- scale_accounts(df)
  expect_identical(nrow(acc), 3L)
  expect_identical(acc$table, c("bpa", "bpa", "bpp"))
  expect_identical(acc$value, c(10, 4, 7))
  expect_match(acc$account[[1]], "^bpa\\|con\\|1\\|\\|\\|2023-12-31$")
  # the DMPL column and the period are part of the identity
  dmpl <- statement_rows(c("5.01" = 1, "5.01" = 2), table = "dmpl")
  dmpl$coluna_df <- c("Capital Social", "Reservas")
  expect_identical(nrow(scale_accounts(dmpl)), 2L)
  dre <- statement_rows(c("3.01" = 1, "3.01" = 2), table = "dre")
  dre$dt_ini_exerc <- as.Date(c("2023-01-01", "2023-10-01"))
  expect_identical(nrow(scale_accounts(dre)), 2L)
})

test_that("the rule: every account on one factor is 'apenas'", {
  load_etl_scale()
  old <- scale_accounts(statement_rows(c("1" = 10, "1.01" = 4, "2" = -6)))
  new <- scale_accounts(statement_rows(
    c("1" = 10000, "1.01" = 4000, "2" = -6000),
    versao = "2"
  ))
  cmp <- scale_compare(old, new)
  expect_identical(cmp$n_judged, 3L)
  expect_identical(cmp$n_factor, 3L)
  expect_identical(cmp$exponent, 1L)
  expect_identical(scale_label(cmp), apenas)
  # the other way round (R$ thousand filed as units) too
  expect_identical(scale_label(scale_compare(new, old)), apenas)
  expect_identical(scale_compare(new, old)$exponent, -1L)
  # a zero on both sides is not judged and does not break 'apenas'
  old0 <- scale_accounts(statement_rows(c("1" = 10, "1.02" = 0)))
  new0 <- scale_accounts(statement_rows(c("1" = 10000, "1.02" = 0)))
  cmp0 <- scale_compare(old0, new0)
  expect_identical(cmp0$n_judged, 1L)
  expect_identical(scale_label(cmp0), apenas)
})

test_that("the rule: a majority on one factor with other changes is mixed", {
  load_etl_scale()
  old <- scale_accounts(statement_rows(c("1" = 10, "1.01" = 4, "2" = -6)))
  # one account changed beyond the scale
  other <- scale_accounts(statement_rows(
    c("1" = 10000, "1.01" = 4500, "2" = -6000),
    versao = "2"
  ))
  cmp <- scale_compare(old, other)
  expect_identical(cmp$n_factor, 2L)
  expect_identical(cmp$n_other, 1L)
  expect_identical(scale_label(cmp), e_outras)
  # one account kept equal while the rest moved a thousandfold
  equal <- scale_accounts(statement_rows(
    c("1" = 10000, "1.01" = 4000, "2" = -6),
    versao = "2"
  ))
  cmp <- scale_compare(old, equal)
  expect_identical(cmp$n_equal, 1L)
  expect_identical(scale_label(cmp), e_outras)
  # a non-zero account on one side only
  extra <- scale_accounts(statement_rows(
    c("1" = 10000, "1.01" = 4000, "2" = -6000, "2.01" = 500),
    versao = "2"
  ))
  cmp <- scale_compare(old, extra)
  expect_identical(cmp$n_one_side, 1L)
  expect_identical(scale_label(cmp), e_outras)
  # a zero account on one side only says nothing
  zero <- scale_accounts(statement_rows(
    c("1" = 10000, "1.01" = 4000, "2" = -6000, "2.01" = 0),
    versao = "2"
  ))
  expect_identical(scale_label(scale_compare(old, zero)), apenas)
})

test_that("the rule: no majority on one factor is 'sem'", {
  load_etl_scale()
  old <- scale_accounts(statement_rows(c("1" = 10, "1.01" = 4, "2" = -6)))
  same <- scale_accounts(statement_rows(
    c("1" = 10, "1.01" = 4, "2" = -6),
    versao = "2"
  ))
  cmp <- scale_compare(old, same)
  expect_identical(cmp$n_equal, 3L)
  expect_identical(cmp$n_factor, 0L)
  expect_true(is.na(cmp$exponent))
  expect_identical(scale_label(cmp), sem)
  # an ordinary restatement
  restated <- scale_accounts(statement_rows(
    c("1" = 11, "1.01" = 5, "2" = -6),
    versao = "2"
  ))
  expect_identical(scale_label(scale_compare(old, restated)), sem)
  # exactly half on the factor is not a majority
  half <- scale_accounts(statement_rows(
    c("1" = 10000, "1.01" = 4000, "2" = -7, "2.01" = 1),
    versao = "2"
  ))
  old4 <- scale_accounts(statement_rows(
    c("1" = 10, "1.01" = 4, "2" = -6, "2.01" = 2)
  ))
  cmp <- scale_compare(old4, half)
  expect_identical(cmp$n_factor, 2L)
  expect_identical(scale_label(cmp), sem)
  # nothing to judge: no shared account, or no successor at all
  expect_identical(scale_label(scale_compare(old, old[0, ])), sem)
  # a zero that became a figure is another value, not the factor; one
  # account of two on the factor is no majority
  from_zero <- scale_accounts(statement_rows(c("1" = 0, "1.01" = 4)))
  to_figure <- scale_accounts(statement_rows(
    c("1" = 5000, "1.01" = 4000),
    versao = "2"
  ))
  cmp <- scale_compare(from_zero, to_figure)
  expect_identical(cmp$n_factor, 1L)
  expect_identical(cmp$n_other, 1L)
  expect_identical(scale_label(cmp), sem)
})

test_that("Technos ITR 2011 version 1 (R$ units) is 'apenas erro de escala'", {
  load_etl_scale()
  f <- data.frame(
    cnpj_cia = "09.295.063/0001-97",
    dt_refer = as.Date("2011-06-30"),
    versao = "1",
    denom_cia = "TECHNOS S.A.",
    cd_cvm = "022519",
    id_doc = "10642",
    dt_receb = as.Date("2011-08-15"),
    superseded_at = "2011-08-16",
    superseded_by_versao = "2",
    stringsAsFactors = FALSE
  )
  r <- rad_read_zip(test_path("fixtures", "rad_itr_2011_10642.zip"), f)
  tables <- rad_history_rows(r$tables, f, r$meta)
  history <- dplyr::bind_rows(lapply(names(tables), function(key) {
    t <- tables[[key]]
    parts <- strsplit(key, "/", fixed = TRUE)[[1L]]
    t$table <- parts[[1L]]
    t$report_type <- parts[[2L]]
    t
  }))
  # version 2, filed the next day "to change the currency scale to
  # thousands", is the same figures a thousand times larger
  current <- history
  current$vl_conta <- current$vl_conta * 1000
  current$versao <- "2"
  current <- current[setdiff(names(current), mirror_history_cols)]
  verdicts <- scale_label_versions(history, current)
  expect_identical(nrow(verdicts), 1L)
  expect_identical(verdicts$scale_error, apenas)
  expect_identical(verdicts$history_source, "rad")
  expect_identical(verdicts$exponent, 1L)
  expect_identical(verdicts$n_other + verdicts$n_one_side, 0L)
  expect_gt(verdicts$n_judged, 20L)
  expect_identical(
    verdicts$version,
    "09.295.063/0001-97|2011-06-30|1|10642|2011-08-16"
  )
  # per-share accounts (3.99*) were left out although the fixture has them
  expect_true(any(startsWith(history$cd_conta, "3.99")))
  expect_lt(verdicts$n_judged, sum(history$ordem_exerc == ultimo))
  # the verdict lands on every row of the version, nothing else
  labelled <- scale_apply_verdicts(history, verdicts)
  expect_true(all(labelled$scale_error == apenas))
  expect_true(anyNA(scale_apply_verdicts(current, verdicts)$scale_error))
  expect_match(scale_tally(verdicts), "^1 version\\(s\\): 1 apenas / 0 ")
})

test_that("versions of a document are paired in order; current last", {
  load_etl_scale()
  # v1 in units (scale error), v2 restated v1 x 1000 with one change,
  # v3 current equal to v2: v1 -> v2 is mixed, v2 -> v3 is 'sem'
  v1 <- statement_rows(
    c("1" = 10, "1.01" = 4, "2" = -6),
    versao = "1",
    superseded_at = "2024-05-14",
    history_source = "rad",
    id_doc = "100"
  )
  v2 <- statement_rows(
    c("1" = 10000, "1.01" = 4500, "2" = -6000),
    versao = "2",
    superseded_at = "2024-07-01",
    history_source = "rad",
    id_doc = "200"
  )
  v3 <- statement_rows(
    c("1" = 10000, "1.01" = 4500, "2" = -6000),
    versao = "3"
  )
  verdicts <- scale_label_versions(rbind(v1, v2), v3)
  expect_identical(verdicts$document, rep("11.111.111/0001-11|2023-12-31", 2))
  expect_identical(verdicts$scale_error, c(e_outras, sem))
  # a version whose document has no current rows (vanished) is 'sem'
  alone <- scale_label_versions(v1, v3[0, ])
  expect_identical(alone$scale_error, sem)
  expect_identical(alone$n_judged, 0L)
  # two documents do not pair with each other
  other <- statement_rows(
    c("1" = 10000, "1.01" = 4000, "2" = -6000),
    cnpj = "22.222.222/0001-22",
    versao = "2"
  )
  verdicts <- scale_label_versions(v1, other)
  expect_identical(verdicts$scale_error, sem)
  expect_identical(nrow(scale_label_versions(v1[0, ], v3)), 0L)
})

test_that("a mirror-filed version takes missing tables from its successor", {
  load_etl_scale()
  # the mirror path files only the partitions whose content changed:
  # the version's bpa is in the history, its dre (unchanged) is not
  v1_bpa <- statement_rows(
    c("1" = 10, "1.01" = 4, "1.02" = 6),
    versao = "1",
    superseded_at = "2026-10-28T07:00:00Z",
    history_source = "mirror"
  )
  current <- rbind(
    statement_rows(c("1" = 10000, "1.01" = 4000, "1.02" = 6000), versao = "2"),
    statement_rows(c("3.01" = 70, "3.11" = 5), table = "dre", versao = "2")
  )
  current <- current[setdiff(names(current), mirror_history_cols)]
  verdicts <- scale_label_versions(v1_bpa, current)
  # the dre accounts count as equal, so this is a scale error with
  # other figures, not 'apenas'
  expect_identical(verdicts$n_judged, 5L)
  expect_identical(verdicts$n_factor, 3L)
  expect_identical(verdicts$n_equal, 2L)
  expect_identical(verdicts$scale_error, e_outras)
  # the same rows filed by the RAD path have no dre: one side only
  v1_rad <- v1_bpa
  v1_rad$history_source <- "rad"
  v1_rad$id_doc <- "100"
  verdicts <- scale_label_versions(v1_rad, current)
  expect_identical(verdicts$n_judged, 3L)
  expect_identical(verdicts$n_one_side, 2L)
  expect_identical(verdicts$scale_error, e_outras)
  # the version key tells the two apart by id_doc
  expect_identical(
    scale_version_key(v1_bpa)[[1]],
    "11.111.111/0001-11|2023-12-31|1||2026-10-28T07:00:00Z"
  )
})

test_that("the stage finds the years to label from the sidecar", {
  load_etl_scale()
  history <- list(
    "bpa/report_type=con/year=2023/history.parquet" = "a1",
    "dre/report_type=ind/year=2023/history.parquet" = "b1",
    "bpa/report_type=con/year=2024/history.parquet" = "c1",
    "submissao/year=2024/history.parquet" = "s1"
  )
  assets <- scale_history_assets(history)
  expect_identical(nrow(assets), 3L)
  expect_identical(assets$table, c("bpa", "dre", "bpa"))
  expect_identical(assets$report_type, c("con", "ind", "con"))
  expect_identical(assets$year, c(2023L, 2023L, 2024L))
  # never labelled: every year
  sidecar <- list(history = history)
  expect_identical(scale_pending_years(sidecar), c(2023L, 2024L))
  # labelled under the current rule: only the asset whose hash moved
  sidecar$scale_rule <- scale_rule
  sidecar$scale_labeled <- history
  expect_identical(scale_pending_years(sidecar), integer())
  sidecar$history[["bpa/report_type=con/year=2024/history.parquet"]] <- "c2"
  expect_identical(scale_pending_years(sidecar), 2024L)
  expect_identical(scale_pending_years(sidecar, year = 2023L), integer())
  expect_identical(scale_pending_years(sidecar, all = TRUE), c(2023L, 2024L))
  # another rule: every year again
  sidecar$scale_rule <- "0"
  expect_identical(scale_pending_years(sidecar), c(2023L, 2024L))
  expect_identical(scale_pending_years(list(history = list())), integer())
  # the current partitions of a year, those the release holds
  sidecar$data <- list(
    "bpa/report_type=con/year=2024/part-0.parquet" = "x",
    "dre/report_type=ind/year=2024/part-0.parquet" = "y",
    "submissao/year=2024/part-0.parquet" = "z"
  )
  expect_identical(
    scale_current_rels(sidecar, 2024L),
    c(
      "bpa/report_type=con/year=2024/part-0.parquet",
      "dre/report_type=ind/year=2024/part-0.parquet"
    )
  )
  expect_identical(scale_current_rels(sidecar, 2023L), character())
})

test_that("the stage parses its arguments", {
  load_etl_scale()
  opts <- scale_parse_args(c(
    "--group",
    "companhias",
    "--dataset",
    "itr",
    "--year",
    "2011",
    "--all",
    "--dry-run"
  ))
  expect_identical(opts$dataset, "itr")
  expect_identical(opts$year, 2011L)
  expect_true(opts$all)
  expect_true(opts$dry_run)
  expect_error(scale_parse_args(c("--group", "companhias")), "required")
  expect_error(
    scale_parse_args(c("--group", "companhias", "--dataset", "fre")),
    "dfp and itr only"
  )
})
