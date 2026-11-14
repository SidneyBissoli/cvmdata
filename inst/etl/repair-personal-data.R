# Repair — pass the parquets of the dated snapshots through the privacy rule
# (one-off after the decision of 2026-11-08; util-privacy.R).
#
# 02-csv-to-parquet.R masks what is published from now on, and 03-publish.R
# rewrites the `-latest` parquets and their history. The dated snapshots
# published before the rule keep the full CPFs and birth dates at public
# URLs, and `cvm_release_set()` still reads them. Snapshot releases are
# never deleted, because the pointers of later snapshots depend on them, so
# their assets are rewritten in place: same names, same rows, the masked
# values. Everything else in those files stays, and a file with nothing to
# mask is left alone.
#
# Since rule 3 (2026-11-14) the repair does two more things. The assets
# of the tables the mirror no longer carries (`mirror: false`) are DELETED
# from the snapshots: nothing later points anywhere else for them, and
# repair-snapshot-digests.R takes their entries out of the sidecars. And a
# count table loses the filings with a small or unanimous group, so the
# rewritten file has fewer rows; what it lost is measured before the
# rewrite and saved in `omitted-reports.json` of the workspace, where the
# digest repair reads it to fill `privacy_omitted` of the dated sidecars
# (a reader pinned to an old date gets the same warning).
#
# Run it AFTER the first publish under the rule, then rerun
# repair-snapshot-digests.R for the same dataset: the sidecars carry the
# sha256 of the bytes each snapshot points to, and the client refuses a
# download that differs. The CVM rewrites nothing here: the old bytes are
# gone once uploaded, and that is the point.
#
# The public URL serves the old bytes for a few minutes after the upload
# (measured 2026-11-14: about three). Both repairs check every download
# against the sha256 the API lists (`release_asset_digests()`), so a dry
# run or the digest repair right after this one reads the new bytes; a
# client pinned to an old date fails its integrity check on the rewritten
# files from the moment the URL turns until the digest repair has run.
#
# Usage:
#   Rscript inst/etl/repair-personal-data.R --group companhias \
#     --dataset fre [--dry-run]
#
# `--dry-run` downloads and counts, by file and column, and uploads
# nothing. Setting `options(cvmdata.etl_testing = TRUE)` loads the helpers
# and skips the entry point.

for (sibling in c("00-config.R", "util-release.R", "util-privacy.R")) {
  marker <- c(
    "00-config.R" = "mirror_tag_latest",
    "util-release.R" = "download_public_asset",
    "util-privacy.R" = "mirror_apply_privacy"
  )[[sibling]]
  if (!exists(marker, mode = "function")) {
    source(file.path("inst", "etl", sibling))
  }
}

stopifnot(requireNamespace("arrow", quietly = TRUE))
stopifnot(requireNamespace("jsonlite", quietly = TRUE))

# Rewrites one local parquet through the rule when it has something to
# mask or drop. Returns the number of values changed (0 = file untouched);
# stops if the rewritten file does not hold the same rows or still fails
# the guard.
scrub_parquet_file <- function(path) {
  # no memory map: it would hold the file open against the overwrite
  df <- as.data.frame(arrow::read_parquet(path, mmap = FALSE))
  left <- mirror_privacy_counts(df)
  if (!length(left)) {
    return(0L)
  }
  tmp <- tempfile(fileext = ".parquet")
  on.exit(unlink(tmp), add = TRUE)
  safe <- mirror_apply_privacy(df)
  arrow::write_parquet(safe, tmp, compression = "snappy")
  if (!suppressWarnings(file.copy(tmp, path, overwrite = TRUE))) {
    stop(sprintf("could not overwrite %s", basename(path)), call. = FALSE)
  }
  # the file that will be uploaded, not the one just written
  again <- as.data.frame(arrow::read_parquet(path, mmap = FALSE))
  if (nrow(again) != nrow(safe) || length(mirror_privacy_counts(again))) {
    stop(
      sprintf("rewrite of %s failed its check", basename(path)),
      call. = FALSE
    )
  }
  # at least one: a contact column with no filled value is still dropped
  max(1L, as.integer(sum(left)))
}

# Table of an asset name (`<table>__year.2024__part-0.parquet`).
asset_table <- function(name) {
  strsplit(name, "__", fixed = TRUE)[[1L]][[1L]]
}

# What the group rule would take from a local parquet, or NULL when it is
# not a count table or loses nothing (a file already rewritten says
# nothing about what it lost, so it must not overwrite an earlier report).
group_report_of_file <- function(path) {
  df <- as.data.frame(arrow::read_parquet(path, mmap = FALSE))
  report <- mirror_group_report(df)
  if (is.null(report) || !report$companies_omitted) {
    return(NULL)
  }
  report
}

# The reports of earlier runs of this repair, by release tag and asset.
read_omitted_reports <- function(path) {
  if (!file.exists(path)) {
    return(list())
  }
  jsonlite::read_json(path)
}

write_omitted_reports <- function(reports, path) {
  reports <- lapply(reports, function(by_asset) {
    lapply(by_asset, function(r) {
      r$cnpj <- I(as.character(unlist(r$cnpj)))
      r
    })
  })
  jsonlite::write_json(reports, path, auto_unbox = TRUE, pretty = TRUE)
  path
}

# sha256 of the parquet assets of a release, by asset name.
release_parquet_assets <- function(tag) {
  digests <- release_asset_digests(tag)
  digests[grepl("[.]parquet$", names(digests))]
}

personal_repair_main <- function(group, dataset, dry_run) {
  work <- file.path(mirror_workspace(), "repair-personal", group, dataset)
  dir.create(work, recursive = TRUE, showWarnings = FALSE)
  sidecar_path <- download_public_asset(
    mirror_tag_latest(group, dataset),
    "__source_hash.json",
    work
  )
  if (is.null(sidecar_path)) {
    stop(sprintf("%s has no sidecar", dataset), call. = FALSE)
  }
  latest <- jsonlite::read_json(sidecar_path)
  if (!identical(latest$privacy_rule %||% "", mirror_privacy_rule)) {
    stop(
      "publish under the privacy rule first: `-latest` still predates it",
      call. = FALSE
    )
  }
  excluded <- mirror_excluded_tables(dataset)
  reports_path <- file.path(work, "omitted-reports.json")
  reports <- read_omitted_reports(reports_path)
  for (date in as.character(unlist(latest$snapshots %||% list()))) {
    tag <- mirror_tag_snapshot(group, dataset, as.Date(date))
    dir <- file.path(work, tag)
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    assets <- release_parquet_assets(tag)
    n_files <- 0L
    n_values <- 0L
    n_deleted <- 0L
    for (name in names(assets)) {
      if (asset_table(name) %in% excluded) {
        n_deleted <- n_deleted + 1L
        if (!dry_run) {
          delete_release_asset(tag, name)
        }
        next
      }
      path <- download_public_asset(
        tag,
        name,
        dir,
        expect_sha256 = assets[[name]]
      )
      if (is.null(path)) {
        stop(sprintf("%s of %s not downloadable", name, tag), call. = FALSE)
      }
      report <- group_report_of_file(path)
      if (!is.null(report)) {
        reports[[tag]][[name]] <- report
      }
      changed <- scrub_parquet_file(path)
      if (changed > 0L) {
        n_files <- n_files + 1L
        n_values <- n_values + changed
        if (!dry_run) {
          upload_release_asset(tag, path)
        }
      }
      unlink(path)
    }
    message(sprintf(
      "[repair-personal] %s: %d of %d file(s), %s value(s)%s; %d file(s) %s",
      tag,
      n_files,
      length(assets),
      format(n_values, big.mark = ","),
      if (dry_run) " (dry run, nothing uploaded)" else " rewritten",
      n_deleted,
      if (dry_run) "of tables out of the mirror to delete" else "deleted"
    ))
  }
  write_omitted_reports(reports, reports_path)
  invisible(NULL)
}

personal_repair_args <- function(args) {
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
  opts <- personal_repair_args(commandArgs(trailingOnly = TRUE))
  personal_repair_main(opts$group, opts$dataset, opts$dry_run)
}
