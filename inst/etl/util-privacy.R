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
mirror_privacy_rule <- "1"

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

# The data frame the mirror may publish: same rows, same column order, with
# the rules above applied. Only the columns that change are assigned, so
# the attributes of the frame survive.
mirror_apply_privacy <- function(df) {
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
# failure can be logged without printing anybody's data.
mirror_privacy_counts <- function(df) {
  safe <- mirror_apply_privacy(df)
  out <- integer()
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
