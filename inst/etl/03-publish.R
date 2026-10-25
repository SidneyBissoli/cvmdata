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
# History of superseded filings (since 2026-10, Part 3 of the versions
# work): for every partition whose content hash moved, the parquet of
# the previous release is downloaded and compared with the new one
# filing by filing (util-history.R). The rows of the filings the new
# file replaces or drops are appended to the history asset of that
# partition, `<table>__report_type=R__year=Y__history.parquet`, which
# accumulates across runs and is never deleted as stale. The `-latest`
# parquets are untouched, and clients ignore the history assets
# (`parse_mirror_asset_name()` rejects the name). The JSON gains a
# `history` map ({partition: content sha256}) that the next run uses to
# know which history assets exist; the `hash` field keeps its meaning.
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
#   Rscript inst/etl/03-publish.R --group companhias --dataset dfp --dry-run
#
# `--dry-run` computes the hash and the history against the live release
# and lists what would be uploaded, without touching the release (local
# smoke test after 01/02 with `--year`).

source("inst/etl/00-config.R")
source("inst/etl/util-hash.R")
source("inst/etl/util-history.R")

args <- commandArgs(trailingOnly = TRUE)
group <- NULL
dataset <- NULL
dry_run <- FALSE
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
  if (args[i] == "--dry-run") {
    dry_run <- TRUE
    i <- i + 1L
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

# Asset name of a partition path, as staged ("=" kept) or as GitHub
# serves it ("=" replaced by ".", see parse_mirror_asset_name()).
asset_name_of <- function(rel) {
  gsub("[/\\\\]", "__", rel)
}
public_asset_name <- function(rel) {
  gsub("=", ".", asset_name_of(rel), fixed = TRUE)
}

# Downloads one asset of the release into `dir` and returns its path, or
# NULL when gh could not fetch it (missing asset or a failure that three
# attempts did not clear; gh does not tell the two apart).
download_release_asset <- function(tag, name, dir, attempts = 3L) {
  for (attempt in seq_len(attempts)) {
    status <- suppressWarnings(system2(
      "gh",
      c(
        "release",
        "download",
        tag,
        "--repo",
        mirror_repo,
        "--pattern",
        name,
        "--dir",
        shQuote(dir),
        "--clobber"
      ),
      stdout = NULL,
      stderr = NULL
    ))
    path <- file.path(dir, name)
    if (status == 0L && file.exists(path)) {
      return(path)
    }
    if (attempt < attempts) {
      Sys.sleep(5 * attempt)
    }
  }
  NULL
}

download_dir <- tempfile("cvmdata-mirror-prev-")
dir.create(download_dir)
on.exit(unlink(download_dir, recursive = TRUE), add = TRUE)
prev_hash_file <- download_release_asset(
  tag,
  "__source_hash.json",
  download_dir
)
prev <- NULL
if (!is.null(prev_hash_file)) {
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
    quit(status = 0L)
  }
  message(sprintf(
    "[03-publish] content changed (prev=%s.., cur=%s..); republishing",
    short_hash(prev$hash %||% NA_character_),
    short_hash(source_hash$hash)
  ))
} else {
  message("[03-publish] no previous __source_hash.json; publishing fresh")
}

# History of superseded filings -----------------------------------------
# For every partition whose content moved, fetch the parquet of the
# previous release and keep the rows of the filings the new one replaces
# or drops. Tables that keep every filing (submissao, cad, ...) lose
# nothing on republish and are skipped. A listed asset that cannot be
# downloaded stops the run: publishing over it would lose history.

history_dir <- file.path(workspace, "out", "history", group, dataset)

# Returns list(map = {history partition: content sha256} after this run,
# files = local history parquets written now).
build_history <- function(prev, source_hash) {
  map <- if (is.null(prev)) list() else prev$history %||% list()
  files <- character()
  if (is.null(prev)) {
    return(list(map = map, files = files))
  }
  changed <- Filter(
    function(rel) {
      !is.null(prev$data[[rel]]) &&
        !identical(prev$data[[rel]], source_hash$data[[rel]])
    },
    names(source_hash$data)
  )
  message(sprintf(
    "[03-publish] %d partition(s) changed since the previous release",
    length(changed)
  ))
  for (rel in changed) {
    versioning <- mirror_table_versioning(
      dataset,
      mirror_partition_table(rel)
    )
    if (!versioning$versioned) {
      next
    }
    old_path <- download_release_asset(
      tag,
      public_asset_name(rel),
      download_dir
    )
    if (is.null(old_path)) {
      stop(
        sprintf("previous parquet of %s is listed but not downloadable", rel),
        call. = FALSE
      )
    }
    old <- arrow::read_parquet(old_path)
    new <- arrow::read_parquet(file.path(dataset_dir, rel))
    keys <- mirror_filing_keys(new, versioning$keys)
    if (is.null(keys)) {
      message("  ", rel, ": no filing keys; no history kept")
      next
    }
    diff <- mirror_superseded_rows(old, new, keys, source_hash$computed_at)
    if (length(diff$columns_added) || length(diff$columns_dropped)) {
      message(sprintf(
        "  %s: columns added [%s], dropped [%s]; compared on the rest",
        rel,
        paste(diff$columns_added, collapse = ", "),
        paste(diff$columns_dropped, collapse = ", ")
      ))
    }
    if (!nrow(diff$rows)) {
      next
    }
    hist_rel <- mirror_history_rel(rel)
    previous <- NULL
    if (!is.null(map[[hist_rel]])) {
      prev_path <- download_release_asset(
        tag,
        public_asset_name(hist_rel),
        download_dir
      )
      if (is.null(prev_path)) {
        stop(
          sprintf("history of %s is listed but not downloadable", rel),
          call. = FALSE
        )
      }
      previous <- arrow::read_parquet(prev_path)
    }
    out <- file.path(history_dir, hist_rel)
    dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
    arrow::write_parquet(
      mirror_append_history(previous, diff$rows),
      out,
      compression = "snappy"
    )
    map[[hist_rel]] <- mirror_hash_parquet(out)
    files <- c(files, out)
    message(sprintf(
      "  %s: %d filing(s) replaced, %d removed -> %d row(s) to history",
      rel,
      diff$n_replaced,
      diff$n_removed,
      nrow(diff$rows)
    ))
  }
  list(map = map, files = files)
}

history <- build_history(prev, source_hash)
source_hash$history <- history$map
message(sprintf(
  "[03-publish] history: %d asset(s) in the release, %d written now",
  length(history$map),
  length(history$files)
))

# Skip manifest ---------------------------------------------------------
# Stage 02 records every (table, year, report_type) it produced no
# parquet for, with the reason: "empty" (the CVM publishes the CSV with
# the header only) or "absent" (the CSV is not in the yearly ZIP). It
# travels inside `__source_hash.json`, which clients already fetch, so
# the package can say why a partition is missing instead of guessing
# (fre/mercado_estrangeiro 2026: CSV absent from the CVM's ZIP although
# the dictionary still lists it, measured 2026-10-25). Not a separate
# asset: parse_mirror_asset_name() aborts on any asset other than the
# parquets and this sidecar, so a new asset would break every installed
# client. The hash excludes the manifest: a skip is derived from the
# data, not data.
read_skip_manifest <- function(path) {
  empty <- data.frame(
    table = character(0L),
    year = integer(0L),
    report_type = character(0L),
    reason = character(0L),
    stringsAsFactors = FALSE
  )
  if (!file.exists(path)) {
    return(empty)
  }
  manifest <- tryCatch(
    jsonlite::read_json(path, simplifyVector = TRUE),
    error = function(e) NULL
  )
  if (!is.data.frame(manifest) || !nrow(manifest)) {
    return(empty)
  }
  data.frame(
    table = as.character(manifest$table),
    year = as.integer(manifest$year),
    report_type = as.character(manifest$report_type),
    reason = as.character(manifest$reason),
    stringsAsFactors = FALSE
  )
}
source_hash$skips <- read_skip_manifest(
  file.path(workspace, "out", "skip", sprintf("%s.json", dataset))
)
message(sprintf(
  "[03-publish] skip manifest: %d tuple(s) (%d empty, %d absent)",
  nrow(source_hash$skips),
  sum(source_hash$skips$reason == "empty"),
  sum(source_hash$skips$reason == "absent")
))

if (dry_run) {
  message("[03-publish] dry run: would upload")
  for (p in parquets) {
    message("  ", asset_name_of(substring(p, nchar(dataset_dir) + 2L)))
  }
  for (p in history$files) {
    message("  ", asset_name_of(substring(p, nchar(history_dir) + 2L)))
  }
  message(sprintf(
    "  __source_hash.json (%d skip tuple(s))",
    nrow(source_hash$skips)
  ))
  quit(status = 0L)
}

# Publish ---------------------------------------------------------------

title <- sprintf("Mirror: %s/%s (latest)", group, dataset)
# The notes carry the data licence: the CVM publishes these datasets
# under the ODbL v1.0 and the mirror is a derivative database, so the
# notice must travel with it (ODbL 4.2). It goes in the notes, not in
# an asset: parse_mirror_asset_name() aborts on any asset other than
# parquets and `__source_hash.json`, so a new asset would break every
# installed client. Keep this text in step with DATA-LICENSE.md.
notes <- sprintf(
  paste0(
    "Auto-generated parquet mirror snapshot for group '%s', dataset '%s'.\n",
    "Updated: %s\n\n",
    "See https://sidneybissoli.github.io/cvmdata/articles/",
    "cache-and-mirror.html for client usage.\n\n",
    "**Data licence.** Contains data from the Comissao de Valores ",
    "Mobiliarios (CVM) Open Data Portal, https://dados.cvm.gov.br/, ",
    "made available under the Open Data Commons Open Database License ",
    "(ODbL) v1.0, https://opendatacommons.org/licenses/odbl/1-0/. ",
    "The parquet files in this release are a derivative database of ",
    "that portal, converted by the cvmdata ETL, and are redistributed ",
    "under the same licence. Attribution and terms: ",
    "https://github.com/SidneyBissoli/cvmdata/blob/main/DATA-LICENSE.md"
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
# `na = "null"`: the skip manifest has NA report_type / year for tables
# without variants or partitions; jsonlite would otherwise write the
# string "NA" for character columns.
jsonlite::write_json(
  source_hash,
  hash_asset,
  auto_unbox = TRUE,
  pretty = TRUE,
  na = "null"
)

stage_assets <- function(paths, root) {
  staged <- character(length(paths))
  for (k in seq_along(paths)) {
    rel <- substring(paths[k], nchar(root) + 2L)
    staged[k] <- file.path(stage_dir, asset_name_of(rel))
    file.copy(paths[k], staged[k], overwrite = TRUE)
  }
  staged
}
# History assets that did not change this run stay as they are on the
# release (they are never stale, see below), so only the ones written
# now are uploaded.
assets <- c(
  stage_assets(parquets, dataset_dir),
  stage_assets(history$files, history_dir),
  hash_asset
)

message(sprintf("[03-publish] uploading %d asset(s)", length(assets)))
# GitHub answers an occasional HTTP 500 on one of the hundreds of uploads
# (19/10: fre failed at asset 216 of ~400). --clobber makes a retry safe
# whether or not the failed attempt already removed the old asset.
upload_attempts <- 4L
for (asset in assets) {
  message("  ", basename(asset))
  for (attempt in seq_len(upload_attempts)) {
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
    if (status == 0L) {
      break
    }
    if (attempt < upload_attempts) {
      wait <- 10 * 2^(attempt - 1L)
      message(sprintf("    upload failed; retry %d in %ds", attempt, wait))
      Sys.sleep(wait)
    }
  }
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
# asset stale and delete the release just uploaded. History assets are
# cumulative and most of them are not re-uploaded: never stale.
current <- current[!mirror_is_history_asset(current)]
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
