# gh calls that outlast a spent API quota (2026-10-27).
#
# The robots publish with the workflow's GITHUB_TOKEN, whose REST quota
# is per hour. On 2026-10-27 the first complete-baseline snapshots (every
# partition uploaded to the dated release and again to `-latest`) plus a
# re-run spent it mid-upload: the 10/20/40 s retries of upload_assets()
# cannot outlast a window that resets once an hour, so itr-latest was
# left with 200 of its 296 assets replaced and an old sidecar, and the
# cad, cgvn and ipe jobs died on `gh release edit`. A spent quota is now
# waited out (the reset time comes from GET /rate_limit, which does not
# count against the quota) and the same call is run again, so a publish
# finishes late instead of half done. The job's `timeout-minutes` still
# bounds the whole run.

# Seconds to wait before the quota resets, from the JSON of
# `gh api rate_limit` (character lines). 0 when the quota is not spent
# or the JSON cannot be read: an unknown state must not stall the job.
quota_wait_seconds <- function(json, now = Sys.time()) {
  core <- tryCatch(
    jsonlite::fromJSON(paste(json, collapse = "\n"))$resources$core,
    error = function(e) NULL
  )
  remaining <- suppressWarnings(as.numeric(core$remaining))
  reset <- suppressWarnings(as.numeric(core$reset))
  if (length(remaining) != 1L || is.na(remaining) || remaining > 0) {
    return(0)
  }
  if (length(reset) != 1L || is.na(reset)) {
    return(0)
  }
  # +5 s of slack: the reset is a whole second and clocks drift.
  max(0, reset - as.numeric(now)) + 5
}

# Waits out a spent quota. TRUE when it waited (the caller runs the call
# again), FALSE when the quota is not what failed. One wait is capped at
# a little over the hourly window, so a bad reading cannot sleep forever.
wait_for_api_quota <- function(max_wait = 3900) {
  json <- tryCatch(
    suppressWarnings(system2(
      "gh",
      c("api", "rate_limit"),
      stdout = TRUE,
      stderr = FALSE
    )),
    error = function(e) character()
  )
  wait <- min(quota_wait_seconds(json), max_wait)
  if (wait <= 0) {
    return(FALSE)
  }
  message(sprintf(
    "[03-publish] GitHub API quota spent; waiting %d s for the reset",
    as.integer(ceiling(wait))
  ))
  Sys.sleep(wait)
  TRUE
}

# Runs `gh <args>` and returns its exit status. When it fails because
# the quota is spent, waits for the reset and runs it again, at most
# `quota_waits` times; any other failure is returned to the caller,
# whose own retries and errors stay as they were.
gh_quota_aware <- function(args, quota_waits = 2L, ...) {
  repeat {
    status <- system2("gh", args, ...)
    if (status == 0L || quota_waits < 1L || !wait_for_api_quota()) {
      return(status)
    }
    quota_waits <- quota_waits - 1L
  }
}
