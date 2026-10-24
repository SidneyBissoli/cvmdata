# Build the small RAD document fixtures used by tests/testthat/test-etl-rad.R.
#
# A RAD document is a ZIP of 2-7 MB (the PDF of the statements inside);
# the fixtures keep only the XML the reader (inst/etl/util-rad.R) uses,
# trimmed to the first accounts of every statement plus the per-share
# accounts (`3.99*`), so each fixture stays under ~30 KB and still
# exercises every rule: both layouts, DFP and ITR, individual and
# consolidated, the Q1 duplicate periods, the three number spellings and
# the positional DMPL labels.
#
#   tests/testthat/fixtures/rad_dfp_2024_151243.zip
#     - new layout, DFP 2024, Travessia Securitizadora VI, the v1
#       delivered AFTER the v2 (the index says versao 2 for id 146055 and
#       1 for 151243; the CSV kept 146055). Values `14.410` with the dot
#       as thousands separator; DMPL values `1,0000000000`.
#   tests/testthat/fixtures/rad_itr_2024_143043.zip
#     - new layout, ITR 3Q2024, Gama Participacoes: four DRE periods
#       (quarter and year-to-date, both years), per-share `0,00635`,
#       consolidated statements present but empty, consolidated DMPL
#       with the eight flat elements.
#   tests/testthat/fixtures/rad_dfp_2011_15513.zip
#     - old layout (`.dfp` inside), DFP 2011, Sauipe SA v1: dot-decimal
#       numbers `29547.0000000000`, cash flow by the direct method,
#       six-column DMPL.
#   tests/testthat/fixtures/rad_itr_2012_17509.zip
#     - old layout (`.itr` inside), ITR 1Q2012, Uptick Participacoes v1:
#       the quarter and the year-to-date columns share the same dates and
#       collapse into one row (the CSV keeps the accumulated column).
#   tests/testthat/fixtures/rad_dfp_2011_14281.zip
#     - old layout, DFP 2011, Banrisul v1: individual AND consolidated,
#       DMPL with seven (ind) and eight (con) columns; the CSV labels the
#       columns by position (its "Participacao dos Nao Controladores" of
#       the individual DMPL is the equity total).
#   tests/testthat/fixtures/rad_dfp_2025_154846.zip
#     - new layout, DFP 2025, Banestes v1 (set aside on 2026-10-20): the
#       DMPL of a financial institution, with `AjustesAvaliacaoPatrimonial`
#       and the three-way equity split of the consolidated statement
#       (controlling, non-controlling, consolidated) — seven columns in
#       the individual DMPL, nine in the consolidated, labelled by
#       position, the ninth without label; the XML writes the consolidated
#       total before the non-controlling interest, the CSV the reverse.
#   tests/testthat/fixtures/rad_dfp_2025_154641.zip
#     - new layout, DFP 2025, BTG Pactual v1 (set aside on 2026-10-21):
#       the other bank template, with `ReservasReavaliacao` third and
#       `AjustesAvaliacaoPatrimonial` AFTER `LucroPrejuizoAcumulado` (the
#       reverse of Banestes), seven columns in the individual DMPL; the
#       consolidated DMPL is the positional variant (`DadosContas`, eight
#       fields). Proves that the CSV follows the document's order.
#   tests/testthat/fixtures/rad_dfp_2021_111777.zip
#     - old layout, DFP 2021, Banrisul v1 (set aside on 2026-10-23): the
#       consolidated DMPL of a bank in the OLD layout has nine columns
#       (controlling, non-controlling and consolidated equity in 7-9,
#       already in the CSV's order), the ninth without label; the
#       individual has seven. BRB DFP 2020 (ids 104653, 102706) is the
#       same class and was measured, not kept.
#   tests/testthat/fixtures/rad_dfp_2020_100464.zip
#     - old layout, DFP 2020, Ferrovia Centro-Atlântica v2 (set aside on
#       2026-10-24 as "no column list for dmpl/con"): a company that does
#       not consolidate, whose document keeps the TEMPLATE of the
#       consolidated DMPL (28 records, all period 0) with no column list
#       for it; the DFP CSV has no consolidated DMPL row for it. Same
#       class: Sabesp 2019, Banese 2019, Newtel 2018, Bradesco 2019 v1.
#   tests/testthat/fixtures/rad_dfp_2020_93001.zip
#     - old layout, DFP 2020-02-29, Camil Alimentos v1 (set aside on
#       2026-10-24): a fiscal year closing on 29 February; the previous
#       exercise closes on 2019-02-28, and "one year before" the reference
#       date is not a calendar date.
#   tests/testthat/fixtures/rad_ipe_2023_132214.zip
#     - NOT a DFP/ITR: the ITR 2023 index lists id 132214 as one of two
#       deliveries of Dibens Leasing for 2023-09-30 (the other, 132223,
#       is the ITR), but the RAD serves an IPE under that number (root
#       `Documento`, an `.ipe` inside). The reader crashed on it on
#       2026-10-23 instead of setting it aside as a document of another
#       type. Kept whole (the XML is 8 KB; the `.ipe` is dropped).
#   tests/testthat/fixtures/rad_dfp_2021_113859.zip
#     - new layout, DFP 2021, Inter & Co v1 (set aside on 2026-10-23): a
#       company abroad whose document carries the CNPJ as zeros and the
#       former name (Inter Platform, Inc.); the CVM code (057886) is the
#       one the index lists for this delivery. Consolidated statements
#       only.
#
# Usage, from the package root, with the original ZIPs (as downloaded
# from the RAD, named `<id_doc>.zip`) in one directory; a fixture whose
# original is absent is kept as it is:
#   Rscript data-raw/build-rad-test-fixtures.R <dir-with-zips>

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) {
  stop("usage: Rscript data-raw/build-rad-test-fixtures.R <dir-with-zips>")
}
src <- args[[1L]]
out_dir <- "tests/testthat/fixtures"
keep_first <- 6L

docs <- list(
  list(id = "151243", name = "rad_dfp_2024_151243", layout = "new"),
  list(id = "143043", name = "rad_itr_2024_143043", layout = "new"),
  list(id = "15513", name = "rad_dfp_2011_15513", layout = "old"),
  list(id = "17509", name = "rad_itr_2012_17509", layout = "old"),
  list(id = "14281", name = "rad_dfp_2011_14281", layout = "old"),
  list(id = "154846", name = "rad_dfp_2025_154846", layout = "new"),
  list(id = "154641", name = "rad_dfp_2025_154641", layout = "new"),
  list(id = "111777", name = "rad_dfp_2021_111777", layout = "old"),
  list(id = "132214", name = "rad_ipe_2023_132214", layout = "new"),
  list(id = "113859", name = "rad_dfp_2021_113859", layout = "new"),
  list(id = "100464", name = "rad_dfp_2020_100464", layout = "old"),
  list(id = "93001", name = "rad_dfp_2020_93001", layout = "old")
)

keep_conta <- function(codes) {
  seq_along(codes) <= keep_first | grepl("^3\\.99", codes)
}

trim_new <- function(xml_path, out_path) {
  # HUGE: the embedded PDF can exceed libxml2's 10 MB text node limit
  doc <- xml2::read_xml(xml_path, options = c("NOBLANKS", "HUGE"))
  for (x in c(
    "//AnexosDocumento",
    "//PareceresDeclaracoes",
    "//Justificativas"
  )) {
    for (n in xml2::xml_find_all(doc, x)) {
      xml2::xml_remove(n)
    }
  }
  for (basis in xml2::xml_find_all(doc, "//DfIndividuais | //DfConsolidadas")) {
    for (st in xml2::xml_children(basis)) {
      if (xml2::xml_name(st) == "DemonstracaoMutacoesPatrimonioLiquido") {
        for (p in xml2::xml_find_all(st, "./DMPL")) {
          contas <- xml2::xml_find_all(p, "./Contas/Conta")
          drop <- contas[
            !keep_conta(xml2::xml_text(xml2::xml_find_first(
              contas,
              "./CodigoConta"
            )))
          ]
          for (n in drop) {
            xml2::xml_remove(n)
          }
        }
      } else {
        contas <- xml2::xml_find_all(st, "./Conta")
        drop <- contas[
          !keep_conta(xml2::xml_text(xml2::xml_find_first(
            contas,
            "./CodigoConta"
          )))
        ]
        for (n in drop) {
          xml2::xml_remove(n)
        }
      }
    }
  }
  xml2::write_xml(doc, out_path)
}

strip_blobs <- function(doc) {
  for (n in xml2::xml_find_all(
    doc,
    "//FormularioDemonstracaoFinanceira/Documento"
  )) {
    xml2::xml_remove(n)
  }
  doc
}

trim_old <- function(inner_zip, out_inner) {
  tmp <- tempfile("rad-fx-")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  need <- c(
    "Documento.xml",
    "PeriodoDemonstracaoFinanceira.xml",
    "InfoFinaDFin.xml",
    "InformacaoFinanceiraDemonstracaoFinanceira.xml"
  )
  utils::unzip(inner_zip, files = need, exdir = tmp)
  # Documento.xml: drop the bulky control lists
  d <- xml2::read_xml(file.path(tmp, "Documento.xml"))
  for (x in c("./ControlesDominio", "./DetalhesDominio", "./HistoricosAcao")) {
    for (n in xml2::xml_find_all(d, x)) {
      xml2::xml_remove(n)
    }
  }
  xml2::write_xml(d, file.path(tmp, "Documento.xml"))
  # InfoFinaDFin.xml: first accounts per (statement, basis, period)
  f <- strip_blobs(xml2::read_xml(file.path(tmp, "InfoFinaDFin.xml")))
  recs <- xml2::xml_find_all(f, "/*/InfoFinaDFin")
  g <- function(p) xml2::xml_text(xml2::xml_find_first(recs, p))
  key <- paste(
    g("./PlanoConta/VersaoPlanoConta/CodigoTipoDemonstracaoFinanceira"),
    g("./PlanoConta/VersaoPlanoConta/CodigoTipoInformacaoFinanceira"),
    g("./PeriodoDemonstracaoFinanceira/NumeroIdentificacaoPeriodo")
  )
  codes <- g("./PlanoConta/NumeroConta")
  rank <- stats::ave(seq_along(key), key, FUN = seq_along)
  keep <- rank <= keep_first | grepl("^3\\.99", codes)
  for (n in recs[!keep]) {
    xml2::xml_remove(n)
  }
  xml2::write_xml(f, file.path(tmp, "InfoFinaDFin.xml"))
  # column table: first record per (statement, basis)
  i <- strip_blobs(xml2::read_xml(file.path(
    tmp,
    "InformacaoFinanceiraDemonstracaoFinanceira.xml"
  )))
  recs <- xml2::xml_find_all(i, "/*/*")
  g <- function(p) xml2::xml_text(xml2::xml_find_first(recs, p))
  key <- paste(
    g("./PlanoConta/VersaoPlanoConta/CodigoTipoDemonstracaoFinanceira"),
    g("./PlanoConta/VersaoPlanoConta/CodigoTipoInformacaoFinanceira")
  )
  for (n in recs[duplicated(key)]) {
    xml2::xml_remove(n)
  }
  for (n in xml2::xml_find_all(
    i,
    "//InformacaoFinanceiraDemonstracaoFinanceira/*/InformacaoFinanceiraDemonstracaoFinanceira"
  )) {
    xml2::xml_remove(n)
  }
  xml2::write_xml(
    i,
    file.path(tmp, "InformacaoFinanceiraDemonstracaoFinanceira.xml")
  )
  old <- setwd(tmp)
  on.exit(setwd(old), add = TRUE)
  unlink(out_inner)
  utils::zip(out_inner, need, flags = "-q9X")
}

for (d in docs) {
  zip <- file.path(src, paste0(d$id, ".zip"))
  if (!file.exists(zip)) {
    message(sprintf(
      "%s: %s not in %s, fixture kept as it is",
      d$name,
      basename(zip),
      src
    ))
    next
  }
  entries <- utils::unzip(zip, list = TRUE)$Name
  work <- tempfile("rad-build-")
  dir.create(work)
  out_zip <- normalizePath(
    file.path(out_dir, paste0(d$name, ".zip")),
    mustWork = FALSE
  )
  unlink(out_zip)
  if (d$layout == "new") {
    main <- entries[grepl("\\.xml$", entries) & !grepl("^Formulario", entries)]
    stopifnot(length(main) == 1L)
    utils::unzip(zip, files = main, exdir = work)
    trim_new(file.path(work, main), file.path(work, main))
    member <- main
  } else {
    inner <- entries[grepl("\\.(dfp|itr)$", entries)]
    stopifnot(length(inner) == 1L)
    utils::unzip(zip, files = inner, exdir = work)
    trim_old(file.path(work, inner), normalizePath(file.path(work, inner)))
    member <- inner
  }
  old <- setwd(work)
  utils::zip(out_zip, member, flags = "-q9X")
  setwd(old)
  unlink(work, recursive = TRUE)
  meta <- list(
    source_url = sprintf(
      "https://www.rad.cvm.gov.br/ENETCONSULTA/frmDownloadDocumento.aspx?CodigoInstituicao=1&NumeroSequencialDocumento=%s",
      d$id
    ),
    fetched_at = format(Sys.Date()),
    id_doc = d$id,
    layout = d$layout,
    notes = paste(
      "RAD document trimmed by data-raw/build-rad-test-fixtures.R:",
      "PDF, annexes and opinions removed; each statement keeps its first",
      keep_first,
      "accounts and the per-share accounts (3.99*)."
    )
  )
  jsonlite::write_json(
    meta,
    paste0(out_zip, ".meta.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  message(sprintf("%s: %d bytes", basename(out_zip), file.size(out_zip)))
}
