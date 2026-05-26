# Skeleton-state tests for offering_fetch(). The function is exported
# in v0.1.0.9000 documenting the planned contract for the public-
# offering datasets; calls abort with cvmdata_error_input_group
# pointing at ROADMAP.md. Full implementation arrives in v0.7.

test_that("offering_fetch is exported", {
  expect_true(exists(
    "offering_fetch",
    mode = "function",
    envir = asNamespace("cvmdata"),
    inherits = FALSE
  ))
  expect_true("offering_fetch" %in% getNamespaceExports("cvmdata"))
})

test_that("offering_fetch has canonical signature", {
  fmls <- formals(offering_fetch)
  expect_named(
    fmls,
    c("dataset", "table", "offering", "date_range",
      "source", "on_error", "validate", "...")
  )
  expect_null(fmls$offering)
  expect_null(fmls$date_range)
  expect_null(fmls$source)
  expect_equal(fmls$on_error, "abort")
  expect_equal(fmls$validate, "strict")
})

test_that("offering_fetch aborts as skeleton with class hierarchy", {
  expect_error(
    offering_fetch("ofertas-publicas", "registradas"),
    class = "cvmdata_error_input_group"
  )
  expect_error(
    offering_fetch("ofertas-publicas", "registradas"),
    class = "cvmdata_error_input"
  )
  expect_error(
    offering_fetch("ofertas-publicas", "registradas"),
    class = "cvmdata_error"
  )
})

test_that("offering_fetch rejects unknown arguments via ...", {
  expect_error(
    offering_fetch("ofertas-publicas", "registradas", offerings = "X"),
    class = "cvmdata_error_input"
  )
  err <- tryCatch(
    offering_fetch("ofertas-publicas", "registradas", offerings = "X"),
    error = identity
  )
  expect_false("cvmdata_error_input_group" %in% class(err))
})

test_that("offering_fetch skeleton message points to the roadmap", {
  expect_error(
    offering_fetch("ofertas-publicas", "registradas"),
    regexp = "ROADMAP|v0\\.[4-8]"
  )
})
