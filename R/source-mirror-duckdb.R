# Mirror backend (Phase F).
#
# Reads parquet snapshots from the GitHub Releases mirror produced by
# inst/etl/03-publish.R. Architecture follows Decision 1 = Alt 3
# ("hybrid") of Sessao 3.13: the asset filename carries (table, year,
# report_type) so the filter pushdown happens client-side before any
# bytes move; the matched parquets are then materialised in the L3
# cache and queried via DuckDB. The L3 cache is populated as a side
# effect of every read (Commit 4 of Sessao 3.13 adds hash-based
# invalidation on top); a future read-through-only mode can be added
# behind an option if real-world workloads show it would pay off.
#
# The partition columns (`year`, `report_type`) do NOT live inside the
# parquet body — the ETL writes Hive-style and the partition values
# live only in the path. The reader reattaches them from the parsed
# asset name (Decision 2 = Alt 1) so the resulting tibble is column-
# equivalent to the `source = "cvm"` path.

# Entry point invoked by `issuer_fetch_internal()` when source =
# "mirror". Returns a tibble (already in the shape that the CVM-HTTP
# path would return after `read_cvm_csv()` +
# `apply_schema_transformations()`), leaving `filter_by_issuer()` to
# the upstream orchestrator.
#
# - `year` mirrors the public `year` argument: NULL means "latest
#   year available in the mirror"; otherwise an integer vector.
# - `report_type` is required for tables with `cvm_file_pattern_variants`
#   and forbidden for the rest, with the same validation rules as the
#   CVM-HTTP path (enforced one level up by `issuer_fetch_internal()`).
# - `history = TRUE` (only `cvm_versions()` asks for it) also reads the
#   `history` asset of every matched partition, when one exists: the
#   rows of the superseded filings, with the five columns the current
#   asset lacks (`superseded_at`, `superseded_by_versao`,
#   `history_source`, `id_doc`, `motivo_reapresentacao`). The two are
#   read in one query, by column name, so the current rows carry those
#   columns as NA.
source_mirror_duckdb_get <- function(
  schema,
  year = NULL,
  report_type = NULL,
  history = FALSE,
  ...
) {
  cache_migrate_v0_1_to_v0_2()
  dataset <- schema$dataset
  table <- schema$table
  partitioning <- schema$temporal_partitioning %||% "none"
  has_variants <- !is.null(schema$cvm_file_pattern_variants)

  validate_mirror_args(schema, partitioning, has_variants, year, report_type)

  group <- schema$group
  inventory <- mirror_list_assets(group, dataset, release = cvm_release_get())
  pinned <- isTRUE(attr(inventory, "pinned"))
  # Under a pinned date the L3 tree is shared with the other snapshots:
  # the per-file sha256 check in `mirror_fetch_to_l3()` tells a cached
  # copy of another snapshot apart, so no eviction by dataset hash.
  if (!pinned) {
    mirror_l3_validate_hash(
      dataset,
      attr(inventory, "source_hash"),
      verified = all(
        !is.na(inventory$sha256[
          !mirror_is_history_name(inventory$name) &
            inventory$name != "__source_hash.json"
        ])
      )
    )
  }
  resolved_years <- resolve_mirror_years(
    inventory,
    table,
    year,
    report_type,
    partitioning
  )
  matches <- filter_mirror_assets(
    inventory,
    table = table,
    year = resolved_years,
    report_type = report_type,
    kind = if (isTRUE(history)) c("current", "history") else "current"
  )
  if (!nrow(matches)) {
    # The release's skip manifest, when it covers the request, says
    # exactly what the ETL found in the CVM's ZIP; the generic bullet
    # stays for years the manifest does not cover.
    recorded <- mirror_skip_bullets(
      inventory,
      table,
      resolved_years,
      report_type
    )
    cvmdata_abort(
      c(
        paste(
          "No parquet assets match {.val {dataset}}/{.val {table}}",
          "in the mirror."
        ),
        "i" = paste(
          "Searched release {.val {attr(inventory, 'release_tag')}}",
          "for {.code year = {format_years(resolved_years)}}",
          "{.code report_type = {format_chr(report_type)}}."
        ),
        recorded,
        "i" = paste(
          if (length(recorded)) "Otherwise," else "",
          "the CVM may not publish the table for that year (a table",
          "can start later or stop earlier than its dataset), or the",
          "mirror may not have it yet; {.code source = \"cvm\"} reads",
          "the portal directly."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  out <- read_mirror_assets(matches, dataset, table)
  if (isTRUE(history) && pinned) {
    out <- mirror_drop_history_after(out, attr(inventory, "snapshot"))
  }
  out
}

# Under a pinned date, the history rows superseded AFTER that date were
# still the current filing on it, and the pinned current asset already
# carries them; keeping them would list a version twice. `superseded_at`
# arrives as text from the history asset (or as a Date); rows without it
# are the current ones.
mirror_drop_history_after <- function(df, date) {
  if (is.na(date) || !"superseded_at" %in% names(df)) {
    return(df)
  }
  superseded <- as.Date(as.character(df$superseded_at), format = "%Y-%m-%d")
  keep <- is.na(superseded) | superseded <= as.Date(date)
  df[keep, , drop = FALSE]
}

# Bridge between `arg_match0()`-validated public arguments and the
# partition layout each table expects. Mirrors the contract enforced
# by `source_cvm_http_get()` so error classes line up across backends.
validate_mirror_args <- function(
  schema,
  partitioning,
  has_variants,
  year,
  report_type
) {
  if (identical(partitioning, "none") && !is.null(year)) {
    cvmdata_abort(
      c(
        paste(
          "Table {.val {schema$dataset}}/{.val {schema$table}} is not",
          "yearly-partitioned; {.arg year} must be {.code NULL}."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  if (has_variants && is.null(report_type)) {
    cvmdata_abort(
      c(
        paste(
          "Table {.val {schema$dataset}}/{.val {schema$table}} requires",
          "{.arg report_type} ({.val ind} or {.val con})."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  if (!has_variants && !is.null(report_type)) {
    cvmdata_abort(
      c(
        paste(
          "Table {.val {schema$dataset}}/{.val {schema$table}} does",
          "not support {.arg report_type}; pass {.code NULL}."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  invisible()
}

# Pick the year set to ask the mirror for. NULL year on a yearly
# table falls back to the latest year present in the inventory (only
# considering the requested table + report_type subset). NA for
# non-yearly tables. Aborts when the table is yearly but the
# inventory has no rows for it.
resolve_mirror_years <- function(
  inventory,
  table,
  year,
  report_type,
  partitioning
) {
  if (!identical(partitioning, "yearly")) {
    return(NULL)
  }
  if (!is.null(year)) {
    return(as.integer(year))
  }
  candidate <- filter_mirror_assets(
    inventory,
    table = table,
    year = NULL,
    report_type = report_type
  )
  if (!nrow(candidate)) {
    cvmdata_abort(
      c(
        paste(
          "No parquet assets for {.val {table}} in the mirror",
          "(report_type = {format_chr(report_type)})."
        ),
        "i" = paste(
          "The mirror may not have published this table yet;",
          "try {.code source = \"cvm\"} or report the issue."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  max(candidate$year, na.rm = TRUE)
}

# Materialise every matched asset under the L3 parquet cache and read
# them via DuckDB, stitching the per-partition results into a single
# tibble. The assets of one partition (its `part-N`, plus its `history`
# when the caller asked for it) are read in one query, by column name
# (`union_by_name`), the current asset first so its columns lead. The
# partition columns (year, report_type) are reattached from the parsed
# asset name (Decision 2 = Alt 1). Partitions are bound by name as
# well: one may have a history asset while another has none.
read_mirror_assets <- function(matches, dataset, table) {
  con <- mirror_duckdb_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  if (is.null(matches$kind)) {
    matches$kind <- rep("current", nrow(matches))
  }
  matches <- matches[order(matches$kind != "current"), , drop = FALSE]
  partition <- paste(matches$year, matches$report_type, sep = "|")
  groups <- split(seq_len(nrow(matches)), factor(partition, unique(partition)))
  parts <- lapply(groups, function(rows) {
    local_paths <- vapply(
      rows,
      function(i) {
        mirror_fetch_to_l3(
          url = matches$url[[i]],
          dataset = dataset,
          table = table,
          year = matches$year[[i]],
          report_type = matches$report_type[[i]],
          kind = matches$kind[[i]],
          sha256 = matches$sha256[[i]] %||% NA_character_,
          size = matches$size_bytes[[i]] %||% NA_integer_
        )
      },
      character(1L)
    )
    sql <- sprintf(
      "SELECT * FROM read_parquet([%s], union_by_name = true)",
      paste(
        vapply(local_paths, mirror_quote_sql, character(1L)),
        collapse = ", "
      )
    )
    df <- tryCatch(
      tibble::as_tibble(DBI::dbGetQuery(con, sql)),
      error = function(e) {
        # A file DuckDB cannot open would be a cache hit for ever; drop
        # the copies so the next call downloads them again (censobr does
        # the same).
        unlink(local_paths, force = TRUE)
        cvmdata_abort(
          c(
            paste(
              "Failed to read parquet asset{?s}",
              "{.val {basename(local_paths)}}."
            ),
            "x" = "{conditionMessage(e)}",
            "i" = paste(
              "{cli::qty(length(local_paths))}The cached cop{?y/ies}",
              "{?was/were} removed; the next call downloads {?it/them} again."
            )
          ),
          class = "cvmdata_error_parse"
        )
      }
    )
    first <- rows[[1L]]
    if (!is.na(matches$year[[first]])) {
      df$year <- matches$year[[first]]
    }
    if (!is.na(matches$report_type[[first]])) {
      df$report_type <- matches$report_type[[first]]
    }
    df
  })
  if (length(parts) == 1L) {
    return(parts[[1L]])
  }
  vctrs::vec_rbind(!!!unname(parts))
}

# Open a single in-memory DuckDB connection per call. Each
# `source_mirror_duckdb_get()` invocation owns its connection and
# tears it down on exit; we do not share connections across calls
# because DuckDB's lifecycle ties to the R session and tempdirs.
mirror_duckdb_connect <- function() {
  tryCatch(
    DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:"),
    error = function(e) {
      cvmdata_abort(
        c(
          "Could not initialise DuckDB.",
          "x" = "{conditionMessage(e)}"
        ),
        class = "cvmdata_error_internal"
      )
    }
  )
}

# Download (or serve from cache) a single parquet asset under the
# package's L3 cache. The on-disk layout mirrors the producer's
# partition tree (CLAUDE.md §10):
#   <cache>/parquet/<dataset>/<table>/[report_type=<X>/][year=<YYYY>/]
#                     part-0.parquet
# with the history asset of the partition, when read, as
# `history.parquet` next to it.
#
# `sha256` and `size` are what the mirror's sidecar publishes for the
# asset (NA when it does not: history assets, releases before
# 2026-10-25). A cached file that does not match them is a truncated
# download or the same partition from another snapshot: it is replaced.
# A download that does not match them is discarded and aborts with
# `cvmdata_error_http_integrity` (ROADMAP "Integridade do download",
# measured 2026-10-25: before this, a corrupt parquet was a cache hit for
# ever). Without a known digest the size alone is checked when known,
# and an existing file is reused as before.
mirror_fetch_to_l3 <- function(
  url,
  dataset,
  table,
  year,
  report_type,
  kind = "current",
  sha256 = NA_character_,
  size = NA_integer_
) {
  dest <- mirror_l3_path(dataset, table, year, report_type, kind)
  ensure_dir(dirname(dest))
  if (file.exists(dest)) {
    if (mirror_file_matches(dest, sha256, size)) {
      return(dest)
    }
    unlink(dest, force = TRUE)
  }
  # One retry on a mismatch: a transfer cut short, or `-latest` read in
  # the minutes between the ETL's upload of the parquets and of the
  # sidecar (the sidecar goes last, so the old one may describe the new
  # bytes for a while).
  got_size <- NA_real_
  for (attempt in 1:2) {
    mirror_download_asset(url, dest)
    if (mirror_file_matches(dest, sha256, size)) {
      return(dest)
    }
    got_size <- file.size(dest)
    unlink(dest, force = TRUE)
  }
  cvmdata_abort(
    c(
      paste(
        "Downloaded asset {.val {basename(url)}} does not match the",
        "mirror's manifest."
      ),
      "x" = paste(
        "Expected {.val {size}} bytes, sha256 {.val {sha256}};",
        "got {.val {got_size}} bytes, twice."
      ),
      "i" = paste(
        "The file was discarded. Try again in a few minutes (the mirror",
        "may be mid-update); if it persists, report it at",
        "{.url https://github.com/SidneyBissoli/cvmdata/issues}."
      )
    ),
    class = c("cvmdata_error_http_integrity", "cvmdata_error_http")
  )
}

# GET one asset into `dest`. HTTP failures are `cvmdata_error_http`.
mirror_download_asset <- function(url, dest) {
  resp <- tryCatch(
    httr2::req_perform(
      httr2::request(url) |>
        httr2::req_user_agent("cvmdata") |>
        httr2::req_retry(max_tries = 3L)
    ),
    error = function(e) {
      cvmdata_abort(
        c(
          "HTTP GET failed for {.url {url}}.",
          "x" = "{conditionMessage(e)}"
        ),
        class = "cvmdata_error_http"
      )
    }
  )
  status <- httr2::resp_status(resp)
  if (status >= 400L) {
    cvmdata_abort(
      c(
        "HTTP {status} for {.url {url}}.",
        "i" = "Re-run with {.code source = \"cvm\"} as a fallback."
      ),
      class = "cvmdata_error_http"
    )
  }
  writeBin(httr2::resp_body_raw(resp), dest)
  invisible(dest)
}

# Whether a local file has the size and sha256 the sidecar publishes.
# Unknown values (NA) are not checked; without a sha256 implementation
# (R < 4.5 and no `digest`) the size decides.
mirror_file_matches <- function(path, sha256, size) {
  if (
    !is.na(size) && !identical(as.numeric(file.size(path)), as.numeric(size))
  ) {
    return(FALSE)
  }
  if (is.na(sha256)) {
    return(TRUE)
  }
  actual <- mirror_sha256_file(path)
  if (is.na(actual)) {
    return(TRUE)
  }
  identical(tolower(actual), tolower(sha256))
}

# SHA-256 of a file: `tools::sha256sum()` (R >= 4.5), else `digest` when
# installed, else NA (not checkable).
mirror_sha256_file <- function(path) {
  tools_ns <- asNamespace("tools")
  if (exists("sha256sum", envir = tools_ns, inherits = FALSE)) {
    return(unname(get("sha256sum", envir = tools_ns)(path)))
  }
  if (requireNamespace("digest", quietly = TRUE)) {
    return(digest::digest(file = path, algo = "sha256"))
  }
  NA_character_
}

# Compose the absolute path of an L3 cache slot. Hive-style ("year=Y",
# "report_type=R") so a future migration to `arrow::open_dataset()`
# can pick the tree up natively. The `<group>` segment was introduced
# in v0.1.0.9000; see `R/util-group-lookup.R`.
mirror_l3_path <- function(
  dataset,
  table,
  year,
  report_type,
  kind = "current"
) {
  parts <- c(
    cvm_cache_path(),
    "parquet",
    dataset_group(dataset),
    dataset,
    table
  )
  if (!is.na(report_type) && nzchar(report_type)) {
    parts <- c(parts, sprintf("report_type=%s", report_type))
  }
  if (!is.na(year)) {
    parts <- c(parts, sprintf("year=%d", as.integer(year)))
  }
  file_name <- if (identical(kind, "history")) {
    "history.parquet"
  } else {
    "part-0.parquet"
  }
  do.call(file.path, as.list(parts)) |>
    file.path(file_name)
}

# Escape a path for inclusion as a SQL string literal. DuckDB uses
# single-quote string delimiters; doubling escapes single quotes
# inside the path. Windows paths with backslashes are normalised to
# forward slashes so DuckDB's path parser handles them uniformly.
mirror_quote_sql <- function(path) {
  normalised <- gsub("\\\\", "/", path, fixed = FALSE)
  sprintf("'%s'", gsub("'", "''", normalised, fixed = TRUE))
}

# Compare the current release source-hash against the sidecar stored
# alongside the L3 cache for the dataset. When they differ, evict the
# entire `<cache>/parquet/<dataset>/` tree before the next read so we
# never serve stale bytes. The sidecar is then refreshed with the
# current hash so subsequent calls in this session can short-circuit.
#
# - `current_hash = NA_character_` (the release predates the
#   hash-detection feature) is treated as "do not evict" so users on
#   older mirrors are not punished with redownloads. The local sidecar
#   is not refreshed in that case either.
# - Missing local sidecar with a non-NA current hash is the common
#   "first call" path: nothing is evicted and the new hash is
#   recorded.
# - `verified = TRUE` (the sidecar publishes a sha256 for every current
#   asset, since 2026-10-25): the per-file check in
#   `mirror_fetch_to_l3()` replaces the copies that changed, so only the
#   history assets, which carry no digest, are evicted. Before this a
#   weekly change of one partition re-downloaded the whole dataset.
mirror_l3_validate_hash <- function(dataset, current_hash, verified = FALSE) {
  if (is.null(current_hash) || is.na(current_hash) || !nzchar(current_hash)) {
    return(invisible())
  }
  dataset_root <- file.path(
    cvm_cache_path(),
    "parquet",
    dataset_group(dataset),
    dataset
  )
  sidecar <- file.path(dataset_root, "__source_hash.json")

  if (file.exists(sidecar)) {
    cached <- tryCatch(
      readLines(sidecar, warn = FALSE),
      error = function(e) character(0L)
    )
    cached <- if (length(cached)) trimws(paste(cached, collapse = "")) else ""
    if (identical(cached, current_hash)) {
      return(invisible())
    }
    if (dir.exists(dataset_root) && verified) {
      stale <- list.files(
        dataset_root,
        pattern = "^history\\.parquet$",
        recursive = TRUE,
        full.names = TRUE
      )
      unlink(stale, force = TRUE)
    } else if (dir.exists(dataset_root)) {
      unlink(dataset_root, recursive = TRUE, force = TRUE)
      cli::cli_inform(c(
        "i" = paste(
          "Mirror source-hash changed; evicted L3 cache for dataset",
          "{.val {dataset}}."
        )
      ))
    }
  }

  ensure_dir(dataset_root)
  writeLines(current_hash, sidecar)
  invisible()
}

# Pretty-print helpers for the error messages — keep `format_chr` and
# `format_years` out of inline cli expressions so the no-rows abort
# reads cleanly with or without filters.
format_chr <- function(x) {
  if (is.null(x) || (length(x) == 1L && is.na(x))) {
    "NULL"
  } else {
    sprintf('"%s"', x)
  }
}

format_years <- function(years) {
  if (is.null(years) || all(is.na(years))) {
    return("NULL")
  }
  paste(years, collapse = ", ")
}
