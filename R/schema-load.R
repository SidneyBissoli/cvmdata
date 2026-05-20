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
  raw <- yaml::read_yaml(path)
  validate_schema(raw, dataset, table)
  structure(raw, class = c("cvm_table_schema", "list"))
}

# Validate schema invariants. Mutating no state; either returns
# silently or aborts.
validate_schema <- function(s, dataset, table) {
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
        "x" = paste(
          "Got archive={.val {archive}},",
          "file={.val {file_url}}."
        )
      ),
      class = "cvmdata_error_internal"
    )
  }
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
  if (identical(meta_status, "missing")) {
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
  invisible(NULL)
}
