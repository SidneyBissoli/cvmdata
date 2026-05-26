#' Fetch a CVM open-data table for a regulatory-event dataset
#'
#' Single entry point for retrieving any table from any CVM
#' event-class dataset covered by the package. Covers sanctioning
#' proceedings (`atividade-sancionadora`) and declaratory acts
#' issued by the CVM directors (`atos-declaratorios`).
#'
#' Column names, categorical values and free-text fields are
#' preserved in Portuguese exactly as published by CVM
#' (snake_case minúsculo).
#'
#' In v0.1.0.9000 the function is exported as a skeleton documenting
#' the planned contract; calling it aborts with
#' `cvmdata_error_input_group` pointing to ROADMAP.md. Full
#' implementation arrives in v0.8.
#'
#' @param dataset Short dataset id (e.g. `"sancionadora"`,
#'   `"atos-declaratorios"`).
#' @param table Snake-case table name within the dataset.
#' @param event Optional character vector of event identifiers
#'   (`nr_processo` for sanctioning proceedings, `nr_ato` for
#'   declaratory acts). `NULL` (default) returns every event in the
#'   date range. Singular naming follows tidyverse conventions; the
#'   argument still accepts vectors of any length.
#' @param date_range Optional `Date` vector of length 2 specifying
#'   the event date window: `c(from, to)`. `NULL` (default) returns
#'   every event ever published. Vectors of length other than 2
#'   abort with `cvmdata_error_input`.
#' @param source One of `"mirror"` (parquet via DuckDB) or `"cvm"`
#'   (CVM Open Data Portal). `NULL` (default) resolves to the
#'   active backend via [cvm_source_get()].
#' @param on_error One of `"abort"` (default), `"warn"` or
#'   `"silent"`. Controls behaviour on HTTP failures, analogously
#'   to [issuer_fetch()].
#' @param validate One of `"strict"` (default), `"warn"` or
#'   `"skip"`. Controls schema validation strictness at parse time.
#' @param ... Reserved for forward compatibility. Currently no
#'   extra arguments are accepted; passing any aborts with
#'   `cvmdata_error_input`.
#'
#' @return A tibble of class `cvm_tbl` carrying the five provenance
#'   attributes `source`, `fetched_at`, `dataset`, `table` and
#'   `package_version`.
#'
#' @examplesIf FALSE
#' # Available from v0.8 onwards (atividade-sancionadora):
#' procs <- event_fetch("sancionadora", "processos",
#'                      date_range = as.Date(
#'                        c("2024-01-01", "2024-12-31")
#'                      ))
#'
#' # Declaratory acts:
#' atos <- event_fetch("atos-declaratorios", "atos")
#'
#' @family fetchers
#' @export
event_fetch <- function(dataset, table,
                        event      = NULL,
                        date_range = NULL,
                        source     = NULL,
                        on_error   = "abort",
                        validate   = "strict",
                        ...) {
  dots <- list(...)
  if (length(dots) > 0L) {
    nms <- names(dots) %||% rep("", length(dots))
    nms[!nzchar(nms)] <- "<unnamed>"
    cvmdata_abort(
      c(
        "Unknown argument{?s}: {.arg {nms}}.",
        "i" = paste(
          "{.fn event_fetch} accepts {.arg event},",
          "{.arg date_range}, {.arg source}, {.arg on_error}",
          "and {.arg validate}."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  cvmdata_abort(
    c(
      paste(
        "{.fn event_fetch} is exported as a skeleton in",
        "{.val 0.1.0.9000}; the event datasets are not yet",
        "implemented."
      ),
      "i" = paste(
        "Groups {.val atividade-sancionadora} and",
        "{.val atos-declaratorios} arrive in v0.8."
      ),
      "i" = "See {.file ROADMAP.md} for the release plan."
    ),
    class = c("cvmdata_error_input_group", "cvmdata_error_input")
  )
}
