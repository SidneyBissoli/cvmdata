# cvm_fetch refuses a year the table has no content for

    Code
      cvm_fetch("fca", "departamento_acionistas", year = 2025, source = "cvm")
    Condition
      Error in `check_empty_from()`:
      ! Table "fca"/"departamento_acionistas" is published without content from 2024 on.
      x Requested: 2025.
      i Why: item 6 of the Formulario Cadastral (shareholders department) was revoked by Resolucao CVM 59/2021, in force since 2023-01-02.
      i The last year with content is 2023.

# cvm_fetch refuses year = NULL on a table that ended

    Code
      cvm_fetch("fre", "endividamento", source = "mirror")
    Condition
      Error in `check_ended_latest()`:
      ! Table "fre"/"endividamento" is no longer published: the CVM's files stopped carrying it after 2023.
      i Pass `year` explicitly, e.g. `year = 2023`; it is published for 2010-2023.

# warn_empty_latest says what each backend returns

    Code
      cvmdata:::warn_empty_latest(latest, schema, "mirror")
    Condition
      Warning:
      `year = NULL`: table "fca"/"departamento_acionistas" is published without content from 2024 on.
      i Why: item 6 of the Formulario Cadastral (shareholders department) was revoked by Resolucao CVM 59/2021, in force since 2023-01-02.
      i Returning 2023, the last year with content.
    Code
      cvmdata:::warn_empty_latest(latest, schema, "cvm")
    Condition
      Warning:
      `year = NULL`: table "fca"/"departamento_acionistas" is published without content from 2024 on.
      i Why: item 6 of the Formulario Cadastral (shareholders department) was revoked by Resolucao CVM 59/2021, in force since 2023-01-02.
      i The CVM's latest file has no rows; pass `year = 2023` for the last year with content.

