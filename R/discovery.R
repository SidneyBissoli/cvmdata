#' List datasets covered by the package
#'
#' Returns the dataset identifiers (e.g. `"cad"`, `"dfp"`) currently
#' covered. Discovered from the schemas installed under
#' `inst/extdata/schemas/`.
#'
#' @return A character vector of dataset ids, sorted alphabetically.
#'
#' @examples
#' cvm_datasets()
#' @family discovery
#' @export
cvm_datasets <- function() {
  root <- system.file("extdata", "schemas", package = "cvmdata")
  if (!nzchar(root)) {
    return(character(0L))
  }
  sort(list.dirs(root, recursive = FALSE, full.names = FALSE))
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
  dir_path <- system.file(
    "extdata", "schemas", dataset, package = "cvmdata"
  )
  if (!nzchar(dir_path)) {
    cvmdata_abort(
      c(
        "Unknown dataset {.val {dataset}}.",
        "i" = "Available: {.val {cvm_datasets()}}."
      ),
      class = "cvmdata_error_input"
    )
  }
  files <- list.files(dir_path, pattern = "\\.yaml$", full.names = FALSE)
  sort(sub("\\.yaml$", "", files))
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
