#!/usr/bin/env Rscript
# teste_cvm_dictionary.R
#
# Smoke check manual de cvm_dictionary(). Le o snapshot embarcado
# (inst/extdata/cvm_dictionary_snapshot.csv) - nao bate na rede.
# Inspecao visual, nao testthat.
#
# Uso (da raiz do pacote):
#   Rscript teste_cvm_dictionary.R
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
outcome
# Scenarios ------------------------------------------------------------

cli::cli_h1("cvmdata smoke check - cvm_dictionary()")
cli::cli_text("Reads inst/extdata/cvm_dictionary_snapshot.csv. Offline.")

run_scenario(1L, "CAD/companhias: 47 columns, all available", {
  d <- cvm_dictionary("cad", "companhias")
  cli::cli_text("nrow: {nrow(d)}")
  cli::cli_text("colnames: {.val {names(d)}}")
  cli::cli_text("attr meta_status: {attr(d, 'meta_status') %||% 'NULL'}")
  print(d, n = 5)
  stopifnot(nrow(d) == 47L)
  stopifnot(all(!is.na(d$tipo_dados)))
  stopifnot(is.null(attr(d, "meta_status")))
})

run_scenario(2L, "DFP/bpa: parsed types include 'date'", {
  d <- cvm_dictionary("dfp", "bpa")
  cli::cli_text("nrow: {nrow(d)}")
  cli::cli_text("tipo_dados frequencies:")
  print(table(d$tipo_dados, useNA = "ifany"))
  print(d, n = Inf)
  stopifnot(any(d$tipo_dados == "date", na.rm = TRUE))
})

run_scenario(3L, "FRE/auditor: 18 columns, all available", {
  d <- cvm_dictionary("fre", "auditor")
  cli::cli_text("nrow: {nrow(d)}")
  print(d, n = Inf)
  stopifnot(nrow(d) == 18L)
  stopifnot(all(!is.na(d$tipo_dados)))
  stopifnot(is.null(attr(d, "meta_status")))
})

run_scenario(4L, "FRE/empregado_PCD: meta_status = missing", {
  d <- cvm_dictionary("fre", "empregado_PCD")
  cli::cli_text("nrow: {nrow(d)}")
  cli::cli_text("attr meta_status: {.val {attr(d, 'meta_status')}}")
  print(d, n = Inf)
  stopifnot(all(is.na(d$tipo_dados)))
  stopifnot(all(is.na(d$descricao)))
  stopifnot(all(is.na(d$tamanho)))
  stopifnot(identical(attr(d, "meta_status"), "missing"))
})

run_scenario(5L, "ITR/submissao: shares schema with DFP submissao", {
  d_itr <- cvm_dictionary("itr", "submissao")
  d_dfp <- cvm_dictionary("dfp", "submissao")
  cli::cli_text(
    "ITR/submissao nrow: {nrow(d_itr)} ; DFP/submissao nrow: {nrow(d_dfp)}"
  )
  cli::cli_text(
    "ITR columns: {.val {d_itr$column}}"
  )
  stopifnot(nrow(d_itr) > 0L)
  stopifnot(setequal(d_itr$column, d_dfp$column))
})
d_itr
d_dfp

run_scenario(6L, "FRE anomalous URL: empregado_local_faixa_etaria parsed", {
  # This table has cvm_dictionary_url pointing to an entry inside the
  # META ZIP without the `meta_` prefix - the generator handled it.
  d <- cvm_dictionary("fre", "empregado_local_faixa_etaria")
  cli::cli_text("nrow: {nrow(d)}")
  print(d, n = Inf)
  stopifnot(nrow(d) > 0L)
  stopifnot(all(!is.na(d$tipo_dados)))
  stopifnot(is.null(attr(d, "meta_status")))
})

run_scenario(7L, "Error: unknown dataset aborts with cvmdata_error_input", {
  err <- tryCatch(
    cvm_dictionary("doesnt_exist", "bpa"),
    cvmdata_error_input = function(e) e
  )
  stopifnot(inherits(err, "cvmdata_error_input"))
  cli::cli_text("Got expected condition class: cvmdata_error_input")
  cli::cli_text("Message: {conditionMessage(err)}")
})
err
run_scenario(8L, "Error: unknown table in known dataset aborts", {
  err <- tryCatch(
    cvm_dictionary("dfp", "doesnt_exist"),
    cvmdata_error_input = function(e) e
  )
  stopifnot(inherits(err, "cvmdata_error_input"))
  cli::cli_text("Got expected condition class: cvmdata_error_input")
  cli::cli_text("Message: {conditionMessage(err)}")
})

run_scenario(9L, "Cross-dataset coverage: 59 (dataset, table) pairs", {
  pairs <- list()
  for (ds in cvm_datasets()) {
    for (tbl in cvm_tables(ds)) {
      pairs[[length(pairs) + 1L]] <- list(dataset = ds, table = tbl)
    }
  }
  cli::cli_text("Total (dataset, table) pairs: {length(pairs)}")

  # Try cvm_dictionary on every pair; record any failures.
  failures <- character(0L)
  meta_missing <- character(0L)
  for (p in pairs) {
    d <- tryCatch(
      cvm_dictionary(p$dataset, p$table),
      error = function(e) e
    )
    if (inherits(d, "error")) {
      failures <- c(
        failures, paste0(p$dataset, "/", p$table, ": ", conditionMessage(d))
      )
    } else if (identical(attr(d, "meta_status"), "missing")) {
      meta_missing <- c(meta_missing, paste0(p$dataset, "/", p$table))
    }
  }
  cli::cli_text("Failures: {length(failures)}")
  if (length(failures)) {
    for (f in failures) cli::cli_alert_danger(f)
  }
  cli::cli_text(
    "Pairs flagged meta_status=missing: {length(meta_missing)}"
  )
  if (length(meta_missing)) {
    cli::cli_text("  {.val {meta_missing}}")
  }
  stopifnot(length(failures) == 0L)
  stopifnot(length(meta_missing) == 8L)
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




