# Follow-up to audit-first-year.R for the datasets it flagged TOO HIGH.
# For each (dataset, table) it walks ZIP years upward from a floor and
# records the first year whose archive contains the table's CSV member —
# the true `first_year` the schema should declare. One ZIP download per
# (dataset, year); all of that dataset's tables are checked against it.
#
#   Rscript data-raw/audit-first-year-deep.R

library(httr2)

schemas_root <- "inst/extdata/schemas"
current_year <- as.integer(format(Sys.Date(), "%Y"))

# Datasets flagged by the HEAD-level audit, with the floor year to start
# probing members from (the archive_first it reported).
targets <- list(
  list(dataset = "fca",  floor = 2016L),
  list(dataset = "ipe",  floor = 2016L),
  list(dataset = "cgvn", floor = 2018L),
  list(dataset = "vlmo", floor = 2018L)
)

zip_members <- function(url) {
  tmp <- tempfile(fileext = ".zip")
  on.exit(unlink(tmp), add = TRUE)
  req <- request(url) |>
    req_error(is_error = function(resp) FALSE) |>
    req_timeout(300)
  resp <- tryCatch(req_perform(req, path = tmp), error = function(e) NULL)
  if (is.null(resp) || resp_status(resp) >= 400L) {
    return(NULL)
  }
  tryCatch(utils::unzip(tmp, list = TRUE)$Name, error = function(e) NULL)
}

member_names <- function(schema, year) {
  pats <- if (!is.null(schema$cvm_file_pattern_variants)) {
    unlist(schema$cvm_file_pattern_variants, use.names = FALSE)
  } else {
    schema$cvm_file_pattern
  }
  gsub("\\{year\\}", year, pats)
}

load_dataset_schemas <- function(dataset) {
  dir <- file.path(schemas_root, "companhias", dataset)
  files <- list.files(dir, pattern = "\\.yaml$", full.names = TRUE)
  lapply(files, yaml::read_yaml)
}

out <- data.frame(
  dataset = character(), table = character(), declared = integer(),
  member_first = integer(), stringsAsFactors = FALSE
)

for (t in targets) {
  schemas <- load_dataset_schemas(t$dataset)
  pattern <- schemas[[1L]]$cvm_archive_url_pattern
  # First member year still unknown for each table.
  found <- stats::setNames(
    rep(NA_integer_, length(schemas)),
    vapply(schemas, `[[`, character(1L), "table")
  )
  for (y in seq.int(t$floor, current_year)) {
    if (!anyNA(found)) {
      break
    }
    url <- gsub("\\{year\\}", y, pattern)
    members <- zip_members(url)
    message(sprintf("  %s %d: %s", t$dataset, y,
                    if (is.null(members)) "no ZIP" else
                      paste(length(members), "members")))
    if (is.null(members)) {
      next
    }
    members_lc <- tolower(members)
    for (s in schemas) {
      if (!is.na(found[[s$table]])) {
        next
      }
      if (any(tolower(member_names(s, y)) %in% members_lc)) {
        found[[s$table]] <- y
      }
    }
  }
  for (s in schemas) {
    out <- rbind(out, data.frame(
      dataset = t$dataset, table = s$table,
      declared = as.integer(s$first_year),
      member_first = found[[s$table]], stringsAsFactors = FALSE
    ))
  }
}

out <- out[order(out$dataset, out$table), ]
out$action <- ifelse(
  is.na(out$member_first), "MEMBER NOT FOUND IN WINDOW",
  ifelse(out$declared == out$member_first, "ok",
         sprintf("change first_year %d -> %d", out$declared,
                 out$member_first))
)
message("\n============ TRUE FIRST MEMBER YEAR ============")
print(out, row.names = FALSE)
