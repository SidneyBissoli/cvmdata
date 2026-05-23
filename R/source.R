# Public source API. Controls which backend `cvm_fetch()` consults
# to retrieve raw CVM data:
#
#   "cvm"    — direct HTTP to the CVM Open Data Portal
#              (https://dados.cvm.gov.br/). Default in v0.1.
#   "mirror" — parquet snapshots in GitHub Releases, queried via
#              DuckDB. Lands in Phase F of the roadmap.
#
# The active source is stored in the option `cvmdata.source`.
# `cvm_fetch()` resolves the default via `cvm_source_get()`, so
# `cvm_source_set("mirror")` flips the global default for subsequent
# fetches; an explicit `source = ...` argument always wins.

#' Get the active cvmdata source backend
#'
#' Reads the option `cvmdata.source`, falling back to `"cvm"` (the
#' direct CVM Open Data Portal backend) when the option is unset.
#'
#' The built-in default is `"cvm"` in the v0.1 series; it transitions
#' to `"mirror"` in the release that ships the GitHub Releases parquet
#' mirror (Phase F of the roadmap). Persist a specific value with
#' [cvm_source_set()] to make scripts robust against that flip.
#'
#' @return A character scalar: `"cvm"` or `"mirror"`.
#'
#' @examples
#' cvm_source_get()
#' @family source
#' @seealso [cvm_source_set()]
#' @export
cvm_source_get <- function() {
  getOption("cvmdata.source", "cvm")
}

#' Set the active cvmdata source backend
#'
#' Configures the option `cvmdata.source`, which becomes the default
#' for subsequent [cvm_fetch()] calls that do not pass `source`
#' explicitly. The argument passed to `cvm_fetch()` always wins over
#' the option.
#'
#' @param source One of `"cvm"` (CVM Open Data Portal) or `"mirror"`
#'   (parquet via DuckDB; available from Phase F).
#'
#' @return The chosen source, invisibly.
#'
#' @examplesIf interactive()
#' cvm_source_set("cvm")
#' @family source
#' @seealso [cvm_source_get()]
#' @export
cvm_source_set <- function(source) {
  if (!is.character(source) || length(source) != 1L || is.na(source) ||
        !nzchar(source)) {
    cvmdata_abort(
      c("{.arg source} must be a single non-empty string."),
      class = "cvmdata_error_input"
    )
  }
  source <- rlang::arg_match0(source, c("cvm", "mirror"))
  options(cvmdata.source = source)
  cli::cli_inform(c(
    "v" = "Source backend set to {.val {source}}."
  ))
  invisible(source)
}
