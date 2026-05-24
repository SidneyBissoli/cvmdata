# Stage 3 — Publish parquet outputs to GitHub Releases.
#
# Uploads every parquet under <workspace>/out/parquet/<dataset>/ as an
# asset of the moving release "mirror-<dataset>-latest". Encodes the
# Hive-style partition path in the asset name via "__" separators,
# because GitHub Releases asset names are flat (no slashes allowed).
#
# Example: parquet/dfp/bpa/report_type=ind/year=2024/part-0.parquet
#       -> asset "bpa__report_type=ind__year=2024__part-0.parquet"
#       -> URL https://github.com/<repo>/releases/download/<tag>/<asset>
#
# Note: `gh release upload path#label` makes `label` only a *display*
# string on the release UI — the asset name (and download URL) always
# comes from the file basename. Since every parquet on disk is named
# "part-0.parquet" (Hive-style layout), we stage a renamed copy in a
# temp dir before uploading, so each asset lands with its encoded
# partition name and they don't collide on basename.
#
# Change detection: before republishing, the script computes the SHA-256
# of the CVM META files (via util-hash.R) and compares it against the
# `__source_hash.json` asset of the previous release. If they match, the
# publish is skipped (exit 0, log line). Otherwise the new hash is
# written into the stage dir as `__source_hash.json` and uploaded
# alongside the parquets.
#
# The future R/source-mirror-duckdb.R consumer reconstructs the
# partition tree client-side from the encoded names and feeds the
# resulting URL list to arrow::open_dataset().
#
# Requires `gh` CLI on PATH and an authenticated token (built-in on
# GitHub Actions via GITHUB_TOKEN; locally via `gh auth login`).
#
# Usage:
#   Rscript inst/etl/03-publish.R --dataset cad

source("inst/etl/00-config.R")
source("inst/etl/util-hash.R")

args <- commandArgs(trailingOnly = TRUE)
dataset <- NULL
i <- 1L
while (i <= length(args)) {
  if (args[i] == "--dataset") {
    dataset <- args[i + 1L]
    i <- i + 2L
    next
  }
  i <- i + 1L
}
if (is.null(dataset)) {
  stop("--dataset is required", call. = FALSE)
}
if (!dataset %in% mirror_datasets_v0_1) {
  stop(sprintf("dataset '%s' not in mirror_datasets_v0_1", dataset),
       call. = FALSE)
}

gh_bin <- Sys.which("gh")
if (!nzchar(gh_bin)) {
  stop("`gh` CLI not found on PATH", call. = FALSE)
}

workspace <- mirror_workspace()
dataset_dir <- file.path(workspace, "out", "parquet", dataset)
if (!dir.exists(dataset_dir)) {
  stop(sprintf("no parquet output for dataset '%s' (expected at %s)",
               dataset, dataset_dir),
       call. = FALSE)
}

parquets <- list.files(
  dataset_dir, pattern = "\\.parquet$",
  recursive = TRUE, full.names = TRUE
)
if (!length(parquets)) {
  stop(sprintf("no parquet files under %s", dataset_dir),
       call. = FALSE)
}

tag <- mirror_tag_latest(dataset)

# Change detection ------------------------------------------------------
# Compute current META hash and compare against the prior release asset.
# Skip publish when nothing upstream has changed.

short_hash <- function(h) {
  if (is.na(h)) "<no-meta>" else substr(h, 1L, 12L)
}

message("[03-publish] computing source META hash")
source_hash <- compute_source_hash(dataset)
message(sprintf(
  "[03-publish] dataset=%s components=%d sha256=%s",
  dataset, length(source_hash$components),
  short_hash(source_hash$hash)
))

prev_hash_path <- tempfile(fileext = ".json")
download_dir <- dirname(prev_hash_path)
download_status <- suppressWarnings(system2(
  "gh", c(
    "release", "download", tag,
    "--repo", mirror_repo,
    "--pattern", "__source_hash.json",
    "--dir", shQuote(download_dir),
    "--clobber"
  ),
  stdout = NULL, stderr = NULL
))
prev_hash_file <- file.path(download_dir, "__source_hash.json")
unlink(prev_hash_path)

if (download_status == 0L && file.exists(prev_hash_file)) {
  prev <- tryCatch(
    jsonlite::read_json(prev_hash_file),
    error = function(e) NULL
  )
  if (!is.null(prev) && identical(prev$hash, source_hash$hash) &&
        !is.na(source_hash$hash)) {
    message(sprintf(
      "[03-publish] META unchanged (sha256=%s..); skipping publish",
      short_hash(source_hash$hash)
    ))
    unlink(prev_hash_file)
    quit(status = 0L)
  }
  message(sprintf(
    "[03-publish] META changed (prev=%s.., cur=%s..); republishing",
    short_hash(prev$hash %||% NA_character_),
    short_hash(source_hash$hash)
  ))
  unlink(prev_hash_file)
} else {
  message("[03-publish] no previous __source_hash.json; publishing fresh")
}

# Publish ---------------------------------------------------------------

title <- sprintf("Mirror: %s (latest)", dataset)
notes <- sprintf(paste0(
  "Auto-generated parquet mirror snapshot for dataset '%s'.\n",
  "Updated: %s\n\n",
  "See https://sidneybissoli.github.io/cvmdata/articles/",
  "cache-and-mirror.html for client usage."
), dataset, format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC"))

# Recreate the release on every run so assets always reflect the
# current parquet tree. `gh release delete` is idempotent under
# --yes; missing release -> exit 1, which we swallow.
suppressWarnings(
  system2("gh", c(
    "release", "delete", tag,
    "--repo", mirror_repo,
    "--yes",
    "--cleanup-tag"
  ), stdout = NULL, stderr = NULL)
)

message(sprintf("[03-publish] creating release %s", tag))
notes_file <- tempfile(fileext = ".md")
writeLines(notes, notes_file)
# system2 on Windows does not auto-quote vector args, so any string
# with spaces, parens or other shell metacharacters must be shQuote()d
# explicitly. Otherwise gh re-parses them as positional args (e.g. a
# title "Mirror: cad (latest)" becomes 3 file-pattern args).
status <- system2("gh", c(
  "release", "create", tag,
  "--repo", mirror_repo,
  "--title", shQuote(title),
  "--notes-file", shQuote(notes_file)
))
if (status != 0L) {
  stop("gh release create failed", call. = FALSE)
}

stage_dir <- tempfile("cvmdata-mirror-stage-")
dir.create(stage_dir)
on.exit(unlink(stage_dir, recursive = TRUE), add = TRUE)

# Drop the hash JSON alongside the parquets so it ships as a regular
# release asset. The consumer can fetch it via the same URL pattern.
hash_asset <- file.path(stage_dir, "__source_hash.json")
jsonlite::write_json(source_hash, hash_asset, auto_unbox = TRUE, pretty = TRUE)

assets <- c(hash_asset, character(length(parquets)))
for (k in seq_along(parquets)) {
  rel <- substring(parquets[k], nchar(dataset_dir) + 2L)
  asset_name <- gsub("[/\\\\]", "__", rel)
  staged <- file.path(stage_dir, asset_name)
  file.copy(parquets[k], staged, overwrite = TRUE)
  assets[k + 1L] <- staged
}

message(sprintf("[03-publish] uploading %d asset(s)", length(assets)))
for (asset in assets) {
  message("  ", basename(asset))
  status <- system2("gh", c(
    "release", "upload", tag,
    shQuote(asset),
    "--repo", mirror_repo,
    "--clobber"
  ))
  if (status != 0L) {
    stop(sprintf("upload failed for %s", basename(asset)), call. = FALSE)
  }
}
message(sprintf("[03-publish] release %s ready.", tag))
