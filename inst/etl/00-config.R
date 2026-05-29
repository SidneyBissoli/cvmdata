# ETL configuration for the GitHub Releases parquet mirror.
#
# Sourced by 01-fetch-cvm.R, 02-csv-to-parquet.R, 02b-validate.R, and
# 03-publish.R. Architectural decisions (Sessao 3.11):
#   - Storage: GitHub Releases on the cvmdata repo itself.
#   - Scope: modular — one release per (group, dataset) pair.
#   - Tags: moving "mirror-<group>-<dataset>-latest" + dated snapshots.
#   - Format: parquet snappy with Hive-style "year=YYYY/" partitioning.
#
# Sessao 08 (v0.1.0.9000) introduced the `<group>` segment in release
# tags and on-disk paths. The producer side ships group-aware code in
# this commit; the four pre-Sessao-08 releases (`mirror-cad-latest`,
# etc.) must be renamed in place via the GitHub API before consumers
# on the new code can read them. Until that rename happens,
# `source = "mirror"` is broken end-to-end; users can fall back to
# `cvm_source_set("cvm")`.

# Repo coordinates. Releases live in the same repo as the package.
mirror_repo <- "SidneyBissoli/cvmdata"

# (group, dataset) pairs eligible for the mirror. The modular layout
# means adding a dataset is a no-op for already-published entries —
# append the row here and the workflow can publish it on next dispatch.
# Named `_v0_1` for the original v0.1 four; v0.2 (Sessoes 10-13) added
# cgvn, vlmo, fca and ipe to the `companhias` group — the etl-mirror
# matrix was extended each session but this allowlist was not, so the
# four v0.2 datasets only became publishable here in the v0.2.0 release.
mirror_datasets_v0_1 <- tibble::tibble(
  group = rep("companhias", 8L),
  dataset = c("cad", "dfp", "itr", "fre", "cgvn", "vlmo", "fca", "ipe")
)

# True iff (group, dataset) is in the v0.1 publish matrix. CLI scripts
# use this to validate user-supplied --group / --dataset combinations.
mirror_pair_valid <- function(group, dataset) {
  any(mirror_datasets_v0_1$group == group &
        mirror_datasets_v0_1$dataset == dataset)
}

# Tag templates --------------------------------------------------------

# Moving tag. Recreated on every ETL run; clients that follow
# "<group>-<dataset>-latest" always pick up the freshest snapshot.
mirror_tag_latest <- function(group, dataset) {
  sprintf("mirror-%s-%s-latest", group, dataset)
}

# Immutable tag. Created on demand (release-pinning, vignette pinning,
# paper reproducibility). Format keeps lexicographic order = temporal
# order.
mirror_tag_snapshot <- function(group, dataset, date = Sys.Date()) {
  sprintf("mirror-%s-%s-snapshot-%s",
          group, dataset, format(date, "%Y-%m-%d"))
}

# Parquet layout -------------------------------------------------------

# Hive-style partition path. Year is optional for non-yearly datasets
# (CAD), in which case the file lives directly under the table dir.
# Layout consumed by arrow::open_dataset() and duckdb read_parquet().
# The `<group>` segment was introduced in Sessao 08 of v0.1.0.9000.
mirror_parquet_path <- function(root, group, dataset, table,
                                year = NULL, report_type = NULL) {
  parts <- c(root, "parquet", group, dataset, table)
  if (!is.null(report_type)) {
    parts <- c(parts, sprintf("report_type=%s", report_type))
  }
  if (!is.null(year)) {
    parts <- c(parts, sprintf("year=%d", year))
  }
  do.call(file.path, c(as.list(parts), list("part-0.parquet")))
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
