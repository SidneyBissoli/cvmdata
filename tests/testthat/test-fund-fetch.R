# Skeleton-state tests for fund_fetch(). The function is exported in
# v0.1.0.9000 documenting the planned contract for the fund-class
# datasets; calls abort with cvmdata_error_input_group pointing at
# ROADMAP.md. Full implementation arrives in v0.4-v0.6.

test_that("fund_fetch is exported", {
  expect_true(exists(
    "fund_fetch",
    mode = "function",
    envir = asNamespace("cvmdata"),
    inherits = FALSE
  ))
  expect_true("fund_fetch" %in% getNamespaceExports("cvmdata"))
})

test_that("fund_fetch has canonical signature", {
  fmls <- formals(fund_fetch)
  expect_named(
    fmls,
    c("dataset", "table", "fund", "date",
      "source", "on_error", "validate", "...")
  )
  expect_null(fmls$fund)
  expect_null(fmls$date)
  expect_null(fmls$source)
  expect_equal(fmls$on_error, "abort")
  expect_equal(fmls$validate, "strict")
})

test_that("fund_fetch aborts as skeleton with class hierarchy", {
  expect_error(
    fund_fetch("fi", "cad"),
    class = "cvmdata_error_input_group"
  )
  expect_error(
    fund_fetch("fi", "cad"),
    class = "cvmdata_error_input"
  )
  expect_error(
    fund_fetch("fi", "cad"),
    class = "cvmdata_error"
  )
})

test_that("fund_fetch rejects unknown arguments via ...", {
  expect_error(
    fund_fetch("fi", "cad", funds = "12.345.678/0001-90"),
    class = "cvmdata_error_input"
  )
  # The ... validator fires before the skeleton abort, so the
  # _group subclass is NOT attached.
  err <- tryCatch(
    fund_fetch("fi", "cad", funds = "X"),
    error = identity
  )
  expect_false("cvmdata_error_input_group" %in% class(err))
})

test_that("fund_fetch skeleton message points to the roadmap", {
  expect_error(
    fund_fetch("fi", "cad"),
    regexp = "ROADMAP|v0\\.[4-8]"
  )
})
