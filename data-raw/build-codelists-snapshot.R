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
#      `tamanho < 200` whose observed distinct count in the latest
#      available year is ≤ 50, EXCLUDING:
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
# Sampling scope: latest year only per dataset. v0.2 may revisit with
# multi-year coverage; that decision is deferred together with the
# `first_seen_year` column (CLAUDE.md §9.2).

suppressPackageStartupMessages({
  devtools::load_all(quiet = TRUE)
  library(dplyr)
  library(readr)
  library(tibble)
  library(cli)
})

`%||%` <- function(a, b) if (is.null(a)) b else a

# --- thresholds (Sessão 3.4) -----------------------------------------

.MAX_TAMANHO <- 200L          # varchar fields wider than this are free text
.MAX_CARDINALITY <- 50L       # hard cap on distinct values for a codelist
.FREE_TEXT_DOMAINS <- c(
  "Alfanumérico", "Numérico", "Númerico", "AAAA-MM-DD"
)
# Free-text / identifier columns to exclude from cardinality promotion.
# Mirrors R/util-csv-cvm.R `.identifier_patterns` (cnpj, cd_cvm,
# codigo_cvm, cep, tel, ddd, cpf, id_doc, id_documento, versao) and
# adds prefixes for accounting codes (`cd_*`), proper names (`nome_*`,
# `denom_*`), descriptions (`ds_*`), and address-related text
# (`email*`, `logradouro*`, `compl*`, `bairro*`, `mun*`,
# `municipio_*`).
.EXCLUDE_PATTERNS <- c(
  "^cnpj($|_)",
  "^cd_",
  "^codigo_cvm($|_)",
  "^cep$",
  "^tel($|_)",
  "^ddd($|_)",
  "^cpf($|_)",
  "^id_doc$",
  "^id_documento$",
  "^versao$",
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
  any(vapply(.EXCLUDE_PATTERNS, function(p) {
    grepl(p, col, perl = TRUE)
  }, logical(1L)))
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

# Resolve the CSV path for one (dataset, table). For yearly datasets
# uses report_type = "ind" when the schema has variants (codelists are
# the same across ind/con). Returns NULL on failure (logged via cli).
resolve_csv_path <- function(dataset, table, year_lookup) {
  schema <- load_schema(dataset, table)
  if (identical(schema$meta_status %||% "available", "missing")) {
    return(NULL)
  }
  partitioning <- schema$temporal_partitioning %||% "none"
  if (identical(partitioning, "yearly")) {
    year <- year_lookup[[dataset]]
    if (is.null(year) || is.na(year)) {
      cli::cli_alert_warning(
        "No year resolved for dataset {.val {dataset}}; skipping."
      )
      return(NULL)
    }
    rt <- if (length(schema$cvm_file_pattern_variants %||% list())) {
      "ind"
    } else {
      NULL
    }
    return(cvmdata:::source_cvm_http_get(
      schema, year = year, report_type = rt
    ))
  }
  cvmdata:::source_cvm_http_get(schema)
}

# Distinct values for one column in a CSV, ignoring NA / blank tokens.
distinct_values <- function(csv_path, encoding, delim, column_lower) {
  header <- readr::read_delim(
    csv_path,
    delim = delim,
    locale = readr::locale(encoding = encoding),
    n_max = 0L,
    show_col_types = FALSE,
    progress = FALSE
  )
  csv_names <- colnames(header)
  csv_lower <- tolower(csv_names)
  idx <- which(csv_lower == column_lower)
  if (!length(idx)) {
    return(character(0L))
  }
  csv_name <- csv_names[idx[1L]]
  df <- readr::read_delim(
    csv_path,
    delim = delim,
    locale = readr::locale(encoding = encoding),
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE,
    progress = FALSE
  )
  vals <- df[[csv_name]]
  vals <- vals[!is.na(vals) & nzchar(vals)]
  sort(unique(vals))
}

# Wrap a noisy operation so readr's parsing-warning chatter does not
# clutter the dry-run log. Genuine errors still propagate.
quietly <- function(expr) {
  withCallingHandlers(
    expr,
    warning = function(w) invokeRestart("muffleWarning")
  )
}

# --- build ------------------------------------------------------------

build_codelists_snapshot <- function() {
  dict_path <- system.file(
    "extdata", "cvm_dictionary_snapshot.csv", package = "cvmdata"
  )
  if (!nzchar(dict_path)) {
    cli::cli_abort(
      "Dictionary snapshot not found. Run build-dictionary-snapshot.R first."
    )
  }
  dict <- readr::read_csv(dict_path, show_col_types = FALSE)

  # Drop meta_status: missing rows.
  dict <- dict[!(dict$meta_status %in% "missing"), , drop = FALSE]

  # --- Branch 1: enumerated dominio (no download required) ----------
  cli::cli_h2("Branch 1 — enumerated dominio (no download)")
  enum_rows <- list()
  for (i in seq_len(nrow(dict))) {
    if (!is_enumerated_domain(dict$dominio[i])) next
    values <- parse_enum_values(dict$dominio[i])
    if (!length(values)) next
    enum_rows[[length(enum_rows) + 1L]] <- tibble::tibble(
      group   = dict$group[i],
      dataset = dict$dataset[i],
      table   = dict$table[i],
      campo   = dict$campo[i],
      value   = values,
      source  = "dominio"
    )
  }
  enum_df <- dplyr::bind_rows(enum_rows)
  cli::cli_alert_info(
    "Enumerated columns: {.val {dplyr::n_distinct(paste(enum_df$group, enum_df$dataset, enum_df$table, enum_df$campo))}}; ",
    "values: {.val {nrow(enum_df)}}."
  )

  # --- Branch 2: cardinality-driven (per-dataset CSV downloads) -----
  cli::cli_h2("Branch 2 — observed cardinality (downloads latest year)")

  # Candidate columns: varchar with tamanho < .MAX_TAMANHO AND not
  # excluded by name AND not in the enumerated set.
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
  enum_keys <- if (!is.null(enum_df) && nrow(enum_df)) {
    paste(enum_df$group, enum_df$dataset, enum_df$table, enum_df$campo)
  } else {
    character(0L)
  }
  candidates <- candidates[
    !(paste(candidates$group, candidates$dataset, candidates$table,
            candidates$campo) %in% enum_keys),
    , drop = FALSE
  ]
  cli::cli_alert_info(
    "Candidate (group,dataset,table,campo) for cardinality test: {.val {nrow(candidates)}}."
  )

  # Resolve latest year per dataset (only for yearly-partitioned ones).
  datasets <- sort(unique(candidates$dataset))
  year_lookup <- list()
  for (ds in datasets) {
    tabs <- cvm_tables(ds)
    if (!length(tabs)) next
    s <- load_schema(ds, tabs[1L])
    if (identical(s$temporal_partitioning %||% "none", "yearly")) {
      yrs <- cvm_dataset_years(ds)
      year_lookup[[ds]] <- max(yrs)
      cli::cli_alert_info(
        "Latest year for {.val {ds}}: {.val {max(yrs)}}."
      )
    }
  }

  # Group candidates by (group, dataset, table); fetch CSV once per
  # bucket. `bucket_key` avoids the variable name `groups`, which would
  # shadow the group-dimension concept.
  buckets <- split(
    candidates,
    paste(candidates$group, candidates$dataset, candidates$table,
          sep = "/")
  )

  card_rows <- list()
  for (gkey in names(buckets)) {
    b <- buckets[[gkey]]
    grp <- b$group[1L]
    dataset <- b$dataset[1L]
    table <- b$table[1L]
    cli::cli_alert_info(
      "Downloading {.val {grp}}/{.val {dataset}}/{.val {table}}..."
    )
    csv_path <- tryCatch(
      quietly(resolve_csv_path(dataset, table, year_lookup)),
      error = function(e) {
        cli::cli_alert_warning(
          "Skip {dataset}/{table}: {conditionMessage(e)}"
        )
        NULL
      }
    )
    if (is.null(csv_path) || !file.exists(csv_path %||% "")) {
      cli::cli_alert_warning(
        "Skip {.val {dataset}}/{.val {table}}: CSV not found in archive."
      )
      next
    }
    schema <- load_schema(dataset, table)
    delim <- schema$delimiter %||% ";"
    enc <- schema$encoding %||% "ISO-8859-1"
    for (i in seq_len(nrow(b))) {
      col_lower <- b$campo[i]
      vals <- tryCatch(
        quietly(distinct_values(csv_path, enc, delim, col_lower)),
        error = function(e) {
          cli::cli_alert_warning(
            "Read failed for {dataset}/{table}/{col_lower}: ",
            "{conditionMessage(e)}"
          )
          character(0L)
        }
      )
      if (!length(vals)) next
      if (length(vals) > .MAX_CARDINALITY) next
      card_rows[[length(card_rows) + 1L]] <- tibble::tibble(
        group   = grp,
        dataset = dataset,
        table   = table,
        campo   = col_lower,
        value   = vals,
        source  = "cardinality"
      )
    }
  }
  card_df <- dplyr::bind_rows(card_rows)
  cli::cli_alert_info(
    "Cardinality-promoted columns: {.val {dplyr::n_distinct(paste(card_df$group, card_df$dataset, card_df$table, card_df$campo))}}; ",
    "values: {.val {nrow(card_df)}}."
  )

  # --- Merge --------------------------------------------------------
  all_df <- dplyr::bind_rows(enum_df, card_df) |>
    dplyr::distinct(group, dataset, table, campo, value, .keep_all = TRUE) |>
    dplyr::arrange(group, dataset, table, campo, value) |>
    dplyr::select(group, dataset, table, campo, value)

  list(
    rows = all_df,
    enum_n = if (is.null(enum_df) || !nrow(enum_df)) 0L else nrow(enum_df),
    card_n = if (is.null(card_df) || !nrow(card_df)) 0L else nrow(card_df)
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

if (write_mode) {
  out <- file.path("inst", "extdata", "cvm_codelists_snapshot.csv")
  readr::write_csv(df, out, na = "")
  cli::cli_alert_success("Wrote {.path {out}} ({nrow(df)} rows)")
} else {
  cli::cli_alert_info(
    "Dry run. Re-run with {.code --write} to persist the CSV."
  )
}
