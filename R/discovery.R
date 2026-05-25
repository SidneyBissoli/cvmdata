#' List datasets covered by the package
#'
#' Returns the dataset identifiers (e.g. `"cad"`, `"dfp"`) currently
#' covered. Discovered from the schemas installed under
#' `inst/extdata/schemas/<group>/<dataset>/`.
#'
#' @return A character vector of dataset ids, sorted alphabetically.
#'
#' @examples
#' cvm_datasets()
#' @family discovery
#' @export
cvm_datasets <- function() {
  sort(unique(schema_tree()$dataset))
}

#' List the tables published in a dataset
#'
#' @param dataset Short dataset id (e.g. `"dfp"`).
#'
#' @return A character vector of table names, sorted alphabetically.
#'
#' @examples
#' cvm_tables("dfp")
#' @family discovery
#' @export
cvm_tables <- function(dataset) {
  if (!is.character(dataset) || length(dataset) != 1L ||
        !nzchar(dataset)) {
    cvmdata_abort(
      c("{.arg dataset} must be a single non-empty string."),
      class = "cvmdata_error_input"
    )
  }
  tree <- schema_tree()
  hit <- tree[tree$dataset == dataset, , drop = FALSE]
  if (!nrow(hit)) {
    cvmdata_abort(
      c(
        "Unknown dataset {.val {dataset}}.",
        "i" = "Available: {.val {cvm_datasets()}}."
      ),
      class = "cvmdata_error_input"
    )
  }
  sort(hit$table)
}

#' Look up the CVM-published dictionary for a table
#'
#' Returns the dictionary metadata (field names, descriptions, domain,
#' data type, size/precision/scale) for a single `(dataset, table)`
#' pair, sourced from the snapshot embedded under
#' `inst/extdata/cvm_dictionary_snapshot.csv`. The snapshot is built
#' offline from the CVM META resources by
#' `data-raw/build-dictionary-snapshot.R`.
#'
#' Tables whose META is not published by CVM (`meta_status: missing` in
#' the schema YAML) return rows with `NA` in every metadata column
#' except `campo`/`campo_original` (sourced from the YAML's
#' `expected_field_names`). In that case the returned tibble carries an
#' attribute `meta_status = "missing"`.
#'
#' @param dataset Short dataset id (e.g. `"dfp"`).
#' @param table Table name within the dataset (e.g. `"bpa"`).
#'
#' @return A tibble with one row per column of the table, columns
#'   `campo` (snake-case name matching [cvm_fetch()] output),
#'   `campo_original` (field name as published by CVM in the META,
#'   preserving the original casing), `descricao`, `dominio`,
#'   `tipo_dados`, `tamanho`, `precisao`, `scale`.
#'
#' @examples
#' cvm_dictionary("dfp", "bpa")
#' cvm_dictionary("fre", "empregado_PCD")
#' @family discovery
#' @seealso [cvm_tables()]
#' @export
cvm_dictionary <- function(dataset, table) {
  if (!is.character(dataset) || length(dataset) != 1L ||
        !nzchar(dataset)) {
    cvmdata_abort(
      c("{.arg dataset} must be a single non-empty string."),
      class = "cvmdata_error_input"
    )
  }
  if (!is.character(table) || length(table) != 1L || !nzchar(table)) {
    cvmdata_abort(
      c("{.arg table} must be a single non-empty string."),
      class = "cvmdata_error_input"
    )
  }
  snapshot_path <- system.file(
    "extdata", "cvm_dictionary_snapshot.csv", package = "cvmdata"
  )
  if (!nzchar(snapshot_path)) {
    cvmdata_abort(
      c(
        "Dictionary snapshot not found in {.pkg cvmdata}.",
        "i" = paste(
          "Expected {.path inst/extdata/cvm_dictionary_snapshot.csv};",
          "regenerate via {.path data-raw/build-dictionary-snapshot.R}."
        )
      ),
      class = "cvmdata_error_internal"
    )
  }
  snapshot <- .read_dictionary_snapshot(snapshot_path)
  hit <- snapshot[
    snapshot$dataset == dataset & snapshot$table == table, ,
    drop = FALSE
  ]
  if (!nrow(hit)) {
    available_datasets <- cvm_datasets()
    if (!dataset %in% available_datasets) {
      cvmdata_abort(
        c(
          "Unknown dataset {.val {dataset}}.",
          "i" = "Available: {.val {available_datasets}}."
        ),
        class = "cvmdata_error_input"
      )
    }
    available_tables <- cvm_tables(dataset)
    cvmdata_abort(
      c(
        "No dictionary entries for {.val {dataset}}/{.val {table}}.",
        "i" = "Tables in {.val {dataset}}: {.val {available_tables}}."
      ),
      class = "cvmdata_error_input"
    )
  }
  out <- tibble::tibble(
    campo          = hit$campo,
    campo_original = hit$campo_original,
    descricao      = hit$descricao,
    dominio        = hit$dominio,
    tipo_dados     = hit$tipo_dados,
    tamanho        = hit$tamanho,
    precisao       = hit$precisao,
    scale          = hit$scale
  )
  if (any(hit$meta_status == "missing", na.rm = TRUE)) {
    attr(out, "meta_status") <- "missing"
  }
  out
}

#' Look up the codelist for a categorical column
#'
#' Returns the set of categorical values observed for a single
#' `(dataset, table, column)` triple, sourced from the snapshot
#' embedded under `inst/extdata/cvm_codelists_snapshot.csv`. The
#' snapshot is built offline by `data-raw/build-codelists-snapshot.R`
#' from the CVM open-data CSVs.
#'
#' Inclusion criteria for the snapshot (see CLAUDE.md §9.2):
#' columns whose dictionary `dominio` enumerates values (e.g. `S/N`,
#' `PF/PJ`), and `varchar` columns with `tamanho < 200` and at most
#' 50 distinct values observed in the latest available year.
#'
#' @param dataset Short dataset id (e.g. `"cad"`).
#' @param table Table name within the dataset (e.g. `"companhias"`).
#' @param column Snake-case column name (e.g. `"sit"`).
#'
#' @return A tibble with one row per categorical value, sorted
#'   alphabetically. Column: `value` (character).
#'
#' @examples
#' cvm_codelist("cad", "companhias", "sit")
#' @family discovery
#' @seealso [cvm_dictionary()]
#' @export
cvm_codelist <- function(dataset, table, column) {
  for (arg_name in c("dataset", "table", "column")) {
    val <- get(arg_name)
    if (!is.character(val) || length(val) != 1L || !nzchar(val)) {
      cvmdata_abort(
        c("{.arg {arg_name}} must be a single non-empty string."),
        class = "cvmdata_error_input"
      )
    }
  }
  snapshot_path <- system.file(
    "extdata", "cvm_codelists_snapshot.csv", package = "cvmdata"
  )
  if (!nzchar(snapshot_path)) {
    cvmdata_abort(
      c(
        "Codelists snapshot not found in {.pkg cvmdata}.",
        "i" = paste(
          "Expected {.path inst/extdata/cvm_codelists_snapshot.csv};",
          "regenerate via {.path data-raw/build-codelists-snapshot.R}."
        )
      ),
      class = "cvmdata_error_internal"
    )
  }
  snapshot <- .read_codelists_snapshot(snapshot_path)
  hit <- snapshot[
    snapshot$dataset == dataset &
      snapshot$table == table &
      snapshot$campo == column, ,
    drop = FALSE
  ]
  if (nrow(hit)) {
    return(tibble::tibble(value = hit$value))
  }
  if (!dataset %in% cvm_datasets()) {
    cvmdata_abort(
      c(
        "Unknown dataset {.val {dataset}}.",
        "i" = "Available: {.val {cvm_datasets()}}."
      ),
      class = "cvmdata_error_input"
    )
  }
  if (!table %in% cvm_tables(dataset)) {
    cvmdata_abort(
      c(
        "Unknown table {.val {table}} in {.val {dataset}}.",
        "i" = "Tables: {.val {cvm_tables(dataset)}}."
      ),
      class = "cvmdata_error_input"
    )
  }
  dict <- cvm_dictionary(dataset, table)
  available_codes <- sort(unique(snapshot$campo[
    snapshot$dataset == dataset & snapshot$table == table
  ]))
  if (column %in% dict$campo) {
    cvmdata_abort(
      c(
        paste(
          "Column {.val {column}} in {.val {dataset}}/{.val {table}}",
          "is not a codelist."
        ),
        "i" = if (length(available_codes)) {
          "Codelist columns: {.val {available_codes}}."
        } else {
          "No codelist columns in this table."
        }
      ),
      class = "cvmdata_error_input"
    )
  }
  cvmdata_abort(
    c(
      paste(
        "Unknown column {.val {column}} in",
        "{.val {dataset}}/{.val {table}}."
      ),
      "i" = if (length(available_codes)) {
        "Codelist columns: {.val {available_codes}}."
      } else {
        "No codelist columns in this table."
      }
    ),
    class = "cvmdata_error_input"
  )
}

# Session-scoped cache for the parsed codelists snapshot.
.codelists_snapshot_cache <- new.env(parent = emptyenv())

.read_codelists_snapshot <- function(path) {
  cached <- .codelists_snapshot_cache[[path]]
  if (!is.null(cached)) {
    return(cached)
  }
  df <- readr::read_csv(
    path,
    col_types = readr::cols(
      dataset = readr::col_character(),
      table   = readr::col_character(),
      campo   = readr::col_character(),
      value   = readr::col_character()
    ),
    progress = FALSE
  )
  .codelists_snapshot_cache[[path]] <- df
  df
}

# Session-scoped cache for the parsed snapshot — read it once.
.dictionary_snapshot_cache <- new.env(parent = emptyenv())

.read_dictionary_snapshot <- function(path) {
  cached <- .dictionary_snapshot_cache[[path]]
  if (!is.null(cached)) {
    return(cached)
  }
  df <- readr::read_csv(
    path,
    col_types = readr::cols(
      dataset        = readr::col_character(),
      table          = readr::col_character(),
      campo          = readr::col_character(),
      campo_original = readr::col_character(),
      descricao      = readr::col_character(),
      dominio        = readr::col_character(),
      tipo_dados     = readr::col_character(),
      tamanho        = readr::col_integer(),
      precisao       = readr::col_integer(),
      scale          = readr::col_integer(),
      meta_status    = readr::col_character()
    ),
    progress = FALSE
  )
  .dictionary_snapshot_cache[[path]] <- df
  df
}

#' Range of years available for a yearly-partitioned dataset
#'
#' Discovers the years currently published for the dataset by reading
#' the CVM open-data directory listing. Returns an integer vector
#' (sorted, no gaps assumed). Caches the result for the duration of
#' the R session to avoid repeated HTTP calls.
#'
#' Returns `NA_integer_` for datasets whose tables are not
#' yearly-partitioned (e.g. `cad`).
#'
#' @param dataset Short dataset id.
#' @param schema Optional already-loaded schema (used internally by
#'   [cvm_fetch()] to avoid double-load). Users typically omit.
#'
#' @return An integer vector of available years, or `NA_integer_`.
#'
#' @examplesIf interactive()
#' cvm_dataset_years("dfp")
#' @family discovery
#' @export
cvm_dataset_years <- function(dataset, schema = NULL) {
  if (is.null(schema)) {
    tables <- cvm_tables(dataset)
    if (!length(tables)) {
      cvmdata_abort(
        c("No tables for dataset {.val {dataset}}."),
        class = "cvmdata_error_input"
      )
    }
    schema <- load_schema(dataset, tables[1L])
  }
  partitioning <- schema$temporal_partitioning %||% "none"
  if (!identical(partitioning, "yearly")) {
    return(NA_integer_)
  }
  pattern_url <- schema$cvm_archive_url_pattern
  if (is.null(pattern_url) || !nzchar(pattern_url)) {
    cvmdata_abort(
      c(
        paste(
          "Yearly schema for {.val {dataset}} lacks",
          "{.field cvm_archive_url_pattern}."
        )
      ),
      class = "cvmdata_error_internal"
    )
  }

  # URL base = diretório pai do pattern (tudo até a última '/')
  dir_url <- sub("/[^/]+$", "/", pattern_url)
  zip_basename_glob <- sub("\\{year\\}", "[0-9]{4}",
                           basename(pattern_url))

  years <- get_years_from_listing(dir_url, zip_basename_glob)
  if (!length(years)) {
    cvmdata_abort(
      c(
        paste(
          "No yearly archives found at {.url {dir_url}}",
          "matching {.val {zip_basename_glob}}."
        )
      ),
      class = "cvmdata_error_http"
    )
  }
  sort(years)
}

# Year-listing cache. Keyed by directory URL.
.year_listing_cache <- new.env(parent = emptyenv())

get_years_from_listing <- function(dir_url, basename_regex) {
  cached <- .year_listing_cache[[dir_url]]
  if (!is.null(cached)) {
    return(cached)
  }
  resp <- tryCatch(
    httr2::req_perform(
      httr2::req_timeout(httr2::request(dir_url), 60L)
    ),
    error = function(e) {
      cvmdata_abort(
        c(
          "HTTP GET failed for directory listing {.url {dir_url}}.",
          "x" = "{conditionMessage(e)}"
        ),
        class = "cvmdata_error_http"
      )
    }
  )
  html <- httr2::resp_body_string(resp)
  matches <- regmatches(
    html, gregexpr(basename_regex, html, perl = TRUE)
  )[[1L]]
  years <- as.integer(regmatches(
    matches, regexpr("[0-9]{4}", matches)
  ))
  years <- unique(years[!is.na(years) & years >= 1990 & years <= 2100])
  .year_listing_cache[[dir_url]] <- years
  years
}
