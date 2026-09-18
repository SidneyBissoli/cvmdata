# Contract between the schema YAMLs and the dictionary snapshot.
#
# The YAMLs under `inst/extdata/schemas/` are hand-written and are the
# source of truth. `data-raw/build-dictionary-snapshot.R` derives
# `inst/extdata/cvm_dictionary_snapshot.csv` from them: it follows each
# YAML's `cvm_dictionary_url` and, for `meta_status: missing`, copies
# `expected_field_names`. Nothing generates YAMLs from the snapshot --
# the dependency runs the other way -- so what keeps the two artefacts
# interchangeable for discovery is the set of invariants pinned here:
# every table has both, and the field count, META status and (for
# META-less tables) the field names agree. A YAML added without
# rebuilding the snapshot, or a snapshot rebuilt against a stale YAML,
# fails one of these.

snapshot_by_table <- function() {
  path <- system.file(
    "extdata", "cvm_dictionary_snapshot.csv", package = "cvmdata"
  )
  snap <- .read_dictionary_snapshot(path)
  split(snap, paste(snap$group, snap$dataset, snap$table, sep = "/"))
}

installed_schemas <- function() {
  tree <- schema_tree()
  tree$key <- paste(tree$group, tree$dataset, tree$table, sep = "/")
  tree
}

test_that("every schema YAML has snapshot rows and vice versa", {
  tree <- installed_schemas()
  snap <- snapshot_by_table()
  expect_gt(nrow(tree), 0L)
  expect_setequal(tree$key, names(snap))
})

test_that("expected_field_count equals the snapshot's row count", {
  tree <- installed_schemas()
  snap <- snapshot_by_table()
  for (i in seq_len(nrow(tree))) {
    schema <- load_schema(tree$dataset[i], tree$table[i], tree$group[i])
    expect_identical(
      as.integer(schema$expected_field_count),
      nrow(snap[[tree$key[i]]]),
      info = tree$key[i]
    )
  }
})

test_that("meta_status in the YAML agrees with every snapshot row", {
  tree <- installed_schemas()
  snap <- snapshot_by_table()
  for (i in seq_len(nrow(tree))) {
    schema <- load_schema(tree$dataset[i], tree$table[i], tree$group[i])
    yaml_status <- schema$meta_status %||% "available"
    expect_identical(
      unique(snap[[tree$key[i]]]$meta_status),
      yaml_status,
      info = tree$key[i]
    )
  }
})

test_that("META-less tables declare the snapshot's field names", {
  tree <- installed_schemas()
  snap <- snapshot_by_table()
  n_missing <- 0L
  for (i in seq_len(nrow(tree))) {
    schema <- load_schema(tree$dataset[i], tree$table[i], tree$group[i])
    if (!identical(schema$meta_status, "missing")) {
      next
    }
    n_missing <- n_missing + 1L
    expect_identical(
      as.character(schema$expected_field_names),
      snap[[tree$key[i]]]$campo_original,
      info = tree$key[i]
    )
  }
  # The 8 FRE tables without a CVM-published META (CLAUDE.md Sec. 7).
  expect_identical(n_missing, 8L)
})
