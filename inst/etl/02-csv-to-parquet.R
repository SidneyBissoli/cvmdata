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

# Returns "ok" (parquet written), "empty" (0 rows upstream — a legitimate
# state for tables the CVM publishes header-only in some years, e.g.
# fca/departamento_acionistas from 2024 on) or "fail" (fetch aborted).
# The caller records "empty" tuples in a manifest so stage 02b can tell
# a legitimately-absent parquet from a genuinely missing one.
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
    error = function(e) {
      message("  ABORT ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(res)) return("fail")
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

# One row of the empty manifest for a (table, year, report_type) tuple.
empty_tuple_row <- function(tbl, y, rt) {
  data.frame(
    table = tbl,
    year = if (is.na(y)) NA_integer_ else as.integer(y),
    report_type = if (is.null(rt)) NA_character_ else rt,
    stringsAsFactors = FALSE
  )
}

message(sprintf(
  "[02-parquet] group=%s dataset=%s tables=[%s] year =[%s]",
  group, dataset, paste(tables, collapse = ", "),
  paste(years_to_process, collapse = ", ")
))

n_ok <- 0L
n_empty <- 0L
n_fail <- 0L
empty_tuples <- list()
for (tbl in tables) {
  for (y in years_to_process) {
    for (rt in mirror_variants_for(tbl)) {
      st <- log_and_write(tbl, y, rt)
      if (identical(st, "ok")) {
        n_ok <- n_ok + 1L
      } else if (identical(st, "empty")) {
        n_empty <- n_empty + 1L
        empty_tuples[[length(empty_tuples) + 1L]] <-
          empty_tuple_row(tbl, y, rt)
      } else {
        n_fail <- n_fail + 1L
      }
    }
  }
}

# Empty manifest: the (table, year, report_type) tuples that were empty
# upstream. Stage 02b reads it to treat a legitimately-absent parquet as
# a pass instead of a hard "missing file" failure. Written outside the
# `parquet/` tree so 03-publish does not upload it as a release asset.
empty_dir <- file.path(out_root, "empty")
dir.create(empty_dir, recursive = TRUE, showWarnings = FALSE)
empty_manifest <- if (length(empty_tuples)) {
  do.call(rbind, empty_tuples)
} else {
  data.frame(
    table = character(0L),
    year = integer(0L),
    report_type = character(0L),
    stringsAsFactors = FALSE
  )
}
jsonlite::write_json(
  empty_manifest,
  file.path(empty_dir, sprintf("%s.json", dataset)),
  auto_unbox = TRUE, pretty = TRUE, na = "null"
)

message(sprintf(
  "[02-parquet] done. %d ok / %d empty / %d failed",
  n_ok, n_empty, n_fail
))
if (n_fail > 0L && n_ok == 0L) {
  quit(status = 1L)
}
