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
    observacao = "CPF 111.444.777-35",
    protocolo_entrega = "11144477735",
    qtd = 1L
  )
  attr(df, "fetched_at") <- "2026-11-08"
  out <- mirror_apply_privacy(df)
  expect_named(
    out,
    c(
      "cnpj_companhia",
      "nome",
      "cpf",
      "ano_nascimento",
      "observacao",
      "protocolo_entrega",
      "qtd"
    )
  )
  expect_identical(out$nome, "Fulana de Tal")
  expect_identical(out$cpf, "***.444.777-**")
  expect_identical(out$ano_nascimento, 1965L)
  expect_identical(out$observacao, "CPF ***.444.777-**")
  expect_identical(out$protocolo_entrega, "11144477735")
  expect_identical(attr(out, "fetched_at"), "2026-11-08")
})

test_that("the rule is idempotent and the guard sees only what it would do", {
  load_etl_privacy()
  df <- data.frame(
    cpf_cnpj_acionista = c("111.444.777-35", "11.222.333/0001-81", NA),
    observacao = c("CPF 111.444.777-35", "nada", NA),
    data_nascimento = as.Date(c("1965-03-01", NA, "1970-01-01"))
  )
  expect_identical(
    mirror_privacy_counts(df),
    c(
      cpf_cnpj_acionista = 1L,
      observacao = 1L,
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

  # a table that names a contact person: the street address goes too,
  # and so does the person (rule 5)
  person <- cbind(company, contato = "Fulana de Tal", uf = "SP")
  expect_named(
    mirror_apply_privacy(person),
    c("cnpj_companhia", "cidade", "uf")
  )

  # cad: the person in charge goes whole, the company's address stays
  cad <- data.frame(
    cnpj_cia = "11.222.333/0001-81",
    logradouro = "Rua A, 1",
    tel = "30000000",
    resp = "Fulana de Tal",
    tp_resp = "DIRETOR DE RELACOES COM INVESTIDORES",
    dt_ini_resp = as.Date("2020-01-01"),
    logradouro_resp = "Rua B, 2",
    cep_resp = "02000-000",
    mun_resp = "Sao Paulo",
    ddd_tel_resp = "11",
    email_resp = "fulana@gmail.com"
  )
  expect_named(mirror_apply_privacy(cad), c("cnpj_cia", "logradouro"))
})

test_that("a table about the company loses the person it names", {
  load_etl_privacy()
  # fca/auditor: the firm stays, its technical lead goes
  fca <- data.frame(
    cnpj_companhia = "11.222.333/0001-81",
    auditor = c("Auditores Exemplo S.S.", "Fulano de Tal"),
    cpf_cnpj_auditor = c("11.222.333/0001-81", "111.444.777-35"),
    responsavel_tecnico = c("Beltrana de Tal", NA),
    cpf_responsavel_tecnico = c("529.982.247-25", NA),
    data_inicio_atuacao_responsavel_tecnico = as.Date("2024-01-01")
  )
  expect_identical(
    mirror_privacy_counts(fca)[["natural_person_rows"]],
    1L
  )
  out <- mirror_apply_privacy(fca)
  expect_named(out, c("cnpj_companhia", "auditor", "cpf_cnpj_auditor"))
  expect_identical(out$auditor, "Auditores Exemplo S.S.")
  expect_identical(mirror_apply_privacy(out), out)
  expect_length(mirror_privacy_counts(out), 0L)

  # fre/auditor: an auditor with a CPF is a natural person
  fre <- data.frame(
    auditor = c("Auditores Exemplo S.S.", "Fulano de Tal"),
    cnpj_auditor = c("11.222.333/0001-81", NA),
    cpf_auditor = c(NA, "***.444.777-**")
  )
  out <- mirror_apply_privacy(fre)
  expect_named(out, c("auditor", "cnpj_auditor"))
  expect_identical(nrow(out), 1L)
})

test_that("the person columns match the dictionary and nothing else", {
  load_etl_privacy()
  dict <- utils::read.csv(
    system.file("extdata", "cvm_dictionary_snapshot.csv", package = "cvmdata"),
    encoding = "UTF-8"
  )
  hit <- dict[grepl(.person_cols, dict$campo), ]
  expect_setequal(
    unique(paste(hit$dataset, hit$table, sep = "/")),
    c(
      "cad/companhias",
      "cad/estrangeiras",
      "cad/incentivadas",
      "fca/auditor",
      "fca/departamento_acionistas",
      "fre/auditor",
      # out of the mirror by its schema; the columns match all the same
      "fre/auditor_responsavel"
    )
  )
  expect_true(all(.person_document_cols %in% dict$campo))
})

test_that("the tables about people are out of the mirror", {
  people <- c(
    "fre/administrador_membro_conselho_fiscal",
    "fre/membro_comite",
    "fre/relacao_familiar",
    "fre/relacao_subordinacao",
    "fre/responsavel",
    "fre/auditor_responsavel",
    "fre/posicao_acionaria",
    "fre/posicao_acionaria_classe_acao",
    "fre/transacao_parte_relacionada",
    "fca/dri"
  )
  for (key in people) {
    parts <- strsplit(key, "/", fixed = TRUE)[[1L]]
    expect_false(load_schema(parts[1L], parts[2L])$mirror, label = key)
  }
  # no table left in the mirror has a column that identifies a person
  dict <- utils::read.csv(
    system.file("extdata", "cvm_dictionary_snapshot.csv", package = "cvmdata"),
    encoding = "UTF-8"
  )
  load_etl_privacy()
  named <- "^(cpf$|cpf_|nome$|nome_administrador|nome_pessoa|nome_responsavel)"
  left <- dict[grepl(named, dict$campo) & !grepl(.person_cols, dict$campo), ]
  left <- unique(paste(left$dataset, left$table, sep = "/"))
  left <- setdiff(left, "fca/auditor")
  for (key in left) {
    parts <- strsplit(key, "/", fixed = TRUE)[[1L]]
    expect_false(load_schema(parts[1L], parts[2L])$mirror, label = key)
  }
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

group_frame <- function() {
  data.frame(
    cnpj_companhia = rep(
      c("11.111.111/0001-11", "22.222.222/0001-22", "33.333.333/0001-33"),
      each = 2L
    ),
    data_referencia = as.Date("2025-12-31"),
    versao = 1L,
    id_documento = rep(c("1", "2", "3"), each = 2L),
    posicao = rep(c("Lideranca", "Nao-lideranca"), 3L),
    # company 1: a group of 4; company 2: a unanimous group of 30;
    # company 3: both groups large and mixed, one of them only because
    # somebody did not answer
    quantidade_branco = c(3, 60, 30, 40, 12, 50),
    quantidade_pardo = c(1, 40, 0, 25, 8, 0),
    quantidade_sem_resposta = c(0, 0, 0, 5, 0, 1),
    stringsAsFactors = FALSE
  )
}

test_that("a filing with a small or unanimous group leaves a count table", {
  load_etl_privacy()
  df <- group_frame()
  attr(df, "fetched_at") <- "2026-11-14"
  expect_true(mirror_is_group_table(names(df)))
  expect_identical(
    mirror_group_unsafe(df),
    c(TRUE, TRUE, TRUE, TRUE, FALSE, FALSE)
  )
  out <- mirror_apply_privacy(df)
  expect_identical(unique(out$cnpj_companhia), "33.333.333/0001-33")
  expect_identical(nrow(out), 2L)
  expect_named(out, names(df))
  expect_identical(attr(out, "fetched_at"), "2026-11-14")
  expect_identical(mirror_apply_privacy(out), out)
  expect_length(mirror_privacy_counts(out), 0L)
  expect_identical(
    mirror_privacy_counts(df),
    c(small_or_unanimous_groups = 4L)
  )
})

test_that("the group rule reports companies and people, never rows", {
  load_etl_privacy()
  report <- mirror_group_report(group_frame())
  expect_identical(report$min, 10L)
  expect_identical(report$companies, 3L)
  expect_identical(report$companies_omitted, 2L)
  expect_identical(report$people, 275)
  expect_identical(report$people_omitted, 204)
  expect_identical(report$cnpj, c("11.111.111/0001-11", "22.222.222/0001-22"))
  expect_null(mirror_group_report(data.frame(cpf = "x")))
})

test_that("a group nobody is in, text counts and other tables are left alone", {
  load_etl_privacy()
  df <- group_frame()[5:6, ]
  df$quantidade_branco <- as.character(df$quantidade_branco)
  df <- rbind(
    df,
    transform(
      df[1L, ],
      posicao = "Outra",
      quantidade_branco = "0",
      quantidade_pardo = 0,
      quantidade_sem_resposta = NA
    )
  )
  expect_identical(mirror_group_unsafe(df), c(FALSE, FALSE, FALSE))
  ages <- data.frame(
    cnpj_companhia = "11.111.111/0001-11",
    posicao = "Lideranca",
    quantidade_ate30anos = 1
  )
  expect_false(mirror_is_group_table(names(ages)))
  expect_identical(mirror_apply_privacy(ages), ages)
})

test_that("the group rule matches the five workforce tables and no other", {
  load_etl_privacy()
  dict <- utils::read.csv(
    system.file("extdata", "cvm_dictionary_snapshot.csv", package = "cvmdata"),
    stringsAsFactors = FALSE
  )
  columns <- split(dict$campo, paste(dict$dataset, dict$table, sep = "/"))
  dir <- system.file("extdata", "schemas", "companhias", package = "cvmdata")
  for (path in list.files(
    dir,
    "[.]yaml$",
    recursive = TRUE,
    full.names = TRUE
  )) {
    schema <- yaml::read_yaml(path)
    key <- paste(schema$dataset, schema$table, sep = "/")
    if (is.null(columns[[key]]) && !is.null(schema$expected_field_names)) {
      columns[[key]] <- tolower(schema$expected_field_names)
    }
  }
  hit <- names(columns)[vapply(columns, mirror_is_group_table, logical(1L))]
  expect_setequal(
    hit,
    c(
      "fre/empregado_PCD",
      "fre/empregado_local_declaracao_genero",
      "fre/empregado_local_declaracao_raca",
      "fre/empregado_posicao_declaracao_genero",
      "fre/empregado_posicao_declaracao_raca"
    )
  )
})

# People who asked to leave (decisions of 2026-11-14). Names are invented.

test_that("the suppression list reads names and optional CPFs", {
  load_etl_privacy()
  expect_identical(nrow(mirror_suppressed("")), 0L)
  people <- mirror_suppressed(paste(
    "# a comment",
    "  Jo\u00e3o  Ant\u00f4nio Exemplo ; 111.444.777-35",
    "MARIA EXEMPLO DE TAL",
    "maria exemplo de tal",
    sep = "\n"
  ))
  expect_identical(
    people$name,
    c("JOAO ANTONIO EXEMPLO", "MARIA EXEMPLO DE TAL")
  )
  expect_identical(people$cpf, c("444777", NA))
  # a first name alone would be erased from every text: refused, unnamed
  err <- expect_error(mirror_suppressed("Maria Exemplo\nJoao"), "entry 2")
  expect_no_match(conditionMessage(err), "Joao")
})

test_that("a person who asked to leave keeps the row and loses the data", {
  load_etl_privacy()
  withr::local_envvar(
    CVMDATA_MIRROR_SUPPRESSED = "Jo\u00e3o Ant\u00f4nio Exemplo"
  )
  df <- data.frame(
    cnpj_companhia = "11.222.333/0001-81",
    orgao_administracao = c("Conselho", "Conselho", "Diretoria"),
    nome = c("JOAO ANTONIO EXEMPLO", "Maria Exemplo de Tal", "Outro Nome"),
    cpf = c("111.444.777-35", "529.982.247-25", NA),
    data_nascimento = as.Date(c("1965-03-01", "1970-01-01", NA)),
    profissao = c("Engenheiro", "Advogada", "Contador"),
    observacao = c(
      "O Sr. Jo\u00e3o  Ant\u00f4nio Exemplo foi diretor.",
      "Trabalhou com joao antonio exemplo e com Joao Antonio Exemplos.",
      "Nada a declarar."
    ),
    data_eleicao = as.Date("2024-04-30")
  )
  out <- mirror_apply_privacy(df)
  expect_identical(nrow(out), 3L)
  expect_identical(out$nome[1L], mirror_suppressed_label)
  expect_true(all(is.na(c(
    out$cpf[1L],
    out$ano_nascimento[1L],
    out$profissao[1L]
  ))))
  expect_identical(
    out$observacao[1L],
    paste0("O Sr. ", mirror_suppressed_label, " foi diretor.")
  )
  # what places the seat stays
  expect_identical(out$orgao_administracao, df$orgao_administracao)
  expect_identical(out$data_eleicao, df$data_eleicao)
  # a mention in somebody else's text becomes the label; a longer name
  # that merely starts the same is another person
  expect_identical(
    out$observacao[2L],
    paste0(
      "Trabalhou com ",
      mirror_suppressed_label,
      " e com Joao Antonio Exemplos."
    )
  )
  expect_identical(out$nome[2:3], df$nome[2:3])
  expect_identical(out$cpf[2L], "***.982.247-**")
  # idempotent, and the guard sees a frame that still names the person
  expect_identical(mirror_apply_privacy(out), out)
  expect_length(mirror_privacy_counts(out), 0L)
  expect_true("nome" %in% names(mirror_privacy_counts(df)))
})

test_that("with a CPF on the list a namesake is left alone", {
  load_etl_privacy()
  withr::local_envvar(
    CVMDATA_MIRROR_SUPPRESSED = "Maria Exemplo de Tal;111.444.777-35"
  )
  df <- data.frame(
    nome = c(
      "Maria Exemplo de Tal",
      "MARIA EXEMPLO DE TAL",
      "Maria Exemplo de Tal"
    ),
    cpf = c("***.444.777-**", "529.982.247-25", NA),
    profissao = c("Economista", "Medica", "Professora"),
    observacao = c("a", "Maria Exemplo de Tal, medica.", "c")
  )
  out <- mirror_apply_privacy(df)
  # same middle digits, and a row without a document: the person
  expect_identical(out$nome[c(1L, 3L)], rep(mirror_suppressed_label, 2L))
  # another document: somebody else, name and text untouched
  expect_identical(out$nome[2L], "MARIA EXEMPLO DE TAL")
  expect_identical(out$profissao[2L], "Medica")
  expect_identical(
    out$observacao[2L],
    "Maria Exemplo de Tal, medica."
  )
})

test_that("a shareholder who asked to leave keeps the percentages", {
  load_etl_privacy()
  withr::local_envvar(CVMDATA_MIRROR_SUPPRESSED = "Maria Exemplo de Tal")
  df <- data.frame(
    acionista = c("Maria Exemplo de Tal", "Holding Exemplo S.A."),
    cpf_cnpj_acionista = c("111.444.777-35", "11.222.333/0001-81"),
    nacionalidade = c("Brasileira", NA),
    sigla_uf = c("SP", "RJ"),
    percentual_total_acoes_circulacao = c(40, 60),
    representante_legal = c(NA, "Maria Exemplo de Tal"),
    cpf_cnpj_representante_legal = c(NA, "111.444.777-35")
  )
  out <- mirror_apply_privacy(df)
  expect_identical(
    out$acionista,
    c(mirror_suppressed_label, "Holding Exemplo S.A.")
  )
  expect_identical(out$percentual_total_acoes_circulacao, c(40, 60))
  expect_true(all(is.na(c(
    out$cpf_cnpj_acionista[1L],
    out$nacionalidade[1L],
    out$sigla_uf[1L],
    out$cpf_cnpj_representante_legal[2L]
  ))))
  expect_identical(out$representante_legal[2L], mirror_suppressed_label)
  expect_identical(out$sigla_uf[2L], "RJ")
})

test_that("every column of the person roles exists in the dictionary", {
  load_etl_privacy()
  dict <- utils::read.csv(
    system.file("extdata", "cvm_dictionary_snapshot.csv", package = "cvmdata"),
    encoding = "UTF-8"
  )
  for (nc in names(.person_roles)) {
    tables <- unique(dict[dict$campo == nc, c("dataset", "table")])
    expect_gt(nrow(tables), 0L, label = nc)
    own <- setdiff(
      unlist(.person_roles[[nc]]),
      # `data_nascimento` is `ano_nascimento` once the rule has run
      "ano_nascimento"
    )
    expect_true(all(own %in% dict$campo), label = nc)
  }
})

test_that("only util-privacy.R reads the suppression list", {
  dir <- dirname(etl_script_path("util-privacy.R"))
  for (path in list.files(dir, pattern = "[.]R$", full.names = TRUE)) {
    lines <- readLines(path, warn = FALSE)
    hits <- grep('Sys.getenv("CVMDATA_MIRROR_SUPPRESSED"', lines, fixed = TRUE)
    expect_true(
      !length(hits) || basename(path) == "util-privacy.R",
      label = basename(path)
    )
  }
})

test_that("the biography column leaves the mirror", {
  load_etl_privacy()
  df <- data.frame(
    nome = c("Fulana de Tal", "Outro Nome"),
    profissao = c("Economista", "Contador"),
    experiencia_profissional = c("Foi dirigente sindical.", NA)
  )
  expect_identical(
    mirror_privacy_counts(df),
    c(experiencia_profissional = 1L)
  )
  out <- mirror_apply_privacy(df)
  expect_named(out, c("nome", "profissao"))
  expect_identical(mirror_apply_privacy(out), out)
  expect_length(mirror_privacy_counts(out), 0L)
  # the only tables with the column are the two that describe a person
  dict <- utils::read.csv(
    system.file("extdata", "cvm_dictionary_snapshot.csv", package = "cvmdata"),
    encoding = "UTF-8"
  )
  hit <- dict[grepl(.biography_cols, dict$campo), ]
  expect_setequal(
    paste(hit$dataset, hit$table, sep = "/"),
    c("fre/administrador_membro_conselho_fiscal", "fre/membro_comite")
  )
})
