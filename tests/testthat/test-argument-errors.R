# Argument checks whose messages no other test reads: each one must stop
# with the class of an input error before touching the cache or the
# network.

test_that("cvm_cache_clear() refuses malformed arguments", {
  withr::local_options(cvmdata.cache_dir = withr::local_tempdir())
  refuse <- function(...) {
    expect_error(
      cvm_cache_clear(..., confirm = FALSE),
      class = "cvmdata_error_input"
    )
  }
  refuse("raw", year = 2024L)
  refuse("raw", dataset = 1L)
  refuse("raw", dataset = c("dfp", "itr"))
  refuse("raw", group = 1L)
  refuse("raw", dataset = "dfp", year = "2024")
  refuse("raw", dataset = "dfp", year = c(2023L, 2024L))
  expect_error(
    cvm_cache_clear("raw", confirm = "yes"),
    class = "cvmdata_error_input"
  )
})

test_that("cvm_cache_set_path() refuses a path that is not one string", {
  expect_error(cvm_cache_set_path(1L), class = "cvmdata_error_input")
  expect_error(cvm_cache_set_path(""), class = "cvmdata_error_input")
  expect_error(cvm_cache_set_path(c("a", "b")), class = "cvmdata_error_input")
})

test_that("cvm_dataset_years() says so when a dataset has no table", {
  local_mocked_bindings(cvm_tables = function(...) character())
  expect_error(cvm_dataset_years("dfp"), class = "cvmdata_error_input")
})
