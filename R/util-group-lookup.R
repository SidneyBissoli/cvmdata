# Internal-only lookup mapping dataset ids to their CKAN group. Driven
# off the installed schema tree at `inst/extdata/schemas/<group>/
# <dataset>/<table>.yaml`. The constant `.dataset_group_map` that
# Session 04 shipped as technical debt was removed here in favour of
# this schema-driven resolver, so adding a new group only requires
# dropping schema YAMLs in place.

# Session-scoped memo of the schema tree. Keyed by the resolved schemas
# root path (so tests that override `cvmdata.schema_root` get a fresh
# cache automatically).
.schema_tree_cache <- new.env(parent = emptyenv())

# Resolve the root that holds `<group>/<dataset>/<table>.yaml`. Honours
# the undocumented `cvmdata.schema_root` option (used in tests to point
# at a fixture); falls back to the installed schemas directory.
.schemas_root <- function() {
  opt <- getOption("cvmdata.schema_root", default = NULL)
  if (!is.null(opt) && is.character(opt) && length(opt) == 1L &&
        nzchar(opt)) {
    return(opt)
  }
  system.file("extdata", "schemas", package = "cvmdata")
}

# Walk the schema root and return a data frame with `group`, `dataset`
# and `table` columns -- one row per installed YAML. Memoized for the
# duration of the R session, keyed by the resolved root path.
schema_tree <- function() {
  root <- .schemas_root()
  cached <- .schema_tree_cache[[root]]
  if (!is.null(cached)) {
    return(cached)
  }
  if (!nzchar(root) || !dir.exists(root)) {
    out <- data.frame(
      group   = character(0L),
      dataset = character(0L),
      table   = character(0L),
      stringsAsFactors = FALSE
    )
    .schema_tree_cache[[root]] <- out
    return(out)
  }
  groups <- list.dirs(root, recursive = FALSE, full.names = FALSE)
  rows <- list()
  for (g in groups) {
    g_path <- file.path(root, g)
    datasets <- list.dirs(g_path, recursive = FALSE, full.names = FALSE)
    for (d in datasets) {
      d_path <- file.path(g_path, d)
      yamls <- list.files(
        d_path, pattern = "\\.yaml$", full.names = FALSE
      )
      if (!length(yamls)) {
        next
      }
      rows[[length(rows) + 1L]] <- data.frame(
        group   = g,
        dataset = d,
        table   = sub("\\.yaml$", "", yamls),
        stringsAsFactors = FALSE
      )
    }
  }
  out <- if (length(rows)) {
    do.call(rbind, rows)
  } else {
    data.frame(
      group   = character(0L),
      dataset = character(0L),
      table   = character(0L),
      stringsAsFactors = FALSE
    )
  }
  .schema_tree_cache[[root]] <- out
  out
}

# Resolve a dataset id to its CKAN group. Aborts with
# `cvmdata_error_internal` for unknown datasets so callers never
# silently land on an empty group string, and with
# `cvmdata_error_input_ambiguous` if a dataset slug appears under more
# than one group (does not happen in v0.1.0.9000 but the design needs
# to sustain it from v0.4 onward when fundos arrive).
dataset_group <- function(dataset) {
  if (!is.character(dataset) || length(dataset) != 1L ||
        is.na(dataset) || !nzchar(dataset)) {
    cvmdata_abort(
      c("{.arg dataset} must be a single non-empty string."),
      class = "cvmdata_error_internal"
    )
  }
  tree <- schema_tree()
  groups <- unique(tree$group[tree$dataset == dataset])
  if (!length(groups)) {
    cvmdata_abort(
      c(
        "Unknown dataset {.val {dataset}}; cannot resolve group.",
        "i" = "Known datasets: {.val {sort(unique(tree$dataset))}}."
      ),
      class = "cvmdata_error_internal"
    )
  }
  if (length(groups) > 1L) {
    cvmdata_abort(
      c(
        paste(
          "Dataset {.val {dataset}} exists in",
          "{length(groups)} groups: {.val {groups}}."
        ),
        "i" = "Pass {.arg group} explicitly to disambiguate."
      ),
      class = c("cvmdata_error_input_ambiguous", "cvmdata_error_input")
    )
  }
  groups
}

# Set of group slugs the package knows about. Used by
# `cvm_cache_clear(group = ...)` to validate user-supplied groups.
known_groups <- function() {
  sort(unique(schema_tree()$group))
}

# Set of dataset slugs known across all groups. Used by callers that
# previously inspected names(.dataset_group_map).
known_datasets <- function() {
  sort(unique(schema_tree()$dataset))
}
