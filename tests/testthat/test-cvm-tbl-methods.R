# The `cvm_tbl` class and its six provenance attributes must survive the
# dplyr verbs and vctrs operations that keep the result a CVM table, and
# must be reconciled (not silently copied from the first input) when two
# tables of different provenance are bound. Measured 2026-10-25 against
# dplyr 1.2.1 / vctrs 0.7.3 / tibble 3.3.1 before the methods existed:
# group_by() dropped the class, the next verb dropped the attributes,
# and bind_rows() stamped x's provenance on y's rows.

skip_if_not_installed("dplyr")

attr_names <- c(
  "source",
  "fetched_at",
  "group",
  "dataset",
  "table",
  "package_version"
)

make_cvm_tbl <- function(source = "mirror", table = "bpa_ind", n = 6L) {
  df <- data.frame(
    cnpj_cia = rep(c("00.000.000/0001-91", "11.111.111/0001-11"), n / 2),
    cd_conta = as.character(seq_len(n)),
    vl_conta = as.numeric(seq_len(n)),
    stringsAsFactors = FALSE
  )
  cvm_attach_metadata(
    df,
    source = source,
    group = "companhias",
    dataset = "dfp",
    table = table
  )
}

# A copy of `x` with the class and the six attributes removed.
unclass_cvm <- function(x) {
  for (a in attr_names) {
    attr(x, a) <- NULL
  }
  class(x) <- setdiff(class(x), "cvm_tbl")
  x
}

expect_provenance <- function(out, template) {
  expect_s3_class(out, "cvm_tbl")
  for (a in attr_names) {
    expect_identical(
      attr(out, a, exact = TRUE),
      attr(template, a, exact = TRUE),
      info = a
    )
  }
  invisible(out)
}

test_that("single-table dplyr verbs keep class and attributes", {
  x <- make_cvm_tbl()
  expect_provenance(dplyr::filter(x, vl_conta > 2), x)
  expect_provenance(dplyr::mutate(x, dobro = vl_conta * 2), x)
  expect_provenance(dplyr::select(x, cnpj_cia, vl_conta), x)
  expect_provenance(dplyr::arrange(x, dplyr::desc(vl_conta)), x)
  expect_provenance(dplyr::slice(x, 1:2), x)
  expect_provenance(dplyr::rename(x, conta = cd_conta), x)
  expect_provenance(dplyr::distinct(x, cnpj_cia), x)
  expect_provenance(dplyr::count(x, cnpj_cia), x)
})

test_that("base subsetting keeps class and attributes", {
  x <- make_cvm_tbl()
  expect_provenance(x[1:3, ], x)
  expect_provenance(x[, 1:2], x)
  expect_provenance(x["vl_conta"], x)
  expect_provenance(head(x, 2), x)
  y <- x
  y$novo <- 1
  expect_provenance(y, x)
})

test_that("group_by keeps the class and the grouping", {
  x <- make_cvm_tbl()
  g <- dplyr::group_by(x, cnpj_cia)
  expect_provenance(g, x)
  expect_s3_class(g, "grouped_df")
  expect_identical(dplyr::group_vars(g), "cnpj_cia")
  expect_identical(
    class(g),
    c("cvm_tbl", "grouped_df", "tbl_df", "tbl", "data.frame")
  )
})

test_that("verbs after group_by keep class and attributes", {
  x <- make_cvm_tbl()
  g <- dplyr::group_by(x, cnpj_cia)

  s <- dplyr::summarise(g, total = sum(vl_conta))
  expect_provenance(s, x)
  expect_false(inherits(s, "grouped_df"))
  expect_identical(nrow(s), 2L)
  expect_identical(s$total, c(9, 12))

  m <- dplyr::mutate(g, n = dplyr::n())
  expect_provenance(m, x)
  expect_s3_class(m, "grouped_df")

  f <- dplyr::filter(g, vl_conta == max(vl_conta))
  expect_provenance(f, x)
  expect_identical(nrow(f), 2L)

  u <- dplyr::ungroup(g)
  expect_provenance(u, x)
  expect_false(inherits(u, "grouped_df"))
  expect_identical(class(u), class(x))

  kept <- dplyr::summarise(
    dplyr::group_by(x, cnpj_cia, cd_conta),
    total = sum(vl_conta)
  )
  expect_provenance(kept, x)
  expect_s3_class(kept, "grouped_df")

  partial <- dplyr::ungroup(dplyr::group_by(x, cnpj_cia, cd_conta), cd_conta)
  expect_provenance(partial, x)
  expect_identical(dplyr::group_vars(partial), "cnpj_cia")
})

test_that("column verbs and subsetting after group_by keep provenance", {
  x <- make_cvm_tbl()
  g <- dplyr::group_by(x, cnpj_cia)
  for (out in list(
    dplyr::select(g, cnpj_cia, vl_conta),
    dplyr::select(g, vl_conta),
    dplyr::arrange(g, dplyr::desc(vl_conta)),
    dplyr::rename(g, conta = cd_conta),
    dplyr::relocate(g, vl_conta),
    dplyr::distinct(g, cnpj_cia),
    dplyr::slice_head(g, n = 1),
    g[1:2, ],
    g[, 1:2],
    head(g, 2)
  )) {
    expect_provenance(out, x)
    expect_s3_class(out, "grouped_df")
  }
  # Selecting away the grouping column ungroups, as dplyr does.
  no_group <- g["vl_conta"]
  expect_provenance(no_group, x)
  expect_false(inherits(no_group, "grouped_df"))
  renamed <- g
  names(renamed)[2] <- "conta"
  expect_provenance(renamed, x)
  expect_identical(names(renamed)[2], "conta")
  expect_type(g[[3]], "double")
  dropped <- g[, 2, drop = TRUE]
  expect_type(dropped, "character")
})

test_that("summarise on an ungrouped cvm_tbl keeps the provenance", {
  x <- make_cvm_tbl()
  s <- dplyr::summarise(x, total = sum(vl_conta))
  expect_provenance(s, x)
  expect_identical(nrow(s), 1L)
  by <- dplyr::summarise(x, total = sum(vl_conta), .by = cnpj_cia)
  expect_provenance(by, x)
  expect_identical(nrow(by), 2L)
})

test_that("joins keep the provenance of the first argument", {
  x <- make_cvm_tbl()
  lookup <- tibble::tibble(
    cnpj_cia = c("00.000.000/0001-91", "11.111.111/0001-11"),
    nome = c("A", "B")
  )
  expect_provenance(dplyr::left_join(x, lookup, by = "cnpj_cia"), x)
  rev <- dplyr::left_join(lookup, x, by = "cnpj_cia")
  expect_false(inherits(rev, "cvm_tbl"))
  expect_null(attr(rev, "source", exact = TRUE))
})

test_that("bind_rows of equal provenance keeps it intact", {
  x <- make_cvm_tbl()
  y <- make_cvm_tbl()
  attr(y, "fetched_at") <- attr(x, "fetched_at")
  out <- dplyr::bind_rows(x, y)
  expect_provenance(out, x)
  expect_identical(nrow(out), 12L)
  expect_provenance(rbind(x, y), x)
  expect_provenance(vctrs::vec_rbind(x, y), x)
})

test_that("vec_rbind and rbind of divergent provenance say mixed", {
  x <- make_cvm_tbl(source = "mirror", table = "bpa_ind")
  y <- make_cvm_tbl(source = "portal", table = "bpa_con")
  older <- as.POSIXct("2026-01-01 00:00:00", tz = "UTC")
  attr(y, "fetched_at") <- older

  out <- vctrs::vec_rbind(x, y)
  expect_s3_class(out, "cvm_tbl")
  expect_identical(nrow(out), 12L)
  expect_identical(attr(out, "source"), "mixed")
  expect_identical(attr(out, "table"), "mixed")
  expect_identical(attr(out, "group"), "companhias")
  expect_identical(attr(out, "dataset"), "dfp")
  expect_identical(attr(out, "package_version"), attr(x, "package_version"))
  expect_equal(as.numeric(attr(out, "fetched_at")), as.numeric(older))

  # Order does not matter: y first gives the same reconciled provenance.
  rev <- vctrs::vec_rbind(y, x)
  expect_identical(attr(rev, "source"), "mixed")
  expect_equal(as.numeric(attr(rev, "fetched_at")), as.numeric(older))

  three <- rbind(x, y, make_cvm_tbl())
  expect_s3_class(three, "cvm_tbl")
  expect_identical(attr(three, "source"), "mixed")
  expect_identical(nrow(three), 18L)
})

test_that("bind_rows keeps the first input's provenance (dplyr's rule)", {
  x <- make_cvm_tbl(source = "mirror", table = "bpa_ind")
  y <- make_cvm_tbl(source = "portal", table = "bpa_con")
  out <- dplyr::bind_rows(x, y)
  expect_provenance(out, x)
  expect_identical(nrow(out), 12L)
  expect_provenance(dplyr::bind_rows(y, x), y)
})

test_that("mixed provenance prints as such", {
  x <- make_cvm_tbl(source = "mirror")
  y <- make_cvm_tbl(source = "portal")
  out <- rbind(x, y)
  msg <- capture.output(print(out), type = "message")
  expect_match(paste(msg, collapse = "\n"), "source: \"mixed\"", fixed = TRUE)
})

test_that("binding with a plain tibble follows dplyr's first-input rule", {
  x <- make_cvm_tbl()
  plain <- tibble::as_tibble(unclass_cvm(x))

  first <- dplyr::bind_rows(x, plain)
  expect_provenance(first, x)
  expect_identical(nrow(first), 12L)

  second <- dplyr::bind_rows(plain, x)
  expect_false(inherits(second, "cvm_tbl"))
  expect_null(attr(second, "source", exact = TRUE))
  expect_identical(class(second), class(plain))

  expect_identical(class(vctrs::vec_rbind(x, plain)), class(plain))
  expect_identical(class(vctrs::vec_rbind(plain, x)), class(plain))
  expect_identical(class(rbind(x, plain)), class(plain))

  df <- as.data.frame(unclass_cvm(x))
  expect_identical(class(vctrs::vec_rbind(x, df)), class(plain))
  expect_identical(class(vctrs::vec_rbind(df, x)), class(plain))
})

test_that("vec_cast to a cvm_tbl stamps the target's provenance", {
  x <- make_cvm_tbl()
  plain <- tibble::as_tibble(unclass_cvm(x))
  df <- as.data.frame(unclass_cvm(x))
  expect_provenance(vctrs::vec_cast(plain, x), x)
  expect_provenance(vctrs::vec_cast(df, x), x)
  expect_provenance(vctrs::vec_cast(x, x), x)
  expect_identical(class(vctrs::vec_cast(x, plain)), class(plain))
  expect_identical(class(vctrs::vec_cast(x, df)), "data.frame")
  expect_identical(class(vctrs::vec_ptype(x)), class(x))
})

test_that("operations that leave the CVM table drop the class", {
  x <- make_cvm_tbl()
  expect_type(dplyr::pull(x, vl_conta), "double")
  expect_type(x[["vl_conta"]], "double")
  expect_false(inherits(tibble::as_tibble(x), "cvm_tbl"))
  expect_false(inherits(as.data.frame(x), "cvm_tbl"))
})

test_that("printing a cvm_tbl with stripped attributes shows no header", {
  x <- make_cvm_tbl()
  for (a in attr_names) {
    attr(x, a) <- NULL
  }
  expect_s3_class(x, "cvm_tbl")
  msg <- capture.output(out <- capture.output(print(x)), type = "message")
  expect_identical(msg, character(0))
  expect_match(out[1], "A tibble")
})

test_that("merging provenance tolerates absent attributes", {
  x <- make_cvm_tbl()
  y <- make_cvm_tbl()
  attr(y, "fetched_at") <- NULL
  merged <- cvm_tbl_merge_attrs(x, y)
  expect_equal(merged$fetched_at, attr(x, "fetched_at"))
  attr(x, "fetched_at") <- NULL
  expect_null(cvm_tbl_merge_attrs(x, y)$fetched_at)
})
