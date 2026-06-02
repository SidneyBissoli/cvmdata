# Audit schema-declared `first_year` against the live CVM open-data
# portal (dados.cvm.gov.br). Network-bound, run manually:
#
#   Rscript data-raw/audit-first-year.R
#
# Motivation: issuer_fetch() now clamps explicitly-requested years below
# a table's `first_year` *before* hitting the backend (see NEWS, the
# year-clamp feature). If a declared `first_year` is set too high the
# clamp silently drops years the portal actually serves. This script
# checks every yearly schema two ways:
#
#   1. HEAD-probe the per-dataset archive ZIP across a year window to find
#      `archive_first` — the lowest year whose ZIP the portal returns.
#      The clamp keys off this: ideally `first_year == archive_first`.
#
#   2. Member check (decisive): download the ZIP for `first_year - 1`
#      (only when that ZIP exists) and look for the table's own CSV
#      member. A member present there proves the table was published a
#      year earlier than declared, so the clamp would cut valid data.
#
# Output: one row per yearly table with declared / archive_first /
# member-below facts and a verdict. CSVs inside a ZIP can start later
# than the ZIP itself (staggered tables, e.g. composicao_capital), so a
# `first_year` above `archive_first` is not automatically wrong — the
# member check disambiguates.

library(httr2)

schemas_root <- "inst/extdata/schemas"
current_year <- as.integer(format(Sys.Date(), "%Y"))

# --- helpers ---------------------------------------------------------

# HTTP HEAD that returns the status code without throwing on 4xx/5xx.
# Memoised across the run so each (url) is probed at most once.
.head_cache <- new.env(parent = emptyenv())
head_status <- function(url) {
  if (!is.null(.head_cache[[url]])) {
    return(.head_cache[[url]])
  }
  req <- request(url) |>
    req_method("HEAD") |>
    req_error(is_error = function(resp) FALSE) |>
    req_timeout(30)
  resp <- tryCatch(req_perform(req), error = function(e) NULL)
  status <- if (is.null(resp)) NA_integer_ else resp_status(resp)
  .head_cache[[url]] <- status
  status
}

# Download a ZIP and list its members; NULL on any failure. Memoised.
.members_cache <- new.env(parent = emptyenv())
zip_members <- function(url) {
  key <- url
  if (exists(key, envir = .members_cache)) {
    return(get(key, envir = .members_cache))
  }
  tmp <- tempfile(fileext = ".zip")
  on.exit(unlink(tmp), add = TRUE)
  req <- request(url) |>
    req_error(is_error = function(resp) FALSE) |>
    req_timeout(300)
  resp <- tryCatch(req_perform(req, path = tmp), error = function(e) NULL)
  members <- if (is.null(resp) || resp_status(resp) >= 400L) {
    NULL
  } else {
    tryCatch(utils::unzip(tmp, list = TRUE)$Name, error = function(e) NULL)
  }
  assign(key, members, envir = .members_cache)
  members
}

# The CSV member name(s) a table expects for a given year. Tables with an
# ind/con split carry `cvm_file_pattern_variants`; the rest a single
# `cvm_file_pattern`.
member_names <- function(schema, year) {
  pats <- if (!is.null(schema$cvm_file_pattern_variants)) {
    unlist(schema$cvm_file_pattern_variants, use.names = FALSE)
  } else {
    schema$cvm_file_pattern
  }
  gsub("\\{year\\}", year, pats)
}

url_for_year <- function(pattern, year) {
  gsub("\\{year\\}", year, pattern)
}

# --- collect yearly schemas -----------------------------------------

yaml_files <- list.files(
  schemas_root, pattern = "\\.yaml$", recursive = TRUE, full.names = TRUE
)

rows <- list()
for (path in yaml_files) {
  s <- yaml::read_yaml(path)
  if (!identical(s$temporal_partitioning, "yearly")) {
    next
  }
  rel <- sub(paste0("^", schemas_root, "/"), "", path)
  group <- strsplit(rel, "/")[[1L]][[1L]]
  rows[[length(rows) + 1L]] <- list(
    group        = group,
    dataset      = s$dataset,
    table        = s$table,
    declared     = as.integer(s$first_year),
    archive_url  = s$cvm_archive_url_pattern,
    schema       = s
  )
}
message(sprintf("Found %d yearly schemas to audit.", length(rows)))

# --- HEAD-probe each unique archive pattern -------------------------

patterns <- unique(vapply(rows, `[[`, character(1L), "archive_url"))
archive_first <- new.env(parent = emptyenv())
for (pat in patterns) {
  declared_here <- vapply(
    Filter(function(r) identical(r$archive_url, pat), rows),
    `[[`, integer(1L), "declared"
  )
  lo <- min(declared_here) - 5L
  window <- seq.int(max(lo, 2000L), current_year + 1L)
  message(sprintf("HEAD-probing %s  [%d..%d]",
                  sub(".*/DOC/([^/]+)/.*", "\\1", pat),
                  min(window), max(window)))
  existing <- integer(0L)
  for (y in window) {
    if (head_status(url_for_year(pat, y)) == 200L) {
      existing <- c(existing, y)
    }
  }
  assign(pat, if (length(existing)) min(existing) else NA_integer_,
         envir = archive_first)
}

# --- per-table verdict ----------------------------------------------

out <- data.frame(
  group = character(), dataset = character(), table = character(),
  declared = integer(), archive_first = integer(),
  member_below = character(), verdict = character(),
  stringsAsFactors = FALSE
)

for (r in rows) {
  af <- get(r$archive_url, envir = archive_first)
  prev <- r$declared - 1L
  prev_url <- url_for_year(r$archive_url, prev)

  # Member check only when the ZIP for first_year - 1 actually exists.
  member_below <- NA
  if (!is.na(af) && prev >= af) {
    members <- zip_members(prev_url)
    if (!is.null(members)) {
      wanted <- tolower(member_names(r$schema, prev))
      member_below <- any(tolower(members) %in% wanted)
    }
  }

  verdict <- if (is.na(af)) {
    "PROBE FAILED (no ZIP found in window)"
  } else if (r$declared < af) {
    "TOO LOW (declared year's ZIP 404s; fetch would error)"
  } else if (isTRUE(member_below)) {
    "TOO HIGH (member exists at first_year-1; clamp cuts valid data)"
  } else if (r$declared > af) {
    "OK? (ZIP exists earlier but member absent — staggered table)"
  } else {
    "OK (declared == archive_first)"
  }

  out <- rbind(out, data.frame(
    group = r$group, dataset = r$dataset, table = r$table,
    declared = r$declared, archive_first = af,
    member_below = as.character(member_below), verdict = verdict,
    stringsAsFactors = FALSE
  ))
}

out <- out[order(out$dataset, out$table), ]
message("\n================ AUDIT RESULT ================")
print(out, row.names = FALSE)

flagged <- out[grepl("^TOO|FAILED", out$verdict), ]
if (nrow(flagged)) {
  message("\n>>> NEEDS ATTENTION:")
  print(flagged[, c("dataset", "table", "declared",
                    "archive_first", "verdict")], row.names = FALSE)
} else {
  message("\nAll declared first_year values are consistent with the portal.")
}
