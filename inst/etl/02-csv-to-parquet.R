# Stage 2 — Convert CVM tables to parquet snappy.
#
# For each (table, year) pair of the requested dataset, fetches the
# tibble via cvmdata::issuer_fetch() (warm cache from stage 01) and writes
# parquet snappy to the ETL workspace, partitioned Hive-style.
#
# Output layout (Sessao 08 of v0.1.0.9000 added `<group>`):
#   <workspace>/out/parquet/<group>/<dataset>/<table>/year=<YYYY>/part-0.parquet
#
# Tables with individual/consolidated variants (DFP/ITR balance sheets,
# income statements, etc.) get a second partition level:
#   .../report_type=<ind|con>/year=<YYYY>/part-0.parquet
#
# Usage:
#   Rscript inst/etl/02-csv-to-parquet.R \
#     --group companhias --dataset dfp [--year 2024]

source("inst/etl/00-config.R")
stopifnot(requireNamespace("arrow", quietly = TRUE))
stopifnot(requireNamespace("jsonlite", quietly = TRUE))

args <- commandArgs(trailingOnly = TRUE)
group <- NULL
dataset <- NULL
year <- NULL
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
  if (args[i] == "--year") {
    year <- as.integer(args[i + 1L])
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
  stop(sprintf("(%s, %s) not in mirror_datasets_v0_1", group, dataset),
       call. = FALSE)
}

workspace <- mirror_workspace()
options(
  cvmdata.cache_dir = file.path(workspace, "cache"),
  cvmdata.source = "cvm"
)

tables <- mirror_tables(dataset)
schema <- cvmdata:::load_schema(dataset, tables[1L])
partitioning <- schema$temporal_partitioning %||% "none"

years_to_process <- if (identical(partitioning, "yearly")) {
  if (is.null(year)) cvmdata::cvm_dataset_years(dataset) else year
} else {
  NA_integer_
}

out_root <- file.path(workspace, "out")
dir.create(out_root, recursive = TRUE, showWarnings = FALSE)

# Classify the outcome of fetching + writing one (table, year, rtype):
#   "ok"     — parquet written.
#   "empty"  — 0 rows upstream: a legitimate state for tables the CVM
#              publishes header-only in some years (e.g.
#              fca/departamento_acionistas from 2024 on, or the current
#              not-yet-filed year of an annual financial table).
#   "absent" — the table's CSV is not inside the dataset's yearly ZIP:
#              the CVM only started publishing that detail table in a
#              later year (e.g. dfp/itr composicao_capital before 2020;
#              several fre tables in early years). The ETL iterates every
#              dataset-year for every table, so years before a table
#              existed land here.
#   "fail"   — any other fetch/convert error (a genuine problem).
# "empty" and "absent" are recorded in the skip manifest so stage 02b
# treats the absent parquet as a soft pass rather than a hard failure;
# "fail" is not recorded, so a genuinely missing parquet still hard-fails.
write_one <- function(tbl, y, rtype) {
  years_arg <- if (is.na(y)) NULL else y
  rt_arg <- if (is.null(rtype)) NULL else rtype
  res <- tryCatch(
    cvmdata::issuer_fetch(
      dataset, tbl,
      year = years_arg,
      report_type = rt_arg,
      source = "cvm"
    ),
    error = function(e) e
  )
  if (inherits(res, "condition")) {
    message("  ABORT ", conditionMessage(res))
    if (grepl("not found inside ZIP", conditionMessage(res), fixed = TRUE)) {
      return("absent")
    }
    return("fail")
  }
  if (nrow(res) == 0L) return("empty")

  parts <- c("parquet", group, dataset, tbl)
  if (!is.null(rtype)) parts <- c(parts, sprintf("report_type=%s", rtype))
  if (!is.na(y)) parts <- c(parts, sprintf("year=%d", y))
  out_dir <- do.call(file.path, c(list(out_root), as.list(parts)))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_path <- file.path(out_dir, "part-0.parquet")

  arrow::write_parquet(res, out_path, compression = "snappy")
  message(sprintf(
    "  wrote %s (%s rows, %.1f KB)",
    out_path,
    format(nrow(res), big.mark = ","),
    file.info(out_path)$size / 1024
  ))
  "ok"
}

# Log the tuple being processed, then convert it. Split out of the main
# loop to keep that loop's cyclomatic complexity within the lint budget.
log_and_write <- function(tbl, y, rt) {
  label <- if (is.null(rt)) tbl else sprintf("%s/%s", tbl, rt)
  message(sprintf(
    "  -> %s/%s/%s", dataset, label,
    if (is.na(y)) "static" else as.character(y)
  ))
  write_one(tbl, y, rt)
}

# One row of the skip manifest for a (table, year, report_type) tuple
# that produced no parquet, tagged with why ("empty" or "absent").
skip_tuple_row <- function(tbl, y, rt, reason) {
  data.frame(
    table = tbl,
    year = if (is.na(y)) NA_integer_ else as.integer(y),
    report_type = if (is.null(rt)) NA_character_ else rt,
    reason = reason,
    stringsAsFactors = FALSE
  )
}

message(sprintf(
  "[02-parquet] group=%s dataset=%s tables=[%s] year =[%s]",
  group, dataset, paste(tables, collapse = ", "),
  paste(years_to_process, collapse = ", ")
))

# Process every tuple, collecting its outcome; tally and build the skip
# manifest afterwards so the loop itself stays simple (lint budget).
outcomes <- list()
for (tbl in tables) {
  for (y in years_to_process) {
    for (rt in mirror_variants_for(tbl)) {
      outcomes[[length(outcomes) + 1L]] <- list(
        tbl = tbl, y = y, rt = rt, st = log_and_write(tbl, y, rt)
      )
    }
  }
}

st_vec <- vapply(outcomes, function(o) o$st, character(1L))
n_ok <- sum(st_vec == "ok")
n_empty <- sum(st_vec == "empty")
n_absent <- sum(st_vec == "absent")
n_fail <- sum(st_vec == "fail")
skip_tuples <- lapply(
  outcomes[st_vec %in% c("empty", "absent")],
  function(o) skip_tuple_row(o$tbl, o$y, o$rt, o$st)
)

# Skip manifest: the (table, year, report_type) tuples that produced no
# parquet for a benign reason ("empty" = 0 rows upstream; "absent" = the
# CSV is not in the yearly ZIP because the table did not exist that year
# yet). Stage 02b reads it to treat the missing parquet as a soft pass
# rather than a hard "missing file" failure. Written outside the
# `parquet/` tree so 03-publish does not upload it as a release asset.
skip_dir <- file.path(out_root, "skip")
dir.create(skip_dir, recursive = TRUE, showWarnings = FALSE)
skip_manifest <- if (length(skip_tuples)) {
  do.call(rbind, skip_tuples)
} else {
  data.frame(
    table = character(0L),
    year = integer(0L),
    report_type = character(0L),
    reason = character(0L),
    stringsAsFactors = FALSE
  )
}
jsonlite::write_json(
  skip_manifest,
  file.path(skip_dir, sprintf("%s.json", dataset)),
  auto_unbox = TRUE, pretty = TRUE, na = "null"
)

message(sprintf(
  "[02-parquet] done. %d ok / %d empty / %d absent / %d failed",
  n_ok, n_empty, n_absent, n_fail
))
if (n_fail > 0L && n_ok == 0L) {
  quit(status = 1L)
}
