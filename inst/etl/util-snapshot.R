# Dated snapshots of the mirror (decision of 2026-10-25, ROADMAP item
# "Release de dados versionado").
#
# The `-latest` release is rewritten in place every week, so a client
# could never ask for "the mirror as of 1 September". Measured on
# 2026-10-25 over 144 weeks of CVM deliveries: a weekly round changes
# about 60 MB and 11% of the ~1,180 partitions. Copying the whole mirror
# into a dated release (~600 MB a week, ~32 GB a year) was rejected for
# a release per round that carries ONLY the partitions whose content
# changed (~3.5 GB a year), plus the complete `__source_hash.json`, in
# which every partition says which snapshot release holds its current
# bytes (`releases`). Snapshot releases are never deleted: the pointers
# of later snapshots depend on them. The first snapshot of a dataset
# (no `releases` map in the previous sidecar) carries every partition,
# so it is a complete baseline.
#
# Fields added to `__source_hash.json` (the snapshot release and
# `-latest` carry the same sidecar; the history map and the history
# assets stay on `-latest` only):
#   snapshot  : "YYYY-MM-DD" of the snapshot whose content this is
#   snapshots : every snapshot date published so far, ascending
#   releases  : {partition path: tag of the snapshot holding its bytes}
#   files     : {partition path: {sha256 of the file bytes, size}}, so
#               the client can verify a download (ROADMAP "Integridade
#               do download") and tell a cached copy of another snapshot
#               from the pinned one

stopifnot(requireNamespace("digest", quietly = TRUE))

# Partitions whose bytes go into today's snapshot: the new ones and the
# ones whose content hash moved — or every partition when the previous
# sidecar cannot tell (first snapshot, or a sidecar written before this
# feature, which has no `releases` map).
snapshot_changed_partitions <- function(prev, data) {
  rels <- names(data)
  if (is.null(prev) || is.null(prev$releases) || is.null(prev$data)) {
    return(rels)
  }
  Filter(
    function(rel) {
      is.null(prev$data[[rel]]) ||
        !identical(prev$data[[rel]], data[[rel]]) ||
        is.null(prev$releases[[rel]])
    },
    rels
  )
}

# {partition: snapshot tag} after this run: the changed partitions point
# to `tag`, the others keep the pointer of the previous sidecar.
snapshot_releases_map <- function(prev, data, changed, tag) {
  out <- list()
  for (rel in names(data)) {
    out[[rel]] <- if (rel %in% changed) tag else prev$releases[[rel]]
  }
  out
}

# Ascending, unique snapshot dates after adding `date`. jsonlite writes a
# single date as a scalar, hence the `unlist()`.
snapshot_dates <- function(prev, date) {
  prior <- as.character(unlist(prev$snapshots %||% list()))
  sort(unique(c(prior, format(date, "%Y-%m-%d"))))
}

# {partition: list(sha256, size)} of the parquet files as uploaded to
# `-latest`, which is rewritten whole on every run.
snapshot_file_digests <- function(parquets, dataset_dir) {
  rels <- substring(parquets, nchar(dataset_dir) + 2L)
  out <- lapply(parquets, function(p) {
    list(
      sha256 = digest::digest(file = p, algo = "sha256"),
      size = file.size(p)
    )
  })
  names(out) <- gsub("\\", "/", rels, fixed = TRUE)
  out
}

# {partition: list(sha256, size)} of the bytes a dated snapshot points to
# (decision of 2026-11-07, after the Zenodo edition robot found 12 of 18
# vlmo partitions failing the digest check). A parquet written by two
# runs from the same rows differs in bytes (its metadata carries the
# run's `fetched_at`), so the digest of the local file describes the
# asset uploaded to `-latest` and NOT the bytes of an unchanged
# partition, which live in the earlier snapshot `releases` points to.
# Until this map existed the dated sidecars carried the local digests
# and a client pinned to any date but the latest snapshot failed with
# `cvmdata_error_http_integrity` on every unchanged partition (measured
# on 2026-11-07: dfp composicao_capital 2021 pinned to 2026-11-04,
# 48,000 bytes expected, 48,001 served). The changed partitions take
# the local digest (those bytes are being uploaded to the snapshot);
# the others keep what the previous `-latest` sidecar recorded under
# `snapshot_files`, carried over run after run. The dated sidecar's
# `files` is this map; the `-latest` sidecar keeps the local digests in
# `files` and this map in `snapshot_files`.
#
# A previous sidecar without `snapshot_files` (written before this
# feature) cannot say what the earlier snapshots hold: the run stops
# and asks for inst/etl/repair-snapshot-digests.R, which rewrites every
# dated sidecar from the bytes themselves. Failing is deliberate: a
# wrong digest in a sidecar that is never rewritten is permanent.
snapshot_pointer_digests <- function(local, prev, changed) {
  out <- local
  carried <- prev$snapshot_files %||% list()
  for (rel in names(out)) {
    if (rel %in% changed) {
      next
    }
    entry <- carried[[rel]]
    if (is.null(entry)) {
      stop(
        sprintf(
          paste(
            "the sidecar of -latest has no `snapshot_files` entry for the",
            "unchanged partition %s; run inst/etl/repair-snapshot-digests.R",
            "for this dataset first"
          ),
          rel
        ),
        call. = FALSE
      )
    }
    out[[rel]] <- entry
  }
  out
}

# The sidecar of a dated snapshot with its `files` map rebuilt from the
# bytes at the pointers: `lookup(tag, rel)` returns list(sha256, size)
# of the asset `rel` on release `tag`. Returns list(sidecar, fixed =
# the partitions whose digest changed). Used by the repair script and
# by its test.
snapshot_repair_files <- function(sidecar, lookup) {
  fixed <- character()
  for (rel in names(sidecar$files %||% list())) {
    tag <- sidecar$releases[[rel]]
    if (is.null(tag)) {
      stop(sprintf("no release pointer for %s", rel), call. = FALSE)
    }
    actual <- lookup(tag, rel)
    if (!identical(actual$sha256, sidecar$files[[rel]]$sha256)) {
      fixed <- c(fixed, rel)
    }
    sidecar$files[[rel]] <- list(sha256 = actual$sha256, size = actual$size)
  }
  list(sidecar = sidecar, fixed = fixed)
}

# A sidecar read back from JSON with its `skips` fields made scalar
# again: a missing `year` or `report_type` is `null` in what 03-publish.R
# writes, and `read_json()` gives NULL for it; a sidecar rewritten by a
# tool that encoded NULL as `{}` (the first repair of 2026-11-07) gives
# an empty list instead, which `write_json()` keeps as `{}` and the
# client reads as a list column. Both become NULL here, so the next
# write (with `null = "null"`) puts `null` back. Returns list(sidecar,
# changed = whether any field was an empty list).
snapshot_normalise_skips <- function(sidecar) {
  changed <- FALSE
  skips <- sidecar$skips
  if (is.list(skips) && length(skips)) {
    for (k in seq_along(skips)) {
      entry <- skips[[k]]
      for (field in names(entry)) {
        value <- entry[[field]]
        if (is.list(value) && !length(value)) {
          entry[field] <- list(NULL)
          changed <- TRUE
        }
      }
      skips[[k]] <- entry
    }
    sidecar$skips <- skips
  }
  list(sidecar = sidecar, changed = changed)
}

# A sidecar without the partitions of tables the mirror no longer carries
# (`mirror: false` in the schema): their entries leave every map keyed by
# partition. Returns list(sidecar, dropped = the partition paths removed).
# The assets themselves are deleted by repair-personal-data.R.
snapshot_drop_tables <- function(sidecar, excluded) {
  gone <- function(rels) {
    tables <- vapply(
      rels,
      function(rel) strsplit(rel, "/", fixed = TRUE)[[1L]][[1L]],
      character(1L)
    )
    rels[tables %in% excluded]
  }
  dropped <- character()
  for (field in c("data", "files", "releases", "snapshot_files")) {
    map <- sidecar[[field]]
    if (!is.list(map) || !length(map)) {
      next
    }
    out <- gone(names(map))
    dropped <- union(dropped, out)
    sidecar[[field]] <- map[setdiff(names(map), out)]
  }
  list(sidecar = sidecar, dropped = dropped)
}

# A dated sidecar with `privacy_omitted` filled from what the repair of
# the parquets measured before rewriting them: `reports[[tag]][[key(rel)]]`
# is the report of `mirror_group_report()` for the asset of partition `rel`
# on release `tag`. A partition points to the snapshot that holds its
# bytes, so one report serves every later sidecar that points there.
# Entries already in the sidecar stay unless a report replaces them.
# Returns list(sidecar, added = number of entries written).
snapshot_add_omitted <- function(sidecar, reports, key = identity) {
  entries <- sidecar$privacy_omitted %||% list()
  id <- function(e) paste(e$table, e$year %||% "", sep = "\r")
  names(entries) <- vapply(entries, id, character(1L))
  added <- 0L
  for (rel in names(sidecar$releases %||% list())) {
    report <- reports[[sidecar$releases[[rel]]]][[key(rel)]]
    if (is.null(report)) {
      next
    }
    year <- regmatches(rel, regexpr("(?<=year=)[0-9]{4}", rel, perl = TRUE))
    entry <- c(
      list(
        table = strsplit(rel, "/", fixed = TRUE)[[1L]][[1L]],
        year = if (length(year)) as.integer(year) else NULL
      ),
      report
    )
    entry$cnpj <- I(as.character(unlist(entry$cnpj)))
    entries[[id(entry)]] <- entry
    added <- added + 1L
  }
  if (length(entries)) {
    sidecar$privacy_omitted <- unname(entries)
  }
  list(sidecar = sidecar, added = added)
}
