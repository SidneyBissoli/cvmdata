#' Fetch a CVM open-data table for a fund dataset
#'
#' Single entry point for retrieving any table from any CVM
#' fund-class dataset covered by the package. Covers investment
#' funds across three CKAN groups: `fundos-de-investimento`
#' (ICVM 555 funds), `fundos-de-investimento-imobiliarios` (FII)
#' and `fundos-estruturados` (FIP, FIDC, FAPI, etc.).
#'
#' Column names, categorical values and free-text fields are
#' preserved in Portuguese exactly as published by CVM
#' (snake_case minúsculo).
#'
#' In v0.1.0.9000 the function is exported as a skeleton documenting
#' the planned contract; calling it aborts with
#' `cvmdata_error_input_group` pointing to ROADMAP.md. Full
#' implementation arrives in v0.4 (`fundos-de-investimento`), v0.5
#' (`fundos-de-investimento-imobiliarios`) and v0.6
#' (`fundos-estruturados`).
#'
#' @param dataset Short dataset id (e.g. `"fi-cad"`,
#'   `"informe-diario"`, `"cda"`).
#' @param table Snake-case table name within the dataset.
#' @param fund Optional character vector of fund CNPJs to include.
#'   `NULL` (default) returns every fund. Free-text matching against
#'   fund denomination is **not** supported in the current API
#'   because CVM Resolution 175 (2023) restructured fund nomenclature
#'   into Classe / Subclasse / Razão Social columns that change
#'   between issues; CNPJ remains the stable identifier. Free-text
#'   matching may be added in v0.5+ if a stable column emerges.
#'   Singular naming follows tidyverse conventions; the argument
#'   still accepts vectors of any length.
#' @param date Optional `Date` vector of reference dates. `NULL`
#'   (default) fetches the latest available month or quarter.
#'   Reference dates are point-in-time (end-of-month for monthly
#'   reports, last business day of quarter for quarterly). Singular
#'   naming; the argument accepts vectors of any length. Pass
#'   `seq.Date()` for ranges or specific historical points.
#' @param source One of `"mirror"` (parquet via DuckDB) or `"cvm"`
#'   (CVM Open Data Portal). `NULL` (default) resolves to the
#'   active backend via [cvm_source_get()].
#' @param on_error One of `"abort"` (default), `"warn"` or
#'   `"silent"`. Controls behaviour on HTTP failures for batches of
#'   dated tables, analogously to [issuer_fetch()].
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
#' # Available from v0.4 onwards (fundos-de-investimento):
#' funds <- fund_fetch("fi-cad", "cad",
#'                     fund = "12.345.678/0001-90")
#'
#' # Available from v0.5 onwards (fundos-de-investimento-imobiliarios):
#' fii <- fund_fetch("fii", "informe-mensal",
#'                   date = as.Date("2024-03-31"))
#'
#' @family fetchers
#' @export
fund_fetch <- function(dataset, table,
                       fund     = NULL,
                       date     = NULL,
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
          "{.fn fund_fetch} accepts {.arg fund}, {.arg date},",
          "{.arg source}, {.arg on_error} and {.arg validate}."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  cvmdata_abort(
    c(
      paste(
        "{.fn fund_fetch} is exported as a skeleton in",
        "{.val 0.1.0.9000}; the fund datasets are not yet",
        "implemented."
      ),
      "i" = paste(
        "Groups {.val fundos-de-investimento},",
        "{.val fundos-de-investimento-imobiliarios} and",
        "{.val fundos-estruturados} arrive in v0.4-v0.6."
      ),
      "i" = "See {.file ROADMAP.md} for the release plan."
    ),
    class = c("cvmdata_error_input_group", "cvmdata_error_input")
  )
}
