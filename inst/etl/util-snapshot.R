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
