# Methods that keep the `cvm_tbl` class and its six provenance
# attributes alive across dplyr verbs and vctrs operations.
#
# Background (measured 2026-10-25, dplyr 1.2.1 / vctrs 0.7.3 / tibble
# 3.3.1): `dplyr_reconstruct.data.frame()` copies every attribute of the
# template, so `filter()`, `mutate()`, `select()`, `arrange()`, `slice()`,
# `[` and friends already preserved the provenance. Three paths lost it
# silently: `group_by()` (which rebuilds the class vector), the verbs
# that follow it (`summarise()`, `mutate()`, `ungroup()`), and
# `bind_rows()`/`vec_rbind()` between two `cvm_tbl` objects (no common
# type, so vctrs fell back to a plain tibble). The methods below follow
# the sf/tsibble pattern: a `dplyr_reconstruct()` method,
# `group_by()`/`ungroup()`/`summarise()` methods that put the class
# back, and vctrs double-dispatch methods that reconcile divergent
# provenance into "mixed" for `vec_rbind()` and `rbind()`. `bind_rows()`
# cannot be made to reconcile: dplyr strips the bound data to a bare
# data frame before `dplyr_reconstruct()` sees it and stamps the first
# input's attributes, as it does for every data frame subclass (sf
# behaves the same way with the CRS).

cvm_tbl_attr_names <- c(
  "source",
  "fetched_at",
  "group",
  "dataset",
  "table",
  "package_version"
)

# Read the six provenance attributes of `x` as a named list (absent
# attributes come back as NULL entries).
#
# @noRd
cvm_tbl_attrs <- function(x) {
  out <- lapply(cvm_tbl_attr_names, function(a) attr(x, a, exact = TRUE))
  names(out) <- cvm_tbl_attr_names
  out
}

# Put the `cvm_tbl` class in front of `out`'s class vector and copy the
# six provenance attributes from `attrs` (a list as returned by
# `cvm_tbl_attrs()`). `out` keeps whatever else it is (grouped_df,
# tbl_df).
#
# @noRd
cvm_tbl_reattach <- function(out, attrs) {
  for (a in cvm_tbl_attr_names) {
    attr(out, a) <- attrs[[a]]
  }
  class(out) <- union("cvm_tbl", class(out))
  out
}

# Reconcile the provenance of two `cvm_tbl` objects about to be
# combined row-wise. Equal values survive; a character attribute that
# differs becomes "mixed"; `fetched_at` keeps the OLDEST timestamp, the
# conservative statement of freshness for the combined rows.
#
# @noRd
cvm_tbl_merge_attrs <- function(x, y) {
  ax <- cvm_tbl_attrs(x)
  ay <- cvm_tbl_attrs(y)
  out <- ax
  for (a in setdiff(cvm_tbl_attr_names, "fetched_at")) {
    if (!identical(ax[[a]], ay[[a]])) {
      out[[a]] <- "mixed"
    }
  }
  stamps <- c(ax$fetched_at, ay$fetched_at)
  out$fetched_at <- if (length(stamps) > 0) min(stamps) else NULL
  out
}

#' Provenance-carrying tibbles
#'
#' @description
#' Every tibble returned by [cvm_fetch()], [cvm_versions()] and the
#' other public fetchers has the S3 class `cvm_tbl`, a subclass of
#' [tibble::tibble()], and carries six provenance attributes:
#' `source` (`"mirror"`, `"portal"` or `"cache"`), `fetched_at`
#' (a `POSIXct` timestamp), `group`, `dataset`, `table` and
#' `package_version`. [print()] shows them above the tibble; read one
#' with `attr(x, "source")`.
#'
#' The class and the attributes travel with the data through these
#' operations:
#'
#' * dplyr verbs on one table: `filter()`, `mutate()`, `select()`,
#'   `arrange()`, `slice()`, `rename()`, `distinct()`, `relocate()`,
#'   `count()`, `group_by()`, `ungroup()` and `summarise()` (the
#'   summary of a CVM table keeps the provenance of that table).
#' * Base subsetting: `x[i, ]`, `x[, j]`, `x[j]`, `x$col <- value`,
#'   `head()`, `tail()`, `subset()`, `unique()`.
#' * Joins where the `cvm_tbl` is the first argument (`left_join(x, y)`
#'   and friends): the result keeps the provenance of `x`, the table
#'   whose rows it describes.
#' * `rbind()` and `vctrs::vec_rbind()` of two or more `cvm_tbl`
#'   objects. Attributes equal in every input survive; a `source`,
#'   `group`, `dataset`, `table` or `package_version` that differs
#'   between inputs becomes `"mixed"`, and `fetched_at` keeps the
#'   oldest timestamp, so the combined tibble never claims a single
#'   origin it does not have.
#' * `dplyr::bind_rows()` of two or more `cvm_tbl` objects keeps the
#'   class but, by dplyr's rule for every data frame subclass, stamps
#'   the provenance of the **first** input on the result, even when the
#'   other inputs came from another source or table. Use `rbind()` or
#'   `vctrs::vec_rbind()` when the inputs may differ.
#'
#' They are dropped, by design, when the result is no longer a CVM
#' table: `pull()`, `x[[j]]` and `x$col` return vectors;
#' `bind_rows()` or a join whose first argument is a plain tibble, and
#' `rbind()` or `vctrs::vec_rbind()` with a plain tibble among the
#' inputs, return a plain tibble; `bind_rows()` of a `cvm_tbl` and a plain
#' tibble follows dplyr's rule and keeps the first input's class, so
#' the provenance then describes only the rows that came from the
#' `cvm_tbl`; `tidyr::pivot_longer()`, `tidyr::pivot_wider()`,
#' `rowwise()`, `tibble::as_tibble()` and `as.data.frame()` return
#' the type they promise.
#'
#' @name cvm_tbl
#' @family utilities
#' @seealso [cvm_fetch()] for the fetcher that creates these tibbles.
#' @examples
#' x <- readRDS(system.file(
#'   "extdata", "vignette-data", "cad_companhias_sample.rds",
#'   package = "cvmdata"
#' ))
#' attr(x, "dataset")
#' if (requireNamespace("dplyr", quietly = TRUE)) {
#'   y <- dplyr::filter(x, sit == "ATIVO")
#'   attr(y, "dataset")
#'   z <- dplyr::count(dplyr::group_by(x, sit))
#'   class(z)
#' }
NULL

#' @exportS3Method dplyr::dplyr_reconstruct
dplyr_reconstruct.cvm_tbl <- function(data, template) {
  # `dplyr_reconstruct()` strips `data` to a bare data frame before
  # dispatching, so the only provenance available here is the
  # template's. This is why `bind_rows()` keeps the first input's
  # provenance (dplyr's rule) while `vec_rbind()` reconciles.
  attrs <- cvm_tbl_attrs(template)
  out <- NextMethod()
  cvm_tbl_reattach(out, attrs)
}

# dplyr's grouped_df methods for row slicing, column modification, `[`
# and `names<-` rebuild the result with `new_grouped_df()` and never
# call `dplyr_reconstruct()`, so the class in front of `grouped_df` and
# the attributes would be lost after `group_by()`. The methods below
# dispatch first (the `cvm_tbl` class comes first) and put them back.

#' @exportS3Method dplyr::dplyr_row_slice
dplyr_row_slice.cvm_tbl <- function(data, i, ...) {
  attrs <- cvm_tbl_attrs(data)
  out <- NextMethod()
  cvm_tbl_reattach(out, attrs)
}

#' @exportS3Method dplyr::dplyr_col_modify
dplyr_col_modify.cvm_tbl <- function(data, cols) {
  attrs <- cvm_tbl_attrs(data)
  out <- NextMethod()
  cvm_tbl_reattach(out, attrs)
}

#' @export
`[.cvm_tbl` <- function(x, i, j, drop = FALSE, ...) {
  attrs <- cvm_tbl_attrs(x)
  out <- NextMethod()
  if (!is.data.frame(out)) {
    return(out)
  }
  cvm_tbl_reattach(out, attrs)
}

#' @export
`names<-.cvm_tbl` <- function(x, value) {
  attrs <- cvm_tbl_attrs(x)
  out <- NextMethod()
  cvm_tbl_reattach(out, attrs)
}

#' @exportS3Method dplyr::group_by
group_by.cvm_tbl <- function(.data, ...) {
  attrs <- cvm_tbl_attrs(.data)
  out <- NextMethod()
  cvm_tbl_reattach(out, attrs)
}

#' @exportS3Method dplyr::ungroup
ungroup.cvm_tbl <- function(x, ...) {
  attrs <- cvm_tbl_attrs(x)
  out <- NextMethod()
  cvm_tbl_reattach(out, attrs)
}

#' @exportS3Method dplyr::summarise
summarise.cvm_tbl <- function(.data, ...) {
  # `.by` and `.groups` stay in `...`: naming them here would wrap the
  # quoted `.by` in a second promise that dplyr's data-masking cannot
  # see through after `NextMethod()`.
  attrs <- cvm_tbl_attrs(.data)
  out <- NextMethod()
  cvm_tbl_reattach(out, attrs)
}

# Base `rbind()` of several `cvm_tbl`s goes through vctrs so the
# provenance is reconciled instead of copied from the first input; with
# a plain tibble among the inputs the common type is a plain tibble.

#' @export
# nolint start: object_name_linter. `deparse.level` is the generic's formal.
rbind.cvm_tbl <- function(..., deparse.level = 1) {
  vctrs::vec_rbind(...)
}
# nolint end

# vctrs double dispatch. Two `cvm_tbl`s have a common type: a `cvm_tbl`
# with reconciled provenance. A `cvm_tbl` and a plain tibble or data
# frame have a plain tibble as common type (the provenance of part of
# the rows is unknown). Casting to a `cvm_tbl` stamps the target's
# provenance; casting away from it drops class and attributes.

#' @exportS3Method vctrs::vec_ptype2
vec_ptype2.cvm_tbl.cvm_tbl <- function(x, y, ...) {
  out <- vctrs::tib_ptype2(x, y, ...)
  cvm_tbl_reattach(out, cvm_tbl_merge_attrs(x, y))
}

#' @exportS3Method vctrs::vec_ptype2
vec_ptype2.cvm_tbl.tbl_df <- function(x, y, ...) {
  vctrs::tib_ptype2(x, y, ...)
}

#' @exportS3Method vctrs::vec_ptype2
vec_ptype2.tbl_df.cvm_tbl <- function(x, y, ...) {
  vctrs::tib_ptype2(x, y, ...)
}

#' @exportS3Method vctrs::vec_ptype2
vec_ptype2.cvm_tbl.data.frame <- function(x, y, ...) {
  vctrs::tib_ptype2(x, y, ...)
}

#' @exportS3Method vctrs::vec_ptype2
vec_ptype2.data.frame.cvm_tbl <- function(x, y, ...) {
  vctrs::tib_ptype2(x, y, ...)
}

#' @exportS3Method vctrs::vec_cast
vec_cast.cvm_tbl.cvm_tbl <- function(x, to, ...) {
  out <- vctrs::tib_cast(x, to, ...)
  cvm_tbl_reattach(out, cvm_tbl_attrs(to))
}

#' @exportS3Method vctrs::vec_cast
vec_cast.cvm_tbl.tbl_df <- function(x, to, ...) {
  out <- vctrs::tib_cast(x, to, ...)
  cvm_tbl_reattach(out, cvm_tbl_attrs(to))
}

#' @exportS3Method vctrs::vec_cast
vec_cast.cvm_tbl.data.frame <- function(x, to, ...) {
  out <- vctrs::tib_cast(x, to, ...)
  cvm_tbl_reattach(out, cvm_tbl_attrs(to))
}

#' @exportS3Method vctrs::vec_cast
vec_cast.tbl_df.cvm_tbl <- function(x, to, ...) {
  vctrs::tib_cast(x, to, ...)
}

#' @exportS3Method vctrs::vec_cast
vec_cast.data.frame.cvm_tbl <- function(x, to, ...) {
  vctrs::df_cast(x, to, ...)
}
