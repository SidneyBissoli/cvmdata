# a read of a count table warns with the numbers and keeps them

    Code
      out <- note_privacy_omitted(omitted_result(), omitted_rows())
    Condition
      Warning:
      The mirror leaves companies out of "fre"/"empregado_PCD" to protect personal data.
      * 2025: 173 of 459 companies (37.7%), with 5.0% of the people counted.
      i A company is left out in a year in which one of its groups has fewer than 10 people, or everybody in a group declared the same category: such a count tells the declaration of a person, which is sensitive data under the LGPD.
      i `source = "cvm"` reads every company. The numbers stay in `attr(x, "omitted")`.

# asking for a company names it when it was left out

    Code
      out <- note_privacy_omitted(omitted_result(), omitted_rows(), cnpj = c(
        "11222333000181", "33.444.555/0001-81"))
    Condition
      Warning:
      The mirror leaves companies out of "fre"/"empregado_PCD" to protect personal data.
      * 2025: asked for and left out: 11.222.333/0001-81.
      i A company is left out in a year in which one of its groups has fewer than 10 people, or everybody in a group declared the same category: such a count tells the declaration of a person, which is sensitive data under the LGPD.
      i `source = "cvm"` reads every company. The numbers stay in `attr(x, "omitted")`.

# the header says it and the attribute survives dplyr

    Code
      print(out)
    Message
      i source: "cvm" | fetched_at: 2026-11-14 12:00:00
      i group: "companhias" | dataset: "fre" | table: "empregado_PCD"
      ! omitted: 173 of 459 companies of 2025 are not in the mirror (privacy rule; `attr(x, "omitted")`)
    Output
      # A tibble: 1 x 2
        cnpj_companhia     quantidade_pcd
        <chr>                       <dbl>
      1 33.444.555/0001-81             12

