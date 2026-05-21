#' Fetch the CVM company registry (CAD)
#'
#' Thin alias for `cvm_fetch(dataset = "cad", table = "companhias",
#' ...)`, kept for ergonomics of the Session 01 release. Returns the
#' current snapshot of the *Cadastro de Companhias Abertas* published
#' by CVM at <https://dados.cvm.gov.br/>.
#'
#' @inheritParams cvm_fetch
#'
#' @return A tibble of class `cvm_tbl` carrying provenance attributes.
#'
#' @examplesIf interactive()
#' companies <- cad_fetch()
#'
#' @family fetchers
#' @seealso [cvm_fetch()] for the generic API.
#' @export
cad_fetch <- function(companies = NULL,
                      source = "cvm",
                      on_error = "abort",
                      validate = "strict",
                      ...) {
  cvm_fetch(
    dataset   = "cad",
    table     = "companhias",
    companies = companies,
    source    = source,
    on_error  = on_error,
    validate  = validate,
    ...
  )
}
