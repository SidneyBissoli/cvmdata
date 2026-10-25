#' Every known version of a filing
#'
#' @description
#' An issuer may file the same document more than once: a DFP or ITR
#' re-filed to fix a figure, a scale, a note. [cvm_fetch()] returns the
#' current version of each document, as the CVM's yearly files do.
#' `cvm_versions()` returns every version the package knows of, the
#' current one included, so the figures of a filing can be followed
#' from one version to the next. The signature mirrors the part of
#' [cvm_fetch()] that identifies the documents (`dataset`, `table`,
#' `cnpj`, `ticker`, `year`, `basis`) and takes none of its row
#' filters: `reading`, `from`/`to` and `as_of` select rows of the
#' current reading and are refused here.
#'
#' Only the tables that keep a single filing per document (those whose
#' schema declares `keep_latest_version`: the DFP, ITR and FRE detail
#' tables, among others) have a version history. Asking for another
#' table, such as a dataset's `submissao` index or the CAD register,
#' aborts: those already return every row the CVM publishes.
#'
#' @section Where the versions come from:
#' The two backends know different parts of the history.
#'
#' * `source = "mirror"` (the default) reads, for every partition of
#'   the table, the current asset [cvm_fetch()] reads plus the
#'   `history` asset the ETL keeps next to it with the superseded
#'   filings, dated. The history holds the filings the mirror saw being
#'   replaced from 2026-10 on and, for the DFP and ITR statements, the
#'   ones recovered from the CVM's filing system (RAD) back to 2010;
#'   `history_source` says which (`"mirror"` or `"rad"`).
#' * `source = "cvm"` reads the CVM's yearly CSV without collapsing it
#'   to the current filing. That file keeps only the versions the CVM
#'   still publishes, usually the current one alone, and carries no
#'   supersession date, so `superseded_at`, `id_doc` and
#'   `motivo_reapresentacao` are `NA` there; the call says so once. The
#'   complete history is on the mirror.
#'
#' @section Columns:
#' The columns of the table, `year` and `basis` as [cvm_fetch()]
#' returns them, then five version columns:
#'
#' * `superseded_at`: `Date` the version stopped being the current one
#'   (the receipt date of the version that replaced it); `NA` for the
#'   current version.
#' * `superseded_by_versao`: the `versao` of the filing that replaced
#'   it; `NA` for the current version.
#' * `history_source`: `"current"` for the rows of the current version,
#'   `"mirror"` or `"rad"` for a superseded version on the mirror,
#'   `"cvm"` for a superseded version still in the CVM's yearly file.
#' * `id_doc`: the CVM document id of the superseded filing, when the
#'   history knows it.
#' * `motivo_reapresentacao`: the reason the issuer gave for the
#'   re-filing, as the CVM publishes it, when known.
#'
#' Rows are ordered by issuer, reference date and `versao`. `versao` is
#' not a key on its own: the CVM index carries two filings under the
#' same `VERSAO` for some documents.
#'
#' @inheritParams cvm_fetch
#' @param year Integer vector of years whose documents to return, as
#'   the CVM publishes them (one file per year). `NULL` (default) uses
#'   the latest available year.
#' @param ... Reserved; any extra argument aborts. `reading`,
#'   `from`/`to` and `as_of` are refused by name.
#'
#' @returns A `cvm_tbl` (a tibble subclass) with the columns of the
#'   table, `basis` for the tables published in individual and
#'   consolidated variants, and the five version columns described
#'   above. Empty when the issuers have no filing in the period.
#'
#' @examplesIf interactive()
#' # Petrobras filed its consolidated 2023 income statement twice;
#' # version 1 was superseded on 2024-03-25 and net income (account
#' # 3.11, exercise row) is the same in both.
#' petr <- cvm_versions(
#'   "dfp",
#'   "dre",
#'   ticker = "PETR4",
#'   year = 2023,
#'   basis = "con"
#' )
#' petr[
#'   petr$cd_conta == "3.11" & petr$ordem_exerc == "ÚLTIMO",
#'   c("versao", "superseded_at", "superseded_by_versao", "vl_conta")
#' ]
#'
#' # Braskem filed it three times: version 1 in R$ units by mistake
#' # (a loss of R$ 4.5 million), version 2 "to reflect the R$ thousand
#' # scale" (R$ 4.89 billion) and version 3.
#' brkm <- cvm_versions(
#'   "dfp",
#'   "dre",
#'   cnpj = "42.150.391/0001-70",
#'   year = 2023,
#'   basis = "con"
#' )
#' unique(brkm[, c("versao", "superseded_at", "motivo_reapresentacao")])
#'
#' @family fetchers
#' @export
cvm_versions <- function(
  dataset,
  table,
  cnpj = NULL,
  ticker = NULL,
  year = NULL,
  basis = NULL,
  source = NULL,
  on_error = "abort",
  validate = "strict",
  ...
) {
  check_versions_dots(list(...))
  if (is.null(source)) {
    source <- cvm_source_get()
  }
  source <- rlang::arg_match0(source, c("mirror", "cvm"))
  validate <- rlang::arg_match0(validate, c("strict", "warn", "skip"))
  on_error <- rlang::arg_match0(on_error, c("abort", "warn", "silent"))

  schema <- load_schema(dataset, table)
  version_tx <- check_versioned_table(schema)
  basis <- check_basis(basis, schema)
  period <- check_published_years(
    list(year = year, from = NULL, to = NULL),
    schema
  )
  warn_empty_latest(period, schema, source)
  cnpj <- check_cnpj(cnpj)
  if (!is.null(ticker)) {
    resolved <- resolve_ticker_all_years(check_ticker(ticker), source = source)
    cnpj <- unique(c(cnpj, cnpj_clean(resolved)))
  }

  variants <- if (is.null(basis)) list(NULL) else as.list(basis)
  parts <- lapply(variants, function(b) {
    out <- if (identical(source, "mirror")) {
      fetch_versions_mirror(schema, cnpj, period$year, b)
    } else {
      fetch_versions_cvm(schema, cnpj, period$year, b, validate, on_error)
    }
    out <- mark_versions(out, version_tx, source)
    if (!is.null(b)) {
      out <- set_basis_column(out, b)
    }
    out
  })
  out <- if (length(parts) == 1L) {
    parts[[1L]]
  } else {
    vctrs::vec_rbind(!!!parts)
  }
  out <- arrange_version_columns(out)
  if (identical(source, "cvm")) {
    inform_versions_cvm()
  }

  cvm_attach_metadata(
    out,
    source = source,
    group = schema$group,
    dataset = dataset,
    table = table
  )
}

# Version columns, in the order they end the result.
.version_columns <- c(
  "superseded_at",
  "superseded_by_versao",
  "history_source",
  "id_doc",
  "motivo_reapresentacao"
)

# Arguments of `cvm_fetch()` that select rows of the current reading;
# they make no sense over every version and are refused by name.
.current_reading_args <- c("reading", "from", "to", "as_of")

# Reject every extra argument, naming the current-reading filters of
# `cvm_fetch()` for what they are when one of them is passed.
check_versions_dots <- function(dots) {
  if (!length(dots)) {
    return(invisible())
  }
  nms <- names(dots) %||% rep("", length(dots))
  nms[!nzchar(nms)] <- "<unnamed>"
  filters <- intersect(nms, .current_reading_args)
  if (length(filters)) {
    cvmdata_abort(
      c(
        "{.fn cvm_versions} does not take {.arg {filters}}.",
        "i" = paste(
          "{.arg reading}, {.arg from}/{.arg to} and {.arg as_of} select",
          "rows of the current reading in {.fn cvm_fetch};",
          "{.fn cvm_versions} returns every version of the documents",
          "of {.arg year} instead."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  cvmdata_abort(
    c(
      "Unknown argument{?s}: {.arg {nms}}.",
      "i" = paste(
        "{.fn cvm_versions} selects issuers with {.arg cnpj} or",
        "{.arg ticker}, the period with {.arg year} and the statement",
        "basis with {.arg basis}."
      )
    ),
    class = "cvmdata_error_input"
  )
}

# Only a table that collapses its filings to the current one has
# superseded versions to show. Returns the `keep_latest_version`
# transformation entry (its optional `keys` compose the document key).
check_versioned_table <- function(schema) {
  for (tx in schema$transformations) {
    if (identical(tx$action, "keep_latest_version")) {
      return(tx)
    }
  }
  cvmdata_abort(
    c(
      paste(
        "Table {.val {schema$dataset}}/{.val {schema$table}} has no",
        "version history: it returns every row the CVM publishes."
      ),
      "i" = paste(
        "{.fn cvm_versions} applies to the tables that keep a single",
        "filing per document, such as the DFP and ITR statements;",
        "use {.fn cvm_fetch} for this one."
      )
    ),
    class = "cvmdata_error_input"
  )
}

# Mirror: the current asset of every partition plus its history asset,
# read by column name, then the issuer filter `cvm_fetch()` applies.
fetch_versions_mirror <- function(schema, cnpj, years, report_type) {
  out <- source_mirror_duckdb_get(
    schema,
    year = years,
    report_type = report_type,
    history = TRUE
  )
  if (!is.null(cnpj)) {
    out <- filter_by_issuer(out, cnpj, schema = schema)
  }
  out
}

# CVM: the yearly files read without `keep_latest_version`, through the
# same year resolution and `on_error` handling as `cvm_fetch()`.
fetch_versions_cvm <- function(
  schema,
  cnpj,
  years,
  report_type,
  validate,
  on_error
) {
  partitioning <- schema$temporal_partitioning %||% "none"
  if (identical(partitioning, "yearly")) {
    return(fetch_yearly_partitioned(
      schema,
      schema$dataset,
      years,
      cnpj,
      report_type,
      validate,
      on_error,
      keep_versions = TRUE
    ))
  }
  if (!is.null(years)) {
    cvmdata_abort(
      c(
        paste(
          "Table {.val {schema$dataset}}/{.val {schema$table}} is not",
          "yearly-partitioned; {.arg year} must be {.code NULL}."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  fetch_one_year(
    schema,
    year = NULL,
    issuer = cnpj,
    report_type = report_type,
    validate = validate,
    keep_versions = TRUE
  )
}

# Complete the version columns and tell the current version of every
# document from the superseded ones. On the mirror the history rows
# arrive marked (`history_source` set by the ETL) and the current rows
# arrive without the columns; on the CVM every row comes unmarked and
# the current filing of each document is the one delivered last, by
# the same rank `keep_latest_version` uses. Rows are then ordered by
# document and version.
mark_versions <- function(df, tx, source) {
  df <- ensure_version_columns(df)
  if (!nrow(df)) {
    return(df)
  }
  key <- version_key(df, tx)
  ver <- if ("versao" %in% names(df)) {
    suppressWarnings(as.integer(df$versao))
  } else {
    rep(NA_integer_, nrow(df))
  }
  if (identical(source, "mirror")) {
    is_current <- is.na(df$history_source)
  } else if (is.null(key) || all(is.na(ver))) {
    is_current <- rep(TRUE, nrow(df))
  } else {
    rank <- filing_rank(df, ver)
    max_rank <- ave(rank, key, FUN = function(r) max(r, na.rm = TRUE))
    is_current <- rank == max_rank & !is.na(ver)
    current_of_key <- df$versao[is_current][match(key, key[is_current])]
    df$superseded_by_versao[!is_current] <- current_of_key[!is_current]
    df$history_source[!is_current] <- "cvm"
  }
  df$history_source[is_current] <- "current"
  ord <- if (is.null(key)) order(ver) else order(key, ver)
  df[ord, , drop = FALSE]
}

# The document key `keep_latest_version` collapses on: issuer, reference
# date and the extra `keys` of the transformation, when declared. NULL
# when the table carries neither convention.
version_key <- function(df, tx) {
  cnpj_c <- first_present(df, c("cnpj_cia", "cnpj_companhia"))
  date_c <- first_present(df, c("dt_refer", "data_referencia"))
  if (is.null(cnpj_c) || is.null(date_c)) {
    return(NULL)
  }
  key_cols <- c(cnpj_c, date_c, intersect(tx$keys, names(df)))
  parts <- lapply(key_cols, function(col) {
    if (inherits(df[[col]], "Date")) format(df[[col]]) else df[[col]]
  })
  do.call(paste, c(parts, list(sep = "|")))
}

# Add the version columns a backend did not supply (NA) and give
# `superseded_at` its Date type: the history asset stores it as text.
ensure_version_columns <- function(df) {
  n <- nrow(df)
  for (col in .version_columns) {
    if (!col %in% names(df)) {
      df[[col]] <- rep(NA_character_, n)
    }
  }
  if (!inherits(df$superseded_at, "Date")) {
    df$superseded_at <- as_date_column(df$superseded_at)
  }
  df
}

# Version columns last, in their canonical order, after `basis`.
arrange_version_columns <- function(df) {
  df[c(setdiff(names(df), .version_columns), .version_columns)]
}

inform_versions_cvm <- function() {
  cli::cli_inform(c(
    "i" = paste(
      "Read from the CVM's yearly file, which keeps only the versions",
      "the CVM still publishes (usually the current one alone) and no",
      "supersession dates. The complete history is on the mirror",
      "({.code source = \"mirror\"})."
    )
  ))
}
