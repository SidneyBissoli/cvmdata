# Stage 4 — Recover the superseded DFP/ITR filings from the CVM RAD.
#
# The CVM annual files carry only the filing delivered last for each
# (company, reference date). Part 3 of the versions work keeps, from
# 2026-10 on, the rows a NEW mirror publish supersedes
# (`inst/etl/util-history.R`); this stage fills the past: every delivery
# the `submissao` index lists that is NOT the current one is downloaded
# from the RAD (one ZIP per `id_doc`), read with `util-rad.R` into the
# package's tables, and appended to the SAME history assets
# (`<table>__report_type=R__year=Y__history.parquet`) with
# `history_source = "rad"`. Decisions of 2026-10-20 (ROADMAP, Part 3b):
#
# * One run per day, early morning, out of the Tuesday 07:00 UTC window
#   of the mirror ETL; ~300 documents per run (26 s of download plus a
#   10 s crawl delay each), so the ~7,600 backlog takes about a month.
# * Scope: the eight statements of DFP and ITR, individual and
#   consolidated. Parecer, FRE, FCA and CGVN are out.
# * Order: most recent reference year first; DFP before ITR (one dataset
#   per run; the workflow runs DFP first).
# * Each version enters the history ONCE: a filing whose
#   (cnpj, dt_refer, versao) the mirror path already wrote is skipped.
# * Errors: a document that cannot be downloaded or read is set aside
#   WHOLE in a public list (`__rad_unread.csv` next to the parquets) and
#   retried on later runs up to `rad_max_attempts` times with the same
#   reader (`rad_reader_id`; a changed reader starts over). A 403 or an
#   HTML body (the WAF) is first taken as transient: the run pauses
#   `rad_waf_pause` seconds and asks for the SAME document again, up to
#   `rad_waf_retries` times (decision of 2026-10-22: one refusal in the
#   middle of a good run of 74 turned the job red, and the document
#   downloaded whole hours later). Only a document refused every time
#   stops the run. Every failure is recorded with its `kind`:
#   `download` (the RAD did not deliver: transport error, an HTTP
#   status other than 403, or its own error text in plain text instead
#   of the ZIP — not markup, so not the WAF; ITR 67723, 2026-10-30),
#   `document` (the ZIP is not the document the
#   index describes, is not a DFP/ITR at all, or carries no statement
#   with rows), `reader` (the reader could not make sense of it) and
#   `waf`. A `download` failure says something about the document only
#   when the RAD serves the others: `rad_outage_streak` of them in a row
#   is the RAD down (2026-10-31: from 11:20 to about 12:30 UTC every
#   request got "The requested service ... could not be activated", 48
#   DFP and 69 ITR documents in a row; the ITR round read 179 more after
#   it). The documents of the streak go back to how they were before it
#   (an outage does not spend their attempts) and the run pauses
#   `rad_outage_pause` seconds, then goes on with the next documents;
#   past `rad_outage_pauses` pauses in one run it stops as `rad-down`.
#   The streak is counted within a checkpoint. From 2026-11-06 the same
#   service fails per REQUEST, not for a stretch: six daily ITR runs in
#   a row stopped as `rad-down` (2026-11-07 to 11-12), and on 11-12 one
#   document asked 30 times from outside GitHub failed 8 times, the next
#   request delivering the ZIP every time. A pause of 15 min does nothing
#   for that, so the document is asked again first (`rad_service_retries`
#   times, `rad_service_pause` seconds apart) and only a document that
#   fails every time counts toward the streak. The failure rate that
#   also stops the run (more than `rad_failure_rate` of the attempts)
#   counts ONLY the `reader` kind, and only after `rad_failure_floor`
#   attempts (decision of 2026-10-23: a run of 16 stopped with one
#   connection reset and one document whose cnpj differed from the
#   index — neither says anything about the reader, which is what the
#   rate guards). The three stops exit with status 2 after publishing what
#   was read. A run publishes in checkpoints of `rad_checkpoint_docs`
#   documents, so a job killed later keeps what it had published.
# * State lives in the release as `__rad_state.json` (documents done, by
#   `id_doc` with the hash of the XML; documents unread with the reason;
#   the last runs). The `hash` of `__source_hash.json` is NOT touched:
#   it describes the current parquets. Only its `history` map gains the
#   new content hashes.
# * A run that finds the whole queue empty still records itself and
#   publishes the state (2026-11-06): the last run of the state is what
#   says the robot is alive. Until then only a checkpoint recorded the
#   run; DFP emptied its queue on 2026-11-04, its state stopped there,
#   and the portfolio monitor read the robot as stalled. A run narrowed
#   by `--year` or `--reread` records nothing when it has nothing to do:
#   its empty queue says nothing about the whole one.
#
# Usage:
#   Rscript inst/etl/04-rad-fetch.R --group companhias --dataset dfp \
#     [--limit 300] [--minutes 260] [--year 2024] [--dry-run]
#     [--reread 113302]
#
# `--dry-run` reads and writes the parquets under
# <workspace>/out/rad/<group>/<dataset>/ without touching the release.
# `--year` restricts the queue to one reference year (smoke test).
# `--reread` reads the listed documents again, done or not, and their
# new rows REPLACE their RAD rows in the history (a document the reader
# read wrong before a fix: Dommo DFP 2021 v1, id 113302, per-share
# values with the decimal point lost, read before PR #42).
#
# Requires `gh` on PATH with a token (GITHUB_TOKEN on Actions). Setting
# `options(cvmdata.etl_testing = TRUE)` loads the helpers and skips the
# entry point.

# Run from the package root (the workflow does). Under
# `cvmdata.etl_testing` the test helper has sourced the siblings already.
for (sibling in c(
  "00-config.R",
  "util-hash.R",
  "util-history.R",
  "util-release.R",
  "util-privacy.R",
  "util-rad.R"
)) {
  marker <- c(
    "00-config.R" = "mirror_tag_latest",
    "util-hash.R" = "mirror_hash_parquet",
    "util-history.R" = "mirror_append_history",
    "util-release.R" = "upload_release_asset",
    "util-privacy.R" = "mirror_apply_privacy",
    "util-rad.R" = "rad_read_zip"
  )[[sibling]]
  if (!exists(marker, mode = "function")) {
    source(file.path("inst", "etl", sibling))
  }
}

stopifnot(requireNamespace("arrow", quietly = TRUE))
stopifnot(requireNamespace("jsonlite", quietly = TRUE))
stopifnot(requireNamespace("dplyr", quietly = TRUE))

rad_crawl_delay <- 10 # seconds between two requests to the RAD
rad_waf_pause <- 90 # seconds of pause after a refusal, before retrying
rad_waf_retries <- 2L # retries of one document refused by the WAF
rad_max_attempts <- 3L # tries per unread document, across runs
rad_failure_rate <- 0.10 # reader failures over the attempts of the run
rad_failure_floor <- 50L # attempts before the rate is judged
rad_checkpoint_docs <- 50L # documents between two publications of a run
rad_outage_streak <- 5L # download failures in a row that mean the RAD is down
rad_outage_pause <- 900 # seconds of pause when the RAD is down
rad_outage_pauses <- 5L # pauses of one run before it stops as `rad-down`
rad_service_pause <- 10 # seconds before asking a document again (crawl delay)
rad_service_retries <- 4L # new requests when the download service flickers

utc_now <- function(t = Sys.time()) {
  format(t, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

# --- queue ------------------------------------------------------------

# The years of the `submissao` index the release publishes, read from
# its `__source_hash.json` (`data`: partition path -> sha256). The
# robot asks for these years and no others, so a year it cannot read is
# a failure, not a year the mirror lacks (DFP of the current year).
rad_index_years <- function(source_hash) {
  paths <- names(source_hash$data %||% list())
  hit <- regmatches(paths, regexec("^submissao/year=(\\d{4})/", paths))
  years <- vapply(hit, function(m) if (length(m)) m[2] else NA_character_, "")
  sort(unique(as.integer(years[!is.na(years)])))
}

# The GitHub Actions annotation of a run that could not reach a source it
# depends on. The title is a fixed contract with the portfolio panel, the
# same one `@sbissoli/mcp-live-source` writes for the MCP servers (hence
# the Portuguese): a failed run that carries it measured nothing, and the
# panel leaves the red to the goal of the product (documents read in the
# window) instead of lighting up for an outage of GitHub.
rad_unreachable_annotation <- function(text) {
  text <- gsub("%", "%25", text, fixed = TRUE)
  text <- gsub("\r", "%0D", text, fixed = TRUE)
  text <- gsub("\n", "%0A", text, fixed = TRUE)
  paste0("::error title=Fonte inalcan\u00e7\u00e1vel::", text)
}

# Ends the run for an unreachable source: the annotation on stdout (where
# the runner reads workflow commands) and exit status 3, the one the MCP
# servers use for the same verdict.
rad_quit_unreachable <- function(e) {
  message("[04-rad] ", conditionMessage(e))
  cat(rad_unreachable_annotation(conditionMessage(e)), "\n", sep = "")
  quit(status = 3L)
}

# The `submissao` rows of `years` of `dataset`, from the mirror. Every
# year must read: on 2026-11-05 two years of the ITR index (2012, 2013)
# failed to download, were dropped in silence, and the run worked on a
# queue without them. A missing year now stops the run, naming it.
#
# A year the MIRROR could not serve is not a defect of the robot: on
# 2026-11-12 GitHub answered HTTP 500 to the 2024 partition on each of
# the 4 attempts of the client, the run died before reaching the RAD and
# the portfolio panel went red for it. Such a year (any
# `cvmdata_error_http`) is asked again after a pause, and when it still
# fails the error carries the class `rad_mirror_unreachable`, which the
# run turns into the labelled exit of `rad_quit_unreachable()`.
rad_index_pause <- 60
rad_index_retries <- 2L

rad_read_index <- function(
  dataset,
  years,
  fetch = NULL,
  pause = rad_index_pause,
  retries = rad_index_retries
) {
  fetch <- fetch %||%
    function(y) {
      suppressMessages(cvmdata::cvm_fetch(
        dataset,
        "submissao",
        year = y,
        source = "mirror"
      ))
    }
  if (length(years) == 0L) {
    stop(
      sprintf("the mirror publishes no submissao index for %s", dataset),
      call. = FALSE
    )
  }
  read_year <- function(y) tryCatch(fetch(y), error = function(e) e)
  is_http <- function(x) inherits(x, "cvmdata_error_http")
  parts <- lapply(years, read_year)
  for (try in seq_len(retries)) {
    again <- which(vapply(parts, is_http, logical(1)))
    if (length(again) == 0L) {
      break
    }
    message(sprintf(
      "[04-rad] the mirror did not serve the index of %s, asking again in %ds",
      paste(years[again], collapse = ", "),
      pause
    ))
    Sys.sleep(pause)
    parts[again] <- lapply(years[again], read_year)
  }
  bad <- vapply(parts, inherits, logical(1), what = "error")
  if (any(bad)) {
    failed <- vapply(
      which(bad),
      function(i) sprintf("%d (%s)", years[i], conditionMessage(parts[[i]])),
      character(1)
    )
    text <- sprintf(
      "could not read the submissao index of %s for year(s): %s",
      dataset,
      paste(failed, collapse = "; ")
    )
    if (all(vapply(parts[bad], is_http, logical(1)))) {
      stop(structure(
        class = c("rad_mirror_unreachable", "error", "condition"),
        list(message = text, call = NULL)
      ))
    }
    stop(text, call. = FALSE)
  }
  keep <- c(
    "cnpj_cia",
    "dt_refer",
    "versao",
    "denom_cia",
    "cd_cvm",
    "categ_doc",
    "id_doc",
    "dt_receb",
    "link_doc"
  )
  as.data.frame(dplyr::bind_rows(lapply(parts, function(p) {
    p[intersect(keep, names(p))]
  })))
}

# The deliveries that are not the current one of their
# (cnpj_cia, dt_refer), with the delivery that replaced each
# (`superseded_at` = its dt_receb, `superseded_by_versao`), minus the
# documents already done and the unread ones out of attempts. Ordered
# by reference year (newest first), then receipt date (newest first).
rad_queue <- function(
  index,
  state,
  year = NULL,
  max_attempts = rad_max_attempts,
  reread = NULL
) {
  idx <- index[
    order(
      index$cnpj_cia,
      index$dt_refer,
      index$dt_receb,
      as.integer(index$id_doc),
      suppressWarnings(as.integer(index$versao))
    ),
    ,
    drop = FALSE
  ]
  key <- paste(idx$cnpj_cia, idx$dt_refer)
  n <- nrow(idx)
  is_last <- !duplicated(key, fromLast = TRUE)
  nxt <- c(seq_len(n)[-1L], NA_integer_)
  idx$superseded_at <- format(idx$dt_receb[nxt], "%Y-%m-%d")
  idx$superseded_by_versao <- as.character(idx$versao[nxt])
  idx <- idx[!is_last, , drop = FALSE]
  refer_year <- as.integer(format(idx$dt_refer, "%Y"))
  if (!is.null(year)) {
    idx <- idx[refer_year %in% year, , drop = FALSE]
    refer_year <- refer_year[refer_year %in% year]
  }
  # out of attempts WITH THIS reader: a document refused by an earlier
  # reader (`reader` absent or different) is tried again
  spent <- names(state$unread)[vapply(
    state$unread,
    function(u) {
      (u$attempts %||% 0L) >= max_attempts &&
        identical(u$reader %||% "", rad_reader_id)
    },
    logical(1)
  )]
  # `reread`: only these documents, done or not (a document the reader
  # read WRONG before a fix; decision of 2026-10-25)
  keep <- if (is.null(reread)) {
    !idx$id_doc %in% c(names(state$done), spent)
  } else {
    idx$id_doc %in% reread
  }
  idx <- idx[keep, , drop = FALSE]
  refer_year <- refer_year[keep]
  idx[order(refer_year, idx$dt_receb, decreasing = TRUE), , drop = FALSE]
}

# --- state ------------------------------------------------------------

rad_empty_state <- function(dataset) {
  list(
    dataset = dataset,
    updated_at = NA_character_,
    done = list(),
    unread = list(),
    runs = list()
  )
}

# A missing `__rad_state.json` reads as an empty state, which is right
# only before the first run. Once the release has history assets the
# robot has run, and an empty state would queue again every document
# already read (thousands; ~16 rounds) and append their rows to the
# history a second time. On 2026-10-27 the mirror publish deleted the
# state of dfp and itr (its stale sweep; fixed in 03-publish.R): stop
# instead, so the state is restored before the robot runs again.
rad_check_state_present <- function(state_file, source_hash, tag) {
  has_history <- length(source_hash$history %||% list()) > 0L
  if (is.null(state_file) && has_history) {
    stop(
      sprintf(
        paste(
          "release %s has history assets but no __rad_state.json;",
          "refusing to start the RAD queue from scratch. Restore the",
          "state first."
        ),
        tag
      ),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

rad_read_state <- function(path, dataset) {
  if (is.null(path) || !file.exists(path)) {
    return(rad_empty_state(dataset))
  }
  st <- jsonlite::read_json(path)
  st$done <- st$done %||% list()
  st$unread <- st$unread %||% list()
  st$runs <- st$runs %||% list()
  st
}

rad_write_state <- function(state, path) {
  state$updated_at <- utc_now()
  jsonlite::write_json(
    state,
    path,
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null",
    na = "null"
  )
  path
}

rad_mark_unread <- function(state, id_doc, reason, kind = "reader") {
  prev <- state$unread[[id_doc]]
  # attempts of an earlier reader do not count against the document
  same <- identical(prev$reader %||% "", rad_reader_id)
  state$unread[[id_doc]] <- list(
    reason = reason,
    kind = kind,
    at = utc_now(),
    attempts = if (same) as.integer(prev$attempts %||% 0L) + 1L else 1L,
    reader = rad_reader_id
  )
  state
}

# The public list of documents set aside, one row per document.
rad_unread_table <- function(state, index) {
  ids <- names(state$unread)
  if (length(ids) == 0L) {
    return(data.frame(
      id_doc = character(),
      cnpj_cia = character(),
      denom_cia = character(),
      dt_refer = character(),
      versao = character(),
      reason = character(),
      kind = character(),
      attempts = integer(),
      last_attempt = character(),
      stringsAsFactors = FALSE
    ))
  }
  m <- match(ids, index$id_doc)
  field <- function(name, default, type) {
    vapply(state$unread, function(u) type(u[[name]] %||% default), type(1))
  }
  data.frame(
    id_doc = ids,
    cnpj_cia = index$cnpj_cia[m],
    denom_cia = index$denom_cia[m],
    dt_refer = format(index$dt_refer[m], "%Y-%m-%d"),
    versao = as.character(index$versao[m]),
    reason = field("reason", "", as.character),
    kind = field("kind", "", as.character),
    attempts = field("attempts", 0L, as.integer),
    last_attempt = field("at", "", as.character),
    stringsAsFactors = FALSE
  )
}

# --- rows -------------------------------------------------------------

# History rows of one document: the package columns plus the history
# columns of util-history.R and the RAD extras.
rad_history_rows <- function(tables, filing, meta) {
  motivo <- mirror_mask_text(trimws(meta$motivo_reapresentacao %||% ""))
  lapply(tables, function(t) {
    t$superseded_at <- filing$superseded_at
    t$superseded_by_versao <- filing$superseded_by_versao
    t$history_source <- "rad"
    t$id_doc <- as.character(filing$id_doc)
    t$motivo_reapresentacao <- if (nzchar(motivo)) motivo else NA_character_
    t
  })
}

# Partition path of the history asset of a (table/report_type) tibble.
rad_history_rel <- function(key, dt_refer) {
  parts <- strsplit(key, "/", fixed = TRUE)[[1L]]
  sprintf(
    "%s/report_type=%s/year=%s/history.parquet",
    parts[1L],
    parts[2L],
    format(dt_refer, "%Y")
  )
}

# Appends `rows` to the previous history of a partition, once per
# version: rows of an id_doc already there, or of a (cnpj, dt_refer,
# versao) the mirror path already holds, are dropped. Returns
# list(history, n_added, n_skipped).
rad_merge_history <- function(previous, rows, replace = character()) {
  if (
    !is.null(previous) &&
      length(replace) &&
      all(c("id_doc", "history_source") %in% names(previous))
  ) {
    # a document read again replaces its own RAD rows, nothing else
    old <- previous$id_doc %in% replace & previous$history_source %in% "rad"
    previous <- previous[!old, , drop = FALSE]
  }
  if (!is.null(previous)) {
    if (!"history_source" %in% names(previous)) {
      previous$history_source <- "mirror"
    }
    previous$history_source[is.na(previous$history_source)] <- "mirror"
    seen_doc <- if ("id_doc" %in% names(previous)) {
      previous$id_doc
    } else {
      character()
    }
    seen_ver <- paste(previous$cnpj_cia, previous$dt_refer, previous$versao)
    keep <- !rows$id_doc %in% seen_doc &
      !paste(rows$cnpj_cia, rows$dt_refer, rows$versao) %in% seen_ver
  } else {
    keep <- rep(TRUE, nrow(rows))
  }
  added <- rows[keep, , drop = FALSE]
  list(
    # same join as the mirror path: the asset may hold rows another
    # release of the reader wrote with other column types
    history = mirror_append_history(previous, added),
    n_added = nrow(added),
    n_skipped = sum(!keep)
  )
}

# --- the run ----------------------------------------------------------

# Downloads and reads the queue until `limit` documents, `minutes` of
# wall clock (counted from `t_start`), a refusal by the RAD, the RAD down
# for longer than `rad_outage_pauses` pauses (each one after
# `rad_outage_streak` download failures in a row) or too many failures
# of the reader. `tally` carries the counts of the earlier checkpoints of
# the same run, so the pauses and the failure rate are judged over the
# whole run: `reader_failed` of the attempts, only once `attempted`
# reached `rad_failure_floor`; failures of the other kinds (download,
# document) are set aside without weighing on the rate. Returns
# list(by_rel, state, attempted, n_read, failed, reader_failed, outages,
# stopped, time_out).
rad_run_queue <- function(
  queue,
  state,
  work,
  limit,
  minutes,
  t_start,
  tally = NULL
) {
  stopped <- NA_character_
  time_out <- FALSE
  attempted <- 0L
  failed <- 0L
  reader_failed <- 0L
  n_read <- 0L
  before <- tally %||% list(attempted = 0L, reader_failed = 0L)
  by_rel <- list()
  # the download failures in a row, with each document's entry in
  # `unread` before the failure (NULL when it had none)
  streak <- list()
  outages <- 0L
  last_request <- Sys.time() - rad_crawl_delay
  for (i in seq_len(min(limit, nrow(queue)))) {
    if (as.numeric(difftime(Sys.time(), t_start, units = "mins")) > minutes) {
      message(sprintf("[04-rad] time budget of %d min reached", minutes))
      time_out <- TRUE
      break
    }
    f <- queue[i, ]
    wait <- rad_crawl_delay -
      as.numeric(difftime(Sys.time(), last_request, units = "secs"))
    if (wait > 0) {
      Sys.sleep(wait)
    }
    got <- rad_fetch_one(f, work)
    last_request <- Sys.time()
    attempted <- attempted + 1L
    message(sprintf(
      "  %s %s %s: %s",
      f$id_doc,
      f$denom_cia,
      f$dt_refer,
      got$note
    ))
    kind <- rad_failure_kind(got)
    streak <- rad_extend_streak(streak, kind, f$id_doc, state)
    if (!got$ok) {
      failed <- failed + 1L
      state <- rad_mark_unread(state, f$id_doc, got$note, kind)
      if (length(streak) >= rad_outage_streak) {
        state <- rad_undo_streak(state, streak)
        failed <- failed - length(streak)
        streak <- list()
        outages <- outages + 1L
        if ((before$outages %||% 0L) + outages > rad_outage_pauses) {
          stopped <- "rad-down"
          message("[04-rad] the RAD is still down: stopping")
          break
        }
        message(sprintf(
          "[04-rad] %d downloads failed in a row: the RAD is down, pausing %ds",
          rad_outage_streak,
          as.integer(rad_outage_pause)
        ))
        Sys.sleep(rad_outage_pause)
        next
      }
      if (got$waf) {
        stopped <- "waf"
        message("[04-rad] the RAD refused the request (WAF): stopping")
        break
      }
      if (kind != "reader") {
        next
      }
      reader_failed <- reader_failed + 1L
      all_attempted <- before$attempted + attempted
      all_failed <- (before$reader_failed %||% 0L) + reader_failed
      if (rad_rate_exceeded(all_failed, all_attempted)) {
        stopped <- "failure-rate"
        message(sprintf(
          "[04-rad] the reader failed on %d of %d documents: stopping",
          all_failed,
          all_attempted
        ))
        break
      }
      next
    }
    for (k in names(got$rows)) {
      rel <- rad_history_rel(k, f$dt_refer)
      by_rel[[rel]] <- c(by_rel[[rel]], list(got$rows[[k]]))
    }
    state$unread[[f$id_doc]] <- NULL
    state$done[[f$id_doc]] <- got$done
    n_read <- n_read + 1L
  }
  list(
    by_rel = by_rel,
    state = state,
    attempted = attempted,
    n_read = n_read,
    failed = failed,
    reader_failed = reader_failed,
    outages = outages,
    stopped = stopped,
    time_out = time_out
  )
}

# Whether the reader's failures stop the run: more than
# `rad_failure_rate` of the attempts, once `rad_failure_floor` is reached.
rad_rate_exceeded <- function(n_failed, n_attempted) {
  n_attempted >= rad_failure_floor &&
    n_failed / n_attempted > rad_failure_rate
}

# The kind of failure of a `rad_fetch_one()` result; NA when it read.
rad_failure_kind <- function(got) {
  if (got$ok) {
    return(NA_character_)
  }
  got$kind %||% if (got$waf) "waf" else "reader"
}

# The download streak after one more document: a download failure joins
# it, keeping the document's `unread` entry from before (call it BEFORE
# `rad_mark_unread()`); anything else ends it.
rad_extend_streak <- function(streak, kind, id_doc, state) {
  if (!identical(kind, "download")) {
    return(list())
  }
  streak[[id_doc]] <- list(prev = state$unread[[id_doc]])
  streak
}

# Puts back the `unread` entries the documents of a download streak had
# before it (`streak`: id_doc -> list(prev)); a document without one
# leaves the list (assigning NULL drops the entry).
rad_undo_streak <- function(state, streak) {
  for (id in names(streak)) {
    state$unread[[id]] <- streak[[id]]$prev
  }
  state
}

# Whether a download error is the RAD's internal download service
# failing for ONE request ("The HTTP service located at
# http://127.0.0.1:8182/Download/DownloadDocumento.svc is unavailable",
# "The requested service, '...DownloadDocumento.svc' could not be
# activated"). Measured 2026-11-12 from a Brazilian network, outside
# GitHub: the same document asked 30 times, 3 min and then 10 s apart,
# got this text 8 times, scattered, and the ZIP on the very next request
# every time. The same backend also answers "The underlying connection
# was closed: A connection that was expected to be kept alive was closed
# by the server." (3 of the 8 failures of the run of 2026-11-12, 292 of
# 300 read): the front end lost its connection to the service, not the
# robot its own, so it is asked again too. Other texts of the RAD (ITR
# 67723, "Index was out of range") are about the document and are not
# retried.
rad_service_flicker_texts <- c(
  "DownloadDocumento.svc",
  "The underlying connection was closed"
)

rad_service_flicker <- function(error) {
  texts <- rad_service_flicker_texts
  !is.na(error) && any(vapply(texts, grepl, logical(1), error, fixed = TRUE))
}

# What one download attempt looked like on the wire, for the log: whether
# the connection was new and how long the answer took ("new connection,
# 0.3s"). The parts `rad_download()` could not tell are left out.
rad_attempt_note <- function(dl) {
  conn <- if (isTRUE(dl$new_conn)) {
    "new connection"
  } else if (isFALSE(dl$new_conn)) {
    "reused connection"
  } else {
    "connection unknown"
  }
  secs <- dl$ttfb %||% NA_real_
  if (is.na(secs)) conn else sprintf("%s, %.1fs", conn, secs)
}

# A failed `rad_fetch_one()` result of the given kind.
rad_failure <- function(kind, note) {
  list(ok = FALSE, waf = identical(kind, "waf"), kind = kind, note = note)
}

# Downloads one document to `zip`, asking again what is worth asking
# again (see `rad_fetch_one()`). Returns list(dl, failure): `failure` is
# NULL when the ZIP arrived, the `rad_fetch_one()` result otherwise.
rad_download_patiently <- function(
  id_doc,
  zip,
  pause,
  retries,
  service_pause,
  service_retries
) {
  refused <- 0L
  flickers <- 0L
  repeat {
    dl <- rad_download(id_doc, zip)
    if (dl$ok) {
      return(list(dl = dl, failure = NULL))
    }
    if (rad_service_flicker(dl$error)) {
      flickers <- flickers + 1L
      if (flickers > service_retries) {
        note <- sprintf("%s, %d times in a row", dl$error, flickers)
        return(list(dl = dl, failure = rad_failure("download", note)))
      }
      message(sprintf(
        "  %s: the RAD's download service failed (%s), try %d of %d next",
        id_doc,
        rad_attempt_note(dl),
        flickers + 1L,
        service_retries + 1L
      ))
      Sys.sleep(service_pause)
      next
    }
    waf <- identical(dl$status, 403L) ||
      grepl("not a ZIP", dl$error, fixed = TRUE)
    if (!waf) {
      return(list(dl = dl, failure = rad_failure("download", dl$error)))
    }
    refused <- refused + 1L
    if (refused > retries) {
      note <- sprintf("%s, refused %d times", dl$error, refused)
      return(list(dl = dl, failure = rad_failure("waf", note)))
    }
    message(sprintf(
      "  %s refused by the RAD (%s): pausing %ds before try %d of %d",
      id_doc,
      dl$error,
      as.integer(pause),
      refused + 1L,
      retries + 1L
    ))
    Sys.sleep(pause)
  }
}

# Downloads and reads one document. Returns list(ok, waf, kind, note,
# rows, done): `note` is the reason when not ok, a summary otherwise;
# `done` is the state entry of a document read. A refusal by the WAF
# (403 or an HTML body) is retried after `pause` seconds, `retries`
# times; `waf` is TRUE only when every try was refused. The download
# service failing for the request (`rad_service_flicker()`) is asked
# again after `service_pause` seconds, `service_retries` times, on a
# count of its own; failing every time, it is a `download` failure like
# any other and joins the outage streak of the queue. `kind` names the
# failure (see the header): "waf", "download" (the RAD did not deliver
# the ZIP), "document" (not the document of the index row, or nothing
# in it) or "reader" (the reader could not read it); NA when ok.
rad_fetch_one <- function(
  f,
  work,
  pause = rad_waf_pause,
  retries = rad_waf_retries,
  service_pause = rad_service_pause,
  service_retries = rad_service_retries
) {
  zip <- file.path(work, paste0(f$id_doc, ".zip"))
  got <- rad_download_patiently(
    f$id_doc,
    zip,
    pause,
    retries,
    service_pause,
    service_retries
  )
  if (!is.null(got$failure)) {
    return(got$failure)
  }
  dl <- got$dl
  res <- tryCatch(rad_read_zip(zip, f), error = function(e) {
    list(meta = list(), tables = list(), problems = conditionMessage(e))
  })
  unlink(zip)
  if (length(res$problems) || length(res$tables) == 0L) {
    reason <- if (length(res$problems)) {
      paste(res$problems, collapse = " | ")
    } else {
      "no statement with rows"
    }
    # a document that is not the one the index describes (or not a
    # DFP/ITR at all: the reader says so in `kind`), or that has nothing
    # to read, is set aside for what it is, not for the reader
    kind <- res$kind %||%
      if (isTRUE(res$index_mismatch) || length(res$problems) == 0L) {
        "document"
      } else {
        "reader"
      }
    return(list(
      ok = FALSE,
      waf = FALSE,
      kind = kind,
      note = paste0("set aside (", reason, ")")
    ))
  }
  rows <- rad_history_rows(res$tables, f, res$meta)
  n_rows <- sum(vapply(rows, nrow, integer(1)))
  list(
    ok = TRUE,
    waf = FALSE,
    kind = NA_character_,
    note = sprintf(
      "v%s, %s layout, %d tables, %d rows (%.0fs)%s",
      f$versao,
      res$meta$layout,
      length(rows),
      n_rows,
      dl$seconds,
      rad_cnpj_note(res$meta$cnpj_doc)
    ),
    rows = rows,
    done = c(
      list(
        hash = res$meta$xml_hash,
        at = utc_now(),
        layout = res$meta$layout,
        rows = n_rows,
        tables = length(rows)
      ),
      # the CNPJ the document carries when it is not the index's (a
      # branch's, or another company's by a slip of the filer): accepted
      # by the CVM code, kept in the state so the case can be found
      if (!is.null(res$meta$cnpj_doc)) list(cnpj_doc = res$meta$cnpj_doc)
    )
  )
}

rad_cnpj_note <- function(cnpj_doc) {
  if (is.null(cnpj_doc)) {
    return("")
  }
  sprintf("; cnpj in the document %s, accepted by the CVM code", cnpj_doc)
}

# Merges the rows of a checkpoint into the history assets. Returns
# list(uploads, n_added, n_skipped, source_hash).
rad_build_history <- function(
  by_rel,
  tag,
  prev_dir,
  hist_dir,
  source_hash,
  replace = character()
) {
  uploads <- character()
  n_added <- 0L
  n_skipped <- 0L
  for (rel in names(by_rel)) {
    new_rows <- dplyr::bind_rows(by_rel[[rel]])
    prev_path <- download_release_asset(tag, public_asset_name(rel), prev_dir)
    previous <- if (is.null(prev_path)) NULL else arrow::read_parquet(prev_path)
    if (!is.null(source_hash$history[[rel]]) && is.null(previous)) {
      stop(
        sprintf("history asset %s is listed but could not be downloaded", rel),
        call. = FALSE
      )
    }
    merged <- rad_merge_history(previous, new_rows, replace = replace)
    n_added <- n_added + merged$n_added
    n_skipped <- n_skipped + merged$n_skipped
    if (merged$n_added == 0L) {
      next
    }
    out <- file.path(hist_dir, rel)
    dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
    arrow::write_parquet(merged$history, out, compression = "snappy")
    source_hash$history[[rel]] <- mirror_hash_parquet(out)
    staged <- file.path(hist_dir, asset_name_of(rel))
    file.copy(out, staged, overwrite = TRUE)
    uploads <- c(uploads, staged)
    message(sprintf(
      "  %s: +%d rows (%d already there)",
      rel,
      merged$n_added,
      merged$n_skipped
    ))
  }
  list(
    uploads = uploads,
    n_added = n_added,
    n_skipped = n_skipped,
    source_hash = source_hash
  )
}

# The record of the current run goes first in `state$runs`; a checkpoint
# of the same run (same `at`) replaces it instead of adding another.
rad_record_run <- function(state, record, keep = 30L) {
  runs <- state$runs
  same <- length(runs) > 0L && identical(runs[[1L]]$at, record$at)
  if (same) {
    runs[[1L]] <- record
  } else {
    runs <- c(list(record), runs)
  }
  state$runs <- utils::head(runs, keep)
  state
}

# Writes the state, the unread list and the hash map under `out_dir` and
# uploads them with the history assets built, unless `dry_run`. Called at
# every checkpoint, so a run that dies later keeps what it published.
rad_publish <- function(built, state, index, out_dir, tag, dry_run) {
  state_path <- rad_write_state(state, file.path(out_dir, "__rad_state.json"))
  unread_path <- file.path(out_dir, "__rad_unread.csv")
  utils::write.csv(
    rad_unread_table(state, index),
    unread_path,
    row.names = FALSE,
    na = ""
  )
  hash_path <- file.path(out_dir, "__source_hash.json")
  jsonlite::write_json(
    built$source_hash,
    hash_path,
    auto_unbox = TRUE,
    pretty = TRUE
  )
  if (dry_run) {
    message(sprintf(
      "[04-rad] dry run: %d history asset(s) under %s; nothing uploaded",
      length(built$uploads),
      out_dir
    ))
    return(invisible(0L))
  }
  assets <- c(
    built$uploads,
    if (length(built$uploads)) hash_path,
    state_path,
    unread_path
  )
  for (p in assets) {
    message("  uploading ", basename(p))
    upload_release_asset(tag, p)
  }
  message(sprintf("[04-rad] published %d asset(s) to %s", length(assets), tag))
  invisible(length(assets))
}

rad_main <- function(
  group,
  dataset,
  limit,
  minutes,
  year,
  dry_run,
  reread = NULL
) {
  t_start <- Sys.time()
  tag <- mirror_tag_latest(group, dataset)
  work <- file.path(mirror_workspace(), "rad", group, dataset)
  prev_dir <- file.path(work, "release")
  out_dir <- file.path(mirror_workspace(), "out", "rad", group, dataset)
  hist_dir <- file.path(out_dir, "history")
  for (d in c(work, prev_dir, out_dir, hist_dir)) {
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
  }

  message(sprintf("[04-rad] %s: reading state of release %s", dataset, tag))
  hash_file <- download_release_asset(tag, "__source_hash.json", prev_dir)
  if (is.null(hash_file)) {
    stop(sprintf("release %s has no __source_hash.json", tag), call. = FALSE)
  }
  source_hash <- jsonlite::read_json(hash_file)
  source_hash$history <- source_hash$history %||% list()
  state_file <- download_release_asset(tag, "__rad_state.json", prev_dir)
  rad_check_state_present(state_file, source_hash, tag)
  state <- rad_read_state(state_file, dataset)

  index <- tryCatch(
    rad_read_index(dataset, rad_index_years(source_hash)),
    rad_mirror_unreachable = rad_quit_unreachable
  )
  queue <- rad_queue(index, state, year = year, reread = reread)
  message(sprintf(
    "[04-rad] index: %d deliveries; queue: %d (%d done, %d set aside)",
    nrow(index),
    nrow(queue),
    length(state$done),
    length(state$unread)
  ))

  ctx <- list(
    tag = tag,
    work = work,
    prev_dir = prev_dir,
    hist_dir = hist_dir,
    out_dir = out_dir,
    index = index,
    limit = limit,
    minutes = minutes,
    t_start = t_start,
    dry_run = dry_run,
    reread = reread,
    whole_queue = is.null(year) && length(reread) == 0L
  )
  res <- rad_run_checkpoints(queue, state, source_hash, ctx)
  tally <- res$tally
  message(sprintf(
    "[04-rad] run: %d tried, %d read, %d failed, +%d rows, %d checkpoint(s)%s",
    tally$attempted,
    tally$read,
    tally$failed,
    tally$rows,
    tally$checkpoints,
    if (is.na(res$stopped)) "" else paste0(" (stopped: ", res$stopped, ")")
  ))
  if (!is.na(res$stopped)) {
    quit(status = 2L)
  }
  invisible(NULL)
}

# The run goes in checkpoints of `rad_checkpoint_docs` documents: each
# one is merged into the history assets and published before the next
# starts, so a job killed later loses at most one checkpoint. `ctx` holds
# the paths and limits of the run. Returns list(tally, stopped).
rad_run_checkpoints <- function(queue, state, source_hash, ctx) {
  tally <- list(
    attempted = 0L,
    failed = 0L,
    reader_failed = 0L,
    outages = 0L,
    read = 0L,
    rows = 0L,
    checkpoints = 0L
  )
  pos <- 1L
  stopped <- NA_character_
  repeat {
    n <- min(rad_checkpoint_docs, ctx$limit - tally$attempted)
    if (n <= 0L || pos > nrow(queue)) {
      break
    }
    run <- rad_run_queue(
      queue[seq.int(pos, nrow(queue)), , drop = FALSE],
      state,
      ctx$work,
      n,
      ctx$minutes,
      ctx$t_start,
      tally
    )
    pos <- pos + run$attempted
    state <- run$state
    tally$attempted <- tally$attempted + run$attempted
    tally$failed <- tally$failed + run$failed
    tally$reader_failed <- tally$reader_failed + run$reader_failed
    tally$outages <- tally$outages + run$outages
    tally$read <- tally$read + run$n_read
    stopped <- run$stopped
    built <- rad_build_history(
      run$by_rel,
      ctx$tag,
      ctx$prev_dir,
      ctx$hist_dir,
      source_hash,
      replace = ctx$reread %||% character()
    )
    source_hash <- built$source_hash
    tally$rows <- tally$rows + built$n_added
    tally$checkpoints <- tally$checkpoints + 1L
    message(sprintf(
      "[04-rad] checkpoint %d: %d tried, %d read, %d failed, +%d rows%s",
      tally$checkpoints,
      tally$attempted,
      tally$read,
      tally$failed,
      built$n_added,
      if (is.na(stopped)) "" else paste0(" (stopped: ", stopped, ")")
    ))
    state <- rad_record_run(
      state,
      rad_run_record(ctx$t_start, nrow(queue), tally, stopped)
    )
    rad_publish(built, state, ctx$index, ctx$out_dir, ctx$tag, ctx$dry_run)
    if (!is.na(stopped) || run$time_out || run$attempted == 0L) {
      break
    }
  }
  if (rad_idle_round(nrow(queue), tally$checkpoints, ctx$whole_queue)) {
    message("[04-rad] the queue is empty: recording the idle run")
    state <- rad_record_run(
      state,
      rad_run_record(ctx$t_start, 0L, tally, stopped)
    )
    idle <- list(uploads = character(), source_hash = source_hash)
    rad_publish(idle, state, ctx$index, ctx$out_dir, ctx$tag, ctx$dry_run)
  }
  list(tally = tally, stopped = stopped)
}

# The record of a run as `state$runs` keeps it: when it started, the
# size of the queue it found, the counts so far and why it stopped.
rad_run_record <- function(t_start, n_queue, tally, stopped = NA_character_) {
  list(
    at = utc_now(t_start),
    queue = n_queue,
    attempted = tally$attempted,
    read = tally$read,
    failed = tally$failed,
    reader_failed = tally$reader_failed,
    outages = tally$outages,
    rows = tally$rows,
    checkpoints = tally$checkpoints,
    stopped = if (is.na(stopped)) NULL else stopped,
    seconds = round(as.numeric(difftime(Sys.time(), t_start, units = "secs")))
  )
}

# A run is idle when it went through no checkpoint because the WHOLE
# queue was empty. `whole_queue` is FALSE for a run narrowed by `--year`
# or `--reread`, whose empty queue is not the robot's.
rad_idle_round <- function(n_queue, checkpoints, whole_queue) {
  n_queue == 0L && checkpoints == 0L && isTRUE(whole_queue)
}

rad_parse_args <- function(args) {
  opts <- list(
    group = "companhias",
    dataset = NULL,
    limit = 300L,
    minutes = 260,
    year = NULL,
    dry_run = FALSE,
    reread = NULL
  )
  i <- 1L
  while (i <= length(args)) {
    key <- args[i]
    if (key == "--dry-run") {
      opts$dry_run <- TRUE
      i <- i + 1L
      next
    }
    value <- args[i + 1L]
    if (key == "--group") {
      opts$group <- value
    } else if (key == "--dataset") {
      opts$dataset <- value
    } else if (key == "--limit") {
      opts$limit <- as.integer(value)
    } else if (key == "--minutes") {
      opts$minutes <- as.numeric(value)
    } else if (key == "--year") {
      opts$year <- as.integer(value)
    } else if (key == "--reread") {
      opts$reread <- trimws(strsplit(value, ",", fixed = TRUE)[[1L]])
    } else {
      i <- i + 1L
      next
    }
    i <- i + 2L
  }
  opts
}

if (!isTRUE(getOption("cvmdata.etl_testing"))) {
  opts <- rad_parse_args(commandArgs(trailingOnly = TRUE))
  if (is.null(opts$dataset) || !opts$dataset %in% c("dfp", "itr")) {
    stop("--dataset dfp|itr is required", call. = FALSE)
  }
  if (!mirror_pair_valid(opts$group, opts$dataset)) {
    stop(
      sprintf("(%s, %s) is not a mirror pair", opts$group, opts$dataset),
      call. = FALSE
    )
  }
  rad_main(
    opts$group,
    opts$dataset,
    opts$limit,
    opts$minutes,
    opts$year,
    opts$dry_run,
    opts$reread
  )
}
