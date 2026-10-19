# identical rows of a doubled filing are dropped with a warning

    Code
      out <- cvmdata:::drop_duplicate_filings(trv_bpa(), "cnpj_cia", "dt_refer")
    Condition
      Warning:
      The CVM file repeats rows for 1 filing; the identical copies were dropped.
      * TRV XLIII SECURITIZADORA DE CREDITOS MERCANTIS S.A. (2023-12-31)
      i A statement has one row per account and period, so sums over the raw file count these twice. See <https://sidneybissoli.github.io/cvmdata/articles/data-defects.html>.

# a table behind the latest delivery is flagged

    Code
      out <- cvmdata:::check_filings(travessia_bpa_v2(), schema = list(), dataset = "dfp",
      table = "bpa", year = 2024L, source = "cvm", validate = "strict")
    Condition
      Warning:
      1 filing in "dfp"/"bpa" is not the latest delivery in the CVM filing index.
      * TRAVESSIA SECURITIZADORA DE CRÉDITOS MERCANTIS VI S.A. (2024-12-31)
      i The CVM file kept an earlier filing; the issuer delivered a later one under a lower versao. Its numbers are not in the CVM file. See <https://sidneybissoli.github.io/cvmdata/articles/data-defects.html>.

