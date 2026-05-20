#' Fetch the CVM company registry (CAD)
#'
#' Returns the current snapshot of the *Cadastro de Companhias Abertas*
#' published by CVM at <https://dados.cvm.gov.br/>. CAD is a
#' single-file dataset without temporal partitioning: each download
#' supersedes the previous one. Column names, categorical values and
#' free-text fields are preserved in Portuguese exactly as published
#' by CVM (snake_case minúsculo).
#'
#' @param companies Optional character vector of CVM codes (`cd_cvm`)
#'   or CNPJ numbers (with or without punctuation) used to filter the
#'   returned tibble. `NULL` (default) returns every row.
#' @param source One of `"auto"` (default; portal with mirror
#'   fallback), `"portal"` or `"mirror"`. Only `"auto"` and `"portal"`
#'   are wired in v0.1; `"mirror"` triggers an internal error.
#' @param on_error One of `"abort"` (default), `"warn"` or
#'   `"silent"`. Controls behaviour on HTTP failures and partial-batch
#'   errors. Only `"abort"` is wired in v0.1; the other values are
#'   reserved for the multi-entity batch operations of later
#'   sessions.
#' @param validate One of `"strict"` (default), `"warn"` or `"skip"`.
#'   Controls schema validation strictness at parse time (field count
#'   and, for tables with `meta_status: missing`, field names).
#' @param ... Reserved for forward compatibility.
#'
#' @return A tibble of class `cvm_tbl` carrying the five provenance
#'   attributes `source`, `fetched_at`, `dataset`, `table` and
#'   `package_version`. Identifier columns (`cnpj_cia`, `cd_cvm`,
#'   `cep`, telephone-related fields) are coerced to character.
#'   Date columns (`dt_*`) are parsed to `Date`.
#'
#' @examplesIf interactive()
#' companies <- cad_fetch()
#' dplyr::glimpse(companies)
#'
#' @family fetchers
#' @export
cad_fetch <- function(companies = NULL,
                      source = "auto",
                      on_error = "abort",
                      validate = "strict",
                      ...) {
  cvm_fetch_internal(
    dataset = "cad",
    table = "companhias",
    companies = companies,
    source = source,
    on_error = on_error,
    validate = validate,
    ...
  )
}

# Internal orchestrator. Dispatches across dataset-specific transforms
# in a `switch()` while Session 1 has only CAD. Generalised in
# Session 2 once at least two aliases share the pipeline.
cvm_fetch_internal <- function(dataset,
                               table,
                               companies = NULL,
                               years = NULL,
                               source = "auto",
                               on_error = "abort",
                               validate = "strict",
                               ...) {
  validate <- rlang::arg_match0(
    validate,
    c("strict", "warn", "skip")
  )
  source <- rlang::arg_match0(
    source,
    c("auto", "portal", "mirror")
  )
  on_error <- rlang::arg_match0(
    on_error,
    c("abort", "warn", "silent")
  )

  if (identical(source, "mirror")) {
    cvmdata_abort(
      c(
        "{.code source = \"mirror\"} not implemented in v0.1.",
        "i" = paste(
          "The GitHub Releases mirror lands in Phase F.",
          "Use {.val auto} or {.val portal} for now."
        )
      ),
      class = "cvmdata_error_input"
    )
  }

  schema <- load_schema(dataset, table)
  path <- source_cvm_http_get(schema, ...)
  raw <- read_cvm_csv(path, schema, validate = validate)

  out <- switch(
    dataset,
    cad = transform_cad(raw, schema),
    cvmdata_abort(
      c(
        "Unknown dataset {.val {dataset}}.",
        "i" = "Session 1 supports only {.val cad}."
      ),
      class = "cvmdata_error_internal"
    )
  )

  if (!is.null(companies)) {
    out <- filter_by_companies(out, companies)
  }

  cvm_attach_metadata(
    out,
    source = "portal",
    dataset = dataset,
    table = table
  )
}

# Filter a tibble by CD_CVM or CNPJ (with or without punctuation).
# Match is OR across the supported identifier columns when present.
filter_by_companies <- function(df, companies) {
  companies_chr <- as.character(companies)
  match_vec <- rep(FALSE, nrow(df))
  if ("cnpj_cia" %in% names(df)) {
    raw_cnpj <- df$cnpj_cia
    clean_cnpj <- cnpj_clean(raw_cnpj)
    match_vec <- match_vec |
      raw_cnpj %in% companies_chr |
      clean_cnpj %in% companies_chr
  }
  if ("cd_cvm" %in% names(df)) {
    match_vec <- match_vec | df$cd_cvm %in% companies_chr
  }
  df[match_vec, , drop = FALSE]
}
