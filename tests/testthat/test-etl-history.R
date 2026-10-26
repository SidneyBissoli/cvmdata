# Tests for inst/etl/util-history.R, the history of superseded filings
# that 03-publish.R keeps next to every versioned partition (Part 3 of
# the versions work, 2026-10).
#
# Pinned here: a restated filing sends its OLD rows to history with the
# replacing `versao`; a filing that vanished goes with NA; a filing that
# is new, or identical in another row order, sends nothing; a column the
# CVM adds upstream is not a change of every filing; history accumulates.

load_etl_history <- function() {
  skip_if_not_installed("arrow")
  skip_if_not_installed("digest")
  env <- parent.frame()
  for (script in c("00-config.R", "util-history.R")) {
    installed <- system.file("etl", script, package = "cvmdata")
    path <- if (nzchar(installed)) {
      installed
    } else {
      normalizePath(
        test_path("..", "..", "inst", "etl", script),
        winslash = "/"
      )
    }
    sys.source(path, envir = env)
  }
}

dre_rows <- function(cnpj = "43.335.774/0001-86", versao = "1", vl = 100) {
  data.frame(
    cnpj_cia = cnpj,
    dt_refer = as.Date("2024-12-31"),
    versao = versao,
    cd_conta = c("3.01", "3.02"),
    vl_conta = c(vl, vl * 2),
    stringsAsFactors = FALSE
  )
}

stamp <- "2026-10-27T07:00:00Z"

test_that("a restated filing sends its old rows to history", {
  load_etl_history()
  old <- rbind(dre_rows(versao = "1", vl = 100), dre_rows("B", "1", 5))
  new <- rbind(dre_rows(versao = "2", vl = 150), dre_rows("B", "1", 5))

  out <- mirror_superseded_rows(old, new, c("cnpj_cia", "dt_refer"), stamp)
  expect_identical(out$n_replaced, 1L)
  expect_identical(out$n_removed, 0L)
  expect_identical(nrow(out$rows), 2L)
  expect_identical(unique(out$rows$cnpj_cia), "43.335.774/0001-86")
  expect_identical(out$rows$vl_conta, c(100, 200))
  expect_identical(out$rows$superseded_at, rep(stamp, 2L))
  expect_identical(out$rows$superseded_by_versao, c("2", "2"))
})

test_that("a filing that vanished goes to history with NA versao", {
  load_etl_history()
  old <- rbind(dre_rows(), dre_rows("B", "1", 5))
  new <- dre_rows()

  out <- mirror_superseded_rows(old, new, c("cnpj_cia", "dt_refer"), stamp)
  expect_identical(out$n_removed, 1L)
  expect_identical(out$rows$cnpj_cia, c("B", "B"))
  expect_identical(out$rows$superseded_by_versao, c(NA_character_, NA))
})

test_that("identical content in another row order is not a change", {
  load_etl_history()
  old <- dre_rows()
  new <- old[2:1, ]
  out <- mirror_superseded_rows(old, new, c("cnpj_cia", "dt_refer"), stamp)
  expect_identical(nrow(out$rows), 0L)
  expect_identical(out$n_replaced, 0L)
  expect_named(
    out$rows,
    c(names(old), "superseded_at", "superseded_by_versao", "history_source")
  )
})

test_that("a new filing and a new upstream column send nothing", {
  load_etl_history()
  old <- dre_rows()
  new <- rbind(dre_rows(), dre_rows("B", "1", 5))
  new$moeda <- "REAL"

  out <- mirror_superseded_rows(old, new, c("cnpj_cia", "dt_refer"), stamp)
  expect_identical(nrow(out$rows), 0L)
  expect_identical(out$columns_added, "moeda")
  expect_identical(out$columns_dropped, character())
})

test_that("a changed versao with identical content is not a change", {
  load_etl_history()
  # Travessia VI: VERSAO 1 delivered after VERSAO 2 with the same numbers.
  old <- dre_rows(versao = "2")
  new <- dre_rows(versao = "1")
  out <- mirror_superseded_rows(old, new, c("cnpj_cia", "dt_refer"), stamp)
  expect_identical(nrow(out$rows), 0L)
})

test_that("extra keys split one (cnpj, date) into several filings", {
  load_etl_history()
  old <- dre_rows()
  old$id_item <- c("1", "2")
  new <- old
  new$vl_conta[2] <- 999
  keys <- c("cnpj_cia", "dt_refer", "id_item")

  out <- mirror_superseded_rows(old, new, keys, stamp)
  expect_identical(out$rows$id_item, "2")
  expect_identical(out$rows$vl_conta, 200)
})

test_that("history accumulates across runs", {
  load_etl_history()
  first <- mirror_superseded_rows(
    dre_rows(vl = 100),
    dre_rows(versao = "2", vl = 150),
    c("cnpj_cia", "dt_refer"),
    "2026-10-27T07:00:00Z"
  )$rows
  second <- mirror_superseded_rows(
    dre_rows(versao = "2", vl = 150),
    dre_rows(versao = "3", vl = 170),
    c("cnpj_cia", "dt_refer"),
    "2026-11-03T07:00:00Z"
  )$rows

  expect_identical(mirror_append_history(NULL, first), first)
  all <- mirror_append_history(first, second)
  expect_identical(nrow(all), 4L)
  expect_identical(all$versao, c("1", "1", "2", "2"))
  expect_identical(all$superseded_by_versao, c("2", "2", "3", "3"))
})

test_that("filing keys follow the two naming conventions", {
  load_etl_history()
  expect_identical(
    mirror_filing_keys(dre_rows()),
    c("cnpj_cia", "dt_refer")
  )
  fre <- data.frame(cnpj_companhia = "x", data_referencia = "y", id_doc = 1)
  expect_identical(
    mirror_filing_keys(fre),
    c("cnpj_companhia", "data_referencia")
  )
  expect_null(mirror_filing_keys(data.frame(cnpj_cia = "x")))
  expect_null(mirror_filing_keys(dre_rows(), extras = "id_item"))
})

test_that("the schema says which tables are versioned", {
  load_etl_history()
  skip_if_not(
    dir.exists(mirror_schema_dir("dfp")),
    "schemas not reachable from the test"
  )
  expect_identical(
    mirror_table_versioning("dfp", "dre"),
    list(versioned = TRUE, keys = NULL)
  )
  expect_identical(
    mirror_table_versioning("dfp", "submissao"),
    list(versioned = FALSE, keys = NULL)
  )
  expect_identical(
    mirror_table_versioning("cgvn", "praticas"),
    list(versioned = TRUE, keys = "id_item")
  )
  expect_false(mirror_table_versioning("dfp", "no_such_table")$versioned)
})

test_that("history assets are named so that the current readers skip them", {
  load_etl_history()
  rel <- "bpa/report_type=ind/year=2024/part-0.parquet"
  hist <- mirror_history_rel(rel)
  expect_identical(hist, "bpa/report_type=ind/year=2024/history.parquet")
  name <- gsub("/", "__", hist, fixed = TRUE)
  expect_true(mirror_is_history_asset(name))
  expect_false(mirror_is_history_asset(gsub("/", "__", rel, fixed = TRUE)))
  expect_identical(mirror_partition_table(rel), "bpa")
  # The client parser tags the name as history, and
  # filter_mirror_assets() keeps only the current assets unless asked,
  # so cvm_fetch() never reads history rows as current.
  public <- gsub("=", ".", name, fixed = TRUE)
  expect_identical(cvmdata:::parse_mirror_asset_name(public)$kind, "history")
  assets <- tibble::tibble(
    name = c(gsub("=", ".", gsub("/", "__", rel, fixed = TRUE)), public),
    url = paste0("https://example.test/", name),
    size_bytes = c(1L, 2L)
  )
  kept <- cvmdata:::filter_mirror_assets(assets, "bpa", 2024L, "ind")
  expect_identical(kept$kind, "current")
})

test_that("after a reader change only a new delivery is a replacement", {
  load_etl_history()
  keys <- c("cnpj_cia", "dt_refer")
  # A: same delivery (versao 1), rows the old reader lost -> the reader's
  # B: a re-filing (versao 1 -> 2) with new numbers -> the CVM's
  # C: vanished -> still history
  old <- rbind(
    dre_rows("A", "1", 10)[1, ],
    dre_rows("B", "1", 5),
    dre_rows("C", "1", 7)
  )
  new <- rbind(dre_rows("A", "1", 10), dre_rows("B", "2", 6))
  all <- mirror_superseded_rows(old, new, keys, stamp)
  expect_identical(all$n_replaced, 2L)
  only <- mirror_superseded_rows(old, new, keys, stamp, identity_only = TRUE)
  expect_identical(only$n_replaced, 1L)
  expect_identical(only$n_removed, 1L)
  expect_setequal(unique(only$rows$cnpj_cia), c("B", "C"))
  # a table without delivery columns cannot tell: nothing is replaced
  bare <- function(df) df[, setdiff(names(df), "versao")]
  none <- mirror_superseded_rows(
    bare(old),
    bare(new),
    keys,
    stamp,
    identity_only = TRUE
  )
  expect_identical(none$n_replaced, 0L)
  expect_identical(none$n_removed, 1L)
})

test_that("the reader fingerprint follows the reader's code", {
  load_etl_history()
  id <- mirror_reader_id()
  expect_match(id, "^[0-9a-f]{12}$")
  expect_identical(mirror_reader_id(), id)
  ns <- new.env()
  for (o in intersect(
    mirror_reader_objects,
    ls(asNamespace("cvmdata"), all.names = TRUE)
  )) {
    assign(o, get(o, envir = asNamespace("cvmdata")), envir = ns)
  }
  expect_identical(mirror_reader_id(ns), id)
  assign(".text_types", c("varchar"), envir = ns)
  expect_false(identical(mirror_reader_id(ns), id))
  # every object of the list exists in the package
  expect_true(all(vapply(
    mirror_reader_objects,
    exists,
    logical(1L),
    envir = asNamespace("cvmdata"),
    inherits = FALSE
  )))
})
