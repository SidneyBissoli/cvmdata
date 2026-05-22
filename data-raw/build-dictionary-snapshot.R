#!/usr/bin/env Rscript
# data-raw/build-dictionary-snapshot.R
#
# Reproducible generator for `inst/extdata/cvm_dictionary_snapshot.csv`.
# Downloads the META resources declared in each YAML's
# `cvm_dictionary_url`, parses the CVM-flavoured field descriptors,
# and writes the embedded snapshot consumed by `cvm_dictionary()`.
#
# Usage (from package root):
#   Rscript data-raw/build-dictionary-snapshot.R           # dry run
#   Rscript data-raw/build-dictionary-snapshot.R --write   # persists CSV
#
# Tables with `meta_status: missing` (no CVM-published META) emit one
# row per `expected_field_names` entry with NA fields.

suppressPackageStartupMessages({
  library(tibble)
  library(dplyr)
  library(yaml)
  library(httr2)
  library(readr)
  library(cli)
})

# --- helpers ----------------------------------------------------------

# Split "https://.../foo.zip#entry.txt" into list(zip = url, entry = name).
# Direct .txt URLs (CAD) return list(zip = NA, entry = NA).
split_url <- function(url) {
  if (is.null(url) || is.na(url) || !nzchar(url)) {
    return(list(zip = NA_character_, entry = NA_character_))
  }
  if (grepl("#", url, fixed = TRUE)) {
    parts <- strsplit(url, "#", fixed = TRUE)[[1L]]
    return(list(zip = parts[1L], entry = parts[2L]))
  }
  list(zip = NA_character_, entry = NA_character_)
}

fetch_to_path <- function(url, dest) {
  resp <- httr2::request(url) |>
    httr2::req_timeout(180L) |>
    httr2::req_perform()
  writeBin(httr2::resp_body_raw(resp), dest)
  invisible(dest)
}

# Read an ISO-8859-1 text file as a character vector of lines in UTF-8.
# rawToChar() on R 4.5 Windows marks the result as the native (UTF-8)
# encoding, so a literal `iconv(from = "ISO-8859-1")` is a no-op.
# Marking the string as "latin1" first and then re-encoding to UTF-8 is
# what produces the correct accents.
read_iso_lines <- function(path) {
  raw <- readBin(path, "raw", n = file.info(path)$size)
  text <- rawToChar(raw)
  Encoding(text) <- "latin1"
  text <- enc2utf8(text)
  strsplit(text, "\r?\n", perl = TRUE)[[1L]]
}

# Recognized META keys (UTF-8, accented), mapped to canonical names.
.meta_keys <- list(
  list(key = "Campo",       canonical = "campo"),
  list(key = "Descrição",  canonical = "descricao"),
  list(key = "Domínio",  canonical = "dominio"),
  list(key = "Tipo Dados",  canonical = "tipo_dados"),
  list(key = "Tamanho",     canonical = "tamanho_str"),
  list(key = "Precisão", canonical = "precisao_str"),
  list(key = "Scale",       canonical = "scale_str")
)

# Parse one Campo block (lines from "Campo: <name>" up to the next
# block start or EOF). Returns a one-row tibble.
parse_meta_block <- function(lines) {
  values <- list()
  cur_key <- NULL
  for (line in lines) {
    matched_key <- NULL
    for (mk in .meta_keys) {
      pat <- paste0("^\\s*", mk$key, "\\s*:")
      if (grepl(pat, line, perl = TRUE)) {
        cur_key <- mk$canonical
        value <- sub(pat, "", line, perl = TRUE)
        values[[cur_key]] <- trimws(value)
        matched_key <- TRUE
        break
      }
    }
    if (is.null(matched_key) && !is.null(cur_key)) {
      # Continuation line for the current key. Skip pure separators
      # ("--------") and blank lines.
      if (grepl("^\\s*-+\\s*$", line) || !nzchar(trimws(line))) next
      extra <- trimws(line)
      if (nzchar(values[[cur_key]] %||% "")) {
        values[[cur_key]] <- paste(values[[cur_key]], extra)
      } else {
        values[[cur_key]] <- extra
      }
    }
  }
  to_int <- function(x) suppressWarnings(as.integer(x %||% NA_character_))
  tibble::tibble(
    campo      = values$campo      %||% NA_character_,
    descricao  = values$descricao  %||% NA_character_,
    dominio    = values$dominio    %||% NA_character_,
    tipo_dados = values$tipo_dados %||% NA_character_,
    tamanho    = to_int(values$tamanho_str),
    precisao   = to_int(values$precisao_str),
    scale      = to_int(values$scale_str)
  )
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# Parse a full META .txt file into a tibble with one row per Campo.
parse_meta_txt <- function(path) {
  lines <- read_iso_lines(path)
  campo_idx <- grep("^\\s*Campo\\s*:", lines, perl = TRUE)
  if (!length(campo_idx)) return(tibble::tibble())
  block_end <- c(campo_idx[-1L] - 1L, length(lines))
  records <- vector("list", length(campo_idx))
  for (i in seq_along(campo_idx)) {
    records[[i]] <- parse_meta_block(
      lines[campo_idx[i]:block_end[i]]
    )
  }
  dplyr::bind_rows(records)
}

# --- build ------------------------------------------------------------

# Returns list(rows = <main tibble>, inventory = <per-dataset stats>).
build_dictionary_snapshot <- function() {
  schemas_root <- file.path("inst", "extdata", "schemas")
  datasets <- sort(
    list.dirs(schemas_root, recursive = FALSE, full.names = FALSE)
  )

  # Collect (dataset, table, meta_status, url, expected_field_names)
  yamls <- list()
  for (ds in datasets) {
    yaml_files <- list.files(
      file.path(schemas_root, ds), pattern = "\\.yaml$", full.names = TRUE
    )
    for (yp in yaml_files) {
      y <- yaml::read_yaml(yp)
      yamls[[length(yamls) + 1L]] <- list(
        dataset = ds,
        table = y$table,
        meta_status = y$meta_status %||% "available",
        cvm_dictionary_url = y$cvm_dictionary_url,
        expected_field_names = y$expected_field_names
      )
    }
  }

  # Caches: keyed by URL string.
  download_cache <- new.env(parent = emptyenv())
  zip_extract_cache <- new.env(parent = emptyenv())
  tmp_root <- tempfile("meta_")
  dir.create(tmp_root)

  all_rows <- list()
  for (info in yamls) {
    if (identical(info$meta_status, "missing")) {
      fields <- info$expected_field_names
      if (is.null(fields) || !length(fields)) {
        cli::cli_abort(c(
          paste0(
            "YAML {.val ", info$dataset, "/", info$table,
            "}: meta_status=missing but expected_field_names empty."
          )
        ))
      }
      all_rows[[length(all_rows) + 1L]] <- tibble::tibble(
        dataset    = info$dataset,
        table      = info$table,
        column     = tolower(fields),
        campo      = fields,
        descricao  = NA_character_,
        dominio    = NA_character_,
        tipo_dados = NA_character_,
        tamanho    = NA_integer_,
        precisao   = NA_integer_,
        scale      = NA_integer_,
        meta_status = "missing"
      )
      next
    }

    # meta_status: available
    url <- info$cvm_dictionary_url
    if (is.null(url) || !nzchar(url)) {
      cli::cli_abort(c(
        paste0(
          "YAML {.val ", info$dataset, "/", info$table,
          "}: meta_status=available but cvm_dictionary_url is empty."
        )
      ))
    }
    parts <- split_url(url)

    if (is.na(parts$zip)) {
      # Direct .txt (CAD).
      local <- download_cache[[url]]
      if (is.null(local)) {
        local <- tempfile(tmpdir = tmp_root, fileext = ".txt")
        cli::cli_alert_info("Downloading {.url {url}}")
        fetch_to_path(url, local)
        download_cache[[url]] <- local
      }
      txt_path <- local
    } else {
      # ZIP entry.
      extracted_dir <- zip_extract_cache[[parts$zip]]
      if (is.null(extracted_dir)) {
        zip_local <- tempfile(tmpdir = tmp_root, fileext = ".zip")
        cli::cli_alert_info("Downloading {.url {parts$zip}}")
        fetch_to_path(parts$zip, zip_local)
        extracted_dir <- tempfile("ext_", tmpdir = tmp_root)
        dir.create(extracted_dir)
        utils::unzip(zip_local, exdir = extracted_dir)
        zip_extract_cache[[parts$zip]] <- extracted_dir
      }
      txt_path <- file.path(extracted_dir, parts$entry)
      if (!file.exists(txt_path)) {
        cli::cli_abort(c(
          "Entry {.val {parts$entry}} not found in archive.",
          "i" = "ZIP: {.url {parts$zip}}"
        ))
      }
    }

    entries <- parse_meta_txt(txt_path)
    if (!nrow(entries)) {
      cli::cli_abort(c(
        paste0(
          "No Campo entries parsed from {.path ", basename(txt_path),
          "} ({.val ", info$dataset, "/", info$table, "})."
        )
      ))
    }

    all_rows[[length(all_rows) + 1L]] <- entries |>
      dplyr::mutate(
        dataset = info$dataset,
        table   = info$table,
        column  = tolower(.data$campo),
        meta_status = "available"
      ) |>
      dplyr::select(
        dataset, table, column, campo, descricao, dominio,
        tipo_dados, tamanho, precisao, scale, meta_status
      )
  }

  rows <- dplyr::bind_rows(all_rows)

  # Inventory: per dataset, count META .txt entries actually present
  # in the published source (ZIP archive or single .txt).
  inventory <- list()
  for (ds in datasets) {
    yamls_ds <- Filter(function(y) y$dataset == ds, yamls)
    urls <- unique(unlist(lapply(yamls_ds, function(y) {
      y$cvm_dictionary_url
    })))
    urls <- urls[!is.na(urls) & nzchar(urls)]
    n_entries <- 0L
    if (length(urls)) {
      zips <- unique(vapply(
        urls, function(u) split_url(u)$zip, character(1L)
      ))
      direct_txt_urls <- urls[is.na(vapply(
        urls, function(u) split_url(u)$zip, character(1L)
      ))]
      for (z in zips[!is.na(zips)]) {
        d <- zip_extract_cache[[z]]
        if (!is.null(d)) {
          n_entries <- n_entries + length(
            list.files(d, pattern = "\\.txt$")
          )
        }
      }
      n_entries <- n_entries + length(direct_txt_urls)
    }

    n_tables_yaml <- length(yamls_ds)
    n_tables_available <- sum(vapply(
      yamls_ds, function(y) identical(y$meta_status %||% "available", "available"),
      logical(1L)
    ))
    n_tables_missing <- sum(vapply(
      yamls_ds, function(y) identical(y$meta_status, "missing"),
      logical(1L)
    ))
    inventory[[length(inventory) + 1L]] <- tibble::tibble(
      dataset = ds,
      n_meta_entries_no_zip = n_entries,
      n_tabelas_com_yaml = n_tables_yaml,
      n_tabelas_com_meta_disponivel = n_tables_available,
      n_tabelas_meta_missing = n_tables_missing
    )
  }

  list(
    rows = rows,
    inventory = dplyr::bind_rows(inventory)
  )
}

# --- main -------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
write_mode <- "--write" %in% args

result <- build_dictionary_snapshot()
df <- result$rows

cli::cli_h1("Dictionary snapshot summary")
cli::cli_h2("Per-dataset inventory")
print(result$inventory)

cli::cli_h2("Totals")
cli::cli_bullets(c(
  "*" = "Total rows: {nrow(df)}",
  "*" = "Total (dataset, table) pairs: {dplyr::n_distinct(paste(df$dataset, df$table))}",
  "*" = "Rows with meta_status = missing: {sum(df$meta_status == 'missing')}",
  "*" = "Rows with meta_status = available: {sum(df$meta_status == 'available')}"
))

if (write_mode) {
  out <- file.path("inst", "extdata", "cvm_dictionary_snapshot.csv")
  readr::write_csv(df, out, na = "")
  cli::cli_alert_success("Wrote {.path {out}}")
} else {
  cli::cli_alert_info(
    "Dry run. Re-run with {.code --write} to persist the CSV."
  )
}
