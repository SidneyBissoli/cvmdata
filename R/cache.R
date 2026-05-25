# Public cache API. Single source of truth for the cache root used by
# the HTTP source backend and any future cache layer (L3 parquet, L4
# memory). All cache directories live under the path returned by
# `cvm_cache_path()`; the raw HTTP artifacts (CSV directos for
# non-partitioned datasets, ZIP + extracted CSVs for yearly datasets)
# live under `<cache>/raw/<group>/<dataset>/[<year>/]`. The `<group>`
# segment is the CVM CKAN group slug (`companhias` for the four v0.1
# datasets); see `R/util-group-lookup.R`. A one-time migration
# (`cache_migrate_v0_1_to_v0_2()`) relocates pre-v0.1.0.9000 caches
# that lived directly under `<cache>/raw/<dataset>/`.

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
#' The cache size is bounded by `options(cvmdata.cache_max_size_mb)`
#' (default `100` MiB). Whenever the total counted across yearly
#' bundles and non-partitioned `{artifact, sidecar}` pairs exceeds
#' 90% of the limit, the next download evicts the oldest units
#' (by ZIP/CSV `mtime`) until the cache is at or below 80% of the
#' limit. Set the option to `0`, a negative number, or `Inf` to
#' disable eviction. Interactive sessions see a
#' `cvmdata_warn_eviction` warning after each eviction round;
#' batch jobs stay silent unless
#' `options(cvmdata.cache_warn_evictions = TRUE)` is set.
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
#' The returned tibble carries an attribute `total_size_bytes` with
#' the sum of `size_bytes`, useful for comparing against the
#' eviction limit set via `options(cvmdata.cache_max_size_mb)`
#' (default 100 MiB). When the total exceeds 90% of the limit, the
#' next download triggers LRU eviction of the oldest year directories
#' (yearly datasets) or artifact+sidecar pairs (non-partitioned).
#' See [cvm_cache_path()] for the option's semantics.
#'
#' @return A tibble with one row per cached file, sorted by
#'   `group` then `dataset` then `file`. Columns: `group`
#'   (character), `dataset` (character), `file` (basename), `path`
#'   (absolute), `size_bytes` (integer), `mtime` (POSIXct), `etag`
#'   (character; `NA` when absent), `last_modified` (character;
#'   `NA` when absent). The tibble has an attribute
#'   `total_size_bytes` (numeric scalar) with the total bytes counted
#'   toward the cache size limit. Returns a zero-row tibble with the
#'   same schema (and `total_size_bytes = 0`) when the cache is empty.
#'
#' @examples
#' cvm_cache_info()
#' @family cache
#' @export
cvm_cache_info <- function() {
  cache_migrate_v0_1_to_v0_2()
  schema <- tibble::tibble(
    group         = character(0L),
    dataset       = character(0L),
    file          = character(0L),
    path          = character(0L),
    size_bytes    = integer(0L),
    mtime         = as.POSIXct(character(0L), tz = "UTC"),
    etag          = character(0L),
    last_modified = character(0L)
  )
  attr(schema, "total_size_bytes") <- 0
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
  segments <- strsplit(rel, "/", fixed = TRUE)
  group <- vapply(segments, `[[`, character(1L), 1L)
  dataset <- vapply(
    segments,
    function(s) if (length(s) >= 2L) s[[2L]] else NA_character_,
    character(1L)
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
    group         = group,
    dataset       = dataset,
    file          = file_basename,
    path          = artifacts,
    size_bytes    = size_bytes,
    mtime         = mtime,
    etag          = etag,
    last_modified = last_modified
  )
  out <- out[order(out$group, out$dataset, out$file), , drop = FALSE]
  attr(out, "total_size_bytes") <- cache_current_size_bytes()
  out
}

#' Clear cached files
#'
#' Deletes cached files selectively. `what = "all"` removes the
#' entire cache tree (everything under [cvm_cache_path()]);
#' `what = "raw"` removes only the raw download area
#' (`<cache>/raw/`); `what = "parquet"` removes only the L3 mirror
#' cache (`<cache>/parquet/`). When `group`, `dataset` (and
#' optionally `year`) are supplied, the scope is narrowed to the
#' matching subtree under the chosen area; passing `group` or
#' `dataset` without an explicit `what` defaults to `"raw"` for
#' backwards compatibility.
#'
#' Filter precedence: `what = "all"` wipes everything ignoring the
#' other filters; otherwise the path is composed as
#' `<cache>/<what>/<group>/<dataset>/<year>/`, with each level
#' becoming optional from right to left. `year` requires `dataset`;
#' `dataset` may be supplied without `group` (the group is inferred
#' via the v0.1.0.9000 lookup table). `group` may be supplied alone
#' to wipe a whole group at once.
#'
#' In interactive sessions the user is asked to confirm via
#' [utils::askYesNo()] before deletion. In batch sessions the
#' default (`confirm = interactive()`) evaluates to `FALSE` and
#' deletion proceeds silently — pass `confirm = TRUE` explicitly to
#' force a prompt.
#'
#' @param what One of `"all"`, `"raw"` or `"parquet"`. Default
#'   `"all"`.
#' @param dataset Optional dataset id (e.g. `"dfp"`). Restricts
#'   deletion to the matching
#'   `<cache>/<what>/<group>/<dataset>/` subtree.
#' @param group Optional CKAN group slug (e.g. `"companhias"`).
#'   Restricts deletion to the matching `<cache>/<what>/<group>/`
#'   subtree. When omitted but `dataset` is supplied, the group is
#'   inferred from the dataset lookup.
#' @param year Optional integer year. Requires `dataset` to be
#'   non-`NULL`. Restricts deletion to the matching `year=<YYYY>/`
#'   slot (raw) or `year=<YYYY>/` slot (parquet).
#' @param confirm Logical scalar. When `TRUE`, asks for confirmation
#'   before deleting. Default: [interactive()].
#'
#' @return The number of files deleted, invisibly.
#'
#' @examplesIf interactive()
#' cvm_cache_clear(dataset = "dfp", year = 2024)
#' cvm_cache_clear(group = "companhias", what = "raw")
#' cvm_cache_clear(what = "raw")
#' @family cache
#' @export
cvm_cache_clear <- function(what = "all",
                            dataset = NULL,
                            group = NULL,
                            year = NULL,
                            confirm = interactive()) {
  cache_migrate_v0_1_to_v0_2()
  args <- .validate_cache_clear_args(
    what, dataset, group, year, confirm
  )
  target <- .cache_clear_target(
    cvm_cache_path(), args$what, args$group, args$dataset, args$year
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

# Validate the five arguments of cvm_cache_clear(); returns the
# normalized (what, group, dataset, year, confirm) list. `what` is
# widened to "raw" when a group or dataset filter is supplied without
# an explicit parquet target. `group` is inferred from `dataset` when
# omitted; when both are supplied they must agree.
.validate_cache_clear_args <- function(what, dataset, group, year,
                                       confirm) {
  what <- rlang::arg_match0(what, c("all", "raw", "parquet"))
  if (!is.null(year) && is.null(dataset)) {
    cvmdata_abort(
      c("{.arg year} requires {.arg dataset} to be supplied."),
      class = "cvmdata_error_input"
    )
  }
  .check_dataset_arg(dataset)
  group <- .check_group_arg(group)
  if (!is.null(dataset)) {
    inferred <- tryCatch(
      dataset_group(dataset),
      cvmdata_error_internal = function(e) NULL
    )
    if (is.null(inferred)) {
      cvmdata_abort(
        c(
          "Unknown dataset {.val {dataset}}.",
          "i" = paste(
            "Known datasets in v0.1.0.9000:",
            "{.val {names(.dataset_group_map)}}."
          )
        ),
        class = "cvmdata_error_input"
      )
    }
    if (is.null(group)) {
      group <- inferred
    } else if (!identical(group, inferred)) {
      cvmdata_abort(
        c(
          paste(
            "Dataset {.val {dataset}} belongs to group",
            "{.val {inferred}}, not {.val {group}}."
          )
        ),
        class = "cvmdata_error_input"
      )
    }
  }
  if ((!is.null(group) || !is.null(dataset)) &&
        identical(what, "all")) {
    what <- "raw"
  }
  year <- .check_year_arg(year)
  if (!is.null(year) && identical(what, "parquet")) {
    cvmdata_abort(
      c(
        paste(
          "{.arg year} is not supported with",
          "{.code what = \"parquet\"}."
        ),
        "i" = paste(
          "The L3 parquet cache partitions year under each table",
          "(`<group>/<dataset>/<table>/[report_type=R/]year=Y/`);",
          "pass {.arg dataset} alone to evict the whole dataset, or",
          "{.code what = \"raw\"} for year-level eviction."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  .check_confirm_arg(confirm)
  list(what = what, group = group, dataset = dataset,
       year = year, confirm = confirm)
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

# Group filter: optional character scalar. Accepts any non-empty
# string (forward-compatible with v0.2+ groups that the package does
# not yet ship datasets for); the caller can still wipe an unknown
# group's slot — it simply resolves to a non-existent directory and
# the no-op short-circuit returns 0.
.check_group_arg <- function(group) {
  if (is.null(group)) {
    return(NULL)
  }
  if (!is.character(group) || length(group) != 1L ||
        is.na(group) || !nzchar(group)) {
    cvmdata_abort(
      c("{.arg group} must be a single non-empty string."),
      class = "cvmdata_error_input"
    )
  }
  group
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

# Compose the absolute path the cleanup should target. `year` only
# applies to `what = "raw"` (the .validate step aborts otherwise).
# Tree: <cache>/<what>/<group>/<dataset>/<year>/ — every level is
# optional from the right; `what = "all"` short-circuits to the cache
# root.
.cache_clear_target <- function(cache_root, what, group, dataset, year) {
  if (identical(what, "all")) {
    return(cache_root)
  }
  base <- file.path(cache_root, what)
  if (is.null(group)) {
    return(base)
  }
  base <- file.path(base, group)
  if (is.null(dataset)) {
    return(base)
  }
  base <- file.path(base, dataset)
  if (is.null(year)) {
    return(base)
  }
  file.path(base, as.character(year))
}

# Internal: ensure a directory exists. Used by the HTTP source backend
# to lazily materialise the per-dataset subtree under the cache root.
ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
  invisible(path)
}

# Read and validate `options(cvmdata.cache_max_size_mb)`. Returns the
# limit in bytes. `Inf` is the sentinel for "eviction disabled" — the
# option being `0`, negative, or `Inf` all map to it. Malformed values
# (non-numeric, length != 1, NA) fall back to the default 100 MB so
# that a corrupt user option cannot accidentally unbound the cache.
read_cache_max_size <- function() {
  raw <- getOption("cvmdata.cache_max_size_mb", 100L)
  if (!is.numeric(raw) || length(raw) != 1L || is.na(raw)) {
    return(100 * 1024 * 1024)
  }
  if (raw <= 0 || is.infinite(raw)) {
    return(Inf)
  }
  as.numeric(raw) * 1024 * 1024
}

# Build the list of cache units that the eviction engine considers.
# A "unit" is anchored by an upstream artifact (a file with a sibling
# `*.etag.rds` sidecar). Two layouts are recognised:
#
#   - Yearly (DFP/ITR/FRE): the unit is the year directory
#     `<cache>/raw/<group>/<dataset>/<YYYY>/`, which holds the ZIP,
#     the sidecar, and any CSV(s) extracted via `unzip()`. mtime
#     anchor is the upstream ZIP itself.
#   - Non-partitioned (CAD): the unit is the pair
#     `{anchor, anchor.etag.rds}`. mtime anchor is the artifact.
#
# The `<group>` segment is detected implicitly via the parent-dir
# heuristic: `.cache_unit_key()` looks at the immediate parent's
# basename and only treats it as a year directory when it matches
# `^[0-9]{4}$`. Group slugs (`companhias`, ...) and dataset slugs
# (`cad`, `dfp`, ...) never match that pattern, so the eviction
# engine works unchanged across the v0.1 → v0.1.0.9000 layout shift.
#
# Orphan sidecars (sidecar without artifact) and orphan files
# (artifact without sidecar) are ignored: they do not count toward
# the cache size and are not removed by eviction. Cleaning them up
# is the user's job via `cvm_cache_clear()`.
build_cache_units <- function(raw_root) {
  empty <- list(
    units = list(),
    mtime = .POSIXct(numeric(0L), tz = "UTC"),
    size_bytes = numeric(0L)
  )
  if (!dir.exists(raw_root)) {
    return(empty)
  }
  all_files <- list.files(
    raw_root, recursive = TRUE, full.names = TRUE, no.. = TRUE
  )
  sidecars <- all_files[grepl("\\.etag\\.rds$", all_files)]
  if (!length(sidecars)) {
    return(empty)
  }
  anchors <- sub("\\.etag\\.rds$", "", sidecars)
  ok <- file.exists(anchors)
  anchors <- anchors[ok]
  sidecars <- sidecars[ok]
  if (!length(anchors)) {
    return(empty)
  }
  unit_keys <- vapply(anchors, .cache_unit_key, character(1L))
  unique_keys <- unique(unit_keys)
  units <- vector("list", length(unique_keys))
  mtimes <- .POSIXct(numeric(length(unique_keys)), tz = "UTC")
  sizes <- numeric(length(unique_keys))
  for (i in seq_along(unique_keys)) {
    key <- unique_keys[[i]]
    idx <- which(unit_keys == key)
    mtimes[[i]] <- max(file.mtime(anchors[idx]))
    if (dir.exists(key)) {
      files <- list.files(
        key, recursive = TRUE, full.names = TRUE, no.. = TRUE
      )
    } else {
      files <- c(anchors[[idx[[1L]]]], sidecars[[idx[[1L]]]])
    }
    units[[i]] <- files
    sizes[[i]] <- sum(file.size(files), na.rm = TRUE)
  }
  list(units = units, mtime = mtimes, size_bytes = sizes)
}

# Map an anchor path to the unit key under which `build_cache_units()`
# groups files. For yearly partitionings the key is the year directory
# (parent of the anchor when that parent's basename looks like a
# 4-digit year). For non-partitioned datasets the key is the anchor
# path itself.
.cache_unit_key <- function(anchor) {
  parent <- dirname(anchor)
  if (grepl("^[0-9]{4}$", basename(parent))) {
    parent
  } else {
    anchor
  }
}

# Total bytes counted toward the cache size limit. Sums sizes across
# every unit returned by `build_cache_units()`; orphan files and
# orphan sidecars are excluded by design (see that helper for the
# accounting rules).
cache_current_size_bytes <- function() {
  units <- build_cache_units(file.path(cvm_cache_path(), "raw"))
  sum(units$size_bytes)
}

# Enforce the cache size limit. Triggered after `download_with_etag()`
# writes fresh bytes (see `R/source-cvm-http.R`); when the total
# exceeds 90% of `options(cvmdata.cache_max_size_mb)`, evict units in
# ascending mtime order (oldest first) until at or below 80% of the
# limit, or the candidate list is exhausted. The `protect` argument
# names a path that must not be evicted (set by the trigger to the
# just-written `dest_path`, so a single download larger than the
# limit cannot delete itself). Returns the number of units removed,
# invisibly.
cache_enforce_limit <- function(protect = NULL) {
  limit <- read_cache_max_size()
  if (is.infinite(limit)) {
    return(invisible(0L))
  }
  raw_root <- file.path(cvm_cache_path(), "raw")
  units <- build_cache_units(raw_root)
  if (!length(units$units)) {
    return(invisible(0L))
  }
  total <- sum(units$size_bytes)
  if (total <= 0.9 * limit) {
    return(invisible(0L))
  }
  target <- 0.8 * limit
  protect_norm <- if (is.null(protect)) {
    NULL
  } else {
    normalizePath(protect, winslash = "/", mustWork = FALSE)
  }
  ord <- order(units$mtime)
  removed <- 0L
  freed_bytes <- 0
  for (i in ord) {
    if (total <= target) {
      break
    }
    if (.cache_unit_protects(units$units[[i]], protect_norm)) {
      next
    }
    .cache_evict_unit(units$units[[i]])
    total <- total - units$size_bytes[[i]]
    freed_bytes <- freed_bytes + units$size_bytes[[i]]
    removed <- removed + 1L
  }
  if (removed > 0L) {
    cache_emit_eviction_warning(removed, freed_bytes, limit)
  }
  invisible(removed)
}

# Emit `cvmdata_warn_eviction` after a successful eviction round.
# Defaults are tuned so interactive users see that the cache is being
# managed under them, while batch jobs (CI/ETL) stay silent unless
# explicitly opted in via `options(cvmdata.cache_warn_evictions =
# TRUE)`. The warning carries the number of units removed and the
# bytes freed, plus the active limit so the user can decide whether
# to bump it.
cache_emit_eviction_warning <- function(removed, freed_bytes,
                                        limit_bytes) {
  if (!should_warn_eviction()) {
    return(invisible())
  }
  freed_mb <- round(freed_bytes / 1024 / 1024, 2)
  limit_mb <- round(limit_bytes / 1024 / 1024, 2)
  cvmdata_warn(
    c(
      paste0(
        "Cache eviction removed {removed} unit{?s} ",
        "({freed_mb} MiB) to honour the ",
        "{limit_mb} MiB size limit."
      ),
      "i" = paste(
        "Re-fetching evicted years/datasets will redownload.",
        "Silence with",
        "{.code options(cvmdata.cache_warn_evictions = FALSE)}",
        "or raise the limit via",
        "{.code options(cvmdata.cache_max_size_mb = N)}."
      )
    ),
    class = "cvmdata_warn_eviction"
  )
  invisible()
}

# Read `options(cvmdata.cache_warn_evictions)`. Default is
# `interactive()` (interactive users see the warning; batch jobs do
# not). Malformed values (non-logical, length != 1, NA) fall back to
# the default — never crash a cache operation because of a bad opt.
should_warn_eviction <- function() {
  raw <- getOption("cvmdata.cache_warn_evictions", interactive())
  if (!is.logical(raw) || length(raw) != 1L || is.na(raw)) {
    return(interactive())
  }
  raw
}

# Whether the just-written path lives in this unit. Both sides are
# normalised to forward-slash form so the mixed separators
# `file.path()` and `list.files()` can return on Windows do not
# defeat the comparison.
.cache_unit_protects <- function(unit_files, protect_norm) {
  if (is.null(protect_norm)) {
    return(FALSE)
  }
  normalised <- normalizePath(
    unit_files, winslash = "/", mustWork = FALSE
  )
  protect_norm %in% normalised
}

# Remove every file in a unit and prune the unit's directory if the
# unit was a yearly bundle (i.e., all its files lived inside a single
# directory that is now empty). Non-partitioned units share their
# parent directory with other datasets, so the dir is left alone.
.cache_evict_unit <- function(files) {
  unlink(files, force = TRUE)
  parent_dirs <- unique(dirname(files))
  for (d in parent_dirs) {
    if (dir.exists(d) &&
          !length(list.files(d, all.files = TRUE, no.. = TRUE))) {
      unlink(d, recursive = TRUE, force = TRUE)
    }
  }
  invisible()
}

# Cache layout migration v0.1 -> v0.1.0.9000 -------------------------------
#
# v0.1.0 stored downloads under `<cache>/{raw,parquet}/<dataset>/...`.
# v0.1.0.9000 nests them one level deeper to keep multi-group coverage
# straight: `<cache>/{raw,parquet}/<group>/<dataset>/...`. This helper
# detects a v0.1 layout (any of the v0.1 dataset directories sitting
# directly under `raw/` or `parquet/`) and relocates the subtree under
# the corresponding group slug.
#
# Contract:
#   - Idempotent: a layout that is already v0.1.0.9000 is a no-op.
#   - Transactional pre-flight: if any destination already exists,
#     aborts with `cvmdata_error_internal` listing every conflicting
#     path *before* moving any file. Partial v0.1 caches mixed with
#     fresh v0.1.0.9000 writes therefore fail-fast — the user is
#     instructed to run `cvm_cache_clear("all")` and re-download.
#   - Audit log: every non-empty migration appends an entry to
#     `tools::R_user_dir("cvmdata", "config")/cache_migrate_log.rds`.
#     Each entry carries the timestamp, the cache root, and the list
#     of subtrees moved.
#   - Read-only filesystem: when the cache root exists but is not
#     writeable (e.g. read-only mount), aborts with
#     `cvmdata_error_internal` and no file moved.
#
# Not exported. Called from `source_cvm_http_get()`,
# `source_mirror_duckdb_get()`, `cvm_cache_info()`, and
# `cvm_cache_clear()`; the no-op fast path keeps the steady-state cost
# of those entries to a couple of `file.exists()` calls.
cache_migrate_v0_1_to_v0_2 <- function(cache_root = cvm_cache_path()) {
  empty <- list(moved = character(0L), log_path = NA_character_,
                ts = as.POSIXct(NA_character_, tz = "UTC"))
  if (!.cache_migrate_root_usable(cache_root)) {
    return(invisible(empty))
  }
  planned <- .cache_migrate_plan(cache_root)
  if (!length(planned)) {
    return(invisible(empty))
  }
  .cache_migrate_check_conflicts(planned)
  .cache_migrate_check_writeable(cache_root)
  moved <- .cache_migrate_execute(planned)
  log_path <- cache_migrate_log_path()
  ts <- Sys.time()
  .cache_migrate_log_append(log_path, cache_root, moved, ts)
  invisible(list(moved = moved, log_path = log_path, ts = ts))
}

# True iff `cache_root` is a valid, existing directory the migration
# can examine. Anything else (NULL, NA, vector, non-existent path) is
# a silent no-op — the migration is a side helper of the source layer,
# not an API touchpoint.
.cache_migrate_root_usable <- function(cache_root) {
  is.character(cache_root) && length(cache_root) == 1L &&
    !is.na(cache_root) && nzchar(cache_root) &&
    dir.exists(cache_root)
}

# Transactional pre-flight: scan every planned move for a destination
# that already exists. On conflict, abort *before* moving anything so
# a partial mix of v0.1 and v0.1.0.9000 caches fails fast.
.cache_migrate_check_conflicts <- function(planned) {
  conflicts <- vapply(
    planned, function(p) file.exists(p$dest), logical(1L)
  )
  if (!any(conflicts)) {
    return(invisible())
  }
  cvmdata_abort(
    c(
      paste(
        "Cannot migrate cache layout to v0.1.0.9000:",
        "{sum(conflicts)} destination path{?s} already exist{?s/}."
      ),
      "i" = paste(
        "Conflicting path{?s}:",
        "{.path {vapply(planned[conflicts], `[[`, character(1L), 'dest')}}."
      ),
      "i" = paste(
        "Run {.code cvm_cache_clear(\"all\")} and re-fetch to recover."
      )
    ),
    class = "cvmdata_error_internal"
  )
}

# Abort when the cache root is read-only. Probed by writing then
# removing a temp file (see `.cache_root_writeable()`); this is the
# only portable signal of writability we have on Windows.
.cache_migrate_check_writeable <- function(cache_root) {
  if (.cache_root_writeable(cache_root)) {
    return(invisible())
  }
  cvmdata_abort(
    c(
      "Cache root {.path {cache_root}} is not writeable.",
      "i" = paste(
        "Cannot perform cache layout migration on a read-only mount.",
        "Either grant write permissions or point",
        "{.code cvm_cache_set_path()} at a writeable location."
      )
    ),
    class = "cvmdata_error_internal"
  )
}

# Perform every move; abort on the first failure (pre-flight already
# ruled out same-name conflicts, so the remaining failure modes are
# OS-level: permission, cross-device, ENOENT). Returns the list of
# destination paths that succeeded.
.cache_migrate_execute <- function(planned) {
  moved <- character(0L)
  for (p in planned) {
    ensure_dir(dirname(p$dest))
    ok <- file.rename(p$src, p$dest)
    if (!isTRUE(ok)) {
      cvmdata_abort(
        c(
          paste(
            "Cache layout migration failed while moving",
            "{.path {p$src}} to {.path {p$dest}}."
          ),
          "i" = paste(
            "Run {.code cvm_cache_clear(\"all\")} and re-fetch to recover."
          )
        ),
        class = "cvmdata_error_internal"
      )
    }
    moved <- c(moved, p$dest)
  }
  moved
}

# Build the list of (src, dest) pairs that the migration should attempt
# on `cache_root`. Returns an empty list when nothing matches the v0.1
# layout (the steady-state fast path post-migration).
.cache_migrate_plan <- function(cache_root) {
  out <- list()
  for (layer in c("raw", "parquet")) {
    layer_root <- file.path(cache_root, layer)
    if (!dir.exists(layer_root)) {
      next
    }
    for (dataset in names(.dataset_group_map)) {
      src <- file.path(layer_root, dataset)
      if (!dir.exists(src)) {
        next
      }
      group <- .dataset_group_map[[dataset]]
      dest <- file.path(layer_root, group, dataset)
      out <- c(out, list(list(src = src, dest = dest)))
    }
  }
  out
}

# Probe writeability of an existing cache root without leaving a stray
# file behind. Returns TRUE if a temp file can be created and removed.
.cache_root_writeable <- function(cache_root) {
  probe <- tempfile(tmpdir = cache_root, fileext = ".migrate-probe")
  ok <- tryCatch(
    {
      created <- file.create(probe)
      if (file.exists(probe)) {
        unlink(probe, force = TRUE)
      }
      isTRUE(created)
    },
    warning = function(w) FALSE,
    error = function(e) FALSE
  )
  ok
}

# Resolve the path of the audit log. Lives under
# `tools::R_user_dir("cvmdata", "config")` (separate from the cache
# directory so it survives `cvm_cache_clear("all")`).
cache_migrate_log_path <- function() {
  config_dir <- tools::R_user_dir("cvmdata", which = "config")
  file.path(config_dir, "cache_migrate_log.rds")
}

# Append a single audit entry to the log. Creates the parent directory
# and an empty log on first use; tolerates a corrupt log by starting
# fresh (we would rather lose history than crash a migration over a
# broken sidecar).
.cache_migrate_log_append <- function(log_path, cache_root, moved, ts) {
  ensure_dir(dirname(log_path))
  prior <- list()
  if (file.exists(log_path)) {
    prior <- tryCatch(
      {
        x <- readRDS(log_path)
        if (is.list(x)) x else list()
      },
      error = function(e) list()
    )
  }
  entry <- list(
    timestamp = ts,
    cache_root = cache_root,
    moved = moved,
    package_version = as.character(utils::packageVersion("cvmdata"))
  )
  saveRDS(c(prior, list(entry)), log_path)
  invisible(log_path)
}
