# Stage 5 — Label the superseded DFP/ITR versions that were scale errors.
#
# Runs after a stage that appended to the history assets of a release
# (03-publish.R on the mirror path, 04-rad-fetch.R on the RAD path) and
# writes, in every history asset of the eight statements, the column
# `scale_error` of util-scale.R: one verdict per superseded version,
# judged over the whole document. The verdict needs every table of the
# version and of its successor, so it cannot be given where the rows
# are written (the mirror path sees one partition at a time, the RAD
# path one document at a time without its successor): it is given here,
# one reference year at a time, from the release itself.
#
# Which years: the ones with a statement history asset whose content
# hash (`history` map of `__source_hash.json`) differs from the hash it
# had when last labelled (`scale_labeled` map, written here), or every
# year when the rule changed (`scale_rule`) or `--all` is given (the
# backfill of 2026-11). Every history asset of a labelled year is
# rewritten whole and uploaded, the sidecar last; a run that dies between
# the two leaves `history` hashes behind the assets, which no reader
# checks (the client evicts history assets on a change of the dataset
# hash, not by digest).
#
# Usage:
#   Rscript inst/etl/05-label-scale.R --group companhias --dataset dfp \
#     [--all] [--year 2023] [--dry-run]
#
# `--dry-run` writes the labelled assets under
# <workspace>/out/scale/<group>/<dataset>/ and prints the counts without
# touching the release. Setting `options(cvmdata.etl_testing = TRUE)`
# loads the helpers and skips the entry point.

for (sibling in c(
  "00-config.R",
  "util-hash.R",
  "util-history.R",
  "util-release.R",
  "util-scale.R"
)) {
  marker <- c(
    "00-config.R" = "mirror_tag_latest",
    "util-hash.R" = "mirror_hash_parquet",
    "util-history.R" = "mirror_partition_table",
    "util-release.R" = "upload_release_asset",
    "util-scale.R" = "scale_label_versions"
  )[[sibling]]
  if (!exists(marker, mode = "function")) {
    source(file.path("inst", "etl", sibling))
  }
}

stopifnot(requireNamespace("arrow", quietly = TRUE))
stopifnot(requireNamespace("jsonlite", quietly = TRUE))

# --- the release ------------------------------------------------------

# Partition path pieces of a history or partition asset:
# list(table, report_type, year).
scale_rel_parts <- function(rel) {
  segments <- strsplit(rel, "/", fixed = TRUE)[[1L]]
  pick <- function(prefix) {
    hit <- segments[startsWith(segments, prefix)]
    if (length(hit)) substring(hit[[1L]], nchar(prefix) + 1L) else NA_character_
  }
  list(
    table = segments[[1L]],
    report_type = pick("report_type="),
    year = as.integer(pick("year="))
  )
}

# The history assets of the statement tables in `history` (the map of
# the sidecar): data.frame(rel, table, report_type, year).
scale_history_assets <- function(history) {
  rels <- names(history) %||% character()
  parts <- lapply(rels, scale_rel_parts)
  out <- data.frame(
    rel = rels,
    table = vapply(parts, function(p) p$table, character(1L)),
    report_type = vapply(parts, function(p) p$report_type, character(1L)),
    year = vapply(parts, function(p) p$year, integer(1L)),
    stringsAsFactors = FALSE
  )
  out[out$table %in% scale_tables & !is.na(out$year), , drop = FALSE]
}

# The years this run labels: every year with a statement history asset
# when `all` or the rule changed; otherwise the years with an asset
# whose hash moved since it was labelled. `year` narrows the list.
scale_pending_years <- function(source_hash, all = FALSE, year = NULL) {
  assets <- scale_history_assets(source_hash$history)
  if (!nrow(assets)) {
    return(integer())
  }
  whole <- isTRUE(all) || !identical(source_hash$scale_rule, scale_rule)
  pending <- if (whole) {
    assets$year
  } else {
    labeled <- source_hash$scale_labeled %||% list()
    moved <- vapply(
      assets$rel,
      function(rel) !identical(source_hash$history[[rel]], labeled[[rel]]),
      logical(1L)
    )
    assets$year[moved]
  }
  pending <- sort(unique(pending))
  if (!is.null(year)) {
    pending <- intersect(pending, year)
  }
  pending
}

# The current partitions of the statement tables of `year` the release
# holds (the `data` map of the sidecar): partition paths.
scale_current_rels <- function(source_hash, year) {
  pairs <- expand.grid(
    basis = c("ind", "con"),
    table = scale_tables,
    stringsAsFactors = FALSE
  )
  rels <- sprintf(
    "%s/report_type=%s/year=%d/part-0.parquet",
    pairs$table,
    pairs$basis,
    year
  )
  rels[rels %in% names(source_hash$data)]
}

# Reads one asset of the release (downloaded to `dir`) with `table` and
# `report_type` added; `cols` limits the columns read (NULL = all).
scale_read_asset <- function(tag, rel, dir, cols = NULL) {
  path <- download_public_asset(tag, public_asset_name(rel), dir)
  if (is.null(path)) {
    stop(sprintf("asset %s is listed but not downloadable", rel), call. = FALSE)
  }
  df <- if (is.null(cols)) {
    arrow::read_parquet(path)
  } else {
    arrow::read_parquet(path, col_select = dplyr::any_of(cols))
  }
  df <- as.data.frame(df)
  parts <- scale_rel_parts(rel)
  df$table <- rep(parts$table, nrow(df))
  df$report_type <- rep(parts$report_type, nrow(df))
  df
}

# Labels one year: reads its history and current assets, judges every
# version, writes every history asset of the year with `scale_error`
# under `out_dir` and returns list(files = local paths by rel,
# verdicts).
scale_label_year <- function(tag, source_hash, year, prev_dir, out_dir) {
  assets <- scale_history_assets(source_hash$history)
  assets <- assets[assets$year == year, , drop = FALSE]
  history <- lapply(assets$rel, function(rel) {
    scale_read_asset(tag, rel, prev_dir)
  })
  names(history) <- assets$rel
  current <- lapply(scale_current_rels(source_hash, year), function(rel) {
    scale_read_asset(tag, rel, prev_dir, cols = scale_value_cols)
  })
  value_cols <- c(scale_value_cols, mirror_history_cols, "table", "report_type")
  verdicts <- scale_label_versions(
    dplyr::bind_rows(lapply(history, function(h) {
      h[intersect(value_cols, names(h))]
    })),
    dplyr::bind_rows(current)
  )
  files <- character()
  for (rel in assets$rel) {
    labelled <- scale_apply_verdicts(history[[rel]], verdicts)
    labelled$table <- NULL
    labelled$report_type <- NULL
    out <- file.path(out_dir, rel)
    dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
    arrow::write_parquet(labelled, out, compression = "snappy")
    files[[rel]] <- out
  }
  list(files = files, verdicts = verdicts)
}

# --- the run ----------------------------------------------------------

scale_main <- function(group, dataset, all, year, dry_run) {
  tag <- mirror_tag_latest(group, dataset)
  work <- file.path(mirror_workspace(), "scale", group, dataset)
  prev_dir <- file.path(work, "release")
  out_dir <- file.path(mirror_workspace(), "out", "scale", group, dataset)
  for (d in c(work, prev_dir, out_dir)) {
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
  }

  message(sprintf(
    "[05-scale] %s: reading the sidecar of release %s",
    dataset,
    tag
  ))
  hash_file <- download_release_asset(tag, "__source_hash.json", prev_dir)
  if (is.null(hash_file)) {
    stop(sprintf("release %s has no __source_hash.json", tag), call. = FALSE)
  }
  source_hash <- jsonlite::read_json(hash_file)
  source_hash$history <- source_hash$history %||% list()
  years <- scale_pending_years(source_hash, all = all, year = year)
  message(sprintf(
    "[05-scale] %d history asset(s) of the statements; %d year(s) to label%s",
    nrow(scale_history_assets(source_hash$history)),
    length(years),
    if (length(years)) paste0(": ", paste(years, collapse = ", ")) else ""
  ))
  if (!length(years)) {
    return(invisible(NULL))
  }

  for (y in years) {
    res <- scale_label_year(tag, source_hash, y, prev_dir, out_dir)
    message(sprintf(
      "[05-scale] %s %d: %s",
      dataset,
      y,
      scale_tally(res$verdicts)
    ))
    staged <- character()
    for (rel in names(res$files)) {
      h <- mirror_hash_parquet(res$files[[rel]])
      source_hash$history[[rel]] <- h
      source_hash$scale_labeled[[rel]] <- h
      stage <- file.path(out_dir, asset_name_of(rel))
      file.copy(res$files[[rel]], stage, overwrite = TRUE)
      staged <- c(staged, stage)
    }
    source_hash$scale_rule <- scale_rule
    hash_path <- file.path(out_dir, "__source_hash.json")
    jsonlite::write_json(
      source_hash,
      hash_path,
      auto_unbox = TRUE,
      pretty = TRUE
    )
    if (dry_run) {
      message(sprintf(
        "  dry run: %d asset(s) written under %s; nothing uploaded",
        length(staged),
        out_dir
      ))
      next
    }
    for (p in c(staged, hash_path)) {
      message("  uploading ", basename(p))
      upload_release_asset(tag, p)
    }
  }
  invisible(NULL)
}

scale_parse_args <- function(args) {
  opts <- list(
    group = NULL,
    dataset = NULL,
    all = FALSE,
    year = NULL,
    dry_run = FALSE
  )
  i <- 1L
  while (i <= length(args)) {
    a <- args[i]
    if (a == "--group") {
      opts$group <- args[i + 1L]
      i <- i + 2L
    } else if (a == "--dataset") {
      opts$dataset <- args[i + 1L]
      i <- i + 2L
    } else if (a == "--year") {
      opts$year <- as.integer(args[i + 1L])
      i <- i + 2L
    } else if (a == "--all") {
      opts$all <- TRUE
      i <- i + 1L
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
  if (!opts$dataset %in% c("dfp", "itr")) {
    stop("stage 05 labels the statements of dfp and itr only", call. = FALSE)
  }
  opts
}

if (!isTRUE(getOption("cvmdata.etl_testing"))) {
  if (!nzchar(Sys.which("gh"))) {
    stop("`gh` CLI not found on PATH", call. = FALSE)
  }
  opts <- scale_parse_args(commandArgs(trailingOnly = TRUE))
  scale_main(opts$group, opts$dataset, opts$all, opts$year, opts$dry_run)
}
