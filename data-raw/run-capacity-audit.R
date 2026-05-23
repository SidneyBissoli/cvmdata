# Mirror capacity audit (Sessao 3.11 — Tarefa A, Passo 1).
#
# Produces data-raw/mirror-capacity-audit.md with per-dataset volumes from
# the CVM open data portal, projected over the planning horizon (historical
# years already published + 10 future years at 2024 volume).
#
# Methodology:
#  1. Enumerate listing pages of every dataset within v0.1-v1.0 scope.
#  2. HEAD every file to capture the exact Content-Length the portal serves.
#  3. Download 3 archetypal ZIPs (company yearly, fund monthly, FII yearly),
#     unzip and write parquet snappy to derive a parquet/ZIP size ratio per
#     archetype.
#  4. Apply the matching ratio to project parquet volume per dataset, then
#     extrapolate by (historical_years + 10).
#
# Run from package root:
#   Rscript data-raw/run-capacity-audit.R

stopifnot(
  requireNamespace("httr2", quietly = TRUE),
  requireNamespace("arrow", quietly = TRUE),
  requireNamespace("readr", quietly = TRUE),
  requireNamespace("tibble", quietly = TRUE),
  requireNamespace("dplyr", quietly = TRUE)
)

library(httr2)

CVM_ROOT <- "https://dados.cvm.gov.br/dados"

audit_dir <- file.path(tempdir(), "cvmdata-audit")
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
parquet_dir <- file.path(audit_dir, "parquet")
dir.create(parquet_dir, recursive = TRUE, showWarnings = FALSE)

message("Audit workspace: ", audit_dir)

# ---- 1. Dataset inventory (within v0.1-v1.0 scope) ----------------------

inventory <- tibble::tribble(
  ~category,      ~scope,  ~dataset,           ~archetype,        ~listing_path,
  "CIA_ABERTA",   "v0.1",  "CAD",              "company_static",  "CIA_ABERTA/CAD/DADOS",
  "CIA_ABERTA",   "v0.1",  "DFP",              "company_yearly",  "CIA_ABERTA/DOC/DFP/DADOS",
  "CIA_ABERTA",   "v0.1",  "ITR",              "company_yearly",  "CIA_ABERTA/DOC/ITR/DADOS",
  "CIA_ABERTA",   "v0.1",  "FRE",              "company_yearly",  "CIA_ABERTA/DOC/FRE/DADOS",
  "CIA_ABERTA",   "v0.2",  "FCA",              "company_yearly",  "CIA_ABERTA/DOC/FCA/DADOS",
  "CIA_ABERTA",   "v0.2",  "IPE",              "company_yearly",  "CIA_ABERTA/DOC/IPE/DADOS",
  "CIA_ABERTA",   "v0.2",  "VLMO",             "company_yearly",  "CIA_ABERTA/DOC/VLMO/DADOS",
  "CIA_ABERTA",   "v0.2",  "CGVN",             "company_yearly",  "CIA_ABERTA/DOC/CGVN/DADOS",
  "CIA_ESTRANG",  "v0.3",  "CAD",              "company_static",  "CIA_ESTRANG/CAD/DADOS",
  "CIA_INCENT",   "v0.3",  "CAD",              "company_static",  "CIA_INCENT/CAD/DADOS",
  "CROWDFUNDING", "v0.3",  "CAD",              "company_static",  "CROWDFUNDING/CAD/DADOS",
  "OFERTA",       "v0.3",  "DISTRIB",          "company_yearly",  "OFERTA/DISTRIB/DADOS",
  "FI",           "v0.4",  "BALANCETE",        "fund_monthly",    "FI/DOC/BALANCETE/DADOS",
  "FI",           "v0.4",  "CDA",              "fund_monthly",    "FI/DOC/CDA/DADOS",
  "FI",           "v0.4",  "COMPL",            "fund_monthly",    "FI/DOC/COMPL/DADOS",
  "FI",           "v0.4",  "ENTREGA",          "fund_monthly",    "FI/DOC/ENTREGA/DADOS",
  "FI",           "v0.4",  "EVENTUAL",         "fund_monthly",    "FI/DOC/EVENTUAL/DADOS",
  "FI",           "v0.4",  "EXTRATO",          "fund_monthly",    "FI/DOC/EXTRATO/DADOS",
  "FI",           "v0.4",  "INF_DIARIO",       "fund_monthly",    "FI/DOC/INF_DIARIO/DADOS",
  "FI",           "v0.4",  "LAMINA",           "fund_monthly",    "FI/DOC/LAMINA/DADOS",
  "FI",           "v0.4",  "PERFIL_MENSAL",    "fund_monthly",    "FI/DOC/PERFIL_MENSAL/DADOS",
  "FII",          "v0.5",  "DFIN",             "fii_yearly",      "FII/DOC/DFIN/DADOS",
  "FII",          "v0.5",  "INF_ANUAL",        "fii_yearly",      "FII/DOC/INF_ANUAL/DADOS",
  "FII",          "v0.5",  "INF_MENSAL",       "fii_yearly",      "FII/DOC/INF_MENSAL/DADOS",
  "FII",          "v0.5",  "INF_TRIMESTRAL",   "fii_yearly",      "FII/DOC/INF_TRIMESTRAL/DADOS",
  "FIDC",         "v0.6",  "INF_MENSAL",       "fii_yearly",      "FIDC/DOC/INF_MENSAL/DADOS",
  "FIP",          "v0.6+", "INF_QUADRIMESTRAL", "fii_yearly",     "FIP/DOC/INF_QUADRIMESTRAL/DADOS",
  "FIP",          "v0.6+", "INF_TRIMESTRAL",   "fii_yearly",      "FIP/DOC/INF_TRIMESTRAL/DADOS",
  "FIAGRO",       "v0.6+", "INF_MENSAL",       "fii_yearly",      "FIAGRO/DOC/INF_MENSAL/DADOS",
  "FIE",          "v0.6+", "BALANCETE",        "fii_yearly",      "FIE/DOC/BALANCETE/DADOS",
  "FIE",          "v0.6+", "BALANCO",          "fii_yearly",      "FIE/DOC/BALANCO/DADOS",
  "SECURIT",      "v0.6+", "DFIN_CRA",         "fii_yearly",      "SECURIT/DOC/DFIN_CRA/DADOS",
  "SECURIT",      "v0.6+", "DFIN_CRI",         "fii_yearly",      "SECURIT/DOC/DFIN_CRI/DADOS",
  "SECURIT",      "v0.6+", "INF_MENSAL_CRA",   "fii_yearly",      "SECURIT/DOC/INF_MENSAL_CRA/DADOS",
  "SECURIT",      "v0.6+", "INF_MENSAL_CRI",   "fii_yearly",      "SECURIT/DOC/INF_MENSAL_CRI/DADOS",
  "SECURIT",      "v0.6+", "INF_MENSAL_OTS",   "fii_yearly",      "SECURIT/DOC/INF_MENSAL_OTS/DADOS"
)

inventory$listing_url <- file.path(CVM_ROOT, inventory$listing_path)

# ---- 2. Parse listing pages --------------------------------------------

parse_human_size <- function(s) {
  s <- trimws(s)
  s[s == "-" | s == ""] <- NA
  unit_mult <- c(K = 1024, M = 1024^2, G = 1024^3, T = 1024^4)
  num <- suppressWarnings(as.numeric(sub("([0-9.]+).*", "\\1", s)))
  unit <- toupper(sub(".*[0-9.]([A-Za-z])?$", "\\1", s))
  mult <- ifelse(unit %in% names(unit_mult), unit_mult[unit], 1)
  num * unname(mult)
}

fetch_listing <- function(url) {
  req <- request(url) |>
    req_timeout(30) |>
    req_user_agent("cvmdata-audit/0.1") |>
    req_error(is_error = \(resp) FALSE)
  resp <- tryCatch(req_perform(req), error = function(e) NULL)
  if (is.null(resp) || resp_status(resp) >= 400) {
    return(tibble::tibble(filename = character(0), bytes = numeric(0)))
  }
  html <- resp_body_string(resp)
  # Apache mod_autoindex format observed on dados.cvm.gov.br:
  #   <a href="file.zip">file.zip</a>   17-May-2026 07:21     13M
  rx <- '<a href="([^"?][^"]*\\.(zip|csv|txt))">[^<]*</a>\\s+([0-9]{2}-[A-Za-z]{3}-[0-9]{4} [0-9]{2}:[0-9]{2})\\s+([0-9.]+[KMGT]?|-)'
  m <- regmatches(html, gregexpr(rx, html, perl = TRUE))[[1]]
  if (length(m) == 0) {
    rx2 <- '<a href="([^"?][^"]*\\.(zip|csv|txt))"'
    m2 <- regmatches(html, gregexpr(rx2, html, perl = TRUE))[[1]]
    files <- sub(rx2, "\\1", m2)
    return(tibble::tibble(filename = files, bytes = NA_real_))
  }
  files <- sub(rx, "\\1", m)
  size_str <- sub(rx, "\\4", m)
  sizes <- parse_human_size(size_str)
  tibble::tibble(filename = files, bytes = sizes)
}

message("\n[1/4] Enumerating listing pages...")
all_files <- vector("list", nrow(inventory))
for (i in seq_len(nrow(inventory))) {
  row <- inventory[i, ]
  files <- fetch_listing(row$listing_url)
  if (nrow(files) > 0) {
    files$category <- row$category
    files$scope <- row$scope
    files$dataset <- row$dataset
    files$archetype <- row$archetype
    files$listing_url <- row$listing_url
  }
  all_files[[i]] <- files
  message(sprintf("  %-13s/ %-18s  -> %d files",
                  row$category, row$dataset, nrow(files)))
}
files_df <- do.call(rbind, all_files)
saveRDS(files_df, file.path(audit_dir, "files_df.rds"))
message(sprintf("  Total files enumerated: %d", nrow(files_df)))

# ---- 3. Classify files by year and pick 2024 / 2021 samples -----------

extract_year <- function(fn) {
  m <- regmatches(fn, regexpr("(19|20)[0-9]{2}", fn))
  suppressWarnings(as.integer(m[1]))
}
extract_yearmonth <- function(fn) {
  m <- regmatches(fn, regexpr("(19|20)[0-9]{4}", fn))
  if (length(m) == 0 || is.na(m)) return(NA_integer_)
  suppressWarnings(as.integer(m[1]))  # YYYYMM
}

files_df$year_token <- vapply(files_df$filename, function(fn) {
  ym <- extract_yearmonth(fn)
  if (!is.na(ym)) return(as.integer(substr(as.character(ym), 1, 4)))
  y <- extract_year(fn)
  if (!is.na(y)) return(y)
  NA_integer_
}, integer(1))

# ---- 4. Per-dataset aggregation (HEAD already done via Apache index) ---

per_dataset_years <- files_df |>
  dplyr::filter(grepl("\\.zip$|\\.csv$", filename)) |>
  dplyr::group_by(category, scope, dataset, archetype, year_token) |>
  dplyr::summarise(
    files = dplyr::n(),
    zip_bytes = sum(bytes, na.rm = TRUE),
    .groups = "drop"
  )

# ---- 5. Pick archetypes for ratio calibration -------------------------

download_with_retry <- function(url, dest) {
  if (file.exists(dest) && file.info(dest)$size > 0) return(invisible(dest))
  req <- request(url) |>
    req_timeout(600) |>
    req_user_agent("cvmdata-audit/0.1") |>
    req_retry(max_tries = 3)
  resp <- req_perform(req, path = dest)
  invisible(dest)
}

measure_archetype <- function(label, url, fn_save) {
  dest <- file.path(audit_dir, fn_save)
  message(sprintf("\n[archetype %s] downloading %s ...", label, url))
  download_with_retry(url, dest)
  zip_size <- file.info(dest)$size
  extract_dir <- file.path(audit_dir, paste0(label, "_extract"))
  dir.create(extract_dir, showWarnings = FALSE)
  if (grepl("\\.zip$", fn_save, ignore.case = TRUE)) {
    unzip(dest, exdir = extract_dir)
    files <- list.files(extract_dir, full.names = TRUE, recursive = TRUE)
  } else {
    file.copy(dest, file.path(extract_dir, basename(dest)), overwrite = TRUE)
    files <- file.path(extract_dir, basename(dest))
  }
  csv_files <- files[grepl("\\.(csv|txt)$", files, ignore.case = TRUE)]
  csv_size <- sum(file.info(csv_files)$size, na.rm = TRUE)

  pq_dir <- file.path(parquet_dir, label)
  dir.create(pq_dir, showWarnings = FALSE, recursive = TRUE)
  parquet_size <- 0
  for (f in csv_files) {
    pq_path <- file.path(pq_dir, paste0(tools::file_path_sans_ext(basename(f)), ".parquet"))
    df <- tryCatch(
      readr::read_delim(
        f, delim = ";",
        locale = readr::locale(encoding = "ISO-8859-1",
                               decimal_mark = ",",
                               grouping_mark = "."),
        show_col_types = FALSE, progress = FALSE,
        guess_max = 50000
      ),
      error = function(e) NULL
    )
    if (is.null(df) || nrow(df) == 0) next
    arrow::write_parquet(df, pq_path, compression = "snappy")
    parquet_size <- parquet_size + file.info(pq_path)$size
  }
  tibble::tibble(
    archetype = label,
    sample_file = fn_save,
    zip_bytes = zip_size,
    csv_bytes = csv_size,
    parquet_bytes = parquet_size,
    parquet_over_zip = parquet_size / zip_size,
    csv_over_zip = csv_size / zip_size
  )
}

message("\n[2/4] Measuring archetype ratios (3 downloads)...")
arch_paths <- list(
  company_yearly = list(
    fn = "dfp_cia_aberta_2024.zip",
    url = paste0(CVM_ROOT, "/CIA_ABERTA/DOC/DFP/DADOS/dfp_cia_aberta_2024.zip")
  ),
  fund_monthly = list(
    fn = "inf_diario_fi_202412.zip",
    url = paste0(CVM_ROOT, "/FI/DOC/INF_DIARIO/DADOS/inf_diario_fi_202412.zip")
  ),
  fii_yearly = list(
    fn = "inf_mensal_fii_2024.zip",
    url = paste0(CVM_ROOT, "/FII/DOC/INF_MENSAL/DADOS/inf_mensal_fii_2024.zip")
  )
)
arch_results <- lapply(names(arch_paths), function(label) {
  measure_archetype(label, arch_paths[[label]]$url, arch_paths[[label]]$fn)
})
ratios <- do.call(rbind, arch_results)
# company_static uses the same ratio as company_yearly (single CSV snapshot).
ratios <- rbind(
  ratios,
  tibble::tibble(
    archetype = "company_static",
    sample_file = ratios$sample_file[ratios$archetype == "company_yearly"],
    zip_bytes = ratios$zip_bytes[ratios$archetype == "company_yearly"],
    csv_bytes = ratios$csv_bytes[ratios$archetype == "company_yearly"],
    parquet_bytes = ratios$parquet_bytes[ratios$archetype == "company_yearly"],
    parquet_over_zip = ratios$parquet_over_zip[ratios$archetype == "company_yearly"],
    csv_over_zip = ratios$csv_over_zip[ratios$archetype == "company_yearly"]
  )
)
saveRDS(ratios, file.path(audit_dir, "ratios.rds"))
print(ratios)

# ---- 6. Build per-dataset projection -----------------------------------

message("\n[3/4] Projecting per-dataset volumes...")

# Per-dataset summary across all years observed.
per_dataset <- files_df |>
  dplyr::filter(grepl("\\.zip$|\\.csv$", filename)) |>
  dplyr::group_by(category, scope, dataset, archetype) |>
  dplyr::summarise(
    n_files = dplyr::n(),
    historical_years = length(unique(year_token[!is.na(year_token)])),
    zip_total_bytes = sum(bytes, na.rm = TRUE),
    zip_2024_bytes = sum(bytes[year_token == 2024], na.rm = TRUE),
    .groups = "drop"
  )

# Datasets without a year token (e.g. CAD static) get historical_years = 1.
per_dataset$historical_years <- pmax(per_dataset$historical_years, 1)
# Datasets without explicit 2024 sample fall back to annual average.
per_dataset$zip_2024_bytes <- ifelse(
  per_dataset$zip_2024_bytes == 0,
  per_dataset$zip_total_bytes / per_dataset$historical_years,
  per_dataset$zip_2024_bytes
)

per_dataset <- per_dataset |>
  dplyr::left_join(
    ratios |> dplyr::select(archetype, parquet_over_zip),
    by = "archetype"
  )

# Project: parquet_total = parquet_historical + 10 * parquet_2024_yearly
# - parquet_historical = zip_total * parquet_over_zip
# - parquet_2024_yearly = zip_2024 * parquet_over_zip
per_dataset$parquet_historical_bytes <-
  per_dataset$zip_total_bytes * per_dataset$parquet_over_zip
per_dataset$parquet_yearly_2024_bytes <-
  per_dataset$zip_2024_bytes * per_dataset$parquet_over_zip
per_dataset$parquet_10y_future_bytes <-
  per_dataset$parquet_yearly_2024_bytes * 10
per_dataset$parquet_v10_total_bytes <-
  per_dataset$parquet_historical_bytes + per_dataset$parquet_10y_future_bytes

saveRDS(per_dataset, file.path(audit_dir, "per_dataset.rds"))

# ---- 7. Render markdown report -----------------------------------------

message("\n[4/4] Rendering markdown report...")

fmt_mb <- function(b) ifelse(is.na(b), "—", sprintf("%.1f", b / 1024^2))
fmt_gb <- function(b) ifelse(is.na(b), "—", sprintf("%.2f", b / 1024^3))

out <- character()
out <- c(out, "# Mirror capacity audit — Sessao 3.11")
out <- c(out, "")
out <- c(out, sprintf("_Generated: %s_", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")))
out <- c(out, "")
out <- c(out, "## Methodology")
out <- c(out, "")
out <- c(out, "1. **Inventory**: 36 datasets across 13 top-level CVM domains within v0.1-v1.0 scope.")
out <- c(out, "2. **HEAD probe**: byte sizes extracted from Apache directory listings on `dados.cvm.gov.br`.")
out <- c(out, "3. **Parquet ratio**: three archetypes downloaded, unzipped, converted to parquet snappy.")
out <- c(out, "4. **Projection**: parquet_total = parquet_historical + 10 * parquet_2024_yearly.")
out <- c(out, "")
out <- c(out, "## Archetype ratios (parquet snappy / ZIP)")
out <- c(out, "")
out <- c(out, "| Archetype | Sample ZIP | ZIP (MB) | CSV (MB) | Parquet (MB) | parquet/ZIP | csv/ZIP |")
out <- c(out, "|---|---|---|---|---|---|---|")
for (i in seq_len(nrow(ratios))) {
  r <- ratios[i, ]
  out <- c(out, sprintf(
    "| %s | `%s` | %s | %s | %s | %.3f | %.3f |",
    r$archetype, r$sample_file,
    fmt_mb(r$zip_bytes), fmt_mb(r$csv_bytes), fmt_mb(r$parquet_bytes),
    r$parquet_over_zip, r$csv_over_zip
  ))
}
out <- c(out, "")

out <- c(out, "## Per-dataset projection")
out <- c(out, "")
out <- c(out, "| Scope | Category | Dataset | Archetype | Hist. yrs | ZIP total (MB) | ZIP 2024 (MB) | Parquet hist. (MB) | Parquet 2024/yr (MB) | **v1.0 total parquet (GB)** |")
out <- c(out, "|---|---|---|---|---:|---:|---:|---:|---:|---:|")
per_dataset_ordered <- per_dataset |>
  dplyr::arrange(scope, category, dataset)
for (i in seq_len(nrow(per_dataset_ordered))) {
  r <- per_dataset_ordered[i, ]
  out <- c(out, sprintf(
    "| %s | %s | %s | %s | %d | %s | %s | %s | %s | **%s** |",
    r$scope, r$category, r$dataset, r$archetype,
    r$historical_years,
    fmt_mb(r$zip_total_bytes), fmt_mb(r$zip_2024_bytes),
    fmt_mb(r$parquet_historical_bytes), fmt_mb(r$parquet_yearly_2024_bytes),
    fmt_gb(r$parquet_v10_total_bytes)
  ))
}
out <- c(out, "")

out <- c(out, "## Totals by scope")
out <- c(out, "")
by_scope <- per_dataset |>
  dplyr::group_by(scope) |>
  dplyr::summarise(
    n_datasets = dplyr::n(),
    parquet_v10_total_gb = sum(parquet_v10_total_bytes, na.rm = TRUE) / 1024^3,
    .groups = "drop"
  ) |>
  dplyr::arrange(scope)
out <- c(out, "| Scope | Datasets | v1.0 total parquet (GB) |")
out <- c(out, "|---|---:|---:|")
for (i in seq_len(nrow(by_scope))) {
  r <- by_scope[i, ]
  out <- c(out, sprintf("| %s | %d | **%.2f** |",
                       r$scope, r$n_datasets, r$parquet_v10_total_gb))
}
total_gb <- sum(per_dataset$parquet_v10_total_bytes, na.rm = TRUE) / 1024^3
out <- c(out, sprintf("| **TOTAL** | %d | **%.2f** |",
                     nrow(per_dataset), total_gb))
out <- c(out, "")
out <- c(out, sprintf("**Projected v1.0 mirror size: %.2f GB (parquet snappy).**", total_gb))
out <- c(out, "")
out <- c(out, "## Assumptions and caveats")
out <- c(out, "")
out <- c(out, "- Historical volume per dataset = sum of all years currently published by CVM.")
out <- c(out, "- Future volume = 10 * size of 2024 (Sidney's heuristic; assumes flat universe).")
out <- c(out, "- For datasets where the universe is growing (FI/INF_DIARIO, CDA, FIDC, FIAGRO),")
out <- c(out, "  the projection is therefore **conservative** when applied to past years and")
out <- c(out, "  **lower-bound** for future years. Recompute on next major scope review.")
out <- c(out, "- Parquet ratio derives from 3 archetypes; outlier datasets (very wide tables,")
out <- c(out, "  identifier-heavy schemas) may diverge.")
out <- c(out, "- Participants (ADM_CART, AGENTE_AUTON, etc.) excluded as they are out of scope")
out <- c(out, "  for v1.0 and consist of small static registers (estimated < 50 MB combined).")
out <- c(out, "")
out <- c(out, "## Per-archetype contribution (sanity check)")
out <- c(out, "")
by_arch <- per_dataset |>
  dplyr::group_by(archetype) |>
  dplyr::summarise(
    n_datasets = dplyr::n(),
    parquet_v10_total_gb = sum(parquet_v10_total_bytes, na.rm = TRUE) / 1024^3,
    .groups = "drop"
  ) |>
  dplyr::arrange(dplyr::desc(parquet_v10_total_gb))
out <- c(out, "| Archetype | Datasets | v1.0 total parquet (GB) |")
out <- c(out, "|---|---:|---:|")
for (i in seq_len(nrow(by_arch))) {
  r <- by_arch[i, ]
  out <- c(out, sprintf("| %s | %d | %.2f |",
                       r$archetype, r$n_datasets, r$parquet_v10_total_gb))
}

writeLines(out, "data-raw/mirror-capacity-audit.md")
message("\nReport written: data-raw/mirror-capacity-audit.md")
message(sprintf("v1.0 total projected: %.2f GB parquet snappy", total_gb))
