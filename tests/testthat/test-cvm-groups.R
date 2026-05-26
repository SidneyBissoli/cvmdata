# Tests for cvm_groups(). The function returns a static taxonomy table
# (see R/api-cvm-groups.R) with no I/O, so every assertion is a pure
# shape check.

test_that("cvm_groups returns 18 rows", {
  g <- cvm_groups()
  expect_s3_class(g, "tbl_df")
  expect_identical(nrow(g), 18L)
})

test_that("cvm_groups columns are (group, n_datasets, contract)", {
  g <- cvm_groups()
  expect_named(g, c("group", "n_datasets", "contract"))
  expect_type(g$group, "character")
  expect_type(g$n_datasets, "integer")
  expect_type(g$contract, "character")
})

test_that("cvm_groups rows are sorted alphabetically by group", {
  g <- cvm_groups()
  expect_identical(g$group, sort(g$group))
})

test_that("cvm_groups carries no duplicate group slugs", {
  g <- cvm_groups()
  expect_identical(length(unique(g$group)), nrow(g))
})

test_that("cvm_groups contract values are restricted to the 5 canonical", {
  g <- cvm_groups()
  expect_true(all(
    g$contract %in% c("issuer", "fund", "agent", "offering", "event")
  ))
  # Each contract has at least one group.
  expect_setequal(
    unique(g$contract),
    c("issuer", "fund", "agent", "offering", "event")
  )
})

test_that("cvm_groups n_datasets are positive integers", {
  g <- cvm_groups()
  expect_true(all(g$n_datasets > 0L))
  expect_true(all(g$n_datasets == as.integer(g$n_datasets)))
})

test_that("cvm_groups totals match the decision doc", {
  # The decision doc table (§1) enumerates 18 groups summing to 67
  # datasets across the CKAN portal. The doc prose says "76 datasets"
  # in two places, but the per-group counts sum to 67 -- treat the
  # table as the source of truth; the discrepancy is a doc bug worth
  # fixing in a follow-up, not in this regression test. The dominant
  # chunks are companhias (12), fundos-de-investimento (22) and
  # fundos-estruturados (10).
  g <- cvm_groups()
  expect_identical(sum(g$n_datasets), 67L)
  expect_identical(
    g$n_datasets[g$group == "companhias"], 12L
  )
  expect_identical(
    g$n_datasets[g$group == "fundos-de-investimento"], 22L
  )
  expect_identical(
    g$n_datasets[g$group == "fundos-estruturados"], 10L
  )
})

test_that("cvm_groups companhias maps to the issuer contract", {
  g <- cvm_groups()
  expect_identical(g$contract[g$group == "companhias"], "issuer")
})
