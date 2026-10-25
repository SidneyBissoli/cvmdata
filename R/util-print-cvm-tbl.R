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
  if (
    is.null(src) &&
      is.null(fetched) &&
      is.null(grp) &&
      is.null(ds) &&
      is.null(tbl)
  ) {
    # Provenance stripped by the caller: print as a plain tibble rather
    # than a header of empty fields.
    return(NextMethod())
  }
  release <- attr(x, "release", exact = TRUE)
  # The release is shown only when it says something: the mirror tag the
  # rows came from. `source = "cvm"` has none (NA).
  release_field <- if (!is.null(release) && !is.na(release)) {
    "  |  {.field release}: {.val {release}}"
  } else {
    ""
  }
  cli::cli_inform(c(
    "i" = paste0(
      "{.field source}: {.val {src}}",
      release_field,
      "  |  {.field fetched_at}: {.val {fetched}}"
    ),
    "i" = paste0(
      "{.field group}: {.val {grp}}  |  ",
      "{.field dataset}: {.val {ds}}  |  ",
      "{.field table}: {.val {tbl}}"
    )
  ))
  NextMethod()
}
