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
  if (is.null(res) || nrow(res) == 0L) return(invisible(FALSE))

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
  invisible(TRUE)
}

message(sprintf(
  "[02-parquet] group=%s dataset=%s tables=[%s] year =[%s]",
  group, dataset, paste(tables, collapse = ", "),
  paste(years_to_process, collapse = ", ")
))

n_ok <- 0L
n_fail <- 0L
for (tbl in tables) {
  for (y in years_to_process) {
    for (rt in mirror_variants_for(tbl)) {
      label <- if (is.null(rt)) tbl else sprintf("%s/%s", tbl, rt)
      message(sprintf(
        "  -> %s/%s/%s", dataset, label,
        if (is.na(y)) "static" else as.character(y)
      ))
      ok <- write_one(tbl, y, rt)
      if (isTRUE(ok)) n_ok <- n_ok + 1L else n_fail <- n_fail + 1L
    }
  }
}
message(sprintf(
  "[02-parquet] done. %d ok / %d failed", n_ok, n_fail
))
if (n_fail > 0L && n_ok == 0L) {
  quit(status = 1L)
}
