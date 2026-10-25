# Tests for R/release.R: the option `cvmdata.mirror_release` and its
# public pair `cvm_release_get()` / `cvm_release_set()`.

test_that("cvm_release_get defaults to latest", {
  withr::local_options(cvmdata.mirror_release = NULL)
  expect_identical(cvm_release_get(), "latest")
})

test_that("cvm_release_set accepts latest and complete dates", {
  withr::local_options(cvmdata.mirror_release = NULL)
  expect_message(out <- cvm_release_set("2026-11-01"), "2026-11-01")
  expect_identical(out, "2026-11-01")
  expect_identical(cvm_release_get(), "2026-11-01")
  expect_identical(getOption("cvmdata.mirror_release"), "2026-11-01")

  expect_message(cvm_release_set(as.Date("2026-12-24")), "2026-12-24")
  expect_identical(cvm_release_get(), "2026-12-24")

  expect_message(cvm_release_set("latest"), "latest")
  expect_identical(cvm_release_get(), "latest")
})

test_that("cvm_release_set rejects what is neither latest nor a date", {
  withr::local_options(cvmdata.mirror_release = NULL)
  expect_error(cvm_release_set("2026-11"), class = "cvmdata_error_input")
  expect_error(cvm_release_set("2026-1-5"), class = "cvmdata_error_input")
  expect_error(cvm_release_set("yesterday"), class = "cvmdata_error_input")
  expect_error(cvm_release_set(""), class = "cvmdata_error_input")
  expect_error(cvm_release_set(NA_character_), class = "cvmdata_error_input")
  expect_error(cvm_release_set(20261101), class = "cvmdata_error_input")
  expect_error(
    cvm_release_set(c("2026-11-01", "2026-11-02")),
    class = "cvmdata_error_input"
  )
  expect_error(cvm_release_set(as.Date(NA)), class = "cvmdata_error_input")
  expect_identical(cvm_release_get(), "latest")
})

test_that("cvm_release_get validates an option set by hand", {
  withr::local_options(cvmdata.mirror_release = "soon")
  expect_error(cvm_release_get(), class = "cvmdata_error_input")
})
