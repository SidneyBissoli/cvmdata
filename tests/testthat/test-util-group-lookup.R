# Unit tests for the internal dataset_group() lookup.

test_that("dataset_group() resolves the four v0.1 datasets to companhias", {
  expect_identical(dataset_group("cad"), "companhias")
  expect_identical(dataset_group("dfp"), "companhias")
  expect_identical(dataset_group("itr"), "companhias")
  expect_identical(dataset_group("fre"), "companhias")
})

test_that("dataset_group() aborts on unknown dataset", {
  expect_error(
    dataset_group("fundos"),
    class = "cvmdata_error_internal"
  )
})

test_that("dataset_group() aborts on bad input types", {
  expect_error(
    dataset_group(NULL),
    class = "cvmdata_error_internal"
  )
  expect_error(
    dataset_group(c("cad", "dfp")),
    class = "cvmdata_error_internal"
  )
  expect_error(
    dataset_group(NA_character_),
    class = "cvmdata_error_internal"
  )
  expect_error(
    dataset_group(""),
    class = "cvmdata_error_internal"
  )
  expect_error(
    dataset_group(42L),
    class = "cvmdata_error_internal"
  )
})

test_that("known_groups() returns the deduplicated group slugs", {
  expect_identical(known_groups(), "companhias")
})

test_that("known_datasets() lists every covered dataset", {
  expect_setequal(
    known_datasets(),
    c("cad", "cgvn", "dfp", "fca", "fre", "itr", "vlmo")
  )
})

test_that("dataset_group() aborts ambiguous when dataset is in 2 groups", {
  fixture_root <- testthat::test_path("fixtures", "schemas-ambiguous")
  withr::local_options(cvmdata.schema_root = fixture_root)
  expect_error(
    dataset_group("fakedata"),
    class = "cvmdata_error_input_ambiguous"
  )
})

test_that("known_groups() reflects fixture overrides", {
  fixture_root <- testthat::test_path("fixtures", "schemas-ambiguous")
  withr::local_options(cvmdata.schema_root = fixture_root)
  expect_setequal(known_groups(), c("g1", "g2"))
})
