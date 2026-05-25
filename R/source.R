# Public source API. Controls which backend `issuer_fetch()` consults
# to retrieve raw CVM data:
#
#   "mirror" — parquet snapshots in GitHub Releases, queried via
#              DuckDB. Default from v0.1.0.
#   "cvm"    — direct HTTP to the CVM Open Data Portal
#              (https://dados.cvm.gov.br/). Fully supported; opt in
#              when byte-level freshness against the CVM origin is
#              required.
#
# The active source is stored in the option `cvmdata.source`.
# `issuer_fetch()` resolves the default via `cvm_source_get()`, so
# `cvm_source_set("cvm")` flips the global default for subsequent
# fetches; an explicit `source = ...` argument always wins.

#' Get the active cvmdata source backend
#'
#' Reads the option `cvmdata.source`, falling back to `"mirror"`
#' (parquet via DuckDB) when the option is unset.
#'
#' From v0.1.0 onward the built-in default is `"mirror"`: it ships the
#' full historical series for CAD, DFP, ITR and FRE as parquet assets
#' on GitHub Releases, refreshed weekly. The `"cvm"` backend, which
#' reads the CVM Open Data Portal directly, remains fully supported
#' and can be selected per call or persisted with [cvm_source_set()].
#'
#' @return A character scalar: `"mirror"` or `"cvm"`.
#'
#' @examples
#' cvm_source_get()
#' @family source
#' @seealso [cvm_source_set()]
#' @export
cvm_source_get <- function() {
  getOption("cvmdata.source", "mirror")
}

#' Set the active cvmdata source backend
#'
#' Configures the option `cvmdata.source`, which becomes the default
#' for subsequent [issuer_fetch()] calls that do not pass `source`
#' explicitly. The argument passed to `issuer_fetch()` always wins over
#' the option.
#'
#' @param source One of `"mirror"` (parquet via DuckDB; default from
#'   v0.1.0) or `"cvm"` (CVM Open Data Portal).
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
