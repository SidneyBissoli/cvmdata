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
mirror_history_cols <- c(
  "superseded_at",
  "superseded_by_versao",
  "history_source",
  "id_doc",
  "motivo_reapresentacao"
)

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
#
# `identity_only` (the run in which the package's CSV reader changed, see
# `mirror_reader_id()`): a filing counts as replaced only when its
# DELIVERY changed too (`versao`, `id_doc`, `dt_receb` and spellings). A
# change of content under the same delivery is the reader's, not the
# CVM's: on 2026-10-25 the reader stopped losing rows to quote handling
# (2,803 rows of FRE 2024 alone), and comparing contents would have filed
# every such filing as superseded by itself. A real re-filing always
# brings a new delivery, so nothing the CVM did is missed.
mirror_superseded_rows <- function(
  old,
  new,
  keys,
  stamp,
  identity_only = FALSE
) {
  cols <- intersect(names(old), names(new))
  cols <- setdiff(cols, c(mirror_history_cols, mirror_delivery_cols))
  stopifnot(all(keys %in% cols))
  o <- mirror_filing_signatures(old, keys, cols)
  n <- mirror_filing_signatures(new, keys, cols)
  new_sig <- n$sig[names(o$sig)]
  removed <- names(o$sig)[is.na(new_sig)]
  replaced <- names(o$sig)[!is.na(new_sig) & new_sig != o$sig]
  if (identity_only && length(replaced)) {
    ident <- intersect(intersect(names(old), names(new)), mirror_delivery_cols)
    if (!length(ident)) {
      replaced <- character()
    } else {
      # the set of DISTINCT deliveries of each filing: recovered rows of
      # the same delivery repeat it, they do not make another one
      oi <- mirror_filing_signatures(
        unique(old[c(keys, ident)]),
        keys,
        ident
      )$sig
      ni <- mirror_filing_signatures(
        unique(new[c(keys, ident)]),
        keys,
        ident
      )$sig
      replaced <- replaced[oi[replaced] != ni[replaced]]
    }
  }
  rows <- old[o$key %in% c(removed, replaced), , drop = FALSE]
  rows$superseded_at <- rep(stamp, nrow(rows))
  rows$superseded_by_versao <- mirror_replacing_versao(
    o$key[o$key %in% c(removed, replaced)],
    new,
    n$key
  )
  # the other path into the same asset is the RAD backfill
  # (04-rad-fetch.R, `history_source = "rad"`)
  rows$history_source <- rep("mirror", nrow(rows))
  list(
    rows = rows,
    n_replaced = length(replaced),
    n_removed = length(removed),
    columns_added = setdiff(names(new), names(old)),
    columns_dropped = setdiff(names(old), names(new))
  )
}

# Fingerprint of the package code that turns a CVM CSV into a parquet:
# the reader (R/util-csv-cvm.R) and the schema transformations
# (R/transform-schema.R), digested from the installed namespace. The
# publish stores it in `__source_hash.json` (`reader`); when it differs
# from the previous release's, the history of that run compares
# deliveries, not contents (`identity_only` above). A sidecar without the
# field (every release before 2026-10-25) counts as a different reader.
mirror_reader_objects <- c(
  ".identifier_prefixes",
  ".identifier_exact",
  ".text_types",
  "identifier_columns",
  "resolve_dict_columns",
  "build_col_types",
  "classify_date",
  "read_cvm_csv",
  "validate_field_count",
  "expected_field_names",
  "validate_field_names",
  "emit_validation",
  "apply_schema_transformations",
  "apply_one_transformation",
  "tx_multiply_by_scale",
  "scale_factor",
  "tx_drop",
  "tx_keep_latest_version",
  ".filing_receipt_cols",
  ".filing_id_cols",
  "first_present",
  "filing_rank",
  "as_sortable_time",
  "as_sortable_id"
)

#
# The reader also follows the dictionary snapshot: a column declared
# varchar/char/nvarchar is read as character, one declared date as Date
# (`resolve_dict_columns()`). So the fingerprint covers the declared
# type of every column too, and a snapshot refresh that changes one is a
# reader change. Measured on 2026-11-01: the CVM META turned
# fre/transacao_parte_relacionada.taxa_juros from numeric into varchar
# (text since the 2023 FRE); with the reader id unchanged, the next run
# would have filed all 616 filings of FRE 2022 (9,408 rows) as
# superseded, "0" now reading "0.000000". The declared sizes do not
# change the reading and stay out.
mirror_reader_dictionary <- function(ns = asNamespace("cvmdata")) {
  snap <- ns$.read_dictionary_snapshot(ns$require_snapshot_path(
    "cvm_dictionary_snapshot.csv",
    "build-dictionary-snapshot.R"
  ))
  rows <- do.call(
    paste,
    c(
      unname(as.list(snap[c("group", "dataset", "table", "campo")])),
      list(ifelse(is.na(snap$tipo_dados), "", snap$tipo_dados), sep = "|")
    )
  )
  sort(rows, method = "radix")
}

mirror_reader_id <- function(
  ns = asNamespace("cvmdata"),
  dictionary = mirror_reader_dictionary()
) {
  present <- mirror_reader_objects[vapply(
    mirror_reader_objects,
    exists,
    logical(1L),
    envir = ns,
    inherits = FALSE
  )]
  objs <- mget(present, envir = ns)
  substr(
    digest::digest(list(lapply(objs, deparse), dictionary)),
    1L,
    12L
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

# Whether a release asset is a partition parquet written by 03-publish.R
# (`<table>__[report_type=R__][year=Y__]part-0.parquet`, `=` possibly
# stored as `.`). Only these may be removed as stale: the release also
# holds assets other robots own, and on 2026-10-27 the stale sweep
# deleted the RAD robot's `__rad_state.json` and `__rad_unread.csv` from
# dfp-latest and itr-latest, the first publish of those datasets since
# the RAD state existed.
mirror_is_partition_asset <- function(name) {
  grepl("__part-[0-9]+\\.parquet$", name) & !mirror_is_history_asset(name)
}

# Table of a partition path: its first segment.
mirror_partition_table <- function(rel) {
  strsplit(rel, "/", fixed = TRUE)[[1L]][[1L]]
}
