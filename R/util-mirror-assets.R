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

# Repo coordinates. Single source of truth on the consumer side; the
# producer side (inst/etl/00-config.R) carries the same constant.
.mirror_repo <- "SidneyBissoli/cvmdata"

# Session-scoped cache for asset listings. Keyed by dataset id.
.mirror_assets_cache <- new.env(parent = emptyenv())

# Reset the session cache. Test helper; never called from production
# code paths.
mirror_assets_cache_clear <- function() {
  rm(list = ls(.mirror_assets_cache), envir = .mirror_assets_cache)
  invisible()
}

# Tag of the moving "latest" release for a dataset (mirrors
# `mirror_tag_latest()` from inst/etl/00-config.R).
mirror_release_tag <- function(dataset) {
  sprintf("mirror-%s-latest", dataset)
}

# List the parquet assets of the release `mirror-<dataset>-latest` via
# the GitHub REST API. Returns a tibble with one row per asset:
#   name        : asset filename (post-sanitisation; `=` -> `.`)
#   url         : browser_download_url (resolves without auth)
#   size_bytes  : asset size in bytes (integer)
# plus an attribute `source_hash` carrying the value of the
# `__source_hash.json` asset of the same release (or `NA_character_`
# when the release has none). The result is cached per session so a
# single `issuer_fetch()` call list-assets at most once per dataset.
#
# Anonymous API access is enough for public repos (rate limit
# 60 req/h, and the per-dataset call hits it once per session). When
# `GITHUB_TOKEN` or `GITHUB_PAT` is set, the call attaches a Bearer
# header to bump the limit to 5000 req/h — useful for CI runners.
mirror_list_assets <- function(dataset, repo = .mirror_repo,
                               refresh = FALSE) {
  if (!isTRUE(refresh) && !is.null(.mirror_assets_cache[[dataset]])) {
    return(.mirror_assets_cache[[dataset]])
  }
  tag <- mirror_release_tag(dataset)
  url <- sprintf("https://api.github.com/repos/%s/releases/tags/%s",
                 repo, tag)
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
    httr2::req_perform(req),
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
        "GitHub API returned HTTP {status} for {.url {url}}.",
        "i" = paste(
          "Release tag {.val {tag}} may not exist yet; check",
          "{.url https://github.com/{repo}/releases}."
        )
      ),
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
  parsed <- mirror_assets_to_tibble(assets)
  attr(parsed, "source_hash") <- mirror_extract_source_hash(assets)
  attr(parsed, "release_tag") <- tag
  .mirror_assets_cache[[dataset]] <- parsed
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
mirror_assets_to_tibble <- function(assets) {
  if (!length(assets)) {
    return(tibble::tibble(
      name = character(0L),
      url = character(0L),
      size_bytes = integer(0L)
    ))
  }
  tibble::tibble(
    name = vapply(assets, function(a) a$name %||% NA_character_,
                  character(1L)),
    url = vapply(
      assets,
      function(a) a$browser_download_url %||% NA_character_,
      character(1L)
    ),
    size_bytes = vapply(
      assets,
      function(a) as.integer(a$size %||% NA_integer_),
      integer(1L)
    )
  )
}

# Pluck the SHA-256 carried by the `__source_hash.json` asset. The asset
# itself is fetched only when present (one extra GET on first call).
# Returns NA_character_ when the release has none — happens for fresh
# releases that have not been republished since the hash-detection
# feature shipped.
mirror_extract_source_hash <- function(assets) {
  hit <- NULL
  for (a in assets) {
    if (identical(a$name, "__source_hash.json")) {
      hit <- a
      break
    }
  }
  if (is.null(hit)) {
    return(NA_character_)
  }
  url <- hit$browser_download_url %||% ""
  if (!nzchar(url)) {
    return(NA_character_)
  }
  resp <- tryCatch(
    httr2::req_perform(
      httr2::req_user_agent(httr2::request(url), "cvmdata")
    ),
    error = function(e) NULL
  )
  if (is.null(resp) || httr2::resp_status(resp) >= 400L) {
    return(NA_character_)
  }
  body <- tryCatch(
    httr2::resp_body_json(resp, simplifyVector = TRUE),
    error = function(e) NULL
  )
  if (is.null(body)) {
    return(NA_character_)
  }
  body$hash %||% NA_character_
}

# Pure parser: decode an asset filename into a (table, report_type,
# year) tuple. Handles both raw (`=`) and GitHub-sanitised (`.`)
# separators in the key/value segments. Returns `NULL` when the asset
# is the `__source_hash.json` sidecar (not a data asset). Aborts with
# `cvmdata_error_parse` for malformed names.
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
  if (!grepl("^part-[0-9]+\\.parquet$", last)) {
    cvmdata_abort(
      c(
        paste(
          "Asset name {.val {name}} does not end in",
          "{.code part-N.parquet}."
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
  list(table = table, report_type = report_type, year = year)
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

# Filter an asset inventory by (table, year, report_type). Returns a
# tibble subset of the input with the parsed `table`, `year`, and
# `report_type` columns attached, ready for the DuckDB reader.
#
# - `year = NULL` keeps every year present in the inventory.
# - `report_type = NULL` keeps every variant (no filter); for tables
#   that publish variants the caller is expected to pass either `"ind"`
#   or `"con"`, otherwise the result mixes both.
filter_mirror_assets <- function(assets, table, year = NULL,
                                 report_type = NULL) {
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
  assets$table <- tbl
  assets$report_type <- rt
  assets$year <- yr

  mask <- assets$table == table
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
  assets
}
