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
# The future R/source-mirror-duckdb.R consumer reconstructs the
# partition tree client-side from these encoded names and feeds the
# resulting URL list to arrow::open_dataset().
#
# Requires `gh` CLI on PATH and an authenticated token (built-in on
# GitHub Actions via GITHUB_TOKEN; locally via `gh auth login`).
#
# Usage:
#   Rscript inst/etl/03-publish.R --dataset cad

source("inst/etl/00-config.R")

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

message(sprintf("[03-publish] uploading %d asset(s)", length(parquets)))
stage_dir <- tempfile("cvmdata-mirror-stage-")
dir.create(stage_dir)
on.exit(unlink(stage_dir, recursive = TRUE), add = TRUE)

for (f in parquets) {
  rel <- substring(f, nchar(dataset_dir) + 2L)
  asset_name <- gsub("[/\\\\]", "__", rel)
  staged <- file.path(stage_dir, asset_name)
  file.copy(f, staged, overwrite = TRUE)
  message("  ", asset_name)
  status <- system2("gh", c(
    "release", "upload", tag,
    shQuote(staged),
    "--repo", mirror_repo,
    "--clobber"
  ))
  if (status != 0L) {
    stop(sprintf("upload failed for %s", asset_name), call. = FALSE)
  }
}
message(sprintf("[03-publish] release %s ready.", tag))
