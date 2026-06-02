# Audit the declared `first_year` of every yearly schema against the
# live CVM portal. Network-bound, run manually:
#
#   Rscript data-raw/audit-first-year.R
#
# Invariant: `first_year` MUST equal min(cvm_dataset_years(dataset)) —
# the earliest year the CVM directory listing serves. `first_year` is
# load-bearing: issuer_fetch()'s year-clamp rejects requested years below
# it, and the mirror ETL (stage 02b) enumerates expected (table, year)
# tuples from cvm_dataset_years(). If first_year sits ABOVE the listing
# minimum, the clamp drops years the portal publishes and the ETL hard-
# fails on the missing parquets; if it sits BELOW, issuer_fetch() lets a
# year through that then 404s. Either way the two must agree.
#
# cvm_dataset_years() is the authoritative oracle here because it reads
# the directory listing — the same source the ETL trusts. (An earlier
# version of this script HEAD-probed a window anchored at first_year - 5,
# which silently masked any data below that floor; do not reintroduce
# that approach.)
#
# For each flagged table the script also downloads the listing-minimum
# year's ZIP and checks the CSV header field count against the schema's
# expected_field_count, so a proposed correction is only reported when
# the older data actually reads under the current schema.

suppressMessages(pkgload::load_all())
library(httr2)

schemas_root <- "inst/extdata/schemas"

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
  rows[[length(rows) + 1L]] <- list(
    dataset  = s$dataset,
    table    = s$table,
    declared = as.integer(s$first_year),
    schema   = s
  )
}
message(sprintf("Found %d yearly schemas to audit.", length(rows)))

# --- listing minimum per dataset ------------------------------------

datasets <- unique(vapply(rows, `[[`, character(1L), "dataset"))
listing_min <- new.env(parent = emptyenv())
for (d in datasets) {
  years <- tryCatch(cvmdata::cvm_dataset_years(d), error = function(e) NULL)
  assign(d, if (is.null(years)) NA_integer_ else min(years), envir = listing_min)
  message(sprintf("  %-5s listing min = %s", d,
                  if (is.null(years)) "ERROR" else min(years)))
}

# --- field-count check at a given year ------------------------------

member_names <- function(schema, year) {
  pats <- if (!is.null(schema$cvm_file_pattern_variants)) {
    unlist(schema$cvm_file_pattern_variants, use.names = FALSE)
  } else {
    schema$cvm_file_pattern
  }
  gsub("\\{year\\}", year, pats)
}

header_matches <- function(schema, year) {
  url <- gsub("\\{year\\}", year, schema$cvm_archive_url_pattern)
  tmp <- tempfile(fileext = ".zip")
  on.exit(unlink(tmp), add = TRUE)
  resp <- tryCatch(
    req_perform(
      req_timeout(req_error(request(url), is_error = function(r) FALSE), 300),
      path = tmp
    ),
    error = function(e) NULL
  )
  if (is.null(resp) || resp_status(resp) >= 400L) {
    return(NA)
  }
  members <- tryCatch(utils::unzip(tmp, list = TRUE)$Name,
                      error = function(e) character(0))
  want <- tolower(member_names(schema, year))
  hit <- members[tolower(members) %in% want]
  if (!length(hit)) {
    return(NA)
  }
  exdir <- tempfile()
  dir.create(exdir)
  ex <- utils::unzip(tmp, files = hit[1L], exdir = exdir)
  con <- file(ex[1L], encoding = "latin1")
  hdr <- readLines(con, n = 1L, warn = FALSE)
  close(con)
  length(strsplit(hdr, ";", fixed = TRUE)[[1L]]) == schema$expected_field_count
}

# --- per-table verdict ----------------------------------------------

out <- data.frame(
  dataset = character(), table = character(), declared = integer(),
  listing_min = integer(), header_ok = character(), verdict = character(),
  stringsAsFactors = FALSE
)
for (r in rows) {
  lm <- get(r$dataset, envir = listing_min)
  header_ok <- NA
  if (!is.na(lm) && r$declared != lm) {
    header_ok <- header_matches(r$schema, lm)
  }
  verdict <- if (is.na(lm)) {
    "PROBE FAILED"
  } else if (r$declared == lm) {
    "OK"
  } else if (isTRUE(header_ok)) {
    sprintf("FIX: first_year %d -> %d (header matches)", r$declared, lm)
  } else if (isFALSE(header_ok)) {
    sprintf("REVIEW: listing min %d header != expected_field_count", lm)
  } else {
    sprintf("REVIEW: declared %d != listing min %d (header unverified)",
            r$declared, lm)
  }
  out <- rbind(out, data.frame(
    dataset = r$dataset, table = r$table, declared = r$declared,
    listing_min = lm, header_ok = as.character(header_ok),
    verdict = verdict, stringsAsFactors = FALSE
  ))
}

out <- out[order(out$dataset, out$table), ]
message("\n================ AUDIT RESULT ================")
print(out, row.names = FALSE)

flagged <- out[out$verdict != "OK", ]
if (nrow(flagged)) {
  message("\n>>> NEEDS ATTENTION:")
  print(flagged[, c("dataset", "table", "declared", "listing_min",
                    "verdict")], row.names = FALSE)
} else {
  message("\nAll first_year values equal the portal listing minimum.")
}
