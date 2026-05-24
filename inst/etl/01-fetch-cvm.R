# Stage 1 — Fetch raw CVM data into the ETL workspace.
#
# Calls cvmdata::cvm_fetch(source = "cvm") for each (table, year) of the
# requested dataset. The package handles the HTTP transport, ETag-based
# revalidation and schema validation; the only side effect this stage
# needs is "warm cache populated" — the actual parquet conversion is
# stage 02.
#
# Usage:
#   Rscript inst/etl/01-fetch-cvm.R --dataset dfp [--year 2024]
#
# Without --year, fetches every year published by CVM for that dataset
# (via cvmdata::cvm_dataset_years()). For non-yearly datasets (CAD),
# --year is ignored.

source("inst/etl/00-config.R")

# Minimal CLI parsing (workflow inputs only).
args <- commandArgs(trailingOnly = TRUE)
dataset <- NULL
year <- NULL
i <- 1L
while (i <= length(args)) {
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
if (is.null(dataset)) {
  stop("--dataset is required", call. = FALSE)
}
if (!dataset %in% mirror_datasets_v0_1) {
  stop(sprintf(
    "dataset '%s' not in mirror_datasets_v0_1 (%s)",
    dataset, paste(mirror_datasets_v0_1, collapse = ", ")
  ), call. = FALSE)
}

# Pin the cache root to the ETL workspace so stage 02 finds the same
# tree. Force backend to "cvm" — the mirror stub would abort here.
workspace <- mirror_workspace()
options(
  cvmdata.cache_dir = file.path(workspace, "cache"),
  cvmdata.source = "cvm"
)

tables <- mirror_tables(dataset)
schema <- cvmdata:::load_schema(dataset, tables[1L])
partitioning <- schema$temporal_partitioning %||% "none"

years_to_fetch <- if (identical(partitioning, "yearly")) {
  if (is.null(year)) cvmdata::cvm_dataset_years(dataset) else year
} else {
  NA_integer_
}

message(sprintf(
  "[01-fetch] dataset=%s tables=[%s] years=[%s] workspace=%s",
  dataset,
  paste(tables, collapse = ", "),
  paste(years_to_fetch, collapse = ", "),
  workspace
))

n_ok <- 0L
n_fail <- 0L
for (tbl in tables) {
  for (y in years_to_fetch) {
    for (rt in mirror_variants_for(tbl)) {
      rt_label <- if (is.null(rt)) "" else sprintf("/%s", rt)
      label <- if (is.na(y)) sprintf("%s/%s%s", dataset, tbl, rt_label) else
        sprintf("%s/%s%s/%d", dataset, tbl, rt_label, y)
      message("  -> ", label)
      res <- tryCatch(
        {
          years_arg <- if (is.na(y)) NULL else y
          rt_arg <- if (is.null(rt)) NULL else rt
          cvmdata::cvm_fetch(
            dataset, tbl,
            years = years_arg,
            report_type = rt_arg,
            source = "cvm"
          )
        },
        error = function(e) {
          message("     ABORT: ", conditionMessage(e))
          NULL
        }
      )
      if (is.null(res)) {
        n_fail <- n_fail + 1L
      } else {
        n_ok <- n_ok + 1L
      }
    }
  }
}
message(sprintf(
  "[01-fetch] done. %d ok / %d failed", n_ok, n_fail
))
if (n_fail > 0L) {
  quit(status = 1L)
}
