# Tests for inst/etl/util-privacy.R, what the mirror does not redistribute
# of the personal data the CVM publishes (decision of 2026-11-08).
#
# Pinned here: a CPF becomes `***.456.789-**` wherever it is; a CNPJ stays;
# a foreign document in a CPF column does not survive; a phone or protocol
# number in free text stays; the birth date becomes the year; the rule is
# idempotent, which is what keeps it from looking like a re-filing.
# All CPFs below are synthetic.

etl_script_path <- function(script) {
  installed <- system.file("etl", script, package = "cvmdata")
  if (nzchar(installed)) {
    return(installed)
  }
  normalizePath(test_path("..", "..", "inst", "etl", script), winslash = "/")
}

load_etl_privacy <- function(env = parent.frame()) {
  sys.source(etl_script_path("util-privacy.R"), envir = env)
}

test_that("a document column masks CPFs, keeps CNPJs, hides the rest", {
  load_etl_privacy()
  x <- c(
    "111.444.777-35",
    "11144477735",
    "11.222.333/0001-81",
    "11222333000181",
    "00011144477735",
    "AA123456",
    "Nao se aplica",
    "***.444.777-**",
    NA
  )
  expect_identical(
    mirror_mask_document(x),
    c(
      "***.444.777-**",
      "***.444.777-**",
      "11.222.333/0001-81",
      "11222333000181",
      "***.444.777-**",
      "***",
      "Nao se aplica",
      "***.444.777-**",
      NA
    )
  )
})

test_that("a punctuated CPF is masked even when its check digits fail", {
  load_etl_privacy()
  expect_identical(mirror_mask_document("123.456.789-00"), "***.456.789-**")
  expect_identical(
    mirror_mask_text("CPF 123.456.789-00, diretor"),
    "CPF ***.456.789-**, diretor"
  )
})

test_that("free text loses the CPF and nothing else", {
  load_etl_privacy()
  expect_identical(
    mirror_mask_text(c(
      "Nascido em 1965, CPF 111.444.777-35 e 11144477735; sem condenacao.",
      "Tel 11987654321, processo 12345678901",
      "Valor de R$ 123.456.789,00 em 11.222.333/0001-81",
      "Numero 0001114447773500",
      NA
    )),
    c(
      "Nascido em 1965, CPF ***.444.777-** e ***.444.777-**; sem condenacao.",
      "Tel 11987654321, processo 12345678901",
      "Valor de R$ 123.456.789,00 em 11.222.333/0001-81",
      "Numero 0001114447773500",
      NA
    )
  )
})

test_that("the frame keeps its rows, order and attributes", {
  load_etl_privacy()
  df <- data.frame(
    cnpj_companhia = "11.222.333/0001-81",
    nome = "Fulana de Tal",
    cpf = "111.444.777-35",
    data_nascimento = as.Date("1965-03-01"),
    experiencia_profissional = "CPF 111.444.777-35",
    protocolo_entrega = "11144477735",
    qtd = 1L
  )
  attr(df, "fetched_at") <- "2026-11-08"
  out <- mirror_apply_privacy(df)
  expect_identical(
    names(out),
    c(
      "cnpj_companhia",
      "nome",
      "cpf",
      "ano_nascimento",
      "experiencia_profissional",
      "protocolo_entrega",
      "qtd"
    )
  )
  expect_identical(out$nome, "Fulana de Tal")
  expect_identical(out$cpf, "***.444.777-**")
  expect_identical(out$ano_nascimento, 1965L)
  expect_identical(out$experiencia_profissional, "CPF ***.444.777-**")
  expect_identical(out$protocolo_entrega, "11144477735")
  expect_identical(attr(out, "fetched_at"), "2026-11-08")
})

test_that("the rule is idempotent and the guard sees only what it would do", {
  load_etl_privacy()
  df <- data.frame(
    cpf_cnpj_acionista = c("111.444.777-35", "11.222.333/0001-81", NA),
    experiencia_profissional = c("CPF 111.444.777-35", "nada", NA),
    data_nascimento = as.Date(c("1965-03-01", NA, "1970-01-01"))
  )
  expect_identical(
    mirror_privacy_counts(df),
    c(
      cpf_cnpj_acionista = 1L,
      experiencia_profissional = 1L,
      data_nascimento = 2L
    )
  )
  once <- mirror_apply_privacy(df)
  expect_identical(mirror_apply_privacy(once), once)
  expect_length(mirror_privacy_counts(once), 0L)
})

test_that("the birth year reads a Date or an ISO string", {
  load_etl_privacy()
  expect_identical(mirror_birth_year(as.Date("1965-03-01")), 1965L)
  expect_identical(mirror_birth_year("1965-03-01"), 1965L)
  expect_identical(mirror_birth_year(as.Date(NA)), NA_integer_)
})

test_that("masking both sides leaves no spurious re-filing", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("digest")
  skip_if_not_installed("dplyr")
  skip_if_not_installed("yaml")
  load_etl_privacy()
  for (script in c("00-config.R", "util-history.R")) {
    sys.source(etl_script_path(script), envir = environment())
  }
  # the previous release, published before the rule existed
  old <- data.frame(
    cnpj_companhia = "11.222.333/0001-81",
    data_referencia = as.Date("2024-12-31"),
    versao = 1L,
    nome = "Fulana de Tal",
    cpf = "111.444.777-35",
    data_nascimento = as.Date("1965-03-01")
  )
  new <- mirror_apply_privacy(old)
  keys <- c("cnpj_companhia", "data_referencia")
  same <- mirror_superseded_rows(
    mirror_apply_privacy(old),
    new,
    keys,
    "2026-11-10"
  )
  expect_identical(nrow(same$rows), 0L)

  # a real re-filing goes to history, already masked
  refiled <- new
  refiled$nome <- "Beltrana de Tal"
  refiled$versao <- 2L
  moved <- mirror_superseded_rows(
    mirror_apply_privacy(old),
    refiled,
    keys,
    "2026-11-10"
  )
  expect_identical(nrow(moved$rows), 1L)
  expect_identical(moved$rows$cpf, "***.444.777-**")
  expect_false("data_nascimento" %in% names(moved$rows))
})

test_that("the repair rewrites a dirty parquet once and leaves a clean one", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("httr2")
  env <- new.env()
  withr::local_options(cvmdata.etl_testing = TRUE)
  for (script in c(
    "00-config.R",
    "util-release.R",
    "util-privacy.R",
    "repair-personal-data.R"
  )) {
    sys.source(etl_script_path(script), envir = env)
  }
  dir <- withr::local_tempdir()
  path <- file.path(dir, "part.parquet")
  arrow::write_parquet(
    data.frame(
      cpf = c("111.444.777-35", NA),
      data_nascimento = as.Date(c("1965-03-01", NA))
    ),
    path
  )
  expect_identical(env$scrub_parquet_file(path), 2L)
  out <- arrow::read_parquet(path)
  expect_identical(out$cpf, c("***.444.777-**", NA))
  expect_identical(out$ano_nascimento, c(1965L, NA))
  before <- file.mtime(path)
  expect_identical(env$scrub_parquet_file(path), 0L)
  expect_identical(file.mtime(path), before)
})

test_that("contact data is dropped, the company address stays", {
  load_etl_privacy()
  # fca/endereco: a company, so the address stays
  company <- data.frame(
    cnpj_companhia = "11.222.333/0001-81",
    logradouro = "Rua A, 1",
    cep = "01000-000",
    cidade = "Sao Paulo",
    ddi_telefone = "55",
    ddd_telefone = "11",
    telefone = 30000000,
    fax = NA_character_,
    email = "ri@empresa.com.br"
  )
  attr(company, "fetched_at") <- "2026-11-14"
  out <- mirror_apply_privacy(company)
  expect_named(out, c("cnpj_companhia", "logradouro", "cep", "cidade"))
  expect_identical(attr(out, "fetched_at"), "2026-11-14")
  expect_identical(
    mirror_privacy_counts(company),
    c(ddi_telefone = 1L, ddd_telefone = 1L, telefone = 1L, fax = 0L, email = 1L)
  )
  expect_identical(mirror_apply_privacy(out), out)
  expect_length(mirror_privacy_counts(out), 0L)

  # fca/dri: the table names a person, so the street address goes too
  person <- cbind(company, responsavel = "Fulana de Tal", uf = "SP")
  expect_named(
    mirror_apply_privacy(person),
    c("cnpj_companhia", "cidade", "responsavel", "uf")
  )

  # cad: the address of the person in charge goes, the company's stays
  cad <- data.frame(
    cnpj_cia = "11.222.333/0001-81",
    logradouro = "Rua A, 1",
    tel = "30000000",
    resp = "Fulana de Tal",
    logradouro_resp = "Rua B, 2",
    cep_resp = "02000-000",
    mun_resp = "Sao Paulo",
    ddd_tel_resp = "11",
    email_resp = "fulana@gmail.com"
  )
  expect_named(
    mirror_apply_privacy(cad),
    c("cnpj_cia", "logradouro", "resp", "mun_resp")
  )
})

test_that("the contact rule matches the dictionary and nothing else", {
  load_etl_privacy()
  dict <- utils::read.csv(
    system.file("extdata", "cvm_dictionary_snapshot.csv", package = "cvmdata"),
    stringsAsFactors = FALSE
  )
  dropped <- lapply(
    split(dict$campo, paste(dict$dataset, dict$table, sep = "/")),
    mirror_contact_columns
  )
  dropped <- dropped[lengths(dropped) > 0L]
  expect_identical(
    sort(names(dropped)),
    c(
      "cad/companhias",
      "cad/estrangeiras",
      "cad/incentivadas",
      "fca/departamento_acionistas",
      "fca/dri",
      "fca/endereco",
      "fca/escriturador",
      "fre/auditor_responsavel"
    )
  )
  # companies keep their address
  for (tbl in c("fca/endereco", "fca/escriturador")) {
    expect_false(any(c("logradouro", "cep") %in% dropped[[tbl]]))
  }
  expect_identical(
    sort(unique(unlist(dropped, use.names = FALSE))),
    c(
      "bairro",
      "bairro_resp",
      "cd_pais_fax",
      "cd_pais_tel",
      "cep",
      "cep_resp",
      "compl_resp",
      "complemento",
      "ddd_fax",
      "ddd_fax_resp",
      "ddd_tel",
      "ddd_tel_resp",
      "ddd_telefone",
      "ddi_fax",
      "ddi_telefone",
      "email",
      "email_resp",
      "fax",
      "fax_resp",
      "logradouro",
      "logradouro_resp",
      "tel",
      "tel_resp",
      "telefone"
    )
  )
})
