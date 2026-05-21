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
#'   returns every company. When the target table does not carry a
#'   `cd_cvm` column (e.g. `composicao_capital`, `parecer`), CD_CVM
#'   tokens are resolved to CNPJ via the dataset's `submissao` table
#'   for the same year — the user-facing interface is identical
#'   regardless of which table holds CD_CVM natively.
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

  partitioning <- schema$temporal_partitioning %||% "none"
  if (identical(partitioning, "yearly")) {
    transformed <- fetch_yearly_partitioned(
      schema, dataset, years, companies, report_type, validate, ...
    )
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
    transformed <- fetch_one_year(
      schema, year = NULL, companies = companies,
      report_type = report_type, validate = validate, ...
    )
  }

  cvm_attach_metadata(
    transformed,
    source  = source,
    dataset = dataset,
    table   = table
  )
}

# Fetch + transform + filter for a single year (or a non-yearly
# table, when year is NULL). Returns the post-filter tibble.
fetch_one_year <- function(schema, year, companies, report_type,
                           validate, ...) {
  path <- source_cvm_http_get(
    schema, year = year, report_type = report_type, ...
  )
  raw <- read_cvm_csv(path, schema, validate = validate)
  transformed <- apply_schema_transformations(raw, schema)
  if (!is.null(companies)) {
    transformed <- filter_by_companies(
      transformed, companies, schema = schema, year = year
    )
  }
  transformed
}

# Year-selection logic for yearly-partitioned tables:
# - years explicit: fetch each year, rbind.
# - years NULL + companies NULL: fetch max year.
# - years NULL + companies non-NULL: try max year; if filter empty,
#   walk down up to .latest_year_max_tries years emitting a warning
#   when finally non-empty. The CVM portal lists the current civil
#   year as soon as the first non-civil-calendar filing arrives
#   (agribusiness companies often have fiscal years ending mid-year),
#   so the max-year ZIP may exist but lack civil-year filers.
.latest_year_max_tries <- 3L

fetch_yearly_partitioned <- function(schema, dataset, years, companies,
                                     report_type, validate, ...) {
  if (!is.null(years)) {
    years <- as.integer(years)
    parts <- lapply(years, function(yr) {
      fetch_one_year(schema, yr, companies, report_type, validate, ...)
    })
    return(do.call(rbind, parts))
  }

  available <- sort(
    cvm_dataset_years(dataset, schema = schema),
    decreasing = TRUE
  )
  candidates <- utils::head(available, .latest_year_max_tries)

  if (is.null(companies)) {
    return(fetch_one_year(
      schema, candidates[1L], companies = NULL,
      report_type = report_type, validate = validate, ...
    ))
  }

  tried <- integer(0L)
  out <- NULL
  for (yr in candidates) {
    tried <- c(tried, yr)
    out <- fetch_one_year(
      schema, yr, companies, report_type, validate, ...
    )
    if (nrow(out) > 0L) {
      if (length(tried) > 1L) {
        skipped <- tried[seq_len(length(tried) - 1L)]
        cvmdata_warn(
          c(
            paste(
              "{.arg years = NULL}: no rows for {.arg companies} in",
              "{.val {skipped}}; returning {.val {yr}} instead."
            ),
            "i" = paste(
              "The CVM portal publishes the current civil year as",
              "soon as the first non-civil-calendar filing arrives",
              "(e.g. agribusiness)."
            )
          ),
          class = "cvmdata_warn_year_fallback"
        )
      }
      return(out)
    }
  }
  out
}

# Classify each token in `companies` as CNPJ (14 digits), CD_CVM
# (1-6 digits), or free-text. Returns a list with parallel logical
# masks and the cleaned digits-only form (used for CNPJ matching).
classify_company_tokens <- function(companies_chr) {
  digits_only <- gsub("[^0-9]", "", companies_chr)
  is_cnpj <- nchar(digits_only) == 14L &
    nchar(companies_chr) >= 14L
  is_cdcvm <- !is_cnpj &
    grepl("^[0-9]{1,6}$", companies_chr)
  is_text <- !is_cnpj & !is_cdcvm
  list(
    digits_only = digits_only,
    is_cnpj = is_cnpj,
    is_cdcvm = is_cdcvm,
    is_text = is_text
  )
}

match_by_cnpj <- function(df, digits_only, mask) {
  if (!any(mask) || !"cnpj_cia" %in% names(df)) {
    return(rep(FALSE, nrow(df)))
  }
  cnpj_clean(df$cnpj_cia) %in% digits_only[mask]
}

match_by_cd_cvm <- function(df, companies_chr, mask) {
  if (!any(mask) || !"cd_cvm" %in% names(df)) {
    return(rep(FALSE, nrow(df)))
  }
  targets <- companies_chr[mask]
  # `%06s` pads with spaces, not zeros — must use formatC with a
  # decimal format to get "9512" -> "009512".
  df_padded <- formatC(
    suppressWarnings(as.integer(df$cd_cvm)),
    width = 6, flag = "0", format = "d"
  )
  targets_padded <- formatC(
    as.integer(targets),
    width = 6, flag = "0", format = "d"
  )
  df$cd_cvm %in% targets | df_padded %in% targets_padded
}

match_by_text <- function(df, companies_chr, mask) {
  if (!any(mask) || !"denom_cia" %in% names(df)) {
    return(rep(FALSE, nrow(df)))
  }
  match_vec <- rep(FALSE, nrow(df))
  for (term in companies_chr[mask]) {
    hits <- search_companies_textual(df$denom_cia, term)
    if (any(hits)) {
      hits <- disambiguate_text_match(df, hits, term)
    }
    match_vec <- match_vec | hits
  }
  match_vec
}

# Filter a tibble by automatic company-identifier detection.
# Implements the rules of CLAUDE.md §2.7.
#
# When the target table does not carry a `cd_cvm` column (e.g.
# composicao_capital, parecer in ITR/DFP) but the user supplied CD_CVM
# identifiers, resolve them to CNPJs via the `submissao` table of the
# same dataset/year. Requires `schema` and `year` to be passed by the
# caller; without them the CD_CVM tokens silently fail to match.
filter_by_companies <- function(df, companies,
                                schema = NULL, year = NULL) {
  companies_chr <- as.character(companies)
  cls <- classify_company_tokens(companies_chr)

  if (any(cls$is_cdcvm) && !("cd_cvm" %in% names(df)) &&
      !is.null(schema) && !is.null(year)) {
    resolved <- resolve_cd_cvm_via_submissao(
      companies_chr[cls$is_cdcvm], schema, year
    )
    companies_chr[cls$is_cdcvm] <- resolved
    cls <- classify_company_tokens(companies_chr)
  }

  match_vec <- match_by_cnpj(df, cls$digits_only, cls$is_cnpj) |
    match_by_cd_cvm(df, companies_chr, cls$is_cdcvm) |
    match_by_text(df, companies_chr, cls$is_text)

  df[match_vec, , drop = FALSE]
}

# Resolve CD_CVM identifiers to CNPJs via the dataset's `submissao`
# table for the given year. Used when the target table lacks `cd_cvm`
# but the user supplied CD_CVM tokens (CLAUDE.md §2.7, Opção D).
# Aborts with cvmdata_error_input if any CD_CVM is not present in
# submissao for that year, or if the dataset lacks a submissao table.
resolve_cd_cvm_via_submissao <- function(cd_cvm_targets, schema, year) {
  dataset <- schema$dataset
  available <- tryCatch(
    cvm_tables(dataset),
    error = function(e) character(0L)
  )
  if (!"submissao" %in% available) {
    cvmdata_abort(
      c(
        paste(
          "Table {.val {dataset}}/{.val {schema$table}} does not carry",
          "{.code cd_cvm}, and dataset {.val {dataset}} has no",
          "{.code submissao} table to resolve CD_CVM identifiers."
        ),
        "i" = paste(
          "Pass {.arg companies} as CNPJ (with or without punctuation)",
          "or as free text matched against {.code denom_cia}."
        )
      ),
      class = "cvmdata_error_input"
    )
  }

  cli::cli_inform(c(
    "i" = paste0(
      "Resolving CD_CVM ", paste(cd_cvm_targets, collapse = ", "),
      " via {.val {dataset}}/submissao for {.val {year}}",
      " (table {.val {schema$table}} does not carry {.code cd_cvm})."
    )
  ))

  sub_schema <- load_schema(dataset, "submissao")
  path <- source_cvm_http_get(
    sub_schema, year = year, report_type = NULL
  )
  sub_df <- read_cvm_csv(path, sub_schema, validate = "skip")

  sub_cd_padded <- formatC(
    suppressWarnings(as.integer(sub_df$cd_cvm)),
    width = 6, flag = "0", format = "d"
  )
  targets_padded <- formatC(
    as.integer(cd_cvm_targets),
    width = 6, flag = "0", format = "d"
  )

  resolved <- vapply(targets_padded, function(tp) {
    idx <- which(sub_cd_padded == tp)[1L]
    if (is.na(idx)) NA_character_ else sub_df$cnpj_cia[idx]
  }, character(1L), USE.NAMES = FALSE)

  missing_mask <- is.na(resolved)
  if (any(missing_mask)) {
    not_found <- cd_cvm_targets[missing_mask]
    cvmdata_abort(
      c(
        paste(
          "CD_CVM not found in {.val {dataset}}/submissao for",
          "{.val {year}}: {.val {not_found}}."
        ),
        "i" = paste(
          "Confirm the company filed in that year or pass",
          "{.arg companies} as CNPJ."
        )
      ),
      class = "cvmdata_error_input"
    )
  }

  resolved
}

# Apply CLAUDE.md §2.7 policy when a textual `companies` term matches
# more than one company: interactive → utils::menu(); batch → abort.
# Returns a logical vector aligned with `df` rows.
#
# `is_interactive` is injectable so tests can simulate both modes
# without relying on testthat::local_mocked_bindings against the
# `base::interactive` primitive (which isn't explicitly imported).
disambiguate_text_match <- function(df, hits, term,
                                    is_interactive = interactive()) {
  key_col <- if ("cd_cvm" %in% names(df)) "cd_cvm" else "denom_cia"
  matched <- df[hits, , drop = FALSE]
  unique_keys <- unique(matched[[key_col]])
  if (length(unique_keys) <= 1L) {
    return(hits)
  }
  unique_rows <- !duplicated(matched[[key_col]])
  matches_tbl <- matched[unique_rows, , drop = FALSE]
  matches_tbl <- matches_tbl[order(matches_tbl$denom_cia), , drop = FALSE]

  if (!is_interactive) {
    abort_on_multiple_matches(term, matches_tbl)
  }
  chosen <- prompt_for_company_choice(term, matches_tbl, key_col)
  hits & df[[key_col]] %in% chosen
}

abort_on_multiple_matches <- function(term, matches_tbl) {
  labels <- paste0(matches_tbl$cd_cvm, " : ", matches_tbl$denom_cia)
  bullets <- rlang::set_names(labels, rep("*", length(labels)))
  cvmdata_abort(
    c(
      "Multiple companies match {.val {term}}.",
      "i" = paste(
        "Pass {.arg companies} as CD_CVM or CNPJ to disambiguate,",
        "or run interactively to pick from a menu."
      ),
      bullets
    ),
    class = "cvmdata_error_input"
  )
}

prompt_for_company_choice <- function(term, matches_tbl, key_col) {
  labels <- paste(matches_tbl$cd_cvm, "-", matches_tbl$denom_cia)
  n <- length(labels)
  cli::cli_inform(c(
    "i" = "Multiple companies match {.val {term}}."
  ))
  choice <- utils::menu(
    choices = c(labels, "All of the above"),
    title = "Select a company (0 to cancel):"
  )
  if (identical(as.integer(choice), 0L)) {
    cvmdata_abort(
      c("Company selection cancelled by user."),
      class = "cvmdata_error_input"
    )
  }
  if (identical(as.integer(choice), as.integer(n + 1L))) {
    return(matches_tbl[[key_col]])
  }
  matches_tbl[[key_col]][choice]
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
