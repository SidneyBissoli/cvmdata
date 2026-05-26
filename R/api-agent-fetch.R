#' Fetch a CVM open-data table for a registered-agent dataset
#'
#' Single entry point for retrieving any table from any CVM
#' agent-class dataset covered by the package. Covers natural and
#' legal persons registered with CVM across eight CKAN groups:
#' `administradores`, `agentes-autonomos`, `agentes-fiduciarios`,
#' `auditores`, `consultores-de-valores-mobiliarios`,
#' `coordenadores-de-ofertas`, `participantes-intermediarios` and
#' `investidores-nao-residentes`.
#'
#' Column names, categorical values and free-text fields are
#' preserved in Portuguese exactly as published by CVM
#' (snake_case minúsculo).
#'
#' In v0.1.0.9000 the function is exported as a skeleton documenting
#' the planned contract; calling it aborts with
#' `cvmdata_error_input_group` pointing to ROADMAP.md. Full
#' implementation arrives in v0.7.
#'
#' @param dataset Short dataset id (e.g. `"administradores"`,
#'   `"agentes-autonomos"`).
#' @param table Snake-case table name within the dataset.
#' @param agent Optional character vector identifying registered
#'   agents to include. Accepts CPF, CNPJ, or free-text — the
#'   accepted token types vary by dataset:
#'   * `agentes-autonomos` accepts CPF only;
#'   * `coordenadores-de-ofertas` accepts CNPJ only;
#'   * `administradores`, `auditores`,
#'     `consultores-de-valores-mobiliarios` accept CPF, CNPJ and
#'     free-text against the registered name.
#'   Validation is performed against the target dataset at fetch
#'   time. `NULL` (default) returns every registered agent.
#'   Singular naming follows tidyverse conventions; the argument
#'   still accepts vectors of any length.
#' @param as_of Optional `Date` scalar specifying a registry
#'   snapshot date. `NULL` (default) returns the most recent
#'   registry snapshot. For historical snapshots, pass a specific
#'   date; the function returns the registry as published at the
#'   closest available snapshot on or before that date.
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
#' # Available from v0.7 onwards:
#' admins <- agent_fetch("administradores", "cadastro")
#'
#' # Snapshot at a historical date:
#' aa <- agent_fetch("agentes-autonomos", "cadastro",
#'                   as_of = as.Date("2023-12-31"))
#'
#' @family fetchers
#' @export
agent_fetch <- function(dataset, table,
                        agent    = NULL,
                        as_of    = NULL,
                        source   = NULL,
                        on_error = "abort",
                        validate = "strict",
                        ...) {
  dots <- list(...)
  if (length(dots) > 0L) {
    nms <- names(dots) %||% rep("", length(dots))
    nms[!nzchar(nms)] <- "<unnamed>"
    cvmdata_abort(
      c(
        "Unknown argument{?s}: {.arg {nms}}.",
        "i" = paste(
          "{.fn agent_fetch} accepts {.arg agent}, {.arg as_of},",
          "{.arg source}, {.arg on_error} and {.arg validate}."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  cvmdata_abort(
    c(
      paste(
        "{.fn agent_fetch} is exported as a skeleton in",
        "{.val 0.1.0.9000}; the agent datasets are not yet",
        "implemented."
      ),
      "i" = paste(
        "Groups {.val administradores}, {.val agentes-autonomos},",
        "{.val agentes-fiduciarios}, {.val auditores},",
        "{.val consultores-de-valores-mobiliarios},",
        "{.val coordenadores-de-ofertas},",
        "{.val participantes-intermediarios} and",
        "{.val investidores-nao-residentes} arrive in v0.7."
      ),
      "i" = "See {.file ROADMAP.md} for the release plan."
    ),
    class = c("cvmdata_error_input_group", "cvmdata_error_input")
  )
}
