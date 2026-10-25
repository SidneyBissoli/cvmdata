# Public API of the mirror snapshot pin (decision of 2026-10-25).
#
# The `-latest` release of every dataset is rewritten in place each
# week. Since 2026-10-25 the ETL also publishes, on every run that
# changes something, a dated release
# `mirror-<group>-<dataset>-snapshot-<YYYY-MM-DD>` with the partitions
# that changed and a complete `__source_hash.json` that says where every
# partition of that day's mirror lives. The option `cvmdata.mirror_release`
# chooses which retrato the package reads: `"latest"` (the default) or a
# complete date, resolved to the most recent snapshot on or before it.
# Like `cvmdata.source`, it is a property of the session, not of one
# call: every `cvm_fetch()` and `cvm_versions()` of a script reads the
# same retrato, which is what reproducing a result needs.

#' Get the mirror snapshot the package reads
#'
#' @description
#' Reads the option `cvmdata.mirror_release`, falling back to `"latest"`
#' when the option is unset. The value says which copy of the parquet
#' mirror `source = "mirror"` reads:
#'
#' * `"latest"`: the release `mirror-<group>-<dataset>-latest`, rewritten
#'   in place by the weekly ETL. The default.
#' * A complete date, `"YYYY-MM-DD"`: the mirror as it was on that day.
#'   The package resolves it to the most recent dated snapshot published
#'   on or before the date and reads every partition from the release
#'   that holds it, so the same date always returns the same bytes. A
#'   date earlier than the first snapshot of a dataset is an error that
#'   names the earliest date available.
#'
#' Dated snapshots exist from 2026-10-27 on. Every tibble read from the
#' mirror carries the release it came from in the attribute `release`
#' (see [cvm_tbl]). [cvm_versions()] under a pinned date drops the
#' history rows superseded after that date, so its result is the set of
#' versions known on that day.
#'
#' @return A character scalar: `"latest"` or a date as `"YYYY-MM-DD"`.
#'
#' @examples
#' cvm_release_get()
#' @family source
#' @seealso [cvm_release_set()], [cvm_source_get()]
#' @export
cvm_release_get <- function() {
  check_release(
    getOption("cvmdata.mirror_release", "latest"),
    arg = "cvmdata.mirror_release"
  )
}

#' Pin the mirror to a dated snapshot
#'
#' @description
#' Sets the option `cvmdata.mirror_release`, which [cvm_fetch()] and
#' [cvm_versions()] consult on every call with `source = "mirror"`. Pass
#' a complete date to read the mirror as it was on that day, or
#' `"latest"` to follow the weekly refresh again. The pin is a property
#' of the session: set it once at the top of a script and every read
#' below it comes from the same snapshot. It has no effect on
#' `source = "cvm"`, which always reads the portal live.
#'
#' Switching snapshots re-downloads only the partitions whose bytes
#' differ between the two; the local cache verifies every parquet
#' against the SHA-256 the mirror publishes for it.
#'
#' @param release `"latest"`, or a complete date as `"YYYY-MM-DD"` or a
#'   [Date] of length one.
#'
#' @return The chosen value, invisibly, as a character scalar.
#'
#' @examplesIf interactive()
#' cvm_release_set("2026-11-01")
#' cvm_release_set("latest")
#' @family source
#' @seealso [cvm_release_get()], [cvm_source_set()]
#' @export
cvm_release_set <- function(release) {
  release <- check_release(release)
  options(cvmdata.mirror_release = release)
  cli::cli_inform(c(
    "v" = "Mirror release set to {.val {release}}."
  ))
  invisible(release)
}

# `"latest"`, or a complete date as `"YYYY-MM-DD"`; a `Date` of length
# one is formatted. Anything else is a `cvmdata_error_input`.
check_release <- function(
  release,
  arg = "release",
  call = rlang::caller_env()
) {
  if (inherits(release, "Date")) {
    if (length(release) == 1L && !is.na(release)) {
      return(format(release, "%Y-%m-%d"))
    }
    cvmdata_abort(
      "{.arg {arg}} must be a single, non-missing date.",
      class = "cvmdata_error_input",
      call = call
    )
  }
  if (
    !is.character(release) ||
      length(release) != 1L ||
      is.na(release) ||
      !nzchar(release)
  ) {
    cvmdata_abort(
      c(
        "{.arg {arg}} must be a single non-empty string.",
        "i" = "Use {.val latest} or a complete date {.val YYYY-MM-DD}."
      ),
      class = "cvmdata_error_input",
      call = call
    )
  }
  if (identical(release, "latest")) {
    return(release)
  }
  check_release_date(release, arg, call)
}

# A complete "YYYY-MM-DD" (the round trip through `as.Date()` rejects
# "2026-1-5" and the like).
check_release_date <- function(release, arg, call) {
  parsed <- as.Date(release, format = "%Y-%m-%d")
  if (is.na(parsed) || !identical(format(parsed, "%Y-%m-%d"), release)) {
    cvmdata_abort(
      c(
        "{.arg {arg}} must be {.val latest} or a complete date.",
        "x" = "Got {.val {release}}.",
        "i" = "Dates are written {.val YYYY-MM-DD}, e.g. {.val 2026-11-01}."
      ),
      class = "cvmdata_error_input",
      call = call
    )
  }
  release
}
