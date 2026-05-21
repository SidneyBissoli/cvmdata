#' Fetch a CVM open-data table
#'
#' Single entry point for retrieving any table from any CVM dataset
#' covered by the package. Selects the right URL, downloads (or serves
#' from cache), parses, applies schema-declared transformations, and
#' returns a tibble carrying provenance attributes.
#'
#' Column names, categorical values and free-text fields are preserved
#' in Portuguese exactly as published by CVM (snake_case minúsculo).
#'
#' @param dataset Short dataset id (e.g. `"cad"`, `"dfp"`).
#' @param table Snake-case table name (e.g. `"companhias"`, `"bpa"`).
#'   For datasets with conceptually paired tables (individual /
#'   consolidated), `table` is the concept name and `report_type`
#'   selects the variant.
#' @param companies Optional character vector identifying companies to
#'   include. Accepts CNPJ (with or without punctuation), CD_CVM (with
#'   or without zero-padding), or free-text matched against
#'   `denom_cia`. Detection is automatic per element. `NULL` (default)
#'   returns every company.
#' @param years Integer vector of years to fetch. `NULL` (default)
#'   fetches the latest available year. Ignored for datasets with
#'   `temporal_partitioning: none` (e.g. CAD).
#' @param source One of `"mirror"` (default, parquet via DuckDB) or
#'   `"cvm"` (CVM open-data portal). The mirror is refreshed weekly
#'   against the CVM portal.
#' @param report_type One of `"ind"`, `"con"`, or `NULL`. Required for
#'   tables that publish individual and consolidated variants
#'   (`bpa`, `bpp`, `dre`, `dra`, `dfc_md`, `dfc_mi`, `dmpl`, `dva`).
#'   Must be `NULL` for tables without that distinction
#'   (`composicao_capital`, `submissao`, `parecer`, `companhias`).
#' @param on_error One of `"abort"` (default), `"warn"` or `"silent"`.
#'   Controls behaviour on HTTP failures and partial-batch errors.
#' @param validate One of `"strict"` (default), `"warn"` or `"skip"`.
#'   Controls schema validation strictness at parse time.
#' @param ... Reserved for forward compatibility.
#'
#' @return A tibble of class `cvm_tbl` carrying the five provenance
#'   attributes `source`, `fetched_at`, `dataset`, `table` and
#'   `package_version`.
#'
#' @examplesIf interactive()
#' # CAD: single snapshot, no temporal partitioning, no report_type
#' companies <- cvm_fetch("cad", "companhias")
#'
#' # DFP BPA individual, latest year, single company
#' bb <- cvm_fetch("dfp", "bpa",
#'                 report_type = "ind",
#'                 companies = "BCO BRASIL",
#'                 years = 2024)
#'
#' @family fetchers
#' @export
cvm_fetch <- function(dataset, table,
                      companies   = NULL,
                      years       = NULL,
                      source      = "mirror",
                      report_type = NULL,
                      on_error    = "abort",
                      validate    = "strict",
                      ...) {
  cvm_fetch_internal(
    dataset     = dataset,
    table       = table,
    companies   = companies,
    years       = years,
    source      = source,
    report_type = report_type,
    on_error    = on_error,
    validate    = validate,
    ...
  )
}

# Internal orchestrator. Validates arguments, dispatches per
# temporal_partitioning, applies schema-declared transformations,
# filters by companies, and attaches provenance metadata.
cvm_fetch_internal <- function(dataset,
                               table,
                               companies   = NULL,
                               years       = NULL,
                               source      = "mirror",
                               report_type = NULL,
                               on_error    = "abort",
                               validate    = "strict",
                               ...) {
  source <- rlang::arg_match0(source, c("mirror", "cvm"))
  validate <- rlang::arg_match0(
    validate, c("strict", "warn", "skip")
  )
  on_error <- rlang::arg_match0(
    on_error, c("abort", "warn", "silent")
  )
  if (!is.null(report_type)) {
    report_type <- rlang::arg_match0(report_type, c("ind", "con"))
  }

  if (identical(source, "mirror")) {
    cvmdata_abort(
      c(
        "{.code source = \"mirror\"} not implemented in v0.1.",
        "i" = paste(
          "The GitHub Releases mirror lands in Phase F (still in",
          "v0.1). Use {.val cvm} meanwhile."
        )
      ),
      class = "cvmdata_error_input"
    )
  }

  schema <- load_schema(dataset, table)

  # Resolve year selection. For yearly-partitioned tables, NULL means
  # latest published year. For non-partitioned tables, year is irrelevant.
  partitioning <- schema$temporal_partitioning %||% "none"
  if (identical(partitioning, "yearly")) {
    if (is.null(years)) {
      years <- cvm_dataset_years(dataset, schema = schema)
      years <- max(years, na.rm = TRUE)
    }
    years <- as.integer(years)
    raw_list <- lapply(years, function(yr) {
      path <- source_cvm_http_get(
        schema, year = yr, report_type = report_type, ...
      )
      read_cvm_csv(path, schema, validate = validate)
    })
    raw <- do.call(rbind, raw_list)
  } else {
    if (!is.null(years)) {
      cvmdata_abort(
        c(
          paste(
            "Table {.val {dataset}}/{.val {table}} is not",
            "yearly-partitioned; {.arg years} must be {.code NULL}."
          )
        ),
        class = "cvmdata_error_input"
      )
    }
    path <- source_cvm_http_get(
      schema, report_type = report_type, ...
    )
    raw <- read_cvm_csv(path, schema, validate = validate)
  }

  transformed <- apply_schema_transformations(raw, schema)

  if (!is.null(companies)) {
    transformed <- filter_by_companies(transformed, companies)
  }

  cvm_attach_metadata(
    transformed,
    source  = source,
    dataset = dataset,
    table   = table
  )
}

# Filter a tibble by automatic company-identifier detection.
# Implements the rules of CLAUDE.md §2.7.
filter_by_companies <- function(df, companies) {
  companies_chr <- as.character(companies)
  digits_only <- gsub("[^0-9]", "", companies_chr)

  is_cnpj <- nchar(digits_only) == 14L &
    nchar(companies_chr) >= 14L
  is_cdcvm <- !is_cnpj &
    grepl("^[0-9]{1,6}$", companies_chr)
  is_text <- !is_cnpj & !is_cdcvm

  match_vec <- rep(FALSE, nrow(df))

  if (any(is_cnpj) && "cnpj_cia" %in% names(df)) {
    targets <- digits_only[is_cnpj]
    df_clean <- cnpj_clean(df$cnpj_cia)
    match_vec <- match_vec | df_clean %in% targets
  }

  if (any(is_cdcvm) && "cd_cvm" %in% names(df)) {
    targets <- companies_chr[is_cdcvm]
    df_padded <- sprintf("%06s", df$cd_cvm)
    targets_padded <- sprintf("%06s", targets)
    match_vec <- match_vec |
      df$cd_cvm %in% targets |
      df_padded %in% targets_padded
  }

  if (any(is_text) && "denom_cia" %in% names(df)) {
    for (term in companies_chr[is_text]) {
      hits <- search_companies_textual(df$denom_cia, term)
      match_vec <- match_vec | hits
    }
  }

  df[match_vec, , drop = FALSE]
}

# Word-boundary substring matching with the abbreviation map of
# CLAUDE.md §2.7. Returns a logical vector aligned with `names_vec`.
search_companies_textual <- function(names_vec, query) {
  tokens <- strsplit(normalize_company_text(query), "\\s+")[[1L]]
  tokens <- tokens[nzchar(tokens)]
  if (!length(tokens)) {
    return(rep(FALSE, length(names_vec)))
  }
  names_norm <- normalize_company_text(names_vec)

  # All tokens must match (AND).
  hits <- rep(TRUE, length(names_vec))
  for (tok in tokens) {
    alternatives <- expand_abbreviations(tok)
    pattern <- paste0(
      "\\b(", paste(alternatives, collapse = "|"), ")\\b"
    )
    hits <- hits & grepl(pattern, names_norm, perl = TRUE)
  }
  hits
}

normalize_company_text <- function(x) {
  x <- toupper(as.character(x))
  accented <- intToUtf8(c(
    0x00C1, 0x00C2, 0x00C3, 0x00C0, 0x00C9, 0x00CA, 0x00CD,
    0x00D3, 0x00D4, 0x00D5, 0x00DA, 0x00DC, 0x00C7
  ))
  plain <- "AAAAEEIOOOUUC"
  x <- chartr(accented, plain, x)
  x <- gsub("[^A-Z0-9 ]+", " ", x)
  x <- gsub("\\s+", " ", x)
  trimws(x)
}

# Companion to normalize_company_text(): given a single normalized
# token, returns the set of alternative spellings to match (BANCO and
# BCO both stand in for the user's "banco"). List minimal here; expand
# empirically as needed.
expand_abbreviations <- function(token) {
  alt <- list(
    BANCO       = c("BANCO", "BCO"),
    BCO         = c("BANCO", "BCO"),
    COMPANHIA   = c("COMPANHIA", "CIA"),
    CIA         = c("COMPANHIA", "CIA"),
    INDUSTRIA   = c("INDUSTRIA", "IND"),
    INDUSTRIAS  = c("INDUSTRIAS", "INDS"),
    PARTICIPACOES = c("PARTICIPACOES", "PART"),
    PART        = c("PARTICIPACOES", "PART")
  )
  alt[[token]] %||% token
}
