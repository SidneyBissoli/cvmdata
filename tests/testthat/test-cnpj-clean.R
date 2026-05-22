test_that("cnpj_clean strips punctuation", {
  expect_identical(cnpj_clean("12.345.678/0001-90"), "12345678000190")
  expect_identical(cnpj_clean("12345678000190"), "12345678000190")
})

test_that("cnpj_clean preserves NA", {
  expect_identical(
    cnpj_clean(c("12.345.678/0001-90", NA, "99.999.999/0001-91")),
    c("12345678000190", NA, "99999999000191")
  )
})

test_that("cnpj_clean rejects non-character input", {
  expect_error(cnpj_clean(12345678000190), class = "cvmdata_error_input")
})

test_that("cnpj_clean is vectorised", {
  input <- c("12.345.678/0001-90", "98.765.432/0001-10")
  expected <- c("12345678000190", "98765432000110")
  expect_identical(cnpj_clean(input), expected)
})

test_that("cnpj_format adds canonical punctuation", {
  expect_identical(
    cnpj_format("12345678000190"),
    "12.345.678/0001-90"
  )
  # Already-formatted input round-trips.
  expect_identical(
    cnpj_format("12.345.678/0001-90"),
    "12.345.678/0001-90"
  )
})

test_that("cnpj_format preserves NA", {
  expect_identical(
    cnpj_format(c("12345678000190", NA, "98765432000110")),
    c("12.345.678/0001-90", NA, "98.765.432/0001-10")
  )
})

test_that("cnpj_format is vectorised", {
  input <- c("12345678000190", "98.765.432/0001-10")
  expected <- c("12.345.678/0001-90", "98.765.432/0001-10")
  expect_identical(cnpj_format(input), expected)
})

test_that("cnpj_format returns NA + warns on non-14-digit input", {
  expect_warning(
    out <- cnpj_format("123"),
    class = "cvmdata_warn"
  )
  expect_identical(out, NA_character_)
})

test_that("cnpj_format mixed-validity vector returns NA only for invalids", {
  expect_warning(
    out <- cnpj_format(c("12345678000190", "123", NA, "98765432000110")),
    class = "cvmdata_warn"
  )
  expect_identical(
    out,
    c("12.345.678/0001-90", NA, NA, "98.765.432/0001-10")
  )
})

test_that("cnpj_format rejects non-character input", {
  expect_error(cnpj_format(12345678000190), class = "cvmdata_error_input")
})

test_that("cnpj_format is the inverse of cnpj_clean for valid input", {
  formatted <- c("12.345.678/0001-90", "98.765.432/0001-10")
  expect_identical(cnpj_format(cnpj_clean(formatted)), formatted)
})
