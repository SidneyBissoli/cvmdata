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

#' Look up a company's CNPJ by name
#'
#' Searches the CVM company registers for a name, or part of one, and
#' returns the matching registrations with their CNPJ. Use it to find
#' the `cnpj` that [cvm_fetch()] takes. The function never picks a
#' company for you: it lists every match, and you choose.
#'
#' The search reads the three registers of the `cad` dataset
#' (`companhias`, `estrangeiras` and `incentivadas`, see [cvm_tables()])
#' from `source` and looks for `name` in `denom_social` and
#' `denom_comerc`. Every word of `name` must appear, in any order,
#' ignoring case and accents: `"banco brasil"` finds
#' `"BANCO DO BRASIL S.A."` and `"tiete"` finds `"AES TIETÊ ENERGIA S.A"`.
#' Words are matched as plain text, not as regular expressions.
#'
#' Cancelled registrations are included, after the active ones: a
#' delisted company has no ticker, which is when a CNPJ is most needed.
#' The registers hold today's names only; a company that changed its
#' name is found by the current one.
#'
#' @param name A single string: the company name, or part of it.
#' @param source One of `"mirror"` or `"cvm"`, as in [cvm_fetch()].
#'   `NULL` (default) resolves to the active backend via
#'   [cvm_source_get()].
#' @return A tibble with one row per registration: `cnpj_cia`,
#'   `denom_social`, `denom_comerc`, `cd_cvm`, `sit`, `dt_reg`,
#'   `dt_cancel` and `table` (the register the row comes from). Rows the
#'   CVM repeats per market (`tp_merc`) appear once. Active
#'   registrations (no `dt_cancel`) come first, then by `denom_social`.
#'   No match returns zero rows and a message.
#' @examples
#' \donttest{
#' hits <- cnpj_lookup("magazine luiza")
#' hits
#' cvm_fetch("dfp", "dre", cnpj = hits$cnpj_cia[1], basis = "con")
#' }
#' @family utilities
#' @seealso [cvm_fetch()], whose `cnpj` argument takes the result;
#'   its `ticker` argument is the shortcut for exchange-listed companies.
#' @export
cnpj_lookup <- function(name, source = NULL) {
  check_lookup_name(name)
  registers <- lapply(.lookup_registers, function(tbl) {
    cvm_fetch("cad", tbl, source = source)
  })
  names(registers) <- .lookup_registers
  out <- lookup_registers(registers, name)
  if (!nrow(out)) {
    cli::cli_inform(
      c(
        "No company register matches {.val {name}}.",
        "i" = "Try fewer or shorter words; every word must appear."
      ),
      class = "cvmdata_message_no_match"
    )
  }
  out
}

# The cad tables the lookup searches.
.lookup_registers <- c("companhias", "estrangeiras", "incentivadas")

check_lookup_name <- function(name) {
  if (
    !is.character(name) ||
      length(name) != 1L ||
      is.na(name) ||
      !nzchar(trimws(name))
  ) {
    cvmdata_abort(
      c(
        "{.arg name} must be a single, non-empty string.",
        "i" = "Search one company at a time."
      ),
      class = "cvmdata_error_input"
    )
  }
  invisible(name)
}

# Match `name` against a named list of cad registers (data frames with
# `cnpj_cia` or `cnpj`, `denom_social`, `denom_comerc`, `cd_cvm`, `sit`,
# `dt_reg`, `dt_cancel`). Pure: no I/O.
lookup_registers <- function(registers, name) {
  cols <- c(
    "cnpj_cia",
    "denom_social",
    "denom_comerc",
    "cd_cvm",
    "sit",
    "dt_reg",
    "dt_cancel"
  )
  parts <- lapply(names(registers), function(tbl) {
    df <- as.data.frame(registers[[tbl]])
    if (!"cnpj_cia" %in% names(df)) {
      names(df)[names(df) == "cnpj"] <- "cnpj_cia"
    }
    df <- df[, cols, drop = FALSE]
    df$table <- rep(tbl, nrow(df))
    df
  })
  all <- do.call(rbind, parts)
  words <- strsplit(normalize_company_name(name), " ", fixed = TRUE)[[1]]
  hay <- paste(
    normalize_company_name(all$denom_social),
    normalize_company_name(all$denom_comerc)
  )
  keep <- rep(TRUE, nrow(all))
  for (w in words) {
    keep <- keep & grepl(w, hay, fixed = TRUE)
  }
  out <- unique(all[keep, , drop = FALSE])
  ord <- order(!is.na(out$dt_cancel), out$denom_social, out$table)
  out <- out[ord, , drop = FALSE]
  rownames(out) <- NULL
  tibble::as_tibble(out)
}

# Upper case, accents folded to ASCII, runs of spaces collapsed. `NA`
# becomes "" so it never matches.
normalize_company_name <- function(x) {
  x <- toupper(enc2utf8(x))
  x[is.na(x)] <- ""
  x <- chartr(.accented, .unaccented, x)
  trimws(gsub("[[:space:]]+", " ", x, perl = TRUE))
}

# Upper-case accented letters of Portuguese, Spanish and French names
# and their ASCII form (as code points to keep the source ASCII).
.accented <- intToUtf8(
  c(
    0xC1,
    0xC0,
    0xC2,
    0xC3,
    0xC4, # A
    0xC9,
    0xC8,
    0xCA,
    0xCB, # E
    0xCD,
    0xCC,
    0xCE,
    0xCF, # I
    0xD3,
    0xD2,
    0xD4,
    0xD5,
    0xD6, # O
    0xDA,
    0xD9,
    0xDB,
    0xDC, # U
    0xC7,
    0xD1 # C, N
  )
)
.unaccented <- "AAAAAEEEEIIIIOOOOOUUUUCN"
