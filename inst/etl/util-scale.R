# ETL helper: the scale-error label of a superseded DFP/ITR version.
#
# A company that files a statement in R$ units when the form asks for
# R$ thousand re-files it days later, and the two versions differ by a
# factor of 1000 in every account. The history keeps both (decision of
# 2026-11-06: keep and mark, never omit), and without a mark the row a
# thousand times smaller reads as a restatement. Stage 05
# (05-label-scale.R) judges every superseded version ONCE, over the
# WHOLE document (the eight statements, individual and consolidated),
# and writes the verdict as the column `scale_error` of every row of
# the version in the history assets. The three values were named by the
# owner; the client (`cvm_versions()`) reads them through DuckDB's
# `union_by_name` and labels the current version "sem erro de escala".
#
# Rule (closed 2026-11-06, measured on 6,825 pairs of DFP 2010–2025 and
# ITR 2011–2026): an account is (table, basis, cd_conta, coluna_df,
# dt_ini_exerc, dt_fim_exerc) of the ÚLTIMO rows, 3.99* (per-share
# figures) left out, a repeated row counted once. Between the accounts
# with a value in both versions (a zero on both sides says nothing and is
# not judged), MORE THAN HALF follow one factor 1000^n (n != 0) -> the
# version has a scale error; "apenas erro de escala" when EVERY judged
# account follows that factor and no non-zero account exists on one side
# only; otherwise "erro de escala e outras mudanças". Anything else,
# the current version included, is "sem erro de escala". No check of the
# total assets (measured redundant: the same 381 documents). Accepted
# cost: 2 ITR stay "sem" (one with only the consolidated dfc_mi scaled;
# one whose next version is missing from the history, so the pair skips
# to the one after).
#
# The successor of a version is the next delivery of the same
# (cnpj_cia, dt_refer): the superseded versions in the order of
# `superseded_at`, then `id_doc`, then `versao`; the current version
# last. A version the mirror path filed (`history_source` "mirror") holds
# only the tables whose content changed: the tables it lacks are the
# successor's, unchanged, and are taken from it before the comparison
# (the RAD path files the whole document, so a table it lacks is a table
# the version did not have).
#
# Sourced (not loaded as a package). No dependency on the siblings.

stopifnot(requireNamespace("dplyr", quietly = TRUE))

# Version of the rule. 05-label-scale.R stores it in `__source_hash.json`
# (`scale_rule`); a release labelled under another one is labelled again
# whole.
scale_rule <- "1"

scale_labels <- c(
  only = "apenas erro de escala",
  mixed = "erro de escala e outras mudanças",
  none = "sem erro de escala"
)

# The statements the label is judged on (DFP and ITR; CLAUDE.md 2.1).
scale_tables <- c("bpa", "bpp", "dre", "dra", "dfc_md", "dfc_mi", "dmpl", "dva")

# The columns the judgement reads from a statement parquet. `coluna_df`
# exists in dmpl only, `dt_ini_exerc` not in bpa/bpp: absent columns are
# read as NA.
scale_value_cols <- c(
  "cnpj_cia",
  "dt_refer",
  "versao",
  "ordem_exerc",
  "dt_ini_exerc",
  "dt_fim_exerc",
  "cd_conta",
  "coluna_df",
  "vl_conta"
)

scale_exponents <- c(-2L, -1L, 1L, 2L) # the factors tried: 1000^n
scale_tolerance <- 1e-6 # relative; the values are reals already scaled

# --- identity ---------------------------------------------------------

# One string per row naming the version the row belongs to, the same in
# every table of the document: (cnpj, reference date, versao, id_doc,
# superseded_at). `id_doc` is NA in the rows the mirror path filed.
scale_version_key <- function(df) {
  id <- scale_col_or_na(df, "id_doc")
  paste(
    df$cnpj_cia,
    format(df$dt_refer),
    df$versao,
    ifelse(is.na(id), "", as.character(id)),
    scale_col_or_na(df, "superseded_at"),
    sep = "|"
  )
}

# One string per row naming the document (cnpj, reference date).
scale_document_key <- function(df) {
  paste(df$cnpj_cia, format(df$dt_refer), sep = "|")
}

scale_col_or_na <- function(df, col) {
  if (col %in% names(df)) df[[col]] else rep(NA, nrow(df))
}

scale_fmt <- function(x) {
  out <- if (inherits(x, "Date")) format(x) else as.character(x)
  ifelse(is.na(out), "", out)
}

# The accounts of one version: data.frame(account, table, value), one
# row per account (ÚLTIMO, not 3.99*, with a value; a repeated row
# counted once). `df` carries `table` and `report_type` (added by the
# stage from the asset name).
scale_accounts <- function(df) {
  keep <- df$ordem_exerc %in%
    "ÚLTIMO" &
    !startsWith(df$cd_conta, "3.99") &
    !is.na(df$vl_conta)
  df <- df[keep, , drop = FALSE]
  account <- paste(
    df$table,
    df$report_type,
    df$cd_conta,
    scale_fmt(scale_col_or_na(df, "coluna_df")),
    scale_fmt(scale_col_or_na(df, "dt_ini_exerc")),
    scale_fmt(df$dt_fim_exerc),
    sep = "|"
  )
  first <- !duplicated(account)
  data.frame(
    account = account[first],
    table = df$table[first],
    value = as.numeric(df$vl_conta[first]),
    stringsAsFactors = FALSE
  )
}

# --- the rule ---------------------------------------------------------

# Counts of a pair of account frames (the superseded version `old`, its
# successor `new`): list(n_judged, n_factor, n_equal, n_other,
# n_one_side, exponent). `n_factor` counts the judged accounts that
# follow the most common factor 1000^`exponent` (NA when none does);
# `n_other` the ones that follow neither it nor equality; `n_one_side`
# the non-zero accounts one version has and the other does not.
scale_compare <- function(old, new) {
  m <- match(old$account, new$account)
  both <- !is.na(m)
  o <- old$value[both]
  n <- new$value[m[both]]
  judged <- !(o == 0 & n == 0)
  o <- o[judged]
  n <- n[judged]
  equal <- abs(n - o) <= scale_tolerance * pmax(abs(n), abs(o))
  exponent <- rep(NA_integer_, length(o))
  for (k in scale_exponents) {
    hit <- is.na(exponent) &
      !equal &
      abs(n - o * 1000^k) <= scale_tolerance * abs(n)
    exponent[hit] <- k
  }
  counted <- table(exponent)
  mode <- if (length(counted)) {
    as.integer(names(counted)[which.max(counted)])
  } else {
    NA_integer_
  }
  n_factor <- if (is.na(mode)) 0L else sum(exponent %in% mode)
  new_only <- !(seq_len(nrow(new)) %in% m[both])
  list(
    n_judged = length(o),
    n_factor = n_factor,
    n_equal = sum(equal),
    n_other = length(o) - n_factor - sum(equal),
    n_one_side = sum(old$value[!both] != 0) + sum(new$value[new_only] != 0),
    exponent = mode
  )
}

# The label of a comparison (`scale_compare()`).
scale_label <- function(cmp) {
  if (cmp$n_judged == 0L || cmp$n_factor * 2L <= cmp$n_judged) {
    return(scale_labels[["none"]])
  }
  if (cmp$n_other == 0L && cmp$n_equal == 0L && cmp$n_one_side == 0L) {
    return(scale_labels[["only"]])
  }
  scale_labels[["mixed"]]
}

# --- a year of a dataset ----------------------------------------------

scale_empty_verdicts <- function() {
  data.frame(
    version = character(),
    document = character(),
    history_source = character(),
    scale_error = character(),
    n_judged = integer(),
    n_factor = integer(),
    n_equal = integer(),
    n_other = integer(),
    n_one_side = integer(),
    exponent = integer(),
    stringsAsFactors = FALSE
  )
}

# The versions of the history rows `history` (the statement tables of
# one year, with `table` and `report_type`), one row each, in the order
# of succession within their document: data.frame(version, document,
# history_source, at, id_doc, versao).
scale_versions_of <- function(history) {
  v <- data.frame(
    version = scale_version_key(history),
    document = scale_document_key(history),
    history_source = scale_col_or_na(history, "history_source"),
    at = as.character(history$superseded_at),
    id_doc = suppressWarnings(as.integer(scale_col_or_na(history, "id_doc"))),
    versao = suppressWarnings(as.integer(history$versao)),
    stringsAsFactors = FALSE
  )
  v <- v[!duplicated(v$version), , drop = FALSE]
  v[order(v$document, v$at, v$id_doc, v$versao), , drop = FALSE]
}

# The verdict of every superseded version of one year: `history` are
# the rows of the history assets of the statement tables, `current` the
# rows of their current partitions (`scale_value_cols` plus `table` and
# `report_type`). Returns one row per version (`scale_empty_verdicts()`
# columns); `version` is `scale_version_key()` of its rows.
scale_label_versions <- function(history, current) {
  if (!nrow(history)) {
    return(scale_empty_verdicts())
  }
  versions <- scale_versions_of(history)
  acc_h <- lapply(
    split(history, scale_version_key(history)),
    scale_accounts
  )
  acc_c <- lapply(split(current, scale_document_key(current)), scale_accounts)
  out <- vector("list", nrow(versions))
  i <- nrow(versions)
  # from the last version of each document back to the first, so a
  # mirror-filed version takes its missing tables from a successor
  # already completed
  filled <- NULL
  while (i >= 1L) {
    v <- versions[i, ]
    last_of_doc <- i == nrow(versions) ||
      versions$document[i + 1L] != v$document
    if (last_of_doc) {
      filled <- acc_c[[v$document]]
    }
    successor <- filled
    old <- acc_h[[v$version]]
    if (!identical(v$history_source, "rad") && !is.null(successor)) {
      missing <- !successor$table %in% old$table
      old <- rbind(old, successor[missing, , drop = FALSE])
    }
    cmp <- if (is.null(successor)) {
      list(
        n_judged = 0L,
        n_factor = 0L,
        n_equal = 0L,
        n_other = 0L,
        n_one_side = 0L,
        exponent = NA_integer_
      )
    } else {
      scale_compare(old, successor)
    }
    out[[i]] <- data.frame(
      version = v$version,
      document = v$document,
      history_source = v$history_source,
      scale_error = scale_label(cmp),
      n_judged = cmp$n_judged,
      n_factor = cmp$n_factor,
      n_equal = cmp$n_equal,
      n_other = cmp$n_other,
      n_one_side = cmp$n_one_side,
      exponent = cmp$exponent,
      stringsAsFactors = FALSE
    )
    filled <- old
    i <- i - 1L
  }
  rows <- do.call(rbind, out)
  rownames(rows) <- NULL
  rows
}

# `df` (the rows of one history asset) with `scale_error` set from the
# verdicts; NA for a version the verdicts do not name.
scale_apply_verdicts <- function(df, verdicts) {
  df$scale_error <- verdicts$scale_error[match(
    scale_version_key(df),
    verdicts$version
  )]
  df
}

# One line of counts for the log: versions by label.
scale_tally <- function(verdicts) {
  n <- vapply(
    scale_labels,
    function(l) sum(verdicts$scale_error == l),
    integer(1L)
  )
  sprintf(
    "%d version(s): %d apenas / %d e outras mudanças / %d sem",
    nrow(verdicts),
    n[["only"]],
    n[["mixed"]],
    n[["none"]]
  )
}
