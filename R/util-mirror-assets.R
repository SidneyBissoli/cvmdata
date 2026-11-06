# Helpers for the parquet mirror published on GitHub Releases.
#
# The mirror layout is produced by `inst/etl/03-publish.R`: every release
# `mirror-<dataset>-latest` carries one parquet asset per (table, year,
# report_type) tuple, plus a `__source_hash.json` asset used for
# change detection. Asset names encode the Hive-style partition path
# the ETL writes locally — for example,
#   parquet/dfp/bpa/report_type=ind/year=2024/part-0.parquet
# becomes
#   bpa__report_type=ind__year=2024__part-0.parquet
# at upload time, which GitHub Releases then sanitises by replacing
# `=` with `.` in the public asset URL:
#   bpa__report_type.ind__year.2024__part-0.parquet
#
# Both encodings need to round-trip through the parser below. The
# parser is pure (no I/O); the inventory helper hits the GitHub REST
# API and caches the result for the duration of the R session.
#
# Since the filing history shipped (Parte 3 of the versions work,
# 2026-10), a partition of a table that keeps the current filing may
# carry a second asset next to its `part-N`:
#   dre__report_type.con__year.2023__history.parquet
# with the rows of the superseded filings. The parser tags every asset
# with a `kind` ("current" or "history"); `filter_mirror_assets()`
# keeps only the current ones unless asked otherwise, so the readers
# of the current table never see the history.

#
# Since 2026-10-25 every publish also writes a dated release
# `mirror-<group>-<dataset>-snapshot-<YYYY-MM-DD>` (inst/etl/
# util-snapshot.R) with the partitions that changed and the complete
# sidecar, whose `releases` map says which snapshot holds the bytes of
# each partition, `snapshots` lists every date published and `files`
# carries the sha256 and size of every parquet. When the option
# `cvmdata.mirror_release` names a date, the inventory is built from the
# sidecar of the snapshot on or before it instead of the API listing of
# `-latest`, with one download URL per partition pointing into the
# snapshot that holds it; the history assets still come from `-latest`.

# Repo coordinates. Single source of truth on the consumer side; the
# producer side (inst/etl/00-config.R) carries the same constant.
.mirror_repo <- "SidneyBissoli/cvmdata"

# Session-scoped cache for asset listings. Keyed by (group, dataset,
# release). The tests reset it through a helper of their own
# (tests/testthat/helper-cvm-cache.R).
.mirror_assets_cache <- new.env(parent = emptyenv())

# Tag of the moving "latest" release for a (group, dataset) pair
# (mirrors `mirror_tag_latest()` from inst/etl/00-config.R). The
# `<group>` segment was introduced in Sessao 08 of v0.1.0.9000; pre-
# Sessao 08 releases (named `mirror-<dataset>-latest` without a group)
# are not addressable by this consumer -- they must be renamed in
# place on the producer side (see
# `data-raw/decisions/cvmdata_arquitetura_grupos_decisao_v2.md` §4.3).
mirror_release_tag <- function(group, dataset) {
  sprintf("mirror-%s-%s-latest", group, dataset)
}

# Tag of the dated snapshot release of a (group, dataset) pair (mirrors
# `mirror_tag_snapshot()` from inst/etl/00-config.R). `date` is the
# "YYYY-MM-DD" string the sidecar carries.
mirror_snapshot_tag <- function(group, dataset, date) {
  sprintf("mirror-%s-%s-snapshot-%s", group, dataset, date)
}

# Public download URL of a release asset: the stable pattern GitHub uses
# for `browser_download_url`, so a pinned read needs no API call per
# snapshot.
mirror_download_url <- function(tag, name, repo = .mirror_repo) {
  sprintf("https://github.com/%s/releases/download/%s/%s", repo, tag, name)
}

# Composite cache key for the `.mirror_assets_cache` env. We encode
# `(group, dataset, release)` as a single string so the env stays usable
# as a bare hash without switching to a 3-D structure. The `::`
# separator is not a valid character in CKAN slugs (and dataset ids), so
# the round-trip is unambiguous.
.mirror_cache_key <- function(group, dataset, release = "latest") {
  sprintf("%s::%s::%s", group, dataset, release)
}

# Tag of the release the current session reads for (group, dataset), as
# the inventory resolved it: the snapshot tag under a pinned date (or
# under "latest" when the sidecar names its snapshot), else the `-latest`
# tag. NA when the inventory has not been fetched in this session, which
# `cvm_attach_metadata()` turns into an unknown release.
mirror_resolved_release <- function(
  group,
  dataset,
  release = cvm_release_get()
) {
  inventory <- .mirror_assets_cache[[.mirror_cache_key(
    group,
    dataset,
    release
  )]]
  if (is.null(inventory)) {
    return(NA_character_)
  }
  attr(inventory, "release_tag") %||% NA_character_
}

# Inventory of the mirror for (group, dataset) under `release` (the value
# of `cvm_release_get()`: "latest" or a "YYYY-MM-DD" date). Returns a
# tibble with one row per asset:
#   name        : asset filename (post-sanitisation; `=` -> `.`)
#   url         : download URL (resolves without auth)
#   size_bytes  : asset size in bytes (integer; NA when unknown)
#   sha256      : SHA-256 of the file bytes from the sidecar's `files`
#                 map (NA for history assets and for sidecars written
#                 before the map existed)
# plus attributes: `source_hash` (the `hash` of the sidecar, or
# `NA_character_` when the release has none), `skips` (the ETL's skip
# manifest), `release_tag` (the release the rows describe), `snapshot`
# (its "YYYY-MM-DD" date, or NA), `snapshots` (every date published) and
# `pinned` (TRUE under a date). The result is cached per session so a
# single fetch lists at most once per (group, dataset, release).
#
# Under "latest" the rows come from the GitHub REST API listing of
# `mirror-<group>-<dataset>-latest`. Under a date the rows of the current
# partitions come from the sidecar of the snapshot on or before it (one
# URL per partition, into the snapshot that holds its bytes) and the
# history rows from the `-latest` listing, which is where the ETL keeps
# them.
#
# Anonymous API access is enough for public repos (rate limit
# 60 req/h, and the per-(group, dataset) call hits it once per
# session). When `GITHUB_TOKEN` or `GITHUB_PAT` is set, the call
# attaches a Bearer header to bump the limit to 5000 req/h -- useful
# for CI runners.
mirror_list_assets <- function(
  group,
  dataset,
  repo = .mirror_repo,
  refresh = FALSE,
  release = cvm_release_get()
) {
  key <- .mirror_cache_key(group, dataset, release)
  cached <- mirror_cached_inventory(key, refresh)
  if (!is.null(cached)) {
    return(cached)
  }
  latest <- mirror_list_latest(group, dataset, repo, refresh)
  parsed <- if (identical(release, "latest")) {
    mirror_warn_sidecar_unread(latest, dataset)
    latest
  } else {
    mirror_list_snapshot(latest, group, dataset, release, repo)
  }
  .mirror_assets_cache[[key]] <- parsed
  parsed
}

# Seconds an inventory whose sidecar could not be read stays in the
# session cache. After that the next call fetches the inventory again,
# so a release that was unreadable for a moment does not leave the whole
# session without digests; meanwhile no call repeats the listing (the
# anonymous GitHub API allows 60 an hour).
.mirror_sidecar_retry_secs <- 300

# The cached inventory under `key`, or NULL when there is none, when
# `refresh` asks for a new one, or when its sidecar could not be read
# and the wait above is over.
mirror_cached_inventory <- function(key, refresh = FALSE) {
  if (isTRUE(refresh)) {
    return(NULL)
  }
  cached <- .mirror_assets_cache[[key]]
  tried <- attr(cached, "sidecar_tried_at")
  if (
    !is.null(tried) &&
      as.numeric(difftime(Sys.time(), tried, units = "secs")) >
        .mirror_sidecar_retry_secs
  ) {
    return(NULL)
  }
  cached
}

# Warns, once per fetch of the inventory, that the release publishes a
# sidecar the package could not read, and what the session goes without
# (decision of 2026-11-05: a warning, never silence).
mirror_warn_sidecar_unread <- function(inventory, dataset) {
  reason <- attr(inventory, "sidecar_unread")
  if (is.null(reason)) {
    return(invisible())
  }
  tag <- attr(inventory, "release_tag")
  minutes <- .mirror_sidecar_retry_secs / 60
  cvmdata_warn(
    c(
      paste(
        "Could not read the index ({.file __source_hash.json}) of the",
        "mirror release {.val {tag}}."
      ),
      "x" = "{reason}",
      "!" = paste(
        "Until it is read, cached files of {.val {dataset}} are served",
        "without checking that the release still holds them, downloads",
        "are not verified against the published digests, and a missing",
        "year or table comes without its reason."
      ),
      if (isTRUE(attr(inventory, "sidecar_transient"))) {
        http_retry_hint(503L)
      },
      "i" = paste(
        "The first call after {minutes} minutes asks for the index",
        "again."
      )
    ),
    class = "cvmdata_warn_sidecar_unread"
  )
  invisible()
}

# The inventory of a dated snapshot. `latest` is the `-latest` inventory:
# its `snapshots` attribute says which dates exist, and its rows supply
# the history assets. When the snapshot resolved is the one `-latest`
# currently carries, its rows are reused as they are (same bytes, no
# second download of the sidecar).
mirror_list_snapshot <- function(latest, group, dataset, release, repo) {
  reason <- attr(latest, "sidecar_unread")
  if (!is.null(reason)) {
    # the dates that can be pinned are listed in that sidecar: without
    # it the mirror would look as if it had no snapshot at all
    latest_tag <- attr(latest, "release_tag")
    cvmdata_abort(
      c(
        paste(
          "Could not read the index ({.file __source_hash.json}) of the",
          "mirror release {.val {latest_tag}}, which lists the dated",
          "snapshots."
        ),
        "x" = "{reason}",
        if (isTRUE(attr(latest, "sidecar_transient"))) http_retry_hint(503L)
      ),
      class = "cvmdata_error_http"
    )
  }
  date <- mirror_pick_snapshot(attr(latest, "snapshots"), release, dataset)
  tag <- mirror_snapshot_tag(group, dataset, date)
  if (identical(date, attr(latest, "snapshot"))) {
    out <- latest
  } else {
    manifest_url <- mirror_download_url(tag, "__source_hash.json", repo)
    sidecar <- mirror_read_sidecar(manifest_url)
    if (is.na(sidecar$hash)) {
      reason <- sidecar$unread %||% "the manifest carries no content hash"
      cvmdata_abort(
        c(
          "Could not read the manifest of mirror snapshot {.val {tag}}.",
          "x" = "{reason}",
          "i" = "Expected {.url {manifest_url}}.",
          if (isTRUE(sidecar$transient)) http_retry_hint(503L)
        ),
        class = "cvmdata_error_http"
      )
    }
    current <- mirror_inventory_from_manifest(sidecar, repo, tag)
    history <- latest[mirror_is_history_name(latest$name), , drop = FALSE]
    out <- vctrs::vec_rbind(current, history)
    attr(out, "source_hash") <- sidecar$hash
    attr(out, "skips") <- sidecar$skips
    attr(out, "snapshots") <- attr(latest, "snapshots")
  }
  attr(out, "release_tag") <- tag
  attr(out, "snapshot") <- date
  attr(out, "pinned") <- TRUE
  out
}

# The most recent snapshot date on or before `release`, from the dates
# the sidecar lists. A date before the first snapshot, or a mirror
# without snapshots yet, is a `cvmdata_error_input` that says what
# exists.
mirror_pick_snapshot <- function(dates, release, dataset) {
  dates <- sort(unique(as.character(dates)))
  dates <- dates[!is.na(dates) & nzchar(dates)]
  if (!length(dates)) {
    cvmdata_abort(
      c(
        "The mirror of {.val {dataset}} has no dated snapshots yet.",
        "i" = paste(
          "Snapshots exist from the first ETL run after 2026-10-25;",
          "use {.code cvm_release_set(\"latest\")} meanwhile."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  eligible <- dates[dates <= release]
  if (!length(eligible)) {
    cvmdata_abort(
      c(
        paste(
          "No mirror snapshot of {.val {dataset}} on or before",
          "{.val {release}}."
        ),
        "i" = "The earliest snapshot is {.val {dates[[1L]]}}."
      ),
      class = "cvmdata_error_input"
    )
  }
  max(eligible)
}

# Rows of the current partitions of a snapshot, from its sidecar: one per
# entry of `data`, with the URL into the release `releases` names for it.
# A partition without a pointer means a sidecar this client does not
# understand.
mirror_inventory_from_manifest <- function(sidecar, repo, tag) {
  rels <- names(sidecar$data)
  if (!length(rels)) {
    return(mirror_assets_to_tibble(list()))
  }
  names <- mirror_public_asset_name(rels)
  holders <- vapply(
    rels,
    function(rel) {
      holder <- sidecar$releases[[rel]]
      if (is.null(holder) || !nzchar(holder)) {
        cvmdata_abort(
          c(
            paste(
              "The manifest of {.val {tag}} does not say which release",
              "holds partition {.val {rel}}."
            ),
            "i" = "Update cvmdata, or read {.code cvm_release_set(\"latest\")}."
          ),
          class = "cvmdata_error_parse"
        )
      }
      holder
    },
    character(1L)
  )
  digests <- mirror_file_digests(sidecar$files, rels)
  tibble::tibble(
    name = names,
    url = mirror_download_url(unname(holders), names, repo),
    size_bytes = digests$size,
    sha256 = digests$sha256
  )
}

# Asset name GitHub serves for a partition path: `/` -> `__`, `=` -> `.`.
mirror_public_asset_name <- function(rel) {
  gsub("=", ".", gsub("/", "__", rel, fixed = TRUE), fixed = TRUE)
}

# Whether an inventory row is a history asset.
mirror_is_history_name <- function(name) {
  grepl("__history\\.parquet$", name)
}

# size and sha256 of each partition path from the sidecar's `files` map
# (NA where the map has no entry or does not exist).
mirror_file_digests <- function(files, rels) {
  one <- function(rel, field) {
    entry <- files[[rel]]
    if (is.null(entry)) {
      return(NA)
    }
    entry[[field]] %||% NA
  }
  list(
    size = vapply(
      rels,
      function(r) as.integer(one(r, "size")),
      integer(1L),
      USE.NAMES = FALSE
    ),
    sha256 = vapply(
      rels,
      function(r) as.character(one(r, "sha256")),
      character(1L),
      USE.NAMES = FALSE
    )
  )
}

# The `-latest` inventory via the GitHub REST API (see
# `mirror_list_assets()` for the columns and attributes).
mirror_list_latest <- function(group, dataset, repo, refresh = FALSE) {
  key <- .mirror_cache_key(group, dataset, "latest")
  cached <- mirror_cached_inventory(key, refresh)
  if (!is.null(cached)) {
    return(cached)
  }
  tag <- mirror_release_tag(group, dataset)
  url <- sprintf("https://api.github.com/repos/%s/releases/tags/%s", repo, tag)
  req <- httr2::request(url) |>
    httr2::req_headers(
      Accept = "application/vnd.github+json",
      `X-GitHub-Api-Version` = "2022-11-28"
    ) |>
    httr2::req_user_agent("cvmdata") |>
    httr2::req_error(is_error = function(resp) FALSE)
  token <- mirror_github_token()
  if (nzchar(token)) {
    req <- httr2::req_headers(req, Authorization = paste("Bearer", token))
  }
  resp <- tryCatch(
    httr2::req_perform(req_retry_transient(req)),
    error = function(e) {
      cvmdata_abort(
        c(
          "HTTP GET failed for {.url {url}}.",
          "x" = "{conditionMessage(e)}",
          http_retry_hint(e)
        ),
        class = "cvmdata_error_http"
      )
    }
  )
  status <- httr2::resp_status(resp)
  if (status >= 400L) {
    # a 5xx or a 429 that outlasted the retries says nothing about the
    # tag; only the other statuses point at a release that is not there
    hint <- http_retry_hint(status) %||%
      c(
        "i" = paste(
          "Release tag {.val {tag}} may not exist yet; check",
          "{.url https://github.com/{repo}/releases}."
        )
      )
    cvmdata_abort(
      c("GitHub API returned HTTP {status} for {.url {url}}.", hint),
      class = "cvmdata_error_http"
    )
  }
  body <- tryCatch(
    httr2::resp_body_json(resp, simplifyVector = FALSE),
    error = function(e) {
      cvmdata_abort(
        c(
          "Failed to parse GitHub API response for {.url {url}}.",
          "x" = "{conditionMessage(e)}"
        ),
        class = "cvmdata_error_parse"
      )
    }
  )
  assets <- body$assets %||% list()
  sidecar <- mirror_fetch_sidecar(assets)
  parsed <- mirror_assets_to_tibble(assets, sidecar$files)
  attr(parsed, "source_hash") <- sidecar$hash
  attr(parsed, "skips") <- sidecar$skips
  attr(parsed, "release_tag") <- if (is.na(sidecar$snapshot)) {
    tag
  } else {
    mirror_snapshot_tag(group, dataset, sidecar$snapshot)
  }
  attr(parsed, "snapshot") <- sidecar$snapshot
  attr(parsed, "snapshots") <- sidecar$snapshots
  attr(parsed, "pinned") <- FALSE
  # set only when the release publishes a sidecar that could not be read
  # (`mirror_read_sidecar()`); absent on a read sidecar or none at all
  attr(parsed, "sidecar_unread") <- sidecar$unread
  attr(parsed, "sidecar_transient") <- sidecar$transient
  attr(parsed, "sidecar_tried_at") <- if (!is.null(sidecar$unread)) Sys.time()
  .mirror_assets_cache[[key]] <- parsed
  parsed
}

# Resolve a token from the standard env vars used by `gh` and `usethis`.
# Returns "" when none is set so the caller can short-circuit.
mirror_github_token <- function() {
  for (var in c("GITHUB_TOKEN", "GITHUB_PAT")) {
    val <- Sys.getenv(var, "")
    if (nzchar(val)) {
      return(val)
    }
  }
  ""
}

# Convert the raw `assets` list from the GitHub API into a tidy tibble.
# `files` is the sidecar's `files` map (partition path -> sha256, size),
# matched to the assets by their public name; NULL when the sidecar has
# none.
mirror_assets_to_tibble <- function(assets, files = NULL) {
  if (!length(assets)) {
    return(tibble::tibble(
      name = character(0L),
      url = character(0L),
      size_bytes = integer(0L),
      sha256 = character(0L)
    ))
  }
  name <- vapply(assets, function(a) a$name %||% NA_character_, character(1L))
  sha <- rep(NA_character_, length(name))
  if (length(files)) {
    public <- mirror_public_asset_name(names(files))
    digests <- mirror_file_digests(files, names(files))
    hit <- match(name, public)
    sha[!is.na(hit)] <- digests$sha256[hit[!is.na(hit)]]
  }
  tibble::tibble(
    name = name,
    url = vapply(
      assets,
      function(a) a$browser_download_url %||% NA_character_,
      character(1L)
    ),
    size_bytes = vapply(
      assets,
      function(a) as.integer(a$size %||% NA_integer_),
      integer(1L)
    ),
    sha256 = sha
  )
}

# Read the `__source_hash.json` sidecar of the release: the SHA-256 of
# the mirror's content (`hash`); since 2026-10-25 the ETL's skip
# manifest (`skips`: one row per (table, year, report_type) the ETL
# produced no parquet for, with `reason` "empty" — the CVM publishes the
# CSV with the header only — or "absent" — the CSV is not in the yearly
# ZIP); and, with the dated snapshots, `snapshot` (the "YYYY-MM-DD" of
# the snapshot whose content this is), `snapshots` (every date
# published), `releases` (partition path -> tag of the snapshot holding
# its bytes) and `files` (partition path -> sha256, size). The asset is
# fetched only when present (one extra GET on first call). `hash` is
# NA_character_ and the other fields NULL / NA when the release has no
# sidecar, when it cannot be read, or when it predates the field.
mirror_fetch_sidecar <- function(assets) {
  hit <- NULL
  for (a in assets) {
    if (identical(a$name, "__source_hash.json")) {
      hit <- a
      break
    }
  }
  if (is.null(hit)) {
    return(mirror_empty_sidecar())
  }
  url <- hit$browser_download_url %||% ""
  if (!nzchar(url)) {
    return(mirror_empty_sidecar())
  }
  mirror_read_sidecar(url)
}

mirror_empty_sidecar <- function() {
  list(
    hash = NA_character_,
    skips = NULL,
    snapshot = NA_character_,
    snapshots = character(0L),
    releases = NULL,
    files = NULL,
    data = NULL
  )
}

# Download and normalise a sidecar from its URL (see
# `mirror_fetch_sidecar()` for the fields).
#
# A sidecar that is published but could not be read comes back empty
# WITH the reason in `unread` (and `transient`: whether the retry policy
# was exhausted on a failure of the server or of the connection). Until
# 2026-11-05 the request ran once and any failure was swallowed into an
# empty sidecar, which reads exactly like a release that has none: no
# digest check, no eviction of stale cached copies, no reason for a
# missing partition, and under a pinned date "no dated snapshots yet".
# The callers now say so: `mirror_list_assets()` warns,
# `mirror_list_snapshot()` aborts.
mirror_read_sidecar <- function(url) {
  none <- mirror_empty_sidecar()
  unread <- function(reason, transient = FALSE) {
    none$unread <- reason
    none$transient <- transient
    none
  }
  resp <- tryCatch(
    httr2::request(url) |>
      httr2::req_user_agent("cvmdata") |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      req_retry_transient() |>
      httr2::req_perform(),
    error = function(e) e
  )
  if (inherits(resp, "condition")) {
    return(unread(conditionMessage(resp), http_failed_transiently(resp)))
  }
  status <- httr2::resp_status(resp)
  if (status >= 400L) {
    return(unread(paste("HTTP", status), http_failed_transiently(status)))
  }
  # GitHub serves release assets as `application/octet-stream`, and
  # httr2 refuses to parse JSON under that type unless told otherwise.
  # Until 2026-10-25 this call ran with the default check, the error was
  # swallowed into `hash = NA`, and no client ever read the sidecar in
  # production: the L3 eviction by hash and the skip manifest never
  # worked outside the tests, whose mock answered `application/json`.
  body <- tryCatch(
    httr2::resp_body_json(resp, simplifyVector = TRUE, check_type = FALSE),
    error = function(e) NULL
  )
  if (is.null(body)) {
    return(unread("the file is not valid JSON"))
  }
  snapshot <- body$snapshot %||% NA_character_
  list(
    hash = body$hash %||% NA_character_,
    skips = mirror_normalise_skips(body$skips),
    snapshot = if (is.character(snapshot) && length(snapshot) == 1L) {
      snapshot
    } else {
      NA_character_
    },
    # jsonlite writes a single date as a scalar; `unlist()` covers both.
    snapshots = as.character(unlist(body$snapshots %||% list())),
    releases = if (is.list(body$releases)) body$releases else NULL,
    files = if (is.list(body$files)) body$files else NULL,
    data = if (is.list(body$data)) body$data else NULL
  )
}

# The skip manifest as a data frame with exactly the four columns the
# ETL writes, or NULL when the sidecar carries none (older release,
# empty array, or an unexpected shape). `year` and `report_type` are NA
# for tables without yearly partitions or ind/con variants.
mirror_normalise_skips <- function(x) {
  needed <- c("table", "year", "report_type", "reason")
  if (!is.data.frame(x) || !nrow(x) || !all(needed %in% names(x))) {
    return(NULL)
  }
  data.frame(
    table = as.character(x$table),
    year = suppressWarnings(as.integer(x$year)),
    report_type = as.character(x$report_type),
    reason = as.character(x$reason),
    stringsAsFactors = FALSE
  )
}

# cli bullets explaining, from the release's skip manifest, why the
# mirror has no partition for `table` in `years` (and `report_type`,
# when the table has variants). One bullet per recorded year, in the
# ETL's own words; character(0) when the manifest has nothing to say,
# so callers can splice the result into a message unconditionally.
mirror_skip_bullets <- function(inventory, table, years, report_type) {
  skips <- attr(inventory, "skips")
  if (is.null(skips)) {
    return(character(0L))
  }
  rows <- skips[skips$table == table, , drop = FALSE]
  if (!is.null(years)) {
    rows <- rows[
      !is.na(rows$year) & rows$year %in% as.integer(years),
      ,
      drop = FALSE
    ]
  }
  if (!is.null(report_type)) {
    rows <- rows[
      is.na(rows$report_type) | rows$report_type %in% report_type,
      ,
      drop = FALSE
    ]
  }
  if (!nrow(rows)) {
    return(character(0L))
  }
  rows <- rows[order(rows$year, rows$report_type), , drop = FALSE]
  text <- vapply(
    seq_len(nrow(rows)),
    function(i) {
      what <- switch(
        rows$reason[i],
        empty = "the CVM publishes the CSV with the header only",
        absent = "the CSV is not in the CVM's yearly ZIP",
        sprintf("recorded by the mirror ETL as %s", rows$reason[i])
      )
      variant <- if (is.na(rows$report_type[i])) {
        ""
      } else {
        sprintf(" (%s)", rows$report_type[i])
      }
      sprintf(
        "%s%s: %s (recorded by the mirror ETL as \"%s\").",
        if (is.na(rows$year[i])) table else rows$year[i],
        variant,
        what,
        rows$reason[i]
      )
    },
    character(1L)
  )
  stats::setNames(text, rep("i", length(text)))
}

# Pure parser: decode an asset filename into a (table, report_type,
# year, kind) tuple. Handles both raw (`=`) and GitHub-sanitised (`.`)
# separators in the key/value segments. `kind` is "current" for a
# `part-N.parquet` asset and "history" for a `history.parquet` one.
# Returns `NULL` when the asset is the `__source_hash.json` sidecar
# (not a data asset). Aborts with `cvmdata_error_parse` for malformed
# names.
parse_mirror_asset_name <- function(name) {
  if (identical(name, "__source_hash.json")) {
    return(NULL)
  }
  if (!grepl("\\.parquet$", name)) {
    cvmdata_abort(
      c(
        "Asset {.val {name}} is not a parquet file.",
        "i" = paste(
          "The mirror inventory should contain only `*.parquet`",
          "data assets and the `__source_hash.json` sidecar."
        )
      ),
      class = "cvmdata_error_parse"
    )
  }
  parts <- strsplit(name, "__", fixed = TRUE)[[1L]]
  if (length(parts) < 2L) {
    cvmdata_abort(
      c(
        "Asset name {.val {name}} does not encode a partition path.",
        "i" = paste(
          "Expected {.code <table>(__<key>=<value>)*__part-N.parquet}."
        )
      ),
      class = "cvmdata_error_parse"
    )
  }
  table <- parts[[1L]]
  last <- parts[[length(parts)]]
  kind <- if (grepl("^part-[0-9]+\\.parquet$", last)) {
    "current"
  } else if (identical(last, "history.parquet")) {
    "history"
  } else {
    cvmdata_abort(
      c(
        paste(
          "Asset name {.val {name}} does not end in",
          "{.code part-N.parquet} or {.code history.parquet}."
        )
      ),
      class = "cvmdata_error_parse"
    )
  }
  partition_segments <- if (length(parts) > 2L) {
    parts[seq.int(2L, length(parts) - 1L)]
  } else {
    character(0L)
  }
  report_type <- NA_character_
  year <- NA_integer_
  for (seg in partition_segments) {
    kv <- parse_mirror_partition_segment(seg, name)
    if (identical(kv$key, "report_type")) {
      report_type <- kv$value
    } else if (identical(kv$key, "year")) {
      year <- suppressWarnings(as.integer(kv$value))
      if (is.na(year)) {
        cvmdata_abort(
          c(
            paste(
              "Asset {.val {name}} has non-integer year segment",
              "{.val {seg}}."
            )
          ),
          class = "cvmdata_error_parse"
        )
      }
    } else {
      cvmdata_abort(
        c(
          paste(
            "Asset {.val {name}} carries unknown partition key",
            "{.val {kv$key}}."
          ),
          "i" = paste(
            "Supported keys: {.val report_type}, {.val year}."
          )
        ),
        class = "cvmdata_error_parse"
      )
    }
  }
  list(table = table, report_type = report_type, year = year, kind = kind)
}

# Split a single `<key>(=|.)<value>` segment. Both separators are
# accepted because GitHub sanitises `=` to `.` in asset URLs.
parse_mirror_partition_segment <- function(seg, asset_name) {
  # Restrict the key alphabet so a value like `report_type.ind` does
  # not accidentally swallow the `_type` into the value when the
  # separator is `.`. Keys in the producer are `report_type` and
  # `year`; either matches `[a-z_]+`.
  m <- regmatches(seg, regexec("^([a-z_]+)[=.](.*)$", seg))[[1L]]
  if (length(m) != 3L || !nzchar(m[[3L]])) {
    cvmdata_abort(
      c(
        paste(
          "Asset {.val {asset_name}} has malformed partition segment",
          "{.val {seg}}."
        ),
        "i" = paste(
          "Expected {.code <key>=<value>} or {.code <key>.<value>}."
        )
      ),
      class = "cvmdata_error_parse"
    )
  }
  list(key = m[[2L]], value = m[[3L]])
}

# Filter an asset inventory by (table, year, report_type, kind).
# Returns a tibble subset of the input with the parsed `table`, `year`,
# `report_type` and `kind` columns attached, ready for the DuckDB
# reader.
#
# - `year = NULL` keeps every year present in the inventory.
# - `report_type = NULL` keeps every variant (no filter); for tables
#   that publish variants the caller is expected to pass either `"ind"`
#   or `"con"`, otherwise the result mixes both.
# - `kind` defaults to the current assets only; `cvm_versions()` asks
#   for `c("current", "history")`.
filter_mirror_assets <- function(
  assets,
  table,
  year = NULL,
  report_type = NULL,
  kind = "current"
) {
  if (!nrow(assets)) {
    return(annotate_mirror_assets(assets))
  }
  parsed <- lapply(assets$name, function(n) {
    tryCatch(parse_mirror_asset_name(n), cvmdata_error_parse = function(e) NULL)
  })
  keep <- !vapply(parsed, is.null, logical(1L))
  assets <- assets[keep, , drop = FALSE]
  parsed <- parsed[keep]
  tbl <- vapply(parsed, `[[`, character(1L), "table")
  rt <- vapply(parsed, `[[`, character(1L), "report_type")
  yr <- vapply(parsed, `[[`, integer(1L), "year")
  kd <- vapply(parsed, `[[`, character(1L), "kind")
  assets$table <- tbl
  assets$report_type <- rt
  assets$year <- yr
  assets$kind <- kd

  mask <- assets$table == table & assets$kind %in% kind
  if (!is.null(year)) {
    mask <- mask & assets$year %in% as.integer(year)
  }
  if (!is.null(report_type)) {
    mask <- mask & assets$report_type == report_type
  }
  assets[mask, , drop = FALSE]
}

# Annotate an empty asset inventory with the parsed columns so the
# caller can rely on the schema regardless of cardinality.
annotate_mirror_assets <- function(assets) {
  assets$table <- character(0L)
  assets$report_type <- character(0L)
  assets$year <- integer(0L)
  assets$kind <- character(0L)
  assets
}
