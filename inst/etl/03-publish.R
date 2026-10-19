# Stage 3 — Publish parquet outputs to GitHub Releases.
#
# Uploads every parquet under
# <workspace>/out/parquet/<group>/<dataset>/ as an asset of the moving
# release "mirror-<group>-<dataset>-latest" (the `<group>` segment was
# introduced in Sessao 08 of v0.1.0.9000). Encodes the Hive-style
# partition path in the asset name via "__" separators, because GitHub
# Releases asset names are flat (no slashes allowed).
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
# of the CVM META files and of the content of every parquet (via
# util-hash.R) and compares it against the `__source_hash.json` asset of
# the previous release. If they match, the publish is skipped (exit 0,
# log line). Otherwise the new hash is written into the stage dir as
# `__source_hash.json` and uploaded alongside the parquets.
#
# After the upload the release is forced out of draft and checked
# without credentials: on 2026-10-19 the vlmo release had been a draft
# since June, so it answered 404 to every user while the job was green.
#
# The future R/source-mirror-duckdb.R consumer reconstructs the
# partition tree client-side from the encoded names and feeds the
# resulting URL list to arrow::open_dataset().
#
# Requires `gh` CLI on PATH and an authenticated token (built-in on
# GitHub Actions via GITHUB_TOKEN; locally via `gh auth login`).
#
# Usage:
#   Rscript inst/etl/03-publish.R --group companhias --dataset cad

source("inst/etl/00-config.R")
source("inst/etl/util-hash.R")

args <- commandArgs(trailingOnly = TRUE)
group <- NULL
dataset <- NULL
i <- 1L
while (i <= length(args)) {
  if (args[i] == "--group") {
    group <- args[i + 1L]
    i <- i + 2L
    next
  }
  if (args[i] == "--dataset") {
    dataset <- args[i + 1L]
    i <- i + 2L
    next
  }
  i <- i + 1L
}
if (is.null(group)) {
  stop("--group is required", call. = FALSE)
}
if (is.null(dataset)) {
  stop("--dataset is required", call. = FALSE)
}
if (!mirror_pair_valid(group, dataset)) {
  stop(
    sprintf("(%s, %s) not in mirror_datasets_v0_1", group, dataset),
    call. = FALSE
  )
}

gh_bin <- Sys.which("gh")
if (!nzchar(gh_bin)) {
  stop("`gh` CLI not found on PATH", call. = FALSE)
}

workspace <- mirror_workspace()
dataset_dir <- file.path(workspace, "out", "parquet", group, dataset)
if (!dir.exists(dataset_dir)) {
  stop(
    sprintf(
      "no parquet output for (%s, %s) (expected at %s)",
      group,
      dataset,
      dataset_dir
    ),
    call. = FALSE
  )
}

parquets <- list.files(
  dataset_dir,
  pattern = "\\.parquet$",
  recursive = TRUE,
  full.names = TRUE
)
if (!length(parquets)) {
  stop(sprintf("no parquet files under %s", dataset_dir), call. = FALSE)
}

tag <- mirror_tag_latest(group, dataset)

# Change detection ------------------------------------------------------
# Compute the current hash (META + parquet content) and compare against
# the prior release asset. Skip publish when nothing would change.

short_hash <- function(h) {
  if (is.na(h)) "<none>" else substr(h, 1L, 12L)
}

# HTTP status of the release as an anonymous user sees it (200 = public;
# 404 = missing or draft).
release_public_status <- function(tag) {
  url <- sprintf(
    "https://api.github.com/repos/%s/releases/tags/%s",
    mirror_repo,
    tag
  )
  httr2::request(url) |>
    httr2::req_user_agent("cvmdata-etl") |>
    httr2::req_error(is_error = function(resp) FALSE) |>
    httr2::req_retry(max_tries = 3L) |>
    httr2::req_perform() |>
    httr2::resp_status()
}

message("[03-publish] computing source hash (META + parquet content)")
source_hash <- compute_source_hash(dataset, parquets, dataset_dir)
message(sprintf(
  "[03-publish] group=%s dataset=%s meta=%d parquets=%d sha256=%s",
  group,
  dataset,
  length(source_hash$components),
  length(source_hash$data),
  short_hash(source_hash$hash)
))

prev_hash_path <- tempfile(fileext = ".json")
download_dir <- dirname(prev_hash_path)
download_status <- suppressWarnings(system2(
  "gh",
  c(
    "release",
    "download",
    tag,
    "--repo",
    mirror_repo,
    "--pattern",
    "__source_hash.json",
    "--dir",
    shQuote(download_dir),
    "--clobber"
  ),
  stdout = NULL,
  stderr = NULL
))
prev_hash_file <- file.path(download_dir, "__source_hash.json")
unlink(prev_hash_path)

if (download_status == 0L && file.exists(prev_hash_file)) {
  prev <- tryCatch(
    jsonlite::read_json(prev_hash_file),
    error = function(e) NULL
  )
  if (
    !is.null(prev) &&
      identical(prev$hash, source_hash$hash) &&
      !is.na(source_hash$hash) &&
      release_public_status(tag) == 200L
  ) {
    message(sprintf(
      "[03-publish] content unchanged (sha256=%s..); skipping publish",
      short_hash(source_hash$hash)
    ))
    unlink(prev_hash_file)
    quit(status = 0L)
  }
  message(sprintf(
    "[03-publish] content changed (prev=%s.., cur=%s..); republishing",
    short_hash(prev$hash %||% NA_character_),
    short_hash(source_hash$hash)
  ))
  unlink(prev_hash_file)
} else {
  message("[03-publish] no previous __source_hash.json; publishing fresh")
}

# Publish ---------------------------------------------------------------

title <- sprintf("Mirror: %s/%s (latest)", group, dataset)
notes <- sprintf(
  paste0(
    "Auto-generated parquet mirror snapshot for group '%s', dataset '%s'.\n",
    "Updated: %s\n\n",
    "See https://sidneybissoli.github.io/cvmdata/articles/",
    "cache-and-mirror.html for client usage."
  ),
  group,
  dataset,
  format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC")
)

# Update the release in place: overwrite the assets, then remove the
# ones the new tree no longer has. Until 2026-10-19 the release was
# deleted and recreated, which left the mirror empty for the length of
# the upload (up to ~15 min) and, on 19/10, failed for fre and itr: the
# delete did not happen, its error was discarded, and the create hit
# "tag_name already exists" while the June release stayed live.
notes_file <- tempfile(fileext = ".md")
writeLines(notes, notes_file)
# system2 on Windows does not auto-quote vector args, so any string
# with spaces, parens or other shell metacharacters must be shQuote()d
# explicitly. Otherwise gh re-parses them as positional args (e.g. a
# title "Mirror: cad (latest)" becomes 3 file-pattern args).
release_exists <- system2(
  "gh",
  c("release", "view", tag, "--repo", mirror_repo, "--json", "tagName"),
  stdout = NULL,
  stderr = NULL
) ==
  0L
verb <- if (release_exists) "edit" else "create"
message(sprintf("[03-publish] %s release %s", verb, tag))
status <- system2(
  "gh",
  c(
    "release",
    verb,
    tag,
    "--repo",
    mirror_repo,
    "--title",
    shQuote(title),
    "--notes-file",
    shQuote(notes_file)
  )
)
if (status != 0L) {
  stop(sprintf("gh release %s failed", verb), call. = FALSE)
}

stage_dir <- tempfile("cvmdata-mirror-stage-")
dir.create(stage_dir)
on.exit(unlink(stage_dir, recursive = TRUE), add = TRUE)

# Drop the hash JSON alongside the parquets so it ships as a regular
# release asset. The consumer can fetch it via the same URL pattern.
# It goes LAST: the client keys its parquet cache on this hash, so a
# client reading mid-upload must still see the old hash.
hash_asset <- file.path(stage_dir, "__source_hash.json")
jsonlite::write_json(source_hash, hash_asset, auto_unbox = TRUE, pretty = TRUE)

assets <- character(length(parquets))
for (k in seq_along(parquets)) {
  rel <- substring(parquets[k], nchar(dataset_dir) + 2L)
  asset_name <- gsub("[/\\\\]", "__", rel)
  staged <- file.path(stage_dir, asset_name)
  file.copy(parquets[k], staged, overwrite = TRUE)
  assets[k] <- staged
}
assets <- c(assets, hash_asset)

message(sprintf("[03-publish] uploading %d asset(s)", length(assets)))
for (asset in assets) {
  message("  ", basename(asset))
  status <- system2(
    "gh",
    c(
      "release",
      "upload",
      tag,
      shQuote(asset),
      "--repo",
      mirror_repo,
      "--clobber"
    )
  )
  if (status != 0L) {
    stop(sprintf("upload failed for %s", basename(asset)), call. = FALSE)
  }
}

# Remove the assets of the previous tree that the new one does not have
# (a partition that vanished upstream). Done after the upload, so the
# release is never missing a partition that still exists.
current <- system2(
  "gh",
  c(
    "release",
    "view",
    tag,
    "--repo",
    mirror_repo,
    "--json",
    "assets",
    "--jq",
    shQuote(".assets[].name")
  ),
  stdout = TRUE
)
if (!is.null(attr(current, "status"))) {
  stop("gh release view failed while listing assets", call. = FALSE)
}
# GitHub stores "year=2024" as "year.2024" (see parse_mirror_asset_name()),
# so compare in its spelling; comparing the local names would mark every
# asset stale and delete the release just uploaded.
stale <- setdiff(current, gsub("=", ".", basename(assets), fixed = TRUE))
if (length(stale) == length(current) && length(current) > 0L) {
  stop(
    "every asset of the release looks stale; refusing to delete them",
    call. = FALSE
  )
}
for (name in stale) {
  message("  removing stale asset ", name)
  status <- system2(
    "gh",
    c(
      "release",
      "delete-asset",
      tag,
      shQuote(name),
      "--repo",
      mirror_repo,
      "--yes"
    )
  )
  if (status != 0L) {
    stop(sprintf("delete-asset failed for %s", name), call. = FALSE)
  }
}

# A draft release answers 404 to anyone without push access, which is
# every user of source = "mirror". Publish it explicitly, then prove it
# from the outside with an anonymous request.
status <- system2(
  "gh",
  c("release", "edit", tag, "--repo", mirror_repo, "--draft=false")
)
if (status != 0L) {
  stop("gh release edit --draft=false failed", call. = FALSE)
}
public_status <- release_public_status(tag)
if (public_status != 200L) {
  stop(
    sprintf("release %s answers %d without credentials", tag, public_status),
    call. = FALSE
  )
}
message(sprintf("[03-publish] release %s ready and public.", tag))
