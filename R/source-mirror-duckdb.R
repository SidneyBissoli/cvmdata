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

# Entry point invoked by `cvm_fetch_internal()` when source = "mirror".
# Returns a tibble (already in the shape that the CVM-HTTP path would
# return after `read_cvm_csv()` + `apply_schema_transformations()`),
# leaving `filter_by_companies()` to the upstream orchestrator.
#
# - `years` mirrors the public `years` argument: NULL means "latest
#   year available in the mirror"; otherwise an integer vector.
# - `report_type` is required for tables with `cvm_file_pattern_variants`
#   and forbidden for the rest, with the same validation rules as the
#   CVM-HTTP path (enforced one level up by `cvm_fetch_internal()`).
source_mirror_duckdb_get <- function(schema, years = NULL,
                                     report_type = NULL, ...) {
  dataset <- schema$dataset
  table <- schema$table
  partitioning <- schema$temporal_partitioning %||% "none"
  has_variants <- !is.null(schema$cvm_file_pattern_variants)

  validate_mirror_args(schema, partitioning, has_variants,
                       years, report_type)

  inventory <- mirror_list_assets(dataset)
  resolved_years <- resolve_mirror_years(
    inventory, table, years, report_type, partitioning
  )
  matches <- filter_mirror_assets(
    inventory, table = table,
    years = resolved_years, report_type = report_type
  )
  if (!nrow(matches)) {
    cvmdata_abort(
      c(
        paste(
          "No parquet assets match {.val {dataset}}/{.val {table}}",
          "in the mirror."
        ),
        "i" = paste(
          "Searched release {.val {attr(inventory, 'release_tag')}}",
          "for {.code years = {format_years(resolved_years)}}",
          "{.code report_type = {format_chr(report_type)}}."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  read_mirror_assets(matches, dataset, table)
}

# Bridge between `arg_match0()`-validated public arguments and the
# partition layout each table expects. Mirrors the contract enforced
# by `source_cvm_http_get()` so error classes line up across backends.
validate_mirror_args <- function(schema, partitioning, has_variants,
                                 years, report_type) {
  if (identical(partitioning, "none") && !is.null(years)) {
    cvmdata_abort(
      c(
        paste(
          "Table {.val {schema$dataset}}/{.val {schema$table}} is not",
          "yearly-partitioned; {.arg years} must be {.code NULL}."
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

# Pick the year set to ask the mirror for. NULL years on a yearly
# table fall back to the latest year present in the inventory (only
# considering the requested table + report_type subset). NA for
# non-yearly tables. Aborts when the table is yearly but the
# inventory has no rows for it.
resolve_mirror_years <- function(inventory, table, years, report_type,
                                 partitioning) {
  if (!identical(partitioning, "yearly")) {
    return(NULL)
  }
  if (!is.null(years)) {
    return(as.integer(years))
  }
  candidate <- filter_mirror_assets(
    inventory, table = table,
    years = NULL, report_type = report_type
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
# them via DuckDB, stitching the per-asset results into a single
# tibble. The partition columns (year, report_type) are reattached from
# the parsed asset name (Decision 2 = Alt 1).
read_mirror_assets <- function(matches, dataset, table) {
  con <- mirror_duckdb_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  parts <- vector("list", nrow(matches))
  for (i in seq_len(nrow(matches))) {
    local_path <- mirror_fetch_to_l3(
      url = matches$url[[i]],
      dataset = dataset,
      table = table,
      year = matches$year[[i]],
      report_type = matches$report_type[[i]]
    )
    sql <- sprintf(
      "SELECT * FROM read_parquet(%s)",
      mirror_quote_sql(local_path)
    )
    df <- tryCatch(
      tibble::as_tibble(DBI::dbGetQuery(con, sql)),
      error = function(e) {
        cvmdata_abort(
          c(
            paste(
              "Failed to read parquet asset",
              "{.val {basename(local_path)}}."
            ),
            "x" = "{conditionMessage(e)}"
          ),
          class = "cvmdata_error_parse"
        )
      }
    )
    if (!is.na(matches$year[[i]])) {
      df$year <- matches$year[[i]]
    }
    if (!is.na(matches$report_type[[i]])) {
      df$report_type <- matches$report_type[[i]]
    }
    parts[[i]] <- df
  }
  if (length(parts) == 1L) {
    return(parts[[1L]])
  }
  do.call(rbind, parts)
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
#
# Commit 4 of Sessao 3.13 layers hash-based invalidation on top; for
# now an existing file is reused as-is. A future iteration may add
# TTL / etag handling analogous to `download_with_etag()` in
# R/source-cvm-http.R.
mirror_fetch_to_l3 <- function(url, dataset, table, year,
                               report_type) {
  dest <- mirror_l3_path(dataset, table, year, report_type)
  ensure_dir(dirname(dest))
  if (file.exists(dest)) {
    return(dest)
  }
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
  dest
}

# Compose the absolute path of an L3 cache slot. Hive-style ("year=Y",
# "report_type=R") so a future migration to `arrow::open_dataset()`
# can pick the tree up natively.
mirror_l3_path <- function(dataset, table, year, report_type) {
  parts <- c(cvm_cache_path(), "parquet", dataset, table)
  if (!is.na(report_type) && nzchar(report_type)) {
    parts <- c(parts, sprintf("report_type=%s", report_type))
  }
  if (!is.na(year)) {
    parts <- c(parts, sprintf("year=%d", as.integer(year)))
  }
  do.call(file.path, as.list(parts)) |>
    file.path("part-0.parquet")
}

# Escape a path for inclusion as a SQL string literal. DuckDB uses
# single-quote string delimiters; doubling escapes single quotes
# inside the path. Windows paths with backslashes are normalised to
# forward slashes so DuckDB's path parser handles them uniformly.
mirror_quote_sql <- function(path) {
  normalised <- gsub("\\\\", "/", path, fixed = FALSE)
  sprintf("'%s'", gsub("'", "''", normalised, fixed = TRUE))
}

# Pretty-print helpers for the error messages — keep `format_chr` and
# `format_years` out of inline cli expressions so the no-rows abort
# reads cleanly with or without filters.
format_chr <- function(x) {
  if (is.null(x) || (length(x) == 1L && is.na(x))) "NULL" else
    sprintf('"%s"', x)
}

format_years <- function(years) {
  if (is.null(years) || all(is.na(years))) {
    return("NULL")
  }
  paste(years, collapse = ", ")
}
