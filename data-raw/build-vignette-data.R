#!/usr/bin/env Rscript
# data-raw/build-vignette-data.R
#
# Reproducible generator for the small RDS snapshots loaded by the
# CRAN-safe intro vignette `vignettes/cvmdata.Rmd`. Hits the live CVM
# portal once and persists the truncated outputs under
# `inst/extdata/vignette-data/`. The vignette renders without network
# by reading the persisted files via `system.file()`.
#
# Articles under `vignettes/articles/` exercise the live CVM portal at
# pkgdown build time; they do NOT consume these snapshots.
#
# Usage (from package root):
#   Rscript data-raw/build-vignette-data.R           # dry run
#   Rscript data-raw/build-vignette-data.R --write   # persists RDS

suppressPackageStartupMessages({
  library(devtools)
  library(cli)
})

devtools::load_all(".", quiet = TRUE)

# --- helpers ----------------------------------------------------------

# Slice a cvm_tbl preserving provenance attributes and the S3 class.
slice_cvm_tbl <- function(x, n) {
  attrs <- list(
    source          = attr(x, "source", exact = TRUE),
    fetched_at      = attr(x, "fetched_at", exact = TRUE),
    dataset         = attr(x, "dataset", exact = TRUE),
    table           = attr(x, "table", exact = TRUE),
    package_version = attr(x, "package_version", exact = TRUE)
  )
  out <- x[seq_len(min(n, nrow(x))), , drop = FALSE]
  for (nm in names(attrs)) attr(out, nm) <- attrs[[nm]]
  if (!inherits(out, "cvm_tbl")) {
    class(out) <- c("cvm_tbl", class(out))
  }
  out
}

# --- build ------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
write_mode <- "--write" %in% args

out_dir <- file.path("inst", "extdata", "vignette-data")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

cli::cli_h1("Fetching CAD registry (full snapshot)")
cad_full <- cad_fetch()
cli::cli_alert_info(
  "CAD: {nrow(cad_full)} rows, {ncol(cad_full)} cols"
)
cad_sample <- slice_cvm_tbl(cad_full, 15L)

cli::cli_h1("Fetching DFP/BPA individual 2024 (BCO BRASIL, CD_CVM 1023)")
bb_bpa <- cvm_fetch(
  "dfp", "bpa",
  report_type = "ind",
  companies   = "1023",
  years       = 2024L
)
cli::cli_alert_info(
  "DFP/BPA BB 2024: {nrow(bb_bpa)} rows, {ncol(bb_bpa)} cols"
)
bb_bpa_sample <- slice_cvm_tbl(bb_bpa, 8L)

if (write_mode) {
  cad_path <- file.path(out_dir, "cad_companhias_sample.rds")
  bb_path  <- file.path(out_dir, "dfp_bpa_bb_2024_sample.rds")
  saveRDS(cad_sample, cad_path, version = 2L)
  saveRDS(bb_bpa_sample, bb_path, version = 2L)
  cli::cli_alert_success(
    "Wrote {.path {cad_path}} ({file.size(cad_path)} bytes)"
  )
  cli::cli_alert_success(
    "Wrote {.path {bb_path}} ({file.size(bb_path)} bytes)"
  )
} else {
  cli::cli_alert_info(
    "Dry run. Re-run with {.code --write} to persist the RDS files."
  )
}
