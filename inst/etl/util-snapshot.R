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

# {partition: list(sha256, size)} of the parquet files as uploaded.
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
