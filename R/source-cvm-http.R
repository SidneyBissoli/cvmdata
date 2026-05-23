# HTTP source backend for the CVM Open Data Portal. Two paths:
#
# 1. `temporal_partitioning: none` — single CSV (used by CAD).
# 2. `temporal_partitioning: yearly` — yearly ZIP that contains many
#    CSVs, one of which (optionally selected by report_type) is the
#    target table.
#
# Both paths cache the raw upstream artifact (CSV or ZIP) under
# `<cache_root>/raw/<dataset>/...` with a sidecar `.etag.rds` for
# ETag/Last-Modified comparison.

# Download (or serve from cache) the CSV referenced by a schema. Returns
# the local path to the CSV ready to read.
#
# @param schema A `cvm_table_schema`.
# @param year Required when `schema$temporal_partitioning == "yearly"`.
# @param report_type Required when the schema declares
#   `cvm_file_pattern_variants`.
# @return Local filesystem path to the CSV.
source_cvm_http_get <- function(schema, year = NULL,
                                report_type = NULL, ...) {
  partitioning <- schema$temporal_partitioning %||% "none"
  if (identical(partitioning, "none")) {
    return(get_simple_csv(schema, report_type))
  }
  if (identical(partitioning, "yearly")) {
    if (is.null(year)) {
      cvmdata_abort(
        c(
          paste(
            "Table {.val {schema$dataset}}/{.val {schema$table}}",
            "is yearly-partitioned; {.arg year} is required."
          )
        ),
        class = "cvmdata_error_internal"
      )
    }
    return(get_yearly_csv(schema, as.integer(year), report_type))
  }
  cvmdata_abort(
    c(
      paste(
        "Unknown {.field temporal_partitioning} value",
        "{.val {partitioning}}."
      )
    ),
    class = "cvmdata_error_internal"
  )
}

# Path for non-partitioned datasets (CAD-style).
get_simple_csv <- function(schema, report_type) {
  if (!is.null(report_type)) {
    cvmdata_abort(
      c(
        paste(
          "Table {.val {schema$dataset}}/{.val {schema$table}} does",
          "not support {.arg report_type}; pass {.code NULL}."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  url <- schema$cvm_file_url_pattern
  if (is.null(url) || !nzchar(url)) {
    cvmdata_abort(
      c(
        "Schema lacks {.field cvm_file_url_pattern}.",
        "i" = "Required when {.code temporal_partitioning: none}."
      ),
      class = "cvmdata_error_internal"
    )
  }
  cache_dir <- file.path(cvm_cache_path(), "raw", schema$dataset)
  ensure_dir(cache_dir)
  csv_path <- file.path(cache_dir, basename(url))
  download_with_etag(url, csv_path)
  csv_path
}

# Path for yearly-partitioned datasets (DFP/ITR/FRE-detail).
get_yearly_csv <- function(schema, year, report_type) {
  archive_url <- sub("\\{year\\}", year, schema$cvm_archive_url_pattern,
                     fixed = FALSE)
  csv_pattern <- resolve_file_pattern(schema, report_type)
  csv_name <- sub("\\{year\\}", year, csv_pattern, fixed = FALSE)

  cache_dir <- file.path(cvm_cache_path(), "raw", schema$dataset,
                         as.character(year))
  ensure_dir(cache_dir)
  zip_path <- file.path(cache_dir, basename(archive_url))
  download_with_etag(archive_url, zip_path)

  csv_path <- file.path(cache_dir, csv_name)
  if (!file.exists(csv_path) ||
        file.mtime(csv_path) < file.mtime(zip_path)) {
    unzip(zip_path, files = csv_name, exdir = cache_dir, overwrite = TRUE)
  }
  if (!file.exists(csv_path)) {
    cvmdata_abort(
      c(
        paste(
          "CSV {.val {csv_name}} not found inside ZIP",
          "{.path {basename(zip_path)}}."
        ),
        "i" = paste(
          "Either the schema declares the wrong",
          "{.field cvm_file_pattern_variants} or the upstream archive",
          "layout changed."
        )
      ),
      class = "cvmdata_error_parse"
    )
  }
  csv_path
}

# Download a URL into `dest_path`, honoring ETag/Last-Modified for
# freshness. Writes a sidecar `.etag.rds` with cache headers.
download_with_etag <- function(url, dest_path) {
  etag_path <- paste0(dest_path, ".etag.rds")
  cached_meta <- if (file.exists(etag_path)) {
    tryCatch(readRDS(etag_path), error = function(e) NULL)
  } else {
    NULL
  }

  fresh <- FALSE
  if (file.exists(dest_path) && !is.null(cached_meta)) {
    head_resp <- tryCatch(
      httr2::req_perform(httr2::req_method(httr2::request(url), "HEAD")),
      error = function(e) {
        cvmdata_abort(
          c(
            "HTTP HEAD failed for {.url {url}}.",
            "x" = "{conditionMessage(e)}"
          ),
          class = "cvmdata_error_http"
        )
      }
    )
    remote_etag <- httr2::resp_header(head_resp, "ETag")
    remote_lm <- httr2::resp_header(head_resp, "Last-Modified")
    fresh <-
      (!is.null(remote_etag) &&
         identical(cached_meta$etag, remote_etag)) ||
      (!is.null(remote_lm) &&
         identical(cached_meta$last_modified, remote_lm))
  }

  if (!fresh) {
    download_resp <- tryCatch(
      httr2::req_perform(httr2::request(url)),
      error = function(e) {
        cvmdata_abort(
          c(
            "HTTP GET failed for {.url {url}}.",
            "x" = "{conditionMessage(e)}"
          ),
          class = "cvmdata_error_http"
        )
      }
    )
    writeBin(httr2::resp_body_raw(download_resp), dest_path)
    saveRDS(
      list(
        etag = httr2::resp_header(download_resp, "ETag"),
        last_modified = httr2::resp_header(
          download_resp,
          "Last-Modified"
        ),
        fetched_at = format(
          Sys.time(),
          "%Y-%m-%dT%H:%M:%OS3Z",
          tz = "UTC"
        )
      ),
      etag_path
    )
  }
  invisible(dest_path)
}
