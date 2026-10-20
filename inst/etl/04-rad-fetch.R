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
#   retried on later runs up to `rad_max_attempts` times. A 403 or an
#   HTML body (the WAF) stops the run at once; more than ~10% of
#   failures stops it too. Both exit with status 2 after publishing
#   what was read. A run publishes in checkpoints of `rad_checkpoint_docs`
#   documents, so a job killed later keeps what it had published.
# * State lives in the release as `__rad_state.json` (documents done, by
#   `id_doc` with the hash of the XML; documents unread with the reason;
#   the last runs). The `hash` of `__source_hash.json` is NOT touched:
#   it describes the current parquets. Only its `history` map gains the
#   new content hashes.
#
# Usage:
#   Rscript inst/etl/04-rad-fetch.R --group companhias --dataset dfp \
#     [--limit 300] [--minutes 170] [--year 2024] [--dry-run]
#
# `--dry-run` reads and writes the parquets under
# <workspace>/out/rad/<group>/<dataset>/ without touching the release.
# `--year` restricts the queue to one reference year (smoke test).
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
  "util-rad.R"
)) {
  marker <- c(
    "00-config.R" = "mirror_tag_latest",
    "util-hash.R" = "mirror_hash_parquet",
    "util-history.R" = "mirror_append_history",
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
rad_max_attempts <- 3L # tries per unread document, across runs
rad_failure_rate <- 0.10 # of the documents attempted in the run
rad_failure_floor <- 10L # attempts before the rate is judged
rad_checkpoint_docs <- 50L # documents between two publications of a run

utc_now <- function(t = Sys.time()) {
  format(t, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

# --- queue ------------------------------------------------------------

# The `submissao` rows of every published year of `dataset`, from the
# mirror.
rad_read_index <- function(dataset, years) {
  parts <- lapply(years, function(y) {
    tryCatch(
      suppressMessages(cvmdata::cvm_fetch(
        dataset,
        "submissao",
        year = y,
        source = "mirror"
      )),
      error = function(e) NULL
    )
  })
  parts <- parts[!vapply(parts, is.null, logical(1))]
  if (length(parts) == 0L) {
    return(NULL)
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
  max_attempts = rad_max_attempts
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
  spent <- names(state$unread)[vapply(
    state$unread,
    function(u) (u$attempts %||% 0L) >= max_attempts,
    logical(1)
  )]
  keep <- !idx$id_doc %in% c(names(state$done), spent)
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

rad_mark_unread <- function(state, id_doc, reason) {
  prev <- state$unread[[id_doc]]
  state$unread[[id_doc]] <- list(
    reason = reason,
    at = utc_now(),
    attempts = as.integer(prev$attempts %||% 0L) + 1L
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
    attempts = field("attempts", 0L, as.integer),
    last_attempt = field("at", "", as.character),
    stringsAsFactors = FALSE
  )
}

# --- rows -------------------------------------------------------------

# History rows of one document: the package columns plus the history
# columns of util-history.R and the RAD extras.
rad_history_rows <- function(tables, filing, meta) {
  motivo <- trimws(meta$motivo_reapresentacao %||% "")
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
rad_merge_history <- function(previous, rows) {
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
    history = if (is.null(previous)) {
      added
    } else {
      dplyr::bind_rows(previous, added)
    },
    n_added = nrow(added),
    n_skipped = sum(!keep)
  )
}

# --- release I/O ------------------------------------------------------

asset_name_of <- function(rel) {
  gsub("[/\\\\]", "__", rel)
}
public_asset_name <- function(rel) {
  gsub("=", ".", asset_name_of(rel), fixed = TRUE)
}

download_release_asset <- function(tag, name, dir, attempts = 3L) {
  for (attempt in seq_len(attempts)) {
    status <- suppressWarnings(system2(
      "gh",
      c(
        "release",
        "download",
        tag,
        "--repo",
        mirror_repo,
        "--pattern",
        name,
        "--dir",
        shQuote(dir),
        "--clobber"
      ),
      stdout = NULL,
      stderr = NULL
    ))
    path <- file.path(dir, name)
    if (status == 0L && file.exists(path)) {
      return(path)
    }
    if (attempt < attempts) {
      Sys.sleep(5 * attempt)
    }
  }
  NULL
}

upload_release_asset <- function(tag, path, attempts = 4L) {
  for (attempt in seq_len(attempts)) {
    status <- system2(
      "gh",
      c(
        "release",
        "upload",
        tag,
        shQuote(path),
        "--repo",
        mirror_repo,
        "--clobber"
      )
    )
    if (status == 0L) {
      return(invisible(TRUE))
    }
    if (attempt < attempts) {
      wait <- 10 * 2^(attempt - 1L)
      message(sprintf("    upload failed; retry %d in %ds", attempt, wait))
      Sys.sleep(wait)
    }
  }
  stop(sprintf("upload failed for %s", basename(path)), call. = FALSE)
}

# --- the run ----------------------------------------------------------

# Downloads and reads the queue until `limit` documents, `minutes` of
# wall clock (counted from `t_start`), a refusal by the RAD or too many
# failures. `tally` carries the counts of the earlier checkpoints of the
# same run, so the failure rate is judged over the whole run. Returns
# list(by_rel, state, attempted, n_read, failed, stopped, time_out).
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
  n_read <- 0L
  before <- tally %||% list(attempted = 0L, failed = 0L)
  by_rel <- list()
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
    if (!got$ok) {
      failed <- failed + 1L
      state <- rad_mark_unread(state, f$id_doc, got$note)
      if (got$waf) {
        stopped <- "waf"
        message("[04-rad] the RAD refused the request (WAF): stopping")
        break
      }
      all_attempted <- before$attempted + attempted
      all_failed <- before$failed + failed
      if (
        all_attempted >= rad_failure_floor &&
          all_failed / all_attempted > rad_failure_rate
      ) {
        stopped <- "failure-rate"
        message(sprintf(
          "[04-rad] %d of %d documents failed: stopping",
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
    stopped = stopped,
    time_out = time_out
  )
}

# Downloads and reads one document. Returns list(ok, waf, note, rows,
# done): `note` is the reason when not ok, a summary otherwise; `done`
# is the state entry of a document read.
rad_fetch_one <- function(f, work) {
  zip <- file.path(work, paste0(f$id_doc, ".zip"))
  dl <- rad_download(f$id_doc, zip)
  if (!dl$ok) {
    waf <- identical(dl$status, 403L) ||
      grepl("not a ZIP", dl$error, fixed = TRUE)
    return(list(ok = FALSE, waf = waf, note = dl$error))
  }
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
    return(list(
      ok = FALSE,
      waf = FALSE,
      note = paste0("set aside (", reason, ")")
    ))
  }
  rows <- rad_history_rows(res$tables, f, res$meta)
  n_rows <- sum(vapply(rows, nrow, integer(1)))
  list(
    ok = TRUE,
    waf = FALSE,
    note = sprintf(
      "v%s, %s layout, %d tables, %d rows (%.0fs)",
      f$versao,
      res$meta$layout,
      length(rows),
      n_rows,
      dl$seconds
    ),
    rows = rows,
    done = list(
      hash = res$meta$xml_hash,
      at = utc_now(),
      layout = res$meta$layout,
      rows = n_rows,
      tables = length(rows)
    )
  )
}

# Merges the rows of a checkpoint into the history assets. Returns
# list(uploads, n_added, n_skipped, source_hash).
rad_build_history <- function(by_rel, tag, prev_dir, hist_dir, source_hash) {
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
    merged <- rad_merge_history(previous, new_rows)
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

rad_main <- function(group, dataset, limit, minutes, year, dry_run) {
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
  state <- rad_read_state(
    download_release_asset(tag, "__rad_state.json", prev_dir),
    dataset
  )

  schema <- yaml::read_yaml(file.path(
    mirror_schema_dir(dataset),
    "submissao.yaml"
  ))
  years <- seq.int(
    schema$first_year %||% 2010L,
    as.integer(format(Sys.Date(), "%Y"))
  )
  index <- rad_read_index(dataset, years)
  if (is.null(index)) {
    stop("could not read the submissao index from the mirror", call. = FALSE)
  }
  queue <- rad_queue(index, state, year = year)
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
    dry_run = dry_run
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
    tally$read <- tally$read + run$n_read
    stopped <- run$stopped
    built <- rad_build_history(
      run$by_rel,
      ctx$tag,
      ctx$prev_dir,
      ctx$hist_dir,
      source_hash
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
      list(
        at = utc_now(ctx$t_start),
        queue = nrow(queue),
        attempted = tally$attempted,
        read = tally$read,
        failed = tally$failed,
        rows = tally$rows,
        checkpoints = tally$checkpoints,
        stopped = if (is.na(stopped)) NULL else stopped,
        seconds = round(as.numeric(difftime(
          Sys.time(),
          ctx$t_start,
          units = "secs"
        )))
      )
    )
    rad_publish(built, state, ctx$index, ctx$out_dir, ctx$tag, ctx$dry_run)
    if (!is.na(stopped) || run$time_out || run$attempted == 0L) {
      break
    }
  }
  list(tally = tally, stopped = stopped)
}

rad_parse_args <- function(args) {
  opts <- list(
    group = "companhias",
    dataset = NULL,
    limit = 300L,
    minutes = 170,
    year = NULL,
    dry_run = FALSE
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
    opts$dry_run
  )
}
