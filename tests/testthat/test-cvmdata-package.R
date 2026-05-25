# Placeholder test ensuring the package can be loaded and queried.
# Substantive tests for `issuer_fetch("cad", "companhias")` and
# `load_schema()` are added in Session 2 of the implementation
# roadmap.

test_that("package metadata is accessible", {
  expect_no_error(utils::packageVersion("cvmdata"))
  expect_match(utils::packageDescription("cvmdata")$Package, "^cvmdata$")
})
