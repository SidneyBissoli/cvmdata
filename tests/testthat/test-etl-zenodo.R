# Tests for inst/etl/util-zenodo.R and the pure helpers of
# inst/etl/06-zenodo-edition.R: the quarterly DOI editions of the
# mirror on Zenodo (design decided by the owner on 2026-11-06). The
# robot prepares a draft and never publishes; the last test reads the
# source to prove the publish endpoint is absent.

load_etl_zenodo <- function() {
  for (pkg in c("httr2", "digest", "jsonlite", "arrow")) {
    skip_if_not_installed(pkg)
  }
  env <- parent.frame()
  withr::local_options(cvmdata.etl_testing = TRUE, .local_envir = env)
  scripts <- c(
    "00-config.R",
    "util-release.R",
    "util-zenodo.R",
    "06-zenodo-edition.R"
  )
  for (script in scripts) {
    installed <- system.file("etl", script, package = "cvmdata")
    path <- if (nzchar(installed)) {
      installed
    } else {
      normalizePath(
        test_path("..", "..", "inst", "etl", script),
        winslash = "/"
      )
    }
    sys.source(path, envir = env)
  }
}

etl_zenodo_source <- function(script) {
  installed <- system.file("etl", script, package = "cvmdata")
  if (nzchar(installed)) {
    return(installed)
  }
  normalizePath(test_path("..", "..", "inst", "etl", script), winslash = "/")
}

# --- the calendar -----------------------------------------------------

test_that("the edition dates are the first Tuesdays of the edition months", {
  load_etl_zenodo()
  expect_identical(edition_first_tuesday(2026L, 1L), as.Date("2026-01-06"))
  expect_identical(edition_first_tuesday(2026L, 4L), as.Date("2026-04-07"))
  expect_identical(edition_first_tuesday(2026L, 7L), as.Date("2026-07-07"))
  expect_identical(edition_first_tuesday(2026L, 10L), as.Date("2026-10-06"))
  # a month that starts on a Tuesday
  expect_identical(edition_first_tuesday(2025L, 7L), as.Date("2025-07-01"))
  expect_identical(
    edition_dates(2026L),
    as.Date(c("2026-01-06", "2026-04-07", "2026-07-07", "2026-10-06"))
  )
})

test_that("the robot prepares the latest edition whose grace elapsed", {
  load_etl_zenodo()
  # the scheduled day: the 22nd, 16 days after 2026-10-06
  expect_identical(edition_date_for("2026-10-22"), as.Date("2026-10-06"))
  # the day before the grace ends: the previous edition
  expect_identical(edition_date_for("2026-10-19"), as.Date("2026-07-07"))
  expect_identical(edition_date_for("2026-10-20"), as.Date("2026-10-06"))
  # January reaches back into the previous year
  expect_identical(edition_date_for("2026-01-10"), as.Date("2025-10-07"))
  # no grace: the edition of the day
  expect_identical(
    edition_date_for("2026-10-06", grace = 0L),
    as.Date("2026-10-06")
  )
})

test_that("the snapshot of a dataset is the latest on or before the edition", {
  load_etl_zenodo()
  dates <- list("2026-10-27", "2026-11-03", "2026-11-05")
  expect_identical(
    edition_pick_snapshot(dates, "2026-11-04", "dfp"),
    "2026-11-03"
  )
  expect_identical(
    edition_pick_snapshot(dates, "2026-11-03", "dfp"),
    "2026-11-03"
  )
  expect_identical(
    edition_pick_snapshot(dates, "2027-01-05", "dfp"),
    "2026-11-05"
  )
  expect_error(
    edition_pick_snapshot(dates, "2026-10-06", "dfp"),
    "no snapshot on or before 2026-10-06 \\(earliest: 2026-10-27\\)"
  )
  expect_error(
    edition_pick_snapshot(list(), "2026-10-06", "cad"),
    "no snapshot"
  )
})

# --- the files of a dataset ------------------------------------------

snapshot_tag_a <- "mirror-companhias-dfp-snapshot-2026-10-27"
snapshot_tag_b <- "mirror-companhias-dfp-snapshot-2026-11-03"

sidecar_snapshot <- function() {
  list(
    snapshot = "2026-11-03",
    files = list(
      "bpa/report_type=ind/year=2024/part-0.parquet" = list(
        sha256 = "aaa",
        size = 10
      ),
      "bpa/report_type=ind/year=2025/part-0.parquet" = list(
        sha256 = "bbb",
        size = 20
      )
    ),
    releases = list(
      "bpa/report_type=ind/year=2024/part-0.parquet" = snapshot_tag_a,
      "bpa/report_type=ind/year=2025/part-0.parquet" = snapshot_tag_b
    )
  )
}

sidecar_latest <- function() {
  list(
    snapshot = "2026-11-05",
    snapshots = list("2026-10-27", "2026-11-03", "2026-11-05"),
    history = list(
      "bpa/report_type=ind/year=2024/history.parquet" = "h1"
    )
  )
}

test_that("the plan of a dataset lists its partitions and history assets", {
  load_etl_zenodo()
  plan <- edition_plan_dataset(
    "companhias",
    "dfp",
    sidecar_latest(),
    sidecar_snapshot()
  )
  expect_identical(attr(plan, "snapshot"), "2026-11-03")
  expect_identical(plan$kind, c("partition", "partition", "history"))
  expect_identical(
    plan$tag,
    c(
      "mirror-companhias-dfp-snapshot-2026-10-27",
      "mirror-companhias-dfp-snapshot-2026-11-03",
      "mirror-companhias-dfp-latest"
    )
  )
  expect_identical(plan$sha256, c("aaa", "bbb", NA))
  expect_identical(plan$size, c(10, 20, NA))
  expect_identical(
    plan$name,
    c(
      "bpa__report_type.ind__year.2024__part-0.parquet",
      "bpa__report_type.ind__year.2025__part-0.parquet",
      "bpa__report_type.ind__year.2024__history.parquet"
    )
  )
})

test_that("a snapshot that does not say where a partition lives is refused", {
  load_etl_zenodo()
  snapshot <- sidecar_snapshot()
  snapshot$releases[[2L]] <- NULL
  expect_error(
    edition_plan_dataset("companhias", "dfp", sidecar_latest(), snapshot),
    "does not say where 1 partition"
  )
  expect_error(
    edition_plan_dataset(
      "companhias",
      "dfp",
      sidecar_latest(),
      list(snapshot = "x")
    ),
    "no `files` map"
  )
})

test_that("the digests of the partitions are judged, the history is not", {
  load_etl_zenodo()
  plan <- data.frame(
    dataset = "dfp",
    kind = c("partition", "partition", "history"),
    rel = c("a", "b", "c"),
    sha256 = c("aaa", "bbb", NA),
    sha256_actual = c("aaa", "xxx", "zzz"),
    stringsAsFactors = FALSE
  )
  failed <- edition_verify_digests(plan)
  expect_identical(failed$rel, "b")
  expect_identical(failed$actual, "xxx")
  plan$sha256_actual[[2L]] <- "bbb"
  expect_identical(nrow(edition_verify_digests(plan)), 0L)
})

# --- row counts ------------------------------------------------------

test_that("row counts are summed by dataset, kind and table", {
  load_etl_zenodo()
  plan <- data.frame(
    dataset = c("dfp", "dfp", "dfp", "cad"),
    kind = c("partition", "partition", "history", "partition"),
    rel = c(
      "bpa/report_type=ind/year=2024/part-0.parquet",
      "bpa/report_type=con/year=2024/part-0.parquet",
      "bpa/report_type=ind/year=2024/history.parquet",
      "companhias/part-0.parquet"
    ),
    rows = c(10, 5, 2, 100),
    stringsAsFactors = FALSE
  )
  counts <- edition_count_tables(plan)
  expect_identical(counts$dataset, c("cad", "dfp", "dfp"))
  expect_identical(counts$kind, c("partition", "history", "partition"))
  expect_identical(counts$table, c("companhias", "bpa", "bpa"))
  expect_identical(counts$rows, c(100, 2, 15))
})

test_that("a table with fewer rows or gone fails unless shrinking is allowed", {
  load_etl_zenodo()
  now <- data.frame(
    dataset = c("dfp", "dfp", "cad"),
    kind = "partition",
    table = c("bpa", "dre", "companhias"),
    rows = c(15, 50, 100),
    stringsAsFactors = FALSE
  )
  prev <- data.frame(
    dataset = c("dfp", "dfp", "dfp"),
    kind = "partition",
    table = c("bpa", "dre", "dva"),
    rows = c(15, 60, 7),
    stringsAsFactors = FALSE
  )
  cmp <- edition_compare_counts(now, prev)
  expect_identical(
    names(cmp),
    c("dataset", "kind", "table", "rows_prev", "rows_now")
  )
  expect_identical(cmp$table, c("companhias", "bpa", "dre", "dva"))
  expect_identical(cmp$rows_prev, c(NA, 15, 60, 7))
  expect_identical(cmp$rows_now, c(100, 15, 50, NA))
  failures <- edition_count_failures(cmp)
  expect_identical(failures$table, c("dre", "dva"))
  expect_identical(failures$reason, c("fewer rows", "table missing"))
  allowed <- edition_count_failures(cmp, allow_shrink = TRUE)
  expect_identical(allowed$table, "dva")
  # the first edition has nothing to compare with
  first <- edition_compare_counts(now, NULL)
  expect_true(all(is.na(first$rows_prev)))
  expect_identical(nrow(edition_count_failures(first)), 0L)
})

test_that("the manifest round-trips the counts of an edition", {
  load_etl_zenodo()
  plan <- data.frame(
    dataset = "dfp",
    kind = c("partition", "history"),
    rel = c(
      "bpa/report_type=ind/year=2024/part-0.parquet",
      "bpa/report_type=ind/year=2024/history.parquet"
    ),
    tag = "t",
    sha256_actual = c("a", "b"),
    size_actual = c(1, 2),
    rows = c(10, 3),
    stringsAsFactors = FALSE
  )
  attr(plan, "snapshot") <- "2026-11-03"
  manifest <- edition_manifest(list(dfp = plan))
  expect_identical(
    names(manifest),
    c("dataset", "snapshot", "kind", "rel", "release", "sha256", "size", "rows")
  )
  expect_identical(manifest$snapshot, c("2026-11-03", "2026-11-03"))
  counts <- edition_counts_from_manifest(manifest)
  expect_identical(counts$rows, c(3, 10))
})

# --- the package of files ---------------------------------------------

test_that("a dataset packs into a tar with the mirror's paths inside", {
  load_etl_zenodo()
  root <- withr::local_tempdir()
  files_dir <- file.path(root, "files")
  rel <- "bpa/report_type=ind/year=2024/part-0.parquet"
  path <- file.path(files_dir, "dfp", rel)
  dir.create(dirname(path), recursive = TRUE)
  arrow::write_parquet(data.frame(x = 1:3), path)
  expect_identical(edition_row_count(path), 3L)
  plan <- data.frame(
    dataset = "dfp",
    rel = rel,
    path = path,
    stringsAsFactors = FALSE
  )
  out_dir <- file.path(root, "deposit")
  dir.create(out_dir)
  tarfile <- edition_pack_dataset(
    plan,
    "companhias",
    files_dir,
    out_dir,
    "2026-10-06"
  )
  expect_identical(basename(tarfile), "companhias-dfp.tar")
  listed <- utils::untar(tarfile, list = TRUE, tar = "internal")
  expect_true(paste0("dfp/", rel) %in% listed)
  # the file time is the edition date, so an unchanged dataset packs the same
  expect_identical(
    format(file.mtime(path), "%Y-%m-%d", tz = "UTC"),
    "2026-10-06"
  )
  sums <- edition_sha256sums(tarfile)
  expect_match(sums, "^[0-9a-f]{64}  companhias-dfp\\.tar$")
})

test_that("the README and the description name every dataset", {
  load_etl_zenodo()
  snapshots <- list(cad = "2026-10-06", dfp = "2026-09-29")
  counts <- data.frame(
    dataset = c("cad", "dfp", "dfp"),
    kind = c("partition", "partition", "history"),
    table = c("companhias", "bpa", "bpa"),
    rows = c(1000, 25000, 300),
    stringsAsFactors = FALSE
  )
  readme <- edition_readme(
    "2026-10-06",
    snapshots,
    counts,
    "0.2.0.9000",
    "2026-10-22"
  )
  expect_identical(readme[[1L]], "# cvmdata mirror — edition 2026-10-06")
  expect_true(any(grepl(
    "| `dfp` | 2026-09-29 | 25,000 | 300 |",
    readme,
    fixed = TRUE
  )))
  expect_true(any(grepl("Deposited on 2026-10-22", readme, fixed = TRUE)))
  html <- edition_description("2026-10-06", snapshots, counts)
  expect_match(
    html,
    "<code>cad</code>: snapshot of 2026-10-06, 1,000 current rows"
  )
})

test_that("the metadata is an ODbL dataset, dated and versioned by edition", {
  load_etl_zenodo()
  md <- edition_metadata(
    "2026-10-06",
    list(cad = "2026-10-06"),
    "0.2.0.9000",
    "<p>x</p>"
  )
  expect_identical(md$upload_type, "dataset")
  expect_identical(md$license, "odbl-1.0")
  expect_identical(md$access_right, "open")
  expect_identical(md$publication_date, "2026-10-06")
  expect_identical(md$version, "2026-10-06")
  expect_identical(md$creators[[1L]]$orcid, "0009-0001-0442-3700")
  relations <- vapply(md$related_identifiers, `[[`, character(1L), "relation")
  expect_true("isDerivedFrom" %in% relations)
  expect_match(md$notes, "cad 2026-10-06")
  # jsonlite must serialise it as the API expects (scalars unboxed)
  json <- jsonlite::toJSON(list(metadata = md), auto_unbox = TRUE)
  expect_match(as.character(json), "\"upload_type\":\"dataset\"", fixed = TRUE)
  expect_match(as.character(json), "\"keywords\":[\"CVM\"", fixed = TRUE)
})

# --- the Zenodo API --------------------------------------------------

test_that("the robot never runs the publish action", {
  load_etl_zenodo()
  client <- zenodo_client("token", "sandbox")
  expect_error(
    zenodo_action(client, 1L, "publish"),
    "never runs the Zenodo action 'publish'"
  )
  expect_false("publish" %in% zenodo_actions_allowed)
  for (script in c("util-zenodo.R", "06-zenodo-edition.R")) {
    src <- readLines(etl_zenodo_source(script), encoding = "UTF-8")
    expect_false(
      any(grepl("actions/publish", src, fixed = TRUE)),
      info = script
    )
    expect_false(any(grepl("\"publish\"", src, fixed = TRUE)), info = script)
  }
})

test_that("the client targets the sandbox or production and needs a token", {
  load_etl_zenodo()
  expect_identical(zenodo_base_url("sandbox"), "https://sandbox.zenodo.org")
  expect_identical(zenodo_base_url("production"), "https://zenodo.org")
  expect_error(zenodo_client("", "sandbox"), "no Zenodo token for the sandbox")
  expect_identical(zenodo_client("t", "production")$base, "https://zenodo.org")
})

test_that("the versions of a record split into latest published and draft", {
  load_etl_zenodo()
  versions <- list(
    list(id = 10, submitted = TRUE),
    list(id = 12, submitted = TRUE),
    list(id = 15, submitted = FALSE)
  )
  split <- zenodo_split_versions(versions)
  expect_identical(split$published$id, 12)
  expect_identical(split$draft$id, 15)
  expect_null(zenodo_split_versions(list())$published)
  expect_null(zenodo_split_versions(versions[1:2])$draft)
})

test_that("the files of a draft are deleted, uploaded or kept by md5", {
  load_etl_zenodo()
  remote <- data.frame(
    name = c("companhias-cad.tar", "companhias-dfp.tar", "old.csv"),
    id = c("f1", "f2", "f3"),
    md5 = c("same", "stale", "gone"),
    stringsAsFactors = FALSE
  )
  local <- data.frame(
    name = c("companhias-cad.tar", "companhias-dfp.tar", "README.md"),
    md5 = c("same", "fresh", "new"),
    stringsAsFactors = FALSE
  )
  actions <- zenodo_file_actions(remote, local)
  expect_identical(actions$keep, "companhias-cad.tar")
  expect_identical(actions$delete, c("f2", "f3"))
  expect_identical(actions$upload, c("companhias-dfp.tar", "README.md"))
  # an empty draft uploads everything
  empty <- zenodo_files_table(NULL)
  expect_identical(nrow(empty), 0L)
  expect_identical(zenodo_file_actions(empty, local)$upload, local$name)
})

test_that("the first edition opens a new deposition and a failure deletes it", {
  load_etl_zenodo()
  client <- zenodo_client("token", "sandbox")
  seen <- list()
  handler <- function(req) {
    seen[[length(seen) + 1L]] <<- list(
      method = req$method %||% "GET",
      url = req$url,
      body = req$body$data
    )
    if (
      identical(req$method, "POST") &&
        grepl("/api/deposit/depositions$", req$url)
    ) {
      return(httr2::response_json(
        status_code = 201L,
        body = list(
          id = 77,
          conceptrecid = 76,
          links = list(bucket = "https://sandbox.zenodo.org/api/files/b")
        )
      ))
    }
    if (identical(req$method, "DELETE")) {
      return(httr2::response(status_code = 204L))
    }
    httr2::response_json(status_code = 200L, body = list())
  }
  metadata <- edition_metadata(
    "2026-10-06",
    list(cad = "2026-10-06"),
    "0.2",
    "<p>x</p>"
  )
  httr2::with_mocked_responses(handler, {
    draft <- zenodo_open_draft(client, NULL, metadata)
    expect_identical(draft$id, 77L)
    expect_true(attr(draft, "created"))
    expect_identical(zenodo_drop_draft(client, draft), "deleted")
  })
  expect_identical(seen[[1L]]$method, "POST")
  # the body is a JSON object with the metadata, never `[]` (the
  # sandbox answered 500 to an empty array on 2026-11-07)
  body <- as.character(jsonlite::toJSON(seen[[1L]]$body, auto_unbox = TRUE))
  expect_match(body, '^{"metadata":{"upload_type":"dataset"', fixed = TRUE)
  empty <- jsonlite::toJSON(structure(list(), names = character()))
  expect_identical(as.character(empty), "{}")
  expect_identical(seen[[2L]]$method, "DELETE")
  expect_match(seen[[2L]]$url, "/api/deposit/depositions/77$")
})

test_that("a later edition is a new version of the latest published one", {
  load_etl_zenodo()
  client <- zenodo_client("token", "sandbox")
  calls <- character()
  handler <- function(req) {
    calls <<- c(
      calls,
      paste(
        req$method %||% "GET",
        sub("^https://sandbox.zenodo.org", "", req$url)
      )
    )
    url <- req$url
    if (grepl("conceptrecid:76", url, fixed = TRUE)) {
      return(httr2::response_json(
        status_code = 200L,
        body = list(
          list(id = 10, submitted = TRUE),
          list(id = 12, submitted = TRUE)
        )
      ))
    }
    if (grepl("/actions/newversion$", url)) {
      return(httr2::response_json(status_code = 201L, body = list(id = 12)))
    }
    if (grepl("/api/deposit/depositions/12$", url)) {
      return(httr2::response_json(
        status_code = 200L,
        body = list(
          id = 12,
          links = list(
            latest_draft = paste0(
              zenodo_base_url("sandbox"),
              "/api/deposit/depositions/20"
            )
          )
        )
      ))
    }
    if (grepl("/api/deposit/depositions/20$", url)) {
      return(httr2::response_json(
        status_code = 200L,
        body = list(id = 20, submitted = FALSE, files = list())
      ))
    }
    httr2::response_json(
      status_code = 404L,
      body = list(message = "unexpected")
    )
  }
  httr2::with_mocked_responses(handler, {
    draft <- zenodo_open_draft(client, "76")
    expect_identical(draft$id, 20L)
    expect_false(attr(draft, "created"))
  })
  expect_identical(
    calls,
    c(
      paste0(
        "GET /api/deposit/depositions?q=conceptrecid:76",
        "&all_versions=true&size=100"
      ),
      "POST /api/deposit/depositions/12/actions/newversion",
      "GET /api/deposit/depositions/12",
      "GET /api/deposit/depositions/20"
    )
  )
})

test_that("a draft already open is reused instead of opening another", {
  load_etl_zenodo()
  client <- zenodo_client("token", "sandbox")
  handler <- function(req) {
    if (grepl("conceptrecid:76", req$url, fixed = TRUE)) {
      return(httr2::response_json(
        status_code = 200L,
        body = list(
          list(id = 12, submitted = TRUE),
          list(id = 20, submitted = FALSE)
        )
      ))
    }
    if (grepl("/api/deposit/depositions/20$", req$url)) {
      return(httr2::response_json(status_code = 200L, body = list(id = 20)))
    }
    stop("unexpected request: ", req$url)
  }
  httr2::with_mocked_responses(handler, {
    expect_identical(zenodo_open_draft(client, "76")$id, 20L)
  })
})

test_that("an API error names the status and the message", {
  load_etl_zenodo()
  client <- zenodo_client("token", "sandbox")
  handler <- function(req) {
    httr2::response_json(
      status_code = 403L,
      body = list(message = "scope missing")
    )
  }
  httr2::with_mocked_responses(handler, {
    expect_error(
      zenodo_action(client, 12L, "newversion"),
      "Zenodo answered 403 to POST .*newversion.*scope missing"
    )
  })
})

test_that("the read-back reports a file missing from the draft and an extra", {
  load_etl_zenodo()
  client <- zenodo_client("token", "sandbox")
  handler <- function(req) {
    httr2::response_json(
      status_code = 200L,
      body = list(
        id = 20,
        files = list(list(
          filename = "stray.csv",
          id = "f9",
          checksum = "md5:x",
          links = list(download = "https://sandbox.zenodo.org/f9")
        ))
      )
    )
  }
  local <- data.frame(
    name = "README.md",
    sha256 = "s",
    stringsAsFactors = FALSE
  )
  httr2::with_mocked_responses(handler, {
    back <- zenodo_read_back(client, 20L, local, withr::local_tempdir())
  })
  expect_identical(back$name, c("README.md", "stray.csv"))
  expect_identical(back$status, c("missing", "extra"))
})

# --- the entry point ---------------------------------------------------

test_that("the arguments of stage 06 are parsed and checked", {
  load_etl_zenodo()
  opts <- edition_parse_args(c(
    "--target",
    "production",
    "--edition",
    "2026-10-06",
    "--datasets",
    "cad, vlmo",
    "--grace",
    "0",
    "--concept",
    "76",
    "--allow-shrink",
    "--dry-run"
  ))
  expect_identical(opts$target, "production")
  expect_identical(opts$edition, "2026-10-06")
  expect_identical(opts$datasets, c("cad", "vlmo"))
  expect_identical(opts$grace, 0L)
  expect_identical(opts$concept, "76")
  expect_true(opts$allow_shrink)
  expect_true(opts$dry_run)
  defaults <- edition_parse_args(character())
  expect_identical(defaults$target, "sandbox")
  expect_identical(defaults$grace, 14L)
  expect_null(defaults$datasets)
  expect_error(
    edition_parse_args(c("--target", "live")),
    "sandbox or production"
  )
  expect_error(edition_parse_args(c("--edition", "2026-10-6")), "complete date")
})

test_that("the token and the concept come from the environment of the target", {
  load_etl_zenodo()
  withr::local_envvar(
    ZENODO_SANDBOX_TOKEN = "sb",
    ZENODO_TOKEN = "",
    ZENODO_SANDBOX_CONCEPT = "76",
    ZENODO_CONCEPT = ""
  )
  expect_identical(edition_token("sandbox"), "sb")
  expect_error(edition_token("production"), "ZENODO_TOKEN is not set")
  expect_identical(edition_concept("sandbox"), "76")
  expect_null(edition_concept("production"))
  expect_identical(edition_concept("production", "99"), "99")
})

test_that("the report says what failed and what the owner does next", {
  load_etl_zenodo()
  comparison <- data.frame(
    dataset = "dfp",
    kind = "partition",
    table = "bpa",
    rows_prev = 10,
    rows_now = 8,
    stringsAsFactors = FALSE
  )
  failures <- edition_count_failures(comparison)
  report <- edition_report(
    edition = "2026-10-06",
    target = "sandbox",
    snapshots = list(dfp = "2026-10-06"),
    digests_failed = edition_verify_digests(data.frame(
      kind = character(),
      dataset = character(),
      rel = character(),
      sha256 = character(),
      sha256_actual = character()
    )),
    comparison = comparison,
    count_failures = failures,
    previous = NULL,
    files = data.frame(name = "a.tar", size = 1, sha256 = "s"),
    outcome = "FAILED before the deposit"
  )
  expect_identical(report[[1L]], "# cvmdata edition 2026-10-06 — sandbox")
  expect_true(any(grepl("1 table(s) FAILED", report, fixed = TRUE)))
  expect_true(any(grepl("Nothing to publish", report, fixed = TRUE)))
  ready <- edition_report(
    "2026-10-06",
    "sandbox",
    list(dfp = "2026-10-06"),
    digests_failed = data.frame(),
    comparison = comparison[0, ],
    count_failures = failures[0, ],
    previous = NULL,
    files = data.frame(name = "a.tar", size = 1, sha256 = "s"),
    draft = list(
      id = 20,
      links = list(html = "https://sandbox.zenodo.org/deposit/20")
    ),
    read_back = data.frame(name = "a.tar", status = "ok"),
    outcome = "ready"
  )
  expect_true(any(grepl("press *Publish*", ready, fixed = TRUE)))
  expect_true(any(grepl(
    "https://sandbox.zenodo.org/deposit/20",
    ready,
    fixed = TRUE
  )))
})
