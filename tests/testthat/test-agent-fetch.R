# Skeleton-state tests for agent_fetch(). The function is exported in
# v0.1.0.9000 documenting the planned contract for the registered-
# agent datasets; calls abort with cvmdata_error_input_group pointing
# at ROADMAP.md. Full implementation arrives in v0.7.

test_that("agent_fetch is exported", {
  expect_true(exists(
    "agent_fetch",
    mode = "function",
    envir = asNamespace("cvmdata"),
    inherits = FALSE
  ))
  expect_true("agent_fetch" %in% getNamespaceExports("cvmdata"))
})

test_that("agent_fetch has canonical signature", {
  fmls <- formals(agent_fetch)
  expect_named(
    fmls,
    c("dataset", "table", "agent", "as_of",
      "source", "on_error", "validate", "...")
  )
  expect_null(fmls$agent)
  expect_null(fmls$as_of)
  expect_null(fmls$source)
  expect_equal(fmls$on_error, "abort")
  expect_equal(fmls$validate, "strict")
})

test_that("agent_fetch aborts as skeleton with class hierarchy", {
  expect_error(
    agent_fetch("administradores", "cadastro"),
    class = "cvmdata_error_input_group"
  )
  expect_error(
    agent_fetch("administradores", "cadastro"),
    class = "cvmdata_error_input"
  )
  expect_error(
    agent_fetch("administradores", "cadastro"),
    class = "cvmdata_error"
  )
})

test_that("agent_fetch rejects unknown arguments via ...", {
  expect_error(
    agent_fetch("administradores", "cadastro", agents = "X"),
    class = "cvmdata_error_input"
  )
  err <- tryCatch(
    agent_fetch("administradores", "cadastro", agents = "X"),
    error = identity
  )
  expect_false("cvmdata_error_input_group" %in% class(err))
})

test_that("agent_fetch skeleton message points to the roadmap", {
  expect_error(
    agent_fetch("administradores", "cadastro"),
    regexp = "ROADMAP|v0\\.[4-8]"
  )
})
