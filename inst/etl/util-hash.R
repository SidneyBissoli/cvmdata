# ETL helper: SHA-256 hash of what a mirror release would publish.
#
# Used by 03-publish.R to detect changes: when the hash equals the one of
# the last successful publish (recorded in the previous release's
# `__source_hash.json` asset), the publish is skipped. The client also
# evicts its L3 parquet cache when the hash changes.
#
# The hash covers the CVM dictionary (META) files AND the content of every
# parquet about to be published. Until 2026-10-19 it covered META only, so
# new filings, restatements and package fixes never reached the mirror
# while the dictionaries stayed put: every release was frozen at its June
# 2026 snapshot. A parquet is hashed by its rows and columns, not by its
# bytes, because the bytes carry the `fetched_at` attribute and would
# change on every run.
#
# The function does NOT use the package cache — META freshness checks have
# to bite the network every time, otherwise the change-detection guarantee
# is gone.
#
# Sourced (not loaded as a package). Depends on `00-config.R` having been
# sourced first for `mirror_schema_dir()`.

stopifnot(requireNamespace("arrow", quietly = TRUE))
stopifnot(requireNamespace("digest", quietly = TRUE))
stopifnot(requireNamespace("httr2", quietly = TRUE))
stopifnot(requireNamespace("jsonlite", quietly = TRUE))
stopifnot(requireNamespace("yaml", quietly = TRUE))

# Splits a dictionary URL of the form "<zip-url>#<entry>" into a
# (base_url, fragment) pair. Plain URLs return fragment = NA.
mirror_split_dict_url <- function(url) {
  parts <- strsplit(url, "#", fixed = TRUE)[[1L]]
  list(
    base = parts[1L],
    fragment = if (length(parts) > 1L) parts[2L] else NA_character_
  )
}

# Collects the unique non-null `cvm_dictionary_url` values from a dataset's
# schema YAMLs. Tables marked `meta_status: missing` contribute nothing.
mirror_collect_dict_urls <- function(dataset) {
  yaml_files <- list.files(
    mirror_schema_dir(dataset),
    pattern = "\\.yaml$",
    full.names = TRUE
  )
  raw <- unlist(lapply(yaml_files, function(p) {
    s <- yaml::read_yaml(p)
    if (identical(s$meta_status, "missing")) {
      return(character())
    }
    if (is.null(s$cvm_dictionary_url)) {
      return(character())
    }
    s$cvm_dictionary_url
  }))
  sort(unique(raw))
}

# Downloads a URL into a temp file with no caching layer. Returns the path.
mirror_download_meta <- function(base_url) {
  dest <- tempfile(fileext = ".bin")
  req <- httr2::request(base_url) |>
    httr2::req_user_agent("cvmdata-etl") |>
    httr2::req_retry(max_tries = 3L)
  resp <- httr2::req_perform(req, path = dest)
  httr2::resp_check_status(resp)
  dest
}

# Hashes a single META entry. If the URL embeds a ZIP fragment, the entry
# is extracted to tempdir and the extracted file is hashed instead.
mirror_hash_meta_entry <- function(local_base, fragment) {
  if (is.na(fragment)) {
    return(digest::digest(file = local_base, algo = "sha256"))
  }
  extract_dir <- tempfile("metaentry-")
  dir.create(extract_dir)
  on.exit(unlink(extract_dir, recursive = TRUE), add = TRUE)
  utils::unzip(local_base, files = fragment, exdir = extract_dir)
  extracted <- file.path(extract_dir, fragment)
  if (!file.exists(extracted)) {
    stop(
      sprintf(
        "META entry '%s' not found inside '%s'",
        fragment,
        local_base
      ),
      call. = FALSE
    )
  }
  digest::digest(file = extracted, algo = "sha256")
}

# Hashes the rows and columns of one parquet. R attributes restored by
# arrow (`fetched_at`, `package_version`, ...) are dropped first; column
# classes stay, so a type change still counts as a change.
mirror_hash_parquet <- function(path) {
  df <- as.data.frame(arrow::read_parquet(path))
  attributes(df) <- attributes(df)[c("names", "row.names", "class")]
  digest::digest(df, algo = "sha256")
}

# Hashes every parquet of a dataset, keyed by its path relative to
# `dataset_dir` (the partition, e.g. "bpa/report_type=ind/year=2024/...").
mirror_hash_parquets <- function(parquets, dataset_dir) {
  if (!length(parquets)) {
    return(list())
  }
  rel <- substring(parquets, nchar(dataset_dir) + 2L)
  rel <- gsub("\\\\", "/", rel)
  hashes <- vapply(parquets, mirror_hash_parquet, character(1L))
  names(hashes) <- rel
  as.list(hashes)[order(rel)]
}

# SHA-256 of a canonical JSON encoding of a named list sorted by name, so
# different platforms and orderings yield the same digest.
mirror_digest_map <- function(x) {
  payload <- jsonlite::toJSON(
    x[order(names(x))],
    auto_unbox = TRUE,
    pretty = FALSE
  )
  digest::digest(payload, algo = "sha256", serialize = FALSE)
}

# Computes the publish hash for a dataset.
#
# Returns a list with:
#   hash         : SHA-256 over the META hash and the parquet hashes.
#   meta_hash    : SHA-256 of the sorted {url: file_sha256} META map, or
#                  NA when the dataset has no META.
#   components   : the META map (named list).
#   data         : {partition path: content sha256} for each parquet.
#   computed_at  : ISO-8601 UTC timestamp.
#   dataset      : echoed input.
#
# `hash` is NA only when there is neither META nor any parquet.
compute_source_hash <- function(
  dataset,
  parquets = character(),
  dataset_dir = NULL
) {
  meta <- compute_meta_hash(dataset)
  data <- mirror_hash_parquets(parquets, dataset_dir)
  hash <- if (is.na(meta$hash) && !length(data)) {
    NA_character_
  } else {
    mirror_digest_map(list(meta = meta$hash, data = mirror_digest_map(data)))
  }
  list(
    dataset = dataset,
    computed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    hash = hash,
    meta_hash = meta$hash,
    components = meta$components,
    data = data
  )
}

# Computes the META hash for a dataset: list(hash, components). Datasets
# with no available META (all-missing) return hash = NA_character_.
compute_meta_hash <- function(dataset) {
  urls <- mirror_collect_dict_urls(dataset)
  if (!length(urls)) {
    return(list(hash = NA_character_, components = list()))
  }

  # Deduplicate downloads by base URL (DFP/ITR/FRE share one ZIP across
  # 10+ table entries).
  parsed <- lapply(urls, mirror_split_dict_url)
  bases <- unique(vapply(parsed, `[[`, character(1L), "base"))
  local_bases <- vapply(bases, mirror_download_meta, character(1L))
  names(local_bases) <- bases

  components <- vapply(
    parsed,
    function(pair) {
      mirror_hash_meta_entry(local_bases[[pair$base]], pair$fragment)
    },
    character(1L)
  )
  names(components) <- urls
  components <- as.list(components)
  list(hash = mirror_digest_map(components), components = components)
}
