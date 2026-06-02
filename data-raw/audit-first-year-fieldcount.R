# Spot-check: does the CSV header at the proposed (lower) first_year
# carry the same field count the schema declares? If not, lowering
# first_year would expose years that fail strict validation, and the
# correct fix is different (keep first_year high, or relax). Run after
# audit-first-year-deep.R.

library(httr2)

check <- function(dataset, table, year, member) {
  s <- yaml::read_yaml(
    sprintf("inst/extdata/schemas/companhias/%s/%s.yaml", dataset, table)
  )
  url <- gsub("\\{year\\}", year, s$cvm_archive_url_pattern)
  tmp <- tempfile(fileext = ".zip")
  on.exit(unlink(tmp), add = TRUE)
  resp <- req_perform(
    req_timeout(req_error(request(url), is_error = function(r) FALSE), 300),
    path = tmp
  )
  if (resp_status(resp) >= 400L) {
    cat(sprintf("%-5s %-12s y=%d  NO ZIP\n", dataset, table, year))
    return(invisible())
  }
  members <- utils::unzip(tmp, list = TRUE)$Name
  hit <- members[tolower(members) == tolower(member)]
  if (!length(hit)) {
    cat(sprintf("%-5s %-12s y=%d  MEMBER MISSING (have: %s)\n",
                dataset, table, year, paste(members, collapse = ", ")))
    return(invisible())
  }
  exdir <- tempfile()
  dir.create(exdir)
  ex <- utils::unzip(tmp, files = hit[1L], exdir = exdir)
  con <- file(ex[1L], encoding = "latin1")
  hdr <- readLines(con, n = 1L, warn = FALSE)
  close(con)
  n <- length(strsplit(hdr, ";", fixed = TRUE)[[1L]])
  cat(sprintf("%-5s %-12s y=%d  header=%2d  expected=%2d  %s\n",
              dataset, table, year, n, s$expected_field_count,
              if (n == s$expected_field_count) "MATCH" else "*** MISMATCH ***"))
}

check("fca",  "geral",       2016L, "fca_cia_aberta_geral_2016.csv")
check("ipe",  "ipe",         2016L, "ipe_cia_aberta_2016.csv")
check("cgvn", "praticas",    2018L, "cgvn_cia_aberta_praticas_2018.csv")
check("vlmo", "consolidado", 2018L, "vlmo_cia_aberta_con_2018.csv")
