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

#' Format a CNPJ vector with the canonical punctuation
#'
#' Inverse of [cnpj_clean()]. Takes one or more CNPJs in any format
#' (digits-only or already punctuated) and returns them as
#' `"NN.NNN.NNN/NNNN-NN"`. Useful when cross-referencing data from
#' external bases (Receita Federal, DATASUS, IBGE, eSocial) against
#' the punctuated `cnpj_cia` column the package preserves from CVM.
#'
#' `NA` is preserved. Inputs whose digit-only form is not exactly 14
#' characters return `NA_character_` and a single warning of class
#' `cvmdata_warn` listing the offending positions; downstream code
#' can decide whether to filter the NAs or escalate.
#'
#' @param x Character vector of CNPJs (digits-only or punctuated).
#' @return Character vector of the same length as `x`, formatted as
#'   `"NN.NNN.NNN/NNNN-NN"`. `NA_character_` where the input is NA
#'   or has a non-14-digit body.
#'
#' @examples
#' cnpj_format("12345678000190")
#' cnpj_format(c("12345678000190", NA, "12.345.678/0001-90"))
#' @family utilities
#' @seealso [cnpj_clean()]
#' @export
cnpj_format <- function(x) {
  if (!is.character(x) && !all(is.na(x))) {
    cvmdata_abort(
      c(
        "{.arg x} must be a character vector.",
        "i" = "Got {.cls {class(x)[1L]}}."
      ),
      class = "cvmdata_error_input"
    )
  }
  digits <- gsub("[^0-9]", "", x, perl = TRUE)
  digits[is.na(x)] <- NA_character_
  ok <- !is.na(digits) & nchar(digits) == 14L
  out <- rep(NA_character_, length(x))
  out[ok] <- sub(
    "^([0-9]{2})([0-9]{3})([0-9]{3})([0-9]{4})([0-9]{2})$",
    "\\1.\\2.\\3/\\4-\\5",
    digits[ok]
  )
  invalid <- !is.na(x) & !ok
  if (any(invalid)) {
    bad_idx <- which(invalid)
    cvmdata_warn(
      c(
        paste(
          "{length(bad_idx)} value(s) of {.arg x} did not have 14",
          "digits; returning {.code NA_character_} for them."
        ),
        "i" = "Offending positions: {.val {bad_idx}}."
      )
    )
  }
  out
}
