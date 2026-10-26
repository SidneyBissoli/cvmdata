# CSV reader honouring the CVM-specific conventions: ISO-8859-1
# encoding, semicolon delimiter, identifier columns forced to
# character regardless of the META declaration (naming doc v03 §11.2),
# and date columns auto-converted from AAAA-MM-DD.
#
# Date detection is driven canonically by the dictionary snapshot
# (cvm_dictionary(dataset, table), tipo_dados = "date"): when the
# snapshot covers a column, its declared type prevails over the
# legacy name-based heuristic. Columns not covered by the snapshot
# (meta_status: missing tables, synthetic schemas without a dataset,
# or CSV headers added since the last snapshot build) fall back to
# the heuristic `^dt_` / `^data_` match.

# Identifier classification: prefix-based regex + exact-match for the
# few columns without a natural prefix. Both lists operate on lowered
# names. Sourced from naming doc v03 §11.2 and extended for v0.2
# (codes from FCA detail tables: `codigo_cvm_auditor`, `cpf_*`,
# `ddi_*`, `id_item`, `caixa_postal`, `protocolo_entrega`,
# `codigo_negociacao` ticker).
.identifier_prefixes <- c(
  "^cnpj",
  "^cpf",
  "^codigo_",
  "^cd_cvm",
  "^cep",
  "^ddi_",
  "^ddd_",
  "^id_",
  "^protocolo"
)
.identifier_exact <- c("caixa_postal", "tel", "versao")

# Classify CSV column names as identifiers (forced to character).
# `csv_names` may be in any case; matching is on tolower(.) against the
# prefix regexes and the exact-match list. Returns a logical vector
# aligned with `csv_names`.
identifier_columns <- function(csv_names) {
  csv_lower <- tolower(csv_names)
  by_prefix <- vapply(
    csv_lower,
    function(nm) {
      any(vapply(
        .identifier_prefixes,
        function(p) grepl(p, nm, perl = TRUE),
        logical(1L)
      ))
    },
    logical(1L)
  )
  by_exact <- csv_lower %in% .identifier_exact
  unname(by_prefix | by_exact)
}

# Resolve dictionary coverage for the schema's (dataset, table).
# Returns NULL when no canonical info is available (schema lacks
# dataset/table, meta_status is "missing", or the snapshot has no
# entry for the pair). Otherwise returns a list with the columns
# known to the snapshot (`known`) and the subset declared as
# `tipo_dados = "date"` (`date`).
resolve_dict_columns <- function(schema) {
  if (is.null(schema) || is.null(schema$dataset) || is.null(schema$table)) {
    return(NULL)
  }
  if (identical(schema$meta_status %||% "available", "missing")) {
    return(NULL)
  }
  dict <- tryCatch(
    cvm_dictionary(schema$dataset, schema$table),
    cvmdata_error = function(e) NULL
  )
  if (is.null(dict) || !nrow(dict)) {
    return(NULL)
  }
  list(
    known = dict$campo,
    date = dict$campo[
      !is.na(dict$tipo_dados) & dict$tipo_dados == "date"
    ],
    text = dict$campo[
      !is.na(dict$tipo_dados) & dict$tipo_dados %in% .text_types
    ]
  )
}

# META types that hold text. A column of these is read as character
# whatever its values look like: guessed, a telephone became a number
# (losing its leading zeros) and an empty-headed text column a logical.
# Measured on 2026-10-25 on the mirror: 32 text columns (fca telephone
# and fax, fre UF, municipality, CNPJ...) stored as logical or double in
# some year.
.text_types <- c("varchar", "char", "nvarchar")

# Build a `readr::cols()` specification: force identifiers to
# character, parse date columns per the dictionary snapshot (with a
# heuristic fallback for columns the snapshot does not cover), let
# readr guess the rest.
build_col_types <- function(csv_names, schema = NULL) {
  csv_lower <- tolower(csv_names)
  is_identifier <- identifier_columns(csv_names)

  dict_info <- resolve_dict_columns(schema)
  is_date <- vapply(
    csv_lower,
    function(nm) classify_date(nm, dict_info),
    logical(1L)
  )
  is_date <- is_date & !is_identifier
  is_text <- csv_lower %in% (dict_info$text %||% character())

  spec_list <- vector("list", length(csv_names))
  names(spec_list) <- csv_names
  for (i in seq_along(csv_names)) {
    if (is_identifier[i] || (is_text[i] && !is_date[i])) {
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

# Decide whether a lowered column name should be parsed as Date.
# Snapshot coverage prevails over the name heuristic; the heuristic
# only fires for columns the snapshot does not cover.
classify_date <- function(nm, dict_info) {
  if (!is.null(dict_info) && nm %in% dict_info$known) {
    return(nm %in% dict_info$date)
  }
  grepl("^(dt_|data_)", nm)
}

# Read a CVM-published CSV honouring schema rules and validate
# according to the `validate` mode. Returns a tibble with snake_case
# column names (SCREAMING_SNAKE_CASE from CVM is lowered uniformly).
#
# @param path Local path to the CSV.
# @param schema A `cvm_table_schema` returned by `load_schema()`.
# @param validate One of "strict", "warn", "skip".
# @return A tibble with column types parsed per CVM conventions.
read_cvm_csv <- function(path, schema, validate = "strict") {
  delim <- schema$delimiter %||% ";"
  encoding <- schema$encoding %||% "ISO-8859-1"

  # The CVM does not quote: a `"` in its CSVs is a character of the text
  # (`Banco "X" S.A.`), and no field holds the delimiter or a line break
  # (every physical line has the header's field count). Read with the
  # default `quote = '"'`, a text starting with a quote swallowed the
  # following lines into one field until the next quote: on 2026-10-25,
  # 2,803 of 30,679 rows of five FRE 2024 tables (9% of
  # transacao_parte_relacionada) vanished, two of the five tables
  # without a single warning.
  header <- readr::read_delim(
    path,
    delim = delim,
    quote = "",
    locale = readr::locale(encoding = encoding),
    n_max = 0,
    show_col_types = FALSE,
    progress = FALSE
  )
  csv_names <- colnames(header)

  validate_field_count(csv_names, schema, validate, path)
  validate_field_names(csv_names, schema, validate, path)

  # `guess_max = Inf`: a column the type is guessed for is guessed over
  # every row. With readr's default of 1,000, a column empty in its first
  # rows was guessed logical and every later value became NA (the CNPJ
  # of `fre/transacao_parte_relacionada.documento_parte_relacionada`,
  # 2010-2026); over every row a late value can only widen the type.
  df <- readr::read_delim(
    path,
    delim = delim,
    quote = "",
    locale = readr::locale(encoding = encoding),
    col_types = build_col_types(csv_names, schema),
    guess_max = Inf,
    show_col_types = FALSE,
    progress = FALSE
  )
  colnames(df) <- tolower(colnames(df))
  df
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
    msg,
    validate,
    "cvmdata_error_parse",
    .envir = environment()
  )
}

# The column names a table's CSV must carry. A META-less table declares
# them in its YAML (`expected_field_names`); every other table takes them
# from the dictionary snapshot, which is the CVM's META (`campo_original`)
# -- not copied into the YAMLs, so there is one source. Until 2026-10-25
# only the 8 META-less tables had their names checked: the other 66
# compared the COUNT alone, and a column renamed or swapped by the CVM at
# the same count passed silently into the package and the mirror.
# Measured that day against the header of every CSV of every yearly ZIP
# (1,244 headers, 2003-2026): all 74 tables carry exactly the snapshot's
# names in every year (the order differs: the snapshot is alphabetical,
# so the check compares the set). NULL when nothing names the table (a
# synthetic schema).
expected_field_names <- function(schema) {
  if (length(schema$expected_field_names)) {
    return(as.character(schema$expected_field_names))
  }
  if (is.null(schema$dataset) || is.null(schema$table)) {
    return(NULL)
  }
  snapshot <- .read_dictionary_snapshot(require_snapshot_path(
    "cvm_dictionary_snapshot.csv",
    "build-dictionary-snapshot.R"
  ))
  hit <- snapshot$dataset == schema$dataset & snapshot$table == schema$table
  if (!is.null(schema$group)) {
    hit <- hit & snapshot$group == schema$group
  }
  out <- snapshot$campo_original[hit]
  if (length(out)) out else NULL
}

validate_field_names <- function(csv_names, schema, validate, path) {
  expected <- expected_field_names(schema)
  if (is.null(expected)) {
    return(invisible(NULL))
  }
  expected_norm <- tolower(expected)
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
    msg,
    validate,
    "cvmdata_error_parse",
    .envir = environment()
  )
}

emit_validation <- function(
  msg,
  validate,
  error_class,
  .envir = parent.frame()
) {
  if (identical(validate, "strict")) {
    cvmdata_abort(msg, class = error_class, .envir = .envir)
  }
  if (identical(validate, "warn")) {
    cvmdata_warn(
      msg,
      class = "cvmdata_warn_validation",
      .envir = .envir
    )
  }
  invisible(NULL)
}
