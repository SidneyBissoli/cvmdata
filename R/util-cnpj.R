#' Strip punctuation from a CNPJ vector
#'
#' Returns the 14-digit form of one or more Brazilian taxpayer-id
#' numbers (CNPJ). The package stores `cnpj_cia` with punctuation as
#' published by CVM (`"12.345.678/0001-90"`); this helper produces the
#' digits-only form used by external bases such as Receita Federal,
#' DATASUS, IBGE and eSocial.
#'
#' Non-digit characters are removed; `NA` is preserved. No length or
#' check-digit validation is performed in v0.1; that may be added
#' later.
#'
#' @param x Character vector of CNPJs in any format.
#' @return Character vector of the same length as `x`, with only the
#'   digits retained.
#' @examples
#' cnpj_clean("12.345.678/0001-90")
#' cnpj_clean(c("12.345.678/0001-90", NA, "99999999000191"))
#' @family utilities
#' @export
cnpj_clean <- function(x) {
  if (!is.character(x) && !all(is.na(x))) {
    cvmdata_abort(
      c(
        "{.arg x} must be a character vector.",
        "i" = "Got {.cls {class(x)[1L]}}."
      ),
      class = "cvmdata_error_input"
    )
  }
  out <- gsub("[^0-9]", "", x, perl = TRUE)
  out[is.na(x)] <- NA_character_
  out
}
