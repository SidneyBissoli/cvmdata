# The help section "Arguments by table" of cvm_fetch() is generated from
# the same predicates the argument checks use. These tests hold the two
# together for every installed table, then pin the rendered text.

rejects <- function(expr) {
  inherits(
    tryCatch(
      {
        force(expr)
        NULL
      },
      cvmdata_error_input = function(e) e
    ),
    "cvmdata_error_input"
  )
}

test_that("the documented rule is the one every check enforces", {
  a <- table_arguments()
  expect_gt(nrow(a), 0L)
  for (i in seq_len(nrow(a))) {
    s <- load_schema(a$dataset[[i]], a$table[[i]])
    label <- paste0(a$dataset[[i]], "/", a$table[[i]])
    expect_identical(rejects(check_basis("ind", s)), !a$basis[[i]], label)
    expect_identical(rejects(check_basis(NULL, s)), a$basis[[i]], label)
    expect_identical(
      rejects(check_reading("original", s)),
      !a$reading[[i]],
      label
    )
    expect_identical(
      rejects(check_as_of("2020-01-01", s)),
      !a$as_of[[i]],
      label
    )
    expect_identical(
      rejects(check_period(NULL, "2020-01-01", "2020-12-31", s)),
      !a$yearly[[i]],
      label
    )
    expect_identical(
      rejects(check_versioned_table(s)),
      !a$versions[[i]],
      label
    )
  }
})

test_that("the rule follows the measured coverage", {
  a <- table_arguments()
  statements <- c("bpa", "bpp", "dfc_md", "dfc_mi", "dmpl", "dra", "dre", "dva")
  with_basis <- a[a$basis, ]
  expect_setequal(
    paste(with_basis$dataset, with_basis$table),
    c(
      paste("dfp", statements),
      paste("itr", statements)
    )
  )
  expect_identical(a$reading, a$basis)
  expect_identical(paste(a$dataset, a$table)[a$as_of], "cad companhias")
  expect_identical(
    paste(a$dataset, a$table)[!a$yearly],
    c(
      "cad companhias",
      paste(
        "recompra_acoes",
        c("intermediarios", "quantidades", "recompra_acoes")
      )
    )
  )
  expect_identical(
    paste(a$dataset, a$table)[!is.na(a$issuer_via)],
    paste("recompra_acoes", c("intermediarios", "quantidades"))
  )
})

test_that("dataset lists join with commas and a final 'and'", {
  expect_identical(doc_join_and("a"), "a")
  expect_identical(doc_join_and(c("a", "b")), "a and b")
  expect_identical(doc_join_and(c("a", "b", "c")), "a, b and c")
  df <- data.frame(
    dataset = c("dfp", "itr", "cad"),
    table = c("bpa", "bpa", "companhias")
  )
  expect_identical(
    doc_table_list(df),
    "`cad`: `companhias`; `dfp` and `itr`: `bpa`"
  )
})

# A change here means a schema changed what an argument applies to: run
# devtools::document() so the help of cvm_fetch() says the same, then
# accept the snapshot.
test_that("the rendered help section is current", {
  expect_snapshot(cat(doc_arguments_by_table(), sep = "\n"))
})
