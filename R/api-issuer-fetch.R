# Fetch engine behind `cvm_fetch()` (and the mirror ETL, which calls it
# with `source = "cvm"`): validates arguments, dispatches per
# temporal_partitioning, applies schema-declared transformations, filters
# by issuer CNPJ, checks filings and attaches provenance metadata. The
# exported `issuer_fetch()` that wrapped it was removed on 2026-11-01.

issuer_fetch_internal <- function(
  dataset,
  table,
  issuer = NULL,
  year = NULL,
  source = "mirror",
  report_type = NULL,
  on_error = "abort",
  validate = "strict"
) {
  source <- rlang::arg_match0(source, c("mirror", "cvm"))
  validate <- rlang::arg_match0(
    validate,
    c("strict", "warn", "skip")
  )
  on_error <- rlang::arg_match0(
    on_error,
    c("abort", "warn", "silent")
  )
  if (!is.null(report_type)) {
    report_type <- rlang::arg_match0(report_type, c("ind", "con"))
  }

  schema <- load_schema(dataset, table)

  # Drop explicitly-requested years before the dataset's first published
  # year, for both backends, so a "year before the dataset existed"
  # request is a clean user-input concern rather than a backend HTTP 404
  # (source = "cvm") or a silent empty read (source = "mirror"). Genuine
  # network 404s on years that do exist stay governed by `on_error`.
  if (
    !is.null(year) &&
      identical(schema$temporal_partitioning %||% "none", "yearly")
  ) {
    year <- clamp_years_to_first(year, schema)
  }

  if (identical(source, "mirror")) {
    transformed <- fetch_via_mirror(
      schema,
      dataset,
      year,
      issuer,
      report_type
    )
    transformed <- check_filings(
      transformed,
      schema,
      dataset = dataset,
      table = table,
      year = year,
      source = source,
      validate = validate
    )
    return(cvm_attach_metadata(
      transformed,
      source = source,
      group = schema$group,
      dataset = dataset,
      table = table
    ))
  }

  partitioning <- schema$temporal_partitioning %||% "none"
  if (identical(partitioning, "yearly")) {
    transformed <- fetch_yearly_partitioned(
      schema,
      dataset,
      year,
      issuer,
      report_type,
      validate,
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
      schema,
      year = NULL,
      issuer = issuer,
      report_type = report_type,
      validate = validate
    )
  }
  transformed <- check_filings(
    transformed,
    schema,
    dataset = dataset,
    table = table,
    year = year,
    source = source,
    validate = validate
  )

  cvm_attach_metadata(
    transformed,
    source = source,
    group = schema$group,
    dataset = dataset,
    table = table
  )
}

# Mirror path of `issuer_fetch_internal()`. The backend already returns
# a tibble in the post-transformation shape (the ETL applied the same
# `apply_schema_transformations()` step before writing parquet), so
# the orchestrator only has to layer `filter_by_issuer()` and the
# provenance metadata on top.
fetch_via_mirror <- function(schema, dataset, year, issuer, report_type) {
  transformed <- source_mirror_duckdb_get(
    schema,
    year = year,
    report_type = report_type
  )
  if (!is.null(issuer)) {
    transformed <- filter_by_issuer(transformed, issuer)
  }
  transformed
}

# Fetch + transform + filter for a single year (or a non-yearly
# table, when year is NULL). Returns the post-filter tibble. With
# `keep_versions = TRUE` (only `cvm_versions()` asks for it) the
# `keep_latest_version` transformation is skipped, so every filing the
# CSV carries survives.
fetch_one_year <- function(
  schema,
  year,
  issuer,
  report_type,
  validate,
  keep_versions = FALSE
) {
  path <- source_cvm_http_get(
    schema,
    year = year,
    report_type = report_type
  )
  raw <- read_cvm_csv(path, schema, validate = validate)
  transformed <- apply_schema_transformations(
    raw,
    schema,
    skip = if (keep_versions) "keep_latest_version" else NULL
  )
  if (!is.null(issuer)) {
    transformed <- filter_by_issuer(transformed, issuer)
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

fetch_yearly_partitioned <- function(
  schema,
  dataset,
  year,
  issuer,
  report_type,
  validate,
  on_error = "abort",
  keep_versions = FALSE
) {
  if (!is.null(year)) {
    return(fetch_explicit_years(
      schema,
      year,
      issuer,
      report_type,
      validate,
      on_error,
      keep_versions = keep_versions
    ))
  }

  available <- sort(
    cvm_dataset_years(dataset, schema = schema),
    decreasing = TRUE
  )
  candidates <- utils::head(available, .latest_year_max_tries)

  if (is.null(issuer)) {
    return(fetch_one_year(
      schema,
      candidates[1L],
      issuer = NULL,
      report_type = report_type,
      validate = validate,
      keep_versions = keep_versions
    ))
  }

  tried <- integer(0L)
  out <- NULL
  for (i in seq_along(candidates)) {
    yr <- candidates[[i]]
    tried <- c(tried, yr)
    out <- fetch_one_year(
      schema,
      yr,
      issuer,
      report_type,
      validate,
      keep_versions = keep_versions
    )
    if (nrow(out) > 0L) {
      if (length(tried) > 1L) {
        skipped <- tried[seq_len(length(tried) - 1L)]
        cvmdata_warn(
          c(
            paste(
              "{.arg year = NULL}: no rows for the requested issuer in",
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

# Drop requested years that precede the dataset's first published year
# (schema$first_year, guaranteed a valid integer for yearly tables by
# load_schema()). Emits an informational message listing the dropped
# years and returns the survivors as an integer vector. Aborts with
# cvmdata_error_input when every requested year is too early — there is
# nothing left to fetch. Keeps "year before the dataset existed" distinct
# from genuine HTTP 404s, which remain governed by `on_error`.
clamp_years_to_first <- function(year, schema) {
  year <- as.integer(year)
  first_year <- as.integer(schema$first_year)
  too_early <- year < first_year
  if (!any(too_early)) {
    return(year)
  }
  kept <- year[!too_early]
  dropped <- sort(unique(year[too_early]))
  if (!length(kept)) {
    cvmdata_abort(
      c(
        paste(
          "No requested year exists for",
          "{.val {schema$dataset}}/{.val {schema$table}}."
        ),
        "x" = "Requested: {.val {sort(unique(year))}}.",
        "i" = "This table starts at {.val {first_year}}."
      ),
      class = "cvmdata_error_input"
    )
  }
  cli::cli_inform(c(
    "i" = paste(
      "{.val {schema$dataset}}/{.val {schema$table}} starts at",
      "{.val {first_year}}; ignoring {length(dropped)} earlier",
      "year{?s}: {.val {dropped}}."
    )
  ))
  kept
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
fetch_explicit_years <- function(
  schema,
  year,
  issuer,
  report_type,
  validate,
  on_error,
  keep_versions = FALSE
) {
  year <- as.integer(year)
  if (identical(on_error, "abort")) {
    parts <- lapply(year, function(yr) {
      fetch_one_year(
        schema,
        yr,
        issuer,
        report_type,
        validate,
        keep_versions = keep_versions
      )
    })
    return(do.call(rbind, parts))
  }
  attempts <- lapply(year, function(yr) {
    tryCatch(
      list(
        year = yr,
        ok = TRUE,
        value = fetch_one_year(
          schema,
          yr,
          issuer,
          report_type,
          validate,
          keep_versions = keep_versions
        )
      ),
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

# Keep the rows whose issuer CNPJ is one of `issuer` (CNPJs with or
# without punctuation; `cvm_fetch()` resolves tickers to CNPJs before
# calling the engine). CAD/ITR/DFP use `cnpj_cia`, FRE-detail tables
# `cnpj_companhia` (CLAUDE.md §2.2); a table with neither keeps no row.
filter_by_issuer <- function(df, issuer) {
  col <- cnpj_col(df)
  if (is.null(col)) {
    return(df[0L, , drop = FALSE])
  }
  df[cnpj_clean(df[[col]]) %in% cnpj_clean(issuer), , drop = FALSE]
}

# Ticker -> CNPJ lookup ------------------------------------------------
#
# B3 trading tickers (Codigo_Negociacao) are declared by issuers in the
# Formulario Cadastral; fca/valor_mobiliario is the canonical source.
# Decision §3.7 of the v0.2 planning doc (alternative b: derive from a
# field already present in CVM data, no external dependency).

# Session cache for the ticker lookup table (mirrors the mirror
# inventory cache), one entry per source.
.ticker_lookup_cache <- new.env(parent = emptyenv())

# Reset the session cache. Test helper; never called from production
# code paths.
ticker_lookup_cache_clear <- function() {
  rm(list = ls(.ticker_lookup_cache), envir = .ticker_lookup_cache)
  invisible()
}

# Ticker -> CNPJ across every fca/valor_mobiliario year that carries the
# trading code (schema `ticker_first_year`: the column is empty in the
# 2010-2017 files) up to the latest published on `source`. Every row
# counts, extinct securities included: a code that stopped trading
# still identifies its issuer, which is the point of resolving the
# tickers of delisted companies (measured 2026-10-21: 239 of 713 codes
# appear only in files before the latest one; none maps to two CNPJs).
# Returns a data frame with `ticker`, `cnpj_companhia` and `year`, with
# a `years` attribute. Cached per source for the session.
ticker_lookup_table_all <- function(source = "cvm") {
  source <- rlang::arg_match0(source, c("mirror", "cvm"))
  cache_key <- paste0("fca_valor_mobiliario_", source, "_all")
  cached <- .ticker_lookup_cache[[cache_key]]
  if (!is.null(cached)) {
    return(cached)
  }
  schema <- load_schema("fca", "valor_mobiliario")
  first <- as.integer(schema$ticker_first_year %||% schema$first_year)
  years <- published_file_years(schema, NULL, source)
  years <- sort(unique(as.integer(years[years >= first])))
  if (!length(years)) {
    cvmdata_abort(
      c(
        paste(
          "No {.val fca}/{.val valor_mobiliario} file from {.val {first}}",
          "on is available from source {.val {source}}; cannot resolve",
          "tickers."
        ),
        "i" = "Pass {.arg cnpj} instead, or try the other {.arg source}."
      ),
      class = "cvmdata_error_input"
    )
  }
  parts <- lapply(years, function(y) {
    df <- if (identical(source, "mirror")) {
      source_mirror_duckdb_get(schema, year = y, report_type = NULL)
    } else {
      path <- source_cvm_http_get(schema, year = y, report_type = NULL)
      raw <- read_cvm_csv(path, schema, validate = "skip")
      apply_schema_transformations(raw, schema)
    }
    ticker_rows(df, year = y)
  })
  lut <- do.call(rbind, parts)
  rownames(lut) <- NULL
  attr(lut, "years") <- years
  .ticker_lookup_cache[[cache_key]] <- lut
  lut
}

# The (ticker, cnpj_companhia, year) rows of one fca/valor_mobiliario
# file: trading code upper-cased and trimmed, empty codes dropped.
ticker_rows <- function(df, year) {
  cnpj_c <- cnpj_col(df)
  if (is.null(cnpj_c) || !"codigo_negociacao" %in% names(df)) {
    cvmdata_abort(
      c(paste(
        "{.val fca}/{.val valor_mobiliario} lacks the columns needed",
        "for ticker resolution ({.code codigo_negociacao} +",
        "{.code cnpj_companhia})."
      )),
      class = "cvmdata_error_internal"
    )
  }
  out <- data.frame(
    ticker = toupper(trimws(as.character(df$codigo_negociacao))),
    cnpj_companhia = as.character(df[[cnpj_c]]),
    year = rep(as.integer(year), nrow(df)),
    stringsAsFactors = FALSE
  )
  out[!is.na(out$ticker) & nzchar(out$ticker), , drop = FALSE]
}

# Resolve tickers against every FCA year (ticker_lookup_table_all()).
# A code absent from every file aborts; a code that maps to more than
# one issuer aborts as well, asking for `cnpj`, rather than picking one
# silently (the B3 may reuse codes; none is reused today). Returns the
# unique issuer CNPJs as published in the FCA.
resolve_ticker_all_years <- function(tickers, source = "cvm") {
  lut <- ticker_lookup_table_all(source = source)
  years <- attr(lut, "years")
  span <- paste(range(years), collapse = "-")
  resolved <- character(0L)
  for (tk in toupper(trimws(tickers))) {
    cnpjs <- unique(lut$cnpj_companhia[lut$ticker == tk])
    cnpjs <- cnpjs[!is.na(cnpjs) & nzchar(cnpjs)]
    if (!length(cnpjs)) {
      cvmdata_abort(
        c(
          paste(
            "Ticker {.val {tk}} not found in {.val fca}/{.val",
            "valor_mobiliario} for any year ({span})."
          ),
          "i" = paste(
            "Check the spelling, or pass {.arg cnpj}. Tickers cover only",
            "exchange-listed securities, and the CVM files carry trading",
            "codes from {.val {min(years)}} on."
          )
        ),
        class = "cvmdata_error_input"
      )
    }
    if (length(cnpjs) > 1L) {
      cvmdata_abort(
        c(
          paste(
            "Ticker {.val {tk}} maps to more than one issuer in",
            "{.val fca}/{.val valor_mobiliario}: {.val {cnpjs}}."
          ),
          "i" = "Pass {.arg cnpj} to choose the issuer."
        ),
        class = "cvmdata_error_input"
      )
    }
    resolved <- c(resolved, cnpjs)
  }
  unique(resolved)
}
