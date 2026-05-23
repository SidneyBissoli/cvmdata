#!/usr/bin/env Rscript
# teste_fre.R
#
# Smoke check manual do dataset FRE. Bate no portal CVM real
# (source = "cvm"); nao usa fixture. Inspecao visual, nao testthat.
#
# Uso (da raiz do pacote):
#   Rscript teste_fre.R
#
# Excluido do tarball via .Rbuildignore (^teste.*\\.R$).

suppressPackageStartupMessages({
  devtools::load_all(quiet = TRUE)
})

# Per-scenario runner --------------------------------------------------

.results <- new.env(parent = emptyenv())
.results$log <- list()

run_scenario <- function(id, title, expr) {
  cli::cli_h2("Scenario {id} - {title}")
  cli::cli_text("{.code {deparse(substitute(expr))}}")
  outcome <- tryCatch(
    {
      force(expr)
      "OK"
    },
    error = function(e) {
      cli::cli_alert_danger(
        "STOP in scenario {id}: {conditionMessage(e)}"
      )
      "STOP"
    }
  )
  .results$log[[as.character(id)]] <- list(
    title = title, outcome = outcome
  )
  invisible(outcome)
}

show_attrs <- function(x) {
  attrs <- attributes(x)
  attrs$names <- NULL
  attrs$row.names <- NULL
  cli::cli_text("attributes():")
  print(attrs)
}

# Scenarios ------------------------------------------------------------

cli::cli_h1("cvmdata smoke check - FRE")
cli::cli_text(
  "Live calls hit dados.cvm.gov.br. Requires network access."
)

run_scenario(1L, "cvm_tables(\"fre\") returns 36 tables; count missing", {
  tabs <- cvm_tables("fre")
  cli::cli_text("Total FRE tables: {length(tabs)}")
  stopifnot(length(tabs) == 36L)

  yaml_dir <- system.file(
    "extdata", "schemas", "fre", package = "cvmdata"
  )
  missing_tabs <- vapply(tabs, function(t) {
    y <- yaml::read_yaml(file.path(yaml_dir, paste0(t, ".yaml")))
    identical(y$meta_status, "missing")
  }, logical(1L))
  cli::cli_text(
    "meta_status = missing: {sum(missing_tabs)} tables - ",
    "{.val {names(missing_tabs)[missing_tabs]}}"
  )
  stopifnot(sum(missing_tabs) == 8L)
})

run_scenario(2L, "FRE-detail tracer via CD_CVM (submissao lookup)", {
  res <- cvm_fetch(
    "fre", "auditor",
    companies = "001023",
    years = 2024L,
    source = "cvm"
  )
  show_attrs(res)
  dplyr::glimpse(res)
  cli::cli_text("nrow: {nrow(res)}")
  stopifnot(nrow(res) >= 1L)
  stopifnot("cnpj_companhia" %in% names(res))
})

run_scenario(3L, "FRE-detail filter via CNPJ (cnpj_companhia)", {
  res <- cvm_fetch(
    "fre", "auditor",
    companies = "00.000.000/0001-91",
    years = 2024L,
    source = "cvm"
  )
  uniq_cnpj <- unique(res$cnpj_companhia)
  cli::cli_text("unique cnpj_companhia: {.val {uniq_cnpj}}")
  cli::cli_text("nrow: {nrow(res)}")
  stopifnot(nrow(res) >= 1L)
  stopifnot(all(uniq_cnpj == "00.000.000/0001-91"))
})

run_scenario(4L, "FRE-detail text search via nome_companhia", {
  res <- cvm_fetch(
    "fre", "auditor",
    companies = "MAGAZINE LUIZA",
    years = 2024L,
    source = "cvm"
  )
  cli::cli_text(
    "unique nome_companhia: {.val {unique(res$nome_companhia)}}"
  )
  cli::cli_text("nrow: {nrow(res)}")
  stopifnot(nrow(res) >= 1L)
})

run_scenario(5L, "meta_status: missing under validate = \"strict\"", {
  res <- cvm_fetch(
    "fre", "empregado_PCD",
    years = 2024L,
    source = "cvm",
    validate = "strict"
  )
  show_attrs(res)
  print(res)
  cli::cli_text("nrow: {nrow(res)}")
})

run_scenario(6L, "keep_latest_version: only max(versao) per (cnpj, dt_refer)", {
  # FRE-detail tables can have fine-grained granularity (e.g. auditor
  # carries one row per auditor within the document). keep_latest_version
  # filters out older filings of the same document — it does NOT
  # collapse to one row per (cnpj, data_referencia). Correct assertion:
  # for any (cnpj, data_referencia) slice, all surviving rows share
  # the same `versao` (the maximum that was present in the raw CSV).
  res <- cvm_fetch(
    "fre", "auditor",
    companies = "001023",
    years = 2024L,
    source = "cvm"
  )
  versions_by_key <- res |>
    dplyr::group_by(cnpj_companhia, data_referencia) |>
    dplyr::summarise(
      n_versions = dplyr::n_distinct(versao),
      versions   = paste(sort(unique(versao)), collapse = ","),
      n_rows     = dplyr::n(),
      .groups    = "drop"
    )
  print(versions_by_key)
  multi_version <- dplyr::filter(versions_by_key, n_versions > 1L)
  cli::cli_text(
    "(cnpj, data_referencia) slices with >1 versao: {nrow(multi_version)}"
  )
  if (nrow(multi_version) > 0L) print(multi_version)
  stopifnot(nrow(multi_version) == 0L)
})

# Summary --------------------------------------------------------------

cli::cli_h1("Summary")
ok_n <- sum(vapply(.results$log, \(x) x$outcome == "OK", logical(1L)))
stop_n <- sum(
  vapply(.results$log, \(x) x$outcome == "STOP", logical(1L))
)
for (id in names(.results$log)) {
  rec <- .results$log[[id]]
  symbol <- if (rec$outcome == "OK") "v" else "x"
  cli::cli_bullets(c(
    "{symbol}" = "Scenario {id} - {rec$title}: {rec$outcome}"
  ))
}
cli::cli_text("Total: {ok_n} OK, {stop_n} STOP")
if (stop_n > 0L) {
  quit(status = 1L)
}
