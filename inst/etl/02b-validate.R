# Stage 2b — Validate parquets pre-publish.
#
# Runs between 02-csv-to-parquet.R and 03-publish.R. For each parquet
# the previous stage wrote under <workspace>/out/parquet/<dataset>/...,
# applies a hybrid set of checks. Hard (structural) failures abort the
# publish (exit 1); soft (content) failures emit a warning log and let
# the publish proceed.
#
# Hard checks (abort on failure):
#   * Parquet file exists where the schema implies it should
#   * Parquet readable by arrow
#   * n_rows > 0
#   * Identifier column has character type (matches reader policy)
#   * vl_conta numeric when the schema declares `multiply_by_scale`
#
# Soft checks (warn, continue):
#   * cnpj_cia / cnpj_companhia values match the CVM punctuated format
#   * cd_cvm values are all-digits when the column is present
#   * dt_refer / data_referencia within [first_year, today + 1y]
#
# Pointblank drives the column-level checks (regex, type, range);
# parquet existence and n_rows > 0 are handled inline so the report
# stays uniform across "file absent" and "file present but empty".
#
# Output:
#   * `<workspace>/out/validation/<dataset>.md` — per-parquet report
#   * stdout summary line for the workflow log
#   * exit 0 (all pass / soft warnings only), exit 1 (any hard fail),
#     exit 2 (no parquets found — usually means stage 02 did not run)
#
# Usage:
#   Rscript inst/etl/02b-validate.R --dataset cad [--year 2024]

# Locate 00-config.R across the three call modes this script supports:
#   * `Rscript inst/etl/02b-validate.R` from the package root — cwd has
#     the source tree, so `inst/etl/00-config.R` resolves directly.
#   * `system.file("etl", "00-config.R", package = "cvmdata")` from an
#     installed cvmdata — works for tests under R CMD check.
#   * Direct invocation by path — `commandArgs()` carries `--file=`,
#     whose dirname holds the sibling 00-config.R.
.validate_locate_config <- function() {
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

source(.validate_locate_config())

stopifnot(requireNamespace("arrow", quietly = TRUE))
stopifnot(requireNamespace("pointblank", quietly = TRUE))
stopifnot(requireNamespace("yaml", quietly = TRUE))

# CNPJ as published by CVM: XX.XXX.XXX/XXXX-XX. Applies to cnpj_cia
# and cnpj_companhia in every dataset. Reader leaves the value as-is.
.cnpj_regex <- "^[0-9]{2}\\.[0-9]{3}\\.[0-9]{3}/[0-9]{4}-[0-9]{2}$"

# CD_CVM is character but stores digits only. Padding varies by dataset
# (CAD: unpadded; ITR/DFP: zero-padded to 6); both match `^\\d+$`.
.cd_cvm_regex <- "^[0-9]+$"

# --- workspace helpers -------------------------------------------------

# Build the local parquet path mirroring 02-csv-to-parquet.R's layout.
validate_parquet_path <- function(root, dataset, table, year,
                                  report_type) {
  parts <- c(root, "out", "parquet", dataset, table)
  if (!is.null(report_type)) {
    parts <- c(parts, sprintf("report_type=%s", report_type))
  }
  if (!is.null(year) && !is.na(year)) {
    parts <- c(parts, sprintf("year=%d", as.integer(year)))
  }
  do.call(file.path, as.list(c(parts, "part-0.parquet")))
}

# Returns the list of (table, year, report_type) tuples the previous
# stage was supposed to write. Yearly tables expand across every year
# present upstream (or the override `years_arg`); non-yearly tables
# return a single tuple with year = NA.
validate_expected_tuples <- function(dataset, years_arg = NULL) {
  tables <- mirror_tables(dataset)
  schema <- cvmdata:::load_schema(dataset, tables[[1L]])
  partitioning <- schema$temporal_partitioning %||% "none"
  years <- if (identical(partitioning, "yearly")) {
    if (is.null(years_arg)) {
      cvmdata::cvm_dataset_years(dataset)
    } else {
      years_arg
    }
  } else {
    NA_integer_
  }
  out <- list()
  for (tbl in tables) {
    for (y in years) {
      for (rt in mirror_variants_for(tbl)) {
        out[[length(out) + 1L]] <- list(
          table = tbl,
          year = y,
          report_type = rt
        )
      }
    }
  }
  out
}

# Reads a schema YAML and surfaces the bits the validator branches on.
validate_schema_hints <- function(dataset, table) {
  schema <- cvmdata:::load_schema(dataset, table)
  multiply_by_scale <- FALSE
  for (tx in schema$transformations %||% list()) {
    if (identical(tx$action %||% "", "multiply_by_scale")) {
      multiply_by_scale <- TRUE
      break
    }
  }
  list(
    first_year = schema$first_year %||% 2010L,
    has_multiply_by_scale = multiply_by_scale
  )
}

# --- pointblank-driven column checks -----------------------------------

# Builds and interrogates the agent for one parquet's column checks.
# Returns the validation_set tibble of one row per check, plus a
# severity column derived from which action_levels tier configured
# the check (pointblank stores NA in the unconfigured tier's flag).
validate_run_pointblank <- function(tbl, hints, table) {
  pb_levels <- pointblank::action_levels
  hard <- pb_levels(stop_at = 1L)
  soft <- pb_levels(warn_at = 1L)

  cnpj_col <- if ("cnpj_cia" %in% names(tbl)) "cnpj_cia" else
    if ("cnpj_companhia" %in% names(tbl)) "cnpj_companhia" else NA_character_

  # tidyselect::all_of() avoids the "external vector in selection"
  # deprecation warning that bites when `columns = a_character_var`
  # is forwarded into pointblank's tidyselect machinery.
  col <- function(x) tidyselect::all_of(x)

  agent <- pointblank::create_agent(
    tbl = tbl, tbl_name = table, label = sprintf("cvmdata-etl-%s", table)
  )

  # Hard tier --------------------------------------------------------
  if (!is.na(cnpj_col)) {
    agent <- pointblank::col_is_character(
      agent, columns = col(cnpj_col), actions = hard,
      label = sprintf("%s is character", cnpj_col)
    )
  }
  if (isTRUE(hints$has_multiply_by_scale) && "vl_conta" %in% names(tbl)) {
    agent <- pointblank::col_is_numeric(
      agent, columns = col("vl_conta"), actions = hard,
      label = "vl_conta is numeric"
    )
  }

  # Soft tier --------------------------------------------------------
  if (!is.na(cnpj_col)) {
    agent <- pointblank::col_vals_regex(
      agent, columns = col(cnpj_col), regex = .cnpj_regex,
      na_pass = TRUE, actions = soft,
      label = sprintf("%s matches CVM CNPJ format", cnpj_col)
    )
  }
  if ("cd_cvm" %in% names(tbl)) {
    agent <- pointblank::col_vals_regex(
      agent, columns = col("cd_cvm"), regex = .cd_cvm_regex,
      na_pass = TRUE, actions = soft,
      label = "cd_cvm is all-digits"
    )
  }
  for (date_col in c("dt_refer", "data_referencia")) {
    if (date_col %in% names(tbl)) {
      lower <- as.Date(sprintf("%d-01-01", hints$first_year))
      upper <- Sys.Date() + 365L
      agent <- pointblank::col_vals_between(
        agent, columns = col(date_col),
        left = lower, right = upper,
        na_pass = TRUE, actions = soft,
        label = sprintf("%s within [%s, %s]", date_col, lower, upper)
      )
    }
  }

  vset <- pointblank::interrogate(agent)$validation_set
  # Pointblank leaves `stop` NA on checks that did not configure
  # `stop_at`, and `warn` NA on checks that did not configure
  # `warn_at`. Since each check here belongs to exactly one tier,
  # presence-of-flag is a reliable severity signal.
  vset$severity <- ifelse(!is.na(vset$stop), "hard", "soft")
  vset
}

# --- single parquet ----------------------------------------------------

# Returns a tibble with one row per check applied to this parquet.
# The synthetic checks (existence, readable, n_rows > 0) always come
# first and short-circuit: if any of them fails, the column-level
# checks are skipped to keep the report cause-and-effect.
validate_one_parquet <- function(parquet_path, dataset, table, hints) {
  if (!file.exists(parquet_path)) {
    return(tibble::tibble(
      check = "parquet_exists",
      severity = "hard",
      status = "fail",
      n = 0L, n_failed = 0L,
      note = parquet_path
    ))
  }
  tbl <- tryCatch(
    tibble::as_tibble(arrow::read_parquet(parquet_path)),
    error = function(ex) ex
  )
  if (inherits(tbl, "error")) {
    return(tibble::tibble(
      check = "parquet_readable",
      severity = "hard",
      status = "fail",
      n = 0L, n_failed = 0L,
      note = conditionMessage(tbl)
    ))
  }
  pre <- tibble::tibble(
    check = c("parquet_exists", "parquet_readable", "n_rows > 0"),
    severity = c("hard", "hard", "hard"),
    status = c("pass", "pass",
               if (nrow(tbl) > 0L) "pass" else "fail"),
    n = c(NA_integer_, NA_integer_, nrow(tbl)),
    n_failed = c(NA_integer_, NA_integer_,
                 if (nrow(tbl) > 0L) 0L else 1L),
    note = c("", "", sprintf("%d row(s)", nrow(tbl)))
  )
  if (nrow(tbl) == 0L) {
    return(pre)
  }
  vset <- validate_run_pointblank(tbl, hints, table)
  pb <- tibble::tibble(
    check = vset$label,
    severity = vset$severity,
    status = ifelse(vset$all_passed, "pass", "fail"),
    n = as.integer(vset$n),
    n_failed = as.integer(vset$n_failed),
    note = ""
  )
  rbind(pre, pb)
}

# --- aggregate ---------------------------------------------------------

# Returns a tibble with one row per (table, year, report_type) tuple,
# carrying the aggregated status and the full per-check detail.
validate_dataset <- function(dataset, workspace, years_arg = NULL) {
  expected <- validate_expected_tuples(dataset, years_arg)
  if (!length(expected)) {
    return(tibble::tibble(
      table = character(0L),
      year = integer(0L),
      report_type = character(0L),
      status = character(0L),
      hard_failed = integer(0L),
      soft_failed = integer(0L),
      details = list()
    ))
  }
  rows <- vector("list", length(expected))
  for (i in seq_along(expected)) {
    e <- expected[[i]]
    path <- validate_parquet_path(
      workspace, dataset, e$table, e$year, e$report_type
    )
    label <- sprintf(
      "%s/%s%s%s", dataset, e$table,
      if (!is.null(e$report_type)) sprintf("/%s", e$report_type) else "",
      if (!is.na(e$year)) sprintf("/%d", e$year) else ""
    )
    hints <- validate_schema_hints(dataset, e$table)
    details <- validate_one_parquet(path, dataset, e$table, hints)
    hard_failed <- sum(details$status == "fail" &
                         details$severity == "hard")
    soft_failed <- sum(details$status == "fail" &
                         details$severity == "soft")
    status <- if (hard_failed > 0L) "hard_fail" else
      if (soft_failed > 0L) "soft_fail" else "pass"
    message(sprintf(
      "  [%s] %s",
      switch(status, pass = "OK   ", soft_fail = "SOFT ", hard_fail = "HARD "),
      label
    ))
    rows[[i]] <- tibble::tibble(
      table = e$table,
      year = as.integer(e$year),
      report_type = e$report_type %||% NA_character_,
      status = status,
      hard_failed = hard_failed,
      soft_failed = soft_failed,
      details = list(as.data.frame(details))
    )
  }
  do.call(rbind, rows)
}

# --- report writer -----------------------------------------------------

validate_write_report <- function(results, dataset, out_dir) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_path <- file.path(out_dir, sprintf("%s.md", dataset))
  lines <- c(
    sprintf("# ETL validation report: %s", dataset),
    sprintf("Generated: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC")),
    "",
    sprintf("Total parquets checked: %d", nrow(results)),
    sprintf("  pass:       %d", sum(results$status == "pass")),
    sprintf("  soft_fail:  %d", sum(results$status == "soft_fail")),
    sprintf("  hard_fail:  %d", sum(results$status == "hard_fail")),
    ""
  )
  for (i in seq_len(nrow(results))) {
    r <- results[i, ]
    label <- sprintf(
      "%s%s%s",
      r$table,
      if (!is.na(r$report_type)) sprintf("/%s", r$report_type) else "",
      if (!is.na(r$year)) sprintf("/%d", r$year) else ""
    )
    lines <- c(lines, sprintf("## %s -- %s", label, toupper(r$status)))
    det <- r$details[[1L]]
    if (!is.null(det) && nrow(det)) {
      for (j in seq_len(nrow(det))) {
        d <- det[j, ]
        suffix <- if (!is.na(d$n_failed) && d$n_failed > 0L) {
          sprintf(" (%d/%d failed)", d$n_failed, d$n)
        } else {
          ""
        }
        note_suffix <- if (nzchar(d$note %||% "")) {
          sprintf(" -- %s", d$note)
        } else {
          ""
        }
        lines <- c(lines, sprintf(
          "  - [%s] %s -- %s%s%s",
          d$severity, d$status, d$check, suffix, note_suffix
        ))
      }
    }
    lines <- c(lines, "")
  }
  writeLines(lines, out_path)
  out_path
}

# --- CLI driver --------------------------------------------------------

# Guard so the file can be sourced from tests without firing main.
# Setting `options(cvmdata.etl_testing = TRUE)` keeps the helpers
# loaded but skips the entry point. Calling with `Rscript` and no args
# also exits early so source-evaluation in the IDE never side-effects.
if (!isTRUE(getOption("cvmdata.etl_testing")) &&
      length(commandArgs(trailingOnly = TRUE)) > 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  dataset <- NULL
  year <- NULL
  i <- 1L
  while (i <= length(args)) {
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
  if (is.null(dataset)) {
    stop("--dataset is required", call. = FALSE)
  }
  if (!dataset %in% mirror_datasets_v0_1) {
    stop(sprintf(
      "dataset '%s' not in mirror_datasets_v0_1 (%s)",
      dataset, paste(mirror_datasets_v0_1, collapse = ", ")
    ), call. = FALSE)
  }
  workspace <- mirror_workspace()
  options(
    cvmdata.cache_dir = file.path(workspace, "cache"),
    cvmdata.source = "cvm"
  )

  message(sprintf("[02b-validate] dataset=%s workspace=%s",
                  dataset, workspace))
  results <- validate_dataset(
    dataset, workspace,
    years_arg = if (is.null(year)) NULL else year
  )
  if (!nrow(results)) {
    message("[02b-validate] no parquets found -- did stage 02 run?")
    quit(status = 2L)
  }
  out_path <- validate_write_report(
    results, dataset, file.path(workspace, "out", "validation")
  )
  hard <- sum(results$hard_failed)
  soft <- sum(results$soft_failed)
  message(sprintf(
    "[02b-validate] done. %d parquet(s); %d hard fail(s); %d soft warn(s)",
    nrow(results), hard, soft
  ))
  message(sprintf("[02b-validate] report at %s", out_path))
  if (hard > 0L) {
    quit(status = 1L)
  }
}
