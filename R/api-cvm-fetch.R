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
#'   then filtered like `cnpj`; the two arguments combine. The lookup
#'   reads every yearly FCA file that carries trading codes (2018
#'   onwards), so the code of a company that has since left the
#'   exchange still resolves, for any `year`. A ticker absent from
#'   every file aborts with `cvmdata_error_input`; so does a ticker
#'   that maps to more than one issuer (pass `cnpj` instead).
#' @param year Integer vector of years to fetch, as the CVM publishes
#'   them (one file per year). `NULL` (default) fetches the latest
#'   available year. Must be `NULL` for datasets with
#'   `temporal_partitioning: none` (e.g. CAD), and cannot be combined
#'   with `from`/`to`. Years the table is not published for are refused
#'   before any download: years before the table's first year, and
#'   years from which the CVM publishes its CSV with the header only
#'   (`fca/departamento_acionistas` from 2024, after Resolução CVM
#'   59/2021 revoked the block). For such a table, `year = NULL` warns
#'   (`cvmdata_warn_empty_upstream`): the mirror returns the last year
#'   with content, the portal returns the latest file, which has zero
#'   rows.
#' @param from,to Optional period bounds, both required together, as
#'   complete dates (`"YYYY-MM-DD"` strings or `Date` scalars). Rows
#'   are kept when the document's reference date (`dt_refer` or
#'   `data_referencia`) falls inside `[from, to]`; the yearly files
#'   read are the years spanned by the interval. Incomplete dates
#'   (`"2024"`, `"2024-06"`) are rejected. Cannot be combined with
#'   `year`, and do not apply to snapshot tables such as CAD.
#' @param as_of Optional complete date (`"YYYY-MM-DD"` or `Date`) for
#'   registry tables only (`cad/companhias`): keeps the registrations
#'   in force on that date, i.e. registered on or before it and not
#'   cancelled by it. The rows are the register as the CVM publishes it
#'   today, not a reconstruction of the past. See the section *Company
#'   register*. Passing it for any other table aborts.
#' @param basis Individual (`"ind"`), consolidated (`"con"`) or both
#'   (`c("ind", "con")`) financial statements. Required for tables
#'   that publish the two variants (`bpa`, `bpp`, `dre`, `dra`,
#'   `dfc_md`, `dfc_mi`, `dmpl`, `dva`): there is no default, because
#'   many issuers file only individual statements. Those tables always
#'   carry a `basis` column in the result, even when a single value
#'   was requested. Must be `NULL` for every other table; passing it
#'   aborts.
#' @param reading Which reading of each fiscal exercise to return, for
#'   the DFP and ITR statement tables (the ones with `ordem_exerc`):
#'   `"original"` (the figures the issuer filed for the exercise, the
#'   `ÚLTIMO` rows of that year's file), `"restated"` (the comparative
#'   figures for the same exercise in the following year's file, the
#'   `PENÚLTIMO` rows there) or `c("original", "restated")`, which
#'   stacks both. `NULL` (default) returns each year's file as the CVM
#'   publishes it, `ÚLTIMO` and `PENÚLTIMO` rows together, without a
#'   `reading` column. When set, `year` names the exercises and the
#'   following year's files are read as needed; the result carries a
#'   `reading` column. See the section *Readings of an exercise*.
#'   Must be `NULL` for tables without `ordem_exerc`; passing it
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
#' @section Filing versions:
#' When a detail table carries several filings for the same issuer and
#' reference date, only the last one delivered is kept, ranked by
#' receipt date, then CVM document id, then `versao`. The version number
#' alone is not a filing key: the CVM index can list two filings under
#' the same version, or a later filing under a lower one.
#'
#' The `submissao` table of each dataset is the filing index and is not
#' collapsed: it returns one row per delivery, re-filings included, with
#' the receipt date (`dt_receb` or `data_entrega`), the document id
#' (`id_doc`, `id_documento` or `protocolo_entrega`) and `versao`. The
#' current filing of an issuer and reference date is the last row by
#' that order; joining `submissao` to a detail table on the issuer and
#' reference date alone matches every delivery.
#'
#' Tables of datasets with a `submissao` index are checked against it
#' before returning. In DFP and ITR tables, rows the CVM file holds twice
#' are dropped (`cvmdata_warn_duplicate_filing`); copies that differ in
#' `vl_conta` are kept (`cvmdata_warn_conflicting_filing`). A table
#' holding an earlier filing than the last delivery keeps the CVM
#' numbers and warns (`cvmdata_warn_stale_filing`). Set
#' `options(cvmdata.check_filings = FALSE)` to skip these checks.
#'
#' @section Readings of an exercise:
#' Every yearly DFP and ITR statement file carries two columns of
#' figures per account: `ordem_exerc = "ÚLTIMO"`, the exercise the
#' file is about, and `ordem_exerc = "PENÚLTIMO"`, the comparative
#' the issuer presented for the previous exercise. The comparative is
#' often not the figure originally filed: issuers restate it after a
#' change of accounting policy, an error or a reorganisation (about a
#' third of the issuers in the DFP, measured on the 2023 file against
#' the 2022 one), and the restated figure is the one later statements
#' build on. With `reading`, `cvm_fetch()` reads the exercise by its
#' own year and labels each row:
#'
#' * `"original"`: the `ÚLTIMO` rows of the file of `year`.
#' * `"restated"`: the `PENÚLTIMO` rows of the file of `year + 1`,
#'   read in addition to (or instead of) the file of `year`. Rows are
#'   returned as the CVM publishes them, so `dt_refer` and `versao`
#'   are those of the following year's document and `dt_fim_exerc`
#'   (and `dt_ini_exerc`) identify the exercise the figure belongs
#'   to. An exercise whose following year's file is not published yet
#'   has no restated reading; the call says so and returns what
#'   exists. When the file exists but the issuer has not filed in it
#'   yet, its restated rows are simply absent.
#'
#' The two readings of an exercise pair on the issuer, the exercise
#' dates, `cd_conta` and, in `dmpl`, `coluna_df`. Either reading can be
#' absent for an issuer (it stopped filing, or started filing in the
#' following year), and a restated figure can be `0` where the issuer
#' presented no comparative at all, as the banks did for 2024 on the
#' individual basis after adopting CMN Resolution 4,966 in 2025. In
#' the ITR, the comparative of the balance sheet (`bpa`, `bpp`) is the
#' previous year end, not the previous year's quarter, so the restated
#' reading of an ITR balance sheet is the year-end balance as the
#' following year's quarterly filings present it.
#'
#' With `from`/`to`, the window applies to the exercise end
#' (`dt_fim_exerc`) rather than to the document date, so an exercise's
#' two readings stay together.
#'
#' @section Company register:
#' `cad/companhias` is a single file holding today's state of every
#' registration the CVM ever granted: companies that cancelled their
#' registration stay in it, with `sit = "CANCELADA"`, `dt_cancel` and
#' `motivo_cancel` (cancellations go back to 1984 and are three quarters
#' of the rows). Its key is `(cnpj_cia, cd_cvm, tp_merc)`, which has two
#' consequences for joins:
#'
#' * A few dozen CNPJs hold **two registrations** (a company that
#'   cancelled and registered again years later under a new CVM code).
#'   These are distinct registrations and the package keeps them apart.
#' * About a hundred registrations are **repeated in two or three rows
#'   that differ only in `tp_merc`** (the markets the company is
#'   admitted to: exchange, organised OTC, non-organised OTC). Every
#'   other column is identical. A join on `cnpj_cia` alone duplicates
#'   those companies. The package returns the file as published; for one
#'   row per registration, drop the market before joining, e.g.
#'   `dplyr::distinct(reg, cnpj_cia, cd_cvm, .keep_all = TRUE)`.
#'   `tp_merc` is empty for almost every cancelled company, so filtering
#'   on it discards delisted companies.
#'
#' `as_of` answers "which companies were registered on date X" from the
#' registration and cancellation dates of each registration, which is
#' what a survivorship-free universe needs. The rows it returns are still
#' today's: a company registered in 2012 and cancelled in 2017 is part of
#' the 2015 universe, but its row says `"CANCELADA"`, because the CVM
#' does not publish past states of the register (the file only records
#' when the current value of each field started). The yearly
#' `fca/geral` file is the CVM's own picture of a company in a given
#' year (name, registration situation, category, issuer situation).
#'
#' @section Arguments by table:
#' `r paste(doc_arguments_by_table(), collapse = "\n")`
#'
#' @return A tibble of class `cvm_tbl` carrying the provenance
#'   attributes `source`, `fetched_at`, `group`, `dataset`, `table`
#'   and `package_version`.
#'
#' @examplesIf interactive()
#' # CAD: single snapshot, no year, no basis
#' issuers <- cvm_fetch("cad", "companhias")
#'
#' # Registrations in force at the end of 2015 (survivorship-free
#' # universe), one row per registration
#' u2015 <- cvm_fetch("cad", "companhias", as_of = "2015-12-31")
#' u2015 <- dplyr::distinct(u2015, cnpj_cia, cd_cvm, .keep_all = TRUE)
#'
#' # A delisted company by its former ticker
#' gol <- cvm_fetch("dfp", "dre", ticker = "GOLL4", year = 2019, basis = "con")
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
#' # Exercise 2022 as originally filed and as restated in the 2023
#' # file, side by side in a `reading` column
#' pssa <- cvm_fetch(
#'   "dfp", "bpa",
#'   ticker = "PSSA3",
#'   year = 2022,
#'   basis = "con",
#'   reading = c("original", "restated")
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
  as_of = NULL,
  basis = NULL,
  reading = NULL,
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
          "{.arg from}/{.arg to}, the statement basis with",
          "{.arg basis} and the exercise reading with {.arg reading}."
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
  reading <- check_reading(reading, schema)
  period <- check_period(year, from, to, schema)
  period <- check_published_years(period, schema)
  warn_empty_latest(period, schema, source)
  as_of <- check_as_of(as_of, schema)
  cnpj <- check_cnpj(cnpj)
  if (!is.null(ticker)) {
    resolved <- resolve_ticker_all_years(check_ticker(ticker), source = source)
    cnpj <- unique(c(cnpj, cnpj_clean(resolved)))
  }

  # One backend call per basis variant and set of yearly files. The
  # closure fixes everything but the variant and the years so the
  # reading logic can ask for the following year's files on its own.
  fetch_files <- function(b, years) {
    out <- issuer_fetch_internal(
      dataset = dataset,
      table = table,
      issuer = cnpj,
      year = years,
      source = source,
      report_type = b,
      on_error = on_error,
      validate = validate
    )
    strip_cvm_tbl(out)
  }
  variants <- if (is.null(basis)) list(NULL) else as.list(basis)
  parts <- lapply(variants, function(b) {
    out <- if (is.null(reading)) {
      fetch_files(b, period$year)
    } else {
      fetch_readings(fetch_files, b, period$year, reading, schema, source)
    }
    if (!is.null(b)) {
      out <- set_basis_column(out, b)
    }
    if (!is.null(reading)) {
      # Argument order is column order: `basis`, then `reading`.
      out <- out[c(setdiff(names(out), "reading"), "reading")]
    }
    out
  })
  out <- if (length(parts) == 1L) {
    parts[[1L]]
  } else {
    vctrs::vec_rbind(!!!parts)
  }
  out <- filter_by_reference_date(
    out,
    period$from,
    period$to,
    schema,
    col = if (is.null(reading)) NULL else "dt_fim_exerc"
  )
  out <- filter_as_of(out, as_of, schema)

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
  if (!table_has_basis(schema)) {
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

# `reading` ------------------------------------------------------------

.reading_values <- c("original", "restated")

# The two values of `ordem_exerc` in the DFP/ITR statement files, as
# the CVM spells them (accented, upper case).
# Built from code points so the source stays ASCII (R CMD check).
.exercise_last <- paste0(intToUtf8(0x00DA), "LTIMO")
.exercise_previous <- paste0("PEN", intToUtf8(0x00DA), "LTIMO")

# Validate `reading` against the table. Only the tables that carry
# `ordem_exerc` (the DFP and ITR statements) have two readings per
# exercise; every other table rejects it. Returns the unique requested
# values in the order given, or NULL.
check_reading <- function(reading, schema) {
  if (is.null(reading)) {
    return(NULL)
  }
  if (!table_has_readings(schema)) {
    cvmdata_abort(
      c(
        paste(
          "Table {.val {schema$dataset}}/{.val {schema$table}} has no",
          "exercise order column ({.var ordem_exerc}); leave",
          "{.arg reading} unset."
        ),
        "x" = "Got {.val {reading}}.",
        "i" = paste(
          "{.arg reading} applies to the DFP and ITR statement tables",
          "({.val bpa}, {.val bpp}, {.val dre}, {.val dra},",
          "{.val dfc_md}, {.val dfc_mi}, {.val dmpl}, {.val dva})."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  if (
    !is.character(reading) ||
      !length(reading) ||
      anyNA(reading) ||
      !all(reading %in% .reading_values)
  ) {
    cvmdata_abort(
      c(
        paste(
          "{.arg reading} must be {.val original}, {.val restated} or",
          "{.code c(\"original\", \"restated\")}."
        ),
        "x" = "Got {.val {reading}}."
      ),
      class = "cvmdata_error_input"
    )
  }
  unique(reading)
}

# Column names the dictionary snapshot declares for the table (empty
# when the table has no dictionary rows).
dictionary_fields <- function(schema) {
  snapshot <- .read_dictionary_snapshot(require_snapshot_path(
    "cvm_dictionary_snapshot.csv",
    "build-dictionary-snapshot.R"
  ))
  hit <- snapshot$group == schema$group &
    snapshot$dataset == schema$dataset &
    snapshot$table == schema$table
  snapshot$campo[hit]
}

# Assemble the requested readings of the exercises named by `years`
# (NULL = the latest year, resolved as the plain fetch resolves it).
# `fetch` reads the yearly files of one basis variant. The original
# reading of exercise N is the ÚLTIMO rows of file N; the restated
# reading is the PENÚLTIMO rows of file N + 1, which is read only
# when published. Rows are returned as published, with a `reading`
# column appended; readings are stacked in the order requested.
fetch_readings <- function(fetch, basis, years, reading, schema, source) {
  need_base <- "original" %in% reading || is.null(years)
  base <- if (need_base) fetch(basis, years) else NULL
  base_years <- if (is.null(base)) integer(0) else file_year(base)
  exercises <- if (is.null(years)) {
    unique(base_years)
  } else {
    as.integer(years)
  }

  rows <- base
  if ("restated" %in% reading && length(exercises)) {
    wanted <- exercises + 1L
    published <- published_file_years(schema, basis, source)
    unpublished <- wanted[!wanted %in% published]
    if (length(unpublished)) {
      inform_restated_unpublished(exercises[wanted %in% unpublished], schema)
    }
    to_read <- setdiff(wanted[wanted %in% published], unique(base_years))
    if (length(to_read)) {
      following <- fetch(basis, to_read)
      rows <- if (is.null(rows)) {
        following
      } else {
        vctrs::vec_rbind(rows, following)
      }
    }
  }
  if (is.null(rows)) {
    # Only the restated reading was asked for and no following year's
    # file exists yet: nothing to read. Shape the empty result like a
    # read of the exercise year's file would.
    rows <- fetch(basis, exercises)[0L, , drop = FALSE]
  }
  if (!"ordem_exerc" %in% names(rows)) {
    cvmdata_abort(
      c(
        paste(
          "Table {.val {schema$dataset}}/{.val {schema$table}} returned",
          "no {.var ordem_exerc} column; {.arg reading} cannot be applied."
        )
      ),
      class = "cvmdata_error_internal"
    )
  }
  row_years <- file_year(rows)
  parts <- lapply(reading, function(r) {
    keep <- if (identical(r, "original")) {
      row_years %in% exercises & rows$ordem_exerc == .exercise_last
    } else {
      (row_years - 1L) %in% exercises & rows$ordem_exerc == .exercise_previous
    }
    out <- rows[!is.na(keep) & keep, , drop = FALSE]
    out$reading <- rep(r, nrow(out))
    out
  })
  if (length(parts) == 1L) {
    parts[[1L]]
  } else {
    vctrs::vec_rbind(!!!parts)
  }
}

# The CVM names each yearly file after the year of the document's
# reference date (`dt_refer`); measured on the mirror for the DFP and
# ITR statements, the two never differ.
file_year <- function(df) {
  ref <- df$dt_refer
  if (!inherits(ref, "Date")) {
    ref <- as.Date(as.character(ref), format = "%Y-%m-%d")
  }
  as.integer(format(ref, "%Y"))
}

# Years whose file exists for the table on the active backend: the
# mirror's asset inventory (cached per session) or the CVM directory
# listing (cached per session as well).
published_file_years <- function(schema, basis, source) {
  if (identical(source, "mirror")) {
    inventory <- mirror_list_assets(schema$group, schema$dataset)
    assets <- filter_mirror_assets(
      inventory,
      table = schema$table,
      year = NULL,
      report_type = basis
    )
    return(sort(unique(as.integer(assets$year))))
  }
  cvm_dataset_years(schema$dataset, schema = schema)
}

inform_restated_unpublished <- function(exercises, schema) {
  following <- exercises + 1L
  cli::cli_inform(c(
    "i" = paste(
      "No restated reading for {.val {exercises}}: the",
      "{.val {schema$dataset}} {cli::qty(length(following))}file{?s} for",
      "{.val {following}} {?is/are} not published yet.",
      "Returning what exists."
    )
  ))
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
  if (!table_is_yearly(schema)) {
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
# convention); a table with neither cannot be windowed. With `reading`
# the caller passes `col = "dt_fim_exerc"`: the window then applies to
# the exercise end, so the restated rows (whose document is dated the
# following year) stay with the exercise they restate.
filter_by_reference_date <- function(df, from, to, schema, col = NULL) {
  if (is.null(from)) {
    return(df)
  }
  if (is.null(col)) {
    col <- first_present(df, c("dt_refer", "data_referencia"))
  } else if (!col %in% names(df)) {
    col <- NULL
  }
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

# Years the table is published for ----------------------------------------

# A table can start later than its dataset: the CVM's yearly ZIP simply
# lacks its CSV before then (composicao_capital from 2020, thirteen FRE
# tables from 2023; measured 2026-10-21 on the mirror's inventory and
# confirmed in the ZIP members). The schema's `first_year` records
# that. Years before it are refused here, before any download, rather
# than failing deep in the backend with a message about ZIP members:
# an explicit `year` aborts; a `from`/`to` window drops the years the
# table does not exist for and says so, unless nothing is left.
#
# The symmetric case: a table can stop carrying content before its
# dataset does. The CVM then still publishes the CSV every year, header
# only, so the portal returns zero rows and the mirror (which skips an
# empty year) has no partition (fca/departamento_acionistas from 2024,
# after Res. CVM 59/2021 revoked the block; measured 2026-10-24). The
# schema's `empty_from` records that, with `empty_reason`. Years from
# it on are handled like the years before `first_year`: refused when
# asked for explicitly, dropped with a message inside a window.
check_published_years <- function(period, schema) {
  if (is.null(period$year)) {
    return(period)
  }
  period <- check_first_year(period, schema)
  check_empty_from(period, schema)
}

check_first_year <- function(period, schema) {
  first <- schema$first_year
  if (is.null(first)) {
    return(period)
  }
  first <- as.integer(first)
  years <- as.integer(period$year)
  early <- years[years < first]
  if (!length(early)) {
    return(period)
  }
  if (is.null(period$from) || length(early) == length(years)) {
    cvmdata_abort(
      c(
        paste(
          "Table {.val {schema$dataset}}/{.val {schema$table}} is not",
          "published for {.val {early}}."
        ),
        "i" = paste(
          "The CVM's {.val {schema$dataset}} files carry it from",
          "{.val {first}} on."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  kept <- years[years >= first]
  cli::cli_inform(c(
    "i" = paste(
      "Table {.val {schema$dataset}}/{.val {schema$table}} is not",
      "published before {.val {first}}; reading {.val {kept}}."
    )
  ))
  period$year <- kept
  period
}

check_empty_from <- function(period, schema) {
  empty <- schema$empty_from
  if (is.null(empty)) {
    return(period)
  }
  empty <- as.integer(empty)
  years <- as.integer(period$year)
  late <- years[years >= empty]
  if (!length(late)) {
    return(period)
  }
  last <- empty - 1L
  if (is.null(period$from) || length(late) == length(years)) {
    cvmdata_abort(
      c(
        paste(
          "Table {.val {schema$dataset}}/{.val {schema$table}} is",
          "published without content from {.val {empty}} on."
        ),
        "x" = "Requested: {.val {late}}.",
        "i" = empty_reason_bullet(schema),
        "i" = "The last year with content is {.val {last}}."
      ),
      class = "cvmdata_error_input"
    )
  }
  kept <- years[years < empty]
  cli::cli_inform(c(
    "i" = paste(
      "Table {.val {schema$dataset}}/{.val {schema$table}} has no",
      "content from {.val {empty}} on; reading {.val {kept}}."
    )
  ))
  period$year <- kept
  period
}

# `year = NULL` on a table with `empty_from`: the user asked for the
# latest year and the latest year the CVM publishes has no content.
# Say so before the backend runs. The two backends then differ, by
# design (decision of 2026-10-24): the mirror has no partition for the
# empty years, so it returns the last year with content; the portal
# reads the latest file as published and returns zero rows. Called by
# cvm_fetch() and cvm_versions() after check_published_years().
warn_empty_latest <- function(period, schema, source) {
  empty <- schema$empty_from
  if (!is.null(period$year) || is.null(empty)) {
    return(invisible(NULL))
  }
  empty <- as.integer(empty)
  last <- empty - 1L
  outcome <- if (identical(source, "mirror")) {
    "Returning {.val {last}}, the last year with content."
  } else {
    paste(
      "The CVM's latest file has no rows; pass {.code year = {last}}",
      "for the last year with content."
    )
  }
  cvmdata_warn(
    c(
      paste(
        "{.code year = NULL}: table",
        "{.val {schema$dataset}}/{.val {schema$table}} is published",
        "without content from {.val {empty}} on."
      ),
      "i" = empty_reason_bullet(schema),
      "i" = outcome
    ),
    class = "cvmdata_warn_empty_upstream"
  )
  invisible(NULL)
}

# The schema's `empty_reason` as a cli bullet, or a neutral sentence
# when the schema has none.
empty_reason_bullet <- function(schema) {
  reason <- schema$empty_reason
  if (is.null(reason)) {
    return("The CVM publishes the CSV for those years with the header only.")
  }
  paste0("Why: ", reason, ".")
}

# `as_of`: registrations in force on a date -------------------------------

# Validate `as_of` against the table. Only registry tables declare in
# their schema which columns hold the registration and cancellation
# dates (`as_of: {registered: ..., cancelled: ...}`; today
# cad/companhias), and only they accept the argument. Returns the
# parsed Date, or NULL.
check_as_of <- function(as_of, schema) {
  if (is.null(as_of)) {
    return(NULL)
  }
  if (!table_is_registry(schema)) {
    cvmdata_abort(
      c(
        paste(
          "Table {.val {schema$dataset}}/{.val {schema$table}} is not a",
          "registry; {.arg as_of} does not apply."
        ),
        "i" = paste(
          "{.arg as_of} keeps the registrations in force on a date and",
          "needs a table with registration and cancellation dates, such",
          "as {.val cad}/{.val companhias}."
        )
      ),
      class = "cvmdata_error_input"
    )
  }
  parse_full_date(as_of, "as_of")
}

# Keep the registrations in force on `as_of`: registered on or before
# the date and not cancelled by it (cancellation date empty or later).
# A row without a registration date cannot be placed in time and is
# dropped (measured 2026-10-21: none in the CAD). The rows kept are the
# register as published today, not the state on `as_of`.
filter_as_of <- function(df, as_of, schema) {
  if (is.null(as_of)) {
    return(df)
  }
  spec <- schema$as_of
  missing_cols <- setdiff(c(spec$registered, spec$cancelled), names(df))
  if (length(missing_cols)) {
    cvmdata_abort(
      c(
        paste(
          "Table {.val {schema$dataset}}/{.val {schema$table}} lacks the",
          "registry date column{?s} its schema declares:",
          "{.code {missing_cols}}."
        )
      ),
      class = "cvmdata_error_internal"
    )
  }
  registered <- as_date_column(df[[spec$registered]])
  cancelled <- as_date_column(df[[spec$cancelled]])
  keep <- !is.na(registered) &
    registered <= as_of &
    (is.na(cancelled) | cancelled > as_of)
  df[keep, , drop = FALSE]
}

# Dates in the CAD arrive as Date through the dictionary; coerce
# defensively so a backend that leaves them as text still compares.
as_date_column <- function(x) {
  if (inherits(x, "Date")) {
    return(x)
  }
  x <- as.character(x)
  x[!nzchar(trimws(x))] <- NA_character_
  as.Date(x, format = "%Y-%m-%d")
}

# Drop the `cvm_tbl` class and provenance attributes from a fetched part
# so the parts can be bound with vctrs and re-stamped once.
strip_cvm_tbl <- function(df) {
  for (a in cvm_tbl_attr_names) {
    attr(df, a) <- NULL
  }
  class(df) <- setdiff(class(df), "cvm_tbl")
  df
}
