# ETL helper: the rows a new mirror partition supersedes, kept as history.
#
# Every CVM annual file carries only the filing delivered last for each
# (company, reference date); the detail tables of the package keep that
# policy (`keep_latest_version`). When a company restates a statement,
# the rows of the previous filing vanish from the CVM file, and until
# 2026-10 they vanished from the mirror too: the release was overwritten
# in place. From now on 03-publish.R compares, for every partition whose
# content hash moved, the parquet of the previous release with the new
# one, filing by filing, and appends the rows of the filings that changed
# or disappeared to a history asset of the same partition
# (`<table>__report_type=R__year=Y__history.parquet`). The `-latest`
# parquet stays exactly as before, so no client changes.
#
# What counts as a change is the CONTENT of the filing's rows (sorted,
# over the columns both parquets share), never the identity of the
# delivery: `versao`, `id_doc`, `dt_receb` and their FRE/vlmo spellings
# are left out of the comparison. The CVM index carries two VERSAO 1
# filings for one (cnpj, date) and a VERSAO 1 delivered after a VERSAO 2
# with the same numbers (Travessia VI, DFP 2024); the `submissao` table
# already records every delivery, so a new document with the same data
# adds nothing to history. A column added or dropped upstream is
# reported by the caller, not treated as a change of every filing.
#
# Sourced (not loaded as a package). Depends on `00-config.R` having been
# sourced first for `mirror_schema_dir()`.

stopifnot(requireNamespace("arrow", quietly = TRUE))
stopifnot(requireNamespace("digest", quietly = TRUE))
stopifnot(requireNamespace("dplyr", quietly = TRUE))
stopifnot(requireNamespace("yaml", quietly = TRUE))

# Columns appended to every history row.
mirror_history_cols <- c("superseded_at", "superseded_by_versao")

# Columns that identify the delivery, not its content (CLAUDE.md 2.3 and
# R/transform-schema.R): left out of the comparison.
mirror_delivery_cols <- c(
  "versao",
  "id_doc",
  "id_documento",
  "protocolo_entrega",
  "dt_receb",
  "data_entrega",
  "data_recebimento"
)

# Whether the schema of (dataset, table) keeps only the latest filing,
# i.e. whether a new release can drop rows worth keeping. Returns
# list(versioned, keys): `keys` are the extra key columns the YAML
# declares (e.g. cgvn/praticas: id_item), NULL otherwise.
mirror_table_versioning <- function(dataset, table) {
  path <- file.path(mirror_schema_dir(dataset), paste0(table, ".yaml"))
  none <- list(versioned = FALSE, keys = NULL)
  if (!file.exists(path)) {
    return(none)
  }
  schema <- yaml::read_yaml(path)
  for (tx in schema$transformations) {
    if (identical(tx$action, "keep_latest_version")) {
      return(list(versioned = TRUE, keys = unlist(tx$keys)))
    }
  }
  none
}

# Key columns that identify a filing in `df`: the (cnpj, date) pair in
# either naming convention (CLAUDE.md 2.2) plus the schema extras. NULL
# when the table carries no filing identity.
mirror_filing_keys <- function(df, extras = NULL) {
  cnpj_c <- intersect(c("cnpj_cia", "cnpj_companhia"), names(df))[1L]
  date_c <- intersect(c("dt_refer", "data_referencia"), names(df))[1L]
  if (is.na(cnpj_c) || is.na(date_c)) {
    return(NULL)
  }
  keys <- c(cnpj_c, date_c, extras)
  if (!all(keys %in% names(df))) {
    return(NULL)
  }
  keys
}

# One string per row over `cols`, order-independent across platforms.
mirror_row_strings <- function(df, cols, sep) {
  parts <- lapply(df[cols], function(x) {
    if (inherits(x, "Date")) format(x) else as.character(x)
  })
  do.call(paste, c(parts, list(sep = sep)))
}

# Signature of every filing of `df`: `key` is the filing key of each row,
# `sig` a named vector (by key) with the SHA-256 of the sorted row strings
# of the filing over `cols`. Row order inside a filing does not matter.
mirror_filing_signatures <- function(df, keys, cols) {
  key <- mirror_row_strings(df, keys, sep = "|")
  rows <- mirror_row_strings(df, cols, sep = "\x1f")
  sig <- vapply(
    split(rows, key),
    function(r) {
      digest::digest(
        paste(sort(r), collapse = "\n"),
        algo = "sha256",
        serialize = FALSE
      )
    },
    character(1L)
  )
  list(key = key, sig = sig)
}

# Rows of `old` that `new` supersedes: the filings whose content changed
# and the filings that vanished, compared over the columns both have
# minus the delivery identity. Every row keeps all the columns `old`
# had, plus `superseded_at` (`stamp`, ISO-8601 UTC of the ETL run) and
# `superseded_by_versao` (the `versao` of the replacing filing; NA when
# it vanished).
#
# Returns list(rows, n_replaced, n_removed, columns_added,
# columns_dropped). `rows` has zero rows when nothing was superseded.
mirror_superseded_rows <- function(old, new, keys, stamp) {
  cols <- intersect(names(old), names(new))
  cols <- setdiff(cols, c(mirror_history_cols, mirror_delivery_cols))
  stopifnot(all(keys %in% cols))
  o <- mirror_filing_signatures(old, keys, cols)
  n <- mirror_filing_signatures(new, keys, cols)
  new_sig <- n$sig[names(o$sig)]
  removed <- names(o$sig)[is.na(new_sig)]
  replaced <- names(o$sig)[!is.na(new_sig) & new_sig != o$sig]
  rows <- old[o$key %in% c(removed, replaced), , drop = FALSE]
  rows$superseded_at <- rep(stamp, nrow(rows))
  rows$superseded_by_versao <- mirror_replacing_versao(
    o$key[o$key %in% c(removed, replaced)],
    new,
    n$key
  )
  list(
    rows = rows,
    n_replaced = length(replaced),
    n_removed = length(removed),
    columns_added = setdiff(names(new), names(old)),
    columns_dropped = setdiff(names(old), names(new))
  )
}

# `versao` of the filing `new` holds for each key of `old_keys`; NA when
# `new` has no such filing or no `versao` column.
mirror_replacing_versao <- function(old_keys, new, new_key) {
  if (!"versao" %in% names(new)) {
    return(rep(NA_character_, length(old_keys)))
  }
  first <- !duplicated(new_key)
  lookup <- as.character(new$versao[first])
  names(lookup) <- new_key[first]
  unname(lookup[old_keys])
}

# History of a partition after this run: the previous history asset (NULL
# on the first supersession) followed by the rows superseded now.
mirror_append_history <- function(previous, rows) {
  if (is.null(previous)) {
    return(rows)
  }
  dplyr::bind_rows(previous, rows)
}

# Partition path of the history asset for the partition `rel`
# ("bpa/report_type=ind/year=2024/part-0.parquet" ->
# "bpa/report_type=ind/year=2024/history.parquet"). The last segment is
# not "part-N", so `parse_mirror_asset_name()` rejects the asset and
# every current client ignores it.
mirror_history_rel <- function(rel) {
  file.path(dirname(rel), "history.parquet")
}

# Whether a release asset name is a history asset.
mirror_is_history_asset <- function(name) {
  grepl("__history\\.parquet$", name)
}

# Table of a partition path: its first segment.
mirror_partition_table <- function(rel) {
  strsplit(rel, "/", fixed = TRUE)[[1L]][[1L]]
}
