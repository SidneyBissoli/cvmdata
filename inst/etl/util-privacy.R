# ETL helper: what the mirror and the Zenodo editions do NOT redistribute
# of the personal data the CVM publishes (owner's decision of 2026-11-08,
# data-raw/decisions/cvmdata_dados_pessoais_espelho_decisao.md).
#
# The Zenodo deposit is permanent and public, so the test of necessity
# (LGPD art. 10, par. 1) is applied column by column: research needs to
# follow a person across companies and to know their age, not to hold the
# number that opens their bank account.
#   * CPF: masked the way the Federal Revenue publishes the CNPJ partners
#     (`***.456.789-**`). Measured on FRE 2021-2025: mask + name merges no
#     two different people, so joins keep working.
#   * birth date: reduced to the year (`data_nascimento` becomes
#     `ano_nascimento`, integer), because name + CPF + birth date is what
#     banks and public services use to confirm an identity.
#   * names, biographies and per-body counts stay as published: the name
#     is the content of the disclosure (Res. CVM 80, items 7.5 and 7.6).
#   * contact data (owner's decision of 2026-11-14): no e-mail, telephone
#     or fax of anybody, person or company, and no street address of a
#     person. The columns are dropped, not blanked. The field of the
#     company is not spared because small companies declare somebody's
#     own address there (measured: 296 of the 696 company e-mails of
#     `cad/incentivadas` are webmail), and telling one from the other
#     would mean guessing by domain. The address of the company stays;
#     so do the city, state and country of a person.
#   * counts of declarations (owner's decision of 2026-11-14): the five
#     workforce tables of the FRE count employees by race, gender or
#     disability, per company and position or region. Nobody is named, so
#     a count is anonymised data (LGPD art. 12) while it cannot be traced
#     back to a person; it can in a group of a few people and in a group
#     where everybody declared the same. A filing with any group under
#     `mirror_group_min` people, or with a unanimous group, leaves the
#     table whole, so no row can be rebuilt by subtraction. The references
#     read for the minimum (IBGE, UK Government Analysis Function, ONS,
#     CMS) are in the decision file.
# `source = "cvm"` still reads everything from the CVM, untouched: this
# file runs in the ETL only.
#
# `mirror_apply_privacy()` is idempotent on purpose. 03-publish.R passes
# the parquet of the previous release through it before comparing, so the
# change of rule does not look like a re-filing of every filing and no
# unmasked row reaches history; and `mirror_privacy_counts()`, the guard of
# 02b-validate.R and 06-zenodo-edition.R, is simply "would it change
# anything?".
#
# Where the CPFs are (measured 2026-11-08 on every parquet of the seven
# datasets with text):
#   * columns named `cpf*` and `documento_*`: CPF, CNPJ, a padded CPF, or a
#     foreign document (`AA999999` and the like, in `cpf`);
#   * free text (`experiencia_profissional`, `explicacao`, `assunto`, ...):
#     about 2,400 rows of biographies carry a punctuated CPF. Masking the
#     number there changes no statement the text makes.

# Version of the rule. 03-publish.R stores it in `__source_hash.json`; a
# previous sidecar with another one (or none) makes that run rewrite the
# history assets of the release.
mirror_privacy_rule <- "3"

# A punctuated CPF is a CPF even when its check digits fail (a typing
# error); any other spelling needs the check digits, or phone numbers and
# protocols would be masked (measured: the 11-digit numbers of the ITR
# `motivo_reapresentacao` have none valid).
.cpf_strict <- "^[0-9]{3}[.][0-9]{3}[.][0-9]{3}-[0-9]{2}$"
.cpf_punctuated <- paste0(
  "(?<![0-9.])",
  "[0-9]{3}[.][0-9]{3}[.][0-9]{3}-[0-9]{2}",
  "(?![0-9])"
)
.cpf_loose <- paste0(
  "(?<![0-9.,/-])",
  "[0-9]{3}[. ]?[0-9]{3}[. ]?[0-9]{3}[-/ ]?[0-9]{2}",
  "(?![0-9]|[.,/-][0-9])"
)

# Columns that hold identifiers of companies, deliveries or contacts: never
# a CPF, and an 11-digit value there can pass the check digits by chance.
.privacy_skip_cols <- paste0(
  "^(id$|id_|codigo_|cd_|protocolo|versao|link|url|",
  "cep|ddd|ddi|tel|fax|cnpj_)"
)

# Contact columns, by the tokens of the name so a column the CVM adds
# later is caught too: `email`, `tel_resp`, `ddd_telefone`, `ddi_fax`,
# `cd_pais_tel`. tests/testthat/test-etl-privacy.R pins the match against
# the dictionary snapshot.
.contact_cols <- "(^|_)(email|e_mail|tel|telefone|celular|fax)($|_)"

# Street address: of the person in charge in the `cad` (`*_resp`), and the
# plain columns of a table that names a contact person (`fca/dri`,
# `fca/departamento_acionistas`, `fre/auditor_responsavel`).
.address_cols <- "^(logradouro|compl|complemento|bairro|cep|caixa_postal)$"
.address_resp_cols <- sub("[$]$", "_resp$", .address_cols)
.person_markers <- c("responsavel", "contato", "responsavel_tecnico")

# Columns of a frame the mirror does not carry, in the order they appear.
mirror_contact_columns <- function(cols) {
  drop <- grepl(.contact_cols, cols) | grepl(.address_resp_cols, cols)
  if (any(cols %in% .person_markers)) {
    drop <- drop | grepl(.address_cols, cols)
  }
  cols[drop]
}

# Smallest group of people a count table may show.
mirror_group_min <- 10L

# A table of declaration counts: one row per filing and position or
# region, with the people who did not answer in their own column. The
# five workforce tables of the FRE and no other (the age-band tables have
# no `quantidade_sem_resposta`); the test pins this against the schemas.
mirror_is_group_table <- function(cols) {
  "quantidade_sem_resposta" %in% cols && any(c("posicao", "local") %in% cols)
}

# The counts of a group table as a numeric matrix, one column per
# `quantidade_*` column, missing as zero.
mirror_group_counts <- function(df) {
  cols <- grep("^quantidade_", names(df), value = TRUE)
  m <- vapply(
    cols,
    function(cn) suppressWarnings(as.numeric(as.character(df[[cn]]))),
    numeric(nrow(df))
  )
  m <- matrix(m, nrow = nrow(df), dimnames = list(NULL, cols))
  m[is.na(m)] <- 0
  m
}

# Rows of a group table the mirror does not carry: every row of a filing
# (company, reference date, version, document) in which some group with
# people is under the minimum or unanimous (everybody answered, and all in
# one category). FALSE everywhere for any other table.
mirror_group_unsafe <- function(df) {
  if (!mirror_is_group_table(names(df)) || !nrow(df)) {
    return(logical(nrow(df)))
  }
  m <- mirror_group_counts(df)
  size <- rowSums(m)
  silent <- m[, "quantidade_sem_resposta"]
  declared <- m[, colnames(m) != "quantidade_sem_resposta", drop = FALSE]
  top <- apply(declared, 1L, max)
  bad <- size > 0 & (size < mirror_group_min | (silent == 0 & top == size))
  keys <- intersect(
    c("cnpj_companhia", "data_referencia", "versao", "id_documento"),
    names(df)
  )
  filing <- do.call(paste, c(lapply(df[keys], as.character), sep = "\r"))
  filing %in% filing[bad]
}

# What the rule takes from a group table, for the sidecar of the release
# and the reader's warning: companies and people in the table, companies
# and people omitted, and the CNPJs omitted. NULL for any other table.
# Counts and company identifiers only.
mirror_group_report <- function(df) {
  if (!mirror_is_group_table(names(df))) {
    return(NULL)
  }
  unsafe <- mirror_group_unsafe(df)
  people <- rowSums(mirror_group_counts(df))
  cnpj <- as.character(df[["cnpj_companhia"]])
  list(
    min = mirror_group_min,
    companies = length(unique(cnpj[people > 0])),
    companies_omitted = length(unique(cnpj[unsafe])),
    people = sum(people),
    people_omitted = sum(people[unsafe]),
    cnpj = sort(unique(cnpj[unsafe]))
  )
}

mirror_digits <- function(x) gsub("[^0-9]", "", x)

# Check digits of a CPF (11 digits), vectorised over `digits`; FALSE for
# any other length and for a repeated digit (`111.111.111-11`).
mirror_cpf_valid <- function(digits) {
  vapply(
    digits,
    function(d) {
      v <- utf8ToInt(d) - 48L
      if (length(v) != 11L || length(unique(v)) == 1L) {
        return(FALSE)
      }
      a <- (sum(v[1:9] * 10:2) * 10L) %% 11L %% 10L
      b <- (sum(v[1:10] * 11:2) * 10L) %% 11L %% 10L
      a == v[10L] && b == v[11L]
    },
    logical(1L),
    USE.NAMES = FALSE
  )
}

# Check digits of a CNPJ (14 digits), vectorised over `digits`.
mirror_cnpj_valid <- function(digits) {
  w1 <- c(5:2, 9:2)
  w2 <- c(6:2, 9:2)
  vapply(
    digits,
    function(d) {
      v <- utf8ToInt(d) - 48L
      if (length(v) != 14L || length(unique(v)) == 1L) {
        return(FALSE)
      }
      r1 <- sum(v[1:12] * w1) %% 11L
      r2 <- sum(v[1:13] * w2) %% 11L
      (if (r1 < 2L) 0L else 11L - r1) == v[13L] &&
        (if (r2 < 2L) 0L else 11L - r2) == v[14L]
    },
    logical(1L),
    USE.NAMES = FALSE
  )
}

# `***.456.789-**` from the 11 digits.
mirror_cpf_mask <- function(digits) {
  paste0(
    "***.",
    substr(digits, 4L, 6L),
    ".",
    substr(digits, 7L, 9L),
    "-**"
  )
}

# A column that holds a document. CNPJs stay (a company is not a person);
# 11 digits are a CPF whatever their check digits; 14 digits that fail as a
# CNPJ and pass as a zero-padded CPF are that CPF; any other value with a
# digit is a foreign document and becomes `***`. Values already masked and
# values without digits ("Nao se aplica") stay.
mirror_mask_document <- function(x) {
  out <- x
  todo <- which(!is.na(x) & !startsWith(x, "***"))
  if (!length(todo)) {
    return(out)
  }
  d <- mirror_digits(x[todo])
  n <- nchar(d)
  cpf <- n == 11L
  padded <- n == 14L & startsWith(d, "000")
  padded[padded] <- !mirror_cnpj_valid(d[padded]) &
    mirror_cpf_valid(substr(d[padded], 4L, 14L))
  out[todo[cpf]] <- mirror_cpf_mask(d[cpf])
  out[todo[padded]] <- mirror_cpf_mask(substr(d[padded], 4L, 14L))
  other <- n > 0L & n != 11L & n != 14L
  out[todo[other]] <- "***"
  out
}

# Free text: every punctuated CPF, and any other spelling that passes the
# check digits, keeping the rest of the text as published.
mirror_mask_text <- function(x) {
  re <- paste(.cpf_punctuated, .cpf_loose, sep = "|")
  hit <- which(!is.na(x) & grepl(re, x, perl = TRUE))
  if (!length(hit)) {
    return(x)
  }
  texts <- x[hit]
  matches <- gregexpr(re, texts, perl = TRUE)
  regmatches(texts, matches) <- lapply(
    regmatches(texts, matches),
    function(found) {
      d <- mirror_digits(found)
      mask <- grepl(.cpf_strict, found) | mirror_cpf_valid(d)
      found[mask] <- mirror_cpf_mask(d[mask])
      found
    }
  )
  x[hit] <- texts
  x
}

mirror_birth_year <- function(x) {
  if (inherits(x, "Date")) {
    return(as.integer(format(x, "%Y")))
  }
  as.integer(substr(as.character(x), 1L, 4L))
}

mirror_is_document_col <- function(name) {
  grepl("^(cpf|documento_)", name)
}

# The data frame the mirror may publish: the rules above applied to the
# columns, then the filings a group table may not show taken out. Same
# column order; the attributes of the frame survive both steps.
mirror_apply_privacy <- function(df) {
  df <- mirror_mask_columns(df)
  unsafe <- mirror_group_unsafe(df)
  if (!any(unsafe)) {
    return(df)
  }
  kept <- df[!unsafe, , drop = FALSE]
  own <- setdiff(names(attributes(df)), c("names", "row.names", "class"))
  for (a in own) {
    attr(kept, a) <- attr(df, a, exact = TRUE)
  }
  kept
}

# The column rules: same rows, same column order. Only the columns that
# change are assigned, so the attributes of the frame survive.
mirror_mask_columns <- function(df) {
  for (cn in mirror_contact_columns(names(df))) {
    df[[cn]] <- NULL
  }
  for (cn in names(df)) {
    x <- df[[cn]]
    if (!is.character(x)) {
      next
    }
    masked <- if (mirror_is_document_col(cn)) {
      mirror_mask_document(x)
    } else if (grepl(.privacy_skip_cols, cn)) {
      x
    } else {
      mirror_mask_text(x)
    }
    if (!identical(masked, x)) {
      df[[cn]] <- masked
    }
  }
  if ("data_nascimento" %in% names(df)) {
    df[["data_nascimento"]] <- mirror_birth_year(df[["data_nascimento"]])
    names(df)[names(df) == "data_nascimento"] <- "ano_nascimento"
  }
  df
}

# How many values of each column `mirror_apply_privacy()` would change, as
# a named integer holding only the columns with something to change: empty
# means the frame may be published. Counts and column names only, so a
# failure can be logged without printing anybody's data. A contact column
# is listed whenever it is present, with its filled values as the count:
# zero there still means "this column must go". The rows of a group table
# that must go are counted under `small_or_unanimous_groups`.
mirror_privacy_counts <- function(df) {
  safe <- mirror_mask_columns(df)
  out <- integer()
  unsafe <- sum(mirror_group_unsafe(df))
  if (unsafe) {
    out[["small_or_unanimous_groups"]] <- unsafe
  }
  for (cn in mirror_contact_columns(names(df))) {
    out[[cn]] <- sum(!is.na(df[[cn]]))
  }
  for (cn in intersect(names(df), names(safe))) {
    a <- df[[cn]]
    b <- safe[[cn]]
    if (is.character(a) && !identical(a, b)) {
      out[[cn]] <- sum(a != b, na.rm = TRUE)
    }
  }
  if ("data_nascimento" %in% names(df)) {
    out[["data_nascimento"]] <- sum(!is.na(df[["data_nascimento"]]))
  }
  out
}
