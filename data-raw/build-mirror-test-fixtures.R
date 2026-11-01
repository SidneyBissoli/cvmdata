# Build small fixtures used by tests/testthat/.
#
# Mirror fixtures (parquet, consumed by test-source-mirror-*.R):
#   tests/testthat/fixtures/mirror-cad-companhias.parquet
#     - the same 50-row CAD sample as cad_sample.csv after the package
#       transform pipeline (no transformations declared for CAD).
#   tests/testthat/fixtures/mirror-dfp-bpa-ind-2024.parquet
#     - a small subset of the DFP fixture: bpa ind 2024 after
#       apply_schema_transformations() (multiply_by_scale +
#       keep_latest_version).
#
# Raw ZIP fixtures (consumed by test-issuer-fetch-*.R via mocked HTTP +
# `local_prepare_*_cache()` helpers):
#   tests/testthat/fixtures/cgvn_cia_aberta_2024.zip
#     - subset of CGVN 2024 to BCO BRASIL + MAGAZINE LUIZA, repacked
#       to keep the fixture under 200 KB. Built on demand here because
#       v0.2 Sessao 10 introduced the dataset; pre-existing raw ZIPs
#       (dfp/itr/fre) were committed manually before this script
#       existed.
#   tests/testthat/fixtures/vlmo_cia_aberta_2024.zip
#     - subset of VLMO 2024 (submissao + con) to BCO BRASIL +
#       MAGAZINE LUIZA, repacked under 200 KB. Added in v0.2 Sessao 11.
#   tests/testthat/fixtures/fca_cia_aberta_2024.zip
#     - subset of FCA 2024 (all 10 tables) to BCO BRASIL + MAGAZINE
#       LUIZA, repacked under 200 KB. Added in v0.2 Sessao 12.
#       departamento_acionistas ships header-only (empty upstream).
#   tests/testthat/fixtures/ipe_cia_aberta_2024.zip
#     - subset of IPE 2024 (single-table manifest) to BCO BRASIL +
#       MAGAZINE LUIZA, repacked under 200 KB. Added in v0.2 Sessao 13.
#       Keeps every Categoria emitted by the pair (manifest is
#       event-per-row, no dedup) for the category-filter test.
#   tests/testthat/fixtures/mirror-dfp-dre-con-2023.parquet and
#   tests/testthat/fixtures/mirror-dfp-dre-con-2023-history.parquet
#     - the current (`part-0`) and superseded (`history`) assets of
#       dfp/dre con 2023 as published on the mirror, cut to BRASKEM
#       (versions 1, 2 and the current 3) and PETROBRAS (1 and the
#       current 2) and to four income-statement accounts. Consumed by
#       test-cvm-versions.R.
#   tests/testthat/fixtures/dfp_cia_aberta_2025.zip and
#   tests/testthat/fixtures/mirror-dfp-bpa-ind-2025.parquet
#     - subset of DFP 2025 (submissao, BPA ind/con, DRE ind,
#       composicao_capital) to the same pair, plus the bpa ind parquet
#       built from it. The following year's file of the 2024 fixtures,
#       for the `reading` tests of cvm_fetch() (v0.3).
#
# Run with `Rscript data-raw/build-mirror-test-fixtures.R` from the
# package root to (re)build everything, or pass one or more targets to
# build a subset, e.g. `Rscript data-raw/build-mirror-test-fixtures.R
# fca` to rebuild only the FCA fixture in isolation (the pattern used
# from Sessao 11 onward to avoid disturbing already-committed
# fixtures). Targets: `parquet`, `cgvn`, `vlmo`, `fca`, `ipe`,
# `dfp2025`, `dre2023`. Idempotent — overwrites any pre-existing
# fixtures it touches. The cgvn/vlmo/fca/ipe/dfp2025 raw-fixture steps
# require network access to the CVM portal; `dre2023` downloads two
# assets of the parquet mirror from GitHub Releases.

stopifnot(requireNamespace("devtools", quietly = TRUE))
stopifnot(requireNamespace("DBI", quietly = TRUE))
stopifnot(requireNamespace("duckdb", quietly = TRUE))
stopifnot(requireNamespace("httr2", quietly = TRUE))
stopifnot(requireNamespace("jsonlite", quietly = TRUE))

devtools::load_all(quiet = TRUE)
options(cvmdata.cache_dir = file.path(tempdir(), "cvmdata-build-fixtures"))

# Target selection: default to all; CLI args restrict to a subset.
.all_targets <- c(
  "parquet",
  "cgvn",
  "vlmo",
  "fca",
  "ipe",
  "recompra",
  "dfp2025",
  "dre2023"
)
.targets <- commandArgs(trailingOnly = TRUE)
if (!length(.targets)) {
  .targets <- .all_targets
}
unknown_targets <- setdiff(.targets, .all_targets)
if (length(unknown_targets)) {
  stop(sprintf(
    "Unknown fixture target(s): %s. Valid: %s",
    paste(unknown_targets, collapse = ", "),
    paste(.all_targets, collapse = ", ")
  ))
}

write_parquet_via_duckdb <- function(df, path) {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbWriteTable(con, "t", df, overwrite = TRUE)
  DBI::dbExecute(
    con,
    sprintf(
      "COPY (SELECT * FROM t) TO '%s' (FORMAT 'parquet', COMPRESSION 'snappy')",
      gsub("\\\\", "/", path, fixed = FALSE)
    )
  )
  invisible(path)
}

build_parquet_fixtures <- function() {
  # CAD ---------------------------------------------------------------------

  cad_schema <- cvmdata:::load_schema("cad", "companhias")
  cad_df <- cvmdata:::read_cvm_csv(
    "tests/testthat/fixtures/cad_sample.csv",
    cad_schema,
    validate = "skip"
  )
  cad_df <- cvmdata:::apply_schema_transformations(cad_df, cad_schema)

  cad_out <- "tests/testthat/fixtures/mirror-cad-companhias.parquet"
  write_parquet_via_duckdb(cad_df, cad_out)
  cat(sprintf(
    "[fixture] %s  %d rows, %s bytes\n",
    cad_out,
    nrow(cad_df),
    format(file.info(cad_out)$size)
  ))

  # DFP BPA ind 2024 --------------------------------------------------------

  dfp_schema <- cvmdata:::load_schema("dfp", "bpa")
  # Stage the fixture ZIP into a fake cache, then run the package
  # pipeline against it so the resulting parquet matches what the ETL
  # would publish (post-transformations, no companies filter).
  fixt_zip <- "tests/testthat/fixtures/dfp_cia_aberta_2024.zip"
  cache_root <- file.path(tempdir(), "cvmdata-build-fixtures-cache")
  raw_dir <- file.path(cache_root, "raw", "dfp", "2024")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  file.copy(fixt_zip, file.path(raw_dir, basename(fixt_zip)), overwrite = TRUE)
  saveRDS(
    list(
      etag = '"fixture-etag"',
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
    ),
    file.path(raw_dir, paste0(basename(fixt_zip), ".etag.rds"))
  )
  withr::with_options(
    list(
      cvmdata.cache_dir = cache_root,
      cvmdata.cache_ttl_seconds = Inf
    ),
    {
      bpa <- issuer_fetch(
        "dfp",
        "bpa",
        report_type = "ind",
        year = 2024,
        source = "cvm"
      )
    }
  )
  # Strip the cvm_tbl class + provenance attrs so the parquet body is a
  # plain table — the mirror reader reattaches its own attrs from the
  # parsed asset name.
  attr(bpa, "source") <- NULL
  attr(bpa, "fetched_at") <- NULL
  attr(bpa, "dataset") <- NULL
  attr(bpa, "table") <- NULL
  attr(bpa, "package_version") <- NULL
  class(bpa) <- setdiff(class(bpa), "cvm_tbl")

  bpa_out <- "tests/testthat/fixtures/mirror-dfp-bpa-ind-2024.parquet"
  write_parquet_via_duckdb(bpa, bpa_out)
  cat(sprintf(
    "[fixture] %s  %d rows, %s bytes\n",
    bpa_out,
    nrow(bpa),
    format(file.info(bpa_out)$size)
  ))

  invisible(NULL)
}

# CGVN raw ZIP fixture (Sessao 10) ----------------------------------------
# Downloads the real 2024 ZIP from the CVM portal, filters submissao +
# praticas to BCO BRASIL + MAGAZINE LUIZA, repacks as a small fixture.
# Subset uses CNPJ_Companhia because the praticas CSV does not carry
# Codigo_CVM (lookup CD_CVM -> CNPJ would normally go through the
# submissao path; here we filter directly on CNPJ for fixture size).

build_cgvn_raw_fixture <- function() {
  cgvn_url <- paste0(
    "https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/CGVN/DADOS/",
    "cgvn_cia_aberta_2024.zip"
  )
  out_zip <- "tests/testthat/fixtures/cgvn_cia_aberta_2024.zip"
  out_meta <- paste0(out_zip, ".meta.json")

  # Companies kept in the subset (same pair used in DFP/ITR/FRE
  # fixtures for cross-test coherence).
  keep_cnpjs <- c("00.000.000/0001-91", "47.960.950/0001-21")
  keep_meta <- list(
    list(
      cd_cvm = "001023",
      cnpj_companhia = "00.000.000/0001-91",
      nome_empresarial = "BCO BRASIL S.A."
    ),
    list(
      cd_cvm = "022470",
      cnpj_companhia = "47.960.950/0001-21",
      nome_empresarial = "MAGAZINE LUIZA S.A."
    )
  )

  stage <- tempfile("cgvn_fixture_")
  dir.create(stage, recursive = TRUE)
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)

  zip_local <- file.path(stage, "cgvn_cia_aberta_2024.zip")
  cat(sprintf("[cgvn] Downloading %s\n", cgvn_url))
  resp <- httr2::req_perform(
    httr2::req_timeout(httr2::request(cgvn_url), 300L)
  )
  writeBin(httr2::resp_body_raw(resp), zip_local)

  extract_dir <- file.path(stage, "extract")
  dir.create(extract_dir)
  utils::unzip(zip_local, exdir = extract_dir)

  subset_csv <- function(name, cnpj_col) {
    path <- file.path(extract_dir, name)
    if (!file.exists(path)) {
      stop(sprintf("Expected CSV not found in CGVN ZIP: %s", name))
    }
    # Read whole file as character to preserve every byte; filter; write
    # back with the same encoding/delimiter.
    raw <- readBin(path, "raw", n = file.info(path)$size)
    txt <- iconv(rawToChar(raw), from = "ISO-8859-1", to = "UTF-8")
    lines <- strsplit(txt, "\r?\n", perl = TRUE)[[1L]]
    header <- lines[1L]
    cols <- strsplit(header, ";", fixed = TRUE)[[1L]]
    idx <- which(tolower(cols) == cnpj_col)
    if (!length(idx)) {
      stop(sprintf("CNPJ column %s not found in %s", cnpj_col, name))
    }
    body <- lines[-1L]
    body <- body[nzchar(body)]
    fields <- strsplit(body, ";", fixed = TRUE)
    cnpjs <- vapply(
      fields,
      function(f) {
        if (length(f) >= idx) f[idx] else NA_character_
      },
      character(1L)
    )
    keep_mask <- cnpjs %in% keep_cnpjs
    kept <- c(header, body[keep_mask])
    out <- file.path(extract_dir, paste0("subset_", name))
    out_raw <- charToRaw(
      iconv(paste(kept, collapse = "\r\n"), from = "UTF-8", to = "ISO-8859-1")
    )
    writeBin(out_raw, out)
    list(path = out, n_rows = sum(keep_mask))
  }

  sub_info <- subset_csv("cgvn_cia_aberta_2024.csv", "cnpj_companhia")
  prat_info <- subset_csv("cgvn_cia_aberta_praticas_2024.csv", "cnpj_companhia")

  # Repack: only the two filtered CSVs (renamed back to canonical).
  pack_dir <- file.path(stage, "pack")
  dir.create(pack_dir)
  file.copy(
    sub_info$path,
    file.path(pack_dir, "cgvn_cia_aberta_2024.csv"),
    overwrite = TRUE
  )
  file.copy(
    prat_info$path,
    file.path(pack_dir, "cgvn_cia_aberta_praticas_2024.csv"),
    overwrite = TRUE
  )

  if (file.exists(out_zip)) {
    file.remove(out_zip)
  }
  # zip writes relative to the pack_dir we cd into, so the zipfile arg
  # must be an absolute path before the with_dir; computing it after
  # with_dir would resolve it under pack_dir and silently fail on
  # Windows when intermediate parent dirs don't exist there.
  out_zip_abs <- file.path(
    normalizePath(dirname(out_zip), winslash = "/", mustWork = TRUE),
    basename(out_zip)
  )
  withr::with_dir(pack_dir, {
    utils::zip(
      zipfile = out_zip_abs,
      files = list.files("."),
      flags = "-q9X"
    )
  })

  meta <- list(
    source_url = cgvn_url,
    fetched_at = format(Sys.Date()),
    companies_included = keep_meta,
    files_included = c(
      "cgvn_cia_aberta_2024.csv",
      "cgvn_cia_aberta_praticas_2024.csv"
    ),
    notes = paste(
      "Subset filtered by CNPJ_Companhia (BCO BRASIL + MAGAZINE LUIZA).",
      "ISO-8859-1 encoding preserved.",
      "Built from the 2024 yearly archive (Sessao 10, v0.2).",
      "praticas keeps all 54 ID_Item rows per company per filing,",
      "covering the 4 valid Pratica_Adotada categories",
      "(Sim, Nao, Parcialmente, Nao se Aplica)."
    )
  )
  writeLines(
    jsonlite::toJSON(meta, pretty = TRUE, auto_unbox = TRUE),
    out_meta
  )

  cat(sprintf(
    "[fixture] %s  %s bytes\n",
    out_zip,
    format(file.info(out_zip)$size)
  ))
  cat(sprintf(
    "[fixture] submissao subset: %d rows; praticas: %d rows\n",
    sub_info$n_rows,
    prat_info$n_rows
  ))
  cat(sprintf("[fixture] %s\n", out_meta))
}

# --- VLMO raw ZIP fixture --------------------------------------------
# Downloads the 2024 VLMO yearly archive, filters submissao + con to
# BCO BRASIL + MAGAZINE LUIZA, repacks as a small fixture. Both CSVs
# carry CNPJ_Companhia, so the subset filters on that column directly.
# con does not carry Codigo_CVM (CD_CVM lookup would go through the
# submissao path in real use); filtering on CNPJ keeps the fixture
# self-contained. The "no dedup by version" semantics are exercised by
# a synthetic in-test data frame, not by this fixture.

build_vlmo_raw_fixture <- function() {
  vlmo_url <- paste0(
    "https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/VLMO/DADOS/",
    "vlmo_cia_aberta_2024.zip"
  )
  out_zip <- "tests/testthat/fixtures/vlmo_cia_aberta_2024.zip"
  out_meta <- paste0(out_zip, ".meta.json")

  # Companies kept in the subset (same pair used in CGVN/DFP/ITR/FRE
  # fixtures for cross-test coherence).
  keep_cnpjs <- c("00.000.000/0001-91", "47.960.950/0001-21")
  keep_meta <- list(
    list(
      cd_cvm = "001023",
      cnpj_companhia = "00.000.000/0001-91",
      nome_companhia = "BCO BRASIL S.A."
    ),
    list(
      cd_cvm = "022470",
      cnpj_companhia = "47.960.950/0001-21",
      nome_companhia = "MAGAZINE LUIZA S.A."
    )
  )

  stage <- tempfile("vlmo_fixture_")
  dir.create(stage, recursive = TRUE)
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)

  zip_local <- file.path(stage, "vlmo_cia_aberta_2024.zip")
  cat(sprintf("[vlmo] Downloading %s\n", vlmo_url))
  resp <- httr2::req_perform(
    httr2::req_timeout(httr2::request(vlmo_url), 300L)
  )
  writeBin(httr2::resp_body_raw(resp), zip_local)

  extract_dir <- file.path(stage, "extract")
  dir.create(extract_dir)
  utils::unzip(zip_local, exdir = extract_dir)

  subset_csv <- function(name, cnpj_col) {
    path <- file.path(extract_dir, name)
    if (!file.exists(path)) {
      stop(sprintf("Expected CSV not found in VLMO ZIP: %s", name))
    }
    raw <- readBin(path, "raw", n = file.info(path)$size)
    txt <- iconv(rawToChar(raw), from = "ISO-8859-1", to = "UTF-8")
    lines <- strsplit(txt, "\r?\n", perl = TRUE)[[1L]]
    header <- lines[1L]
    cols <- strsplit(header, ";", fixed = TRUE)[[1L]]
    idx <- which(tolower(cols) == cnpj_col)
    if (!length(idx)) {
      stop(sprintf("CNPJ column %s not found in %s", cnpj_col, name))
    }
    body <- lines[-1L]
    body <- body[nzchar(body)]
    fields <- strsplit(body, ";", fixed = TRUE)
    cnpjs <- vapply(
      fields,
      function(f) {
        if (length(f) >= idx) f[idx] else NA_character_
      },
      character(1L)
    )
    keep_mask <- cnpjs %in% keep_cnpjs
    kept <- c(header, body[keep_mask])
    out <- file.path(extract_dir, paste0("subset_", name))
    out_raw <- charToRaw(
      iconv(paste(kept, collapse = "\r\n"), from = "UTF-8", to = "ISO-8859-1")
    )
    writeBin(out_raw, out)
    list(path = out, n_rows = sum(keep_mask))
  }

  sub_info <- subset_csv("vlmo_cia_aberta_2024.csv", "cnpj_companhia")
  con_info <- subset_csv("vlmo_cia_aberta_con_2024.csv", "cnpj_companhia")

  # Repack: only the two filtered CSVs (renamed back to canonical).
  pack_dir <- file.path(stage, "pack")
  dir.create(pack_dir)
  file.copy(
    sub_info$path,
    file.path(pack_dir, "vlmo_cia_aberta_2024.csv"),
    overwrite = TRUE
  )
  file.copy(
    con_info$path,
    file.path(pack_dir, "vlmo_cia_aberta_con_2024.csv"),
    overwrite = TRUE
  )

  if (file.exists(out_zip)) {
    file.remove(out_zip)
  }
  out_zip_abs <- file.path(
    normalizePath(dirname(out_zip), winslash = "/", mustWork = TRUE),
    basename(out_zip)
  )
  withr::with_dir(pack_dir, {
    utils::zip(
      zipfile = out_zip_abs,
      files = list.files("."),
      flags = "-q9X"
    )
  })

  meta <- list(
    source_url = vlmo_url,
    fetched_at = format(Sys.Date()),
    companies_included = keep_meta,
    files_included = c(
      "vlmo_cia_aberta_2024.csv",
      "vlmo_cia_aberta_con_2024.csv"
    ),
    notes = paste(
      "Subset filtered by CNPJ_Companhia (BCO BRASIL + MAGAZINE LUIZA).",
      "ISO-8859-1 encoding preserved.",
      "Built from the 2024 yearly archive (Sessao 11, v0.2).",
      "con is event-per-row: NO keep_latest_version transformation,",
      "so multiple VERSAO rows per (cnpj, data_ref) survive verbatim."
    )
  )
  writeLines(
    jsonlite::toJSON(meta, pretty = TRUE, auto_unbox = TRUE),
    out_meta
  )

  cat(sprintf(
    "[fixture] %s  %s bytes\n",
    out_zip,
    format(file.info(out_zip)$size)
  ))
  cat(sprintf(
    "[fixture] submissao subset: %d rows; con: %d rows\n",
    sub_info$n_rows,
    con_info$n_rows
  ))
  cat(sprintf("[fixture] %s\n", out_meta))
}

# --- FCA raw ZIP fixture (Sessao 12) ---------------------------------
# Downloads the 2024 FCA yearly archive and subsets all 10 tables to
# BCO BRASIL + MAGAZINE LUIZA. The submissao CSV uses the classic
# CNPJ_CIA column; the 9 detail CSVs use CNPJ_Companhia, so each is
# filtered on the column it carries. departamento_acionistas is empty
# upstream from 2024 on, so its subset is header-only — exactly the
# case the reader must tolerate (nrow == 0L without aborting).
# valor_mobiliario keeps the BB/MGLU rows, which carry the B3 tickers
# (BBAS3, MGLU3, ...) that exercise resolve_ticker_via_fca().

build_fca_raw_fixture <- function() {
  fca_url <- paste0(
    "https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/FCA/DADOS/",
    "fca_cia_aberta_2024.zip"
  )
  out_zip <- "tests/testthat/fixtures/fca_cia_aberta_2024.zip"
  out_meta <- paste0(out_zip, ".meta.json")

  keep_cnpjs <- c("00.000.000/0001-91", "47.960.950/0001-21")
  keep_meta <- list(
    list(
      cd_cvm = "001023",
      cnpj = "00.000.000/0001-91",
      denom = "BCO BRASIL S.A."
    ),
    list(
      cd_cvm = "022470",
      cnpj = "47.960.950/0001-21",
      denom = "MAGAZINE LUIZA S.A."
    )
  )

  # (CSV file in the ZIP, CNPJ column used to subset). The first is the
  # classic submissao (CNPJ_CIA); the rest are FRE-detail (CNPJ_Companhia).
  tables <- list(
    c("fca_cia_aberta_2024.csv", "cnpj_cia"),
    c("fca_cia_aberta_auditor_2024.csv", "cnpj_companhia"),
    c("fca_cia_aberta_canal_divulgacao_2024.csv", "cnpj_companhia"),
    c("fca_cia_aberta_departamento_acionistas_2024.csv", "cnpj_companhia"),
    c("fca_cia_aberta_dri_2024.csv", "cnpj_companhia"),
    c("fca_cia_aberta_endereco_2024.csv", "cnpj_companhia"),
    c("fca_cia_aberta_escriturador_2024.csv", "cnpj_companhia"),
    c("fca_cia_aberta_geral_2024.csv", "cnpj_companhia"),
    c("fca_cia_aberta_pais_estrangeiro_negociacao_2024.csv", "cnpj_companhia"),
    c("fca_cia_aberta_valor_mobiliario_2024.csv", "cnpj_companhia")
  )

  stage <- tempfile("fca_fixture_")
  dir.create(stage, recursive = TRUE)
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)

  zip_local <- file.path(stage, "fca_cia_aberta_2024.zip")
  cat(sprintf("[fca] Downloading %s\n", fca_url))
  resp <- httr2::req_perform(
    httr2::req_timeout(httr2::request(fca_url), 300L)
  )
  writeBin(httr2::resp_body_raw(resp), zip_local)

  extract_dir <- file.path(stage, "extract")
  dir.create(extract_dir)
  utils::unzip(zip_local, exdir = extract_dir)

  subset_csv <- function(name, cnpj_col) {
    path <- file.path(extract_dir, name)
    if (!file.exists(path)) {
      stop(sprintf("Expected CSV not found in FCA ZIP: %s", name))
    }
    raw <- readBin(path, "raw", n = file.info(path)$size)
    txt <- iconv(rawToChar(raw), from = "ISO-8859-1", to = "UTF-8")
    lines <- strsplit(txt, "\r?\n", perl = TRUE)[[1L]]
    header <- lines[1L]
    cols <- strsplit(header, ";", fixed = TRUE)[[1L]]
    idx <- which(tolower(cols) == cnpj_col)
    if (!length(idx)) {
      stop(sprintf("CNPJ column %s not found in %s", cnpj_col, name))
    }
    body <- lines[-1L]
    body <- body[nzchar(body)]
    fields <- strsplit(body, ";", fixed = TRUE)
    cnpjs <- vapply(
      fields,
      function(f) {
        if (length(f) >= idx) f[idx] else NA_character_
      },
      character(1L)
    )
    keep_mask <- cnpjs %in% keep_cnpjs
    kept <- c(header, body[keep_mask])
    out <- file.path(extract_dir, paste0("subset_", name))
    out_raw <- charToRaw(
      iconv(paste(kept, collapse = "\r\n"), from = "UTF-8", to = "ISO-8859-1")
    )
    writeBin(out_raw, out)
    list(path = out, n_rows = sum(keep_mask))
  }

  pack_dir <- file.path(stage, "pack")
  dir.create(pack_dir)
  row_counts <- integer(0L)
  for (t in tables) {
    info <- subset_csv(t[[1L]], t[[2L]])
    file.copy(info$path, file.path(pack_dir, t[[1L]]), overwrite = TRUE)
    row_counts[[t[[1L]]]] <- info$n_rows
  }

  if (file.exists(out_zip)) {
    file.remove(out_zip)
  }
  out_zip_abs <- file.path(
    normalizePath(dirname(out_zip), winslash = "/", mustWork = TRUE),
    basename(out_zip)
  )
  withr::with_dir(pack_dir, {
    utils::zip(
      zipfile = out_zip_abs,
      files = list.files("."),
      flags = "-q9X"
    )
  })

  meta <- list(
    source_url = fca_url,
    fetched_at = format(Sys.Date()),
    companies_included = keep_meta,
    files_included = vapply(tables, `[[`, character(1L), 1L),
    notes = paste(
      "Subset filtered by CNPJ (BCO BRASIL + MAGAZINE LUIZA).",
      "ISO-8859-1 encoding preserved.",
      "Built from the 2024 yearly archive (Sessao 12, v0.2).",
      "All 10 tables included. submissao filtered on CNPJ_CIA (classic);",
      "the 9 detail tables on CNPJ_Companhia (FRE-detail).",
      "departamento_acionistas ships header-only (empty upstream from",
      "2024), exercising the reader's nrow == 0L tolerance.",
      "valor_mobiliario carries the BB/MGLU B3 tickers for the ticker",
      "lookup."
    )
  )
  writeLines(
    jsonlite::toJSON(meta, pretty = TRUE, auto_unbox = TRUE),
    out_meta
  )

  cat(sprintf(
    "[fixture] %s  %s bytes\n",
    out_zip,
    format(file.info(out_zip)$size)
  ))
  for (nm in names(row_counts)) {
    cat(sprintf("[fixture]   %-52s %d rows\n", nm, row_counts[[nm]]))
  }
  cat(sprintf("[fixture] %s\n", out_meta))
}

# --- IPE raw ZIP fixture (Sessao 13) ---------------------------------
# Downloads the 2024 IPE yearly archive and subsets the single-table
# manifest to BCO BRASIL + MAGAZINE LUIZA. The CSV carries
# CNPJ_Companhia, so the subset filters on that column directly. IPE
# also carries Codigo_CVM natively (CD_CVM filters match directly, no
# submissao bridge), but CNPJ is used here to keep the fixture
# self-contained. Every Categoria the pair emits is kept (manifest is
# event-per-row, no dedup), giving the category-filter test plenty of
# distinct values. The full BB/MGLU subset stays well under the 200 KB
# cap, so no per-category trimming is needed.

build_ipe_raw_fixture <- function() {
  ipe_url <- paste0(
    "https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/IPE/DADOS/",
    "ipe_cia_aberta_2024.zip"
  )
  out_zip <- "tests/testthat/fixtures/ipe_cia_aberta_2024.zip"
  out_meta <- paste0(out_zip, ".meta.json")

  # Companies kept in the subset (same pair used in CGVN/VLMO/FCA/DFP/
  # ITR/FRE fixtures for cross-test coherence).
  keep_cnpjs <- c("00.000.000/0001-91", "47.960.950/0001-21")
  keep_meta <- list(
    list(
      cd_cvm = "001023",
      cnpj_companhia = "00.000.000/0001-91",
      nome_companhia = "BANCO DO BRASIL S.A."
    ),
    list(
      cd_cvm = "022470",
      cnpj_companhia = "47.960.950/0001-21",
      nome_companhia = "MAGAZINE LUIZA S.A."
    )
  )

  stage <- tempfile("ipe_fixture_")
  dir.create(stage, recursive = TRUE)
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)

  zip_local <- file.path(stage, "ipe_cia_aberta_2024.zip")
  cat(sprintf("[ipe] Downloading %s\n", ipe_url))
  resp <- httr2::req_perform(
    httr2::req_timeout(httr2::request(ipe_url), 300L)
  )
  writeBin(httr2::resp_body_raw(resp), zip_local)

  extract_dir <- file.path(stage, "extract")
  dir.create(extract_dir)
  utils::unzip(zip_local, exdir = extract_dir)

  # Categoria sits at index 5; collected here to record which distinct
  # categories the subset preserves in the .meta.json.
  categories <- character(0L)

  subset_csv <- function(name, cnpj_col) {
    path <- file.path(extract_dir, name)
    if (!file.exists(path)) {
      stop(sprintf("Expected CSV not found in IPE ZIP: %s", name))
    }
    raw <- readBin(path, "raw", n = file.info(path)$size)
    txt <- iconv(rawToChar(raw), from = "ISO-8859-1", to = "UTF-8")
    lines <- strsplit(txt, "\r?\n", perl = TRUE)[[1L]]
    header <- lines[1L]
    cols <- strsplit(header, ";", fixed = TRUE)[[1L]]
    idx <- which(tolower(cols) == cnpj_col)
    cat_idx <- which(tolower(cols) == "categoria")
    if (!length(idx)) {
      stop(sprintf("CNPJ column %s not found in %s", cnpj_col, name))
    }
    body <- lines[-1L]
    body <- body[nzchar(body)]
    fields <- strsplit(body, ";", fixed = TRUE)
    cnpjs <- vapply(
      fields,
      function(f) {
        if (length(f) >= idx) f[idx] else NA_character_
      },
      character(1L)
    )
    keep_mask <- cnpjs %in% keep_cnpjs
    kept_fields <- fields[keep_mask]
    categories <<- unique(c(
      categories,
      vapply(
        kept_fields,
        function(f) {
          if (length(f) >= cat_idx) f[cat_idx] else NA_character_
        },
        character(1L)
      )
    ))
    kept <- c(header, body[keep_mask])
    out <- file.path(extract_dir, paste0("subset_", name))
    out_raw <- charToRaw(
      iconv(paste(kept, collapse = "\r\n"), from = "UTF-8", to = "ISO-8859-1")
    )
    writeBin(out_raw, out)
    list(path = out, n_rows = sum(keep_mask))
  }

  ipe_info <- subset_csv("ipe_cia_aberta_2024.csv", "cnpj_companhia")

  # Repack: only the filtered CSV (renamed back to canonical).
  pack_dir <- file.path(stage, "pack")
  dir.create(pack_dir)
  file.copy(
    ipe_info$path,
    file.path(pack_dir, "ipe_cia_aberta_2024.csv"),
    overwrite = TRUE
  )

  if (file.exists(out_zip)) {
    file.remove(out_zip)
  }
  out_zip_abs <- file.path(
    normalizePath(dirname(out_zip), winslash = "/", mustWork = TRUE),
    basename(out_zip)
  )
  withr::with_dir(pack_dir, {
    utils::zip(
      zipfile = out_zip_abs,
      files = list.files("."),
      flags = "-q9X"
    )
  })

  meta <- list(
    source_url = ipe_url,
    fetched_at = format(Sys.Date()),
    companies_included = keep_meta,
    files_included = "ipe_cia_aberta_2024.csv",
    categories_included = sort(categories),
    notes = paste(
      "Subset filtered by CNPJ_Companhia (BCO BRASIL + MAGAZINE LUIZA).",
      "ISO-8859-1 encoding preserved.",
      "Built from the 2024 yearly archive (Sessao 13, v0.2).",
      "IPE is an event-per-row manifest: NO keep_latest_version",
      "transformation, so every filed document (and every VERSAO)",
      "survives verbatim. Every Categoria the pair emits is kept for",
      "the category-filter test. The overlap category 'Valores",
      "Mobiliarios negociados e detidos (art. 11 ...)' is the same",
      "event VLMO structures (see vignette ipe-vlmo)."
    )
  )
  writeLines(
    jsonlite::toJSON(meta, pretty = TRUE, auto_unbox = TRUE),
    out_meta
  )

  cat(sprintf(
    "[fixture] %s  %s bytes\n",
    out_zip,
    format(file.info(out_zip)$size)
  ))
  cat(sprintf(
    "[fixture] ipe subset: %d rows, %d distinct categories\n",
    ipe_info$n_rows,
    length(categories)
  ))
  cat(sprintf("[fixture] %s\n", out_meta))
}

# DFP 2025 raw ZIP + mirror parquet fixtures (v0.3, `reading`) ----------
# Downloads the real 2025 DFP ZIP, filters submissao + BPA ind/con +
# DRE ind + composicao_capital to BCO BRASIL + MAGAZINE LUIZA and
# repacks as a small fixture, then runs the package pipeline on it to
# produce the 2025 mirror parquet of bpa ind. The pair was chosen in
# 2024; its 2025 file exercises the three readings cases measured on
# 2026-10-20: BB consolidated restates 12 BPA accounts of 2024, BB
# individual carries the 2024 comparative as zeros (CMN Resolution
# 4,966 adopted in 2025 without restating), MAGAZINE LUIZA restates
# nothing.

build_dfp_2025_fixtures <- function() {
  dfp_url <- paste0(
    "https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/DFP/DADOS/",
    "dfp_cia_aberta_2025.zip"
  )
  out_zip <- "tests/testthat/fixtures/dfp_cia_aberta_2025.zip"
  out_meta <- paste0(out_zip, ".meta.json")
  members <- c(
    "dfp_cia_aberta_2025.csv",
    "dfp_cia_aberta_BPA_ind_2025.csv",
    "dfp_cia_aberta_BPA_con_2025.csv",
    "dfp_cia_aberta_DRE_ind_2025.csv",
    "dfp_cia_aberta_composicao_capital_2025.csv"
  )

  keep_cnpjs <- c("00.000.000/0001-91", "47.960.950/0001-21")
  keep_meta <- list(
    list(
      cd_cvm = "001023",
      cnpj_cia = "00.000.000/0001-91",
      denom_cia = "BCO BRASIL S.A."
    ),
    list(
      cd_cvm = "022470",
      cnpj_cia = "47.960.950/0001-21",
      denom_cia = "MAGAZINE LUIZA S.A."
    )
  )

  stage <- tempfile("dfp2025_fixture_")
  dir.create(stage, recursive = TRUE)
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)

  zip_local <- file.path(stage, "dfp_cia_aberta_2025.zip")
  cat(sprintf("[dfp2025] Downloading %s\n", dfp_url))
  resp <- httr2::req_perform(
    httr2::req_timeout(httr2::request(dfp_url), 600L)
  )
  writeBin(httr2::resp_body_raw(resp), zip_local)

  extract_dir <- file.path(stage, "extract")
  dir.create(extract_dir)
  utils::unzip(zip_local, files = members, exdir = extract_dir)

  # Whole-file character round trip so every byte of the kept lines
  # survives; filter on the CNPJ_CIA column; write back ISO-8859-1.
  subset_csv <- function(name, cnpj_col = "cnpj_cia") {
    path <- file.path(extract_dir, name)
    if (!file.exists(path)) {
      stop(sprintf("Expected CSV not found in DFP ZIP: %s", name))
    }
    raw <- readBin(path, "raw", n = file.info(path)$size)
    txt <- iconv(rawToChar(raw), from = "ISO-8859-1", to = "UTF-8")
    lines <- strsplit(txt, "\r?\n", perl = TRUE)[[1L]]
    header <- lines[1L]
    cols <- strsplit(header, ";", fixed = TRUE)[[1L]]
    idx <- which(tolower(cols) == cnpj_col)
    if (!length(idx)) {
      stop(sprintf("CNPJ column %s not found in %s", cnpj_col, name))
    }
    body <- lines[-1L]
    body <- body[nzchar(body)]
    fields <- strsplit(body, ";", fixed = TRUE)
    cnpjs <- vapply(
      fields,
      function(f) {
        if (length(f) >= idx) f[idx] else NA_character_
      },
      character(1L)
    )
    keep_mask <- cnpjs %in% keep_cnpjs
    kept <- c(header, body[keep_mask])
    out <- file.path(extract_dir, paste0("subset_", name))
    out_raw <- charToRaw(
      iconv(paste(kept, collapse = "\r\n"), from = "UTF-8", to = "ISO-8859-1")
    )
    writeBin(out_raw, out)
    list(path = out, n_rows = sum(keep_mask))
  }

  pack_dir <- file.path(stage, "pack")
  dir.create(pack_dir)
  n_rows <- integer(0)
  for (m in members) {
    info <- subset_csv(m)
    n_rows[[m]] <- info$n_rows
    file.copy(info$path, file.path(pack_dir, m), overwrite = TRUE)
  }

  if (file.exists(out_zip)) {
    file.remove(out_zip)
  }
  out_zip_abs <- file.path(
    normalizePath(dirname(out_zip), winslash = "/", mustWork = TRUE),
    basename(out_zip)
  )
  withr::with_dir(pack_dir, {
    utils::zip(
      zipfile = out_zip_abs,
      files = list.files("."),
      flags = "-q9X"
    )
  })

  meta <- list(
    source_url = dfp_url,
    fetched_at = format(Sys.Date()),
    companies_included = keep_meta,
    files_included = members,
    notes = paste(
      "Subset filtered by CNPJ_CIA (BCO BRASIL + MAGAZINE LUIZA).",
      "ISO-8859-1 encoding preserved. Built from the 2025 yearly",
      "archive for the `reading` tests of cvm_fetch() (v0.3): its",
      "PENULTIMO rows are the restated reading of exercise 2024. BCO",
      "BRASIL consolidated restates 12 BPA accounts of 2024; BCO BRASIL",
      "individual carries the 2024 comparative as zeros (CMN",
      "Resolution 4,966 adopted in 2025 without restating); MAGAZINE",
      "LUIZA restates nothing."
    )
  )
  writeLines(
    jsonlite::toJSON(meta, pretty = TRUE, auto_unbox = TRUE),
    out_meta
  )
  cat(sprintf(
    "[fixture] %s  %s bytes (%s)\n",
    out_zip,
    format(file.info(out_zip)$size),
    paste(
      sprintf("%s=%d", sub("dfp_cia_aberta_", "", members), n_rows),
      collapse = " "
    )
  ))
  cat(sprintf("[fixture] %s\n", out_meta))

  # Mirror parquet of bpa ind 2025 from the fixture just built, through
  # the package pipeline (same recipe as build_parquet_fixtures()).
  cache_root <- file.path(tempdir(), "cvmdata-build-fixtures-cache-2025")
  raw_dir <- file.path(cache_root, "raw", "companhias", "dfp", "2025")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  file.copy(out_zip, file.path(raw_dir, basename(out_zip)), overwrite = TRUE)
  saveRDS(
    list(
      etag = '"fixture-etag"',
      last_modified = "Mon, 19 May 2026 00:00:00 GMT",
      fetched_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
    ),
    file.path(raw_dir, paste0(basename(out_zip), ".etag.rds"))
  )
  withr::with_options(
    list(
      cvmdata.cache_dir = cache_root,
      cvmdata.cache_ttl_seconds = Inf,
      cvmdata.check_filings = FALSE
    ),
    {
      bpa <- cvm_fetch(
        "dfp",
        "bpa",
        basis = "ind",
        year = 2025,
        source = "cvm"
      )
    }
  )
  bpa$basis <- NULL
  for (a in c(
    "source",
    "fetched_at",
    "group",
    "dataset",
    "table",
    "package_version"
  )) {
    attr(bpa, a) <- NULL
  }
  class(bpa) <- setdiff(class(bpa), "cvm_tbl")
  bpa_out <- "tests/testthat/fixtures/mirror-dfp-bpa-ind-2025.parquet"
  write_parquet_via_duckdb(bpa, bpa_out)
  cat(sprintf(
    "[fixture] %s  %d rows, %s bytes\n",
    bpa_out,
    nrow(bpa),
    format(file.info(bpa_out)$size)
  ))
  invisible(NULL)
}

# DFP DRE con 2023: current + history mirror assets (cvm_versions()) ------
# Downloads the two assets of the (dre, con, 2023) partition from the
# release `mirror-companhias-dfp-latest` and cuts both to two issuers
# whose 2023 income statement was re-filed: PETROBRAS (version 1
# superseded on 2024-03-25 by version 2, same net income) and BRASKEM
# (version 1 in R$ units superseded by version 2 "to reflect the R$
# thousand scale", itself superseded by version 3). Four accounts are
# kept so the fixture stays small; every version and reading
# (`ordem_exerc`) of them survives. The history asset carries the five
# columns the current one lacks (`superseded_at`, `superseded_by_versao`,
# `history_source`, `id_doc`, `motivo_reapresentacao`), as published.
build_dre_2023_fixtures <- function() {
  base_url <- paste0(
    "https://github.com/SidneyBissoli/cvmdata/releases/download/",
    "mirror-companhias-dfp-latest/"
  )
  assets <- c(
    current = "dre__report_type.con__year.2023__part-0.parquet",
    history = "dre__report_type.con__year.2023__history.parquet"
  )
  outputs <- c(
    current = "tests/testthat/fixtures/mirror-dfp-dre-con-2023.parquet",
    history = "tests/testthat/fixtures/mirror-dfp-dre-con-2023-history.parquet"
  )
  keep_cnpjs <- c("33.000.167/0001-01", "42.150.391/0001-70")
  keep_accounts <- c("3.01", "3.03", "3.05", "3.11")
  keep_meta <- list(
    list(
      cd_cvm = "009512",
      cnpj_cia = "33.000.167/0001-01",
      denom_cia = "PETROLEO BRASILEIRO S.A. PETROBRAS"
    ),
    list(
      cd_cvm = "004820",
      cnpj_cia = "42.150.391/0001-70",
      denom_cia = "BRASKEM S.A."
    )
  )

  stage <- tempfile("dre2023_fixture_")
  dir.create(stage, recursive = TRUE)
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  sql_list <- function(x) paste(sprintf("'%s'", x), collapse = ", ")
  n_rows <- integer(0)
  for (kind in names(assets)) {
    url <- paste0(base_url, assets[[kind]])
    local <- file.path(stage, assets[[kind]])
    cat(sprintf("[dre2023] Downloading %s\n", url))
    resp <- httr2::req_perform(
      httr2::req_timeout(httr2::request(url), 600L)
    )
    writeBin(httr2::resp_body_raw(resp), local)
    out <- outputs[[kind]]
    if (file.exists(out)) {
      file.remove(out)
    }
    DBI::dbExecute(
      con,
      sprintf(
        paste(
          "COPY (SELECT * FROM read_parquet('%s') WHERE cnpj_cia IN (%s)",
          "AND cd_conta IN (%s) ORDER BY cnpj_cia, versao, ordem_exerc,",
          "cd_conta) TO '%s' (FORMAT 'parquet', COMPRESSION 'snappy')"
        ),
        gsub("\\\\", "/", local),
        sql_list(keep_cnpjs),
        sql_list(keep_accounts),
        gsub("\\\\", "/", out)
      )
    )
    n_rows[[kind]] <- DBI::dbGetQuery(
      con,
      sprintf("SELECT count(*) AS n FROM read_parquet('%s')", out)
    )$n
    meta <- list(
      source_url = url,
      fetched_at = format(Sys.Date()),
      companies_included = keep_meta,
      accounts_included = keep_accounts,
      notes = paste(
        "Subset of the mirror asset filtered by cnpj_cia (PETROBRAS +",
        "BRASKEM) and cd_conta, columns as published. Built for the",
        "cvm_versions() tests: PETROBRAS DFP 2023 has versions 1 and 2",
        "(same net income); BRASKEM has versions 1 (R$ units), 2 (R$",
        "thousand, with motivo_reapresentacao) and 3.",
        if (identical(kind, "history")) {
          "Every row is history_source = 'rad' (recovered from the RAD)."
        } else {
          "Current versions only (3 for BRASKEM, 2 for PETROBRAS)."
        }
      )
    )
    writeLines(
      jsonlite::toJSON(meta, pretty = TRUE, auto_unbox = TRUE),
      paste0(out, ".meta.json")
    )
    cat(sprintf(
      "[fixture] %s  %d rows, %s bytes\n",
      out,
      n_rows[[kind]],
      format(file.info(out)$size)
    ))
  }
  invisible(outputs)
}

# Recompra de acoes raw fixture: the dataset ZIP has no year, and only
# the main table carries the issuer CNPJ. The main table is subset by
# CNPJ_Companhia (BB + MGLU); the two child tables by the ID_Programa of
# the programs kept, so the fixture exercises the issuer_via bridge.
build_recompra_raw_fixture <- function() {
  url <- paste0(
    "https://dados.cvm.gov.br/dados/CIA_ABERTA/EVENTOS/RECOMPRA_ACOES/",
    "DADOS/cia_aberta_recompra_acoes.zip"
  )
  out_zip <- "tests/testthat/fixtures/cia_aberta_recompra_acoes.zip"
  out_meta <- paste0(out_zip, ".meta.json")
  keep_cnpjs <- c("00.000.000/0001-91", "47.960.950/0001-21")
  files <- c(
    "cia_aberta_recompra_acoes.csv",
    "cia_aberta_recompra_acoes_intermediarios.csv",
    "cia_aberta_recompra_acoes_quantidades.csv"
  )

  stage <- tempfile("recompra_fixture_")
  dir.create(stage, recursive = TRUE)
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)
  zip_local <- file.path(stage, basename(url))
  cat(sprintf("[recompra] Downloading %s\n", url))
  resp <- httr2::req_perform(
    httr2::req_timeout(httr2::request(url), 300L)
  )
  writeBin(httr2::resp_body_raw(resp), zip_local)
  extract_dir <- file.path(stage, "extract")
  dir.create(extract_dir)
  utils::unzip(zip_local, exdir = extract_dir)

  # Lines of a CSV and the values of one of its columns (lowercased name).
  read_lines <- function(name, col) {
    path <- file.path(extract_dir, name)
    raw <- readBin(path, "raw", n = file.info(path)$size)
    txt <- iconv(rawToChar(raw), from = "ISO-8859-1", to = "UTF-8")
    lines <- strsplit(txt, "\r?\n", perl = TRUE)[[1L]]
    body <- lines[-1L]
    body <- body[nzchar(body)]
    idx <- which(tolower(strsplit(lines[1L], ";", fixed = TRUE)[[1L]]) == col)
    values <- vapply(
      strsplit(body, ";", fixed = TRUE),
      function(f) f[idx],
      character(1L)
    )
    list(header = lines[1L], body = body, values = values)
  }
  write_subset <- function(name, x, keep) {
    out_raw <- charToRaw(iconv(
      paste(c(x$header, x$body[keep]), collapse = "\r\n"),
      from = "UTF-8",
      to = "ISO-8859-1"
    ))
    writeBin(out_raw, file.path(pack_dir, name))
    sum(keep)
  }

  pack_dir <- file.path(stage, "pack")
  dir.create(pack_dir)
  main <- read_lines(files[[1L]], "cnpj_companhia")
  keep_main <- main$values %in% keep_cnpjs
  ids <- read_lines(files[[1L]], "id_programa")$values[keep_main]
  n_rows <- c(main = write_subset(files[[1L]], main, keep_main))
  for (f in files[-1L]) {
    child <- read_lines(f, "id_programa")
    n_rows[[f]] <- write_subset(f, child, child$values %in% ids)
  }

  if (file.exists(out_zip)) {
    file.remove(out_zip)
  }
  out_zip_abs <- file.path(
    normalizePath(dirname(out_zip), winslash = "/", mustWork = TRUE),
    basename(out_zip)
  )
  withr::with_dir(pack_dir, {
    utils::zip(zipfile = out_zip_abs, files = files, flags = "-q9X")
  })

  # Mirror fixtures of the same subset, one parquet per table, so the
  # issuer_via bridge is tested through source = "mirror" too.
  tables <- c("recompra_acoes", "intermediarios", "quantidades")
  for (k in seq_along(tables)) {
    schema <- cvmdata:::load_schema("recompra_acoes", tables[[k]])
    df <- cvmdata:::read_cvm_csv(
      file.path(pack_dir, files[[k]]),
      schema,
      validate = "skip"
    )
    df <- cvmdata:::apply_schema_transformations(df, schema)
    write_parquet_via_duckdb(
      df,
      sprintf(
        "tests/testthat/fixtures/mirror-recompra_acoes-%s.parquet",
        tables[[k]]
      )
    )
  }

  meta <- list(
    source_url = url,
    fetched_at = format(Sys.Date()),
    companies_included = keep_cnpjs,
    files_included = files,
    notes = paste(
      "Main table subset by CNPJ_Companhia (BCO BRASIL + MAGAZINE LUIZA);",
      "intermediarios and quantidades subset by the ID_Programa of the",
      "programs kept (they carry no issuer column).",
      "ISO-8859-1 encoding preserved. The CVM ZIP has no year."
    )
  )
  writeLines(
    jsonlite::toJSON(meta, pretty = TRUE, auto_unbox = TRUE),
    out_meta
  )
  cat(sprintf(
    "[fixture] %s  %s bytes; rows: %s\n",
    out_zip,
    format(file.info(out_zip)$size),
    paste(n_rows, collapse = "/")
  ))
  invisible(out_zip)
}

# --- dispatch --------------------------------------------------------
if ("parquet" %in% .targets) {
  build_parquet_fixtures()
}
if ("dfp2025" %in% .targets) {
  build_dfp_2025_fixtures()
}
if ("dre2023" %in% .targets) {
  build_dre_2023_fixtures()
}
if ("cgvn" %in% .targets) {
  build_cgvn_raw_fixture()
}
if ("vlmo" %in% .targets) {
  build_vlmo_raw_fixture()
}
if ("fca" %in% .targets) {
  build_fca_raw_fixture()
}
if ("ipe" %in% .targets) {
  build_ipe_raw_fixture()
}
if ("recompra" %in% .targets) {
  build_recompra_raw_fixture()
}
