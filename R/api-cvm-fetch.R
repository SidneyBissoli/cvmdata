#' Fetch a CVM open-data table
#'
#' Single public entry point for any table of any dataset covered by
#' the package. Selects the right file, downloads (or serves from the
#' cache or the parquet mirror), parses, applies the schema-declared
#' transformations, filters by issuer and period, and returns a tibble
#' carrying provenance attributes.
#'
#' Column names, categorical values and free-text fields are preserved
#' in Portuguese exactly as published by CVM (snake_case minúsculo).
#'
#' @param dataset Short dataset id (e.g. `"cad"`, `"dfp"`).
#' @param table Snake-case table name (e.g. `"companhias"`, `"bpa"`).
#'   For tables published in individual and consolidated variants,
#'   `table` is the concept name and `basis` selects the variant(s).
#' @param cnpj Optional character vector of issuer CNPJs, with or
#'   without punctuation (`"00.000.000/0001-91"` or
#'   `"00000000000191"`). Only CNPJs are accepted: a CVM code or a
#'   company name aborts with `cvmdata_error_input`. `NULL` (default)
#'   keeps every issuer. A CNPJ absent from the table yields zero rows
#'   for it, silently.
#' @param ticker Optional character vector of B3 trading codes
#'   (`"PETR4"`, `"BBAS3"`). Each ticker is resolved to its issuer CNPJ
#'   through `fca/valor_mobiliario` (read from the same `source`) and
#'   then filtered like `cnpj`; the two arguments combine. A ticker
#'   absent from the lookup aborts with `cvmdata_error_input`.
#' @param year Integer vector of years to fetch, as the CVM publishes
#'   them (one file per year). `NULL` (default) fetches the latest
#'   available year. Must be `NULL` for datasets with
#'   `temporal_partitioning: none` (e.g. CAD), and cannot be combined
#'   with `from`/`to`.
#' @param from,to Optional period bounds, both required together, as
#'   complete dates (`"YYYY-MM-DD"` strings or `Date` scalars). Rows
#'   are kept when the document's reference date (`dt_refer` or
#'   `data_referencia`) falls inside `[from, to]`; the yearly files
#'   read are the years spanned by the interval. Incomplete dates
#'   (`"2024"`, `"2024-06"`) are rejected. Cannot be combined with
#'   `year`, and do not apply to snapshot tables such as CAD.
#' @param basis Individual (`"ind"`), consolidated (`"con"`) or both
#'   (`c("ind", "con")`) financial statements. Required for tables
#'   that publish the two variants (`bpa`, `bpp`, `dre`, `dra`,
#'   `dfc_md`, `dfc_mi`, `dmpl`, `dva`): there is no default, because
#'   many issuers file only individual statements. Those tables always
#'   carry a `basis` column in the result, even when a single value
#'   was requested. Must be `NULL` for every other table; passing it
#'   aborts.
#' @param source One of `"mirror"` (parquet via DuckDB) or `"cvm"`
#'   (CVM Open Data Portal). `NULL` (default) resolves to the active
#'   backend via [cvm_source_get()].
#' @param on_error One of `"abort"` (default), `"warn"` or `"silent"`.
#'   Controls behaviour on HTTP failures when several yearly files are
#'   read (`year` with more than one element, or a `from`/`to` window
#'   spanning several years). With `"warn"`, the failed years are
#'   skipped and a `cvmdata_warn_partial_failure` warning lists them;
#'   with `"silent"`, they are skipped silently; with `"abort"`, the
#'   first failure aborts the call. Total failure always aborts.
#' @param validate One of `"strict"` (default), `"warn"` or `"skip"`.
#'   Controls schema validation strictness at parse time.
#' @param ... Reserved for forward compatibility. Currently no extra
#'   arguments are accepted; passing any aborts with
#'   `cvmdata_error_input`.
#'
#' @inheritSection issuer_fetch Filing versions
#'
#' @return A tibble of class `cvm_tbl` carrying the provenance
#'   attributes `source`, `fetched_at`, `group`, `dataset`, `table`
#'   and `package_version`.
#'
#' @examplesIf interactive()
#' # CAD: single snapshot, no year, no basis
#' issuers <- cvm_fetch("cad", "companhias")
#'
#' # DFP balance sheet (assets), individual statements, latest year,
#' # one issuer by CNPJ
#' bb <- cvm_fetch("dfp", "bpa", cnpj = "00.000.000/0001-91", basis = "ind")
#'
#' # Both bases, 2022 to 2024, issuer by B3 ticker
#' petr <- cvm_fetch(
#'   "dfp", "dre",
#'   ticker = "PETR4",
#'   year = 2022:2024,
#'   basis = c("ind", "con")
#' )
#'
#' # ITR by reference date: the quarters of the first half of 2024
#' h1 <- cvm_fetch(
#'   "itr", "bpa",
#'   from = "2024-01-01", to = "2024-06-30",
#'   basis = "con"
#' )
#'
#' @family fetchers
#' @export
cvm_fetch <- function(
  dataset,
  table,
  cnpj = NULL,
  ticker = NULL,
  year = NULL,
  from = NULL,
  to = NULL,
  basis = NULL,
  source = NULL,
  on_error = "abort",
  validate = "strict",
  ...
) {
  dots <- list(...)
  if (length(dots) > 0L) {
    nms <- names(dots) %||% rep("", length(dots))
    nms[!nzchar(nms)] <- "<unnamed>"
    cvmdata_abort(
      c(
        "Unknown argument{?s}: {.arg {nms}}.",
        "i" = paste(
          "{.fn cvm_fetch} selects issuers with {.arg cnpj} or",
          "{.arg ticker}, the period with {.arg year} or",
          "{.arg from}/{.arg to}, and the statement basis with",
          "{.arg basis}."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  if (is.null(source)) {
    source <- cvm_source_get()
  }
  source <- rlang::arg_match0(source, c("mirror", "cvm"))

  schema <- load_schema(dataset, table)
  basis <- check_basis(basis, schema)
  period <- check_period(year, from, to, schema)
  cnpj <- check_cnpj(cnpj)
  if (!is.null(ticker)) {
    resolved <- resolve_ticker_via_fca(
      check_ticker(ticker),
      year = ticker_lookup_year(period),
      source = source
    )
    cnpj <- unique(c(cnpj, cnpj_clean(resolved)))
  }

  variants <- if (is.null(basis)) list(NULL) else as.list(basis)
  parts <- lapply(variants, function(b) {
    out <- issuer_fetch_internal(
      dataset = dataset,
      table = table,
      issuer = cnpj,
      year = period$year,
      source = source,
      report_type = b,
      on_error = on_error,
      validate = validate
    )
    out <- strip_cvm_tbl(out)
    if (!is.null(b)) {
      out <- set_basis_column(out, b)
    }
    out
  })
  out <- if (length(parts) == 1L) {
    parts[[1L]]
  } else {
    vctrs::vec_rbind(!!!parts)
  }
  out <- filter_by_reference_date(out, period$from, period$to, schema)

  cvm_attach_metadata(
    out,
    source = source,
    group = schema$group,
    dataset = dataset,
    table = table
  )
}

# `basis` ---------------------------------------------------------------

.basis_values <- c("ind", "con")

# Validate `basis` against the table. Tables with ind/con variants
# require it (no default: many issuers file only individual
# statements, so defaulting to "con" would silently drop them); every
# other table rejects it. Returns the unique requested values, or NULL
# for tables without the split.
check_basis <- function(basis, schema) {
  has_variants <- !is.null(schema$cvm_file_pattern_variants)
  if (!has_variants) {
    if (!is.null(basis)) {
      cvmdata_abort(
        c(
          paste(
            "Table {.val {schema$dataset}}/{.val {schema$table}} has no",
            "individual/consolidated split; leave {.arg basis} unset."
          ),
          "x" = "Got {.val {basis}}."
        ),
        class = "cvmdata_error_input"
      )
    }
    return(NULL)
  }
  if (is.null(basis)) {
    cvmdata_abort(
      c(
        paste(
          "Table {.val {schema$dataset}}/{.val {schema$table}} requires",
          "{.arg basis}."
        ),
        "i" = paste(
          "Pass {.code basis = \"ind\"} for individual statements,",
          "{.code basis = \"con\"} for consolidated, or",
          "{.code basis = c(\"ind\", \"con\")} for both."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  if (
    !is.character(basis) ||
      !length(basis) ||
      anyNA(basis) ||
      !all(basis %in% .basis_values)
  ) {
    cvmdata_abort(
      c(
        paste(
          "{.arg basis} must be {.val ind}, {.val con} or",
          "{.code c(\"ind\", \"con\")}."
        ),
        "x" = "Got {.val {basis}}."
      ),
      class = "cvmdata_error_input"
    )
  }
  unique(basis)
}

# Stamp the requested basis on every row. The mirror reattaches the
# partition value as a `report_type` column; `cvm_fetch()` exposes that
# information under the public name `basis` only, so the leaked column
# is removed before the new one is appended.
set_basis_column <- function(df, basis) {
  df$report_type <- NULL
  df$basis <- rep(basis, nrow(df))
  df
}

# Period: `year` xor `from`/`to` ---------------------------------------

# Validate the period arguments and return a list with the yearly
# files to read (`year`) and the reference-date window (`from`, `to`),
# NULL when no window was requested. `year` and the window are
# mutually exclusive; the window requires both bounds as complete
# dates and only applies to yearly-partitioned tables.
check_period <- function(year, from, to, schema) {
  has_window <- !is.null(from) || !is.null(to)
  if (!has_window) {
    return(list(year = year, from = NULL, to = NULL))
  }
  if (!is.null(year)) {
    cvmdata_abort(
      c(
        paste(
          "Use either {.arg year} or {.arg from}/{.arg to} to select",
          "the period, not both."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  if (is.null(from) || is.null(to)) {
    cvmdata_abort(
      c(
        "{.arg from} and {.arg to} must be given together.",
        "i" = paste(
          "For whole years use {.arg year}; for an open-ended window",
          "pass an explicit far bound."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  from <- parse_full_date(from, "from")
  to <- parse_full_date(to, "to")
  if (from > to) {
    cvmdata_abort(
      c(
        "{.arg from} must not be later than {.arg to}.",
        "x" = "Got {.val {format(from)}} to {.val {format(to)}}."
      ),
      class = "cvmdata_error_input"
    )
  }
  partitioning <- schema$temporal_partitioning %||% "none"
  if (!identical(partitioning, "yearly")) {
    cvmdata_abort(
      c(
        paste(
          "Table {.val {schema$dataset}}/{.val {schema$table}} is a",
          "single snapshot without reference dates;",
          "{.arg from}/{.arg to} do not apply."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  years <- seq.int(date_year(from), date_year(to))
  list(year = years, from = from, to = to)
}

# Accept a single complete date: a `Date` scalar or a `"YYYY-MM-DD"`
# string. Partial dates ("2024", "2024-06") and other formats abort.
parse_full_date <- function(x, arg) {
  if (inherits(x, "Date")) {
    if (length(x) != 1L || is.na(x)) {
      cvmdata_abort(
        "{.arg {arg}} must be a single, non-missing date.",
        class = "cvmdata_error_input"
      )
    }
    return(x)
  }
  if (
    !is.character(x) ||
      length(x) != 1L ||
      is.na(x) ||
      !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x)
  ) {
    cvmdata_abort(
      c(
        "{.arg {arg}} must be a complete date ({.val YYYY-MM-DD}).",
        "x" = "Got {.val {x}}."
      ),
      class = "cvmdata_error_input"
    )
  }
  parsed <- as.Date(x, format = "%Y-%m-%d")
  if (is.na(parsed)) {
    cvmdata_abort(
      c(
        "{.arg {arg}} is not a valid calendar date.",
        "x" = "Got {.val {x}}."
      ),
      class = "cvmdata_error_input"
    )
  }
  parsed
}

date_year <- function(d) {
  as.integer(format(d, "%Y"))
}

# Keep the rows whose document reference date falls inside the window.
# No-op when no window was requested. Every yearly table carries
# `dt_refer` (CAD/ITR/DFP convention) or `data_referencia` (FRE-detail
# convention); a table with neither cannot be windowed.
filter_by_reference_date <- function(df, from, to, schema) {
  if (is.null(from)) {
    return(df)
  }
  col <- first_present(df, c("dt_refer", "data_referencia"))
  if (is.null(col)) {
    cvmdata_abort(
      c(
        paste(
          "Table {.val {schema$dataset}}/{.val {schema$table}} has no",
          "reference-date column; {.arg from}/{.arg to} do not apply."
        ),
        "i" = "Use {.arg year} instead."
      ),
      class = "cvmdata_error_input"
    )
  }
  ref <- df[[col]]
  if (!inherits(ref, "Date")) {
    ref <- as.Date(as.character(ref), format = "%Y-%m-%d")
  }
  keep <- !is.na(ref) & ref >= from & ref <= to
  df[keep, , drop = FALSE]
}

# Issuer selectors --------------------------------------------------------

# Validate `cnpj`: character, every element with exactly 14 digits once
# punctuation is stripped. Returns the unique digits-only forms. CVM
# codes and names are deliberately rejected — `cvm_fetch()` identifies
# issuers by CNPJ or B3 ticker only.
check_cnpj <- function(cnpj) {
  if (is.null(cnpj)) {
    return(NULL)
  }
  if (!is.character(cnpj)) {
    cvmdata_abort(
      c(
        "{.arg cnpj} must be a character vector.",
        "i" = paste(
          "Quote the number so leading zeros survive:",
          "{.code cnpj = \"00000000000191\"}."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  digits <- cnpj_clean(cnpj)
  bad <- is.na(digits) | nchar(digits) != 14L
  if (any(bad)) {
    cvmdata_abort(
      c(
        paste(
          "{.arg cnpj} accepts only CNPJ numbers (14 digits, with or",
          "without punctuation)."
        ),
        "x" = "Not a CNPJ: {.val {cnpj[bad]}}.",
        "i" = paste(
          "CVM codes and company names are not accepted here; use",
          "{.arg ticker} for a B3 trading code."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  unique(digits)
}

# Validate `ticker`: character, B3 trading-code shape (four letters,
# one or two digits, optional suffix letter). Returns the upper-cased,
# trimmed, unique codes.
check_ticker <- function(ticker) {
  if (!is.character(ticker) || !length(ticker) || anyNA(ticker)) {
    cvmdata_abort(
      "{.arg ticker} must be a character vector of B3 trading codes.",
      class = "cvmdata_error_input"
    )
  }
  up <- toupper(trimws(ticker))
  bad <- !grepl("^[A-Z]{4}[0-9]{1,2}[A-Z]?$", up)
  if (any(bad)) {
    cvmdata_abort(
      c(
        "{.arg ticker} must look like a B3 trading code (e.g. {.val PETR4}).",
        "x" = "Not a ticker: {.val {ticker[bad]}}.",
        "i" = "To select by taxpayer id use {.arg cnpj}."
      ),
      class = "cvmdata_error_input"
    )
  }
  unique(up)
}

# Which fca/valor_mobiliario year to resolve tickers against: the most
# recent year of the request, or NULL (latest available) when the
# request itself asks for the latest year.
ticker_lookup_year <- function(period) {
  if (is.null(period$year)) {
    return(NULL)
  }
  max(as.integer(period$year))
}

# Drop the `cvm_tbl` class and provenance attributes from a fetched part
# so the parts can be bound with vctrs and re-stamped once.
strip_cvm_tbl <- function(df) {
  for (a in c(
    "source",
    "fetched_at",
    "group",
    "dataset",
    "table",
    "package_version"
  )) {
    attr(df, a) <- NULL
  }
  class(df) <- setdiff(class(df), "cvm_tbl")
  df
}
