# What the reader does with the companies the mirror left out of a count
# table (`privacy_omitted` of the sidecar; inst/etl/util-privacy.R).

omitted_rows <- function() {
  out <- data.frame(
    table = "empregado_PCD",
    year = c(2024L, 2025L),
    min = 10,
    companies = c(45, 459),
    companies_omitted = c(0, 173),
    people = c(1000, 3957181),
    people_omitted = c(0, 197859)
  )
  out$cnpj <- list(character(0L), c("11.222.333/0001-81", "22.333.444/0001-81"))
  out
}

omitted_result <- function() {
  cvm_attach_metadata(
    tibble::tibble(cnpj_companhia = "33.444.555/0001-81", quantidade_pcd = 12),
    source = "cvm",
    group = "companhias",
    dataset = "fre",
    table = "empregado_PCD"
  )
}

test_that("the sidecar entry is read whatever shape jsonlite gives it", {
  json <- paste0(
    '[{"table":"empregado_PCD","year":2025,"min":10,"companies":459,',
    '"companies_omitted":2,"people":100,"people_omitted":7,',
    '"cnpj":["11.222.333/0001-81","22.333.444/0001-81"]},',
    '{"table":"empregado_PCD","year":2024,"min":10,"companies":45,',
    '"companies_omitted":0,"people":50,"people_omitted":0,"cnpj":[]}]'
  )
  got <- mirror_normalise_omitted(jsonlite::fromJSON(json))
  expect_identical(got$year, c(2025L, 2024L))
  expect_identical(got$companies_omitted, c(2, 0))
  expect_identical(lengths(got$cnpj), c(2L, 0L))
  # two entries of the same length arrive as a matrix
  same <- sub('"cnpj":\\[\\]', '"cnpj":["a","b"]', json)
  expect_identical(
    mirror_normalise_omitted(jsonlite::fromJSON(same))$cnpj[[2L]],
    c("a", "b")
  )
  expect_null(mirror_normalise_omitted(NULL))
  expect_null(mirror_normalise_omitted(list()))
  expect_null(mirror_normalise_omitted(data.frame(table = "x")))
})

test_that("the backend notes the years it read and the fetcher takes them", {
  inventory <- structure(list(), omitted = omitted_rows())
  mirror_take_omitted()
  mirror_note_omitted(inventory, "empregado_PCD", 2025L)
  mirror_note_omitted(inventory, "empregado_PCD", 2025L)
  mirror_note_omitted(inventory, "outra", 2025L)
  got <- mirror_take_omitted()
  expect_identical(got$year, 2025L)
  expect_null(mirror_take_omitted())
  mirror_note_omitted(structure(list(), omitted = NULL), "empregado_PCD", 2025L)
  expect_null(mirror_take_omitted())
})

test_that("a read of a count table warns with the numbers and keeps them", {
  expect_snapshot(
    out <- note_privacy_omitted(omitted_result(), omitted_rows())
  )
  expect_warning(
    note_privacy_omitted(omitted_result(), omitted_rows()),
    class = "cvmdata_warn_privacy_omitted"
  )
  kept <- attr(out, "omitted")
  expect_identical(kept$year, c(2024L, 2025L))
  expect_identical(kept$companies_omitted, c(0, 173))
  expect_false("cnpj" %in% names(kept))
  # nothing omitted, nothing said
  quiet <- omitted_rows()[1L, ]
  expect_no_warning(got <- note_privacy_omitted(omitted_result(), quiet))
  expect_null(attr(got, "omitted"))
  expect_no_warning(note_privacy_omitted(omitted_result(), NULL))
})

test_that("asking for a company names it when it was left out", {
  expect_snapshot(
    out <- note_privacy_omitted(
      omitted_result(),
      omitted_rows(),
      cnpj = c("11222333000181", "33.444.555/0001-81")
    )
  )
  # the company asked for is in the table: the attribute stays, no warning
  expect_no_warning(
    got <- note_privacy_omitted(
      omitted_result(),
      omitted_rows(),
      cnpj = "33.444.555/0001-81"
    )
  )
  expect_identical(attr(got, "omitted")$companies_omitted, c(0, 173))
})

test_that("the header says it and the attribute survives dplyr", {
  skip_if_not_installed("dplyr")
  out <- suppressWarnings(note_privacy_omitted(
    omitted_result(),
    omitted_rows()
  ))
  attr(out, "fetched_at") <- as.POSIXct("2026-11-14 12:00:00", tz = "UTC")
  expect_snapshot(print(out))
  several <- omitted_rows()
  several$companies_omitted[1L] <- 3
  expect_match(
    print_omitted_field(several),
    "173 of 459 companies of 2025 are not in the mirror, and in 1 other",
    fixed = TRUE
  )
  expect_null(print_omitted_field(omitted_rows()[1L, ]))
  filtered <- dplyr::filter(out, quantidade_pcd > 1)
  expect_identical(attr(filtered, "omitted"), attr(out, "omitted"))
  plain <- omitted_result()
  expect_null(attr(dplyr::filter(plain, quantidade_pcd > 1), "omitted"))
})
