# Retry policy of every network request the package makes (decision of
# 2026-11-05).
#
# httr2 retries 429 and 503 only. On 2026-11-05 the download host of
# GitHub Releases answered 504 for assets that were there (four times in
# one afternoon, with the status page all green) and each call gave up
# on the first answer: a `cvm_versions()` read, the article
# `data-defects` in the pkgdown build. The CVM portal fails the same way.
#
# What is tried again is a failure of the SERVER or of the connection:
# 429 (the server asks for a pause; httr2 honours `Retry-After`), the
# 5xx a healthy request can meet, and a request that produced no
# response. A 4xx is the package's own doing (a file that does not
# exist, a malformed URL, no permission): the same request brings the
# same answer, so it is reported at once and never retried.

# Statuses that say "not now", not "not ever".
.http_transient_statuses <- c(429L, 500L, 502L, 503L, 504L)

# Attempts per request, the first included. httr2 waits between them
# with exponential backoff and jitter: about 15 s in the worst case.
.http_max_tries <- 4L

# Whether a response is worth another attempt.
http_is_transient <- function(resp) {
  httr2::resp_status(resp) %in% .http_transient_statuses
}

# `req` under the package's retry policy.
req_retry_transient <- function(req) {
  httr2::req_retry(
    req,
    max_tries = .http_max_tries,
    is_transient = http_is_transient,
    retry_on_failure = TRUE
  )
}

# Whether a request ended, after every attempt, in a failure the policy
# retries. `x` is the condition httr2 raised (`httr2_http` carries the
# status; `httr2_failure` is a request with no response) or the status
# of a response read with `req_error(is_error = function(resp) FALSE)`.
http_failed_transiently <- function(x) {
  if (is.numeric(x)) {
    return(isTRUE(x %in% .http_transient_statuses))
  }
  if (inherits(x, "httr2_failure")) {
    return(TRUE)
  }
  inherits(x, "httr2_http") && isTRUE(x$status %in% .http_transient_statuses)
}

# Bullet for the error of a request that failed transiently: it says the
# request was repeated and that waiting helps. NULL for any other
# failure, where trying again would bring the same answer.
http_retry_hint <- function(x) {
  if (!http_failed_transiently(x)) {
    return(NULL)
  }
  c(
    "i" = sprintf(
      paste(
        "The server or the connection failed on each of %d attempts,",
        "which is usually temporary. Try again in a few minutes."
      ),
      .http_max_tries
    )
  )
}
