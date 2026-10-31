# ETL helper: read one DFP/ITR document of the CVM "RAD" system (the
# ENET document archive) into the tables of the package.
#
# The CVM annual CSV keeps only the filing delivered last for each
# (company, reference date). The earlier filings exist only as documents
# in the RAD, one ZIP per `id_doc` of the `submissao` table. This file
# turns such a ZIP into the eight statements of the dfp/itr datasets
# (bpa, bpp, dre, dra, dfc_md, dfc_mi, dmpl, dva; individual and
# consolidated) with EXACTLY the columns, types and conventions of the
# mirror parquets, so the rows can be appended to the history assets
# (`<table>__report_type=R__year=Y__history.parquet`, util-history.R)
# next to the rows the mirror itself supersedes.
#
# Two layouts exist, both measured on real documents (2026-10-20):
#
# * NEW (documents from ~2012 on): the ZIP holds one XML whose root is
#   `XmlDemonstracoesFinanceiras` (DFP) or
#   `XmlInformacoesTrimestraisFinanceiras` (ITR), with the statements
#   under `Formulario/DfIndividuais` and `Formulario/DfConsolidadas`.
#   Each `Conta` carries one value element per period column, named by
#   period (`UltimoExercicio`, `TrimestreAtual`, ...). The DMPL has one
#   `DMPL` node per period with the equity components as elements (or,
#   in one consolidated variant, as `DadosContas/CamposDadosContas`).
# * OLD (2010-2011 and early 2012): the ZIP holds a `.dfp`/`.itr` file,
#   itself a ZIP of XML tables: `Documento.xml` (metadata),
#   `PeriodoDemonstracaoFinanceira.xml` (period ids and dates),
#   `InfoFinaDFin.xml` (one record per account and statement with
#   `ValorConta1`..`ValorConta12`) and
#   `InformacaoFinanceiraDemonstracaoFinanceira.xml` (which value
#   columns each statement has).
#
# Conventions reproduced from the CSV (calibrated against the mirror):
#
# * An account is kept only if its description is non-empty, whether it
#   is a fixed account of the chart or not. The description loses its
#   surrounding spaces and then its line breaks, as the CVM converter
#   does; the per-share accounts `3.99*` are "N" in `st_conta_fixa`
#   whatever the XML says.
# * `st_conta_fixa` is otherwise the document's own flag. The CSV takes
#   it from the chart of accounts in force when the file is GENERATED,
#   so for a few accounts whose status changed between chart versions
#   the two differ (30 rows in 3 of the 60 calibration documents, all
#   ITR 2019). Accepted by the owner on 2026-10-20: the document's flag
#   is the one that held when the filing was delivered.
# * Only the two most recent periods are kept (`ÚLTIMO`, `PENÚLTIMO`);
#   the DFP XML also carries the third one, the CSV does not.
# * Two period columns with the same dates (first quarter: the quarter
#   and the year-to-date) collapse into one row; the CSV keeps the value
#   of the accumulated column.
# * An empty value element of a kept account is 0.
# * Values are published in the scale the document declares (2 = MIL);
#   `vl_conta` is in reais, as the package's `multiply_by_scale` does.
# * The DMPL column labels (`coluna_df`) are POSITIONAL: the n-th value
#   column takes the n-th label of a fixed list of eight, and a ninth
#   column (the consolidated equity of a bank, in both layouts) has no
#   label. The CSV does the same, even where it mislabels (Banrisul DFP
#   2011, individual).
#
# Numbers come in three spellings: `14.410` (dot as thousands
# separator), `31159,0000000000` / `0,00635` (comma decimal) and
# `29547.0000000000` (old layout, dot decimal with ten places). Any
# other spelling marks the document as doubtful.
#
# Identity columns (`cnpj_cia`, `denom_cia`, `cd_cvm`, `versao`,
# `dt_refer`) come from the `submissao` row of the document when the
# caller passes it: the CSV takes them from the registry, not from the
# document (case differs). The document's own values are checked
# against the row.
#
# Sourced (not loaded as a package). Pure: no network. The caller
# downloads (see `rad_download()`), reads, and decides what to do with
# `problems`: any problem means the WHOLE document is set aside.

stopifnot(requireNamespace("xml2", quietly = TRUE))
stopifnot(requireNamespace("digest", quietly = TRUE))
stopifnot(requireNamespace("tibble", quietly = TRUE))

`%||%` <- function(x, y) if (is.null(x)) y else x # nolint: object_name_linter.

rad_ordem_ultimo <- "ÚLTIMO"
rad_ordem_penultimo <- "PENÚLTIMO"

# The eight statements: the XML element of the new layout, the
# `CodigoTipoDemonstracaoFinanceira` of the old one, the CSV label.
rad_tables <- data.frame(
  table = c("bpa", "bpp", "dre", "dra", "dfc_md", "dfc_mi", "dmpl", "dva"),
  xml_new = c(
    "BalancoPatrimonialAtivo",
    "BalancoPatrimonialPassivo",
    "DemonstracaoResultado",
    "DemonstracaoResultadoAbrangente",
    "DemonstracaoFluxoCaixa",
    "DemonstracaoFluxoCaixa",
    "DemonstracaoMutacoesPatrimonioLiquido",
    "DemonstracaoValorAdicionado"
  ),
  code_old = c("2", "3", "4", "5", "6", "7", "8", "9"),
  label = c(
    "Balanço Patrimonial Ativo",
    "Balanço Patrimonial Passivo",
    "Demonstração do Resultado",
    "Demonstração de Resultado Abrangente",
    "Demonstração do Fluxo de Caixa (Método Direto)",
    "Demonstração do Fluxo de Caixa (Método Indireto)",
    paste0(
      "Demonstração das Mutações do ",
      "Patrimônio Líquido"
    ),
    "Demonstração de Valor Adicionado"
  ),
  stringsAsFactors = FALSE
)

# `grupo_dfp` as the CSV spells it.
rad_grupo_dfp <- function(table, report_type) {
  label <- rad_tables$label[match(table, rad_tables$table)]
  prefix <- ifelse(report_type == "con", "DF Consolidado", "DF Individual")
  paste0(prefix, " - ", label)
}

# DMPL column labels, in the positional order the CSV uses.
rad_dmpl_labels <- c(
  "Capital Social Integralizado",
  paste0(
    "Reservas de Capital, Opções Outorgadas e ",
    "Ações em Tesouraria"
  ),
  "Reservas de Lucro",
  "Lucros ou Prejuízos Acumulados",
  "Outros Resultados Abrangentes",
  "Patrimônio Líquido",
  "Participação dos Não Controladores",
  "Patrimônio Líquido Consolidado"
)

# New-layout DMPL element names the CVM converter knows. The n-th element
# PRESENT in the document is the n-th CSV column, labelled by its
# position in `rad_dmpl_labels` (a ninth column has no label), and the
# columns come in the DOCUMENT's order, which depends on the template the
# company filed with: a financial institution writes
# `AjustesAvaliacaoPatrimonial` before `LucroPrejuizoAcumulado` in one
# template (Banestes, Pine, Daycoval, Banese) and after it in another
# (BTG Pactual, Itaú, with `ReservasReavaliacao` third), and the CSV
# follows each. Measured account by account against the DFP 2025 CSV on
# 2026-10-20/21 (six current versions, zero differences). In the
# individual DMPL of a bank the CSV therefore writes the adjustments under
# "Lucros ou Prejuízos Acumulados" or "Patrimônio Líquido" and the equity
# total under "Participação dos Não Controladores". An element outside
# this set sets the document aside: the labels are positional, so an
# unmeasured element would silently shift every column after it.
rad_dmpl_tags <- c(
  "CapitalSocialIntegralizado",
  "ReservasCapital",
  "ReservasCapitalOpcoesOutorgAcoesTesour",
  "ReservasReavaliacao",
  "ReservasLucro",
  "AjustesAvaliacaoPatrimonial",
  "LucroPrejuizoAcumulado",
  "OutrosResultadosAbrangentes",
  "PatrimonioLiquido",
  "PatrimonioLiquidoAcionistasControl",
  "PatrimonioLiquidoAcionistasNaoControl",
  "PatrimonioLiquidoConsolidado"
)

# The one place the converter does NOT follow the document: the three-way
# equity split of a consolidated DMPL is written as controlling (column
# 7), non-controlling (8) and consolidated total (the unlabelled 9),
# although the XML writes the total before the non-controlling interest.
rad_dmpl_tail <- c(
  "PatrimonioLiquidoAcionistasControl",
  "PatrimonioLiquidoAcionistasNaoControl",
  "PatrimonioLiquidoConsolidado"
)

# DMPL columns the CSV carries: the eight labels plus one without label.
rad_dmpl_max_cols <- length(rad_dmpl_labels) + 1L

# Columns of each table, in CSV order (`escala_moeda` already dropped).
rad_table_columns <- function(table) {
  head <- c(
    "cnpj_cia",
    "dt_refer",
    "versao",
    "denom_cia",
    "cd_cvm",
    "grupo_dfp",
    "moeda",
    "ordem_exerc"
  )
  tail <- c("cd_conta", "ds_conta", "vl_conta", "st_conta_fixa")
  if (table %in% c("bpa", "bpp")) {
    return(c(head, "dt_fim_exerc", tail))
  }
  if (table == "dmpl") {
    return(c(head, "dt_ini_exerc", "dt_fim_exerc", "coluna_df", tail))
  }
  c(head, "dt_ini_exerc", "dt_fim_exerc", tail)
}

# --- download ---------------------------------------------------------

rad_user_agent <- paste0(
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ",
  "(KHTML, like Gecko) Chrome/130.0 Safari/537.36"
)

# The `link_doc` of `submissao` is http and answers 403; https with a
# browser user agent answers 200 (measured 2026-10-16).
rad_document_url <- function(id_doc) {
  paste0(
    "https://www.rad.cvm.gov.br/ENETCONSULTA/frmDownloadDocumento.aspx",
    "?CodigoInstituicao=1&NumeroSequencialDocumento=",
    as.character(id_doc)
  )
}

# Downloads one document to `dest` (a .zip path). Returns
# list(ok, status, bytes, seconds, error). The RAD answers
# `Content-Type: text/html` even for the ZIP, so the body is checked by
# its magic bytes, not by the header. A 403 or an HTML body is how the
# WAF refuses: the caller pauses and retries the document, and stops
# the whole round only when every try is refused.
#
# The download gives up when the connection STALLS (below
# `rad_download_stall_bps` for `rad_download_stall_secs`) or past
# `timeout`, a ceiling. Until 2026-10-23 `timeout` was 180 s of total
# time, and a document with a huge embedded PDF never fitted: NEXPE DFP
# 2021 (59 MB received in 180 s) and Orizon DFP 2020 (126 MB) failed on
# every attempt. Decision of 2026-10-23: a stalled connection is the
# failure, size is not. The window was 60 s on the first full round
# (2026-10-24): 29 downloads died of it in one day (16 dfp, 13 itr) and
# 14 of the 16 dfp passed whole on the next attempt — the RAD stops
# sending for more than a minute and resumes. Decision of 2026-10-24:
# 180 s, the ceiling unchanged.
rad_download_stall_bps <- 1024
rad_download_stall_secs <- 180
rad_download_timeout <- 900

rad_download_request <- function(id_doc, timeout = rad_download_timeout) {
  req <- httr2::request(rad_document_url(id_doc))
  req <- httr2::req_user_agent(req, rad_user_agent)
  req <- httr2::req_timeout(req, timeout)
  httr2::req_options(
    req,
    low_speed_limit = rad_download_stall_bps,
    low_speed_time = rad_download_stall_secs
  )
}

rad_download <- function(id_doc, dest, timeout = rad_download_timeout) {
  stopifnot(requireNamespace("httr2", quietly = TRUE))
  t0 <- Sys.time()
  out <- list(
    ok = FALSE,
    status = NA_integer_,
    bytes = NA_real_,
    seconds = NA_real_,
    error = NA_character_
  )
  req <- rad_download_request(id_doc, timeout)
  resp <- tryCatch(
    httr2::req_perform(req, path = dest),
    httr2_http = function(e) e$resp,
    error = function(e) e
  )
  out$seconds <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  if (inherits(resp, "error")) {
    out$error <- conditionMessage(resp)
    return(out)
  }
  out$status <- httr2::resp_status(resp)
  if (out$status != 200L) {
    out$error <- paste0("HTTP ", out$status)
    if (file.exists(dest)) {
      unlink(dest)
    }
    return(out)
  }
  out$bytes <- file.size(dest)
  if (!rad_is_zip(dest)) {
    head <- rad_body_head(dest)
    # an empty body says nothing: it stays a refusal, the cautious side
    out$error <- if (!nzchar(trimws(head)) || rad_looks_like_html(head)) {
      paste0("body is not a ZIP (WAF page?): ", rad_snippet(head))
    } else {
      paste0(
        "the RAD answered an error instead of the ZIP: ",
        rad_snippet(head)
      )
    }
    unlink(dest)
    return(out)
  }
  out$ok <- TRUE
  out
}

rad_is_zip <- function(path) {
  if (!file.exists(path) || file.size(path) < 4) {
    return(FALSE)
  }
  con <- file(path, "rb")
  on.exit(close(con))
  identical(readBin(con, "raw", 2L), as.raw(c(0x50, 0x4b)))
}

# A body that is not a ZIP is either a page (the WAF refusing) or the
# RAD's own error text in plain `text/html`. Measured 2026-10-30: ITR
# 67723 (Autopista Planalto Sul, 2017-06-30) answers 200 with the .NET
# message "Index was out of range. Must be non-negative and less than
# the size of the collection." on every request, from any network; the
# robot took it for the WAF, retried it and stopped the whole itr round
# of 2026-10-29. Only markup is a refusal now: plain text is a document
# the RAD cannot serve, set aside like any download failure. The head of
# the body goes into the note either way, so the WAF page gets measured.
rad_body_head <- function(path, n = 2048L) {
  if (!file.exists(path)) {
    return("")
  }
  con <- file(path, "rb")
  on.exit(close(con))
  raw <- readBin(con, "raw", n)
  raw <- raw[raw != as.raw(0)]
  iconv(rawToChar(raw), "UTF-8", "UTF-8", sub = "?")
}

rad_looks_like_html <- function(head) {
  grepl(
    "<\\s*(!doctype|html|head|body|script|meta|title)\\b",
    head,
    ignore.case = TRUE
  )
}

rad_snippet <- function(head, n = 120L) {
  s <- trimws(gsub("\\s+", " ", head))
  if (nchar(s) > n) paste0(substr(s, 1L, n), "...") else s
}

# --- reading: entry point ---------------------------------------------

# Reads one downloaded ZIP. `filing` is the `submissao` row of the
# document (list or one-row data frame with cnpj_cia, dt_refer, versao,
# denom_cia, cd_cvm, id_doc, dt_receb) or NULL. Returns
# list(meta, tables, problems):
#   meta     list(layout, dataset, id_doc, cnpj_cia, cd_cvm, denom_cia,
#            dt_refer, versao, versao_doc, moeda, escala,
#            tipo_apresentacao, motivo_reapresentacao, xml_hash)
#   tables   named list "<table>/<report_type>" -> tibble with the
#            columns of `rad_table_columns(table)`; empty statements are
#            absent
#   problems character(0) when the document is trustworthy
#   index_mismatch TRUE when the document is not the one the index
#            row describes (cnpj or dt_refer differ): the document is
#            set aside for what it IS, not for how it was read. The
#            fetch stage keeps such a failure out of the reader's
#            failure rate.
rad_read_zip <- function(zip, filing = NULL) {
  stopifnot(file.exists(zip))
  entries <- utils::unzip(zip, list = TRUE)$Name
  tmp <- tempfile("rad-")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  old <- entries[grepl("\\.(dfp|itr)$", entries, ignore.case = TRUE)]
  if (length(old) == 1L) {
    inner <- utils::unzip(zip, files = old, exdir = tmp)
    res <- rad_read_old(inner)
  } else {
    xmls <- entries[grepl("\\.xml$", entries, ignore.case = TRUE)]
    xmls <- xmls[!grepl("^Formulario", basename(xmls))]
    if (length(xmls) != 1L) {
      return(rad_result(
        problems = paste0(
          "cannot find the statements XML in the ZIP (",
          length(xmls),
          " candidates)"
        ),
        kind = "document"
      ))
    }
    path <- utils::unzip(zip, files = xmls, exdir = tmp)
    res <- rad_read_new(path)
  }
  rad_finish(res, filing)
}

# `kind` names who is to blame when the reader gives up before reading:
# "document" when the ZIP is not a DFP/ITR at all (the index of the ITR
# 2023 lists id 132214 for Dibens Leasing; the RAD serves an IPE under
# that number), NULL when the decision is left to the caller.
rad_result <- function(
  meta = list(),
  rows = NULL,
  problems = character(),
  kind = NULL
) {
  list(meta = meta, rows = rows, problems = problems, kind = kind)
}

# Cross-checks the document against its `submissao` row, applies the
# identity columns and splits the long table.
rad_finish <- function(res, filing) {
  problems <- res$problems
  meta <- res$meta
  index_mismatch <- FALSE
  if (is.null(meta$dt_refer)) {
    # nothing was read (not a DFP/ITR, or the old layout is incomplete):
    # no document to cross-check against the index. Until 2026-10-23 the
    # checks below ran on the empty meta and the reader crashed on the
    # IPE of id 132214 ("missing value where TRUE/FALSE needed").
    return(list(
      meta = meta,
      tables = list(),
      problems = problems,
      index_mismatch = FALSE,
      kind = res$kind
    ))
  }
  if (!is.null(filing)) {
    checked <- rad_apply_filing(meta, as.list(filing))
    meta <- checked$meta
    problems <- c(problems, checked$problems)
    index_mismatch <- length(checked$problems) > 0L
  } else {
    meta$cnpj_cia <- rad_format_cnpj(meta$cnpj_cia)
    meta$cd_cvm <- rad_format_cd_cvm(meta$cd_cvm)
  }
  if (!identical(meta$moeda, "1")) {
    problems <- c(
      problems,
      paste0("currency code is not 1 (REAL): ", meta$moeda)
    )
  }
  factor <- rad_scale_factor(meta$escala)
  if (is.na(factor)) {
    problems <- c(problems, paste0("unknown scale code: ", meta$escala))
  }
  tables <- list()
  rows <- res$rows
  if (!is.null(rows) && nrow(rows) > 0L) {
    bad <- is.na(rows$vl_conta)
    if (any(bad)) {
      problems <- c(
        problems,
        sprintf(
          "%d values could not be parsed (e.g. %s)",
          sum(bad),
          paste(utils::head(unique(rows$raw[bad]), 3L), collapse = ", ")
        )
      )
    }
    rows$vl_conta <- rows$vl_conta * (if (is.na(factor)) 1 else factor)
    rows$cnpj_cia <- meta$cnpj_cia
    rows$dt_refer <- meta$dt_refer
    rows$versao <- meta$versao
    rows$denom_cia <- meta$denom_cia
    rows$cd_cvm <- meta$cd_cvm
    rows$moeda <- "REAL"
    rows$grupo_dfp <- rad_grupo_dfp(rows$table, rows$report_type)
    tables <- rad_split(rows)
  }
  list(
    meta = meta,
    tables = tables,
    problems = problems,
    index_mismatch = index_mismatch,
    kind = res$kind
  )
}

# A document filed under a BRANCH's CNPJ is the company's: the first
# eight digits (the root, which identifies the company) and the CVM code
# both match the index. Pacaembu Construtora, ITR 2020-09-30 v1 (id
# 98410): the document carries 96.298.013/0002-49, the index and the CSV
# the head office 0001-68, CVM code 025143 on both. Decision of the
# owner, 2026-10-25: accepted; the rows carry the index's identity, as
# every row does. A different root, or the same root with another CVM
# code, is still another document.
rad_same_company <- function(doc_cnpj, idx_cnpj, doc_cd, idx_cd) {
  doc_cd <- rad_format_cd_cvm(doc_cd)
  idx_cd <- rad_format_cd_cvm(idx_cd)
  nchar(doc_cnpj) == 14L &&
    nchar(idx_cnpj) == 14L &&
    identical(substr(doc_cnpj, 1L, 8L), substr(idx_cnpj, 1L, 8L)) &&
    !is.na(doc_cd) &&
    identical(doc_cd, idx_cd)
}

# The identity of the filing comes from the index; the document is
# checked against it. The version inside the document can differ from
# the index (Travessia VI, DFP 2024: the index says 2, the XML says 1);
# the CSV takes the index, so the document's is kept as a note only.
rad_apply_filing <- function(meta, filing) {
  problems <- character()
  doc_cnpj <- gsub("[^0-9]", "", meta$cnpj_cia %||% "")
  idx_cnpj <- gsub("[^0-9]", "", filing$cnpj_cia)
  if (grepl("^0+$", doc_cnpj)) {
    # a blank CNPJ (all zeros: Inter & Co, DFP 2021, a company abroad)
    # is not a different CNPJ; the identity is then checked by the CVM
    # code, which the index lists for the delivery (decision of
    # 2026-10-23). The rows carry the index's identity either way.
    doc_cd <- rad_format_cd_cvm(meta$cd_cvm)
    idx_cd <- rad_format_cd_cvm(filing$cd_cvm)
    if (is.na(doc_cd) || !identical(doc_cd, idx_cd)) {
      problems <- c(
        problems,
        sprintf(
          paste0(
            "cnpj blank in the document and cd_cvm (%s) ",
            "differs from the index (%s)"
          ),
          doc_cd,
          idx_cd
        )
      )
    }
  } else if (
    nzchar(doc_cnpj) &&
      doc_cnpj != idx_cnpj &&
      !rad_same_company(doc_cnpj, idx_cnpj, meta$cd_cvm, filing$cd_cvm)
  ) {
    problems <- c(
      problems,
      sprintf(
        "cnpj in the document (%s) differs from the index (%s)",
        doc_cnpj,
        idx_cnpj
      )
    )
  }
  idx_refer <- as.Date(filing$dt_refer)
  if (!is.na(meta$dt_refer) && !identical(meta$dt_refer, idx_refer)) {
    problems <- c(
      problems,
      sprintf(
        "dt_refer in the document (%s) differs from the index (%s)",
        meta$dt_refer,
        idx_refer
      )
    )
  }
  meta$versao_doc <- meta$versao
  meta$cnpj_cia <- filing$cnpj_cia
  meta$denom_cia <- filing$denom_cia
  meta$cd_cvm <- as.character(filing$cd_cvm)
  meta$versao <- as.character(filing$versao)
  meta$dt_refer <- idx_refer
  meta$id_doc <- as.character(filing$id_doc)
  list(meta = meta, problems = problems)
}

rad_split <- function(rows) {
  key <- paste(rows$table, rows$report_type, sep = "/")
  out <- list()
  for (k in unique(key)) {
    part <- rows[key == k, , drop = FALSE]
    cols <- rad_table_columns(part$table[[1L]])
    # CSV order: account (as listed), then DMPL column, then period
    acct <- match(part$cd_conta, unique(part$cd_conta[order(part$seq)]))
    part <- part[order(acct, part$col, part$dt_fim_exerc), , drop = FALSE]
    out[[k]] <- tibble::as_tibble(part[, cols, drop = FALSE])
  }
  out
}

# --- values -----------------------------------------------------------

# Parses the three spellings. NA for anything else; "" is 0.
# `per_share` flags the per-share accounts (3.99*), see the end.
rad_parse_number <- function(x, per_share = FALSE) {
  x <- trimws(x)
  per_share <- rep_len(per_share, length(x))
  out <- rep(NA_real_, length(x))
  out[!nzchar(x)] <- 0
  comma <- grepl("^-?[0-9]{1,3}(\\.[0-9]{3})*,[0-9]+$", x) |
    grepl("^-?[0-9]+,[0-9]+$", x)
  plain <- gsub(".", "", x[comma], fixed = TRUE)
  out[comma] <- as.numeric(gsub(",", ".", plain, fixed = TRUE))
  decimal <- grepl("^-?[0-9]+\\.[0-9]{4,}$", x)
  out[decimal] <- as.numeric(x[decimal])
  # `1.461.169` and `1461169` are both integers in thousands
  grouped <- grepl("^-?[0-9]+$", x) | grepl("^-?[0-9]{1,3}(\\.[0-9]{3})+$", x)
  out[grouped] <- as.numeric(gsub(".", "", x[grouped], fixed = TRUE))
  # `-0.05`: a dot after a lone zero is a decimal point, whatever the
  # number of digits (no thousands group starts with 0). Meliuz, ITR
  # 2021-06-30 v1 (id 107950), per-share accounts; the CSV has -0.05.
  zero_dot <- grepl("^-?0\\.[0-9]+$", x)
  out[zero_dot] <- as.numeric(x[zero_dot])
  # Scientific notation, as a serializer of some filer wrote the
  # per-share accounts (Magazine Luiza, ITR 2021-06-30 v1, id 107658,
  # set aside on 2026-10-25). The mantissa sometimes lost its decimal
  # point: `55E-2`, `53999999999999999E-2`, `-50000000000000001E-3`
  # next to `1.4999999999999999E-2` in the same document. The CVM
  # converter reads them as 5.5E-2, 5.3999...E-2 and -5.0...E-3 (the
  # CSV has 0.055, 0.054 and -0.005 there, measured on 2026-10-25), so
  # a mantissa without a point gets it after its first digit.
  sci <- grepl("^-?[0-9]+(\\.[0-9]+)?[Ee][-+]?[0-9]+$", x)
  if (any(sci)) {
    mant <- sub("[Ee].*$", "", x[sci])
    expo <- sub("^[^Ee]*[Ee]", "", x[sci])
    no_point <- !grepl(".", mant, fixed = TRUE)
    mant[no_point] <- sub("^(-?[0-9])", "\\1.", mant[no_point])
    out[sci] <- as.numeric(paste0(mant, "e", expo))
  }
  # The same lost point without an exponent, in the per-share accounts
  # of the same two documents: `-002`, `-001`, `123`, `24` where the CSV
  # has -0.02, -0.01, 1.23 and 2.4. A per-share value written in digits
  # only, with more than one digit, gets the point after its first
  # digit. Measured on 2026-10-25 against 15 other RAD documents (both
  # layouts, 2011-2025): their digits-only per-share values are all `0`,
  # which the rule leaves alone.
  lost <- per_share & grepl("^-?[0-9]{2,}$", x)
  out[lost] <- as.numeric(sub("^(-?[0-9])", "\\1.", x[lost]))
  out
}

# Scale code of the document -> multiplier to reais. The CSV spells the
# same codes as UNIDADE / MIL (R/transform-schema.R `scale_factor`).
rad_scale_factor <- function(code) {
  switch(as.character(code), "1" = 1, "2" = 1e3, NA_real_)
}

rad_format_cnpj <- function(digits) {
  d <- gsub("[^0-9]", "", digits %||% "")
  if (nchar(d) != 14L) {
    return(NA_character_)
  }
  sub("^(..)(...)(...)(....)(..)$", "\\1.\\2.\\3/\\4-\\5", d)
}

rad_format_cd_cvm <- function(code) {
  d <- gsub("[^0-9]", "", code %||% "")
  if (!nzchar(d)) {
    return(NA_character_)
  }
  formatC(as.integer(d), width = 6L, flag = "0")
}

rad_date_br <- function(x) {
  as.Date(x, format = "%d/%m/%Y")
}

rad_date_iso <- function(x) {
  as.Date(substr(x, 1L, 10L))
}

# `d` one year earlier. Statement dates are month starts and month
# ends; the one date without a counterpart is 29 February, the close of
# a fiscal year in a leap year (Camil DFP 2020-02-29, set aside on
# 2026-10-24: `as.Date("2019-02-29")` without a format ERRORS instead of
# returning NA). Its previous exercise closes on the 28th, as the CSV
# writes it (ordem_exerc PENÚLTIMO on 2019-02-28).
rad_year_before <- function(d) {
  y <- as.integer(format(d, "%Y")) - 1L
  m <- as.integer(format(d, "%m"))
  dd <- as.integer(format(d, "%d"))
  out <- as.Date(sprintf("%04d-%02d-%02d", y, m, dd), format = "%Y-%m-%d")
  feb29 <- !is.na(d) & is.na(out) & m == 2L & dd == 29L
  out[feb29] <- as.Date(sprintf("%04d-02-28", y[feb29]), format = "%Y-%m-%d")
  out
}

# ordem_exerc from the end date of a period: the reference date is
# ÚLTIMO, anything ending within the year before it is PENÚLTIMO, older
# periods (the third exercise of the DFP) are dropped (NA).
rad_ordem <- function(dt_fim, dt_refer) {
  out <- rep(NA_character_, length(dt_fim))
  out[!is.na(dt_fim) & dt_fim == dt_refer] <- rad_ordem_ultimo
  prev <- !is.na(dt_fim) &
    dt_fim < dt_refer &
    dt_fim >= rad_year_before(dt_refer)
  out[prev] <- rad_ordem_penultimo
  out
}

# One period column: `tag` is the name of the value column in `contas`,
# `col` the DMPL column position (1 otherwise), `rank` the order used by
# the duplicate rule (the accumulated column ranks higher).
rad_cols <- function(tag, dt_ini, dt_fim, col = 1L, rank = seq_along(tag)) {
  data.frame(
    tag = tag,
    dt_ini = dt_ini,
    dt_fim = dt_fim,
    col = col,
    rank = rank,
    stringsAsFactors = FALSE
  )
}

# The long rows of one statement: `contas` has one row per account with
# `seq`, `cd_conta`, `ds_conta`, `st_conta_fixa` and one raw value
# column per `cols$tag`.
rad_rows <- function(table, report_type, contas, cols, dt_refer) {
  if (nrow(contas) == 0L || nrow(cols) == 0L) {
    return(NULL)
  }
  contas <- contas[nzchar(contas$ds_conta), , drop = FALSE]
  if (nrow(contas) == 0L) {
    return(NULL)
  }
  n <- nrow(contas)
  m <- nrow(cols)
  idx_c <- rep(seq_len(n), times = m)
  idx_k <- rep(seq_len(m), each = n)
  raw <- unlist(
    lapply(seq_len(m), function(j) contas[[cols$tag[j]]]),
    use.names = FALSE
  )
  out <- data.frame(
    table = table,
    report_type = report_type,
    seq = contas$seq[idx_c],
    cd_conta = contas$cd_conta[idx_c],
    ds_conta = contas$ds_conta[idx_c],
    st_conta_fixa = contas$st_conta_fixa[idx_c],
    col = cols$col[idx_k],
    coluna_df = rad_dmpl_labels[cols$col[idx_k]],
    dt_ini_exerc = cols$dt_ini[idx_k],
    dt_fim_exerc = cols$dt_fim[idx_k],
    rank = cols$rank[idx_k],
    raw = raw,
    stringsAsFactors = FALSE
  )
  if (table != "dmpl") {
    out$coluna_df <- NA_character_
  }
  out$ordem_exerc <- rad_ordem(out$dt_fim_exerc, dt_refer)
  out <- out[!is.na(out$ordem_exerc), , drop = FALSE]
  # a statement with every value empty is a statement the company did
  # not present (consolidated of a company without subsidiaries)
  if (nrow(out) == 0L || all(!nzchar(trimws(out$raw)))) {
    return(NULL)
  }
  # duplicate periods (quarter == year-to-date): keep the accumulated
  # column, which ranks higher
  out <- out[order(out$rank), , drop = FALSE]
  dup_key <- paste(out$seq, out$col, out$dt_ini_exerc, out$dt_fim_exerc)
  out <- out[!duplicated(dup_key, fromLast = TRUE), , drop = FALSE]
  out$vl_conta <- rad_parse_number(
    out$raw,
    per_share = grepl("^3\\.99", out$cd_conta)
  )
  out
}

rad_bind <- function(rows) {
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (length(rows) == 0L) {
    return(NULL)
  }
  do.call(rbind, rows)
}

xml_text1 <- function(node, xpath) {
  xml2::xml_text(xml2::xml_find_first(node, xpath))
}

# `xml2::read_xml()` on a document file, without libxml2's size limits
# (`HUGE`). A RAD document embeds its PDF as one base64 text node; when
# the PDF exceeds 10 MB (5 of the 73 DFP 2025 read on 2026-10-20, e.g.
# REVEE id 155949, a 20 MB XML), libxml2 2.9 stops at the node and
# refuses the rest as "Extra content at the end of the document", while
# libxml2 2.12 warns "huge text node" and goes on. The statements are
# intact either way; the limit is what is lifted.
rad_read_xml <- function(path) {
  xml2::read_xml(path, options = c("NOBLANKS", "HUGE"))
}

# --- new layout -------------------------------------------------------

rad_read_new <- function(path) {
  doc <- rad_read_xml(path)
  dataset <- switch(
    xml2::xml_name(doc),
    XmlDemonstracoesFinanceiras = "dfp",
    XmlInformacoesTrimestraisFinanceiras = "itr",
    NA_character_
  )
  if (is.na(dataset)) {
    # not a DFP/ITR: an IPE (`Documento`) served under an ITR id
    return(rad_result(
      problems = paste0("unknown XML root: ", xml2::xml_name(doc)),
      kind = "document"
    ))
  }
  data <- xml2::xml_find_first(
    doc,
    if (dataset == "dfp") "./DadosDFP" else "./DadosITR"
  )
  meta <- rad_new_meta(doc, data, dataset, path)
  if (is.na(meta$dt_refer)) {
    return(rad_result(meta, problems = "DataReferencia missing"))
  }
  cols <- rad_new_columns(data, dataset, meta$dt_refer)
  problems <- character()
  rows <- list()
  for (basis in c("ind", "con")) {
    node <- xml2::xml_find_first(
      data,
      paste0(
        "./Formulario/",
        if (basis == "ind") "DfIndividuais" else "DfConsolidadas"
      )
    )
    if (inherits(node, "xml_missing")) {
      next
    }
    for (i in which(rad_tables$table != "dfc_mi")) {
      st <- xml2::xml_find_first(node, paste0("./", rad_tables$xml_new[i]))
      if (inherits(st, "xml_missing")) {
        next
      }
      r <- rad_new_statement(st, rad_tables$table[i], basis, cols, meta)
      rows <- c(rows, r$rows)
      problems <- c(problems, r$problems)
    }
  }
  rad_result(meta, rad_bind(rows), problems)
}

rad_new_meta <- function(doc, data, dataset, path) {
  list(
    layout = "new",
    dataset = dataset,
    cnpj_cia = xml_text1(doc, "./DadosEmpresa/CnpjEmpresa"),
    cd_cvm = xml_text1(doc, "./DadosEmpresa/CodigoCvm"),
    denom_cia = xml_text1(doc, "./DadosEmpresa/RazaoSocialEmpresa"),
    dt_refer = rad_date_br(xml_text1(data, "./DataReferencia")),
    versao = xml_text1(doc, "./Documento/VersaoDocumento"),
    moeda = xml_text1(data, "./Moeda"),
    escala = xml_text1(data, "./EscalaMoeda"),
    tipo_apresentacao = xml_text1(doc, "./Documento/TipoApresentacao"),
    motivo_reapresentacao = xml_text1(doc, "./Documento/MotivoReapresentacao"),
    xml_hash = digest::digest(path, algo = "sha256", file = TRUE)
  )
}

# The period columns of the new layout: list(flow, balance, cash) with
# the element names and the dates each one stands for. The ITR header
# gives the current quarter and the two fiscal years; the previous-year
# quarter and year-to-date are the same windows one year earlier.
rad_new_columns <- function(data, dataset, dt_refer) {
  d <- function(xpath) rad_date_br(xml_text1(data, xpath))
  if (dataset == "dfp") {
    flow <- rad_cols(
      tag = c("PenultimoExercicio", "UltimoExercicio"),
      dt_ini = c(
        d("./DtInicioPenultimoExercicioSocial"),
        d("./DtInicioUltimoExercicioSocial")
      ),
      dt_fim = c(
        d("./DtFimPenultimoExercicioSocial"),
        d("./DtFimUltimoExercicioSocial")
      )
    )
    balance <- flow
    balance$dt_ini <- as.Date(NA)
    return(list(flow = flow, balance = balance, cash = flow))
  }
  q_ini <- d("./DtInicioTrimestreAtual")
  q_fim <- d("./DtFimTrimestreAtual")
  y_ini <- d("./DtInicioExercicioSocialCurso")
  a_ini <- d("./DtInicioExercicioSocialAnterior")
  flow <- rad_cols(
    tag = c(
      "TrimestreAnterior",
      "AcumuladoExercicioAnterior",
      "TrimestreAtual",
      "AcumuladoExercicioAtual"
    ),
    dt_ini = c(rad_year_before(q_ini), a_ini, q_ini, y_ini),
    dt_fim = c(
      rad_year_before(q_fim),
      rad_year_before(dt_refer),
      q_fim,
      dt_refer
    )
  )
  balance <- rad_cols(
    tag = c("ExercicioAnterior", "TrimestreAtual"),
    dt_ini = as.Date(NA),
    dt_fim = c(d("./DtFimExercicioSocialAnterior"), dt_refer)
  )
  # the DFC and the DVA of the ITR spell their accumulated columns apart
  cash <- flow[flow$rank %in% c(2L, 4L), , drop = FALSE]
  cash$tag[cash$rank == 4L] <- "AcumuladoAtualExercicio"
  list(flow = flow, balance = balance, cash = cash)
}

# One statement node -> list(rows, problems). The cash-flow statement is
# split into the two method tables by its `Metodo` element.
rad_new_statement <- function(st, table, basis, cols, meta) {
  problems <- character()
  if (table == "dmpl") {
    return(rad_new_dmpl(st, basis, meta$dt_refer))
  }
  contas <- rad_new_contas(xml2::xml_find_all(st, "./Conta"))
  if (nrow(contas) == 0L) {
    return(list(rows = list(), problems = problems))
  }
  spec <- if (table %in% c("bpa", "bpp")) {
    cols$balance
  } else if (table %in% c("dfc_md", "dva")) {
    cols$cash
  } else {
    cols$flow
  }
  missing <- setdiff(spec$tag, names(contas))
  if (length(missing)) {
    return(list(
      rows = list(),
      problems = sprintf(
        "%s/%s: value elements %s not found",
        table,
        basis,
        paste(missing, collapse = ",")
      )
    ))
  }
  if (table != "dfc_md") {
    return(list(
      rows = list(rad_rows(table, basis, contas, spec, meta$dt_refer)),
      problems = problems
    ))
  }
  metodo <- contas$Metodo %||% rep("", nrow(contas))
  rows <- list(
    rad_rows(
      "dfc_md",
      basis,
      contas[metodo == "Direto", ],
      spec,
      meta$dt_refer
    ),
    rad_rows(
      "dfc_mi",
      basis,
      contas[metodo == "Indireto", ],
      spec,
      meta$dt_refer
    )
  )
  unknown <- unique(metodo[!metodo %in% c("Direto", "Indireto")])
  if (length(unknown)) {
    problems <- sprintf(
      "dfc/%s: unknown cash-flow method %s",
      basis,
      paste(unknown, collapse = ",")
    )
  }
  list(rows = rows, problems = problems)
}

# `Conta` nodes -> data frame with one column per child element plus
# the normalised account columns.
rad_new_contas <- function(nodes) {
  if (length(nodes) == 0L) {
    return(data.frame())
  }
  tags <- unique(xml2::xml_name(xml2::xml_children(nodes[[1L]])))
  tags <- tags[!tags %in% "DadosContas"]
  out <- lapply(tags, function(t) {
    xml2::xml_text(xml2::xml_find_first(nodes, paste0("./", t)))
  })
  names(out) <- tags
  out <- as.data.frame(out, stringsAsFactors = FALSE, check.names = FALSE)
  out[is.na(out)] <- ""
  out$seq <- seq_along(nodes)
  rad_account_columns(out, out$CodigoConta, out$DescricaoConta, out$ContaFixa)
}

# The account columns as the CSV spells them: the description as the
# CVM converter writes it (`rad_csv_text`), and the per-share accounts
# (`3.99*`) flagged as not fixed whatever the XML says (calibrated
# 2026-10-20: 240 of 240 such rows in the mirror are "N").
rad_account_columns <- function(df, codigo, descricao, fixa) {
  df$cd_conta <- codigo
  df$ds_conta <- rad_csv_text(descricao)
  df$st_conta_fixa <- ifelse(tolower(fixa) == "true", "S", "N")
  df$st_conta_fixa[grepl("^3\\.99", df$cd_conta)] <- "N"
  df
}

# Free text as the CVM CSV carries it, measured against the raw CSV
# files (2026-10-20): SPACES at both ends are removed first, then line
# breaks and tabs, so `"Outros créditos "` becomes `"Outros créditos"`
# while `"Ativo financeiro setorial \n"` keeps its trailing space. Only
# spaces are trimmed (an SQL-style RTRIM). The CSV is ISO-8859-1, so the
# dashes and quotes outside Latin-1 come out as their ASCII cousins, and
# `DS_CONTA` is a varchar(100): longer descriptions are cut.
rad_csv_text <- function(x, width = 100L) {
  x <- gsub("^ +| +$", "", x)
  x <- gsub("[\r\n\t]", "", x)
  ascii <- c(
    "–" = "-",
    "—" = "-",
    "‘" = "'",
    "’" = "'",
    "“" = "\"",
    "”" = "\""
  )
  for (from in names(ascii)) {
    x <- gsub(from, ascii[[from]], x, fixed = TRUE)
  }
  x <- gsub("…", "...", x, fixed = TRUE)
  substr(x, 1L, width)
}

# The DMPL: one `DMPL` node per period, the equity components as
# elements of each `Conta` (or as `DadosContas/CamposDadosContas`).
rad_new_dmpl <- function(st, basis, dt_refer) {
  problems <- character()
  rows <- list()
  for (p in xml2::xml_find_all(st, "./DMPL")) {
    dt_ini <- rad_date_br(xml_text1(p, "./Periodo/DtInicio"))
    dt_fim <- rad_date_br(xml_text1(p, "./Periodo/DtFim"))
    nodes <- xml2::xml_find_all(p, "./Contas/Conta")
    if (length(nodes) == 0L) {
      next
    }
    period <- rad_new_dmpl_period(nodes, basis, dt_ini, dt_fim)
    if (!is.null(period$problem)) {
      problems <- c(problems, period$problem)
      next
    }
    rows <- c(
      rows,
      list(rad_rows("dmpl", basis, period$contas, period$cols, dt_refer))
    )
  }
  list(rows = rows, problems = problems)
}

# The accounts and the column spec of one DMPL period, in either variant.
rad_new_dmpl_period <- function(nodes, basis, dt_ini, dt_fim) {
  dados <- xml2::xml_find_all(nodes[[1L]], "./DadosContas/CamposDadosContas")
  contas <- rad_new_contas(nodes)
  if (length(dados) > 0L) {
    # positional variant: the n-th field is the n-th label
    n_col <- length(dados)
    if (n_col > rad_dmpl_max_cols) {
      return(list(
        problem = sprintf("dmpl/%s: %d DMPL columns", basis, n_col)
      ))
    }
    for (j in seq_len(n_col)) {
      contas[[paste0("c", j)]] <- xml2::xml_text(xml2::xml_find_first(
        nodes,
        sprintf("./DadosContas/CamposDadosContas[%d]/Valor", j)
      ))
    }
    contas[is.na(contas)] <- ""
    cols <- rad_cols(
      tag = paste0("c", seq_len(n_col)),
      dt_ini = dt_ini,
      dt_fim = dt_fim,
      col = seq_len(n_col),
      rank = 1L
    )
    return(list(contas = contas, cols = cols))
  }
  present <- setdiff(
    names(contas),
    c(
      "ContaFixa",
      "CodigoConta",
      "DescricaoConta",
      "seq",
      "cd_conta",
      "ds_conta",
      "st_conta_fixa"
    )
  )
  unknown <- setdiff(present, rad_dmpl_tags)
  if (length(unknown)) {
    return(list(
      problem = sprintf(
        "dmpl/%s: unknown DMPL columns %s",
        basis,
        paste(unknown, collapse = ",")
      )
    ))
  }
  # document order, the three-way equity split in the converter's order
  tags <- c(
    present[!present %in% rad_dmpl_tail],
    intersect(rad_dmpl_tail, present)
  )
  if (length(tags) > rad_dmpl_max_cols) {
    return(list(
      problem = sprintf("dmpl/%s: %d DMPL columns", basis, length(tags))
    ))
  }
  cols <- rad_cols(
    tag = tags,
    dt_ini = dt_ini,
    dt_fim = dt_fim,
    col = seq_along(tags),
    rank = 1L
  )
  list(contas = contas, cols = cols)
}

# --- old layout -------------------------------------------------------

rad_old_files <- c(
  "Documento.xml",
  "PeriodoDemonstracaoFinanceira.xml",
  "InfoFinaDFin.xml",
  "InformacaoFinanceiraDemonstracaoFinanceira.xml"
)

rad_read_old <- function(inner_zip) {
  tmp <- tempfile("rad-old-")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  entries <- utils::unzip(inner_zip, list = TRUE)$Name
  if (!all(rad_old_files %in% entries)) {
    return(rad_result(
      problems = paste0(
        "old layout without ",
        paste(setdiff(rad_old_files, entries), collapse = ", ")
      ),
      kind = "document"
    ))
  }
  utils::unzip(inner_zip, files = rad_old_files, exdir = tmp)
  meta <- rad_old_meta(file.path(tmp, "Documento.xml"), inner_zip)
  if (is.na(meta$dataset)) {
    return(rad_result(
      meta,
      problems = paste0("unknown CodigoTipoDocumento: ", meta$tipo_doc),
      kind = "document"
    ))
  }
  periods <- rad_old_periods(
    file.path(tmp, "PeriodoDemonstracaoFinanceira.xml")
  )
  colsets <- rad_old_colsets(
    file.path(tmp, "InformacaoFinanceiraDemonstracaoFinanceira.xml")
  )
  acc <- rad_old_accounts(file.path(tmp, "InfoFinaDFin.xml"))
  problems <- character()
  rows <- list()
  for (k in unique(paste(acc$code, acc$info_type))) {
    parts <- strsplit(k, " ")[[1L]]
    sub <- acc[acc$code == parts[1L] & acc$info_type == parts[2L], ]
    r <- rad_old_statement(parts, sub, colsets[[k]], periods, meta$dt_refer)
    rows <- c(rows, r$rows)
    problems <- c(problems, r$problems)
  }
  rad_result(meta, rad_bind(rows), problems)
}

rad_old_meta <- function(path, inner_zip) {
  doc <- rad_read_xml(path)
  tipo_doc <- xml_text1(doc, "./CodigoTipoDocumento")
  list(
    layout = "old",
    dataset = switch(tipo_doc, "3" = "itr", "4" = "dfp", NA_character_),
    tipo_doc = tipo_doc,
    cnpj_cia = xml_text1(doc, "./CompanhiaAberta/NumeroCnpjCompanhiaAberta"),
    cd_cvm = xml_text1(doc, "./CompanhiaAberta/CodigoCvm"),
    denom_cia = xml_text1(
      doc,
      "./CompanhiaAberta/NomeRazaoSocialCompanhiaAberta"
    ),
    dt_refer = rad_date_iso(xml_text1(doc, "./DataReferenciaDocumento")),
    versao = xml_text1(doc, "./NumeroVersaoDocumento"),
    moeda = xml_text1(doc, "./CodigoMoeda"),
    escala = xml_text1(doc, "./CodigoEscalaMoeda"),
    tipo_apresentacao = xml_text1(doc, "./CodigoTipoApresentacao"),
    motivo_reapresentacao = trimws(
      xml_text1(doc, "./MotivosReapresentacaoDocumento")
    ),
    xml_hash = digest::digest(inner_zip, algo = "sha256", file = TRUE)
  )
}

# Period id -> dates.
rad_old_periods <- function(path) {
  per <- xml2::xml_find_all(rad_read_xml(path), "/*/*")
  data.frame(
    id = xml2::xml_text(xml2::xml_find_first(
      per,
      "./NumeroIdentificacaoPeriodo"
    )),
    dt_ini = rad_date_iso(xml2::xml_text(xml2::xml_find_first(
      per,
      "./DataInicioPeriodo"
    ))),
    dt_fim = rad_date_iso(xml2::xml_text(xml2::xml_find_first(
      per,
      "./DataFimPeriodo"
    ))),
    stringsAsFactors = FALSE
  )
}

# Which value columns each (statement, basis) has: the first record of
# each pair in the column table, as data.frame(col, period).
rad_old_colsets <- function(path) {
  recs <- xml2::xml_find_all(rad_read_xml(path), "/*/*")
  plan <- "./PlanoConta/VersaoPlanoConta/"
  rkey <- paste(
    xml2::xml_text(xml2::xml_find_first(
      recs,
      paste0(plan, "CodigoTipoDemonstracaoFinanceira")
    )),
    xml2::xml_text(xml2::xml_find_first(
      recs,
      paste0(plan, "CodigoTipoInformacaoFinanceira")
    ))
  )
  colsets <- list()
  for (k in unique(rkey)) {
    r <- recs[[which(rkey == k)[1L]]]
    cs <- xml2::xml_find_all(
      r,
      "./ColunasInformacaoFinanceiraDemonstracaoFinanceira/*"
    )
    colsets[[k]] <- data.frame(
      col = as.integer(xml2::xml_text(xml2::xml_find_first(
        cs,
        "./NumeroIdentificacaoColuna"
      ))),
      period = xml2::xml_text(xml2::xml_find_first(
        cs,
        "./PeriodoDemonstracaoFinanceira/NumeroIdentificacaoPeriodo"
      )),
      stringsAsFactors = FALSE
    )
  }
  colsets
}

# One row per account record with its twelve raw values.
rad_old_accounts <- function(path) {
  nodes <- xml2::xml_find_all(rad_read_xml(path), "/*/InfoFinaDFin")
  gx <- function(xpath) xml2::xml_text(xml2::xml_find_first(nodes, xpath))
  plan <- "./PlanoConta/VersaoPlanoConta/"
  acc <- data.frame(
    seq = seq_along(nodes),
    code = gx(paste0(plan, "CodigoTipoDemonstracaoFinanceira")),
    info_type = gx(paste0(plan, "CodigoTipoInformacaoFinanceira")),
    period = gx("./PeriodoDemonstracaoFinanceira/NumeroIdentificacaoPeriodo"),
    cd_conta = gx("./PlanoConta/NumeroConta"),
    fixa = gx("./PlanoConta/IndicadorContaFixa"),
    ds_conta = gx("./DescricaoConta1"),
    stringsAsFactors = FALSE
  )
  acc$ds_conta[is.na(acc$ds_conta)] <- ""
  acc <- rad_account_columns(acc, acc$cd_conta, acc$ds_conta, acc$fixa)
  for (j in 1:12) {
    acc[[paste0("v", j)]] <- gx(sprintf("./ValorConta%d", j))
  }
  acc
}

# The rows of one (statement code, basis code) of the old layout.
rad_old_statement <- function(parts, sub, colset, periods, dt_refer) {
  table <- rad_tables$table[match(parts[1L], rad_tables$code_old)]
  basis <- switch(parts[2L], "1" = "ind", "2" = "con", NA_character_)
  none <- function(problem) list(rows = list(), problems = problem)
  if (is.na(table) || is.na(basis)) {
    return(none(paste0(
      "unknown statement/basis code: ",
      paste(parts, collapse = " ")
    )))
  }
  if (is.null(colset) || nrow(colset) == 0L) {
    # A statement with no column list whose records are ALL template
    # rows (period 0) was not filed: the old layout keeps the template
    # of the consolidated DMPL in a company that does not consolidate
    # (Ferrovia Centro-Atlântica DFP 2018 and 2020, Sabesp 2019, Banese
    # 2019, Newtel 2018, Bradesco 2019 v1 — set aside on 2026-10-24 as
    # "no column list for dmpl/con"; measured against the DFP CSVs: no
    # consolidated DMPL row for any of them, 28-33 template records in
    # every document). Nothing to read, nothing wrong. A record with a
    # real period and no column list is still a problem: the reader
    # would not know which column is which.
    if (all(sub$period == "0")) {
      return(list(rows = list(), problems = character()))
    }
    return(none(paste0("no column list for ", table, "/", basis)))
  }
  if (table == "dmpl") {
    # the period is on the record, the columns are the components; a
    # consolidated DMPL of a bank has nine (controlling, non-controlling
    # and consolidated equity in columns 7-9, already in the CSV's order:
    # Banrisul DFP 2021 and BRB DFP 2020, measured 2026-10-23 against the
    # DFP CSV), the ninth without label, as in the new layout
    n_col <- max(colset$col)
    if (n_col > rad_dmpl_max_cols) {
      return(none(sprintf("dmpl/%s: %d DMPL columns", basis, n_col)))
    }
    rows <- lapply(unique(sub$period), function(pid) {
      pr <- periods[periods$id == pid, , drop = FALSE]
      if (nrow(pr) != 1L) {
        return(NULL) # period 0: template rows without a period
      }
      cols <- rad_cols(
        tag = paste0("v", seq_len(n_col)),
        dt_ini = pr$dt_ini,
        dt_fim = pr$dt_fim,
        col = seq_len(n_col),
        rank = 1L
      )
      rad_rows(
        table,
        basis,
        sub[sub$period == pid, , drop = FALSE],
        cols,
        dt_refer
      )
    })
    return(list(rows = rows, problems = character()))
  }
  # ValorConta<N> is the column of period N; later ids are the
  # accumulated columns (the duplicate rule keeps them)
  pid <- colset$period
  pr <- periods[match(pid, periods$id), , drop = FALSE]
  if (anyNA(pr$id)) {
    return(none(sprintf("%s/%s: period id without dates", table, basis)))
  }
  cols <- rad_cols(
    tag = paste0("v", pid),
    dt_ini = if (table %in% c("bpa", "bpp")) as.Date(NA) else pr$dt_ini,
    dt_fim = pr$dt_fim,
    rank = as.integer(pid)
  )
  list(
    rows = list(rad_rows(table, basis, sub, cols, dt_refer)),
    problems = character()
  )
}

# --- calibration ------------------------------------------------------

# Compares the rows read from the RAD with the rows of the mirror for the
# same filing, account by account. `rad` and `mirror` are tibbles of one
# (table, report_type) with the package columns; `mirror` may carry the
# `year`/`basis` client columns. Returns list(ok, n_rad, n_mirror,
# dup_rad, only_rad, only_mirror, value_diff) where the last three are
# data frames of the keys that differ.
rad_compare <- function(rad, mirror, tol = 1e-6) {
  keys <- intersect(
    c("cd_conta", "ordem_exerc", "dt_ini_exerc", "dt_fim_exerc", "coluna_df"),
    names(rad)
  )
  kr <- do.call(paste, c(rad[keys], sep = "|"))
  km <- do.call(paste, c(mirror[keys], sep = "|"))
  only_rad <- rad[!kr %in% km, keys, drop = FALSE]
  only_mirror <- mirror[!km %in% kr, keys, drop = FALSE]
  both <- intersect(kr, km)
  r <- rad[match(both, kr), , drop = FALSE]
  m <- mirror[match(both, km), , drop = FALSE]
  diff <- abs(r$vl_conta - m$vl_conta) > tol * pmax(1, abs(m$vl_conta))
  diff[is.na(diff)] <- TRUE
  diff <- diff | r$ds_conta != m$ds_conta | r$st_conta_fixa != m$st_conta_fixa
  value_diff <- data.frame(
    key = both[diff],
    rad = r$vl_conta[diff],
    mirror = m$vl_conta[diff],
    ds_rad = r$ds_conta[diff],
    ds_mirror = m$ds_conta[diff],
    stringsAsFactors = FALSE
  )
  list(
    ok = nrow(only_rad) == 0L &&
      nrow(only_mirror) == 0L &&
      nrow(value_diff) == 0L &&
      anyDuplicated(kr) == 0L,
    n_rad = nrow(rad),
    n_mirror = nrow(mirror),
    dup_rad = anyDuplicated(kr),
    only_rad = only_rad,
    only_mirror = only_mirror,
    value_diff = value_diff
  )
}

# --- reader fingerprint -----------------------------------------------

# The code of every `rad_*` object above, digested. The state records it
# with each unread document and the queue only counts the attempts made
# with the reader as it is now, so a document set aside by an earlier
# reader is tried again once the reader changes (on 2026-10-20 eight
# documents were refused by two defects of the reader, none of the
# documents).
rad_reader_id <- local({
  env <- environment()
  env <- parent.env(env)
  objs <- mget(sort(ls(env, pattern = "^rad_")), envir = env)
  substr(digest::digest(lapply(objs, deparse)), 1L, 12L)
})
