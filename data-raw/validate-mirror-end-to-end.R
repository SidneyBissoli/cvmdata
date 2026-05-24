# Tarefa C of Sessao 3.13 — end-to-end validation that the mirror
# backend returns a tibble equivalent to the `source = "cvm"` path.
#
# Run with: Rscript data-raw/validate-mirror-end-to-end.R
# Requires: live internet, CVM portal + GitHub Releases reachable.
#
# Output: a 4-row table comparing `source = "cvm"` vs
# `source = "mirror"` for one call per dataset (cad/dfp/itr/fre).

stopifnot(requireNamespace("devtools", quietly = TRUE))
devtools::load_all(quiet = TRUE)

# Use a scratch cache so the validation does not pollute the user's
# real cache and so both backends start cold.
options(
  cvmdata.cache_dir = file.path(tempdir(), "validate-mirror"),
  cvmdata.cache_ttl_seconds = Inf
)
unlink(getOption("cvmdata.cache_dir"), recursive = TRUE, force = TRUE)
dir.create(getOption("cvmdata.cache_dir"), recursive = TRUE,
           showWarnings = FALSE)

cases <- list(
  list(
    label = "cad/companhias",
    args = list(dataset = "cad", table = "companhias")
  ),
  list(
    label = "dfp/bpa ind 2024",
    args = list(dataset = "dfp", table = "bpa",
                report_type = "ind", years = 2024L)
  ),
  list(
    label = "itr/dre con (latest)",
    args = list(dataset = "itr", table = "dre",
                report_type = "con")
  ),
  list(
    label = "fre/posicao_acionaria 2024 (PETROBRAS)",
    args = list(dataset = "fre", table = "posicao_acionaria",
                years = 2024L, companies = "PETROBRAS")
  )
)

run_case <- function(case, source) {
  args <- c(case$args, list(source = source))
  res <- tryCatch(
    do.call(cvm_fetch, args),
    error = function(e) {
      list(error = conditionMessage(e), class = class(e)[[1L]])
    }
  )
  if (!is.null(res$error)) {
    return(list(ok = FALSE, error = res$error))
  }
  list(
    ok = TRUE,
    nrow = nrow(res),
    cols = names(res),
    types = vapply(res, function(c) class(c)[[1L]], character(1L))
  )
}

results <- list()
for (case in cases) {
  message(sprintf("\n[case] %s", case$label))
  message("  -> source = cvm")
  cvm_res <- run_case(case, "cvm")
  message("  -> source = mirror")
  mir_res <- run_case(case, "mirror")
  if (cvm_res$ok && mir_res$ok) {
    # The mirror reattaches `year` and `report_type` derived from the
    # asset name. The CVM-HTTP path carries them too (year via the
    # explicit argument; report_type via column when present). For a
    # like-for-like comparison drop the partition columns the mirror
    # adds when the CVM path doesn't have them.
    common <- intersect(cvm_res$cols, mir_res$cols)
    cvm_only <- setdiff(cvm_res$cols, mir_res$cols)
    mir_only <- setdiff(mir_res$cols, cvm_res$cols)
    types_eq <- identical(
      cvm_res$types[common], mir_res$types[common]
    )
    results[[length(results) + 1L]] <- data.frame(
      chamada = case$label,
      n_rows_cvm = cvm_res$nrow,
      n_rows_mirror = mir_res$nrow,
      colunas_iguais = identical(cvm_res$cols, mir_res$cols),
      tipos_iguais = types_eq,
      cvm_only = paste(cvm_only, collapse = ","),
      mirror_only = paste(mir_only, collapse = ","),
      stringsAsFactors = FALSE
    )
  } else {
    results[[length(results) + 1L]] <- data.frame(
      chamada = case$label,
      n_rows_cvm = if (cvm_res$ok) cvm_res$nrow else NA_integer_,
      n_rows_mirror = if (mir_res$ok) mir_res$nrow else NA_integer_,
      colunas_iguais = NA, tipos_iguais = NA,
      cvm_only = if (cvm_res$ok) "" else paste("ERROR:", cvm_res$error),
      mirror_only = if (mir_res$ok) "" else paste("ERROR:", mir_res$error),
      stringsAsFactors = FALSE
    )
  }
}

tbl <- do.call(rbind, results)
cat("\n\n=== Equivalencia CVM vs Mirror ===\n")
print(tbl, row.names = FALSE)
saveRDS(tbl, "data-raw/validate-mirror-end-to-end.rds")
cat("\nSaved to data-raw/validate-mirror-end-to-end.rds\n")
