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
#   - keep_latest_version: keeps only the row of highest `versao` per
#     `(cnpj_cia, dt_refer)`. Default policy for v0.1 — historical
#     versions accessible in v0.2+ via opt-in argument.
#
# Unknown actions abort with cvmdata_error_internal.

# Apply every transformation declared in a schema to a tibble.
# Returns the transformed tibble.
apply_schema_transformations <- function(df, schema) {
  transforms <- schema$transformations
  if (is.null(transforms) || !length(transforms)) {
    return(df)
  }
  for (tx in transforms) {
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
    multiply_by_scale  = tx_multiply_by_scale(df, tx, schema),
    drop               = tx_drop(df, tx, schema),
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
    0x00C1, 0x00C2, 0x00C3, 0x00C9, 0x00CA, 0x00CD,
    0x00D3, 0x00D4, 0x00DA, 0x00DC, 0x00C7
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
# carries and keeps the row of highest `versao`. CAD/ITR/DFP submissao
# use (cnpj_cia, dt_refer); FRE-detail uses
# (cnpj_companhia, data_referencia) per CLAUDE.md §2.2. When the triple
# is absent (e.g., CAD has none of them) this is a no-op.
tx_keep_latest_version <- function(df, tx, schema) {
  if (!"versao" %in% names(df)) {
    return(df)
  }
  cnpj_c <- if ("cnpj_cia" %in% names(df)) "cnpj_cia"
            else if ("cnpj_companhia" %in% names(df)) "cnpj_companhia"
            else NULL
  date_c <- if ("dt_refer" %in% names(df)) "dt_refer"
            else if ("data_referencia" %in% names(df)) "data_referencia"
            else NULL
  if (is.null(cnpj_c) || is.null(date_c)) {
    return(df)
  }
  # Coerce versao to integer-like for stable ordering.
  ver <- suppressWarnings(as.integer(df$versao))
  key <- paste(df[[cnpj_c]], format(df[[date_c]]), sep = "|")
  # Build a logical mask: TRUE where this row's versao == max versao
  # within its key.
  max_ver <- ave(ver, key, FUN = function(v) max(v, na.rm = TRUE))
  df[ver == max_ver & !is.na(ver), , drop = FALSE]
}
