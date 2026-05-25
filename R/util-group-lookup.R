# Lookup table mapping dataset id to CKAN group. Internal-only; never
# exported. v0.1.0.9000 ships with the four datasets of the
# `companhias` group; Session 05 will replace this constant by a
# schema-driven lookup once schemas move to
# `inst/extdata/schemas/<group>/<dataset>/`.

# Single source of truth on the consumer side. Keep in sync with the
# schema layout when Session 05 lands.
.dataset_group_map <- c(
  cad = "companhias",
  dfp = "companhias",
  itr = "companhias",
  fre = "companhias"
)

# Resolve a dataset id to its CKAN group. Aborts with
# `cvmdata_error_internal` for unknown datasets so callers never
# silently land on an empty group string.
dataset_group <- function(dataset) {
  if (!is.character(dataset) || length(dataset) != 1L ||
        is.na(dataset) || !nzchar(dataset)) {
    cvmdata_abort(
      c("{.arg dataset} must be a single non-empty string."),
      class = "cvmdata_error_internal"
    )
  }
  if (!dataset %in% names(.dataset_group_map)) {
    cvmdata_abort(
      c(
        "Unknown dataset {.val {dataset}}; cannot resolve group.",
        "i" = paste(
          "Known datasets in v0.1.0.9000:",
          "{.val {names(.dataset_group_map)}}."
        )
      ),
      class = "cvmdata_error_internal"
    )
  }
  unname(.dataset_group_map[[dataset]])
}

# Set of group slugs the package knows about. Used by
# `cvm_cache_clear(group = ...)` to validate user-supplied groups.
known_groups <- function() {
  unique(unname(.dataset_group_map))
}
