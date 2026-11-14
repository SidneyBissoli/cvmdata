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
#
# The public URL lags behind an upload: on 2026-11-14 an asset replaced
# with `--clobber` at 12:41:28 was still served with its old bytes at
# 12:43:10 and with the new ones at 12:44:36, while the API had the new
# ones all along. A caller that reads an asset it (or a step before it)
# may have just replaced passes `expect_sha256`, the digest the API
# lists for it (`release_asset_digests()`): other bytes are a stale
# copy, and the asset is fetched through the API instead; if that copy
# differs too, it stops, since those are not the bytes the release
# holds. NULL or NA (an asset the API lists without a digest) skips the
# check.
download_public_asset <- function(tag, name, dir, expect_sha256 = NULL) {
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
  answered <- !is.null(resp) && httr2::resp_status(resp) == 200L
  if (answered && asset_digest_matches(path, expect_sha256)) {
    return(path)
  }
  message(sprintf(
    "  %s: public download %s; trying the API",
    name,
    if (answered) {
      "brought bytes the release no longer holds (stale copy)"
    } else if (is.null(resp)) {
      "answered no response"
    } else {
      sprintf("answered %s", httr2::resp_status(resp))
    }
  ))
  unlink(path)
  path <- download_release_asset(tag, name, dir)
  if (!is.null(path) && !asset_digest_matches(path, expect_sha256)) {
    stop(
      sprintf(
        "%s of %s: the download does not have the sha256 the release lists",
        name,
        tag
      ),
      call. = FALSE
    )
  }
  path
}

# TRUE when the file has the sha256 expected of it, or none is expected.
asset_digest_matches <- function(path, expect_sha256) {
  if (is.null(expect_sha256) || is.na(expect_sha256)) {
    return(TRUE)
  }
  identical(
    digest::digest(file = path, algo = "sha256"),
    unname(as.character(expect_sha256))
  )
}

# sha256 of the assets of a release, by asset name, as the API lists
# them: one call for the whole release. Stops when the release cannot be
# read, since a caller asks for it to tell fresh bytes from stale ones.
release_asset_digests <- function(tag) {
  out <- suppressWarnings(system2(
    "gh",
    c("release", "view", tag, "--repo", mirror_repo, "--json", "assets"),
    stdout = TRUE,
    stderr = NULL
  ))
  if (!is.null(attr(out, "status")) || !length(out)) {
    stop(sprintf("could not list the assets of %s", tag), call. = FALSE)
  }
  # Joined with nothing: R cuts a long line of output into pieces, and a
  # newline between two of them can fall inside a string (seen on
  # 2026-11-14 with the assets of an fre snapshot: "invalid character
  # inside string"). JSON needs no line break between tokens.
  parse_asset_digests(paste(out, collapse = ""))
}

# The `{"assets": [{name, digest, ...}]}` of `gh release view` as a
# character vector of sha256 by asset name; NA for an asset listed
# without a digest or with one of another algorithm.
parse_asset_digests <- function(json) {
  assets <- jsonlite::fromJSON(json, simplifyVector = FALSE)$assets
  digests <- vapply(
    assets,
    function(a) {
      d <- a$digest
      if (is.null(d) || !startsWith(d, "sha256:")) {
        return(NA_character_)
      }
      sub("^sha256:", "", d)
    },
    character(1)
  )
  names(digests) <- vapply(assets, function(a) a$name, character(1))
  digests
}

# Uploads one asset to the release, replacing an asset of the same name;
# four attempts with a growing wait, then an error.
# Deletes one asset of a release. Used by the repair of the dated
# snapshots for the tables the mirror no longer carries; stops when gh
# refuses, because a partly cleaned snapshot must not pass for done.
delete_release_asset <- function(tag, name) {
  status <- system2(
    "gh",
    c(
      "release",
      "delete-asset",
      tag,
      shQuote(name),
      "--repo",
      mirror_repo,
      "--yes"
    )
  )
  if (!identical(status, 0L)) {
    stop(sprintf("could not delete %s from %s", name, tag), call. = FALSE)
  }
  invisible(TRUE)
}

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
