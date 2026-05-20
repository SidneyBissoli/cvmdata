# HTTP source backend for the CVM Open Data Portal. Implements the
# Phase B contract for `temporal_partitioning: none` only (Session 1).
# `yearly` partitioning is rejected with a "not implemented yet"
# internal error — handled in Session 2.

# Resolve the cache root. Overridable via `options(cvmdata.cache_dir)`
# so that tests can swap the user's cache for a tempdir.
cvm_cache_root <- function() {
  getOption(
    "cvmdata.cache_dir",
    tools::R_user_dir("cvmdata", which = "cache")
  )
}

# Download (or serve from cache) the CSV referenced by a schema.
# Returns the local path to the cached CSV. Cache layout follows
# `cvmdata_rodada2_arquitetura_estavel.md` §5.2:
# `<cache_root>/raw/<dataset>/<filename>` with a sidecar RDS holding
# ETag and Last-Modified.
#
# @param schema A `cvm_table_schema`.
# @param year Required when `schema$temporal_partitioning == "yearly"`;
#   ignored otherwise.
# @return Local filesystem path to the CSV ready to read.
source_cvm_http_get <- function(schema, year = NULL, ...) {
  partitioning <- schema$temporal_partitioning %||% "none"
  if (!identical(partitioning, "none")) {
    cvmdata_abort(
      c(
        paste(
          "Temporal partitioning {.val {partitioning}} not",
          "implemented yet."
        ),
        "i" = paste(
          "Session 1 covers only {.code temporal_partitioning: none}.",
          "Yearly partitioning lands in Session 2."
        )
      ),
      class = "cvmdata_error_internal"
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

  cache_dir <- file.path(cvm_cache_root(), "raw", schema$dataset)
  if (!dir.exists(cache_dir)) {
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  }

  csv_path <- file.path(cache_dir, basename(url))
  etag_path <- paste0(csv_path, ".etag.rds")

  cached_meta <- if (file.exists(etag_path)) {
    tryCatch(readRDS(etag_path), error = function(e) NULL)
  } else {
    NULL
  }

  fresh <- FALSE
  if (file.exists(csv_path) && !is.null(cached_meta)) {
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
    writeBin(httr2::resp_body_raw(download_resp), csv_path)
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

  csv_path
}
