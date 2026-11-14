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
    NextMethod()
    return(invisible(x))
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
    ),
    print_omitted_field(attr(x, "omitted", exact = TRUE))
  ))
  NextMethod()
  invisible(x)
}

# The header line of a count table the mirror left companies out of, or
# nothing: the warning of the read is gone by the time the object is
# printed again.
print_omitted_field <- function(omitted) {
  if (is.null(omitted)) {
    return(NULL)
  }
  rows <- omitted[which(omitted$companies_omitted > 0), , drop = FALSE]
  if (!nrow(rows)) {
    return(NULL)
  }
  # the latest year says it; the attribute has the others
  last <- rows[nrow(rows), , drop = FALSE]
  others <- if (nrow(rows) > 1L) {
    sprintf(", and in %d other year(s)", nrow(rows) - 1L)
  } else {
    ""
  }
  c(
    "!" = paste0(
      "{.field omitted}: ",
      format(last$companies_omitted, big.mark = ",", trim = TRUE),
      " of ",
      format(last$companies, big.mark = ",", trim = TRUE),
      " companies of ",
      last$year,
      " are not in the mirror",
      others,
      " (privacy rule; {.code attr(x, \"omitted\")})"
    )
  )
}
