# Generic application of YAML-declared transformations.
#
# Each entry in `schema$transformations` is a list with `action` (one of
# the supported actions below) plus action-specific keys:
#
#   - multiply_by_scale: multiplies `column` by `scale_column` in place
#     (UNIDADE=1, MIL=1e3, MILHÃO=1e6, BILHÃO=1e9). Naming doc v03 §2.6.
#
#   - drop: removes `column` from the tibble.
#
#   - keep_latest_version: keeps, per `(cnpj, reference date)`, the rows
#     of the filing delivered last — ranked by receipt date, then CVM
#     document id, then `versao` (see `filing_rank()`). Declared by the
#     detail tables of every versioned dataset. The `submissao` tables
#     declare it no more (0.2.0.9000): they are the filing index and
#     return every delivery; `check_filings()` computes the current
#     filing from them when it needs one.
#
# Unknown actions abort with cvmdata_error_internal.

# Apply every transformation declared in a schema to a tibble, except
# the actions named in `skip` (`cvm_versions()` skips
# `keep_latest_version` to see every filing the CSV carries). Returns
# the transformed tibble.
apply_schema_transformations <- function(df, schema, skip = NULL) {
  transforms <- schema$transformations
  if (is.null(transforms) || !length(transforms)) {
    return(df)
  }
  for (tx in transforms) {
    if (!is.null(skip) && isTRUE(tx$action %in% skip)) {
      next
    }
    df <- apply_one_transformation(df, tx, schema)
  }
  df
}

apply_one_transformation <- function(df, tx, schema) {
  action <- tx$action
  if (is.null(action)) {
    cvmdata_abort(
      c(
        paste(
          "Transformation entry for {.val {schema$dataset}}/",
          "{.val {schema$table}} lacks {.field action}."
        )
      ),
      class = "cvmdata_error_internal"
    )
  }
  switch(
    action,
    multiply_by_scale = tx_multiply_by_scale(df, tx, schema),
    drop = tx_drop(df, tx, schema),
    keep_latest_version = tx_keep_latest_version(df, tx, schema),
    cvmdata_abort(
      c(
        "Unknown transformation action {.val {action}}.",
        "i" = paste(
          "Supported: {.val multiply_by_scale}, {.val drop},",
          "{.val keep_latest_version}."
        )
      ),
      class = "cvmdata_error_internal"
    )
  )
}

# multiply_by_scale: column <- column * scale_factor(scale_column)
tx_multiply_by_scale <- function(df, tx, schema) {
  col <- tx$column
  scale_col <- tx$scale_column
  if (is.null(col) || is.null(scale_col)) {
    cvmdata_abort(
      c(
        paste(
          "Transformation {.code multiply_by_scale} requires",
          "{.field column} and {.field scale_column}."
        )
      ),
      class = "cvmdata_error_internal"
    )
  }
  if (!col %in% names(df) || !scale_col %in% names(df)) {
    cvmdata_abort(
      c(
        paste(
          "Columns {.val {col}} / {.val {scale_col}} not found in",
          "tibble for {.val {schema$dataset}}/{.val {schema$table}}."
        )
      ),
      class = "cvmdata_error_parse"
    )
  }
  # Nothing to scale in an empty table. CVM publishes header-only CSVs
  # for the current, not-yet-filed year of annual financial tables
  # (e.g. dfp/dfc_md in the year before the filing window). With zero
  # rows, readr guesses a non-numeric type for `col`, and `col * factors`
  # would abort with "non-numeric argument to binary operator". Return
  # the empty tibble unchanged so callers get a clean 0-row result.
  if (nrow(df) == 0L) {
    return(df)
  }
  factors <- scale_factor(df[[scale_col]])
  df[[col]] <- df[[col]] * factors
  df
}

# Map a vector of CVM scale labels to numeric factors.
# Recognizes both accented and non-accented variants because some
# upstream filings drop accents.
scale_factor <- function(x) {
  norm <- toupper(as.character(x))
  accented <- intToUtf8(c(
    0x00C1,
    0x00C2,
    0x00C3,
    0x00C9,
    0x00CA,
    0x00CD,
    0x00D3,
    0x00D4,
    0x00DA,
    0x00DC,
    0x00C7
  ))
  plain <- "AAAEEIOOUUC"
  norm <- chartr(accented, plain, norm)
  out <- rep(NA_real_, length(norm))
  out[norm == "UNIDADE"] <- 1
  out[norm == "MIL"] <- 1e3
  out[norm == "MILHAO"] <- 1e6
  out[norm == "BILHAO"] <- 1e9
  if (any(is.na(out) & !is.na(norm))) {
    bad <- unique(norm[is.na(out) & !is.na(norm)])
    cvmdata_abort(
      c(
        "Unknown scale label(s): {.val {bad}}.",
        "i" = paste(
          "Expected one of {.val UNIDADE}, {.val MIL},",
          "{.val MILHAO}, {.val BILHAO}."
        )
      ),
      class = "cvmdata_error_parse"
    )
  }
  out
}

# drop: removes the column.
tx_drop <- function(df, tx, schema) {
  col <- tx$column
  if (is.null(col)) {
    cvmdata_abort(
      c("Transformation {.code drop} requires {.field column}."),
      class = "cvmdata_error_internal"
    )
  }
  df[, setdiff(names(df), col), drop = FALSE]
}

# keep_latest_version: groups by the (cnpj, ref_date) pair the table
# carries and keeps the rows of the filing delivered last. ITR/DFP
# statement tables use (cnpj_cia, dt_refer); FRE-detail uses
# (cnpj_companhia, data_referencia) per CLAUDE.md §2.2. When the triple
# is absent (e.g., CAD has none of them) this is a no-op.
#
# Tables whose conceptual identity needs a third axis (e.g.
# `cgvn/praticas`, one row per ID_Item per filing) declare additional
# key columns in the YAML via `keys: [col1, ...]`; those compose with
# the implicit (cnpj, date) pair. Missing extras abort the run.
tx_keep_latest_version <- function(df, tx, schema) {
  if (!"versao" %in% names(df)) {
    return(df)
  }
  cnpj_c <- if ("cnpj_cia" %in% names(df)) {
    "cnpj_cia"
  } else if ("cnpj_companhia" %in% names(df)) {
    "cnpj_companhia"
  } else {
    NULL
  }
  date_c <- if ("dt_refer" %in% names(df)) {
    "dt_refer"
  } else if ("data_referencia" %in% names(df)) {
    "data_referencia"
  } else {
    NULL
  }
  if (is.null(cnpj_c) || is.null(date_c)) {
    return(df)
  }
  extras <- tx$keys
  if (!is.null(extras)) {
    missing <- setdiff(extras, names(df))
    if (length(missing)) {
      cvmdata_abort(
        c(
          paste(
            "Transformation {.code keep_latest_version} for",
            "{.val {schema$dataset}}/{.val {schema$table}} declares",
            "extra {.field keys} not present in the tibble."
          ),
          "x" = "Missing: {.val {missing}}."
        ),
        class = "cvmdata_error_internal"
      )
    }
  }
  # Coerce versao to integer-like for stable ordering.
  ver <- suppressWarnings(as.integer(df$versao))
  key_cols <- c(cnpj_c, date_c, extras)
  key_parts <- lapply(key_cols, function(col) {
    if (inherits(df[[col]], "Date")) format(df[[col]]) else df[[col]]
  })
  key <- do.call(paste, c(key_parts, list(sep = "|")))
  # Rank every filing by delivery order and keep, within each key, the
  # rows of the last filing delivered. `versao` alone is not a key: the
  # CVM index carries two VERSAO 1 filings for the same (cnpj, date)
  # (TRV XLIII DFP 2023) and a VERSAO 1 delivered after VERSAO 2
  # (Travessia VI DFP 2024). Tables without delivery columns fall back
  # to the highest `versao`, which is all they carry.
  rank <- filing_rank(df, ver)
  max_rank <- ave(rank, key, FUN = function(r) max(r, na.rm = TRUE))
  df[rank == max_rank & !is.na(ver), , drop = FALSE]
}

# Delivery-order columns, in snake_case as the reader returns them.
# Receipt date first, then the CVM document id (sequential), then the
# protocol number for tables that carry no id (vlmo).
.filing_receipt_cols <- c("dt_receb", "data_entrega", "data_recebimento")
.filing_id_cols <- c("id_doc", "id_documento", "protocolo_entrega")

first_present <- function(df, candidates) {
  hit <- intersect(candidates, names(df))
  if (length(hit)) hit[[1L]] else NULL
}

# Dense rank of each row's filing by (receipt, id, versao), ascending.
# Rows of the same filing share a rank.
filing_rank <- function(df, ver) {
  receipt_c <- first_present(df, .filing_receipt_cols)
  id_c <- first_present(df, .filing_id_cols)
  parts <- list()
  if (!is.null(receipt_c)) {
    parts$receipt <- as_sortable_time(df[[receipt_c]])
  }
  if (!is.null(id_c)) {
    parts$id <- as_sortable_id(df[[id_c]])
  }
  parts$ver <- ver
  ord <- do.call(order, c(unname(parts), list(na.last = FALSE)))
  tuple <- do.call(paste, c(lapply(parts, as.character), list(sep = "|")))
  match(tuple, unique(tuple[ord]))
}

as_sortable_time <- function(x) {
  if (inherits(x, c("Date", "POSIXt"))) {
    return(as.numeric(as.POSIXct(x, tz = "UTC")))
  }
  x <- as.character(x)
  out <- suppressWarnings(as.numeric(as.POSIXct(
    x,
    tz = "UTC",
    format = "%Y-%m-%d %H:%M:%OS"
  )))
  date_only <- is.na(out) & !is.na(x)
  out[date_only] <- suppressWarnings(as.numeric(as.POSIXct(
    x[date_only],
    tz = "UTC",
    format = "%Y-%m-%d"
  )))
  out
}

as_sortable_id <- function(x) {
  num <- suppressWarnings(as.numeric(as.character(x)))
  if (all(is.na(num) == is.na(x))) {
    return(num)
  }
  xtfrm(as.character(x))
}
