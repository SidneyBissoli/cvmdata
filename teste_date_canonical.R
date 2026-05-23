#!/usr/bin/env Rscript
# teste_date_canonical.R
#
# Smoke check da regra canonica de Date (Tarefa A da Sessao 3.4):
# o snapshot de dicionario passa a dirigir a deteccao de colunas Date
# em read_cvm_csv(); a heuristica `^(dt_|data_)` vira fallback para
# meta_status:missing e schemas sem cobertura no snapshot.
#
# Bate na CVM real (source = "cvm"). Inspecao visual, nao testthat.
#
# Uso (da raiz do pacote):
#   Rscript teste_date_canonical.R
#
# Excluido do tarball via .Rbuildignore (^teste.*\\.R$).

suppressPackageStartupMessages({
  devtools::load_all(quiet = TRUE)
})

.results <- new.env(parent = emptyenv())
.results$log <- list()

run_scenario <- function(id, title, expr) {
  cli::cli_h2("Scenario {id} - {title}")
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

date_cols <- function(df) {
  names(df)[vapply(df, inherits, logical(1L), "Date")]
}

cli::cli_h1("cvmdata smoke check - canonical Date detection")

run_scenario(1L, "dfp/bpa: dt_refer/dt_fim_exerc remain Date", {
  res <- cvm_fetch(
    "dfp", "bpa",
    report_type = "ind",
    companies = "001023",
    years = 2024L,
    source = "cvm"
  )
  cli::cli_text("Date columns: {.val {date_cols(res)}}")
  stopifnot(inherits(res$dt_refer, "Date"))
  stopifnot(inherits(res$dt_fim_exerc, "Date"))
})

run_scenario(2L, "fre/auditor: data_* columns remain Date", {
  res <- cvm_fetch(
    "fre", "auditor",
    companies = "001023",
    years = 2024L,
    source = "cvm"
  )
  cli::cli_text("Date columns: {.val {date_cols(res)}}")
  stopifnot(inherits(res$data_referencia, "Date"))
  stopifnot(inherits(res$data_inicio_contratacao, "Date"))
  stopifnot(inherits(res$data_fim_contratacao, "Date"))
  stopifnot(inherits(res$data_inicio_prestacao_servico, "Date"))
})

run_scenario(3L, "fre/empregado_PCD (meta_status:missing): heuristic fallback", {
  res <- cvm_fetch(
    "fre", "empregado_PCD",
    years = 2024L,
    source = "cvm",
    validate = "skip"
  )
  cli::cli_text("Date columns: {.val {date_cols(res)}}")
  # meta_status: missing => snapshot has NA in tipo_dados;
  # the heuristic must continue to detect data_referencia.
  stopifnot(inherits(res$data_referencia, "Date"))
})

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
