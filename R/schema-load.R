# Schema YAML loader. One YAML per (dataset, table) lives in
# `inst/extdata/schemas/<dataset>/<table>.yaml`. Format documented in
# naming doc v03 §7.2 with the `meta_status` refinement from Rodada
# 3.0.2 §4.1.

# Resolve and load the YAML for one table. Returns a `cvm_table_schema`
# S3 list with validated invariants. Errors of class
# `cvmdata_error_input` (table not found) or `cvmdata_error_internal`
# (malformed YAML).
#
# @param dataset Short dataset id, e.g. "cad".
# @param table Snake-case table name, e.g. "companhias".
# @return A list with the schema fields, of class `cvm_table_schema`.
load_schema <- function(dataset, table) {
  rel <- file.path("extdata", "schemas", dataset, paste0(table, ".yaml"))
  path <- system.file(rel, package = "cvmdata")
  if (!nzchar(path)) {
    cvmdata_abort(
      c(
        "Schema not found for dataset {.val {dataset}}, table {.val {table}}.",
        "i" = "Looked for {.path {rel}} under the package's installed files."
      ),
      class = "cvmdata_error_input"
    )
  }
  raw <- read_schema_yaml(path)
  validate_schema(raw, dataset, table)
  structure(raw, class = c("cvm_table_schema", "list"))
}

# Read a YAML schema file forcing UTF-8 regardless of the user's
# `LC_CTYPE`. `yaml::read_yaml(path)` delegates to an internal
# `readLines(path)` whose encoding follows the active locale; under
# `LC_CTYPE = "C"` (common in non-interactive R or stripped-down REPL
# sessions on Windows), multibyte UTF-8 bytes in our schema comments
# (e.g. "Demonstração", "Exercício") get rejected as invalid input and
# the file is silently truncated, leaving `yaml::read_yaml()` to return
# `NULL` and downstream validators to abort with confusing "empty
# field" messages. Opening the connection ourselves with
# `encoding = "UTF-8"` sidesteps the locale entirely.
read_schema_yaml <- function(path) {
  con <- file(path, encoding = "UTF-8")
  on.exit(close(con), add = TRUE)
  txt <- paste(readLines(con, warn = FALSE), collapse = "\n")
  yaml::yaml.load(txt)
}

# Validate schema invariants. Mutating no state; either returns
# silently or aborts.
validate_schema <- function(s, dataset, table) {
  validate_url_topology(s, dataset, table)
  validate_file_pattern_topology(s, dataset, table)
  validate_meta_status(s, dataset, table)
  validate_temporal_partitioning(s, dataset, table)
  invisible(NULL)
}

# Exactly one of cvm_archive_url_pattern / cvm_file_url_pattern.
validate_url_topology <- function(s, dataset, table) {
  archive <- s$cvm_archive_url_pattern
  file_url <- s$cvm_file_url_pattern
  has_archive <- !is.null(archive) && !is.na(archive) && nzchar(archive)
  has_file <- !is.null(file_url) && !is.na(file_url) && nzchar(file_url)
  if (has_archive == has_file) {
    cvmdata_abort(
      c(
        paste(
          "Schema for {.val {dataset}}/{.val {table}} must declare",
          "exactly one of {.field cvm_archive_url_pattern} or",
          "{.field cvm_file_url_pattern}."
        ),
        "x" = paste("Got archive={.val {archive}},",
                    "file={.val {file_url}}.")
      ),
      class = "cvmdata_error_internal"
    )
  }
}

# Exactly one of cvm_file_pattern / cvm_file_pattern_variants;
# variants require archive (not bare URL); variant keys must be ind/con.
validate_file_pattern_topology <- function(s, dataset, table) {
  has_pattern <- !is.null(s$cvm_file_pattern) &&
    is.character(s$cvm_file_pattern) &&
    length(s$cvm_file_pattern) == 1L &&
    nzchar(s$cvm_file_pattern)
  has_variants <- !is.null(s$cvm_file_pattern_variants) &&
    is.list(s$cvm_file_pattern_variants) &&
    length(s$cvm_file_pattern_variants) > 0L
  if (has_pattern == has_variants) {
    cvmdata_abort(
      c(paste(
        "Schema for {.val {dataset}}/{.val {table}} must declare",
        "exactly one of {.field cvm_file_pattern} (scalar) or",
        "{.field cvm_file_pattern_variants} (map with",
        "{.val ind}/{.val con} keys)."
      )),
      class = "cvmdata_error_internal"
    )
  }
  if (!has_variants) {
    return(invisible(NULL))
  }
  variant_keys <- names(s$cvm_file_pattern_variants)
  if (!setequal(variant_keys, c("ind", "con"))) {
    cvmdata_abort(
      c(
        paste(
          "Schema for {.val {dataset}}/{.val {table}}:",
          "{.field cvm_file_pattern_variants} must have",
          "exactly the keys {.val ind} and {.val con}."
        ),
        "x" = "Got: {.val {variant_keys}}."
      ),
      class = "cvmdata_error_internal"
    )
  }
  if (!is.null(s$cvm_file_url_pattern) && nzchar(s$cvm_file_url_pattern)) {
    cvmdata_abort(
      c(
        paste(
          "Schema for {.val {dataset}}/{.val {table}}:",
          "{.field cvm_file_pattern_variants} is incompatible with",
          "{.field cvm_file_url_pattern}."
        ),
        "i" = "Variants require ZIP-based archives."
      ),
      class = "cvmdata_error_internal"
    )
  }
}

# meta_status domain + cross-checks with expected_field_names and
# cvm_dictionary_url.
validate_meta_status <- function(s, dataset, table) {
  meta_status <- s$meta_status %||% "available"
  if (!meta_status %in% c("available", "missing")) {
    cvmdata_abort(
      c(
        "Invalid {.field meta_status} value {.val {meta_status}}.",
        "i" = "Must be {.val available} or {.val missing}."
      ),
      class = "cvmdata_error_internal"
    )
  }
  if (!identical(meta_status, "missing")) {
    return(invisible(NULL))
  }
  if (is.null(s$expected_field_names) ||
        !length(s$expected_field_names)) {
    cvmdata_abort(
      c(
        paste(
          "Schema for {.val {dataset}}/{.val {table}} declares",
          "{.code meta_status: missing} but lacks",
          "{.field expected_field_names}."
        ),
        "i" = paste(
          "When the CVM does not publish a META, the schema YAML",
          "must enumerate the field names explicitly."
        )
      ),
      class = "cvmdata_error_internal"
    )
  }
  if (!is.null(s$cvm_dictionary_url) && nzchar(s$cvm_dictionary_url)) {
    cvmdata_abort(
      c(
        paste(
          "Schema for {.val {dataset}}/{.val {table}} declares",
          "{.code meta_status: missing} but also a",
          "{.field cvm_dictionary_url}."
        ),
        "i" = "These two are mutually exclusive."
      ),
      class = "cvmdata_error_internal"
    )
  }
}

# temporal_partitioning domain + first_year requirement.
validate_temporal_partitioning <- function(s, dataset, table) {
  if (!identical(s$temporal_partitioning, "none") &&
        !identical(s$temporal_partitioning, "yearly")) {
    cvmdata_abort(
      c(
        paste(
          "Invalid {.field temporal_partitioning} value",
          "{.val {s$temporal_partitioning}}."
        ),
        "i" = "Must be {.val none} or {.val yearly}."
      ),
      class = "cvmdata_error_internal"
    )
  }
  if (!identical(s$temporal_partitioning, "yearly")) {
    return(invisible(NULL))
  }
  fy <- s$first_year
  ok <- !is.null(fy) && is.numeric(fy) && length(fy) == 1L &&
    is.finite(fy) && fy == as.integer(fy)
  if (!ok) {
    cvmdata_abort(
      c(paste(
        "Schema for {.val {dataset}}/{.val {table}} declares",
        "{.code temporal_partitioning: yearly} but lacks a",
        "valid {.field first_year} (integer)."
      )),
      class = "cvmdata_error_internal"
    )
  }
}

# Resolve the CSV pattern from a schema given a report_type. Returns the
# concrete file pattern (still with {year} placeholder unsubstituted) or
# aborts with a clear input error when the schema/report_type combo is
# invalid.
#
# @param schema A `cvm_table_schema`.
# @param report_type One of "ind", "con", or NULL.
# @return Character scalar.
resolve_file_pattern <- function(schema, report_type) {
  variants <- schema$cvm_file_pattern_variants
  if (is.null(variants) || !length(variants)) {
    # Tabela sem variants — report_type deve ser NULL
    if (!is.null(report_type)) {
      cvmdata_abort(
        c(
          paste(
            "Table {.val {schema$dataset}}/{.val {schema$table}}",
            "does not have {.val ind}/{.val con} variants;",
            "{.arg report_type} must be {.code NULL}."
          ),
          "x" = "Got {.val {report_type}}."
        ),
        class = "cvmdata_error_input"
      )
    }
    return(schema$cvm_file_pattern)
  }
  # Tabela com variants — report_type obrigatorio
  if (is.null(report_type)) {
    cvmdata_abort(
      c(
        paste(
          "Table {.val {schema$dataset}}/{.val {schema$table}} requires",
          "{.arg report_type} ({.val ind} or {.val con})."
        ),
        "i" = paste(
          "Pass {.code report_type = \"ind\"} for individual or",
          "{.code report_type = \"con\"} for consolidated."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  if (!report_type %in% names(variants)) {
    cvmdata_abort(
      c(
        paste(
          "Unknown {.arg report_type} {.val {report_type}} for table",
          "{.val {schema$dataset}}/{.val {schema$table}}."
        ),
        "i" = "Available variants: {.val {names(variants)}}."
      ),
      class = "cvmdata_error_input"
    )
  }
  variants[[report_type]]
}
