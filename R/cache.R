# Public cache API. Single source of truth for the cache root used by
# the HTTP source backend and any future cache layer (L3 parquet, L4
# memory). All cache directories live under the path returned by
# `cvm_cache_path()`; the raw HTTP artifacts (CSV directos for
# non-partitioned datasets, ZIP + extracted CSVs for yearly datasets)
# live under `<cache>/raw/<dataset>/[<year>/]`.

#' Path to the cvmdata cache directory
#'
#' Returns the directory where downloaded CSV/ZIP artifacts are cached.
#' The default is the user-level cache slot from
#' [tools::R_user_dir()], which can be overridden by setting the
#' option `cvmdata.cache_dir` (see [cvm_cache_set_path()]).
#'
#' Cached artifacts are revalidated against the CVM portal (HEAD with
#' ETag/Last-Modified) only after the freshness window expires. The
#' window is controlled by the option `cvmdata.cache_ttl_seconds`
#' (default `2592000`, i.e. 30 days); set it to `0` to revalidate on
#' every call, or to `Inf` to skip revalidation entirely until
#' [cvm_cache_clear()] is called.
#'
#' Read-only: this function does not create the directory.
#'
#' @return A character scalar with the absolute path.
#'
#' @examples
#' cvm_cache_path()
#' @family cache
#' @seealso [cvm_cache_set_path()], [cvm_cache_info()],
#'   [cvm_cache_clear()]
#' @export
cvm_cache_path <- function() {
  getOption(
    "cvmdata.cache_dir",
    tools::R_user_dir("cvmdata", which = "cache")
  )
}

#' Set the cvmdata cache directory
#'
#' Configures the option `cvmdata.cache_dir` so that subsequent
#' downloads land at `path`. The directory is created (recursively) if
#' it does not exist, and writeability is verified before the option
#' is committed.
#'
#' @param path Character scalar with the desired cache directory.
#'
#' @return The normalized path, invisibly.
#'
#' @examplesIf interactive()
#' cvm_cache_set_path(tempfile("cvmdata-"))
#' @family cache
#' @seealso [cvm_cache_path()]
#' @export
cvm_cache_set_path <- function(path) {
  if (!is.character(path) || length(path) != 1L || !nzchar(path) ||
        is.na(path)) {
    cvmdata_abort(
      c("{.arg path} must be a single non-empty string."),
      class = "cvmdata_error_input"
    )
  }
  if (!dir.exists(path)) {
    created <- dir.create(path, recursive = TRUE, showWarnings = FALSE)
    if (!created || !dir.exists(path)) {
      cvmdata_abort(
        c(
          "Could not create cache directory {.path {path}}.",
          "i" = "Check parent-directory permissions."
        ),
        class = "cvmdata_error_internal"
      )
    }
  }
  probe <- tempfile(tmpdir = path, fileext = ".tmp")
  ok <- tryCatch(
    {
      writeable <- file.create(probe)
      if (file.exists(probe)) {
        unlink(probe, force = TRUE)
      }
      isTRUE(writeable)
    },
    warning = function(w) FALSE,
    error = function(e) FALSE
  )
  if (!ok) {
    cvmdata_abort(
      c(
        "Cache directory {.path {path}} is not writeable.",
        "i" = "Choose a different path."
      ),
      class = "cvmdata_error_input"
    )
  }
  normalized <- normalizePath(path, winslash = "/", mustWork = TRUE)
  options(cvmdata.cache_dir = normalized)
  cli::cli_inform(c(
    "v" = "Cache directory set to {.path {normalized}}."
  ))
  invisible(normalized)
}

#' Inventory of files in the cvmdata cache
#'
#' Lists every artifact currently stored under
#' `<cache>/raw/`, with size, modification time and ETag metadata
#' when available. Both upstream artifacts (CSV directos for
#' non-partitioned datasets, ZIPs for yearly datasets) and CSVs
#' extracted from those ZIPs appear as separate rows; the sidecar
#' `*.etag.rds` files themselves are excluded from the listing
#' (their content surfaces in the `etag` and `last_modified`
#' columns).
#'
#' Extracted CSVs have no sidecar of their own — the freshness of
#' the parent ZIP covers them — so they appear with
#' `etag = NA_character_` and `last_modified = NA_character_`.
#'
#' @return A tibble with one row per cached file, sorted by
#'   `dataset` then `file`. Columns: `dataset` (character),
#'   `file` (basename), `path` (absolute), `size_bytes` (integer),
#'   `mtime` (POSIXct), `etag` (character; `NA` when absent),
#'   `last_modified` (character; `NA` when absent). Returns a
#'   zero-row tibble with the same schema when the cache is empty.
#'
#' @examples
#' cvm_cache_info()
#' @family cache
#' @export
cvm_cache_info <- function() {
  schema <- tibble::tibble(
    dataset       = character(0L),
    file          = character(0L),
    path          = character(0L),
    size_bytes    = integer(0L),
    mtime         = as.POSIXct(character(0L), tz = "UTC"),
    etag          = character(0L),
    last_modified = character(0L)
  )
  raw_root <- file.path(cvm_cache_path(), "raw")
  if (!dir.exists(raw_root)) {
    return(schema)
  }
  all_files <- list.files(
    raw_root, recursive = TRUE, full.names = TRUE, no.. = TRUE
  )
  artifacts <- all_files[!grepl("\\.etag\\.rds$", all_files)]
  if (!length(artifacts)) {
    return(schema)
  }
  rel <- substring(artifacts, nchar(raw_root) + 2L)
  dataset <- vapply(
    strsplit(rel, "/", fixed = TRUE), `[[`, character(1L), 1L
  )
  file_basename <- basename(artifacts)
  size_bytes <- as.integer(file.size(artifacts))
  mtime <- file.mtime(artifacts)
  sidecar_paths <- paste0(artifacts, ".etag.rds")
  etag <- rep(NA_character_, length(artifacts))
  last_modified <- rep(NA_character_, length(artifacts))
  for (i in seq_along(artifacts)) {
    if (file.exists(sidecar_paths[[i]])) {
      meta <- tryCatch(
        readRDS(sidecar_paths[[i]]),
        error = function(e) NULL
      )
      if (is.list(meta)) {
        etag[[i]] <- meta$etag %||% NA_character_
        last_modified[[i]] <- meta$last_modified %||% NA_character_
      }
    }
  }
  out <- tibble::tibble(
    dataset       = dataset,
    file          = file_basename,
    path          = artifacts,
    size_bytes    = size_bytes,
    mtime         = mtime,
    etag          = etag,
    last_modified = last_modified
  )
  out[order(out$dataset, out$file), , drop = FALSE]
}

#' Clear cached files
#'
#' Deletes cached files selectively. `what = "all"` removes the
#' entire cache tree (everything under [cvm_cache_path()]);
#' `what = "raw"` removes only the raw download area
#' (`<cache>/raw/`). When `dataset` (and optionally `year`) is
#' supplied, the scope is narrowed to
#' `<cache>/raw/<dataset>/[<year>/]`; `what` is implicit and must
#' be `"raw"` in that case.
#'
#' In interactive sessions the user is asked to confirm via
#' [utils::askYesNo()] before deletion. In batch sessions the
#' default (`confirm = interactive()`) evaluates to `FALSE` and
#' deletion proceeds silently — pass `confirm = TRUE` explicitly to
#' force a prompt.
#'
#' @param what One of `"all"` or `"raw"`. Default `"all"`.
#' @param dataset Optional dataset id (e.g. `"dfp"`). Restricts
#'   deletion to `<cache>/raw/<dataset>/`.
#' @param year Optional integer year. Requires `dataset` to be
#'   non-`NULL`. Restricts deletion to
#'   `<cache>/raw/<dataset>/<year>/`.
#' @param confirm Logical scalar. When `TRUE`, asks for confirmation
#'   before deleting. Default: [interactive()].
#'
#' @return The number of files deleted, invisibly.
#'
#' @examplesIf interactive()
#' cvm_cache_clear(dataset = "dfp", year = 2024)
#' cvm_cache_clear(what = "raw")
#' @family cache
#' @export
cvm_cache_clear <- function(what = "all",
                            dataset = NULL,
                            year = NULL,
                            confirm = interactive()) {
  args <- .validate_cache_clear_args(what, dataset, year, confirm)
  target <- .cache_clear_target(
    cvm_cache_path(), args$what, args$dataset, args$year
  )
  if (!dir.exists(target)) {
    if (!is.null(args$dataset)) {
      cvmdata_abort(
        c(
          "No cached files at {.path {target}}.",
          "i" = paste(
            "Either {.val {args$dataset}} is unknown or the cache was",
            "never populated for it."
          )
        ),
        class = "cvmdata_error_input"
      )
    }
    return(invisible(0L))
  }
  n_files <- length(list.files(target, recursive = TRUE, no.. = TRUE))
  if (args$confirm) {
    answer <- utils::askYesNo(
      sprintf("Delete %d file(s) under %s?", n_files, target),
      default = FALSE
    )
    if (!isTRUE(answer)) {
      cli::cli_inform(c("i" = "Cancelled; nothing was deleted."))
      return(invisible(0L))
    }
  }
  unlink(target, recursive = TRUE, force = TRUE)
  cli::cli_inform(c(
    "v" = "Deleted {n_files} file{?s} from {.path {target}}."
  ))
  invisible(n_files)
}

# Validate the four arguments of cvm_cache_clear(); returns the
# normalized (what, dataset, year, confirm) list. `what` is widened
# to "raw" when a dataset filter is supplied.
.validate_cache_clear_args <- function(what, dataset, year, confirm) {
  what <- rlang::arg_match0(what, c("all", "raw"))
  if (!is.null(year) && is.null(dataset)) {
    cvmdata_abort(
      c("{.arg year} requires {.arg dataset} to be supplied."),
      class = "cvmdata_error_input"
    )
  }
  .check_dataset_arg(dataset)
  if (!is.null(dataset) && identical(what, "all")) {
    what <- "raw"
  }
  year <- .check_year_arg(year)
  .check_confirm_arg(confirm)
  list(what = what, dataset = dataset, year = year, confirm = confirm)
}

.check_dataset_arg <- function(dataset) {
  if (is.null(dataset)) {
    return(invisible())
  }
  if (!is.character(dataset) || length(dataset) != 1L ||
        !nzchar(dataset)) {
    cvmdata_abort(
      c("{.arg dataset} must be a single non-empty string."),
      class = "cvmdata_error_input"
    )
  }
  invisible()
}

.check_year_arg <- function(year) {
  if (is.null(year)) {
    return(NULL)
  }
  if (length(year) != 1L || is.na(year) ||
        !is.numeric(year) || year != as.integer(year)) {
    cvmdata_abort(
      c("{.arg year} must be a single integer."),
      class = "cvmdata_error_input"
    )
  }
  as.integer(year)
}

.check_confirm_arg <- function(confirm) {
  if (!is.logical(confirm) || length(confirm) != 1L || is.na(confirm)) {
    cvmdata_abort(
      c("{.arg confirm} must be a single logical (TRUE or FALSE)."),
      class = "cvmdata_error_input"
    )
  }
  invisible()
}

# Compose the absolute path the cleanup should target.
.cache_clear_target <- function(cache_root, what, dataset, year) {
  if (identical(what, "all")) {
    return(cache_root)
  }
  base <- file.path(cache_root, "raw")
  if (is.null(dataset)) {
    return(base)
  }
  if (is.null(year)) {
    return(file.path(base, dataset))
  }
  file.path(base, dataset, as.character(year))
}

# Internal: ensure a directory exists. Used by the HTTP source backend
# to lazily materialise the per-dataset subtree under the cache root.
ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
  invisible(path)
}
