# ETL helpers for the quarterly DOI editions of the mirror on Zenodo
# (design decided by the owner on 2026-11-06; ROADMAP item "DOI por
# EDIÇÃO trimestral do espelho").
#
# Four editions a year, dated on the first weekly round (a Tuesday) of
# January, April, July and October, the same calendar for every
# dataset. An edition is the whole mirror as it was on that day — the
# partitions `cvm_release_set(D)` reads — plus the history assets, a
# README, the column dictionary, the data licence and the checksums, in
# ONE Zenodo record with one version per edition (a concept DOI for the
# record and a DOI per edition). The robot PREPARES the edition as a
# draft and never publishes it: the owner reads the report and
# publishes on the site, because a published record cannot be deleted.
# No function here reaches the publish action: `zenodo_action()` only
# accepts the actions of `zenodo_actions_allowed`, and
# tests/testthat/test-etl-zenodo.R reads this file to prove the
# endpoint is absent.
#
# The checks the owner asked for, in the order 06-zenodo-edition.R runs
# them: every partition of every dataset present with the sha256 the
# mirror published for it; row counts compared with the previous
# edition; the files of the draft read back from Zenodo and compared
# with the local copy. A check that fails leaves no draft behind.
#
# Depends on 00-config.R and util-release.R having been sourced.

stopifnot(requireNamespace("httr2", quietly = TRUE))
stopifnot(requireNamespace("jsonlite", quietly = TRUE))
stopifnot(requireNamespace("digest", quietly = TRUE))

# --- the calendar -----------------------------------------------------

# Months with an edition, and the days between the edition date and the
# deposit: a defect found days after a round (the 99,070 false history
# rows of 2026-11-03 surfaced on 05/11) must have time to appear.
edition_months <- c(1L, 4L, 7L, 10L)
edition_grace_days <- 14L

# The first Tuesday of a month, the day of the first weekly round of
# the mirror (etl-mirror.yaml runs on Tuesdays at 07:00 UTC).
edition_first_tuesday <- function(year, month) {
  first <- as.Date(sprintf("%04d-%02d-01", as.integer(year), as.integer(month)))
  weekday <- as.integer(format(first, "%u")) # 1 = Monday ... 7 = Sunday
  first + ((2L - weekday) %% 7L)
}

# Every edition date of `years`, ascending.
edition_dates <- function(years) {
  dates <- unlist(lapply(years, function(y) {
    vapply(
      edition_months,
      function(m) as.character(edition_first_tuesday(y, m)),
      character(1L)
    )
  }))
  sort(as.Date(dates))
}

# The edition the robot prepares when run on `today`: the most recent
# edition date whose grace has elapsed. A run on the scheduled day (the
# 22nd of an edition month) always lands on that month's edition; a run
# on any other day lands on the previous one, which is what a repeat
# after a failure should prepare.
edition_date_for <- function(today = Sys.Date(), grace = edition_grace_days) {
  today <- as.Date(today)
  year <- as.integer(format(today, "%Y"))
  candidates <- edition_dates(c(year - 1L, year))
  eligible <- candidates[candidates + as.integer(grace) <= today]
  if (!length(eligible)) {
    stop("no edition date with its grace elapsed", call. = FALSE)
  }
  max(eligible)
}

# The most recent snapshot of a dataset on or before the edition date,
# from the `snapshots` list of its `-latest` sidecar: the same rule the
# client applies to a pinned date (R/util-mirror-assets.R).
edition_pick_snapshot <- function(dates, edition, dataset) {
  dates <- sort(unique(as.character(unlist(dates))))
  dates <- dates[!is.na(dates) & nzchar(dates)]
  edition <- format(as.Date(edition), "%Y-%m-%d")
  eligible <- dates[dates <= edition]
  if (!length(eligible)) {
    stop(
      sprintf(
        "%s has no snapshot on or before %s%s",
        dataset,
        edition,
        if (length(dates)) sprintf(" (earliest: %s)", dates[[1L]]) else ""
      ),
      call. = FALSE
    )
  }
  eligible[[length(eligible)]]
}

# --- the files of a dataset ------------------------------------------

# The files one dataset contributes to the edition, from two parsed
# sidecars: `snapshot` (the `__source_hash.json` of the snapshot the
# edition date resolves to; its `files` map carries the sha256 and size
# of every partition and its `releases` map the release holding the
# bytes) and `latest` (the `-latest` sidecar, whose `history` map names
# the history assets; those live on `-latest` only and are taken as
# they are on the deposit day, which the README of the edition says).
# One row per file: dataset, kind ("partition" or "history"), rel (the
# partition path), tag (the release to download from), name (the asset
# name on that release), sha256 and size (NA for history assets).
edition_plan_dataset <- function(group, dataset, latest, snapshot) {
  rels <- names(snapshot$files %||% list())
  if (!length(rels)) {
    stop(
      sprintf(
        "the snapshot %s of %s has no `files` map",
        snapshot$snapshot %||% "?",
        dataset
      ),
      call. = FALSE
    )
  }
  pick <- function(map, rel, field = NULL) {
    value <- map[[rel]]
    if (!is.null(field)) {
      value <- value[[field]]
    }
    value
  }
  tags <- vapply(
    rels,
    function(rel) pick(snapshot$releases, rel) %||% NA_character_,
    character(1L)
  )
  if (anyNA(tags)) {
    stop(
      sprintf(
        "the snapshot %s of %s does not say where %d partition(s) live",
        snapshot$snapshot %||% "?",
        dataset,
        sum(is.na(tags))
      ),
      call. = FALSE
    )
  }
  partitions <- data.frame(
    dataset = dataset,
    kind = "partition",
    rel = rels,
    tag = unname(tags),
    sha256 = vapply(
      rels,
      function(rel) pick(snapshot$files, rel, "sha256") %||% NA_character_,
      character(1L)
    ),
    size = vapply(
      rels,
      function(rel) as.numeric(pick(snapshot$files, rel, "size") %||% NA),
      numeric(1L)
    ),
    stringsAsFactors = FALSE
  )
  history_rels <- names(latest$history %||% list())
  history <- data.frame(
    dataset = rep(dataset, length(history_rels)),
    kind = rep("history", length(history_rels)),
    rel = history_rels,
    tag = rep(mirror_tag_latest(group, dataset), length(history_rels)),
    sha256 = rep(NA_character_, length(history_rels)),
    size = rep(NA_real_, length(history_rels)),
    stringsAsFactors = FALSE
  )
  out <- rbind(partitions, history)
  out$name <- public_asset_name(out$rel)
  rownames(out) <- NULL
  attr(out, "snapshot") <- snapshot$snapshot
  out
}

# The two sidecars of a dataset for the edition: list(latest, snapshot,
# date), `latest` for the history map and the snapshot dates, `snapshot`
# (the dated release's own sidecar) for the partitions and their digests.
edition_read_sidecars <- function(group, dataset, edition, dir) {
  latest_tag <- mirror_tag_latest(group, dataset)
  latest_dir <- file.path(dir, latest_tag)
  dir.create(latest_dir, recursive = TRUE, showWarnings = FALSE)
  latest_file <- download_public_asset(
    latest_tag,
    "__source_hash.json",
    latest_dir
  )
  if (is.null(latest_file)) {
    stop(
      sprintf("release %s has no __source_hash.json", latest_tag),
      call. = FALSE
    )
  }
  latest <- jsonlite::read_json(latest_file)
  date <- edition_pick_snapshot(latest$snapshots, edition, dataset)
  # Always the dated sidecar, even for the snapshot `-latest` carries:
  # since 2026-11-07 its `files` map holds the digests of the bytes at
  # the pointers, while `-latest` describes its own rewritten assets.
  tag <- mirror_tag_snapshot(group, dataset, as.Date(date))
  snapshot_dir <- file.path(dir, tag)
  dir.create(snapshot_dir, recursive = TRUE, showWarnings = FALSE)
  snapshot_file <- download_public_asset(
    tag,
    "__source_hash.json",
    snapshot_dir
  )
  if (is.null(snapshot_file)) {
    stop(sprintf("release %s has no __source_hash.json", tag), call. = FALSE)
  }
  list(
    latest = latest,
    snapshot = jsonlite::read_json(snapshot_file),
    date = date
  )
}

# Downloads every file of `plan` under `dir/<dataset>/<rel>` and returns
# the plan with `path`, `sha256_actual` and `size_actual`. A file the
# mirror does not deliver is an error: the edition is complete or it is
# nothing.
edition_fetch_dataset <- function(plan, dir) {
  plan$path <- file.path(dir, plan$dataset, plan$rel)
  plan$sha256_actual <- NA_character_
  plan$size_actual <- NA_real_
  staging <- file.path(dir, "__download")
  dir.create(staging, recursive = TRUE, showWarnings = FALSE)
  for (k in seq_len(nrow(plan))) {
    target <- plan$path[[k]]
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    got <- download_public_asset(plan$tag[[k]], plan$name[[k]], staging)
    if (is.null(got)) {
      stop(
        sprintf(
          "%s: asset %s of release %s could not be downloaded",
          plan$dataset[[k]],
          plan$name[[k]],
          plan$tag[[k]]
        ),
        call. = FALSE
      )
    }
    if (!file.rename(got, target)) {
      file.copy(got, target, overwrite = TRUE)
      unlink(got)
    }
    plan$sha256_actual[[k]] <- digest::digest(file = target, algo = "sha256")
    plan$size_actual[[k]] <- file.size(target)
  }
  plan
}

# The partitions whose bytes differ from what the mirror published:
# data.frame(dataset, rel, expected, actual), empty when every one
# matches. History assets have no published digest and are not judged.
edition_verify_digests <- function(plan) {
  judged <- plan[plan$kind == "partition", , drop = FALSE]
  bad <- is.na(judged$sha256) | judged$sha256 != judged$sha256_actual
  out <- data.frame(
    dataset = judged$dataset[bad],
    rel = judged$rel[bad],
    expected = judged$sha256[bad],
    actual = judged$sha256_actual[bad],
    stringsAsFactors = FALSE
  )
  rownames(out) <- NULL
  out
}

# --- row counts ------------------------------------------------------

# Rows of a parquet file. The table is read and dropped at once rather
# than counted from the footer with `ParquetFileReader`, whose object
# holds the file open until it is collected (on Windows that blocks
# the file time the packing sets).
edition_row_count <- function(path) {
  arrow::read_parquet(path, as_data_frame = FALSE)$num_rows
}

# Table of a partition path: its first segment (as
# `mirror_partition_table()` of util-history.R, not sourced here).
edition_table_of <- function(rel) {
  strsplit(rel, "/", fixed = TRUE)[[1L]][[1L]]
}

# Row counts of the edition by (dataset, kind, table), summed over the
# partitions of a table: the unit the owner compares between editions.
edition_count_tables <- function(plan) {
  tables <- vapply(plan$rel, edition_table_of, character(1L))
  key <- paste(plan$dataset, plan$kind, tables, sep = "\r")
  rows <- vapply(split(plan$rows, key), sum, numeric(1L))
  parts <- strsplit(names(rows), "\r", fixed = TRUE)
  out <- data.frame(
    dataset = vapply(parts, `[[`, character(1L), 1L),
    kind = vapply(parts, `[[`, character(1L), 2L),
    table = vapply(parts, `[[`, character(1L), 3L),
    rows = unname(rows),
    stringsAsFactors = FALSE
  )
  out <- out[order(out$dataset, out$kind, out$table), , drop = FALSE]
  rownames(out) <- NULL
  out
}

# The counts of this edition beside those of the previous one, by
# (dataset, kind, table): rows_prev is NA for a table the previous
# edition did not have, rows_now for one it had and this one lacks.
edition_compare_counts <- function(now, prev) {
  if (is.null(prev) || !nrow(prev)) {
    out <- now
    out$rows_prev <- NA_real_
    names(out)[names(out) == "rows"] <- "rows_now"
    return(out[c("dataset", "kind", "table", "rows_prev", "rows_now")])
  }
  names(now)[names(now) == "rows"] <- "rows_now"
  names(prev)[names(prev) == "rows"] <- "rows_prev"
  out <- merge(
    prev[c("dataset", "kind", "table", "rows_prev")],
    now[c("dataset", "kind", "table", "rows_now")],
    by = c("dataset", "kind", "table"),
    all = TRUE
  )
  out <- out[order(out$dataset, out$kind, out$table), , drop = FALSE]
  rownames(out) <- NULL
  out
}

# The comparisons the edition fails on. The CVM data only accumulates
# and the history only grows, so a table with fewer rows than the
# previous edition, or a table that disappeared, is a sign of a lost
# partition or of a prune — and a prune that was decided (the one of
# 2026-11-05 removed 99,070 rows) is passed with `allow_shrink`. Growth
# is reported, never failed: a legitimate week can triple the usual
# volume (the renames of 2026-11-03).
edition_count_failures <- function(comparison, allow_shrink = FALSE) {
  gone <- !is.na(comparison$rows_prev) & is.na(comparison$rows_now)
  shrunk <- !is.na(comparison$rows_prev) &
    !is.na(comparison$rows_now) &
    comparison$rows_now < comparison$rows_prev
  bad <- gone | (shrunk & !isTRUE(allow_shrink))
  out <- comparison[bad, , drop = FALSE]
  out$reason <- ifelse(gone[bad], "table missing", "fewer rows")
  rownames(out) <- NULL
  out
}

# --- the package of files ---------------------------------------------

# The manifest of the edition, one row per file: what `manifest.csv`
# carries and what the next edition compares its counts against.
edition_manifest <- function(plans) {
  out <- do.call(
    rbind,
    lapply(plans, function(plan) {
      data.frame(
        dataset = plan$dataset,
        snapshot = rep(attr(plan, "snapshot"), nrow(plan)),
        kind = plan$kind,
        rel = plan$rel,
        release = plan$tag,
        sha256 = plan$sha256_actual,
        size = plan$size_actual,
        rows = plan$rows,
        stringsAsFactors = FALSE
      )
    })
  )
  rownames(out) <- NULL
  out
}

# The row counts by (dataset, kind, table) of a manifest read from a
# previous edition.
edition_counts_from_manifest <- function(manifest) {
  plan <- manifest[c("dataset", "kind", "rel", "rows")]
  edition_count_tables(plan)
}

# Packs the files of one dataset into `<group>-<dataset>.tar` under
# `out_dir`, with the paths `<dataset>/<rel>` inside. No compression:
# the parquets are snappy-compressed already, and R's internal tar
# needs no external binary. File times are set to the edition date so a
# dataset that did not change between two editions packs to the same
# bytes and Zenodo keeps the file instead of taking it again.
edition_pack_dataset <- function(plan, group, dir, out_dir, edition) {
  dataset <- plan$dataset[[1L]]
  tarfile <- file.path(out_dir, sprintf("%s-%s.tar", group, dataset))
  stamp <- as.POSIXct(paste(format(as.Date(edition)), "00:00:00"), tz = "UTC")
  Sys.setFileTime(plan$path, stamp)
  old <- setwd(dir)
  on.exit(setwd(old), add = TRUE)
  utils::tar(
    tarfile,
    files = dataset,
    compression = "none",
    tar = "internal"
  )
  tarfile
}

# The `SHA256SUMS` lines of the files of the deposit, in the format of
# `sha256sum`, so `sha256sum -c SHA256SUMS` verifies a download.
edition_sha256sums <- function(paths) {
  sprintf(
    "%s  %s",
    vapply(
      paths,
      function(p) digest::digest(file = p, algo = "sha256"),
      character(1L)
    ),
    basename(paths)
  )
}

# The README of the deposit: what the edition is, how it was made, how
# to read it, and what it does not guarantee.
edition_readme <- function(
  edition,
  snapshots,
  counts,
  package_version,
  deposit_date = Sys.Date()
) {
  per_dataset <- vapply(
    names(snapshots),
    function(ds) {
      rows <- counts[counts$dataset == ds, , drop = FALSE]
      sprintf(
        "| `%s` | %s | %s | %s |",
        ds,
        snapshots[[ds]],
        format(sum(rows$rows[rows$kind == "partition"]), big.mark = ","),
        format(sum(rows$rows[rows$kind == "history"]), big.mark = ",")
      )
    },
    character(1L)
  )
  c(
    sprintf("# cvmdata mirror — edition %s", edition),
    "",
    paste(
      "This deposit is one edition of the parquet mirror of the Open Data",
      "Portal of the Comissão de Valores Mobiliários (CVM), the Brazilian",
      "securities regulator, as served by the R package `cvmdata`",
      "(<https://github.com/SidneyBissoli/cvmdata>). It holds every",
      "dataset of the mirror exactly as it was on the edition date, so a",
      "result computed from it can be cited and reproduced after the",
      "GitHub releases that serve the live mirror are gone."
    ),
    "",
    "## What is here",
    "",
    sprintf(
      paste(
        "Edition date: %s. Deposited on %s, after a grace period in",
        "which defects found in the weekly rounds are fixed before the",
        "edition is frozen. Built with cvmdata %s."
      ),
      edition,
      format(as.Date(deposit_date)),
      package_version
    ),
    "",
    "| Dataset | Mirror snapshot | Rows (current) | Rows (history) |",
    "|---|---|---|---|",
    per_dataset,
    "",
    paste(
      "One `companhias-<dataset>.tar` per dataset, no compression (the",
      "parquet files inside are snappy-compressed). Inside, the current",
      "data is at"
    ),
    "",
    "```",
    "<dataset>/<table>/[report_type=<ind|con>/][year=<YYYY>/]part-0.parquet",
    "```",
    "",
    paste(
      "(Hive-style partitions; `arrow::open_dataset()` and DuckDB read them",
      "as one table), and the superseded versions of the same partition at",
      "`<dataset>/<table>/.../history.parquet` (see *History*)."
    ),
    "",
    "Alongside the tar files:",
    "",
    "- `manifest.csv`: every file of the edition with the mirror release",
    "  it came from, its SHA-256, size and row count.",
    "- `cvm_dictionary.csv`: the column dictionary of every table (column",
    "  name in the mirror, original CVM name, description, domain, type).",
    "- `cvm_codelists.csv`: the code lists the CVM publishes for coded",
    "  columns.",
    "- `DATA-LICENSE.md`: the licence of the data and the attribution it",
    "  requires.",
    "- `SHA256SUMS`: the digests of the files of this deposit",
    "  (`sha256sum -c SHA256SUMS`).",
    "",
    "## How the data was made",
    "",
    paste(
      "The ETL of the package (`inst/etl/` in the repository) downloads",
      "the CSV files the CVM publishes, reads them with the encoding and",
      "the column types the package's schemas declare, lowercases the",
      "column names, parses dates and numbers, and writes one parquet",
      "partition per table, statement basis (individual or consolidated)",
      "and reference year. Values are kept as the CVM delivers them: no",
      "row is dropped, no value is corrected. The mirror is refreshed",
      "every week; an edition is the mirror as it stood on the first",
      "weekly round of January, April, July or October."
    ),
    "",
    "### History",
    "",
    paste(
      "The CVM rewrites its yearly CSV files in place, so a filing that",
      "was restated is gone from the portal; the mirror keeps the",
      "superseded versions in the `history.parquet` files, appended by",
      "the weekly ETL (versions the mirror saw replaced) and by a second",
      "robot that reads the CVM document system (RAD) for the versions",
      "replaced before the mirror existed. The history files of this",
      "edition are the ones of the deposit day, not of the edition date:",
      "they only grow, so the edition date's versions are all there, with",
      "the ones recovered during the grace period. Superseded DFP and",
      "ITR versions carry the column `scale_error`, which says whether",
      "the version was replaced only because it was filed in the wrong",
      "unit (`cvm_versions()` in the package documents the rule)."
    ),
    "",
    "## How to read it",
    "",
    "```r",
    "# any parquet reader works; with arrow:",
    "untar(\"companhias-dfp.tar\")",
    "dfp_dre <- arrow::open_dataset(\"dfp/dre\")",
    "",
    "# or with DuckDB:",
    "# SELECT * FROM read_parquet('dfp/dre/**/part-0.parquet',",
    "#                            hive_partitioning = true)",
    "```",
    "",
    paste(
      "The package reads the same bytes from the live mirror with",
      "`cvm_release_set(\"<edition date>\")` followed by `cvm_fetch()`,",
      "as long as the GitHub releases exist."
    ),
    "",
    "## Licence and citation",
    "",
    paste(
      "The data is published by the CVM under the Open Data Commons Open",
      "Database License (ODbL) v1.0 and redistributed here under the same",
      "licence as a derivative database; `DATA-LICENSE.md` has the terms",
      "and the attribution. Cite this edition by its DOI and the CVM as",
      "the source of the data."
    ),
    ""
  )
}

# The Zenodo metadata of the edition. `related_identifiers` ties the
# record to the portal it derives from and to the package that built
# it; `version` is the edition date, so the versions of the record sort
# by date.
edition_metadata <- function(edition, snapshots, package_version, description) {
  list(
    upload_type = "dataset",
    publication_date = format(as.Date(edition)),
    title = sprintf(
      paste(
        "cvmdata mirror: open data of the Brazilian securities regulator",
        "(CVM) in parquet, edition %s"
      ),
      edition
    ),
    creators = list(list(
      name = "Bissoli, Sidney da Silva Pereira",
      orcid = "0009-0001-0442-3700"
    )),
    description = description,
    access_right = "open",
    license = zenodo_license_odbl,
    version = format(as.Date(edition)),
    language = "eng",
    keywords = list(
      "CVM",
      "Brazil",
      "open data",
      "financial statements",
      "listed companies",
      "parquet",
      "cvmdata"
    ),
    related_identifiers = list(
      list(
        identifier = "https://dados.cvm.gov.br/",
        relation = "isDerivedFrom"
      ),
      list(
        identifier = "https://github.com/SidneyBissoli/cvmdata",
        relation = "isCompiledBy",
        resource_type = "software"
      ),
      list(
        identifier = "https://sidneybissoli.github.io/cvmdata/",
        relation = "isDocumentedBy"
      )
    ),
    notes = sprintf(
      paste(
        "Mirror snapshots per dataset: %s. Prepared by the cvmdata ETL",
        "(version %s); published by the maintainer after the checks of",
        "the preparation report."
      ),
      paste(
        sprintf("%s %s", names(snapshots), unlist(snapshots)),
        collapse = "; "
      ),
      package_version
    )
  )
}

# The HTML description shown on the Zenodo page.
edition_description <- function(edition, snapshots, counts) {
  rows <- vapply(
    names(snapshots),
    function(ds) {
      r <- counts[counts$dataset == ds, , drop = FALSE]
      sprintf(
        paste0(
          "<li><code>%s</code>: snapshot of %s, %s current rows, ",
          "%s history rows</li>"
        ),
        ds,
        snapshots[[ds]],
        format(sum(r$rows[r$kind == "partition"]), big.mark = ","),
        format(sum(r$rows[r$kind == "history"]), big.mark = ",")
      )
    },
    character(1L)
  )
  paste0(
    "<p>Quarterly edition of the parquet mirror of the Open Data Portal ",
    "of the Comissão de Valores Mobiliários (CVM), the Brazilian ",
    "securities regulator, served by the R package ",
    "<a href=\"https://github.com/SidneyBissoli/cvmdata\">cvmdata</a>. ",
    "The edition is every dataset of the mirror as it was on ",
    edition,
    ", with the superseded versions of the filings (history), the column ",
    "dictionary, the code lists, the data licence and the checksums. ",
    "One tar file per dataset; the README inside the deposit says how it was ",
    "made and how to read it.</p>",
    "<ul>",
    paste(rows, collapse = ""),
    "</ul>",
    "<p>Data licence: ODbL v1.0, as published by the CVM; this deposit is a ",
    "derivative database under the same licence.</p>"
  )
}

# --- the Zenodo API --------------------------------------------------

# The sandbox comes first: a record published there is disposable, one
# published in production is forever.
zenodo_base_url <- function(target = c("sandbox", "production")) {
  target <- match.arg(target)
  switch(
    target,
    sandbox = "https://sandbox.zenodo.org",
    production = "https://zenodo.org"
  )
}

zenodo_client <- function(token, target = c("sandbox", "production")) {
  target <- match.arg(target)
  if (!is.character(token) || length(token) != 1L || !nzchar(token)) {
    stop(sprintf("no Zenodo token for the %s", target), call. = FALSE)
  }
  list(base = zenodo_base_url(target), token = token, target = target)
}

# A request to the API with the token, retried on the transient
# statuses, and whose status the caller judges (`zenodo_perform()`).
zenodo_request <- function(client, path) {
  url <- if (startsWith(path, "http")) path else paste0(client$base, path)
  httr2::request(url) |>
    httr2::req_auth_bearer_token(client$token) |>
    httr2::req_user_agent("cvmdata-etl (zenodo edition)") |>
    httr2::req_error(is_error = function(resp) FALSE) |>
    httr2::req_retry(
      max_tries = 4L,
      is_transient = function(resp) {
        httr2::resp_status(resp) %in% c(429L, 500L, 502L, 503L, 504L)
      },
      backoff = function(attempt) 10 * attempt,
      retry_on_failure = TRUE
    )
}

# Performs a request and returns the parsed JSON body (NULL for 204), or
# stops naming the status and the message the API gave.
zenodo_perform <- function(req, ok = c(200L, 201L, 202L, 204L), what = "") {
  resp <- httr2::req_perform(req)
  status <- httr2::resp_status(resp)
  if (!status %in% ok) {
    body <- tryCatch(
      httr2::resp_body_string(resp),
      error = function(e) ""
    )
    stop(
      sprintf(
        "Zenodo answered %d to %s %s%s",
        status,
        req$method %||% "GET",
        req$url,
        if (nzchar(body)) paste0(": ", substr(body, 1L, 500L)) else ""
      ),
      call. = FALSE
    )
  }
  if (status == 204L || !length(httr2::resp_body_raw(resp))) {
    return(NULL)
  }
  httr2::resp_body_json(resp)
}

zenodo_get <- function(client, path, what = "") {
  zenodo_perform(zenodo_request(client, path), what = what)
}

# The actions the robot may run on a deposition. Publishing is not one
# of them, by design: the owner publishes on the site after reading the
# report. `newversion` opens the draft of the next edition; `discard`
# throws away a draft that failed a check.
zenodo_actions_allowed <- c("newversion", "edit", "discard")

zenodo_action <- function(client, id, action) {
  if (!action %in% zenodo_actions_allowed) {
    stop(
      sprintf("the robot never runs the Zenodo action '%s'", action),
      call. = FALSE
    )
  }
  req <- zenodo_request(
    client,
    sprintf("/api/deposit/depositions/%s/actions/%s", id, action)
  ) |>
    httr2::req_method("POST")
  zenodo_perform(req, what = action)
}

# Does the token open the account? A 401 here says the secret is
# missing or wrong before anything is downloaded.
zenodo_check_token <- function(client) {
  zenodo_get(client, "/api/deposit/depositions?size=1")
  invisible(TRUE)
}

# Is the licence id known to this Zenodo? The id of the ODbL is checked
# before the metadata is sent, so a renamed vocabulary fails the run
# with a clear message instead of a 400 on the metadata. The sandbox
# trial of 2026-11-07 is why: the legacy `/api/licenses/<id>` answers
# 404 and the opendefinition id `odc-odbl` is not the one Zenodo uses;
# the vocabulary is `/api/vocabularies/licenses/<id>` and the ODbL is
# `odbl-1.0` (the same on both sites).
zenodo_license_odbl <- "odbl-1.0"

zenodo_check_license <- function(client, license = zenodo_license_odbl) {
  zenodo_get(client, sprintf("/api/vocabularies/licenses/%s", license))
  invisible(TRUE)
}

# Every version of the concept record the token owns.
zenodo_list_versions <- function(client, concept) {
  path <- sprintf(
    "/api/deposit/depositions?q=conceptrecid:%s&all_versions=true&size=100",
    concept
  )
  zenodo_get(client, path) %||% list()
}

# The published version to build the next edition on (the most recent
# by id) and the draft already open, if any: list(published, draft).
zenodo_split_versions <- function(depositions) {
  submitted <- vapply(
    depositions,
    function(d) isTRUE(d$submitted),
    logical(1L)
  )
  published <- depositions[submitted]
  drafts <- depositions[!submitted]
  pick_latest <- function(x) {
    if (!length(x)) {
      return(NULL)
    }
    ids <- vapply(x, function(d) as.numeric(d$id), numeric(1L))
    x[[which.max(ids)]]
  }
  list(published = pick_latest(published), draft = pick_latest(drafts))
}

# The draft the edition goes into. Without a concept record the first
# edition opens a new deposition, created with its metadata in the body
# (the sandbox trial of 2026-11-07 answered 500 to a body of `[]`: an
# empty R list serialises as an array, and the API wants an object);
# with one, the draft already open is reused (a run repeated after a
# failure) or a new version of the latest published edition is opened,
# and the metadata is set afterwards. The deposition returned is fresh
# from the API, with its `links$bucket`.
zenodo_open_draft <- function(client, concept = NULL, metadata = NULL) {
  if (is.null(concept) || !nzchar(concept)) {
    body <- if (is.null(metadata)) {
      structure(list(), names = character())
    } else {
      list(metadata = metadata)
    }
    draft <- zenodo_perform(
      zenodo_request(client, "/api/deposit/depositions") |>
        httr2::req_method("POST") |>
        httr2::req_body_json(body),
      what = "create"
    )
    attr(draft, "created") <- TRUE
    return(draft)
  }
  versions <- zenodo_split_versions(zenodo_list_versions(client, concept))
  if (!is.null(versions$draft)) {
    draft <- zenodo_get(
      client,
      sprintf("/api/deposit/depositions/%s", versions$draft$id)
    )
    attr(draft, "created") <- FALSE
    return(draft)
  }
  if (is.null(versions$published)) {
    stop(
      sprintf(
        "concept record %s has neither a published version nor a draft",
        concept
      ),
      call. = FALSE
    )
  }
  zenodo_action(client, versions$published$id, "newversion")
  latest <- zenodo_get(
    client,
    sprintf("/api/deposit/depositions/%s", versions$published$id)
  )
  draft_url <- latest$links$latest_draft
  if (is.null(draft_url)) {
    stop("newversion opened no draft (no `latest_draft` link)", call. = FALSE)
  }
  draft <- zenodo_get(client, draft_url)
  attr(draft, "created") <- FALSE
  draft
}

# The files of a deposition as a data.frame(name, id, md5, download).
zenodo_files_table <- function(files) {
  files <- files %||% list()
  data.frame(
    name = vapply(
      files,
      function(f) f$filename %||% f$key %||% NA_character_,
      character(1L)
    ),
    id = vapply(
      files,
      function(f) as.character(f$id %||% NA_character_),
      character(1L)
    ),
    md5 = vapply(
      files,
      function(f) sub("^md5:", "", f$checksum %||% NA_character_),
      character(1L)
    ),
    download = vapply(
      files,
      function(f) f$links$download %||% f$links$self %||% NA_character_,
      character(1L)
    ),
    stringsAsFactors = FALSE
  )
}

# What to do with the files of a draft so they match `local`
# (data.frame(name, md5)): delete the ones that are not in the edition
# or whose bytes differ, upload the ones missing, keep the rest (a
# dataset unchanged since the previous edition is inherited by
# `newversion` and not transferred again).
zenodo_file_actions <- function(remote, local) {
  same <- merge(remote, local, by = "name", suffixes = c("_remote", "_local"))
  keep <- same$name[same$md5_remote == same$md5_local]
  list(
    delete = remote$id[!remote$name %in% keep],
    upload = local$name[!local$name %in% keep],
    keep = keep
  )
}

# Makes the files of the draft match the local files of the edition.
zenodo_sync_files <- function(client, draft, local) {
  remote <- zenodo_files_table(draft$files)
  actions <- zenodo_file_actions(remote, local)
  for (id in actions$delete) {
    zenodo_perform(
      zenodo_request(
        client,
        sprintf("/api/deposit/depositions/%s/files/%s", draft$id, id)
      ) |>
        httr2::req_method("DELETE"),
      what = "delete file"
    )
  }
  bucket <- draft$links$bucket
  if (length(actions$upload) && is.null(bucket)) {
    stop("the draft has no `bucket` link to upload to", call. = FALSE)
  }
  for (name in actions$upload) {
    path <- local$path[local$name == name]
    message(sprintf(
      "  uploading %s (%s MB)",
      name,
      format(round(file.size(path) / 1e6, 1), nsmall = 1L)
    ))
    zenodo_perform(
      zenodo_request(
        client,
        paste0(bucket, "/", utils::URLencode(name, reserved = TRUE))
      ) |>
        httr2::req_method("PUT") |>
        httr2::req_body_file(path, type = "application/octet-stream") |>
        httr2::req_timeout(3600),
      what = "upload"
    )
  }
  actions
}

zenodo_set_metadata <- function(client, draft, metadata) {
  zenodo_perform(
    zenodo_request(client, sprintf("/api/deposit/depositions/%s", draft$id)) |>
      httr2::req_method("PUT") |>
      httr2::req_body_json(list(metadata = metadata)),
    what = "metadata"
  )
}

# Reads the draft back: every file of the edition is listed in the
# draft, nothing else is, and the bytes downloaded from the draft have
# the sha256 of the local file. Returns data.frame(name, status) with
# "ok", "missing", "extra" or "differs".
zenodo_read_back <- function(client, draft_id, local, dir) {
  draft <- zenodo_get(client, sprintf("/api/deposit/depositions/%s", draft_id))
  remote <- zenodo_files_table(draft$files)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  status <- character()
  for (name in local$name) {
    if (!name %in% remote$name) {
      status[[name]] <- "missing"
      next
    }
    target <- file.path(dir, name)
    resp <- zenodo_request(client, remote$download[remote$name == name]) |>
      httr2::req_timeout(3600) |>
      httr2::req_perform(path = target)
    if (httr2::resp_status(resp) != 200L) {
      status[[name]] <- sprintf("download %d", httr2::resp_status(resp))
      next
    }
    got <- digest::digest(file = target, algo = "sha256")
    status[[name]] <- if (identical(got, local$sha256[local$name == name])) {
      "ok"
    } else {
      "differs"
    }
    unlink(target)
  }
  for (name in setdiff(remote$name, local$name)) {
    status[[name]] <- "extra"
  }
  data.frame(
    name = names(status),
    status = unname(status),
    stringsAsFactors = FALSE
  )
}

# Throws a draft away after a failed check: a deposition the run
# created is deleted; the draft of a new version is discarded. Errors
# here are reported, not raised: the run is already failing.
zenodo_drop_draft <- function(client, draft) {
  result <- tryCatch(
    {
      if (isTRUE(attr(draft, "created"))) {
        zenodo_perform(
          zenodo_request(
            client,
            sprintf("/api/deposit/depositions/%s", draft$id)
          ) |>
            httr2::req_method("DELETE"),
          what = "delete draft"
        )
        "deleted"
      } else {
        zenodo_action(client, draft$id, "discard")
        "discarded"
      }
    },
    error = function(e) paste("could not be dropped:", conditionMessage(e))
  )
  result
}

# The content URL of a file of a PUBLISHED record, from the JSON of
# `/api/records/<id>`: `files[].key` names the file and `links$self` is
# the content (`.../files/<key>/content`). The deposit API's file links
# of a published deposition did not serve the bytes in the sandbox
# trial of 2026-11-07 (second run: "the manifest of the previous
# edition could not be downloaded"); the public records API does, with
# or without a token, which is also what a reader of the edition uses.
zenodo_record_file_url <- function(record, name) {
  for (f in record$files %||% list()) {
    if (identical(f$key %||% f$filename, name)) {
      return(f$links$self %||% f$links$content %||% NA_character_)
    }
  }
  NA_character_
}

# The manifest of the latest published edition of the concept record,
# downloaded from the record's `manifest.csv` through the public
# records API, or NULL when there is no published edition yet (the
# first one has nothing to compare with).
zenodo_previous_manifest <- function(client, concept, dir) {
  if (is.null(concept) || !nzchar(concept)) {
    return(NULL)
  }
  versions <- zenodo_split_versions(zenodo_list_versions(client, concept))
  if (is.null(versions$published)) {
    return(NULL)
  }
  record <- zenodo_get(
    client,
    sprintf("/api/records/%s", versions$published$id)
  )
  url <- zenodo_record_file_url(record, "manifest.csv")
  if (is.na(url)) {
    stop(
      sprintf(
        "the published edition %s has no manifest.csv",
        versions$published$id
      ),
      call. = FALSE
    )
  }
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  target <- file.path(dir, "manifest-previous.csv")
  resp <- zenodo_request(client, url) |>
    httr2::req_perform(path = target)
  if (httr2::resp_status(resp) != 200L) {
    stop(
      sprintf(
        paste(
          "the manifest of the previous edition could not be downloaded:",
          "%d from %s"
        ),
        httr2::resp_status(resp),
        url
      ),
      call. = FALSE
    )
  }
  manifest <- utils::read.csv(
    target,
    stringsAsFactors = FALSE,
    encoding = "UTF-8"
  )
  attr(manifest, "edition") <- record$metadata$version %||% NA_character_
  attr(manifest, "doi") <- record$doi %||% NA_character_
  manifest
}

# --- the report ------------------------------------------------------

# A markdown table from a data.frame.
edition_md_table <- function(df) {
  if (!nrow(df)) {
    return("(none)")
  }
  cell <- function(x) {
    x <- as.character(x)
    x[is.na(x)] <- ""
    x
  }
  header <- sprintf("| %s |", paste(names(df), collapse = " | "))
  rule <- sprintf("|%s|", paste(rep("---", ncol(df)), collapse = "|"))
  rows <- apply(df, 1L, function(r) {
    sprintf("| %s |", paste(cell(r), collapse = " | "))
  })
  c(header, rule, unname(rows))
}

# The report the owner reads before publishing.
edition_report <- function(
  edition,
  target,
  snapshots,
  digests_failed,
  comparison,
  count_failures,
  previous,
  files,
  draft = NULL,
  read_back = NULL,
  outcome
) {
  snaps <- data.frame(
    dataset = names(snapshots),
    snapshot = unlist(snapshots),
    stringsAsFactors = FALSE
  )
  previous_line <- if (is.null(previous)) {
    "No previous edition: first edition, counts not compared."
  } else {
    sprintf(
      "Previous edition: %s (DOI %s).",
      attr(previous, "edition") %||% "?",
      attr(previous, "doi") %||% "?"
    )
  }
  c(
    sprintf("# cvmdata edition %s — %s", edition, target),
    "",
    sprintf("**Outcome: %s**", outcome),
    "",
    "## Snapshots",
    "",
    edition_md_table(snaps),
    "",
    "## Digests (partitions vs the mirror's sidecar)",
    "",
    if (nrow(digests_failed)) {
      c(
        sprintf("%d partition(s) differ:", nrow(digests_failed)),
        "",
        edition_md_table(digests_failed)
      )
    } else {
      "Every partition has the sha256 the mirror published."
    },
    "",
    "## Row counts",
    "",
    previous_line,
    "",
    if (nrow(count_failures)) {
      c(
        sprintf("%d table(s) FAILED:", nrow(count_failures)),
        "",
        edition_md_table(count_failures),
        ""
      )
    },
    "<details><summary>All tables</summary>",
    "",
    edition_md_table(comparison),
    "",
    "</details>",
    "",
    "## Files of the deposit",
    "",
    edition_md_table(files),
    "",
    if (!is.null(draft)) {
      c(
        "## Zenodo draft",
        "",
        sprintf("Draft %s: %s", draft$id, draft$links$html %||% ""),
        "",
        if (!is.null(draft$conceptrecid)) {
          c(
            sprintf(
              paste(
                "Concept record id: **%s**. After publishing the first",
                "edition, save it as the repository variable",
                "`ZENODO_%sCONCEPT`, so the next edition is a new version",
                "of this record."
              ),
              draft$conceptrecid,
              if (identical(target, "sandbox")) "SANDBOX_" else ""
            ),
            ""
          )
        },
        if (!is.null(read_back)) {
          c("Read back from the draft:", "", edition_md_table(read_back))
        },
        ""
      )
    },
    "## Next step",
    "",
    if (identical(outcome, "ready")) {
      c(
        "The draft is complete and verified. The robot does not publish:",
        "open the draft on Zenodo, read it over and press *Publish*.",
        "Publishing cannot be undone."
      )
    } else {
      "Nothing to publish: fix the cause and run the edition again."
    },
    ""
  )
}
