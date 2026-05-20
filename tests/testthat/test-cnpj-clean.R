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
