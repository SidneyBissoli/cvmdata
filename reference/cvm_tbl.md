# Provenance-carrying tibbles

Every tibble returned by
[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md),
[`cvm_versions()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_versions.md)
and the other public fetchers has the S3 class `cvm_tbl`, a subclass of
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html),
and carries six provenance attributes: `source` (`"mirror"`, `"portal"`
or `"cache"`), `fetched_at` (a `POSIXct` timestamp), `group`, `dataset`,
`table` and `package_version`.
[`print()`](https://rdrr.io/r/base/print.html) shows them above the
tibble; read one with `attr(x, "source")`.

The class and the attributes travel with the data through these
operations:

- dplyr verbs on one table:
  [`filter()`](https://rdrr.io/r/stats/filter.html), `mutate()`,
  `select()`, `arrange()`, `slice()`, `rename()`, `distinct()`,
  `relocate()`, `count()`, `group_by()`, `ungroup()` and `summarise()`
  (the summary of a CVM table keeps the provenance of that table).

- Base subsetting: `x[i, ]`, `x[, j]`, `x[j]`, `x$col <- value`,
  [`head()`](https://rdrr.io/r/utils/head.html),
  [`tail()`](https://rdrr.io/r/utils/head.html),
  [`subset()`](https://rdrr.io/r/base/subset.html),
  [`unique()`](https://rdrr.io/r/base/unique.html).

- Joins where the `cvm_tbl` is the first argument (`left_join(x, y)` and
  friends): the result keeps the provenance of `x`, the table whose rows
  it describes.

- [`rbind()`](https://rdrr.io/r/base/cbind.html) and
  [`vctrs::vec_rbind()`](https://vctrs.r-lib.org/reference/vec_bind.html)
  of two or more `cvm_tbl` objects. Attributes equal in every input
  survive; a `source`, `group`, `dataset`, `table` or `package_version`
  that differs between inputs becomes `"mixed"`, and `fetched_at` keeps
  the oldest timestamp, so the combined tibble never claims a single
  origin it does not have.

- [`dplyr::bind_rows()`](https://dplyr.tidyverse.org/reference/bind_rows.html)
  of two or more `cvm_tbl` objects keeps the class but, by dplyr's rule
  for every data frame subclass, stamps the provenance of the **first**
  input on the result, even when the other inputs came from another
  source or table. Use [`rbind()`](https://rdrr.io/r/base/cbind.html) or
  [`vctrs::vec_rbind()`](https://vctrs.r-lib.org/reference/vec_bind.html)
  when the inputs may differ.

They are dropped, by design, when the result is no longer a CVM table:
`pull()`, `x[[j]]` and `x$col` return vectors; `bind_rows()` or a join
whose first argument is a plain tibble, and
[`rbind()`](https://rdrr.io/r/base/cbind.html) or
[`vctrs::vec_rbind()`](https://vctrs.r-lib.org/reference/vec_bind.html)
with a plain tibble among the inputs, return a plain tibble;
`bind_rows()` of a `cvm_tbl` and a plain tibble follows dplyr's rule and
keeps the first input's class, so the provenance then describes only the
rows that came from the `cvm_tbl`;
[`tidyr::pivot_longer()`](https://tidyr.tidyverse.org/reference/pivot_longer.html),
[`tidyr::pivot_wider()`](https://tidyr.tidyverse.org/reference/pivot_wider.html),
`rowwise()`,
[`tibble::as_tibble()`](https://tibble.tidyverse.org/reference/as_tibble.html)
and [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html)
return the type they promise.

## See also

[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
for the fetcher that creates these tibbles.

Other utilities:
[`cnpj_clean()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_clean.md),
[`cnpj_format()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_format.md)

## Examples

``` r
x <- readRDS(system.file(
  "extdata", "vignette-data", "cad_companhias_sample.rds",
  package = "cvmdata"
))
attr(x, "dataset")
#> [1] "cad"
if (requireNamespace("dplyr", quietly = TRUE)) {
  y <- dplyr::filter(x, sit == "ATIVO")
  attr(y, "dataset")
  z <- dplyr::count(dplyr::group_by(x, sit))
  class(z)
}
#> [1] "cvm_tbl"    "grouped_df" "tbl_df"     "tbl"        "data.frame"
```
