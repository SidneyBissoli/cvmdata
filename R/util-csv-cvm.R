# CSV reader honouring the CVM-specific conventions: ISO-8859-1
# encoding, semicolon delimiter, identifier columns forced to
# character regardless of the META declaration (naming doc v03 §11.2),
# and date columns auto-converted from AAAA-MM-DD.
#
# Pre-v0.1 caveat: the CVM dictionary snapshot is not built yet
# (Phase B/C of ROADMAP). Until it exists, date columns are detected
# heuristically by name (`DT_*` or `Data_*`) and ISO-8601 content.
# This heuristic is replaced by the dictionary-driven rule once the
# snapshot lands.

# Names matching these patterns (case-insensitive) are forced to
# character. Sourced from naming doc v03 §11.2.
.identifier_patterns <- c(
  "^cnpj($|_)",
  "^cd_cvm$",
  "^cep$",
  "^tel($|_)",
  "^ddd($|_)",
  "^cpf$",
  "^id_doc$",
  "^id_documento$",
  "^versao$"
)

# Build a `readr::cols()` specification: force identifiers to
# character, parse `DT_*`/`Data_*` columns as Date, let readr guess
# the rest.
build_col_types <- function(csv_names) {
  csv_lower <- tolower(csv_names)
  is_identifier <- vapply(
    csv_lower,
    function(nm) {
      any(vapply(
        .identifier_patterns,
        function(p) grepl(p, nm, perl = TRUE),
        logical(1L)
      ))
    },
    logical(1L)
  )
  is_date <- grepl("^(dt_|data_)", csv_lower) & !is_identifier

  spec_list <- vector("list", length(csv_names))
  names(spec_list) <- csv_names
  for (i in seq_along(csv_names)) {
    if (is_identifier[i]) {
      spec_list[[i]] <- readr::col_character()
    } else if (is_date[i]) {
      spec_list[[i]] <- readr::col_date(format = "%Y-%m-%d")
    }
  }
  spec_list <- spec_list[!vapply(spec_list, is.null, logical(1L))]
  do.call(
    readr::cols,
    c(spec_list, list(.default = readr::col_guess()))
  )
}

# Read a CVM-published CSV honouring schema rules and validate
# according to the `validate` mode.
#
# @param path Local path to the CSV.
# @param schema A `cvm_table_schema` returned by `load_schema()`.
# @param validate One of "strict", "warn", "skip".
# @return A tibble with column types parsed per CVM conventions.
read_cvm_csv <- function(path, schema, validate = "strict") {
  delim <- schema$delimiter %||% ";"
  encoding <- schema$encoding %||% "ISO-8859-1"

  header <- readr::read_delim(
    path,
    delim = delim,
    locale = readr::locale(encoding = encoding),
    n_max = 0,
    show_col_types = FALSE,
    progress = FALSE
  )
  csv_names <- colnames(header)

  validate_field_count(csv_names, schema, validate, path)
  if (identical(schema$meta_status %||% "available", "missing")) {
    validate_field_names(csv_names, schema, validate, path)
  }

  readr::read_delim(
    path,
    delim = delim,
    locale = readr::locale(encoding = encoding),
    col_types = build_col_types(csv_names),
    show_col_types = FALSE,
    progress = FALSE
  )
}

validate_field_count <- function(csv_names, schema, validate, path) {
  expected <- schema$expected_field_count
  if (is.null(expected) || is.na(expected)) {
    return(invisible(NULL))
  }
  actual <- length(csv_names)
  if (identical(as.integer(actual), as.integer(expected))) {
    return(invisible(NULL))
  }
  msg <- c(
    "Field count mismatch in {.path {basename(path)}}.",
    "x" = paste(
      "Schema expected {.val {expected}} fields;",
      "CSV has {.val {actual}}."
    ),
    "i" = paste(
      "This may indicate an unannounced schema change",
      "in the CVM source."
    )
  )
  emit_validation(
    msg, validate, "cvmdata_error_parse",
    .envir = environment()
  )
}

validate_field_names <- function(csv_names, schema, validate, path) {
  expected_norm <- tolower(schema$expected_field_names)
  csv_norm <- tolower(csv_names)
  missing_fields <- setdiff(expected_norm, csv_norm)
  extra_fields <- setdiff(csv_norm, expected_norm)
  if (!length(missing_fields) && !length(extra_fields)) {
    return(invisible(NULL))
  }
  msg <- c(
    paste(
      "Field name mismatch in {.path {basename(path)}}",
      "against schema {.code expected_field_names}."
    )
  )
  if (length(missing_fields)) {
    msg <- c(
      msg,
      "x" = "Missing in CSV: {.val {missing_fields}}."
    )
  }
  if (length(extra_fields)) {
    msg <- c(
      msg,
      "x" = "Extra in CSV: {.val {extra_fields}}."
    )
  }
  emit_validation(
    msg, validate, "cvmdata_error_parse",
    .envir = environment()
  )
}

emit_validation <- function(msg,
                            validate,
                            error_class,
                            .envir = parent.frame()) {
  if (identical(validate, "strict")) {
    cvmdata_abort(msg, class = error_class, .envir = .envir)
  }
  if (identical(validate, "warn")) {
    cvmdata_warn(
      msg, class = "cvmdata_warn_validation",
      .envir = .envir
    )
  }
  invisible(NULL)
}
