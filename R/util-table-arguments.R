# Which arguments of `cvm_fetch()` and `cvm_versions()` apply to a
# table, read from its schema. The argument checks (`check_basis()`,
# `check_reading()`, `check_as_of()`, `check_period()`,
# `check_versioned_table()`) and the help section "Arguments by table"
# of `cvm_fetch()` share these predicates, so the rule the help states
# is the rule the checks enforce.

# Individual/consolidated variants: `basis` is required.
table_has_basis <- function(schema) {
  !is.null(schema$cvm_file_pattern_variants)
}

# Two readings per exercise (`ordem_exerc`): `reading` applies.
table_has_readings <- function(schema) {
  "ordem_exerc" %in% dictionary_fields(schema)
}

# Registration and cancellation dates declared in the YAML: `as_of`
# applies.
table_is_registry <- function(schema) {
  !is.null(schema$as_of$registered) && !is.null(schema$as_of$cancelled)
}

# One file per year: `year` and `from`/`to` apply.
table_is_yearly <- function(schema) {
  identical(schema$temporal_partitioning %||% "none", "yearly")
}

# The `keep_latest_version` transformation of the table, or NULL: only
# such a table has superseded versions for `cvm_versions()`.
table_version_tx <- function(schema) {
  for (tx in schema$transformations) {
    if (identical(tx$action, "keep_latest_version")) {
      return(tx)
    }
  }
  NULL
}

# One row per argument of `cvm_fetch()` that depends on the table or
# selects rows, with its status for this table ("required", "optional"
# or "not allowed") and the values it takes. Built on the predicates
# above, the ones the argument checks enforce. The engine of
# `cvm_arguments()`.
fetch_argument_rules <- function(schema) {
  yearly <- table_is_yearly(schema)
  first <- schema$first_year
  last <- schema$last_year
  empty <- schema$empty_from
  years <- if (!is.null(last)) {
    paste0(first, "-", last)
  } else if (!is.null(empty)) {
    paste0(first, "-", as.integer(empty) - 1L)
  } else {
    paste0(first, " onwards")
  }
  year_status <- if (!yearly) {
    "not allowed"
  } else if (!is.null(last)) {
    "required"
  } else {
    "optional"
  }
  year_values <- if (!yearly) {
    NA_character_
  } else if (!is.null(last)) {
    paste0(years, "; or `from`/`to` instead")
  } else {
    paste0(years, "; NULL = latest year")
  }
  window <- if (yearly) {
    "full date (\"YYYY-MM-DD\"); `from` and `to` together, not with `year`"
  } else {
    NA_character_
  }
  allowed <- function(x) if (x) "optional" else "not allowed"
  source_values <- if (isFALSE(schema$mirror)) {
    "\"cvm\" (not in the mirror: read from the CVM)"
  } else {
    "\"mirror\", \"cvm\"; NULL = session default"
  }
  tibble::tibble(
    argument = c(
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
    ),
    status = c(
      "optional",
      "optional",
      year_status,
      allowed(yearly),
      allowed(yearly),
      allowed(table_is_registry(schema)),
      if (table_has_basis(schema)) "required" else "not allowed",
      allowed(table_has_readings(schema)),
      "optional",
      "optional"
    ),
    values = c(
      "CNPJ, with or without punctuation",
      "B3 ticker, e.g. \"PETR4\"",
      year_values,
      window,
      window,
      if (table_is_registry(schema)) "full date (\"YYYY-MM-DD\")" else NA,
      if (table_has_basis(schema)) "\"ind\", \"con\" or both" else NA,
      if (table_has_readings(schema)) {
        "\"original\", \"restated\" or both"
      } else {
        NA
      },
      source_values,
      "\"abort\", \"warn\""
    )
  )
}

# One row per table of the installed schema tree with the arguments
# that apply to it.
table_arguments <- function() {
  tree <- schema_tree()
  rows <- lapply(seq_len(nrow(tree)), function(i) {
    s <- load_schema(tree$dataset[[i]], tree$table[[i]], tree$group[[i]])
    data.frame(
      dataset = s$dataset,
      table = s$table,
      yearly = table_is_yearly(s),
      first_year = as.integer(s$first_year %||% NA_integer_),
      empty_from = as.integer(s$empty_from %||% NA_integer_),
      last_year = as.integer(s$last_year %||% NA_integer_),
      basis = table_has_basis(s),
      reading = table_has_readings(s),
      as_of = table_is_registry(s),
      versions = !is.null(table_version_tx(s)),
      issuer_via = s$issuer_via$table %||% NA_character_,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  out[order(out$dataset, out$table, method = "radix"), , drop = FALSE]
}

# "`dfp` and `itr`: `bpa`, `bpp`" -- the tables of `df`, datasets with
# the same set of tables written once.
doc_table_list <- function(df) {
  by_ds <- split(df$table, df$dataset)
  sets <- vapply(
    by_ds,
    function(t) paste(sort(t, method = "radix"), collapse = ","),
    ""
  )
  parts <- vapply(
    unique(sets),
    function(set) {
      ds <- names(sets)[sets == set]
      tables <- strsplit(set, ",", fixed = TRUE)[[1L]]
      paste0(
        doc_join_and(paste0("`", ds, "`")),
        ": ",
        paste0("`", tables, "`", collapse = ", ")
      )
    },
    ""
  )
  paste(parts, collapse = "; ")
}

# "`fca/x` (2020)": one entry per row, with the year in `col`.
doc_table_years <- function(df, col) {
  paste0(
    "`",
    df$dataset,
    "/",
    df$table,
    "` (",
    df[[col]],
    ")",
    collapse = ", "
  )
}

# Markdown body of the help section "Arguments by table" of
# `cvm_fetch()`, rendered by roxygen at document time.
doc_arguments_by_table <- function() {
  a <- table_arguments()
  yearly <- a[a$yearly, , drop = FALSE]
  ds_first <- tapply(yearly$first_year, yearly$dataset, min)
  late <- yearly[yearly$first_year > ds_first[yearly$dataset], , drop = FALSE]
  empty <- a[!is.na(a$empty_from), , drop = FALSE]
  ended <- a[!is.na(a$last_year), , drop = FALSE]
  c(
    paste0(
      "Which arguments apply depends on the table. The rules below are ",
      "generated from the package's table schemas, the same ones the ",
      "argument checks read, for the ",
      nrow(a),
      " tables in ",
      length(unique(a$dataset)),
      " datasets. An argument passed to a ",
      "table it does not apply to aborts with `cvmdata_error_input` ",
      "before anything is downloaded; nothing is silently ignored. ",
      "[cvm_arguments()] gives the same rules for one table, as a tibble."
    ),
    "",
    paste0(
      "* `year` and `from`/`to`: every table published one file per ",
      "year. Not for ",
      doc_table_list(a[!a$yearly, , drop = FALSE]),
      ", a single snapshot. A `year` before the table's first year is ",
      "refused (a `from`/`to` window is cut to it instead). Most ",
      "tables start with their dataset; these start ",
      "later: ",
      doc_table_years(late, "first_year"),
      "."
    ),
    if (nrow(empty)) {
      paste0(
        "* Years from which the CVM publishes the file with its header ",
        "only are refused too: ",
        doc_table_years(empty, "empty_from"),
        "."
      )
    },
    if (nrow(ended)) {
      paste0(
        "* Tables the CVM stopped publishing (last year in parentheses) ",
        "refuse later years and require an explicit `year`, since ",
        "`year = NULL` would mean the dataset's latest year: ",
        doc_table_years(ended, "last_year"),
        "."
      )
    },
    paste0(
      "* `basis`: required, with no default, in ",
      doc_table_list(a[a$basis, , drop = FALSE]),
      ". Refused in every other table."
    ),
    paste0(
      "* `reading`: only in ",
      doc_table_list(a[a$reading, , drop = FALSE]),
      " (the tables with `ordem_exerc`)."
    ),
    paste0(
      "* `as_of`: only in ",
      doc_table_list(a[a$as_of, , drop = FALSE]),
      "."
    ),
    if (!all(is.na(a$issuer_via))) {
      via <- a[!is.na(a$issuer_via), , drop = FALSE]
      paste0(
        "* `cnpj`/`ticker` in a table without an issuer column: ",
        doc_table_list(via),
        " keep the rows linked to the issuer's rows in ",
        doc_join_and(paste0(
          "`",
          unique(via$dataset),
          "/",
          unique(via$issuer_via),
          "`"
        )),
        "."
      )
    },
    paste0(
      "* [cvm_versions()]: every table except ",
      doc_table_list(a[!a$versions, , drop = FALSE]),
      ", which already return every row the CVM publishes."
    )
  )
}

# "a", "a and b", "a, b and c".
doc_join_and <- function(x) {
  if (length(x) < 2L) {
    return(x)
  }
  paste(toString(x[-length(x)]), "and", x[length(x)])
}
