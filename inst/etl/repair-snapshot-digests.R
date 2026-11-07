# Repair — rebuild the `files` map of every dated snapshot sidecar from
# the bytes the snapshot points to, and write `snapshot_files` into the
# `-latest` sidecar (one-off after the fix of 2026-11-07; see
# `snapshot_pointer_digests()` in util-snapshot.R for the defect).
#
# For each dataset: reads the `-latest` sidecar, then the sidecar of
# every date in its `snapshots`; for each partition of each dated
# sidecar, downloads the asset from the release its `releases` map
# names (once per distinct (release, partition): the stored bytes are
# ~850 MB over the nine datasets on 2026-11-07) and writes the sha256
# and size it has. A dated sidecar whose map changed is uploaded back
# to its release; the `-latest` sidecar gets `snapshot_files` (the map
# of the snapshot it currently carries) so the next publish can carry
# it over. The `-latest` `files` map stays: it describes the assets of
# `-latest`, rewritten whole every run.
#
# Usage:
#   Rscript inst/etl/repair-snapshot-digests.R --group companhias \
#     --dataset dfp [--dry-run]
#
# `--dry-run` downloads and measures, writes the repaired sidecars under
# <workspace>/out/repair/<group>/<dataset>/ and uploads nothing. Setting
# `options(cvmdata.etl_testing = TRUE)` loads the helpers and skips the
# entry point.

for (sibling in c("00-config.R", "util-release.R", "util-snapshot.R")) {
  marker <- c(
    "00-config.R" = "mirror_tag_latest",
    "util-release.R" = "download_public_asset",
    "util-snapshot.R" = "snapshot_repair_files"
  )[[sibling]]
  if (!exists(marker, mode = "function")) {
    source(file.path("inst", "etl", sibling))
  }
}

stopifnot(requireNamespace("jsonlite", quietly = TRUE))
stopifnot(requireNamespace("digest", quietly = TRUE))

# Reads the sidecar of a release, or stops.
repair_read_sidecar <- function(tag, dir) {
  target <- file.path(dir, tag)
  dir.create(target, recursive = TRUE, showWarnings = FALSE)
  path <- download_public_asset(tag, "__source_hash.json", target)
  if (is.null(path)) {
    stop(sprintf("release %s has no __source_hash.json", tag), call. = FALSE)
  }
  jsonlite::read_json(path)
}

# A lookup of list(sha256, size) by (tag, rel) that downloads each
# distinct asset once into `dir`.
repair_digest_lookup <- function(dir) {
  cache <- new.env(parent = emptyenv())
  function(tag, rel) {
    key <- paste(tag, rel, sep = "|")
    hit <- cache[[key]]
    if (!is.null(hit)) {
      return(hit)
    }
    target <- file.path(dir, tag)
    dir.create(target, recursive = TRUE, showWarnings = FALSE)
    path <- download_public_asset(tag, public_asset_name(rel), target)
    if (is.null(path)) {
      stop(
        sprintf("asset %s of %s could not be downloaded", rel, tag),
        call. = FALSE
      )
    }
    value <- list(
      sha256 = digest::digest(file = path, algo = "sha256"),
      size = file.size(path)
    )
    unlink(path)
    cache[[key]] <- value
    value
  }
}

# `null = "null"`: a sidecar read with `read_json()` holds the JSON
# nulls of `skips` (a table without `report_type`) as NULL, and
# `write_json()` writes NULL as `{}` unless told otherwise. The first
# repair of 2026-11-07 wrote `"report_type": {}` into the fre sidecars
# and every client failed on them ("arguments imply differing number
# of rows: 2, 0" in the skips parser) until the sidecars were written
# again. 03-publish.R is not exposed: its `skips` is a data.frame with
# NA, which `na = "null"` covers.
repair_write_sidecar <- function(sidecar, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(
    sidecar,
    path,
    auto_unbox = TRUE,
    pretty = TRUE,
    na = "null",
    null = "null"
  )
  path
}

repair_main <- function(group, dataset, dry_run) {
  latest_tag <- mirror_tag_latest(group, dataset)
  work <- file.path(mirror_workspace(), "repair", group, dataset)
  out_dir <- file.path(mirror_workspace(), "out", "repair", group, dataset)
  dir.create(work, recursive = TRUE, showWarnings = FALSE)
  latest <- repair_read_sidecar(latest_tag, work)
  dates <- as.character(unlist(latest$snapshots %||% list()))
  if (!length(dates)) {
    message(sprintf(
      "[repair] %s: no dated snapshot; nothing to repair",
      dataset
    ))
    return(invisible(NULL))
  }
  lookup <- repair_digest_lookup(file.path(work, "assets"))
  uploads <- character()
  for (date in dates) {
    tag <- mirror_tag_snapshot(group, dataset, as.Date(date))
    sidecar <- repair_read_sidecar(tag, work)
    skips <- snapshot_normalise_skips(sidecar)
    repaired <- snapshot_repair_files(skips$sidecar, lookup)
    message(sprintf(
      "[repair] %s %s: %d of %d partition digest(s) were wrong%s",
      dataset,
      date,
      length(repaired$fixed),
      length(sidecar$files %||% list()),
      if (skips$changed) "; skips had `{}` for null" else ""
    ))
    if (length(repaired$fixed) || skips$changed) {
      path <- repair_write_sidecar(
        repaired$sidecar,
        file.path(out_dir, tag, "__source_hash.json")
      )
      uploads[[tag]] <- path
    }
    if (identical(date, latest$snapshot)) {
      latest$snapshot_files <- repaired$sidecar$files
    }
  }
  if (is.null(latest$snapshot_files)) {
    stop(
      sprintf(
        "the snapshot %s of -latest is not among its dates",
        latest$snapshot %||% "?"
      ),
      call. = FALSE
    )
  }
  latest <- snapshot_normalise_skips(latest)$sidecar
  uploads[[latest_tag]] <- repair_write_sidecar(
    latest,
    file.path(out_dir, latest_tag, "__source_hash.json")
  )
  message(sprintf(
    "[repair] %s: %d sidecar(s) to upload (%s)",
    dataset,
    length(uploads),
    paste(names(uploads), collapse = ", ")
  ))
  if (dry_run) {
    message(sprintf("  dry run: written under %s; nothing uploaded", out_dir))
    return(invisible(uploads))
  }
  for (tag in names(uploads)) {
    message("  uploading __source_hash.json to ", tag)
    upload_release_asset(tag, uploads[[tag]])
  }
  invisible(uploads)
}

repair_parse_args <- function(args) {
  opts <- list(group = NULL, dataset = NULL, dry_run = FALSE)
  i <- 1L
  while (i <= length(args)) {
    a <- args[i]
    if (a == "--group") {
      opts$group <- args[i + 1L]
      i <- i + 2L
    } else if (a == "--dataset") {
      opts$dataset <- args[i + 1L]
      i <- i + 2L
    } else if (a == "--dry-run") {
      opts$dry_run <- TRUE
      i <- i + 1L
    } else {
      i <- i + 1L
    }
  }
  if (is.null(opts$group) || is.null(opts$dataset)) {
    stop("--group and --dataset are required", call. = FALSE)
  }
  if (!mirror_pair_valid(opts$group, opts$dataset)) {
    stop(sprintf("unknown pair %s/%s", opts$group, opts$dataset), call. = FALSE)
  }
  opts
}

if (!isTRUE(getOption("cvmdata.etl_testing"))) {
  if (!nzchar(Sys.which("gh"))) {
    stop("`gh` CLI not found on PATH", call. = FALSE)
  }
  opts <- repair_parse_args(commandArgs(trailingOnly = TRUE))
  repair_main(opts$group, opts$dataset, opts$dry_run)
}
