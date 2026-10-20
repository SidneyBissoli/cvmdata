# Fetch-time checks of a table against the CVM filing index.
#
# Two defects of the CVM files, measured on 2026-10-18, motivate this
# step (defects #14 and #15 of the data-defects article):
#
#   * Repeated rows. The DFP and ITR statement CSVs repeat rows of an
#     issuer: 884 issuer-period-table cases in 2010-2026 have the whole
#     statement doubled, 110 more a few accounts (sweep of 2026-10-18).
#     Some come from two filings under the same VERSAO in the index
#     (TRV XLIII DFP 2023, Dibens Leasing ITR 2023-09-30); most have a
#     single filing. A statement carries one row per account, order and
#     period, so identical rows are dropped here, with a warning naming
#     the issuers; rows that differ only in `vl_conta` are kept and
#     warned about louder, since no rule can say which one is right.
#
#   * Stale filing. The CVM builds the statement CSVs from the highest
#     VERSAO, so a filing delivered later under a lower VERSAO
#     (Travessia VI DFP 2024: versions 1, 2 and again 1, the last one
#     being the filing the issuer carries forward) never reaches them.
#     The table keeps the CVM numbers; a warning names the issuers whose
#     latest delivery is not the one in the table.
#
# The step runs after the backend returns, so both sources (mirror and
# cvm) get the same checks. `options(cvmdata.check_filings = FALSE)`
# turns it off.

# Datasets whose tables hold at most one row per account and period of
# a filing, so an identical row can only be a repeated one. Elsewhere
# identical rows are legitimate: in `vlmo`, two officers receiving the
# same share grant on the same day give two identical rows.
.duplicate_filing_datasets <- c("dfp", "itr")

check_filings <- function(df, schema, dataset, table, year, source, validate) {
  if (!isTRUE(getOption("cvmdata.check_filings", TRUE))) {
    return(df)
  }
  if (!nrow(df) || identical(table, "submissao")) {
    return(df)
  }
  cnpj_c <- first_present(df, c("cnpj_cia", "cnpj_companhia"))
  date_c <- first_present(df, c("dt_refer", "data_referencia"))
  if (is.null(cnpj_c) || is.null(date_c) || !"versao" %in% names(df)) {
    return(df)
  }
  if (dataset %in% .duplicate_filing_datasets) {
    df <- drop_duplicate_filings(df, cnpj_c, date_c)
  }
  warn_stale_filings(
    df,
    dataset = dataset,
    table = table,
    year = year,
    source = source,
    validate = validate,
    cnpj_c = cnpj_c,
    date_c = date_c
  )
  df
}

drop_duplicate_filings <- function(df, cnpj_c, date_c) {
  dup <- vctrs::vec_duplicate_detect(df)
  if (any(dup)) {
    first_copy <- vctrs::vec_duplicate_id(df) == seq_len(nrow(df))
    affected <- filing_labels(df[dup, , drop = FALSE], cnpj_c, date_c)
    df <- df[first_copy, , drop = FALSE]
    cvmdata_warn(
      c(
        paste(
          "The CVM file repeats rows for {length(affected)} filing{?s};",
          "the identical copies were dropped."
        ),
        bullet_labels(affected),
        "i" = paste(
          "A statement has one row per account and period, so sums",
          "over the raw file count these twice. See {.url {(.defects_url)}}."
        )
      ),
      class = "cvmdata_warn_duplicate_filing"
    )
  }
  if ("vl_conta" %in% names(df)) {
    rest <- df[, setdiff(names(df), "vl_conta"), drop = FALSE]
    clash <- vctrs::vec_duplicate_detect(rest)
    if (any(clash)) {
      affected <- filing_labels(df[clash, , drop = FALSE], cnpj_c, date_c)
      cvmdata_warn(
        c(
          paste(
            "{length(affected)} filing{?s} appear{?s/} twice with",
            "different {.field vl_conta}; both copies were kept."
          ),
          bullet_labels(affected),
          "!" = paste(
            "The CVM file gives no way to tell which copy is current.",
            "Sums over these issuers count both."
          )
        ),
        class = "cvmdata_warn_conflicting_filing"
      )
    }
  }
  df
}

# Compare the `versao` of each (cnpj, date) in `df` with the one of the
# filing the index says was delivered last.
warn_stale_filings <- function(
  df,
  dataset,
  table,
  year,
  source,
  validate,
  cnpj_c,
  date_c
) {
  if (!nrow(list_schema_candidates(dataset, "submissao"))) {
    return(invisible())
  }
  years <- year %||% unique(as.integer(format(as.Date(df[[date_c]]), "%Y")))
  years <- years[!is.na(years)]
  if (!length(years)) {
    return(invisible())
  }
  sub <- tryCatch(
    suppressWarnings(issuer_fetch_internal(
      dataset = dataset,
      table = "submissao",
      year = years,
      source = source,
      on_error = "silent",
      validate = validate
    )),
    error = function(e) NULL
  )
  if (is.null(sub) || !nrow(sub)) {
    return(invisible())
  }
  # The index lists every delivery of a filing (the `submissao` schemas
  # declare no `keep_latest_version` since 0.2.0.9000), so the filing
  # the issuer carries forward is computed here: the last one delivered
  # per (cnpj, date), ranked by receipt date, document id and `versao`.
  # The `match()` below needs one row per key; on the raw index it
  # would pick the first delivery listed, which in the CVM files is the
  # oldest one.
  sub <- tx_keep_latest_version(
    sub,
    tx = list(action = "keep_latest_version"),
    schema = list(dataset = dataset, table = "submissao")
  )
  sub_cnpj <- first_present(sub, c("cnpj_cia", "cnpj_companhia"))
  sub_date <- first_present(sub, c("dt_refer", "data_referencia"))
  if (is.null(sub_cnpj) || is.null(sub_date)) {
    return(invisible())
  }
  current_key <- filing_key(sub[[sub_cnpj]], sub[[sub_date]])
  have_key <- filing_key(df[[cnpj_c]], df[[date_c]])
  expected <- as.character(sub$versao)[match(have_key, current_key)]
  stale <- !is.na(expected) & as.character(df$versao) != expected
  if (!any(stale)) {
    return(invisible())
  }
  affected <- filing_labels(df[stale, , drop = FALSE], cnpj_c, date_c)
  cvmdata_warn(
    c(
      paste(
        "{length(affected)} filing{?s} in {.val {dataset}}/{.val {table}}",
        "{?is/are} not the latest delivery in the CVM filing index."
      ),
      bullet_labels(affected),
      "i" = paste(
        "The CVM file kept an earlier filing; the issuer delivered a",
        "later one under a lower {.field versao}. Its numbers are not",
        "in the CVM file. See {.url {(.defects_url)}}."
      )
    ),
    class = "cvmdata_warn_stale_filing"
  )
  invisible()
}

filing_key <- function(cnpj, date) {
  date <- if (inherits(date, "Date")) format(date) else as.character(date)
  paste(as.character(cnpj), substr(date, 1L, 10L), sep = "|")
}

filing_labels <- function(df, cnpj_c, date_c) {
  name_c <- first_present(
    df,
    c("denom_cia", "nome_companhia", "nome_empresarial")
  )
  who <- if (is.null(name_c)) df[[cnpj_c]] else df[[name_c]]
  date <- df[[date_c]]
  date <- if (inherits(date, "Date")) format(date) else as.character(date)
  unique(paste0(who, " (", substr(date, 1L, 10L), ")"))
}

.max_labels <- 5L

# Named cli bullets ("*") for at most `.max_labels` issuers.
bullet_labels <- function(x) {
  out <- x[seq_len(min(length(x), .max_labels))]
  if (length(x) > .max_labels) {
    out <- c(out, sprintf("and %d more", length(x) - .max_labels))
  }
  # cli would read braces in issuer names as glue expressions.
  out <- gsub("}", "}}", gsub("{", "{{", out, fixed = TRUE), fixed = TRUE)
  stats::setNames(out, rep("*", length(out)))
}

.defects_url <- paste0(
  "https://sidneybissoli.github.io/cvmdata/",
  "articles/data-defects.html"
)
