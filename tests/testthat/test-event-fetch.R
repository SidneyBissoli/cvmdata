# Skeleton-state tests for event_fetch(). The function is exported in
# v0.1.0.9000 documenting the planned contract for the regulatory-
# event datasets; calls abort with cvmdata_error_input_group pointing
# at ROADMAP.md. Full implementation arrives in v0.8.

test_that("event_fetch is exported", {
  expect_true(exists(
    "event_fetch",
    mode = "function",
    envir = asNamespace("cvmdata"),
    inherits = FALSE
  ))
  expect_true("event_fetch" %in% getNamespaceExports("cvmdata"))
})

test_that("event_fetch has canonical signature", {
  fmls <- formals(event_fetch)
  expect_named(
    fmls,
    c("dataset", "table", "event", "date_range",
      "source", "on_error", "validate", "...")
  )
  expect_null(fmls$event)
  expect_null(fmls$date_range)
  expect_null(fmls$source)
  expect_equal(fmls$on_error, "abort")
  expect_equal(fmls$validate, "strict")
})

test_that("event_fetch aborts as skeleton with class hierarchy", {
  expect_error(
    event_fetch("sancionadora", "processos"),
    class = "cvmdata_error_input_group"
  )
  expect_error(
    event_fetch("sancionadora", "processos"),
    class = "cvmdata_error_input"
  )
  expect_error(
    event_fetch("sancionadora", "processos"),
    class = "cvmdata_error"
  )
})

test_that("event_fetch rejects unknown arguments via ...", {
  expect_error(
    event_fetch("sancionadora", "processos", events = "X"),
    class = "cvmdata_error_input"
  )
  err <- tryCatch(
    event_fetch("sancionadora", "processos", events = "X"),
    error = identity
  )
  expect_false("cvmdata_error_input_group" %in% class(err))
})

test_that("event_fetch skeleton message points to the roadmap", {
  expect_error(
    event_fetch("sancionadora", "processos"),
    regexp = "ROADMAP|v0\\.[4-8]"
  )
})
