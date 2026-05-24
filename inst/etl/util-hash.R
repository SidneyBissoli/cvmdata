# ETL helper: SHA-256 hash of the CVM dictionary (META) files for a dataset.
#
# Used by 03-publish.R to detect changes upstream: when the META content is
# byte-identical to the last successful publish (recorded in the previous
# release's `__source_hash.json` asset), the publish is skipped.
#
# The function does NOT use the package cache — META freshness checks have
# to bite the network every time, otherwise the change-detection guarantee
# is gone.
#
# Sourced (not loaded as a package). Depends on `00-config.R` having been
# sourced first for `mirror_schema_dir()`.

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
    pattern = "\\.yaml$", full.names = TRUE
  )
  raw <- unlist(lapply(yaml_files, function(p) {
    s <- yaml::read_yaml(p)
    if (identical(s$meta_status, "missing")) return(character())
    if (is.null(s$cvm_dictionary_url)) return(character())
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
    stop(sprintf(
      "META entry '%s' not found inside '%s'", fragment, local_base
    ), call. = FALSE)
  }
  digest::digest(file = extracted, algo = "sha256")
}

# Computes the source META hash for a dataset.
#
# Returns a list with:
#   hash         : SHA-256 of the JSON-encoded sorted {url: file_sha256} map.
#   components   : the same map (named list).
#   computed_at  : ISO-8601 UTC timestamp.
#   dataset      : echoed input.
#
# Datasets with no available META (all-missing) return hash = NA_character_.
compute_source_hash <- function(dataset) {
  urls <- mirror_collect_dict_urls(dataset)
  out_meta <- list(
    dataset = dataset,
    computed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
  if (!length(urls)) {
    return(c(out_meta, list(hash = NA_character_, components = list())))
  }

  # Deduplicate downloads by base URL (DFP/ITR/FRE share one ZIP across
  # 10+ table entries).
  parsed <- lapply(urls, mirror_split_dict_url)
  bases <- unique(vapply(parsed, `[[`, character(1L), "base"))
  local_bases <- vapply(bases, mirror_download_meta, character(1L))
  names(local_bases) <- bases

  components <- vapply(parsed, function(pair) {
    mirror_hash_meta_entry(local_bases[[pair$base]], pair$fragment)
  }, character(1L))
  names(components) <- urls

  # Hash is taken over a canonical JSON encoding of the sorted components
  # map, so different platforms / orderings yield the same digest.
  payload <- jsonlite::toJSON(
    as.list(components)[order(names(components))],
    auto_unbox = TRUE, pretty = FALSE
  )
  c(out_meta, list(
    hash = digest::digest(payload, algo = "sha256", serialize = FALSE),
    components = as.list(components)
  ))
}
