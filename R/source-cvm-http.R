# HTTP source backend for the CVM Open Data Portal. Two paths:
#
# 1. `temporal_partitioning: none` — single CSV (used by CAD).
# 2. `temporal_partitioning: yearly` — yearly ZIP that contains many
#    CSVs, one of which (optionally selected by report_type) is the
#    target table.
#
# Both paths cache the raw upstream artifact (CSV or ZIP) under
# `<cache_root>/raw/<group>/<dataset>/...` with a sidecar `.etag.rds`
# for ETag/Last-Modified comparison. Freshness is gated by a TTL
# window (default 30 days, configurable via
# `options(cvmdata.cache_ttl_seconds)`): within the TTL the HEAD/GET
# round-trip is skipped entirely.

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
  cache_migrate_v0_1_to_v0_2()
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
  cache_dir <- file.path(
    cvm_cache_path(), "raw",
    dataset_group(schema$dataset), schema$dataset
  )
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

  cache_dir <- file.path(
    cvm_cache_path(), "raw",
    dataset_group(schema$dataset), schema$dataset,
    as.character(year)
  )
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
# freshness. Writes a sidecar `.etag.rds` with cache headers. Skips the
# HEAD/GET round-trip when the cached artifact is within its TTL window
# (see `cache_is_within_ttl()`).
download_with_etag <- function(url, dest_path) {
  etag_path <- paste0(dest_path, ".etag.rds")
  cached_meta <- if (file.exists(etag_path)) {
    tryCatch(readRDS(etag_path), error = function(e) NULL)
  } else {
    NULL
  }

  if (cache_is_within_ttl(dest_path, cached_meta)) {
    return(invisible(dest_path))
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
    # Amortised LRU eviction: only fires after a real write (the TTL
    # and 304-not-modified branches above return without touching
    # disk, so steady-state reads pay zero eviction cost). The
    # just-written artifact is protected against self-eviction.
    cache_enforce_limit(protect = dest_path)
  }
  invisible(dest_path)
}

# TTL gate consulted by `download_with_etag()` before issuing HEAD.
# Default 30 days; `options(cvmdata.cache_ttl_seconds)` overrides.
# Special values: 0 forces every call to HEAD (legacy behaviour);
# Inf skips HEAD forever while the sidecar exists. Sidecars without a
# parseable `fetched_at` (legacy or corrupt) fall back to HEAD so the
# next download refreshes the metadata.
cache_is_within_ttl <- function(dest_path, cached_meta) {
  if (!file.exists(dest_path) || is.null(cached_meta)) {
    return(FALSE)
  }
  ttl <- read_cache_ttl()
  if (is.na(ttl) || ttl == 0) {
    return(FALSE)
  }
  fetched_time <- parse_iso_utc(cached_meta$fetched_at)
  if (is.na(fetched_time)) {
    return(FALSE)
  }
  if (is.infinite(ttl)) {
    return(TRUE)
  }
  age <- as.numeric(
    difftime(Sys.time(), fetched_time, units = "secs")
  )
  age < ttl
}

# Read and validate `options(cvmdata.cache_ttl_seconds)`. Returns the
# numeric TTL in seconds, or `NA_real_` when the option is malformed
# (caller treats NA as "no shortcut, always HEAD").
read_cache_ttl <- function() {
  ttl <- getOption("cvmdata.cache_ttl_seconds", 2592000)
  if (!is.numeric(ttl) || length(ttl) != 1L || is.na(ttl) ||
        ttl < 0) {
    return(NA_real_)
  }
  as.numeric(ttl)
}

# Parse the ISO 8601 UTC timestamp stored in `fetched_at`
# (`"%Y-%m-%dT%H:%M:%OS3Z"`). Returns POSIXct NA on any parse failure
# so callers can treat malformed sidecars as "no freshness info".
parse_iso_utc <- function(s) {
  if (is.null(s) || !is.character(s) || length(s) != 1L ||
        !nzchar(s)) {
    return(as.POSIXct(NA_character_, tz = "UTC"))
  }
  stripped <- sub("Z$", "", s)
  tryCatch(
    as.POSIXct(stripped, format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC"),
    error = function(e) as.POSIXct(NA_character_, tz = "UTC"),
    warning = function(w) as.POSIXct(NA_character_, tz = "UTC")
  )
}
