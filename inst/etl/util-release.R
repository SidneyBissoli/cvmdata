# ETL helpers: the assets of a mirror release, by name.
#
# Shared by 03-publish.R, 04-rad-fetch.R and 05-label-scale.R, which
# until 2026-11-06 each carried a copy. Depends on `00-config.R` having
# been sourced first for `mirror_repo`.

stopifnot(requireNamespace("httr2", quietly = TRUE))

# Asset name of a partition path, as staged ("=" kept) or as GitHub
# serves it ("=" replaced by ".", see parse_mirror_asset_name()).
asset_name_of <- function(rel) {
  gsub("[/\\\\]", "__", rel)
}
public_asset_name <- function(rel) {
  gsub("=", ".", asset_name_of(rel), fixed = TRUE)
}

# Downloads one asset of the release into `dir` and returns its path, or
# NULL when gh could not fetch it (missing asset or a failure that three
# attempts did not clear; gh does not tell the two apart).
download_release_asset <- function(tag, name, dir, attempts = 3L) {
  for (attempt in seq_len(attempts)) {
    status <- suppressWarnings(system2(
      "gh",
      c(
        "release",
        "download",
        tag,
        "--repo",
        mirror_repo,
        "--pattern",
        name,
        "--dir",
        shQuote(dir),
        "--clobber"
      ),
      stdout = NULL,
      stderr = NULL
    ))
    path <- file.path(dir, name)
    if (status == 0L && file.exists(path)) {
      return(path)
    }
    if (attempt < attempts) {
      Sys.sleep(5 * attempt)
    }
  }
  NULL
}

# Downloads one asset of the release from its public URL, which costs
# no API quota: the prune of a rule change reads every history asset of
# the release in one run (263 in dfp on 2026-11-05), and the hourly
# quota of the workflow token is already tight for the uploads
# (util-gh.R).
#
# The download host answers an occasional 5xx for an asset that is
# there: on 2026-11-05 one 504 among the 249 history assets of itr
# stopped the prune (httr2 retries 429 and 503 only), while the same URL
# answered 200 twenty seconds later. So every 5xx and every connection
# failure is tried again, five attempts with a growing wait, and an
# asset the public URL still does not bring is fetched through the API
# (`download_release_asset()`), which costs quota only then. NULL when
# neither path brought it.
download_public_asset <- function(tag, name, dir) {
  path <- file.path(dir, name)
  url <- sprintf(
    "https://github.com/%s/releases/download/%s/%s",
    mirror_repo,
    tag,
    utils::URLencode(name, reserved = TRUE)
  )
  resp <- tryCatch(
    httr2::request(url) |>
      httr2::req_user_agent("cvmdata-etl") |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_retry(
        max_tries = 5L,
        is_transient = function(resp) {
          httr2::resp_status(resp) %in% c(429L, 500L, 502L, 503L, 504L)
        },
        backoff = function(attempt) 5 * attempt,
        retry_on_failure = TRUE
      ) |>
      httr2::req_perform(path = path),
    error = function(e) NULL
  )
  if (!is.null(resp) && httr2::resp_status(resp) == 200L) {
    return(path)
  }
  unlink(path)
  message(sprintf(
    "  %s: public download answered %s; trying the API",
    name,
    if (is.null(resp)) "no response" else httr2::resp_status(resp)
  ))
  download_release_asset(tag, name, dir)
}

# Uploads one asset to the release, replacing an asset of the same name;
# four attempts with a growing wait, then an error.
upload_release_asset <- function(tag, path, attempts = 4L) {
  for (attempt in seq_len(attempts)) {
    status <- system2(
      "gh",
      c(
        "release",
        "upload",
        tag,
        shQuote(path),
        "--repo",
        mirror_repo,
        "--clobber"
      )
    )
    if (status == 0L) {
      return(invisible(TRUE))
    }
    if (attempt < attempts) {
      wait <- 10 * 2^(attempt - 1L)
      message(sprintf("    upload failed; retry %d in %ds", attempt, wait))
      Sys.sleep(wait)
    }
  }
  stop(sprintf("upload failed for %s", basename(path)), call. = FALSE)
}
