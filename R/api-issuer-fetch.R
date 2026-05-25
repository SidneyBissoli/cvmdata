#' Fetch a CVM open-data table for an issuer dataset
#'
#' Single entry point for retrieving any table from any CVM
#' issuer-class dataset covered by the package. Selects the right URL,
#' downloads (or serves from cache), parses, applies schema-declared
#' transformations, and returns a tibble carrying provenance
#' attributes.
#'
#' Column names, categorical values and free-text fields are preserved
#' in Portuguese exactly as published by CVM (snake_case minúsculo).
#'
#' @param dataset Short dataset id (e.g. `"cad"`, `"dfp"`).
#' @param table Snake-case table name (e.g. `"companhias"`, `"bpa"`).
#'   For datasets with conceptually paired tables (individual /
#'   consolidated), `table` is the concept name and `report_type`
#'   selects the variant.
#' @param issuer Optional character vector identifying issuers to
#'   include. Accepts CNPJ (with or without punctuation), CD_CVM (with
#'   or without zero-padding), or free-text matched against
#'   `denom_cia`. Detection is automatic per element. `NULL` (default)
#'   returns every issuer. Singular naming follows tidyverse
#'   conventions; the argument still accepts vectors of any length.
#'   When the target table does not carry a `cd_cvm` column (e.g.
#'   `composicao_capital`, `parecer`), CD_CVM tokens are resolved to
#'   CNPJ via the dataset's `submissao` table for the same year — the
#'   user-facing interface is identical regardless of which table
#'   holds CD_CVM natively.
#' @param year Integer vector of years to fetch. `NULL` (default)
#'   fetches the latest available year. Ignored for datasets with
#'   `temporal_partitioning: none` (e.g. CAD). Singular naming follows
#'   tidyverse conventions; the argument still accepts vectors of any
#'   length.
#' @param source One of `"mirror"` (parquet via DuckDB) or `"cvm"`
#'   (CVM Open Data Portal). `NULL` (default) resolves to the active
#'   backend via [cvm_source_get()] — `"mirror"` from v0.1.0 onward
#'   unless the user has flipped it via
#'   `cvm_source_set("cvm")`.
#' @param report_type One of `"ind"`, `"con"`, or `NULL`. Required for
#'   tables that publish individual and consolidated variants
#'   (`bpa`, `bpp`, `dre`, `dra`, `dfc_md`, `dfc_mi`, `dmpl`, `dva`).
#'   Must be `NULL` for tables without that distinction
#'   (`composicao_capital`, `submissao`, `parecer`, `companhias`).
#' @param on_error One of `"abort"` (default), `"warn"` or `"silent"`.
#'   Controls behaviour on HTTP failures for batches of yearly tables
#'   (`year = c(...)` with more than one element). With `"warn"`, the
#'   failed years are skipped and a `cvmdata_warn_partial_failure`
#'   warning lists them; with `"silent"`, the failed years are skipped
#'   silently; with `"abort"`, the first failure aborts the call. Total
#'   batch failure (every year fails) always aborts regardless of the
#'   setting — there is no partial result to return. Parse/validation
#'   failures are governed by `validate`, not `on_error`. Single-year
#'   calls, non-yearly tables, and the implicit fallback when
#'   `year = NULL` always abort on HTTP failure.
#' @param validate One of `"strict"` (default), `"warn"` or `"skip"`.
#'   Controls schema validation strictness at parse time.
#' @param ... Reserved for forward compatibility. Currently no extra
#'   arguments are accepted; passing any aborts with
#'   `cvmdata_error_input`.
#'
#' @return A tibble of class `cvm_tbl` carrying the five provenance
#'   attributes `source`, `fetched_at`, `dataset`, `table` and
#'   `package_version`.
#'
#' @examplesIf interactive()
#' # CAD: single snapshot, no temporal partitioning, no report_type
#' issuers <- issuer_fetch("cad", "companhias")
#'
#' # DFP BPA individual, latest year, single issuer
#' bb <- issuer_fetch("dfp", "bpa",
#'                    report_type = "ind",
#'                    issuer = "BCO BRASIL",
#'                    year = 2024)
#'
#' @family fetchers
#' @export
issuer_fetch <- function(dataset, table,
                         issuer      = NULL,
                         year        = NULL,
                         source      = NULL,
                         report_type = NULL,
                         on_error    = "abort",
                         validate    = "strict",
                         ...) {
  dots <- list(...)
  if (length(dots) > 0L) {
    nms <- names(dots) %||% rep("", length(dots))
    nms[!nzchar(nms)] <- "<unnamed>"
    cvmdata_abort(
      c(
        "Unknown argument{?s}: {.arg {nms}}.",
        "i" = paste(
          "Did you mean {.arg issuer} (was {.arg companies}) or",
          "{.arg year} (was {.arg years})?"
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  if (is.null(source)) {
    source <- cvm_source_get()
  }
  issuer_fetch_internal(
    dataset     = dataset,
    table       = table,
    issuer      = issuer,
    year        = year,
    source      = source,
    report_type = report_type,
    on_error    = on_error,
    validate    = validate
  )
}

# Internal orchestrator. Validates arguments, dispatches per
# temporal_partitioning, applies schema-declared transformations,
# filters by issuer, and attaches provenance metadata.
issuer_fetch_internal <- function(dataset,
                                  table,
                                  issuer      = NULL,
                                  year        = NULL,
                                  source      = "mirror",
                                  report_type = NULL,
                                  on_error    = "abort",
                                  validate    = "strict") {
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

  schema <- load_schema(dataset, table)

  if (identical(source, "mirror")) {
    transformed <- fetch_via_mirror(
      schema, dataset, year, issuer, report_type
    )
    return(cvm_attach_metadata(
      transformed,
      source  = source,
      dataset = dataset,
      table   = table
    ))
  }

  partitioning <- schema$temporal_partitioning %||% "none"
  if (identical(partitioning, "yearly")) {
    transformed <- fetch_yearly_partitioned(
      schema, dataset, year, issuer, report_type, validate,
      on_error
    )
  } else {
    if (!is.null(year)) {
      cvmdata_abort(
        c(
          paste(
            "Table {.val {dataset}}/{.val {table}} is not",
            "yearly-partitioned; {.arg year} must be {.code NULL}."
          )
        ),
        class = "cvmdata_error_input"
      )
    }
    transformed <- fetch_one_year(
      schema, year = NULL, issuer = issuer,
      report_type = report_type, validate = validate
    )
  }

  cvm_attach_metadata(
    transformed,
    source  = source,
    dataset = dataset,
    table   = table
  )
}

# Mirror path of `issuer_fetch_internal()`. The backend already returns
# a tibble in the post-transformation shape (the ETL applied the same
# `apply_schema_transformations()` step before writing parquet), so
# the orchestrator only has to layer `filter_by_issuer()` and the
# provenance metadata on top.
fetch_via_mirror <- function(schema, dataset, year, issuer,
                             report_type) {
  transformed <- source_mirror_duckdb_get(
    schema, year = year, report_type = report_type
  )
  if (!is.null(issuer)) {
    # `filter_by_issuer()` may need the dataset's `submissao` table to
    # resolve CD_CVM tokens when the target table lacks `cd_cvm`.
    # `resolve_cd_cvm_via_submissao()` uses the CVM HTTP path because
    # it loads the submissao via `source_cvm_http_get()`. That keeps
    # the resolution self-consistent within v0.1; a future iteration
    # may route the submissao lookup through the mirror as well.
    resolved_year <- if (!is.null(year)) year[[1L]] else
      max(transformed$year %||% NA_integer_, na.rm = TRUE)
    if (is.infinite(resolved_year) || is.na(resolved_year)) {
      resolved_year <- NULL
    }
    transformed <- filter_by_issuer(
      transformed, issuer, schema = schema, year = resolved_year
    )
  }
  transformed
}

# Fetch + transform + filter for a single year (or a non-yearly
# table, when year is NULL). Returns the post-filter tibble.
fetch_one_year <- function(schema, year, issuer, report_type,
                           validate) {
  path <- source_cvm_http_get(
    schema, year = year, report_type = report_type
  )
  raw <- read_cvm_csv(path, schema, validate = validate)
  transformed <- apply_schema_transformations(raw, schema)
  if (!is.null(issuer)) {
    transformed <- filter_by_issuer(
      transformed, issuer, schema = schema, year = year
    )
  }
  transformed
}

# Year-selection logic for yearly-partitioned tables:
# - year explicit: fetch each year, rbind.
# - year NULL + issuer NULL: fetch max year.
# - year NULL + issuer non-NULL: try max year; if filter empty,
#   walk down up to .latest_year_max_tries years emitting a warning
#   when finally non-empty. The CVM portal lists the current civil
#   year as soon as the first non-civil-calendar filing arrives
#   (agribusiness issuers often have fiscal years ending mid-year),
#   so the max-year ZIP may exist but lack civil-year filers.
.latest_year_max_tries <- 3L

fetch_yearly_partitioned <- function(schema, dataset, year, issuer,
                                     report_type, validate,
                                     on_error = "abort") {
  if (!is.null(year)) {
    return(fetch_explicit_years(
      schema, year, issuer, report_type, validate, on_error
    ))
  }

  available <- sort(
    cvm_dataset_years(dataset, schema = schema),
    decreasing = TRUE
  )
  candidates <- utils::head(available, .latest_year_max_tries)

  if (is.null(issuer)) {
    return(fetch_one_year(
      schema, candidates[1L], issuer = NULL,
      report_type = report_type, validate = validate
    ))
  }

  tried <- integer(0L)
  out <- NULL
  for (yr in candidates) {
    tried <- c(tried, yr)
    out <- fetch_one_year(
      schema, yr, issuer, report_type, validate
    )
    if (nrow(out) > 0L) {
      if (length(tried) > 1L) {
        skipped <- tried[seq_len(length(tried) - 1L)]
        cvmdata_warn(
          c(
            paste(
              "{.arg year = NULL}: no rows for {.arg issuer} in",
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

# Explicit-year branch of fetch_yearly_partitioned. Honors `on_error`
# for HTTP failures only (parse/validation failures still abort — they
# are governed by `validate`). With `"abort"` (default) the first
# failure propagates; with `"warn"` failing years are skipped and a
# `cvmdata_warn_partial_failure` warning lists them; with `"silent"`
# failing years are skipped without notice. Total batch failure always
# aborts with `cvmdata_error_http` regardless of `on_error` — there is
# no partial result to return and silently producing an empty tibble
# would mask outages.
fetch_explicit_years <- function(schema, year, issuer, report_type,
                                 validate, on_error) {
  year <- as.integer(year)
  if (identical(on_error, "abort")) {
    parts <- lapply(year, function(yr) {
      fetch_one_year(schema, yr, issuer, report_type, validate)
    })
    return(do.call(rbind, parts))
  }
  attempts <- lapply(year, function(yr) {
    tryCatch(
      list(year = yr, ok = TRUE, value = fetch_one_year(
        schema, yr, issuer, report_type, validate
      )),
      cvmdata_error_http = function(e) {
        list(year = yr, ok = FALSE, error = e)
      }
    )
  })
  ok_mask <- vapply(attempts, `[[`, logical(1L), "ok")
  successes <- lapply(attempts[ok_mask], `[[`, "value")
  failures <- attempts[!ok_mask]
  if (!length(successes)) {
    failed_years <- vapply(failures, `[[`, integer(1L), "year")
    n_failed <- length(failed_years)
    cvmdata_abort(
      c(
        "All {n_failed} requested year{?s} failed to download.",
        "x" = "Failed: {.val {failed_years}}.",
        "i" = paste(
          "First failure:",
          conditionMessage(failures[[1L]]$error)
        )
      ),
      class = "cvmdata_error_http"
    )
  }
  if (length(failures) && identical(on_error, "warn")) {
    failed_years <- vapply(failures, `[[`, integer(1L), "year")
    n_failed <- length(failed_years)
    n_total <- length(year)
    n_ok <- length(successes)
    cvmdata_warn(
      c(
        paste(
          "{n_failed} of {n_total} year{?s} failed to download;",
          "returning the {n_ok} that succeeded."
        ),
        "i" = "Failed: {.val {failed_years}}."
      ),
      class = "cvmdata_warn_partial_failure"
    )
  }
  do.call(rbind, successes)
}

# Classify each token in `issuer` as CNPJ (14 digits), CD_CVM
# (1-6 digits), or free-text. Returns a list with parallel logical
# masks and the cleaned digits-only form (used for CNPJ matching).
classify_issuer_tokens <- function(issuer_chr) {
  digits_only <- gsub("[^0-9]", "", issuer_chr)
  is_cnpj <- nchar(digits_only) == 14L &
    nchar(issuer_chr) >= 14L
  is_cdcvm <- !is_cnpj &
    grepl("^[0-9]{1,6}$", issuer_chr)
  is_text <- !is_cnpj & !is_cdcvm
  list(
    digits_only = digits_only,
    is_cnpj = is_cnpj,
    is_cdcvm = is_cdcvm,
    is_text = is_text
  )
}

match_by_cnpj <- function(df, digits_only, mask) {
  if (!any(mask)) {
    return(rep(FALSE, nrow(df)))
  }
  # CAD/ITR/DFP submissao use cnpj_cia; FRE-detail tables use
  # cnpj_companhia (CLAUDE.md §2.2). Read whichever is present.
  col <- cnpj_col(df)
  if (is.null(col)) {
    return(rep(FALSE, nrow(df)))
  }
  cnpj_clean(df[[col]]) %in% digits_only[mask]
}

# Detect which CNPJ column the tibble uses. Returns NULL when neither
# is present (CAD pre-filter, schemas without issuer metadata).
cnpj_col <- function(df) {
  if ("cnpj_cia" %in% names(df)) {
    return("cnpj_cia")
  }
  if ("cnpj_companhia" %in% names(df)) {
    return("cnpj_companhia")
  }
  NULL
}

# Detect which company-name column the tibble uses, analogous to
# cnpj_col(). FRE-detail uses nome_companhia; everything else denom_cia.
name_col <- function(df) {
  if ("denom_cia" %in% names(df)) {
    return("denom_cia")
  }
  if ("nome_companhia" %in% names(df)) {
    return("nome_companhia")
  }
  NULL
}

match_by_cd_cvm <- function(df, issuer_chr, mask) {
  if (!any(mask) || !"cd_cvm" %in% names(df)) {
    return(rep(FALSE, nrow(df)))
  }
  targets <- issuer_chr[mask]
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

match_by_text <- function(df, issuer_chr, mask) {
  if (!any(mask)) {
    return(rep(FALSE, nrow(df)))
  }
  ncol_name <- name_col(df)
  if (is.null(ncol_name)) {
    return(rep(FALSE, nrow(df)))
  }
  match_vec <- rep(FALSE, nrow(df))
  for (term in issuer_chr[mask]) {
    hits <- search_issuers_textual(df[[ncol_name]], term)
    if (!any(hits)) {
      cvmdata_abort(
        c(
          "No issuers match {.val {term}}.",
          "i" = paste(
            "Verify the spelling, or pass {.arg issuer} as CD_CVM",
            "or CNPJ."
          )
        ),
        class = "cvmdata_error_input"
      )
    }
    hits <- disambiguate_text_match(df, hits, term)
    match_vec <- match_vec | hits
  }
  match_vec
}

# Filter a tibble by automatic issuer-identifier detection.
# Implements the rules of CLAUDE.md §2.7.
#
# When the target table does not carry a `cd_cvm` column (e.g.
# composicao_capital, parecer in ITR/DFP) but the user supplied CD_CVM
# identifiers, resolve them to CNPJs via the `submissao` table of the
# same dataset/year. Requires `schema` and `year` to be passed by the
# caller; without them the CD_CVM tokens silently fail to match.
filter_by_issuer <- function(df, issuer,
                             schema = NULL, year = NULL) {
  issuer_chr <- as.character(issuer)
  cls <- classify_issuer_tokens(issuer_chr)

  if (any(cls$is_cdcvm) && !("cd_cvm" %in% names(df)) &&
      !is.null(schema) && !is.null(year)) {
    resolved <- resolve_cd_cvm_via_submissao(
      issuer_chr[cls$is_cdcvm], schema, year
    )
    issuer_chr[cls$is_cdcvm] <- resolved
    cls <- classify_issuer_tokens(issuer_chr)
  }

  match_vec <- match_by_cnpj(df, cls$digits_only, cls$is_cnpj) |
    match_by_cd_cvm(df, issuer_chr, cls$is_cdcvm) |
    match_by_text(df, issuer_chr, cls$is_text)

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
          "Pass {.arg issuer} as CNPJ (with or without punctuation)",
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
          "Confirm the issuer filed in that year or pass",
          "{.arg issuer} as CNPJ."
        )
      ),
      class = "cvmdata_error_input"
    )
  }

  resolved
}

# Apply CLAUDE.md §2.7 policy when a textual `issuer` term matches
# more than one issuer: interactive → utils::menu(); batch → abort.
# Returns a logical vector aligned with `df` rows.
#
# `is_interactive` is injectable so tests can simulate both modes
# without relying on testthat::local_mocked_bindings against the
# `base::interactive` primitive (which isn't explicitly imported).
disambiguate_text_match <- function(df, hits, term,
                                    is_interactive = interactive()) {
  # Preferred id is cd_cvm (CAD/submissao); falls back to whichever
  # CNPJ column the table carries (FRE-detail has only cnpj_companhia).
  id_col <- if ("cd_cvm" %in% names(df)) "cd_cvm" else cnpj_col(df)
  if (is.null(id_col)) {
    return(hits)
  }
  label_col <- name_col(df)
  matched <- df[hits, , drop = FALSE]
  unique_keys <- unique(matched[[id_col]])
  if (length(unique_keys) <= 1L) {
    return(hits)
  }
  unique_rows <- !duplicated(matched[[id_col]])
  matches_tbl <- matched[unique_rows, , drop = FALSE]
  if (!is.null(label_col)) {
    matches_tbl <- matches_tbl[order(matches_tbl[[label_col]]),
                               , drop = FALSE]
  }

  if (!is_interactive) {
    abort_on_multiple_matches(term, matches_tbl, id_col, label_col)
  }
  chosen <- prompt_for_issuer_choice(
    term, matches_tbl, id_col, label_col
  )
  hits & df[[id_col]] %in% chosen
}

abort_on_multiple_matches <- function(term, matches_tbl,
                                      id_col, label_col) {
  ids <- matches_tbl[[id_col]]
  labels <- if (!is.null(label_col)) {
    paste0(ids, " : ", matches_tbl[[label_col]])
  } else {
    ids
  }
  bullets <- rlang::set_names(labels, rep("*", length(labels)))
  cvmdata_abort(
    c(
      "Multiple issuers match {.val {term}}.",
      "i" = paste(
        "Pass {.arg issuer} as CD_CVM or CNPJ to disambiguate,",
        "or run interactively to pick from a menu."
      ),
      bullets
    ),
    class = "cvmdata_error_input"
  )
}

prompt_for_issuer_choice <- function(term, matches_tbl,
                                     id_col, label_col) {
  ids <- matches_tbl[[id_col]]
  labels <- if (!is.null(label_col)) {
    paste(ids, "-", matches_tbl[[label_col]])
  } else {
    ids
  }
  n <- length(labels)
  cli::cli_inform(c(
    "i" = "Multiple issuers match {.val {term}}."
  ))
  choice <- utils::menu(
    choices = c(labels, "All of the above"),
    title = "Select an issuer (0 to cancel):"
  )
  if (identical(as.integer(choice), 0L)) {
    cvmdata_abort(
      c("Issuer selection cancelled by user."),
      class = "cvmdata_error_input"
    )
  }
  if (identical(as.integer(choice), as.integer(n + 1L))) {
    return(matches_tbl[[id_col]])
  }
  matches_tbl[[id_col]][choice]
}

# Word-boundary substring matching with the abbreviation map of
# CLAUDE.md §2.7. Returns a logical vector aligned with `names_vec`.
search_issuers_textual <- function(names_vec, query) {
  tokens <- strsplit(normalize_issuer_text(query), "\\s+")[[1L]]
  tokens <- tokens[nzchar(tokens)]
  if (!length(tokens)) {
    return(rep(FALSE, length(names_vec)))
  }
  names_norm <- normalize_issuer_text(names_vec)

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

normalize_issuer_text <- function(x) {
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

# Companion to normalize_issuer_text(): given a single normalized
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
