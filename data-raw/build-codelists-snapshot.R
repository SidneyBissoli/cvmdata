#!/usr/bin/env Rscript
# data-raw/build-codelists-snapshot.R
#
# Reproducible generator for `inst/extdata/cvm_codelists_snapshot.csv`.
# Captures the categorical value domains for columns in the CVM open
# datasets covered by `cvmdata`. Embedding the snapshot lets users
# (and downstream code) query codelists offline via cvm_codelist().
#
# Usage (from package root):
#   Rscript data-raw/build-codelists-snapshot.R           # dry run
#   Rscript data-raw/build-codelists-snapshot.R --write   # persists CSV
#
# Inclusion criteria (Sessão 3.4 — see CLAUDE.md §9.2):
#   1. Dictionary-driven: columns whose `dominio` enumerates values
#      via `/` or `|` separators (captures S/N, PF/PJ).
#   2. Cardinality-driven: columns with `tipo_dados = varchar` and
#      `tamanho < 200` whose distinct count over EVERY published year
#      is ≤ 50 (or listed in `.CARDINALITY_EXCEPTIONS`), EXCLUDING:
#        - identifier columns matching the reader's
#          `.identifier_patterns` (cnpj, cd_cvm, codigo_cvm, cep,
#          tel, ddd, cpf, id_doc, id_documento, versao);
#        - `^cd_` prefix (e.g. cd_conta — accounting codes with very
#          large universes, low cardinality in a single-year sample
#          is sampling bias);
#        - `^nome_` prefix (proper names / corporate denominations —
#          PII or free text, not categorical).
# Tables with `meta_status: missing` are excluded.
#
# Sampling scope: every published year (owner's decision, 2026-11-01).
# Until then the latest year alone was sampled, and on 2026-05-29 that
# was a 2026 with five months of filings (the DFP had one): measured on
# 2026-11-01 over every year, 13 of the 178 columns were free text
# (auditor names, download links; 66 to 14,013 values) and 49 more
# lacked values (fca/pais_estrangeiro_negociacao/pais: 5 of 31).
# Values are read from the mirror, the package's own reading of the
# CVM CSVs; a table the mirror does not carry yet is read from the CVM
# ZIPs. Each value carries the
# first and last year it was observed in (NA: a dominio value never
# observed, or a non-yearly table).
#
# `--write` refuses to drop a (group, dataset, table, campo) present in
# the committed snapshot; pass `--allow-drop` when the CVM really
# retired the column.

suppressPackageStartupMessages({
  devtools::load_all(quiet = TRUE)
  library(dplyr)
  library(readr)
  library(tibble)
  library(cli)
})

`%||%` <- function(a, b) if (is.null(a)) b else a

# --- thresholds (Sessão 3.4) -----------------------------------------

.MAX_TAMANHO <- 200L # varchar fields wider than this are free text
.MAX_CARDINALITY <- 50L # hard cap on distinct values for a codelist
# Closed classifications above the cap, kept on purpose. Measured on
# 2026-11-01 over every year: fca/geral/setor_atividade is the CVM's
# sector classification, 66 values (53 to 60 a year); the 12 other
# columns above 50 were free text (owner's decision, 2026-11-01).
.CARDINALITY_EXCEPTIONS <- c("companhias/fca/geral/setor_atividade")
.FREE_TEXT_DOMAINS <- c(
  "Alfanumérico",
  "Numérico",
  "Númerico",
  "AAAA-MM-DD"
)
# Free-text / identifier columns to exclude from cardinality promotion.
# Mirrors the reader's identifier classification in R/util-csv-cvm.R
# (`.identifier_prefixes` + `.identifier_exact`) and adds purely
# textual prefixes (proper names, descriptions, addresses) that the
# reader does NOT force to character but that are also not codelists.
# Kept in sync with the reader by manual review when either side
# changes — they are correlated but not identical (the reader cares
# about preserving leading zeros; this list cares about excluding
# free-text and high-universe codes from codelist promotion).
.EXCLUDE_PATTERNS <- c(
  # Reader-aligned identifier prefixes (v0.2: broadened from
  # `^codigo_cvm` to `^codigo_`, from `^id_doc`/`^id_documento` to
  # `^id_`, plus new `^ddi_` and `^protocolo`).
  "^cnpj",
  "^cpf",
  "^codigo_",
  "^cd_",
  "^cep",
  "^ddi_",
  "^ddd_",
  "^id_",
  "^protocolo",
  # Reader-aligned identifier exact-match.
  "^versao$",
  "^tel$",
  "^tel_resp$",
  "^fax$",
  "^fax_resp$",
  "^caixa_postal$",
  # Free-text prefixes the reader doesn't touch but that are not
  # codelists either.
  "^nome_",
  "^denom_",
  "^ds_",
  "^email",
  "^logradouro",
  "^compl",
  "^bairro",
  "^mun($|_)",
  "^municipio_"
)

is_excluded_column <- function(col) {
  any(vapply(
    .EXCLUDE_PATTERNS,
    function(p) {
      grepl(p, col, perl = TRUE)
    },
    logical(1L)
  ))
}

# --- helpers ----------------------------------------------------------

is_enumerated_domain <- function(dominio) {
  if (is.null(dominio) || is.na(dominio) || !nzchar(dominio)) {
    return(FALSE)
  }
  if (dominio %in% .FREE_TEXT_DOMAINS) {
    return(FALSE)
  }
  grepl("[/|]", dominio)
}

parse_enum_values <- function(dominio) {
  parts <- strsplit(dominio, "[/|]", perl = TRUE)[[1L]]
  parts <- trimws(parts)
  unique(parts[nzchar(parts)])
}

# Wrap a noisy operation so readr's parsing-warning chatter does not
# clutter the dry-run log. Genuine errors still propagate.
quietly <- function(expr) {
  withCallingHandlers(
    expr,
    warning = function(w) invokeRestart("muffleWarning")
  )
}

# --- observations: every year ------------------------------------------

# Distinct values of `columns` in every published year of one table, as
# a tibble (campo, value, year). Read from the mirror, which is the
# package's own reading of the CVM CSVs (both report types). A table the
# mirror does not carry yet (a schema added on a branch) is read from
# the CVM ZIPs year by year. Non-yearly tables give year = NA.
observe_table <- function(dataset, table, columns) {
  obs <- observe_mirror(dataset, table, columns)
  if (is.null(obs)) {
    cli::cli_alert_info(
      "{dataset}/{table}: not in the mirror; reading the CVM ZIPs."
    )
    obs <- observe_cvm(dataset, table, columns)
  }
  clean_observations(obs)
}

observe_mirror <- function(dataset, table, columns) {
  schema <- load_schema(dataset, table)
  # A dataset added on a branch has no release yet: the GitHub API
  # answers 404 for its tag, and the table is read from the CVM. Any
  # other failure stops the table, not silently swapped for the CVM.
  inventory <- tryCatch(
    cvmdata:::mirror_list_assets(
      schema$group,
      dataset,
      release = cvm_release_get()
    ),
    cvmdata_error_http = function(e) {
      if (!grepl("HTTP 404", conditionMessage(e), fixed = TRUE)) {
        stop(e)
      }
      NULL
    }
  )
  if (is.null(inventory)) {
    return(NULL)
  }
  assets <- cvmdata:::filter_mirror_assets(inventory, table, kind = "current")
  if (!nrow(assets)) {
    return(NULL)
  }
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  parts <- lapply(seq_len(nrow(assets)), function(i) {
    path <- cvmdata:::mirror_fetch_to_l3(
      url = assets$url[[i]],
      dataset = dataset,
      table = table,
      year = assets$year[[i]],
      report_type = assets$report_type[[i]],
      sha256 = assets$sha256[[i]] %||% NA_character_,
      size = assets$size_bytes[[i]] %||% NA_integer_
    )
    src <- sprintf("read_parquet(%s)", cvmdata:::mirror_quote_sql(path))
    have <- DBI::dbGetQuery(
      con,
      sprintf("DESCRIBE SELECT * FROM %s", src)
    )$column_name
    cols <- intersect(columns, have)
    if (!length(cols)) {
      return(NULL)
    }
    sql <- paste(
      sprintf(
        "SELECT DISTINCT '%s' AS campo, CAST(\"%s\" AS VARCHAR) AS value FROM %s",
        cols,
        cols,
        src
      ),
      collapse = " UNION ALL "
    )
    out <- DBI::dbGetQuery(con, sql)
    out$year <- rep(assets$year[[i]], nrow(out))
    out
  })
  dplyr::bind_rows(parts)
}

observe_cvm <- function(dataset, table, columns) {
  schema <- load_schema(dataset, table)
  yearly <- identical(schema$temporal_partitioning %||% "none", "yearly")
  years <- if (yearly) cvm_dataset_years(dataset) else NA_integer_
  report_types <- if (length(schema$cvm_file_pattern_variants %||% list())) {
    list("ind", "con")
  } else {
    list(NULL)
  }
  parts <- list()
  for (year in years) {
    for (rt in report_types) {
      # A year outside the table's span or a CSV the ZIP lacks is a
      # cvmdata_error: that year has nothing to observe. Said out loud,
      # so an HTTP failure is not mistaken for an absent year.
      path <- tryCatch(
        quietly(
          if (yearly) {
            cvmdata:::source_cvm_http_get(schema, year = year, report_type = rt)
          } else {
            cvmdata:::source_cvm_http_get(schema)
          }
        ),
        cvmdata_error = function(e) {
          cli::cli_alert_warning(
            "{dataset}/{table} {year} {rt %||% ''}: {conditionMessage(e)}"
          )
          NULL
        }
      )
      if (is.null(path)) {
        next
      }
      obs <- read_csv_values(path, schema, columns)
      obs$year <- rep(if (yearly) year else NA_integer_, nrow(obs))
      parts[[length(parts) + 1L]] <- obs
    }
  }
  dplyr::bind_rows(parts)
}

# Distinct values of `columns` in one CVM CSV, every field as text. The
# CVM does not quote: a `"` is a character of the text, read with
# quote = "" as the package reader does (with readr's default quote a
# text starting with `"` swallowed the following lines, and a rate,
# "5,13% a.a.", reached the codelist of posicao_contratual_emissor).
read_csv_values <- function(csv_path, schema, columns) {
  df <- quietly(readr::read_delim(
    csv_path,
    delim = schema$delimiter %||% ";",
    locale = readr::locale(encoding = schema$encoding %||% "ISO-8859-1"),
    quote = "",
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE,
    progress = FALSE
  ))
  names(df) <- tolower(names(df))
  cols <- intersect(columns, names(df))
  dplyr::bind_rows(lapply(cols, function(col) {
    tibble::tibble(campo = col, value = unique(df[[col]]))
  }))
}

clean_observations <- function(obs) {
  if (is.null(obs) || !nrow(obs)) {
    return(tibble::tibble(
      campo = character(),
      value = character(),
      year = integer()
    ))
  }
  obs <- tibble::as_tibble(obs)
  obs$year <- as.integer(obs$year)
  obs[!is.na(obs$value) & nzchar(trimws(obs$value)), , drop = FALSE]
}

# First and last year each value of each column was observed in.
value_spans <- function(obs) {
  if (!nrow(obs)) {
    return(tibble::tibble(
      campo = character(),
      value = character(),
      first_seen_year = integer(),
      last_seen_year = integer()
    ))
  }
  obs |>
    dplyr::group_by(campo, value) |>
    dplyr::summarise(
      first_seen_year = if (all(is.na(year))) {
        NA_integer_
      } else {
        min(year, na.rm = TRUE)
      },
      last_seen_year = if (all(is.na(year))) {
        NA_integer_
      } else {
        max(year, na.rm = TRUE)
      },
      .groups = "drop"
    )
}

# --- build ------------------------------------------------------------

build_codelists_snapshot <- function() {
  dict_path <- system.file(
    "extdata",
    "cvm_dictionary_snapshot.csv",
    package = "cvmdata"
  )
  if (!nzchar(dict_path)) {
    cli::cli_abort(
      "Dictionary snapshot not found. Run build-dictionary-snapshot.R first."
    )
  }
  dict <- readr::read_csv(dict_path, show_col_types = FALSE)

  # Drop meta_status: missing rows.
  dict <- dict[!(dict$meta_status %in% "missing"), , drop = FALSE]
  key_of <- function(d) paste(d$group, d$dataset, d$table, d$campo, sep = "/")

  # --- Branch 1: enumerated dominio ----------------------------------
  cli::cli_h2("Branch 1 — enumerated dominio")
  enum_rows <- list()
  for (i in seq_len(nrow(dict))) {
    if (!is_enumerated_domain(dict$dominio[i])) {
      next
    }
    values <- parse_enum_values(dict$dominio[i])
    if (!length(values)) {
      next
    }
    enum_rows[[length(enum_rows) + 1L]] <- tibble::tibble(
      group = dict$group[i],
      dataset = dict$dataset[i],
      table = dict$table[i],
      campo = dict$campo[i],
      value = values
    )
  }
  enum_df <- dplyr::bind_rows(enum_rows)
  enum_keys <- if (nrow(enum_df)) unique(key_of(enum_df)) else character()
  cli::cli_alert_info(
    "Enumerated columns: {.val {length(enum_keys)}}; values: {.val {nrow(enum_df)}}."
  )

  # --- Branch 2 candidates: varchar, narrow, not excluded --------------
  candidates <- dict[
    dict$tipo_dados == "varchar" &
      !is.na(dict$tipo_dados) &
      !is.na(dict$tamanho) &
      dict$tamanho < .MAX_TAMANHO,
    ,
    drop = FALSE
  ]
  excluded <- vapply(candidates$campo, is_excluded_column, logical(1L))
  candidates <- candidates[!excluded, , drop = FALSE]
  candidates <- candidates[!(key_of(candidates) %in% enum_keys), , drop = FALSE]
  cli::cli_alert_info(
    "Candidate columns for the cardinality test: {.val {nrow(candidates)}}."
  )

  # --- Observe every year of every table involved ----------------------
  # The enumerated columns are observed too, for the years their values
  # appear in.
  cli::cli_h2("Observations — every published year")
  wanted <- dplyr::bind_rows(
    candidates[c("group", "dataset", "table", "campo")],
    if (nrow(enum_df)) {
      dplyr::distinct(enum_df, group, dataset, table, campo)
    }
  )
  buckets <- split(
    wanted,
    paste(wanted$group, wanted$dataset, wanted$table, sep = "/")
  )
  enum_out <- list()
  card_out <- list()
  for (bkey in names(buckets)) {
    b <- buckets[[bkey]]
    grp <- b$group[1L]
    dataset <- b$dataset[1L]
    table <- b$table[1L]
    cli::cli_alert_info("Observing {.val {bkey}}...")
    obs <- tryCatch(
      observe_table(dataset, table, unique(b$campo)),
      error = function(e) {
        cli::cli_alert_warning("Skip {bkey}: {conditionMessage(e)}")
        NULL
      }
    )
    if (is.null(obs)) {
      next
    }
    spans <- value_spans(obs)
    for (col in unique(b$campo)) {
      key <- paste(bkey, col, sep = "/")
      col_spans <- spans[spans$campo == col, , drop = FALSE]
      if (key %in% enum_keys) {
        # the dominio lists the values; the data only dates them
        values <- enum_df$value[key_of(enum_df) == key]
        hit <- match(values, col_spans$value)
        enum_out[[key]] <- tibble::tibble(
          group = grp,
          dataset = dataset,
          table = table,
          campo = col,
          value = values,
          first_seen_year = col_spans$first_seen_year[hit],
          last_seen_year = col_spans$last_seen_year[hit]
        )
        next
      }
      if (!nrow(col_spans)) {
        next
      }
      if (
        nrow(col_spans) > .MAX_CARDINALITY &&
          !(key %in% .CARDINALITY_EXCEPTIONS)
      ) {
        next
      }
      card_out[[key]] <- tibble::tibble(
        group = grp,
        dataset = dataset,
        table = table,
        campo = col,
        value = col_spans$value,
        first_seen_year = col_spans$first_seen_year,
        last_seen_year = col_spans$last_seen_year
      )
    }
  }
  # An enumerated column whose table could not be observed keeps its
  # values, undated.
  for (key in setdiff(enum_keys, names(enum_out))) {
    rows <- enum_df[key_of(enum_df) == key, , drop = FALSE]
    rows$first_seen_year <- NA_integer_
    rows$last_seen_year <- NA_integer_
    enum_out[[key]] <- rows
  }
  enum_df <- dplyr::bind_rows(enum_out)
  card_df <- dplyr::bind_rows(card_out)
  cli::cli_alert_info(
    "Cardinality-promoted columns: {.val {length(card_out)}}; values: {.val {nrow(card_df)}}."
  )

  # --- Merge --------------------------------------------------------
  all_df <- dplyr::bind_rows(enum_df, card_df) |>
    dplyr::distinct(group, dataset, table, campo, value, .keep_all = TRUE) |>
    dplyr::arrange(group, dataset, table, campo, value) |>
    dplyr::select(
      group,
      dataset,
      table,
      campo,
      value,
      first_seen_year,
      last_seen_year
    )

  list(
    rows = all_df,
    enum_n = nrow(enum_df),
    card_n = nrow(card_df)
  )
}

# --- main -------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
write_mode <- "--write" %in% args

result <- build_codelists_snapshot()
df <- result$rows

cli::cli_h1("Codelists snapshot summary")

cli::cli_h2("Per (group, dataset) inventory")
per_ds <- df |>
  dplyr::group_by(group, dataset) |>
  dplyr::summarise(
    n_tabelas_com_codelists = dplyr::n_distinct(table),
    n_colunas_codelist = dplyr::n_distinct(paste(table, campo)),
    n_valores_unicos_total = dplyr::n(),
    .groups = "drop"
  )
print(per_ds)

cli::cli_h2("Top-5 (group, dataset, table, campo) by cardinality")
top5 <- df |>
  dplyr::group_by(group, dataset, table, campo) |>
  dplyr::summarise(n_values = dplyr::n(), .groups = "drop") |>
  dplyr::arrange(dplyr::desc(n_values)) |>
  head(5L)
print(top5)

cli::cli_h2("Totals")
cli::cli_bullets(c(
  "*" = "Total rows: {nrow(df)}",
  "*" = "Distinct (group, dataset, table, campo): {dplyr::n_distinct(paste(df$group, df$dataset, df$table, df$campo))}",
  "*" = "From dominio enumeration: {result$enum_n}",
  "*" = "From observed cardinality: {result$card_n}"
))

# A regeneration must not erase codelists silently: list every column
# of the committed snapshot that the new build lacks.
out <- file.path("inst", "extdata", "cvm_codelists_snapshot.csv")
codelist_keys <- function(d) {
  unique(paste(d$group, d$dataset, d$table, d$campo, sep = "/"))
}
lost <- if (file.exists(out)) {
  committed <- readr::read_csv(
    out,
    col_types = readr::cols(.default = readr::col_character())
  )
  setdiff(codelist_keys(committed), codelist_keys(df))
} else {
  character(0L)
}
if (length(lost)) {
  cli::cli_alert_warning(
    "{length(lost)} column{?s} of the committed snapshot lost {?its/their} codelist:"
  )
  cli::cli_bullets(stats::setNames(lost, rep("*", length(lost))))
} else {
  cli::cli_alert_success(
    "No column of the committed snapshot lost its codelist."
  )
}

if (write_mode) {
  if (length(lost) && !("--allow-drop" %in% args)) {
    cli::cli_abort(c(
      "Refusing to write: {length(lost)} codelist column{?s} would be dropped.",
      "i" = "A CSV missing upstream is the usual cause; pass {.code --allow-drop} only if the CVM retired the column."
    ))
  }
  readr::write_csv(df, out, na = "")
  cli::cli_alert_success("Wrote {.path {out}} ({nrow(df)} rows)")
} else {
  cli::cli_alert_info(
    "Dry run. Re-run with {.code --write} to persist the CSV."
  )
}
