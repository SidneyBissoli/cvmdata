# Smoke test of the ETL image, run inside it by etl-image.yaml before the
# push, with the repository checkout as the working directory.
#
# The package list is NOT repeated here: it is derived from the source of
# the robots (every `pkg::` in inst/etl/*.R plus the DESCRIPTION), so a new
# dependency of the ETL fails this test on the pull request instead of
# failing a robot at night.

stopifnot(file.exists("DESCRIPTION"), dir.exists("inst/etl"))

fail <- character()
check <- function(ok, what) {
  cat(if (ok) "ok  " else "FAIL", what, "\n")
  if (!ok) fail <<- c(fail, what)
}

# 1. The R of the image.
check(
  getRversion() == "4.6.2",
  sprintf("R version %s", getRversion())
)

# 2. CRAN is the dated snapshot, never `latest`.
repo <- getOption("repos")[["CRAN"]]
check(
  grepl("/cran/__linux__/[a-z]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", repo),
  sprintf("CRAN pinned to a dated P3M snapshot (%s)", repo)
)

# 3. Every package the ETL calls, read from the scripts by the R parser:
#    only a `pkg::` in code is a SYMBOL_PACKAGE token. A regex also caught
#    the text of messages and comments ("reinstall the package
#    (devtools::install())", an escaped "ável::" in a string).
etl <- list.files("inst/etl", pattern = "\\.R$", full.names = TRUE)
used <- unique(unlist(lapply(etl, function(f) {
  pd <- utils::getParseData(parse(f, keep.source = TRUE))
  pd$text[pd$token == "SYMBOL_PACKAGE"]
})))
base <- rownames(installed.packages(priority = "base"))
needed <- setdiff(used, c(base, "cvmdata"))
for (pkg in sort(needed)) {
  check(requireNamespace(pkg, quietly = TRUE), sprintf("package %s", pkg))
}

# 4. The hard dependencies of the package, read from DESCRIPTION.
desc <- read.dcf("DESCRIPTION", fields = c("Depends", "Imports"))
deps <- unlist(strsplit(paste(desc[!is.na(desc)], collapse = ","), ","))
deps <- trimws(sub("\\(.*\\)", "", trimws(deps)))
deps <- setdiff(deps[nzchar(deps)], c("R", base))
for (pkg in sort(deps)) {
  check(requireNamespace(pkg, quietly = TRUE), sprintf("import %s", pkg))
}

# 5. The external commands.
for (cmd in c("gh", "git")) {
  check(nzchar(Sys.which(cmd)), sprintf("command %s", cmd))
}

# 6. utils::unzip() goes to Info-ZIP: the internal unzip skips Deflate64
#    members of the CVM archives with only a warning.
uz <- getOption("unzip")
check(
  !identical(uz, "internal") && nzchar(Sys.which(uz)),
  sprintf("utils::unzip() uses an external unzip (%s)", uz)
)

# 7. The package installs from the checkout with no network, the way the
#    robots install it, and loads.
lib <- tempfile("lib")
dir.create(lib)
status <- system2(
  file.path(R.home("bin"), "R"),
  c("CMD", "INSTALL", "--no-docs", "--no-multiarch", "-l", lib, "."),
  stdout = FALSE,
  stderr = FALSE
)
check(status == 0L, "R CMD INSTALL of the checkout")
if (status == 0L) {
  check(
    requireNamespace("cvmdata", lib.loc = lib, quietly = TRUE),
    "cvmdata loads"
  )
}

# 8. Every ETL script parses.
for (f in etl) {
  ok <- tryCatch(
    {
      parse(f)
      TRUE
    },
    error = function(e) FALSE
  )
  check(ok, sprintf("parse %s", basename(f)))
}

if (length(fail) > 0L) {
  cat("\n", length(fail), "check(s) failed\n")
  quit(status = 1L)
}
cat("\nall checks passed\n")
