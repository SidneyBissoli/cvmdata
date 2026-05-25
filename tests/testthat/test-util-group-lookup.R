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
