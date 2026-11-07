# Stage 6 — Prepare the quarterly DOI edition of the mirror on Zenodo.
#
# Four editions a year (the first weekly round of January, April, July
# and October), one deposit per edition with every dataset of the
# mirror as it was on the edition date, in one Zenodo record with a
# version per edition (design decided by the owner on 2026-11-06; the
# helpers and the checks are in util-zenodo.R). The robot prepares a
# DRAFT and stops: the owner reads the report, opens the draft on the
# site and publishes it, because a published record cannot be deleted.
#
# The run, in order:
#   1. for every dataset, resolve the snapshot on or before the edition
#      date, download its partitions and the history assets, and
#      verify every partition against the sha256 the mirror published;
#   2. count the rows by table and compare them with the previous
#      edition (its manifest.csv, read from Zenodo): a table with fewer
#      rows, or gone, fails the edition unless --allow-shrink;
#   3. pack one tar per dataset and add README, dictionary, code lists,
#      licence, manifest and SHA256SUMS;
#   4. only when every check passed: open the draft (a new deposition
#      for the first edition, a new version of the latest published one
#      after that), set the metadata, make its files match the local
#      ones, read every file back and compare the digests. A failure
#      here drops the draft, so a failed run leaves nothing to publish.
#   5. write the report (<workspace>/zenodo/<edition>/edition-report.md)
#      the owner reads before publishing.
#
# Usage:
#   Rscript inst/etl/06-zenodo-edition.R [--target sandbox|production]
#     [--edition YYYY-MM-DD] [--datasets cad,dfp,...] [--grace 14]
#     [--concept <conceptrecid>] [--allow-shrink] [--dry-run]
#
# The token comes from ZENODO_SANDBOX_TOKEN or ZENODO_TOKEN and the
# concept record id (after the first edition is published) from
# ZENODO_SANDBOX_CONCEPT or ZENODO_CONCEPT, by target; `--target`
# defaults to the sandbox, where a mistake costs nothing. `--dry-run`
# builds and verifies the files and never touches Zenodo. Setting
# `options(cvmdata.etl_testing = TRUE)` loads the helpers and skips the
# entry point.

for (sibling in c("00-config.R", "util-release.R", "util-zenodo.R")) {
  marker <- c(
    "00-config.R" = "mirror_tag_latest",
    "util-release.R" = "download_public_asset",
    "util-zenodo.R" = "edition_date_for"
  )[[sibling]]
  if (!exists(marker, mode = "function")) {
    source(file.path("inst", "etl", sibling))
  }
}

stopifnot(requireNamespace("arrow", quietly = TRUE))

# --- the files outside the mirror ------------------------------------

# A file of inst/extdata, from the installed package or the checkout.
edition_extdata <- function(name) {
  installed <- system.file("extdata", name, package = "cvmdata")
  path <- if (nzchar(installed)) {
    installed
  } else {
    file.path("inst", "extdata", name)
  }
  if (!file.exists(path)) {
    stop(
      sprintf("%s not found (installed package or checkout)", name),
      call. = FALSE
    )
  }
  path
}

# A file of the repository root (DATA-LICENSE.md is not installed).
edition_repo_file <- function(name) {
  if (!file.exists(name)) {
    stop(
      sprintf("%s not found: run from the repository root", name),
      call. = FALSE
    )
  }
  name
}

edition_package_version <- function() {
  tryCatch(
    as.character(utils::packageVersion("cvmdata")),
    error = function(e) {
      as.character(read.dcf("DESCRIPTION", fields = "Version")[[1L]])
    }
  )
}

# The token and the concept record id of the target, from the
# environment unless given.
edition_token <- function(target) {
  var <- if (target == "production") "ZENODO_TOKEN" else "ZENODO_SANDBOX_TOKEN"
  token <- Sys.getenv(var, "")
  if (!nzchar(token)) {
    stop(sprintf("%s is not set", var), call. = FALSE)
  }
  token
}

edition_concept <- function(target, concept = NULL) {
  if (!is.null(concept) && nzchar(concept)) {
    return(concept)
  }
  var <- if (target == "production") {
    "ZENODO_CONCEPT"
  } else {
    "ZENODO_SANDBOX_CONCEPT"
  }
  value <- Sys.getenv(var, "")
  if (nzchar(value)) value else NULL
}

# Builds the files of the deposit under `deposit_dir` (emptied first)
# and returns data.frame(name, path, sha256, md5, size).
edition_build_deposit <- function(
  plans,
  group,
  files_dir,
  deposit_dir,
  edition,
  snapshots,
  counts,
  manifest,
  package_version
) {
  unlink(deposit_dir, recursive = TRUE)
  dir.create(deposit_dir, recursive = TRUE, showWarnings = FALSE)
  for (plan in plans) {
    tarfile <- edition_pack_dataset(
      plan,
      group,
      files_dir,
      deposit_dir,
      edition
    )
    message(sprintf(
      "  packed %s (%s MB)",
      basename(tarfile),
      format(round(file.size(tarfile) / 1e6, 1), nsmall = 1L)
    ))
  }
  utils::write.csv(
    manifest,
    file.path(deposit_dir, "manifest.csv"),
    row.names = FALSE,
    fileEncoding = "UTF-8"
  )
  readme <- file(
    file.path(deposit_dir, "README.md"),
    open = "w",
    encoding = "UTF-8"
  )
  writeLines(
    edition_readme(edition, snapshots, counts, package_version),
    readme
  )
  close(readme)
  file.copy(edition_repo_file("DATA-LICENSE.md"), deposit_dir, overwrite = TRUE)
  file.copy(
    edition_extdata("cvm_dictionary_snapshot.csv"),
    file.path(deposit_dir, "cvm_dictionary.csv"),
    overwrite = TRUE
  )
  file.copy(
    edition_extdata("cvm_codelists_snapshot.csv"),
    file.path(deposit_dir, "cvm_codelists.csv"),
    overwrite = TRUE
  )
  paths <- sort(list.files(deposit_dir, full.names = TRUE))
  writeLines(edition_sha256sums(paths), file.path(deposit_dir, "SHA256SUMS"))
  paths <- sort(list.files(deposit_dir, full.names = TRUE))
  data.frame(
    name = basename(paths),
    path = paths,
    sha256 = vapply(
      paths,
      function(p) digest::digest(file = p, algo = "sha256"),
      character(1L)
    ),
    md5 = vapply(
      paths,
      function(p) digest::digest(file = p, algo = "md5"),
      character(1L)
    ),
    size = file.size(paths),
    stringsAsFactors = FALSE
  )
}

# --- the run ----------------------------------------------------------

# Returns list(outcome, status, report): status 0 when the draft is
# ready (or the dry run passed), 1 when a check failed.
edition_main <- function(opts) {
  group <- "companhias"
  edition <- opts$edition %||% format(edition_date_for(Sys.Date(), opts$grace))
  datasets <- opts$datasets %||%
    mirror_datasets_v0_1$dataset[mirror_datasets_v0_1$group == group]
  unknown <- datasets[
    !vapply(datasets, function(d) mirror_pair_valid(group, d), logical(1L))
  ]
  if (length(unknown)) {
    stop(
      sprintf("unknown dataset(s): %s", paste(unknown, collapse = ", ")),
      call. = FALSE
    )
  }
  work <- file.path(mirror_workspace(), "zenodo", edition)
  sidecar_dir <- file.path(work, "sidecars")
  files_dir <- file.path(work, "files")
  deposit_dir <- file.path(work, "deposit")
  readback_dir <- file.path(work, "readback")
  dir.create(work, recursive = TRUE, showWarnings = FALSE)
  report_path <- file.path(work, "edition-report.md")
  message(sprintf(
    "[06-zenodo] edition %s on the %s; %d dataset(s)%s",
    edition,
    opts$target,
    length(datasets),
    if (opts$dry_run) " (dry run)" else ""
  ))

  # 1. the files of the mirror, verified
  plans <- list()
  snapshots <- list()
  for (ds in datasets) {
    sidecars <- edition_read_sidecars(group, ds, edition, sidecar_dir)
    plan <- edition_plan_dataset(group, ds, sidecars$latest, sidecars$snapshot)
    message(sprintf(
      "[06-zenodo] %s: snapshot %s, %d partition(s), %d history asset(s)",
      ds,
      sidecars$date,
      sum(plan$kind == "partition"),
      sum(plan$kind == "history")
    ))
    plan <- edition_fetch_dataset(plan, files_dir)
    plan$rows <- vapply(plan$path, edition_row_count, numeric(1L))
    plans[[ds]] <- plan
    snapshots[[ds]] <- sidecars$date
  }
  all_plan <- do.call(rbind, plans)
  digests_failed <- edition_verify_digests(all_plan)
  counts <- edition_count_tables(all_plan)
  manifest <- edition_manifest(plans)

  # 2. the previous edition
  client <- NULL
  previous <- NULL
  concept <- edition_concept(opts$target, opts$concept)
  if (!opts$dry_run) {
    client <- zenodo_client(edition_token(opts$target), opts$target)
    zenodo_check_token(client)
    previous <- zenodo_previous_manifest(client, concept, work)
  }
  comparison <- edition_compare_counts(
    counts,
    if (!is.null(previous)) edition_counts_from_manifest(previous)
  )
  count_failures <- edition_count_failures(comparison, opts$allow_shrink)

  # 3. the package of files
  package_version <- edition_package_version()
  files <- edition_build_deposit(
    plans,
    group,
    files_dir,
    deposit_dir,
    edition,
    snapshots,
    counts,
    manifest,
    package_version
  )
  shown <- files[c("name", "size", "sha256")]

  finish <- function(outcome, status, draft = NULL, read_back = NULL) {
    report <- edition_report(
      edition,
      opts$target,
      snapshots,
      digests_failed,
      comparison,
      count_failures,
      previous,
      shown,
      draft,
      read_back,
      outcome
    )
    con <- file(report_path, open = "w", encoding = "UTF-8")
    writeLines(report, con)
    close(con)
    message(sprintf("[06-zenodo] %s; report at %s", outcome, report_path))
    list(outcome = outcome, status = status, report = report_path)
  }

  if (nrow(digests_failed) || nrow(count_failures)) {
    return(finish(
      sprintf(
        paste(
          "FAILED before the deposit: %d partition(s) with a wrong digest,",
          "%d table(s) with fewer rows or missing"
        ),
        nrow(digests_failed),
        nrow(count_failures)
      ),
      1L
    ))
  }
  if (opts$dry_run) {
    return(finish("dry run: files built and verified; Zenodo not touched", 0L))
  }

  # 4. the draft
  zenodo_check_license(client)
  metadata <- edition_metadata(
    edition,
    snapshots,
    package_version,
    edition_description(edition, snapshots, counts)
  )
  draft <- zenodo_open_draft(client, concept, metadata)
  message(sprintf(
    "[06-zenodo] draft %s (%s): %s",
    draft$id,
    if (isTRUE(attr(draft, "created"))) "new record" else "new version",
    draft$links$html %||% ""
  ))
  read_back <- NULL
  failure <- tryCatch(
    {
      zenodo_set_metadata(client, draft, metadata)
      actions <- zenodo_sync_files(client, draft, files)
      message(sprintf(
        paste(
          "[06-zenodo] files: %d kept from the previous edition,",
          "%d uploaded, %d removed"
        ),
        length(actions$keep),
        length(actions$upload),
        length(actions$delete)
      ))
      read_back <- zenodo_read_back(client, draft$id, files, readback_dir)
      NULL
    },
    error = function(e) conditionMessage(e)
  )
  if (!is.null(failure) || any(read_back$status != "ok")) {
    dropped <- zenodo_drop_draft(client, draft)
    return(finish(
      sprintf(
        "FAILED at the deposit (%s; draft %s %s)",
        failure %||% "read-back found a file missing, extra or different",
        draft$id,
        dropped
      ),
      1L,
      draft,
      read_back
    ))
  }
  finish("ready", 0L, draft, read_back)
}

# The flags of stage 06: the ones that take a value and the switches.
edition_flag_values <- c(
  "--target" = "target",
  "--edition" = "edition",
  "--datasets" = "datasets",
  "--grace" = "grace",
  "--concept" = "concept"
)
edition_flag_switches <- c(
  "--allow-shrink" = "allow_shrink",
  "--dry-run" = "dry_run"
)

edition_parse_args <- function(args) {
  opts <- list(
    target = "sandbox",
    edition = NULL,
    datasets = NULL,
    grace = edition_grace_days,
    concept = NULL,
    allow_shrink = FALSE,
    dry_run = FALSE
  )
  i <- 1L
  while (i <= length(args)) {
    a <- args[i]
    if (a %in% names(edition_flag_values)) {
      opts[[edition_flag_values[[a]]]] <- args[i + 1L]
      i <- i + 2L
    } else if (a %in% names(edition_flag_switches)) {
      opts[[edition_flag_switches[[a]]]] <- TRUE
      i <- i + 1L
    } else {
      i <- i + 1L
    }
  }
  edition_check_args(opts)
}

# The parsed options, typed and checked.
edition_check_args <- function(opts) {
  if (!opts$target %in% c("sandbox", "production")) {
    stop("--target must be sandbox or production", call. = FALSE)
  }
  if (!is.null(opts$edition)) {
    parsed <- as.Date(opts$edition, format = "%Y-%m-%d")
    if (is.na(parsed) || !identical(format(parsed), opts$edition)) {
      stop("--edition must be a complete date, YYYY-MM-DD", call. = FALSE)
    }
  }
  if (!is.null(opts$datasets)) {
    opts$datasets <- trimws(strsplit(opts$datasets, ",", fixed = TRUE)[[1L]])
  }
  opts$grace <- suppressWarnings(as.integer(opts$grace))
  if (length(opts$grace) != 1L || is.na(opts$grace) || opts$grace < 0L) {
    stop("--grace must be a number of days", call. = FALSE)
  }
  opts
}

if (!isTRUE(getOption("cvmdata.etl_testing"))) {
  opts <- edition_parse_args(commandArgs(trailingOnly = TRUE))
  result <- edition_main(opts)
  quit(status = result$status)
}
