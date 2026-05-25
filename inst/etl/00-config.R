# ETL configuration for the GitHub Releases parquet mirror.
#
# Sourced by 01-fetch-cvm.R, 02-csv-to-parquet.R, and 03-publish.R.
# Architectural decisions (Sessao 3.11):
#   - Storage: GitHub Releases on the cvmdata repo itself.
#   - Scope: modular — one release per dataset.
#   - Tags: moving "mirror-<dataset>-latest" + dated snapshots.
#   - Format: parquet snappy with Hive-style "year=YYYY/" partitioning.

# Repo coordinates. Releases live in the same repo as the package.
mirror_repo <- "SidneyBissoli/cvmdata"

# Datasets eligible for the v0.1 mirror. The modular layout means
# adding a dataset is a no-op for already-published datasets — append
# the id here and the workflow can publish it on next dispatch.
mirror_datasets_v0_1 <- c("cad", "dfp", "itr", "fre")

# Tag templates --------------------------------------------------------

# Moving tag. Recreated on every ETL run; clients that follow
# "<dataset>-latest" always pick up the freshest snapshot.
mirror_tag_latest <- function(dataset) {
  sprintf("mirror-%s-latest", dataset)
}

# Immutable tag. Created on demand (release-pinning, vignette pinning,
# paper reproducibility). Format keeps lexicographic order = temporal
# order.
mirror_tag_snapshot <- function(dataset, date = Sys.Date()) {
  sprintf("mirror-%s-snapshot-%s", dataset, format(date, "%Y-%m-%d"))
}

# Parquet layout -------------------------------------------------------

# Hive-style partition path. Year is optional for non-yearly datasets
# (CAD), in which case the file lives directly under the table dir.
# Layout consumed by arrow::open_dataset() and duckdb read_parquet().
mirror_parquet_path <- function(root, dataset, table, year = NULL) {
  if (is.null(year)) {
    file.path(root, "parquet", dataset, table, "part-0.parquet")
  } else {
    file.path(
      root, "parquet", dataset, table,
      sprintf("year=%d", year), "part-0.parquet"
    )
  }
}

# Local workspace ------------------------------------------------------

# Returns the working directory for ETL outputs (downloads + parquet).
# Honors CVMDATA_ETL_WORKSPACE for CI; falls back to tempdir() locally.
# Always creates the directory if missing.
mirror_workspace <- function() {
  root <- Sys.getenv("CVMDATA_ETL_WORKSPACE", "")
  if (!nzchar(root)) {
    root <- file.path(tempdir(), "cvmdata-etl")
  }
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  root
}

# Schema lookup --------------------------------------------------------

# Installed schemas live under
# `inst/extdata/schemas/<group>/<dataset>/*.yaml` since Sessao 05. This
# helper resolves the group via the package's internal `dataset_group()`
# lookup and returns the absolute directory, whether the package is
# loaded via devtools or installed normally.
mirror_schema_dir <- function(dataset) {
  group <- cvmdata:::dataset_group(dataset)
  path <- system.file(
    "extdata", "schemas", group, dataset, package = "cvmdata"
  )
  if (!nzchar(path) || !dir.exists(path)) {
    stop(sprintf(
      "Schema directory not found for dataset '%s' in group '%s'",
      dataset, group
    ), call. = FALSE)
  }
  path
}

# Returns the table ids for a dataset by reading YAML filenames.
mirror_tables <- function(dataset) {
  files <- list.files(mirror_schema_dir(dataset), pattern = "\\.yaml$")
  tools::file_path_sans_ext(files)
}

# Variant tables --------------------------------------------------------

# Tables that require `report_type = "ind" | "con"`. Closed list — the
# API contract is part of the package surface (CLAUDE.md §2.1). All
# ETL stages iterate over these variants when scheduling work.
mirror_variant_tables <- c(
  "bpa", "bpp", "dre", "dra", "dfc_md", "dfc_mi", "dmpl", "dva"
)

# Returns the report_type values to iterate for a given table.
# List(NULL) means "single pass with report_type = NULL".
mirror_variants_for <- function(tbl) {
  if (tbl %in% mirror_variant_tables) c("ind", "con") else list(NULL)
}
