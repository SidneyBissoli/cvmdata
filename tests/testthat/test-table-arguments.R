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
      rejects(check_period(2020L, NULL, NULL, s)),
      !a$yearly[[i]],
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
  cad <- paste("cad", c("companhias", "estrangeiras", "incentivadas"))
  expect_identical(paste(a$dataset, a$table)[a$as_of], cad)
  expect_identical(
    paste(a$dataset, a$table)[!a$yearly],
    c(
      cad,
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

# cvm_arguments() --------------------------------------------------------

# What cvm_fetch() does with a call, without the network: "input" when an
# argument check refuses it, "reached" when it gets past every check to
# the backend.
fetch_outcome <- function(...) {
  local_mocked_bindings(
    issuer_fetch_internal = function(...) {
      rlang::abort("reached", class = "test_reached_backend")
    },
    resolve_ticker_all_years = function(...) "00.000.000/0001-91",
    .env = asNamespace("cvmdata")
  )
  tryCatch(
    suppressWarnings(suppressMessages(cvm_fetch(...))),
    cvmdata_error_input = function(e) "input",
    test_reached_backend = function(e) "reached"
  )
}

# A valid value of each argument for this table.
argument_value <- function(argument, schema) {
  first <- schema$first_year %||% 2020L
  window <- list(
    from = paste0(first, "-01-01"),
    to = paste0(first, "-12-31")
  )
  switch(
    argument,
    cnpj = "00.000.000/0001-91",
    ticker = "PETR4",
    year = as.integer(first),
    from = window,
    to = window,
    as_of = "2020-01-01",
    basis = "ind",
    reading = "original",
    source = "cvm",
    on_error = "warn"
  )
}

test_that("cvm_arguments() states what cvm_fetch() does, for every table", {
  tree <- schema_tree()
  for (i in seq_len(nrow(tree))) {
    ds <- tree$dataset[[i]]
    tb <- tree$table[[i]]
    s <- load_schema(ds, tb)
    rules <- cvm_arguments(ds, tb)
    required <- rules$argument[rules$status == "required"]
    base <- list(dataset = ds, table = tb)
    for (r in required) {
      v <- argument_value(r, s)
      base <- c(base, if (is.list(v)) v else rlang::list2(!!r := v))
    }
    label <- paste0(ds, "/", tb)
    expect_identical(do.call(fetch_outcome, base), "reached", label = label)
    for (j in seq_len(nrow(rules))) {
      arg <- rules$argument[[j]]
      status <- rules$status[[j]]
      # The period is one choice: `year` or the `from`/`to` window.
      drop <- if (arg %in% c("year", "from", "to")) {
        c("year", "from", "to")
      } else {
        arg
      }
      if (status == "required") {
        expect_identical(
          do.call(fetch_outcome, base[!names(base) %in% drop]),
          "input",
          label = paste(label, arg, "left out")
        )
        next
      }
      v <- argument_value(arg, s)
      if (!is.list(v)) {
        v <- rlang::list2(!!arg := v)
      }
      call <- c(base[!names(base) %in% drop], v)
      expected <- if (status == "optional") "reached" else "input"
      expect_identical(
        do.call(fetch_outcome, call),
        expected,
        label = paste(label, arg, status)
      )
    }
  }
})

test_that("cvm_arguments() returns one row per argument with its status", {
  out <- cvm_arguments("dfp", "bpa")
  expect_s3_class(out, "tbl_df")
  expect_named(out, c("argument", "status", "values"))
  expect_identical(
    out$argument,
    c(
      "cnpj",
      "ticker",
      "year",
      "from",
      "to",
      "as_of",
      "basis",
      "reading",
      "source",
      "on_error"
    )
  )
  expect_in(out$status, c("required", "optional", "not allowed"))
  expect_identical(out$argument[out$status == "required"], "basis")
  expect_true(all(is.na(out$values[out$status == "not allowed"])))
  expect_identical(
    cvm_arguments("dfp", "bpa", group = "companhias"),
    out
  )
})

test_that("cvm_arguments() says what the coded values mean", {
  out <- cvm_arguments("dfp", "dre")
  values <- stats::setNames(out$values, out$argument)
  expect_match(values[["basis"]], "\"ind\" = parent company only")
  expect_match(values[["basis"]], "\"con\" = consolidated group")
  expect_match(values[["reading"]], "\"original\" = as first published")
  expect_match(values[["reading"]], "\"restated\" = as shown again")
})

test_that("cvm_arguments() describes years, registries and the mirror", {
  cad <- cvm_arguments("cad", "companhias")
  expect_identical(
    cad$status[cad$argument %in% c("year", "as_of")],
    c("not allowed", "optional")
  )
  ended <- cvm_arguments("fre", "endividamento")
  expect_identical(ended$status[ended$argument == "year"], "required")
  expect_match(ended$values[ended$argument == "year"], "^2010-2023")
  empty <- cvm_arguments("fca", "departamento_acionistas")
  expect_match(empty$values[empty$argument == "year"], "^2010-2023;")
  people <- cvm_arguments("fre", "responsavel")
  expect_match(people$values[people$argument == "source"], "not in the mirror")
})

test_that("cvm_arguments() refuses bad input", {
  expect_error(cvm_arguments("dfp"), "table")
  expect_error(
    cvm_arguments(c("dfp", "itr"), "bpa"),
    class = "cvmdata_error_input"
  )
  expect_error(cvm_arguments("dfp", "nada"), class = "cvmdata_error_input")
  expect_error(
    cvm_arguments("dfp", "bpa", group = "fundos"),
    class = "cvmdata_error_input"
  )
})
