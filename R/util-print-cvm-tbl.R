# Custom print method for the `cvm_tbl` S3 class. Displays provenance
# attributes ahead of the tibble itself, then delegates to the standard
# tibble print method via `NextMethod()`.

#' @export
print.cvm_tbl <- function(x, ...) {
  src <- attr(x, "source", exact = TRUE)
  fetched <- attr(x, "fetched_at", exact = TRUE)
  grp <- attr(x, "group", exact = TRUE)
  ds <- attr(x, "dataset", exact = TRUE)
  tbl <- attr(x, "table", exact = TRUE)
  cli::cli_inform(c(
    "i" = paste0(
      "{.field source}: {.val {src}}  |  ",
      "{.field fetched_at}: {.val {fetched}}"
    ),
    "i" = paste0(
      "{.field group}: {.val {grp}}  |  ",
      "{.field dataset}: {.val {ds}}  |  ",
      "{.field table}: {.val {tbl}}"
    )
  ))
  NextMethod()
}
