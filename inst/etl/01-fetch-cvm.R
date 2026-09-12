# Stage 1 — Fetch raw CVM data into the ETL workspace.
#
# Calls cvmdata::issuer_fetch(source = "cvm") for each (table, year) of the
# requested dataset. The package handles the HTTP transport, ETag-based
# revalidation and schema validation; the only side effect this stage
# needs is "warm cache populated" — the actual parquet conversion is
# stage 02.
#
# Usage:
#   Rscript inst/etl/01-fetch-cvm.R \
#     --group companhias --dataset dfp [--year 2024]
#
# Without --year, fetches every year published by CVM for that dataset
# (via cvmdata::cvm_dataset_years()). For non-yearly datasets (CAD),
# --year is ignored.
#
# Exit codes:
#   0 — at least one (table, year) fetched (partial misses tolerated)
#   1 — every fetch failed, for mixed or non-transport reasons
#   3 — circuit breaker: the CVM portal is unreachable from this runner
#       (see `fetch_breaker_tripped()`)

# Locate 00-config.R across the three call modes this script supports:
#   * `Rscript inst/etl/01-fetch-cvm.R` from the package root — cwd has
#     the source tree, so `inst/etl/00-config.R` resolves directly.
#   * `system.file("etl", "00-config.R", package = "cvmdata")` from an
#     installed cvmdata — works for tests under R CMD check.
#   * Direct invocation by path — `commandArgs()` carries `--file=`,
#     whose dirname holds the sibling 00-config.R.
# Same three modes, and the same resolution order, as 02b-validate.R.
.fetch_locate_config <- function() {
  cwd_path <- file.path(getwd(), "inst", "etl", "00-config.R")
  installed <- system.file("etl", "00-config.R", package = "cvmdata")
  argv <- commandArgs(trailingOnly = FALSE)
  hit <- grep("^--file=", argv)
  argv_path <- if (length(hit)) {
    file.path(
      dirname(normalizePath(sub("^--file=", "", argv[hit[1L]]))),
      "00-config.R"
    )
  } else {
    ""
  }
  for (candidate in c(cwd_path, installed, argv_path)) {
    if (nzchar(candidate) && file.exists(candidate)) {
      return(candidate)
    }
  }
  stop("Could not locate inst/etl/00-config.R", call. = FALSE)
}
source(.fetch_locate_config())

# How many consecutive transport failures, with no fetch having ever
# succeeded, are enough to call the portal unreachable and stop.
#
# Why a breaker at all: on 2026-09-08 the `fre` job logged
# "0 ok / 612 failed", every one of them a 10 s TCP connect timeout to
# dados.cvm.gov.br, and took 5 h 51 min to say so — within minutes of
# GitHub's 6 h job ceiling. Measured on 2026-09-11 from eight runners in
# parallel: the portal answers in ~0,15 s over IPv4 (the runners have no
# IPv6 route), so these episodes are the portal dropping *some* Azure
# egress IPs for a while, never a bad URL on our side. Nothing we fetch
# later in the loop can succeed while that lasts.
#
# Why 8: each failed pair costs ~35 s (3 tries x 10 s connect plus
# backoff), so the breaker spends ~5 min before giving up — long enough
# not to trip on a single flaky pair, cheap enough to leave the runner.
# Overridable via `options(cvmdata.etl_transport_streak)` for tests.
fetch_transport_streak_limit <- function() {
  as.integer(getOption("cvmdata.etl_transport_streak", 8L))
}

# The breaker's decision, isolated so it is testable without network.
# Only fires while `n_ok == 0`: once anything has come through, the
# portal is reachable and a later run of failures is data-shaped (a
# table absent that year), which stage 02 handles.
fetch_breaker_tripped <- function(n_ok, transport_streak,
                                  limit = fetch_transport_streak_limit()) {
  identical(as.integer(n_ok), 0L) && as.integer(transport_streak) >= limit
}

# Fetch one (table, year, report_type) triple. Returns a list with `ok`
# and, when it failed, whether the failure was transport-level — the
# portal never answered — as opposed to an HTTP status or a parse error.
fetch_one <- function(dataset, tbl, year, report_type) {
  cond <- NULL
  res <- tryCatch(
    cvmdata::issuer_fetch(
      dataset, tbl,
      year = if (is.na(year)) NULL else year,
      report_type = report_type,
      source = "cvm"
    ),
    error = function(e) {
      cond <<- e
      message("     ABORT: ", conditionMessage(e))
      NULL
    }
  )
  list(
    ok = !is.null(res),
    transport = inherits(cond, "cvmdata_error_http_transport")
  )
}

# Walk every (table, year, report_type) of a dataset, stopping as soon
# as the breaker trips. Returns the tallies plus `tripped`, leaving the
# exit-code decision to the caller.
#
# The loop lives in a named function rather than inline in the driver
# for the same reason `validate_dataset()` does in 02b-validate.R: it
# keeps the entry point thin enough to read, and the driver's
# cyclomatic complexity inside the project's lint budget.
fetch_all <- function(dataset, tables, years_to_fetch) {
  n_ok <- 0L
  n_fail <- 0L
  n_transport <- 0L
  transport_streak <- 0L
  tripped <- FALSE
  for (tbl in tables) {
    for (y in years_to_fetch) {
      for (rt in mirror_variants_for(tbl)) {
        rt_label <- if (is.null(rt)) "" else sprintf("/%s", rt)
        label <- if (is.na(y)) sprintf("%s/%s%s", dataset, tbl, rt_label) else
          sprintf("%s/%s%s/%d", dataset, tbl, rt_label, y)
        message("  -> ", label)
        out <- fetch_one(dataset, tbl, y, rt)
        if (out$ok) {
          n_ok <- n_ok + 1L
          transport_streak <- 0L
        } else {
          n_fail <- n_fail + 1L
          if (out$transport) {
            n_transport <- n_transport + 1L
            transport_streak <- transport_streak + 1L
          } else {
            transport_streak <- 0L
          }
        }
        if (fetch_breaker_tripped(n_ok, transport_streak)) {
          tripped <- TRUE
          break
        }
      }
      if (tripped) break
    }
    if (tripped) break
  }
  list(
    n_ok = n_ok,
    n_fail = n_fail,
    n_transport = n_transport,
    transport_streak = transport_streak,
    tripped = tripped
  )
}

# --- CLI driver --------------------------------------------------------

# Guard so the file can be sourced from tests without firing main.
# Setting `options(cvmdata.etl_testing = TRUE)` keeps the helpers
# loaded but skips the entry point.
if (!isTRUE(getOption("cvmdata.etl_testing"))) {
  # Minimal CLI parsing (workflow inputs only).
  args <- commandArgs(trailingOnly = TRUE)
  group <- NULL
  dataset <- NULL
  year <- NULL
  i <- 1L
  while (i <= length(args)) {
    if (args[i] == "--group") {
      group <- args[i + 1L]
      i <- i + 2L
      next
    }
    if (args[i] == "--dataset") {
      dataset <- args[i + 1L]
      i <- i + 2L
      next
    }
    if (args[i] == "--year") {
      year <- as.integer(args[i + 1L])
      i <- i + 2L
      next
    }
    i <- i + 1L
  }
  if (is.null(group)) {
    stop("--group is required", call. = FALSE)
  }
  if (is.null(dataset)) {
    stop("--dataset is required", call. = FALSE)
  }
  if (!mirror_pair_valid(group, dataset)) {
    stop(sprintf(
      "(%s, %s) not in mirror_datasets_v0_1; valid pairs: %s",
      group, dataset,
      paste(sprintf("(%s, %s)",
                    mirror_datasets_v0_1$group,
                    mirror_datasets_v0_1$dataset),
            collapse = ", ")
    ), call. = FALSE)
  }

  # Pin the cache root to the ETL workspace so stage 02 finds the same
  # tree. Force backend to "cvm" — the mirror stub would abort here.
  workspace <- mirror_workspace()
  options(
    cvmdata.cache_dir = file.path(workspace, "cache"),
    cvmdata.source = "cvm"
  )

  tables <- mirror_tables(dataset)
  schema <- cvmdata:::load_schema(dataset, tables[1L])
  partitioning <- schema$temporal_partitioning %||% "none"

  years_to_fetch <- if (identical(partitioning, "yearly")) {
    if (is.null(year)) cvmdata::cvm_dataset_years(dataset) else year
  } else {
    NA_integer_
  }

  message(sprintf(
    "[01-fetch] group=%s dataset=%s tables=[%s] year =[%s] workspace=%s",
    group, dataset,
    paste(tables, collapse = ", "),
    paste(years_to_fetch, collapse = ", "),
    workspace
  ))

  tally <- fetch_all(dataset, tables, years_to_fetch)

  message(sprintf(
    "[01-fetch] done. %d ok / %d failed (%d of them transport-level)",
    tally$n_ok, tally$n_fail, tally$n_transport
  ))
  if (tally$tripped) {
    message(sprintf(
      paste(
        "[01-fetch] STOPPING EARLY: %d consecutive transport failures and",
        "no fetch has succeeded — the CVM portal is not answering this",
        "runner. This is an upstream/egress outage, not a bad URL: the",
        "mirror simply does not publish this week. Re-run the failed job;",
        "it lands on a different egress IP."
      ),
      tally$transport_streak
    ))
    quit(status = 3L)
  }
  # Tolerate partial misses (CVM has not published year N+1 yet for some
  # tables; certain (table, year) combos never existed). Only abort when
  # every fetch failed — same policy as stage 02.
  if (tally$n_fail > 0L && tally$n_ok == 0L) {
    quit(status = 1L)
  }
}
