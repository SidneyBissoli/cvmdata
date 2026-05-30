# Hierarchical condition classes used across the package.
#
# Errors inherit from "cvmdata_error" (parent for `tryCatch()` capture);
# warnings inherit from "cvmdata_warn". The hierarchy is documented in
# the naming doc v03 §6.1 with the refinement from Rodada 3.0.2.
#
# Known subclasses of "cvmdata_error_input" (siblings of one another):
#   * cvmdata_error_input_ambiguous (S05) — (dataset, table) resolves
#     to more than one group when the caller did not disambiguate.
#   * cvmdata_error_input_group     (S07) — caller invoked a skeleton
#     fetcher whose group is not yet implemented in this release.
#
# Subclass of "cvmdata_error_parse":
#   * cvmdata_error_zip_member_missing — the requested detail table's
#     CSV is not inside the dataset's yearly ZIP (the table did not
#     exist that year). Lets consumers (the ETL mirror) distinguish a
#     benign "table absent that year" from other parse failures by class.
#
# These subclasses are emergent: they exist by virtue of being passed
# through `cvmdata_abort(class = ...)` and never need a constructor of
# their own. `cvmdata_abort()` appends the "cvmdata_error" parent
# automatically; callers stack the more specific classes ahead of it.

# Wrap `cli::cli_abort()` so that the parent class "cvmdata_error" is
# always appended. Callers pass the specific subclass via `class`.
cvmdata_abort <- function(message,
                          class = NULL,
                          ...,
                          call = rlang::caller_env(),
                          .envir = parent.frame()) {
  classes <- unique(c(class, "cvmdata_error"))
  cli::cli_abort(
    message,
    class = classes,
    call = call,
    ...,
    .envir = .envir
  )
}

# Wrap `cli::cli_warn()` analogously. Parent class is "cvmdata_warn".
cvmdata_warn <- function(message,
                         class = NULL,
                         ...,
                         .envir = parent.frame()) {
  classes <- unique(c(class, "cvmdata_warn"))
  cli::cli_warn(
    message,
    class = classes,
    ...,
    .envir = .envir
  )
}
